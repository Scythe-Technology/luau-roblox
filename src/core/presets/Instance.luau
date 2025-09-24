--!strict
local Attributes = require("../instance/attributes");
local Event = require("../instance/event");
local Tags = require("../instance/tags");

local md5 = require("@polyfill").md5;

local impl = {};
impl.object = nil :: any;
impl.default = {};
impl.method = {};
impl.property = {};
impl.property.get = {};
impl.property.set = {};

function impl.default.Archivable(self: any): boolean
    return true;
end

function impl.method.GetFullName(self: any): string
    local name = self.Name;
    if (not name) then
        return "";
    end
    local parent = rawget(self, "@parent");
    if (not parent) then
        return name;
    end
    return `{parent:GetFullName()}.{name}`;
end

function impl.method.GetChildren(self: any): {any}
    return table.clone(self["@children"]);
end

function impl.method.WaitForChild(self: any, name: string): any?
    local child = self:FindFirstChild(name);
    if (child) then
        return child;
    end
    repeat
        child = self.ChildAdded:Wait();
    until (child.Name == name);
    return child;
end

function impl.method.FindFirstAncestor(self: any, name: string): any?
    local parent = rawget(self, "@parent");
    while (parent) do
        if (parent.Name == name) then
            return parent;
        end
        parent = rawget(parent, "@parent");
    end
    return;
end

function impl.method.FindFirstAncestorOfClass(self: any, className: string): any?
    local parent = rawget(self, "@parent");
    while (parent) do
        if (parent["@instance"].className == className) then
            return parent;
        end
        parent = rawget(parent, "@parent");
    end
    return;
end

function impl.method.FindFirstAncestorWhichIsA(self: any, className: string): any?
    local parent = rawget(self, "@parent");
    while (parent) do
        if (parent:IsA(className)) then
            return parent;
        end
        parent = rawget(parent, "@parent");
    end
    return;
end

function impl.method.FindFirstChild(self: any, name: string, recursive: boolean): any?
    for _, child in self["@children"] do
        if (child.Name == name) then
            return child;
        end
    end
    if (recursive) then
        for _, child in self["@children"] do
            local found = child:FindFirstChild(name, true);
            if (found ~= nil) then
                return found;
            end
        end
    end
    return nil;
end

function impl.method.FindFirstChildOfClass(self: any, className: string): any?
    for _, child in self["@children"] do
        if (child["@instance"].className == className) then
            return child;
        end
    end
    return nil;
end

function impl.method.FindFirstChildWhichIsA(self: any, className: string): any?
    for _, child in self["@children"] do
        if (child:IsA(className)) then
            return child;
        end
    end
    return nil;
end

