--!strict
local Helper = require("./Helper");

export type Entry = {
    Key: string,
    Data: string,
}

local AssetContentMap = {};
AssetContentMap.__type = "AssetContentMap";

local isFn = Helper.DataTypeIsFn(AssetContentMap);

AssetContentMap.__newindex = function()
    error("Cannot change");
end

local function newAssetContentMap(entries: { Entry }?, bundle_asset_id: number?)
    if (bundle_asset_id == 0) then
        bundle_asset_id = nil;
    end
    if (bundle_asset_id ~= nil) then
        if (type(bundle_asset_id) ~= "number" or bundle_asset_id < 0 or bundle_asset_id ~= math.floor(bundle_asset_id)) then
            error("AssetContentMap bundle asset id must be a non-negative integer");
        end
    end

    local source: { Entry } = entries or {};
    local stored: { Entry } = table.create(#source);
    local existing: { [string]: boolean } = {};
    for index, entry in source do
        if (type(entry) ~= "table" or type(entry.Key) ~= "string" or type(entry.Data) ~= "string") then
            error(`AssetContentMap entry {index} must have string Key and Data`);
        end
        if (existing[entry.Key]) then
            error(`AssetContentMap has a duplicate key '{entry.Key}'`);
        end
        existing[entry.Key] = true;
        stored[index] = {
            Key = entry.Key,
            Data = entry.Data,
        };
    end

    return setmetatable({
        BundleAssetId = bundle_asset_id,
        Entries = stored,
    }, AssetContentMap);
end

export type AssetContentMap = typeof(newAssetContentMap(nil, 0));

function AssetContentMap.new(entries: { Entry }?, bundle_asset_id: number?): AssetContentMap
    return newAssetContentMap(entries, bundle_asset_id);
end

function AssetContentMap.load(): AssetContentMap
    return newAssetContentMap(nil, nil);
end

local function Serialize(value: AssetContentMap): (number?, { Entry })
    return value.BundleAssetId, value.Entries;
end

local function Deserialize(bundle_asset_id: number?, entries: { Entry }): AssetContentMap
    return newAssetContentMap(entries, bundle_asset_id);
end

return {
    DataType = AssetContentMap,
    Serialize = Serialize,
    Deserialize = Deserialize,
    Is = isFn,
};
