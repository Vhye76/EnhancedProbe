-- #EnhancedDocs.lua

local ADDON_NAME, ns = ...

local M = {}
ns.RegisterModule("EnhancedDocs", M)

local DOC_ADDONS = { "Blizzard_APIDocumentationGenerated", "Blizzard_APIDocumentation" }

ns.RegisterProbe("docs", function(out)
    out.loadAttempts = {}

    for _, name in ipairs(DOC_ADDONS) do
        local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, name)
        out.loadAttempts[name] = {
            callOk = ok,
            loaded = (ok and loaded == true) or false,
            reason = (not ok and tostring(loaded)) or (reason and tostring(reason)) or nil,
        }
    end

    local doc = _G.APIDocumentation
    out.present = doc ~= nil
    if doc then
        out.tree = ns.SerializeTree(doc, 9)
    end
end)
