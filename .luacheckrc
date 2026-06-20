-- #Luacheck config for EnhancedProbe. WoW runs Lua 5.1, so analysis targets that std.
-- #This catches syntax errors, typo'd API names, and unused/shadowed locals. It does
-- #NOT understand WoW's taint/secret-value model; probes still need in-game runs.

std = "lua51"
max_line_length = false
codes = true
unused_args = false

-- #The addon vararg header 'local ADDON_NAME, ns = ...' leaves ADDON_NAME unused
-- #in most files (only ns is needed).
ignore = { "211/ADDON_NAME" }

-- #Read-only WoW API surface and Lua-extension globals the client provides.
read_globals = {
    -- #C_* namespaces
    "C_AddOns", "C_APIDocumentation", "C_Item", "C_Spell", "C_Timer", "C_UnitAuras",
    "Enum",

    -- #Optional user-set globals: spell IDs for the gcd / charges probes to sample.
    "EnhancedProbeGCDSpells", "EnhancedProbeChargeSpells",

    -- #core API
    "hooksecurefunc", "issecretvalue", "securecall", "debugprofilestop",
    "CreateFrame", "UIParent",
    "GetBuildInfo", "GetTime", "InCombatLockdown", "UnitAffectingCombat",

    -- #fonts
    "GameFontNormal", "GameFontHighlightSmall", "GameFontDisableSmall",

    -- #Lua-extension global aliases WoW exposes (not in base 5.1)
    "wipe", "tinsert", "tremove", "strsplit", "strjoin", "strtrim",
    "format", "tContains", "CopyTable", "Mixin", "CreateFromMixins",
    "floor", "ceil", "abs", "max", "min", "time", "date",
}

-- #Globals this addon legitimately writes.
globals = {
    "SLASH_ENHANCEDPROBE1", "SlashCmdList",
    "EnhancedProbeDB",
    "_",
}
