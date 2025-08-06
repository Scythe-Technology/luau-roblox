--!strict
local VERSION = _VERSION;
if (type(VERSION) == "string") then
    if (string.sub(VERSION, 1, 4) == "zune") then
        return zune.serde.zstd;
    end
end

return {
    compress = function(...)
        error("Not implemented")
    end::any,
    decompress = function(...)
        error("Not implemented")
    end::any,
}
