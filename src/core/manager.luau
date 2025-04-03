--!strict
--!native
local object = require("./object");
local roblox = require("./types/roblox");

local dom = require("../dom");

local reflection = require("../reflection");

local manager = {};

function manager.instanceFromDOM(instance: dom.DOMInstance): roblox.Instance?
    local className = instance.className;
    if (instance.isService and reflection:GetClass(className) == nil) then
        return nil
    end
    local obj = object.dom(instance);
    object.LoadDefaultProperties(obj, instance.className);
    return obj::any;
end

function manager.instancesFromDOM(doc: dom.DOM): {roblox.Instance}
    local instances = table.create(doc.info.instances);
    for _, instance in doc.instances do
        instances[instance.referent] = manager.instanceFromDOM(instance);
    end
    local valid = doc.info.instances;
    for _, instance in doc.instances do
        local object = instances[instance.referent];
        if (instance.parent) then
            local parent = instances[instance.parent];
            if (not parent) then
                print("[rbx-manager] Parent instance not found (instance dropped)");
                instances[instance.referent] = nil;
                continue;
            end
            rawset(object::any, "@parent", parent);
            table.insert(rawget(parent::any, "@children"), object);
            valid -= 1;
        end
    end
    for _, instance in instances do
        for name, property in (instance::any)["@instance"].properties do
            if (property.type == dom.roblox.PropertyTypes.Ref and property.value) then
                property.value = instances[property.value];
            elseif (property.type == dom.roblox.PropertyTypes.SharedString and property.value) then
                property.value = doc.sharedstrings[property.value];
            end
        end
    end
    local list: {roblox.Instance} = table.create(valid);
    for _, instance in instances do
        if (instance and rawget(instance::any, "@parent") == nil) then
            table.insert(list, instance);
        end
    end
    return list;
end

function manager.modelFromDOM(doc: dom.DOM): {roblox.Instance}
    return manager.instancesFromDOM(doc);
end

function manager.placeFromDom(doc: dom.DOM): roblox.DataModel
    local datamodel = object.raw("DataModel");
    datamodel["@instance"].properties["Name"] = {
        value = "DataModel",
        type = dom.roblox.PropertyTypes.String,
    };
    local instances = manager.instancesFromDOM(doc);
    for _, instance in instances do
        rawset(instance::any, "@parent", datamodel);
        table.insert(datamodel["@children"], instance);
    end
    return datamodel::any;
end