function impl.method.GetDescendants(self: any): {any}
    local descendants = table.clone(self["@children"]);
    for _, child in self["@children"] do
        local child_descendants = child:GetDescendants()
        table.move(child_descendants, 1, #child_descendants, #descendants + 1, descendants);
    end
    return descendants;
end

function impl.method.IsDescendantOf(self: any, ancestor: any): boolean
    local parent = rawget(self, "@parent");
    while (parent) do
        if (parent == ancestor) then
            return true;
        end
        parent = rawget(parent, "@parent");
    end
    return false;
end

function impl.method.IsAncestorOf(self: any, child: any): boolean
    local parent = rawget(child, "@parent");
    while (parent) do
        if (parent == self) then
            return true;
        end
        parent = rawget(parent, "@parent");
    end
    return false;
end

function impl.method.GetActor(self: any): any
    if (self["@instance"].className == "Actor") then
        return self;
    end
    return self:FindFirstAncestorOfClass("Actor");
end

function impl.method.GetDebugId(self: any): any
    return md5(tostring(self["@instance"]));
end

function impl.method.GetAttribute(self: any, name: string): any
    assert(type(name) == "string", "Argument #1 must be a string");
    local attributes = self["@instance"].properties["AttributesSerialize"] or {
        type = 1,
        value = "",
    };
    local decoded = Attributes.decodeAttributes(attributes.value);
    if (not decoded[name]) then
        return nil;
    end
    return decoded[name].value;
end
function impl.method.SetAttribute(self: any, name: string, value: any): ()
    local attributes = self["@instance"].properties["AttributesSerialize"];
    if (not attributes) then
        attributes = {
            type = 1,
            value = "",
        };
        self["@instance"].properties["AttributesSerialize"] = attributes;
    end
    if (#name > 100) then
        error(`Attribute name exceeds 100 character limit ("{name}")`);
    end
    local start = string.find(name, "[^a-zA-Z0-9%-%./_]");
    if (start) then
        error(`Attribute name contains illegal character '{string.sub(name, start, start)}' ("{name}")`);
    end
    local decoded = Attributes.decodeAttributes(attributes.value);
    decoded[name] = {
        type = Attributes.getTypeIdOf(value),
        value = value,
    };
    attributes.value = Attributes.encodeAttributes(decoded);
    local event = self["@events"]["AttributeChanged"];
    if (event) then
        event:Fire(name);
    end
end
function impl.method.GetAttributes(self: any, name: string, value: any): any
    local attributes = self["@instance"].properties["AttributesSerialize"] or {
        type = 1,
        value = "",
    };
    local map = {}
    for key, data in Attributes.decodeAttributes(attributes.value) do
        map[key] = data.value;
    end
    return map;
end

function impl.method.HasTag(self: any, tag: string): any
    local tags = self["@instance"].properties["Tags"] or {
        type = 1,
        value = "",
    };
    return table.find(Tags.decodeTags(tags.value), tag) ~= nil;
end
function impl.method.GetTags(self: any, tag: string): any
    local tags = self["@instance"].properties["Tags"] or {
        type = 1,
        value = "",
    };
    return Tags.decodeTags(tags.value);
end
function impl.method.AddTag(self: any, tag: string): ()
    local tags = self["@instance"].properties["Tags"] or {
        type = 1,
        value = "",
    };
    local decoded = Tags.decodeTags(tags.value);
    table.insert(decoded, tag);
    tags.value = Tags.encodeTags(decoded);
end
function impl.method.RemoveTag(self: any, tag: string): ()
    local tags = self["@instance"].properties["Tags"] or {
        type = 1,
        value = "",
    };
    local decoded = Tags.decodeTags(tags.value);
    table.remove(decoded, table.find(decoded, tag) or -1);
    tags.value = Tags.encodeTags(decoded);
end

function impl.method.Clone(self: any): any
    local copy = impl.object.raw(self["@instance"].className);
    copy["@instance"] = table.clone(self["@instance"]);
    copy["@instance"].properties = table.clone(self["@instance"].properties);
    for _, child in self["@children"] do
        table.insert(copy["@children"], child:Clone());
    end
    return copy;
end

function impl.method.ClearAllChildren(self: any): ()
    local childs = self["@children"];
    for _, child in childs do
        rawset(child, "@parent", nil);
    end
    table.clear(childs);
end

function impl.method.Destroy(self: any): ()
    if (rawget(self, "@parent")) then
        self.Parent = nil;
    end
    rawset(self, "@destroyed", true);
    --[[Destroying<Event>]] do
        local event = self["@events"]["Destroying"];
        if (event) then
            event:Fire();
        end
    end
    for _, event in self["@events"] do
        event:Destroy();
    end
end

function impl.property.get.Name(self: any)
    local property = self["@instance"].properties["Name"];
    if (not property) then
        return nil;
    end
    return property.value;
end
function impl.property.get.Archivable(self: any)
    local property = self["@instance"].properties["Archivable"];
    if (not property) then
        return nil;
    end
    return property.value;
end
function impl.property.get.className(self: any)
    return self["@instance"].className;
end

local function addEvent(name: string)
    impl.property.get[name] = Event.generate(name);
end

addEvent("AncestryChanged");
addEvent("AttributeChanged");
addEvent("ChildAdded");
addEvent("ChildRemoved");
addEvent("DescendantAdded");
addEvent("DescendantRemoving");
addEvent("Destroying");

return impl;
