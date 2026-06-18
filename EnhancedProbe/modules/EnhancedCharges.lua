-- #EnhancedCharges.lua

local ADDON_NAME, ns = ...

local M = {}
ns.RegisterModule("EnhancedCharges", M)

local CHARGE_FIELDS = { "currentCharges", "maxCharges", "cooldownStartTime", "cooldownDuration", "chargeModRate" }

local testBar

local function EnsureTestBar()
    if testBar then return testBar end
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:Hide()
    testBar = CreateFrame("StatusBar", nil, holder)
    return testBar
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

    if C_Spell.GetSpellCharges then
        local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
        rec.getSpellCharges = { callOk = ok }
        if ok and type(info) == "table" then
            rec.getSpellCharges.fields = {}
            for _, key in ipairs(CHARGE_FIELDS) do
                rec.getSpellCharges.fields[key] = ClassifyField(info[key])
            end
        end
    end

    if C_Spell.GetSpellChargeDuration then
        local okd, durObj = pcall(C_Spell.GetSpellChargeDuration, spellID)
        local dur = { callOk = okd }
        if okd then
            dur.returned = durObj ~= nil
            dur.secret   = (issecretvalue and issecretvalue(durObj)) and true or false
            if durObj ~= nil then
                local bar = EnsureTestBar()
                local applyOk, applyErr = pcall(function()
                    bar:SetMinMaxValues(0, 1)
                    bar:SetTimerDuration(durObj,
                        Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Linear,
                        Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime)
                end)
                dur.applyOk = applyOk
                if not applyOk then dur.applyErr = tostring(applyErr) end
            end
        end
        rec.getSpellChargeDuration = dur
    end

    return rec
end

local function SampledIDs()
    local ids = {}
    if type(EnhancedProbeChargeSpells) == "table" then
        for _, id in ipairs(EnhancedProbeChargeSpells) do ids[#ids + 1] = id end
    end
    return ids
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

    -- #Fires when a charge is spent or regained, capturing the mid-recharge state.
    ns.RegisterEvent("SPELL_UPDATE_CHARGES", function()
        if not armed then return end
        Capture(UnitAffectingCombat("player") and "event_combat" or "event_ooc", armed)
    end)
end

ns.RegisterProbe("charges", function(out)
    out.contexts = {}
    Capture("sync", out)
    InstallHooks()
    armed = out
    out.pendingContexts = "event_ooc, event_combat"
    if #SampledIDs() == 0 then
        ns.Print("charges: set 'EnhancedProbeChargeSpells = { spellID }' to a multi-charge ability, then '/reload' and re-run.")
    else
        ns.Print("charges: armed - spend a charge out of combat and in combat (while recharging), then '/reload'.")
    end
end)
