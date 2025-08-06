--!strict
local VERSION = _VERSION;
if (type(VERSION) == "string") then
    if (string.sub(VERSION, 1, 4) == "zune") then
        return zune.serde.zlib;
    elseif (string.sub(_VERSION, 1, 4) == "Lune") then
        local serde = require("@lune/serde")::any;
        return {
            compress = function(src: buffer | string): buffer | string
                local isBuffer = type(src) == "buffer";
                local compressed = serde.compress("zlib", if (isBuffer) then buffer.tostring(src::buffer) else src::string);
                if (isBuffer) then
                    return buffer.fromstring(compressed)
                end
                return compressed
            end::any,
            decompress = function(src: buffer | string, _: number): buffer | string
                local isBuffer = type(src) == "buffer";
                local decompressed = serde.decompress("zlib", if (isBuffer) then buffer.tostring(src::buffer) else src::string);
                if (isBuffer) then
                    return buffer.fromstring(decompressed)
                end
                return decompressed
            end::any,
        };
    end
end

return {
    compress = function(...)
        error("Not implemented")
    end::any,
    decompress = function(...)
        error("Not implemented")
    end::any,
};
