--!strict
local fs = zune.fs;
local net = zune.net;
local serde = zune.serde;
local crypto = zune.crypto;

local REPO = "MaximumADHD/Roblox-Client-Tracker";
local BRANCH = "roblox";

local TARGET_PATH = "src/reflection/generated";

local URL = `https://raw.githubusercontent.com/{REPO}/refs/heads/{BRANCH}/Mini-API-Dump.json`;
local VERSION_URL = `https://raw.githubusercontent.com/{REPO}/refs/heads/{BRANCH}/version.txt`;

if (not fs.isDir("scripts/.cache")) then
    fs.writeDir("scripts/.cache");
end

if (not fs.isDir(TARGET_PATH)) then
    fs.writeDir(TARGET_PATH, true);
end

local TYPE_INFO = [[
export type ThreadSafety = "Unsafe" | "ReadSafe" | "Safe"

export type Security = string | {
    Read: string,
    Write: string,
}

export type Capabilities = {
    Read: {string},
}

export type TypeInfo = {
    Category: string,
    Name: string,
}

export type ValueType = {
    Name: string,
    Type: TypeInfo,
    Tags: {string}
}

export type FunctionMemberInfo = {
    MemberType: "Function",
    Name: string,
    Tags: {string}?,
    Serialization: {
        CanLoad: boolean,
        CanSave: boolean,
    },
    Parameters: {ValueType},
    ReturnType: TypeInfo | {TypeInfo},
    ThreadSafety: ThreadSafety,
    Security: Security,
}

export type EventMemberInfo = {
    MemberType: "Event",
    Name: string,
    Tags: {string}?,
    Parameters: {
        {
            Name: string,
            Type: {
                Category: string,
                Name: string,
            },
            Tags: {string}
        }
    },
    ThreadSafety: ThreadSafety,
    Security: Security,
}

export type PropertyMemberInfo = {
    Category: string,
    MemberType: "Property",
    Capabilities: Capabilities,
    Name: string,
    Tags: {string}?,
    Default: string?,
    Serialization: {
        CanLoad: boolean,
        CanSave: boolean,
    },
    ValueType: {
        Category: string,
        Name: string,
    },
    ThreadSafety: ThreadSafety,
    Security: Security,
}

export type MemberInfo = FunctionMemberInfo | EventMemberInfo | PropertyMemberInfo

export type ClassInfo = {
    Name: string,
    Superclass: string,
    Tags: {string}?,
    MemoryCategory: string,
    Members: {MemberInfo},
}

export type EnumInfo = {
    Name: string,
    Tags: {string}?,
    Items: {
        {
            Name: string,
            Value: number,
            Tags: {string}?
        }
    }
}

export type ApiDump = {
    Version: number,
    Classes: {ClassInfo},
    Enums: {EnumInfo}
}
]]

local function build(list: {string}): string
    return table.concat(list, '\n');
end

local version = net.http.request(VERSION_URL, {
    method = "GET",
    maxBodySize = 64; -- 64 bytes
});
assert(version.ok, `Invalid version response ({version.statusCode}): {version.body}`);

local function saveDump(version: string, dump: string)
    fs.writeFile(`{TARGET_PATH}/json-dump.luau`, build {
        `return [===[{dump}]===]`,
        ''
    });
    fs.writeFile(`{TARGET_PATH}/init.luau`, build {
        '-- Luau code generated by api-dump.luau',
        '--!strict',
        TYPE_INFO,
        'return {',
        `    Version = "{version}",`,
        '    DumpJson = require("./json-dump"),',
        '}',
        ''
    });
end

local hash = crypto.hash.md5(`{version.body}({URL})`);
if (fs.isFile(`scripts/.cache/{hash}`)) then
    local dump_compressed = fs.readFile(`scripts/.cache/{hash}`);
    local dump = serde.gzip.decompress(dump_compressed);
    saveDump(version.body, dump);
    print(`Roblox API Dump saved at {TARGET_PATH}/dump.json (from cache)`);
    print(`  Version: {version.body}`);
    return;
end

local dump = net.http.request(URL, {
    method = "GET",
    maxBodySize = 8 * 1024 * 1024; -- 8MB
});
assert(dump.ok, `Invalid dump response ({dump.statusCode}): {dump.body}`);

saveDump(version.body, dump.body);

local contents = serde.gzip.compress(dump.body, {
    level = 9
});
fs.writeFile(`scripts/.cache/{hash}`, contents);

print(`Roblox API Dump saved at {TARGET_PATH}/dump.json`);
print(`  Version: {version.body}`);
