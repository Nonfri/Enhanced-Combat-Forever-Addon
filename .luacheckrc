-- Luacheck configuration for Enhanced Combat Forever addon
std = "lua51"

-- WoW global API available at addon load time
globals = {
    -- Core Lua/WoW injection
    "issecretvalue",
    -- Frame and UI
    "CreateFrame", "UIParent", "SlashCmdList",
    "PanelTemplates_TabResize", "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab",
    "ActionBarButtonEventsFrame", "StanceBar",
    -- Game API tables
    "C_Spell", "C_SpellBook", "C_UnitAuras", "C_NamePlate", "C_SwingTimer",
    "C_CurveUtil", "C_StringUtil", "C_TooltipInfo",
    "Enum",
    "Settings",
    -- Unit/player queries
    "UnitClass", "UnitHealth", "UnitHealthMax", "UnitHealthPercent",
    "UnitPower", "UnitPowerPercent", "UnitAffectingCombat",
    "UnitCanAttack", "UnitIsDeadOrGhost", "UnitExists", "UnitIsUnit",
    -- Action bar
    "GetActionInfo", "GetShapeshiftFormInfo",
    -- Slash command prefixes (WoW registers these as globals)
    "SLASH_ENHANCEDCOMBATFOREVERROTATION1",
    "SLASH_ENHANCEDCOMBATFOREVERDEBUG1",
    "SLASH_ENHANCEDCOMBATFOREVER1",
    "SLASH_ENHANCEDCOMBATFOREVERSPELL1",
    -- Misc WoW globals
    "GetBuildInfo", "UnitDistanceSquared", "ChatFontNormal",
    -- SavedVariables
    "EnhancedCombatForeverDB",
}

-- Files that are test helpers, not production code
files["tests/"] = {
    globals = {
        -- Additional stubs that tests define themselves
        "SLASH_ENHANCEDCOMBATFOREVERROTATION1",
    },
}

-- Ignore line-length warnings (WoW UI code is naturally wide)
ignore = { "631" }
