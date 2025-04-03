--!strict
local dom = require("../dom");
local roblox = require("./types/roblox");
local datatypes = require("./datatypes");
local reflection = require("../reflection");

local presets = require("./presets");

local Signal = require("./signal");

type Signal = Signal.Signal;

local object = {};

local function isObject(value: any): boolean
    return type(value) == "table" and getmetatable(value) == object;
end
object.is = isObject;

local PROXY_MAP = newproxy(true);

getmetatable(PROXY_MAP).__index = reflection.API_CLASS_MAP;

local function blankFromClass(className: string): object
    local class = reflection:GetClass(className);
    if (not class) then
        error(`Class "{className}" not found (maybe outdated?)`);
    end
    local is_service =
        if (class.Tags) then
            table.find(class.Tags, "Service") ~= nil
        else
            false;
    return setmetatable({
        ["@instance"] = {
            className = className,
            referent = -1,
            properties = {},
            parent = nil,
            isService = is_service,
        }::dom.DOMInstance,
        ["@children"] = {},
        ["@events"] = {}::{[string]: Signal},
        ["@parent"] = nil::object?,
        ["@destroyed"] = false,
        ["@internal_map"] = PROXY_MAP,
    }, object);
end

function object.dom(dom: dom.DOMInstance): object
    local blank = blankFromClass(dom.className);
    blank["@instance"] = dom;
    return blank;
end

function object.raw(className: string): object
    return blankFromClass(className);
end

export type object = typeof(blankFromClass(""));

local TYPE_MAP = {
    ["BinaryString"] = "String",
    ["int64"] = "Int64",
    ["bool"] = "Bool",
    ["string"] = "String",
    ["float"] = "Float",
    ["double"] = "Double",
    ["int"] = "Int",
};

local DEFAULT_TYPE_MAP = {
    ["BinaryString"] = function(className: string, superclass: string, property: string)
        return "";
    end,
    ["int64"] = function(className: string, superclass: string, property: string)
        return buffer.create(8);
    end,
    ["bool"] = function(className: string, superclass: string, property: string)
        return false;
    end,
    ["string"] = function(className: string, superclass: string, property: string)
        if (property == "Name") then
            return className;
        end
        return "";
    end,
    ["float"] = function(className: string, superclass: string, property: string)
        return 0;
    end,
    ["double"] = function(className: string, superclass: string, property: string)
        return 0;
    end,
    ["int"] = function(className: string, superclass: string, property: string)
        return 0;
    end,
};

local DEFAULT_VALUE = {
    ["NumberRange"] = function(default: string)
        local min, max = unpack(default:split(" "));
        local nmin = tonumber(min) or 0;
        return datatypes.NumberRange.new(nmin, tonumber(max) or nmin);
    end,
};

local function getSpecialDefaultPropertyHandler(className: string, name: string)
    local class = reflection:GetClass(className);
    if (not class) then
        error("Class not found");
    end
    local preset = presets[className];
    if (preset and preset.default) then
        local handler = preset.default[name];
        if (handler) then
            return handler;
        end
    end
    if (class.Superclass == "<<<ROOT>>>") then
        return;
    end
    return getSpecialDefaultPropertyHandler(class.Superclass, name);
end

local function getSpecialPropertyLoadHandler(className: string, name: string)
    local class = reflection:GetClass(className);
    if (not class) then
        error("Class not found");
    end
    local preset = presets[className];
    if (preset and preset.loader) then
        local handler = preset.loader[name];
        if (handler) then
            return handler;
        end
    end
    if (class.Superclass == "<<<ROOT>>>") then
        return;
    end
    return getSpecialPropertyLoadHandler(class.Superclass, name);
end

local IGNORE_PROPERTIES_TYPE = {
    "SecurityCapabilities",
    "PhysicalProperties",
    "Content", -- TODO: fix?
};