function manager.domFromInstances(
    descendants: {roblox.Instance},
    descendants_map: {[roblox.Instance]: number},
    ignoreParent: roblox.Instance?
): dom.DOM
    local sharedstrings = {};

    local instances: {dom.DOMInstance} = table.create(#descendants);
    local classes: {dom.DOMClass} = {}; do
        local map = {};
        local index = 1;
        for i, descendant in descendants do
            local instance = (descendant::any)["@instance"];
            local class_name = instance.className;
            local class: dom.DOMClass = map[class_name];
            if (not class) then
                class = {
                    index = index;
                    name = class_name,
                    instances = {},
                    isService = instance.isService,
                };
                index += 1;
                map[class_name] = class;
                table.insert(classes, class::any);
            end
            --[[Generate DOMInstance]] do
                local dom_instance = table.clone(instance);
                dom_instance.referent = i;
                dom_instance.properties = table.clone(dom_instance.properties);
                for name, property in instance.properties do
                    if (not property.type) then
                        continue;
                    end
                    local value = property.value;
                    if (property.type == dom.roblox.PropertyTypes.Ref and value) then
                        value = descendants_map[value];
                        if (not value) then
                            error(`Reference to non-existent instance at '{descendant:GetFullName()}' (from another DataModel?)`);
                        end
                    elseif (property.type == dom.roblox.PropertyTypes.SharedString) then
                        if (type(property.value) ~= "table") then
                            print("[rbx-manager] SharedString not set");
                            continue;
                        end
                        if (not table.find(sharedstrings, property.value)) then
                            assert(type(property.value) == "table", "Internal Error, SharedString not set");
                            table.insert(sharedstrings, property.value);
                        end
                        value = table.find(sharedstrings, property.value);
                        assert(value, "SharedString not found");
                    else
                        continue;
                    end
                    dom_instance.properties[name] = {
                        value = value,
                        type = property.type,
                    };
                end
                local parent = rawget(descendant::any, "@parent");
                if (parent and parent ~= ignoreParent) then
                    dom_instance.parent = descendants_map[parent];
                    assert(dom_instance.parent, "Parent instance not found (failed to reference)");
                end
                instances[i] = dom_instance;
            end
            table.insert(class.instances, i);
        end
    end

    return {
        info = {
            version = 0,
            instances = #instances,
            classes = #classes,
            reserved = buffer.create(8),
        },
        instances = instances,
        classes = classes,
        metadata = {},
        sharedstrings = sharedstrings,
    };
end

function manager.domFromPlace(datamodel: roblox.DataModel): dom.DOM
    assert(
        object.is(datamodel) and datamodel:IsA("DataModel"),
        "argument #1 must be a DataModel instance"
    );
    local descendants_map = {};
    local descendants = datamodel:GetDescendants(); do
        local filtered = table.create(#descendants);
        local index = 1;
        for _, descendant in descendants do
            local properties = rawget(descendant::any, "@instance").properties;
            if (properties["Archivable"] == nil or properties["Archivable"].value == true) then
                table.insert(filtered, descendant);
                descendants_map[descendant] = index;
                index += 1;
            end
        end
        descendants = filtered;
    end
    return manager.domFromInstances(descendants, descendants_map, datamodel);
end

function manager.domFromModel(instances: {roblox.Instance}): dom.DOM
    local descendants = {};
    local descendants_map = {};
    local index = 1;
    for _, instance in instances do
        assert(
            object.is(instance) and instance:IsA("Instance"),
            "argument #1 must be a Instance"
        );
        table.insert(descendants, instance);
        descendants_map[instance] = index;
        index += 1;
        for _, descendant in instance:GetDescendants() do
            if (descendant.Archivable) then
                table.insert(descendants, descendant);
                descendants_map[descendant] = index;
                index += 1;
            end
        end
    end
    return manager.domFromInstances(descendants, descendants_map);
end

local instance = {};

local function instanceNew(className: string, parent: roblox.Instance?): roblox.Instance
    return object.new(className, parent);
end
local function instanceCreate(className: string): roblox.Instance
    return object.create(className);
end

instance.new = (instanceNew::any)::roblox.NewConstructor;
instance.create = (instanceCreate::any)::(className: string) -> roblox.Instance;

manager.Instance = instance;

manager.typeof = function(value: any)
    if (object.is(value)) then
        return "Instance";
    end
    return typeof(value);
end;

manager.type = function(value: any)
    if (object.is(value)) then
        return "userdata";
    end
    return type(value);
end;

manager.implementProperty = function(
    className: string,
    propertyName: string,
    get_callback: (instance: roblox.Instance) -> any,
    set_callback: (instance: roblox.Instance, value: any) -> ()
)
    assert(type(className) == "string", "className must be a string");
    assert(type(propertyName) == "string", "propertyName must be a string");
    assert(type(get_callback) == "function", "get_callback must be a function");
    assert(type(set_callback) == "function", "set_callback must be a function");
    local existing = object.presets[className];
    if (not existing) then
        local impl = {};
        impl.method = {};
        impl.property = {
            get = {};
            set = {};
        };
        existing = impl;
        object.presets[className] = existing;
    end
    if (not existing.property) then
        existing.property = {
            get = {};
            set = {};
        };
    end
    existing.property.get[propertyName] = get_callback;
    existing.property.set[propertyName] = set_callback;
end;

manager.implementMethod = function(
    className: string,
    methodName: string,
    callback: (instance: roblox.Instance, ...any) -> any
)
    assert(type(className) == "string", "className must be a string");
    assert(type(methodName) == "string", "methodName must be a string");
    assert(type(callback) == "function", "get_callback must be a function");
    local existing = object.presets[className];
    if (not existing) then
        local impl = {};
        impl.method = {};
        existing = impl;
        object.presets[className] = existing;
    end
    if (not existing.method) then
        existing.method = {};
    end
    existing.method[methodName] = callback;
end;

return manager;
