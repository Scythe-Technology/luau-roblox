--!strict
local roblox = require("./roblox");
local binary = require("./binary");

export type DOM = roblox.Document;
export type DOMInfo = roblox.DocumentInfo;
export type DOMClass = roblox.Class;
export type DOMInstance = roblox.Instance;
export type DOMProperty = roblox.Property;

local BINARY_HEADER_LEN = #binary.header;

local dom = {};

dom.roblox = roblox;

function dom.deserialize(data: string | buffer): roblox.Document
    if (type(data) == "string") then
        data = buffer.fromstring(data);
    end
    assert(type(data) == "buffer", "Internal DOM Error");

    if (
        buffer.len(data) > BINARY_HEADER_LEN
        and buffer.readstring(data, 0, BINARY_HEADER_LEN) == binary.header
    ) then
        -- Binary
        return binary.deserialize(data, BINARY_HEADER_LEN);
    else
        -- XML
        error("Not implemented");
    end
end

function dom.serialize(document: roblox.Document, format: ("XML" | "BINARY")?): buffer
    format = format or "BINARY";
    if (format == "BINARY") then
        return binary.serialize(document);
    else
        error("Not implemented");
    end
end

function dom.setDebugCallback(format: "XML" | "BINARY", callback: (...any) -> ()): ()
    format = format or "BINARY";
    if (format == "BINARY") then
        binary.debug(callback);
    else
        error("Not implemented");
    end
end

return dom;