local function loadDefaultProperties(self: object, className: string)
    local instance = self["@instance"];
    local class = reflection:GetClass(className);
    if (not class) then
        error("Class not found");
    end
    local properties = instance.properties;
    local post_load = {};
    for _, member in class.Members do
        if (member.MemberType ~= "Property") then
            continue;
        end
        local customLoader = getSpecialPropertyLoadHandler(className, member.Name);
        if (customLoader) then
            table.insert(post_load, function(self)
                customLoader(
                    self,
                    (properties[member.Name]::any)
                );
            end);
            continue;
        end
        if (
            properties[member.Name]
            or (member.Name == "ClassName" and member.ValueType.Name == "string" and member.ValueType.Category == "Primitive")
        ) then
            continue;
        end

        local customDefault = getSpecialDefaultPropertyHandler(className, member.Name);
        if (customDefault ~= nil and type(customDefault) == "string") then
            continue;
        end

        if (
            member.Default == "__api_dump_write_only_property__"
            or (member.Tags and (
                table.find(member.Tags, "Deprecated")
                or table.find(member.Tags, "NotScriptable")
            ))
        ) then
            continue;
        end

        local default = nil;
        local serializeId = dom.roblox.PropertyTypes[member.ValueType.Name];
        if (member.ValueType.Category == "Enum") then
            serializeId = dom.roblox.PropertyTypes.Enum;
            local enum = datatypes.Enums[member.ValueType.Name];
            if (enum) then
                local item = enum[member.Default];
                if (item) then
                    default = item;
                else
                    default = enum:GetEnumItems()[1];
                end
            else
                error(`Enum '{member.ValueType.Name}' not found`);
            end
        elseif (member.ValueType.Category == "Primitive") then
            serializeId = dom.roblox.PropertyTypes[TYPE_MAP[member.ValueType.Name]];
            if (DEFAULT_TYPE_MAP[member.ValueType.Name]) then
                default = DEFAULT_TYPE_MAP[member.ValueType.Name](instance.className, className, member.Name);
            end
        elseif (member.ValueType.Category == "DataType") then
            local datatype = datatypes[member.ValueType.Name];
            if (datatype) then
                local custom = DEFAULT_VALUE[member.ValueType.Name];
                if (custom and member.Default ~= "__api_dump_class_not_creatable__") then
                    default = custom(member.Default);
                else
                    local ok, err = pcall(datatype.new);
                    if (ok) then
                        default = err;
                    else
                        if (not table.find(IGNORE_PROPERTIES_TYPE, member.ValueType.Name)) then
                            print(member.ValueType.Name, err);
                        end
                    end
                end
            else
                if (not table.find(IGNORE_PROPERTIES_TYPE, member.ValueType.Name)) then
                    print(`[rbx-manager] DataType '{member.ValueType.Name}' not supported`);
                end
                continue;
            end
        elseif (member.ValueType.Category == "Class") then
            serializeId = dom.roblox.PropertyTypes.Ref;
            default = nil;
        end
        if (not serializeId) then
            continue;
        end

        if (customDefault) then
            if (type(customDefault) == "function") then
                default = customDefault(self, datatypes, default);
            end
        end

        properties[member.Name] = {
            type = serializeId,
            value = default,
        };
    end
    if (class.Superclass ~= "<<<ROOT>>>") then
        loadDefaultProperties(self, class.Superclass);
    end
    for _, post in post_load do
        post(self);
    end
end

function object.LoadDefaultProperties(self: object, className: string)
    loadDefaultProperties(self, className);
end

function object.create(className: string): roblox.Instance
    local class = reflection:GetClass(className);
    if (not class) then
        error("Class not found");
    end

    local object = object.raw(className);

    loadDefaultProperties(object, className);

    return object::any;
end

function object.new(className: string, parent: roblox.Instance?): roblox.Instance
    local class = reflection:GetClass(className);
    if (not class) then
        error("Class not found");
    end
    if (class.Tags and table.find(class.Tags, "NotCreatable")) then
        error("Class is not creatable");
    end

    local object = object.raw(className);

    assert(parent == nil or isObject(parent), "Parent must be an instance");

    loadDefaultProperties(object, className);

    (object::any).Parent = parent;

    return object::any;
end

object.presets = presets;

