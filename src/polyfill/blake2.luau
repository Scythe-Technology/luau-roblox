--!strict
--!native
--!optimize 2
if (type(_VERSION) == "string") then
    if (string.sub(_VERSION, 1, 4) == "Zune") then
        return {
            b128 = function(input)
                local hash = zune.crypto.createHash("blake2b128");
                hash:update(input);
                return hash:digest("hex");
            end
        };
    end
end

local md5 = require("./md5");

-- TODO: replace md5 with blake2 b128
return {
    b128 = md5,
}::any;
