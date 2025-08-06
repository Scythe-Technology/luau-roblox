--!strict
--!native
--!optimize 2
if (type(_VERSION) == "string") then
    if (string.sub(_VERSION, 1, 4) == "zune") then
        return zune.serde.lz4
    end
end

-- metatablecat 2022: https://gist.github.com/metatablecat/92345df2fd6d450da288c28272555faf
-- modified by Sythivo

local Stream = require("../dom/binary/stream");

local lz4 = {}

type Streamer = {
    Offset: number,
    Source: string,
    Length: number,
    IsFinished: boolean,
    LastUnreadBytes: number,

    read: (Streamer, len: number?, shiftOffset: boolean?) -> string,
    seek: (Streamer, len: number) -> (),
    append: (Streamer, newData: string) -> (),
    toEnd: (Streamer) -> ()
}

type BlockData = {
    [number]: {
        Literal: string,
        LiteralLength: number,
        MatchOffset: number?,
        MatchLength: number?
    }
}

local function plainFind(str, pat)
    return string.find(str, pat, 0, true)
end

local function streamer(str): Streamer
    local Stream = {}
    Stream.Offset = 0
    Stream.Source = str
    Stream.Length = string.len(str)
    Stream.IsFinished = false
    Stream.LastUnreadBytes = 0

    function Stream.read(self: Streamer, len: number?, shift: boolean?): string
        local len = len or 1
        local shift = if shift ~= nil then shift else true
        local dat = string.sub(self.Source, self.Offset + 1, self.Offset + len)

        local dataLength = string.len(dat)
        local unreadBytes = len - dataLength

        if shift then
            self:seek(len)
        end

        self.LastUnreadBytes = unreadBytes
        return dat
    end

    function Stream.seek(self: Streamer, len: number)
        local len = len or 1

        self.Offset = math.clamp(self.Offset + len, 0, self.Length)
        self.IsFinished = self.Offset >= self.Length
    end

    function Stream.append(self: Streamer, newData: string)
        -- adds new data to the end of a stream
        self.Source ..= newData
        self.Length = string.len(self.Source)
        self:seek(0) --hacky but forces a recalculation of the isFinished flag
    end

    function Stream.toEnd(self: Streamer)
        self:seek(self.Length)
    end

    return Stream
end

function lz4.compress(str: string): string
    local blocks: BlockData = {}
    local iostream = streamer(str)

    if iostream.Length > 12 then
        local firstFour = iostream:read(4)

        local processed = firstFour
        local lit = firstFour
        local match = ""
        local LiteralPushValue = ""
        local pushToLiteral = true

        repeat
            pushToLiteral = true
            local nextByte = iostream:read()

            if plainFind(processed, nextByte) then
                local next3 = iostream:read(3, false)

                if string.len(next3) < 3 then
                    --push bytes to literal block then break
                    LiteralPushValue = nextByte .. next3
                    iostream:seek(3)
                else
                    match = nextByte .. next3

                    local matchPos = plainFind(processed, match)
                    if matchPos then
                        iostream:seek(3)
                        repeat
                            local nextMatchByte = iostream:read(1, false)
                            local newResult = match .. nextMatchByte

                            local repos = plainFind(processed, newResult)
                            if repos then
                                match = newResult
                                matchPos = repos
                                iostream:seek(1)
                            end
                        until not plainFind(processed, newResult) or iostream.IsFinished

                        local matchLen = string.len(match)
                        local pushMatch = true

                        if iostream.Length - iostream.Offset <= 5 then
                            LiteralPushValue = match
                            pushMatch = false
                            --better safe here, dont bother pushing to match ever
                        end

                        if pushMatch then
                            pushToLiteral = false

                            -- gets the position from the end of processed, then slaps it onto processed
                            local realPosition = string.len(processed) - matchPos
                            processed = processed .. match

                            table.insert(blocks, {
                                Literal = lit,
                                LiteralLength = string.len(lit),
                                MatchOffset = realPosition + 1,
                                MatchLength = matchLen,
                            })
                            lit = ""
                        end
                    else
                        LiteralPushValue = nextByte
                    end
                end
            else
                LiteralPushValue = nextByte
            end

            if pushToLiteral then
                lit = lit .. LiteralPushValue
                processed = processed .. nextByte
            end
        until iostream.IsFinished
        table.insert(blocks, {
            Literal = lit,
            LiteralLength = string.len(lit)
        })
    else
        local str = iostream.Source
        blocks[1] = {
            Literal = str,
            LiteralLength = string.len(str)
        }
    end

    -- generate the output chunk
    -- %s is for adding header
    local output = "";
    local function write(char)
        output = output .. char
    end
    -- begin working through chunks
    for chunkNum, chunk in blocks do
        local litLen = chunk.LiteralLength
        local matLen = (chunk.MatchLength or 4) - 4

        -- create token
        local tokenLit = math.clamp(litLen, 0, 15)
        local tokenMat = math.clamp(matLen, 0, 15)

        local token = bit32.lshift(tokenLit, 4) + tokenMat
        write(string.pack("<I1", token))

        if litLen >= 15 then
            litLen = litLen - 15
            --begin packing extra bytes
            repeat
                local nextToken = math.clamp(litLen, 0, 0xFF)
                write(string.pack("<I1", nextToken))
                if nextToken == 0xFF then
                    litLen = litLen - 255
                end
            until nextToken < 0xFF
        end

        -- push raw lit data
        write(chunk.Literal)

        if chunkNum ~= #blocks then
            -- push offset as u16
            write(string.pack("<I2", chunk.MatchOffset))

            -- pack extra match bytes
            if matLen >= 15 then
                matLen = matLen - 15

                repeat
                    local nextToken = math.clamp(matLen, 0, 0xFF)
                    write(string.pack("<I1", nextToken))
                    if nextToken == 0xFF then
                        matLen = matLen - 255
                    end
                until nextToken < 0xFF
            end
        end
    end
    return output
