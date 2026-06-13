-- #EnhancedSecrets.lua

local ADDON_NAME, ns = ...

local M = {}
ns.RegisterModule("EnhancedSecrets", M)

local MAX_AURAS = 80

local function TestOps(v)
    local ops = {}
    ops.tostring = pcall(tostring, v)
    ops.eq = pcall(function() return v == v end)
    local okType, rawType = pcall(type, v)
    rawType = okType and rawType or "?"
    if rawType == "number" then
        ops.arith = pcall(function() return v + 0 end)
    elseif rawType == "string" then
        ops.len = pcall(string.len, v)
    end
    return ops, rawType
end

local function RecordField(fields, key, v)
    local f = fields[key]
    if not f then
        f = { types = {}, secret = 0, plain = 0, ops = {} }
        fields[key] = f
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
        if not o then
            o = { ok = 0, err = 0 }
            f.ops[op] = o
        end
        if ok then o.ok = o.ok + 1 else o.err = o.err + 1 end
    end
end

local function TestInstanceLookup(ctx, aura)
    if ctx.instanceLookup then return end
    local ok, result = pcall(function()
        if aura.auraInstanceID == nil then return nil end
        return C_UnitAuras.GetAuraDataByAuraInstanceID("player", aura.auraInstanceID) ~= nil
    end)
    if ok and result == nil then return end
    ctx.instanceLookup = { callOk = ok, found = ok and result or nil, err = not ok and tostring(result) or nil }
end

local function RunMatrix(label, out)
    local ctx = {
        inCombat   = UnitAffectingCombat("player") or false,
        lockdown   = InCombatLockdown() or false,
        capturedAt = date("%H:%M:%S"),
        auras      = 0,
        fields     = {},
    }
    out.contexts[label] = ctx

    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, MAX_AURAS do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
            if not ok then
                ctx.enumError = tostring(aura)
                break
            end
            if not aura then break end
            ctx.auras = ctx.auras + 1
            for k, v in pairs(aura) do
                if not (issecretvalue and issecretvalue(k)) then
                    RecordField(ctx.fields, tostring(k), v)
                end
            end
            TestInstanceLookup(ctx, aura)
        end
    end
end

local armed = nil
local hooksInstalled = false

local function DeferredCapture(label)
    if not armed or armed.contexts[label] then return end
    RunMatrix(label, armed)
    ns.Print(string.format("secrets: captured context '%s'.", label))
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

ns.RegisterProbe("secrets", function(out)
    out.contexts = {}
    RunMatrix("sync", out)
    InstallHooks()
    armed = out
    out.pendingContexts = "event_ooc, event_combat, hook_ooc, hook_combat"
    ns.Print("secrets: deferred contexts armed - change an aura and zoom the camera, in and out of combat, then '/reload'.")
end)
