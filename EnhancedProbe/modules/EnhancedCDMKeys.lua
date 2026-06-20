-- #EnhancedCDMKeys.lua

local ADDON_NAME, ns = ...

local M = {}
ns.RegisterModule("EnhancedCDMKeys", M)

local VIEWERS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local IDENTITY = {
    "cooldownID", "auraSpellID", "auraInstanceID", "isActiveSpell",
    "isActive", "wasSetFromItem", "wasSetFromCooldown",
    "wasSetFromCharges", "wasSetFromAura", "wasSetFromEditMode",
}

local MAX_SAMPLES = 8
local DATA_DEPTH = 6

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function ObjectType(v)
    local ok, t = pcall(function() return v.GetObjectType and v:GetObjectType() or nil end)
    return ok and t or nil
end

local function ScalarSample(v)
    local okT, t = pcall(type, v)
    t = okT and t or "?"
    if t == "number" or t == "boolean" or t == "string" then
        local okS, s = pcall(tostring, v)
        if okS then return s, t end
    end
    return nil, t
end

local function SerializeData(v, depth, seen)
    ns.MaybeYield()
    if IsSecret(v) then return "<secret>" end
    local okT, t = pcall(type, v)
    if not okT then return "<?>" end
    if t == "string" or t == "number" or t == "boolean" then return v end
    if t ~= "table" then return "<" .. t .. ">" end
    local wt = ObjectType(v)
    if wt then return "<widget:" .. wt .. ">" end
    if seen[v] then return "<ref>" end
    if depth <= 0 then return "<maxdepth>" end
    seen[v] = true
    local out = {}
    for k, kv in pairs(v) do
        if not IsSecret(k) then
            local kt = type(k)
            local key = (kt == "string" or kt == "number") and k or tostring(k)
            out[key] = SerializeData(kv, depth - 1, seen)
        end
    end
    return out
end

local function RecordField(fields, key, v)
    local f = fields[key]
    if not f then
        f = { seen = 0, secret = 0, plain = 0, types = {}, samples = {} }
        fields[key] = f
    end
    f.seen = f.seen + 1

    if IsSecret(v) then
        f.secret = f.secret + 1
        f.types.secret = (f.types.secret or 0) + 1
        return
    end

    f.plain = f.plain + 1
    local sample, t = ScalarSample(v)
    f.types[t] = (f.types[t] or 0) + 1
    if sample then
        local n = 0
        for _ in pairs(f.samples) do n = n + 1 end
        if f.samples[sample] == nil and n < MAX_SAMPLES then
            f.samples[sample] = true
        end
    end
end

local function IdentityValue(child, key)
    local ok, v = pcall(function() return child[key] end)
    if not ok then return "<error>" end
    if v == nil then return nil end
    if IsSecret(v) then return "<secret>" end
    local s, t = ScalarSample(v)
    return s or ("<" .. t .. ">")
end

local function CallResult(child, method)
    local ok, v = pcall(function()
        local f = child[method]
        if type(f) ~= "function" then return nil end
        return f(child)
    end)
    if not ok then return "<error>" end
    if v == nil then return nil end
    if IsSecret(v) then return "<secret>" end
    return v
end

local function CaptureItemID(child)
    local ok, loc = pcall(function()
        local f = child.GetItemLocation
        return type(f) == "function" and f(child) or nil
    end)
    if not ok or not loc then return nil end
    if IsSecret(loc) then return "<secret>" end
    local okV, valid = pcall(function() return loc.IsValid and loc:IsValid() end)
    if okV and valid == false then return nil end
    local okID, id = pcall(function() return C_Item and C_Item.GetItemID(loc) end)
    if not okID then return "<error>" end
    if IsSecret(id) then return "<secret>" end
    return id
end

local function CaptureChild(child)
    local entry = {
        detected = rawget(child, "cooldownID") ~= nil
            or rawget(child, "auraInstanceID") ~= nil
            or rawget(child, "isActive") ~= nil,
        identity = {},
        data = {},
    }

    local isItem = CallResult(child, "IsItem")
    entry.isItem = isItem
    if isItem == true then
        entry.itemID = CaptureItemID(child)
    end

    for _, key in ipairs(IDENTITY) do
        local v = IdentityValue(child, key)
        if v ~= nil then entry.identity[key] = v end
    end

    for k, v in pairs(child) do
        if type(k) == "string" and not IsSecret(k) then
            local okT, t = pcall(type, v)
            if okT and t == "table" and not IsSecret(v) and not ObjectType(v) then
                entry.data[k] = SerializeData(v, DATA_DEPTH, {})
            end
        end
    end

    return entry
end

local function RunMatrix(label, out)
    local ctx = {
        inCombat   = UnitAffectingCombat("player") or false,
        lockdown   = InCombatLockdown() or false,
        capturedAt = date("%H:%M:%S"),
        viewers    = {},
        fields     = {},
    }
    out.contexts[label] = ctx

    for _, vname in ipairs(VIEWERS) do
        local viewer = _G[vname]
        if viewer and viewer.GetChildren then
            local vrec = { children = 0, detected = 0, items = 0, entries = {} }
            ctx.viewers[vname] = vrec
            for _, child in ipairs({ viewer:GetChildren() }) do
                vrec.children = vrec.children + 1
                local entry = CaptureChild(child)
                if entry.detected then vrec.detected = vrec.detected + 1 end
                if entry.isItem == true then vrec.items = vrec.items + 1 end
                vrec.entries[#vrec.entries + 1] = entry
                for k, v in pairs(child) do
                    if type(k) == "string" and not IsSecret(k) then
                        RecordField(ctx.fields, k, v)
                    end
                end
            end
        end
    end
end

local armed = nil
local hooksInstalled = false

local function DeferredCapture(label)
    if not armed or armed.contexts[label] then return end
    RunMatrix(label, armed)
    ns.Print(string.format("cdmkeys: captured context '%s'.", label))
end

local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    ns.RegisterEvent("UNIT_AURA", function(unit)
        if unit ~= "player" then return end
        DeferredCapture(UnitAffectingCombat("player") and "event_combat" or "event_ooc")
    end)

    hooksecurefunc("CameraZoomIn", function()
        DeferredCapture(UnitAffectingCombat("player") and "hook_combat" or "hook_ooc")
    end)
end

ns.RegisterProbe("cdmkeys", function(out)
    out.contexts = {}
    RunMatrix("sync", out)
    InstallHooks()
    armed = out
    out.pendingContexts = "event_ooc, event_combat, hook_ooc, hook_combat"
    ns.Print("cdmkeys: armed - with potions/healthstones usable and trinkets equipped so the Cooldown Manager populates, change an aura and zoom the camera, in and out of combat, then '/reload'.")
end)