local function resolveGetProperty(self: object, className: string, key: string)
    local class = reflection:GetClass(className);
    if (not class) then
        return nil;
    end
    local preset = presets[className];
    local handler, method;
    if (preset) then
        handler =
            if (preset.property and preset.property.get) then
                preset.property.get[key]
            else
                nil;
        method =
            if (preset.method) then
                preset.method[key]
            else
                nil;
    end
    if (handler and method) then
        error(`[object] Property and Method duplicate name conflict '{key}' in '{className}'`);
    end
    if (not handler and not method) then
        if (class.Superclass == "<<<ROOT>>>") then
            return nil;
        end
        local resolved = resolveGetProperty(self, class.Superclass, key);
        if (resolved) then
            return resolved;
        end
    end
    if (handler) then
        return handler(self)::any
    elseif (method) then
        assert(not self["@destroyed"], "Object is destroyed");
        return method;
    else
        local raw = self["@instance"].properties[key];
        if (raw) then
            return raw.value;
        end
        return;
    end
end

local function resolveSetProperty(self: object, className: string, key: string)
    if (self["@destroyed"]) then
        error("Object is destroyed");
    end
    local class = reflection:GetClass(className);
    if (not class) then
        return;
    end
    local preset = presets[className];
    local handler =
        if (preset and preset.property and preset.property.set) then
            preset.property.set[key]
        else
            nil;
    if (not handler) then
        if (class.Superclass == "<<<ROOT>>>") then
            return;
        end
        return resolveGetProperty(self, class.Superclass, key);
    end
    handler(self);
end

local function checkRecursion(self: object, parent: object?): boolean
    local search: object? = parent;
    while search do
        if (search == self) then
            return true;
        end
        assert(search);
        search = rawget(search::any, "@parent");
    end
    return false;
end

function object.__tostring(self: object)
    local name = self["@instance"].properties["Name"];
    return `<instance {tostring(if (name) then name.value else self["@instance"].className)}>`;
end

function object.__index(self: object, key: string)
    assert(type(key) == "string", "Index must be string");
    if (key == "Parent") then
        return rawget(self::any, "@parent");
    end
    local resolved = resolveGetProperty(self, self["@instance"].className, key);
    if (not resolved) then
        if (self:IsA("Instance")) then
            resolved = self:FindFirstChild(key);
        end
    end
    return resolved;
end

function object.__newindex(self: object, key: string, value: any)
    assert(type(key) == "string", "Index must be string");
    if (key == "Parent") then
        assert(value == nil or (isObject(value) and value:IsA("Instance")), "Parent must be an instance");
        local parent = rawget(self::any, "@parent");
        if (parent == value) then
            return;
        end
        if (checkRecursion(self, value)) then
            error("Parent cannot be a child of itself");
        end
        local descendant_added_signals = {};
        local descendant_removing_signals = {};
        local ancestry_changed_signal = self["@events"]["AncestryChanged"]::Signal?;
        local old_parent_event_signal;
        local new_parent_event_signal;
        if (parent) then
            local children_idx = table.find(parent["@children"], self);
            if (children_idx) then
                table.remove(parent["@children"], children_idx);
            else
                error("Child not found in parent (Internal Error)");
            end
            old_parent_event_signal = parent["@events"]["ChildRemoved"]::Signal?;
            while parent do
                local signal = parent["@events"]["DescendantRemoving"]::Signal?;
                if (signal) then
                    table.insert(descendant_removing_signals, signal);
                end
                parent = parent.Parent;
            end
        end
        if (value) then
            table.insert(value["@children"], self);
            new_parent_event_signal = value["@events"]["ChildAdded"]::Signal?;
            local new_parent = value;
            while new_parent do
                local signal = new_parent["@events"]["DescendantAdded"]::Signal?;
                if (signal) then
                    table.insert(descendant_added_signals, signal);
                end
                new_parent = new_parent.Parent;
            end
        end
        rawset(self::any, "@parent", value);

        if (ancestry_changed_signal) then
            ancestry_changed_signal:Fire(self, parent);
        end
        if (old_parent_event_signal) then
            old_parent_event_signal:Fire(self);
        end
        if (new_parent_event_signal) then
            new_parent_event_signal:Fire(self);
        end
        for _, signal in descendant_removing_signals do
            signal:Fire(self);
        end
        for _, signal in descendant_added_signals do
            signal:Fire(self);
        end
        return;
    end
    resolveSetProperty(self, self["@instance"].className, key);
end

return object;
