local addon = {}
local secret = {}
function issecretvalue(value) return value == secret end
function GetBuildInfo() return "1.60.1", "70938", "Nov 12 2026", 16001 end
SlashCmdList = {}
local info = { name = "Raptor Strike", spellID = 2973, minRange = 0, maxRange = 5, castTime = 0 }
C_Spell = {
    GetSpellInfo = function() return info end,
    SpellHasRange = function() return true end,
    GetSpellSubtext = function() return "Rank 1" end,
    GetSpellDescription = function() return "Description from client" end,
}
C_SpellBook = { IsSpellKnown = function() return true end }
C_TooltipInfo = { GetSpellByID = function()
    return { lines = { { type = 0, leftText = "Melee Range", rightText = "Next melee" },
        { type = 34, leftText = secret } } }
end }
assert(loadfile("EnhancedCombatForever/SpellInspect.lua"))("EnhancedCombatForever", addon)
local report = addon.BuildSpellReport(2973)
for _, expected in ipairs({ "70938", "maxRange: 5", "Rank 1", "Description from client", "Melee Range", "Next melee", "[restricted]" }) do
    assert(report:find(expected, 1, true), "missing report field: " .. expected)
end
C_TooltipInfo.GetSpellByID = function() error("unavailable") end
assert(addon.BuildSpellReport(2973):find("Tooltip unavailable", 1, true))
info = nil
assert(addon.BuildSpellReport(0):find("Ability not found", 1, true))
info = secret
assert(addon.BuildSpellReport(0):find("Ability not found", 1, true))
print("Spell inspection tests passed")
