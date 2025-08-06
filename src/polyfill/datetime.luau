--!strict
--!native
--!optimize 2
if (type(_VERSION) == "string") then
    if (string.sub(_VERSION, 1, 4) == "zune") then
        return zune.datetime;
    elseif (string.sub(_VERSION, 1, 4) == "Lune") then
        return require("@lune/datetime") :: any
    end
end

return {
    now = function()
        error("Not implemented");
    end,
    fromUnixTimestamp = function()
        error("Not implemented");
    end,
    fromUnixTimestampMillis = function()
        error("Not implemented");
    end,
    fromUniversalTime = function()
        error("Not implemented");
    end,
    fromLocalTime = function()
        error("Not implemented");
    end,
    fromIsoDate = function()
        error("Not implemented");
    end,
} :: any;
