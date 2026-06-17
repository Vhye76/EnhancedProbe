-- #EnhancedGCD.lua

local ADDON_NAME, ns = ...

local M = {}
ns.RegisterModule("EnhancedGCD", M)

-- #Dummy "Global Cooldown" spell; its cooldown reflects the live GCD.
local GCD_SPELL = 61304

local COOLDOWN_FIELDS = { "startTime", "duration", "modRate", "isEnabled", "isActive", "isOnGCD" }

local testCooldown

local function EnsureTestFrame()
    if testCooldown then return testCooldown end
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:Hide()
    testCooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    return testCooldown
end

local function ClassifyField(v)
    local secret = (issecretvalue and issecretvalue(v)) and true or false
    local okType, rawType = pcall(type, v)
    rawType = okType and rawType or "?"
    local rec = { secret = secret, type = rawType }
    if not secret then
        if rawType == "number" then
            rec.arithOk = pcall(function() return v + 0 end)
            rec.value = v
        elseif rawType == "boolean" then
            rec.value = v
        end
    end
    return rec
end

local function ProbeSpell(spellID)
    local rec = { spellID = spellID }

    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    rec.getSpellCooldown = { callOk = ok }
    if ok and type(info) == "table" then
        rec.getSpellCooldown.fields = {}
        for _, key in ipairs(COOLDOWN_FIELDS) do
            rec.getSpellCooldown.fields[key] = ClassifyField(info[key])
        end
    end

    local okd, durObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
    local dur = { callOk = okd }
    if okd then
        dur.returned = durObj ~= nil
        dur.secret   = (issecretvalue and issecretvalue(durObj)) and true or false
        if durObj ~= nil then
            local cd = EnsureTestFrame()
            local applyOk, applyErr = pcall(cd.SetCooldownFromDurationObject, cd, durObj)
            dur.applyOk = applyOk
            if not applyOk then dur.applyErr = tostring(applyErr) end
        end
    end
    rec.getSpellCooldownDuration = dur

    return rec
end

local function SampledIDs()
    local ids = { GCD_SPELL }
    if type(EnhancedProbeGCDSpells) == "table" then
        for _, id in ipairs(EnhancedProbeGCDSpells) do ids[#ids + 1] = id end
    end
    return ids
end

-- #A no-cooldown on-GCD filler reads isActive only while a GCD is running; gate capture on that.
local function AnySampledActive()
    for _, id in ipairs(SampledIDs()) do
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" and info.isActive == true then return true end
    end
    return false
end

local function Capture(label, out)
    if out.contexts[label] then return end
    local ctx = {
        inCombat   = UnitAffectingCombat("player") or false,
        lockdown   = InCombatLockdown() or false,
        capturedAt = date("%H:%M:%S"),
        spells     = {},
    }
    out.contexts[label] = ctx

    for _, id in ipairs(SampledIDs()) do
        ctx.spells[#ctx.spells + 1] = ProbeSpell(id)
    end
end

local armed = nil
local hooksInstalled = false

local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    -- #Gate on an active GCD so an off-GCD cast cannot lock in an idle sample.
    ns.RegisterEvent("SPELL_UPDATE_COOLDOWN", function()
        if not armed then return end
        local label = UnitAffectingCombat("player") and "event_combat" or "event_ooc"
        if armed.contexts[label] then return end
        if not AnySampledActive() then return end
        Capture(label, armed)
    end)
end

ns.RegisterProbe("gcd", function(out)
    out.contexts = {}
    Capture("sync", out)
    InstallHooks()
    armed = out
    out.pendingContexts = "event_ooc, event_combat"
    ns.Print("gcd: deferred contexts armed - cast instant abilities out of combat and in combat to fire GCDs, then '/reload'.")
end)
