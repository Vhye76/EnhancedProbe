-- #EnhancedCensus.lua

local ADDON_NAME, ns = ...

local M = {}
ns.RegisterModule("EnhancedCensus", M)

local SELF_PREFIX  = ADDON_NAME
local SLASH_PREFIX = "SLASH_" .. ADDON_NAME:upper()

local function IsSelf(name)
    return name:sub(1, #SELF_PREFIX) == SELF_PREFIX
        or name:sub(1, #SLASH_PREFIX) == SLASH_PREFIX
end

local function CensusNamespace(value)
    local members = {}
    for k, v in pairs(value) do
        if type(k) == "string" then
            members[k] = ns.ClassifyValue(v)
        end
    end
    return members
end

local function CensusEnums(value, out, counts)
    for enumName, enumTable in pairs(value) do
        if type(enumName) == "string" and type(enumTable) == "table" then
            local members = {}
            for k, v in pairs(enumTable) do
                if type(k) == "string" then
                    local vt = type(v)
                    if vt == "number" or vt == "string" or vt == "boolean" then
                        members[k] = v
                    else
                        members[k] = ns.ClassifyValue(v)
                    end
                end
            end
            out.enums[enumName] = members
            counts.enums = counts.enums + 1
        end
    end
end

ns.RegisterProbe("census", function(out)
    out.globals    = {}
    out.namespaces = {}
    out.enums      = {}

    local counts = { globals = 0, namespaces = 0, enums = 0, skippedKeys = 0 }
    out.counts = counts

    for name, value in pairs(_G) do
        ns.MaybeYield()
        if type(name) ~= "string" then
            counts.skippedKeys = counts.skippedKeys + 1
        elseif not IsSelf(name) then
            if name:sub(1, 2) == "C_" and type(value) == "table" then
                out.namespaces[name] = CensusNamespace(value)
                counts.namespaces = counts.namespaces + 1
            elseif name == "Enum" and type(value) == "table" then
                CensusEnums(value, out, counts)
            else
                out.globals[name] = ns.ClassifyValue(value)
                counts.globals = counts.globals + 1
            end
        end
    end
end)