end

function lz4.decompress(lz4data: buffer, len: number): buffer
    local inputStream = Stream.fromBuffer(lz4data);
    local outputStream = Stream.new(len);

    repeat
        local token = inputStream:readu8()
        local litLen = bit32.rshift(token, 4)
        local matLen = bit32.band(token, 15) + 4

        if litLen >= 15 then
            repeat
                local nextByte = inputStream:readu8()
                litLen += nextByte
            until nextByte ~= 0xFF
        end

        local literal = inputStream:readbuffer(litLen);
        outputStream.position = outputStream.len;
        outputStream:writebuffer(literal);
        if outputStream.len < len then
            --match
            local offset = inputStream:readu16();
            if matLen >= 19 then
                repeat
                    local nextByte = inputStream:readu8();
                    matLen += nextByte;
                until nextByte ~= 0xFF;
            end

            outputStream:move(-offset);
            local pos = outputStream.position;
            local unreadBytes = math.abs(math.min((outputStream.len - outputStream.position) - matLen, 0));

            local amount = matLen - unreadBytes;
            local stream_len = outputStream.len;
            outputStream:expandToSize(outputStream.len + amount);
            buffer.copy(
                outputStream.buffer,
                stream_len,
                outputStream.buffer,
                pos,
                matLen - unreadBytes
            );

            if unreadBytes > 0 then
                repeat
                    outputStream.position = pos;
                    local unread = math.abs(math.min((stream_len - pos) - unreadBytes, 0));
                    if (unreadBytes <= 0) then
                        break
                    end
                    local extra_len = outputStream.len;
                    amount = unreadBytes - unread;
                    outputStream:expandToSize(outputStream.len + amount);
                    buffer.copy(
                         outputStream.buffer,
                         extra_len,
                         outputStream.buffer,
                         pos,
                         amount
                    );
                    unreadBytes = unread;
                until unreadBytes <= 0
                outputStream.position = outputStream.len;
            end
        end
    until outputStream.len >= len

    return outputStream.buffer;
end

return {
    compress = function(src: buffer | string): buffer | string
        local isBuffer = type(src) == "buffer";
        local compressed = lz4.compress(if (isBuffer) then buffer.tostring(src::buffer) else src::string);
        if (isBuffer) then
            return buffer.fromstring(compressed)
        end
        return compressed
    end::any,
    decompress = function(src: buffer | string, len: number): buffer | string
        local isBuffer = type(src) == "buffer";
        local decompressed = lz4.decompress(if (isBuffer) then src::buffer else buffer.fromstring(src::string), len);
        if (isBuffer) then
            return decompressed
        end
        return buffer.tostring(decompressed)
    end::any,
    compressFrame = function(...)
        error("Not implemented")
    end::any,
    decompressFrame = function(...)
        error("Not implemented")
    end::any,
}
