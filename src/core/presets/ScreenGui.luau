--!strict
local datatypes = require("../datatypes");

local Enum = datatypes.Enums;

local impl = {};
impl.object = nil::any;
impl.loader = {};
impl.property = {};
impl.property.set = {};

function impl.loader.IgnoreGuiInset(self: any, property: any?): ()
    if (property) then
        local inset = self["@instance"].properties["ScreenInsets"];
        if (inset.value == Enum.ScreenInsets.CoreUISafeInsets) then
            inset.value = Enum.ScreenInsets.DeviceSafeInsets;
        end
    end
end

function impl.property.set.IgnoreGuiInset(self: any, _: boolean)
    error(`Use property 'ScreenInsets' instead of 'IgnoreGuiInset'`);
end

return impl;
