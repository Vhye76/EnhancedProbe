-- #EnhancedFrames.lua

local ADDON_NAME, ns = ...

local M = {}
ns.RegisterModule("EnhancedFrames", M)

M.targets = {
    "BuffBarCooldownViewer",
    "BuffIconCooldownViewer",
    "CooldownViewerSettings",
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
}

local function EnumerateKeys(tbl)
    local keys = {}
    for k, v in pairs(tbl) do
        if type(k) == "string" then
            keys[k] = ns.ClassifyValue(v)
        end
    end
    return keys
end

ns.RegisterProbe("frames", function(out)
    out.targets    = {}
    out.widgetApis = {}

    for _, name in ipairs(M.targets) do
        local target = _G[name]
        local entry = { present = target ~= nil, type = type(target) }
        out.targets[name] = entry

        if type(target) == "table" then
            entry.keys = EnumerateKeys(target)

            local okType, objType = pcall(function()
                return target.GetObjectType and target:GetObjectType()
            end)
            if okType and objType then entry.objectType = objType end

            local mt = getmetatable(target)
            local index = type(mt) == "table" and mt.__index or nil
            if type(index) == "table" then
                local apiKey = entry.objectType or name
                if not out.widgetApis[apiKey] then
                    out.widgetApis[apiKey] = EnumerateKeys(index)
                end
                entry.widgetApi = apiKey
            elseif index ~= nil then
                entry.widgetApi = "<" .. type(index) .. ">"
            end
        end
    end
end)
