-- #EnhancedCDMFields.lua

local ADDON_NAME, ns = ...

local M = {}
ns.RegisterModule("EnhancedCDMFields", M)

local VIEWERS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local FIELDS = {
    "isActive", "auraSpellID", "auraInstanceID", "cooldownID",
    "isActiveSpell",
    "wasSetFromItem", "wasSetFromCooldown", "wasSetFromCharges",
    "wasSetFromAura", "wasSetFromEditMode",
}

local function TestOps(v)
    local ops = {}
    ops.tostring = pcall(tostring, v)
    ops.eq = pcall(function() return v == v end)
    local okType, rawType = pcall(type, v)
    rawType = okType and rawType or "?"
    if rawType == "number" then
        ops.arith = pcall(function() return v + 0 end)
    end
    return ops, rawType
end

local function RecordField(fields, key, readOk, v)
    local f = fields[key]
    if not f then
        f = { types = {}, secret = 0, plain = 0, readErr = 0, ops = {} }
        fields[key] = f
    end

    if not readOk then
        f.readErr = f.readErr + 1
        return
    end
    if issecretvalue and issecretvalue(v) then
        f.secret = f.secret + 1
    else
        f.plain = f.plain + 1
    end

    local ops, rawType = TestOps(v)
    f.types[rawType] = (f.types[rawType] or 0) + 1
    for op, ok in pairs(ops) do
        local o = f.ops[op]
        if not o then o = { ok = 0, err = 0 }; f.ops[op] = o end
        if ok then o.ok = o.ok + 1 else o.err = o.err + 1 end
    end
end

local function RunMatrix(label, out)
    local ctx = {
        inCombat   = UnitAffectingCombat("player") or false,
        lockdown   = InCombatLockdown() or false,
        capturedAt = date("%H:%M:%S"),
        itemFrames = 0,
        activeNow  = 0,
        fields     = {},
    }
    out.contexts[label] = ctx

    for _, vname in ipairs(VIEWERS) do
        local viewer = _G[vname]
        if viewer and viewer.GetChildren then
            for _, child in ipairs({ viewer:GetChildren() }) do
                local isItemFrame = rawget(child, "cooldownID") ~= nil
                    or rawget(child, "auraInstanceID") ~= nil
                    or rawget(child, "isActive") ~= nil
                if isItemFrame then
                    ctx.itemFrames = ctx.itemFrames + 1
                    local okActive, active = pcall(function() return child.isActive == true end)
                    if okActive and active then ctx.activeNow = ctx.activeNow + 1 end
                    for _, fname in ipairs(FIELDS) do
                        local ok, v = pcall(function() return child[fname] end)
                        RecordField(ctx.fields, fname, ok, v)
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
    ns.Print(string.format("cdmfields: captured context '%s'.", label))
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

ns.RegisterProbe("cdmfields", function(out)
    out.contexts = {}
    RunMatrix("sync", out)
    InstallHooks()
    armed = out
    out.pendingContexts = "event_ooc, event_combat, hook_ooc, hook_combat"
    ns.Print("cdmfields: armed - with the Cooldown Manager showing active cooldowns/buffs, change an aura and zoom the camera, in and out of combat, then '/reload'.")
end)
