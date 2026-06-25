-- #EnhancedCDMItems.lua

local ADDON_NAME, ns = ...

local M = {}
ns.RegisterModule("EnhancedCDMItems", M)

local INFO_DEPTH = 5

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- #Full enum dump so a new 12.1 item/trinket/consumable category is discovered, not assumed.
local function EnumCategories()
    local cats = {}
    if Enum and Enum.CooldownViewerCategory then
        for name, val in pairs(Enum.CooldownViewerCategory) do
            cats[#cats + 1] = { name = name, value = val }
        end
        table.sort(cats, function(a, b) return (a.value or 0) < (b.value or 0) end)
    end
    return cats
end

-- #C_CooldownViewer namespace dump so a new item-cooldown accessor is discovered.
local function EnumAPI()
    local fns = {}
    if C_CooldownViewer then
        for k, v in pairs(C_CooldownViewer) do
            fns[#fns + 1] = { name = k, type = type(v) }
        end
        table.sort(fns, function(a, b) return a.name < b.name end)
    end
    return fns
end

-- #Scan _G for any frame whose name ends in CooldownViewer (the 4 known + any new one).
local function EnumViewerFrames()
    local frames = {}
    for k, v in pairs(_G) do
        ns.MaybeYield()
        if type(k) == "string" and k:match("CooldownViewer$") then
            local rec = { name = k, type = type(v) }
            if type(v) == "table" and v.GetObjectType then
                local ok, t = pcall(function() return v:GetObjectType() end)
                rec.objectType = ok and t or "?"
                local okN, n = pcall(function() return v:GetNumChildren() end)
                rec.numChildren = okN and n or nil
            end
            frames[#frames + 1] = rec
        end
    end
    table.sort(frames, function(a, b) return a.name < b.name end)
    return frames
end

-- #Flags whether any field name looks item-related (the smoking gun for native CDM item support).
local function FlagItemFields(info, accum)
    if type(info) ~= "table" then return end
    for k in pairs(info) do
        if type(k) == "string" and k:lower():find("item") then
            accum[k] = (accum[k] or 0) + 1
        end
    end
end

ns.RegisterProbe("cdmitems", function(out)
    out.capturedAt = date("%H:%M:%S")
    out.inCombat   = UnitAffectingCombat("player") or false
    out.lockdown   = InCombatLockdown() or false

    out.categories   = EnumCategories()
    out.api          = EnumAPI()
    out.viewerFrames = EnumViewerFrames()

    -- #Per-category: every cooldownID's full info, serialized secret-aware, plus an item-field tally.
    out.entries        = {}
    out.itemFieldTally = {}
    out.entryCounts    = {}

    if not (C_CooldownViewer
        and C_CooldownViewer.GetCooldownViewerCategorySet
        and C_CooldownViewer.GetCooldownViewerCooldownInfo) then
        out.error = "C_CooldownViewer category/info API missing"
        return
    end

    for _, cat in ipairs(out.categories) do
        local okSet, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat.value)
        local catEntries = {}
        local count = 0
        if okSet and type(ids) == "table" then
            for _, id in ipairs(ids) do
                ns.MaybeYield()
                count = count + 1
                local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
                if okInfo and info ~= nil and not IsSecret(info) then
                    FlagItemFields(info, out.itemFieldTally)
                    catEntries[tostring(id)] = ns.SerializeTree(info, INFO_DEPTH)
                else
                    catEntries[tostring(id)] = okInfo and "<secret-or-nil>" or "<read-error>"
                end
            end
        end
        out.entries[cat.name]     = catEntries
        out.entryCounts[cat.name] = count
    end

    -- #Player-side reference: equipped trinkets + their on-use spells, to cross-check against CDM entries.
    out.trinkets = {}
    for _, slot in ipairs({ 13, 14 }) do
        local itemID = GetInventoryItemID and GetInventoryItemID("player", slot)
        local rec = { slot = slot, itemID = itemID }
        if itemID and C_Item and C_Item.GetItemSpell then
            local _, spellID = C_Item.GetItemSpell(itemID)
            rec.onUseSpellID = spellID
        end
        out.trinkets[#out.trinkets + 1] = rec
    end

    local nItemFields = 0
    for _ in pairs(out.itemFieldTally) do nItemFields = nItemFields + 1 end
    ns.Print(string.format(
        "cdmitems: %d categories, %d API fns, %d viewer frames, %d item-named fields found.",
        #out.categories, #out.api, #out.viewerFrames, nItemFields))
    ns.Print("cdmitems: run OOC with trinkets equipped and a healthstone/potion in bags; if 12.1 tracks items they show as entries or item-named fields.")
end)
