-- Run from the repository root with Lua 5.1+ or fengari.
local frames, byUnit = {}, {}
local target, result = "nameplate1", true
local known, failCheck, secret = true, false, {}
local rangeCalls = 0
local swingResult, probeInfo
local swingTracking = false
Enum = { PlayerSwingType = { MainHand = 0 }, SpellBookSpellBank = { Player = 0 } }
C_SwingTimer = {
    IsTargetWithinSwingRange = function() return swingResult end,
    EnableRangeCheck = function(_, enabled) swingTracking = enabled end,
}
local function frame(parent)
    local f = { parent = parent, scripts = {}, shown = false }
    function f:EnableMouse() end
    function f:Hide() self.shown = false end
    function f:Show() self.shown = true end
    function f:ClearAllPoints() end
    function f:SetParent(p) self.parent = p end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetPoint(...) self.point = {...} end
    function f:IsForbidden() return false end
    function f:SetScript(event, callback) self.scripts[event] = callback end
    function f:RegisterEvent() end
    function f:CreateTexture()
        local t = {}
        function t:SetAllPoints() end
        function t:SetAtlas(atlas) self.atlas = atlas end
        function t:SetVertexColor(r, g, b) self.color = {r, g, b} end
        self.dot = t
        return t
    end
    return f
end
UIParent = frame()
function CreateFrame(_, _, parent)
    local f = frame(parent)
    frames[#frames + 1] = f
    return f
end
function issecretvalue(value) return value == secret end
function UnitIsUnit(unit) return unit == target end
C_NamePlate = { GetNamePlateForUnit = function(unit) return byUnit[unit] end }
local tracking = {}
C_SpellBook = {
    IsSpellKnown = function() return known end,
    GetNumSpellBookSkillLines = function() return probeInfo and 1 or 0 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 1 } end,
    GetSpellBookItemInfo = function() return { spellID = 2974 } end,
}
local tooltipMissing = false
C_TooltipInfo = { GetSpellByID = function(id)
    if tooltipMissing then return nil end
    if id == 14260 or id == 2973 then return { lines = { { type = 0, leftText = "Next melee", rightText = "6 sec cooldown" } } } end
    if id == 1752 or id == 2974 then return { lines = { { type = 0, leftText = "45 Energy", rightText = "Melee Range" } } } end
    if id == 888 then return { lines = { { type = 34, leftText = "Next melee and Melee Range in description" } } } end
    if id == 889 then return { lines = { { type = 0, rightText = "|cffffffff  MELEE   RANGE |r" } } } end
    if id == 890 then return { lines = { { type = 0, leftText = secret } } } end
    return { lines = { { type = 0, leftText = "30 yd range" } } }
end }
C_Spell = {
    GetSpellName = function(id)
        if id == 2973 or id == 14260 then return "Localized Raptor Strike" end
        if id == 2974 then return "Localized Wing Clip" end
    end,
    GetSpellInfo = function() return probeInfo end,
    SpellHasRange = function() return true end,
    EnableSpellRangeCheck = function(id, enabled) tracking[id] = enabled end,
    IsSpellInRange = function(_, unit)
        assert(unit == "target")
        rangeCalls = rangeCalls + 1
        if failCheck then error("unavailable") end
        return result
    end,
}
local addon = { CreateSettings = function() end }
assert(loadfile("EnhancedCombatForever/Core.lua"))("EnhancedCombatForever", addon)
local events, indicator = frames[1], frames[2]
local function emit(event, arg) events.scripts.OnEvent(events, event, arg) end
local function color(r, g, b)
    local actual = indicator.dot.color
    assert(actual[1] == r and actual[2] == g and actual[3] == b, "unexpected range color")
end
emit("ADDON_LOADED", "EnhancedCombatForever")
assert(not indicator.shown, "no nameplate should hide indicator")
byUnit.nameplate1 = frame()
local healthBar = frame()
byUnit.nameplate1.UnitFrame = { HealthBarsContainer = { healthBar = healthBar }, name = frame() }
emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(indicator.shown and indicator.parent == byUnit.nameplate1)
assert(indicator.point[2] == healthBar, "must anchor to the health bar")
assert(indicator.point[1] == "RIGHT" and indicator.point[3] == "LEFT", "must sit outside the bar's left edge")
assert(indicator.point[4] == -8 and indicator.point[5] == 0, "default gap must be eight pixels to the left")
addon.db.offsetX, addon.db.offsetY = 12, 3
addon.Refresh()
assert(indicator.point[4] == -12 and indicator.point[5] == 3, "settings must control gap and vertical offset")
addon.Reset()
color(0.55, 0.55, 0.55)
assert(rangeCalls == 0, "unconfigured indicator must not query range")
assert(not addon.db.abilitySelected and addon.db.spellID == 0)
addon.db.spellID, addon.db.abilitySelected = 75, true
addon.Refresh()
color(0.1, 1, 0.1)
result = false
emit("SPELL_RANGE_CHECK_UPDATE")
color(1, 0.1, 0.1)
result = nil
emit("SPELL_RANGE_CHECK_UPDATE")
color(0.55, 0.55, 0.55)
result = secret
emit("SPELL_RANGE_CHECK_UPDATE")
color(0.55, 0.55, 0.55)
failCheck = true
emit("SPELL_RANGE_CHECK_UPDATE")
color(0.55, 0.55, 0.55)
failCheck, result = false, true
local before = rangeCalls
indicator.scripts.OnUpdate(indicator, 0.1)
assert(rangeCalls == before, "polling must be throttled")
indicator.scripts.OnUpdate(indicator, 0.1)
assert(rangeCalls == before + 1)
color(0.1, 1, 0.1)
byUnit.nameplate2 = frame()
emit("NAME_PLATE_UNIT_ADDED", "nameplate2")
target = "nameplate2"
emit("PLAYER_TARGET_CHANGED")
assert(indicator.parent == byUnit.nameplate2, "must move to new target")
assert(indicator.point[2] == byUnit.nameplate2, "custom plates without a health bar use the plate fallback")
emit("NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(indicator.shown, "removing a different plate must not hide target")
emit("NAME_PLATE_UNIT_REMOVED", "nameplate2")
assert(not indicator.shown, "removed target plate must hide indicator")
-- Reusing a plate for another unit must not leave the previous target's dot.
target = "nameplate1"
emit("NAME_PLATE_UNIT_ADDED", "nameplate2")
assert(not indicator.shown)
emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(indicator.shown)
known = false
emit("SPELLS_CHANGED")
color(0.55, 0.55, 0.55)
assert(tracking[75] == false, "unlearned spell must stop range subscription")
known = true
addon.db.spellID = 123
addon.Refresh()
assert(tracking[123] == true)
addon.Reset()
assert(tracking[123] == false and tracking[75] == false)
assert(not addon.db.abilitySelected and addon.db.spellID == 0)
color(0.55, 0.55, 0.55)
assert(addon.db.size == 16 and addon.db.offsetX == 8)
-- Queuing Raptor Strike can report true at any distance. Never use that result.
addon.db.spellID, addon.db.abilitySelected = 14260, true
result, swingResult = true, false
local callsBeforeMelee = rangeCalls
addon.Refresh()
assert(swingTracking and tracking[14260] == nil)
color(1, 0.1, 0.1)
assert(rangeCalls == callsBeforeMelee, "Raptor Strike must bypass spell range")
swingResult = true
emit("PLAYER_SWING_RANGE_UPDATE")
color(0.1, 1, 0.1)
swingResult = nil
emit("PLAYER_SWING_RANGE_UPDATE")
color(0.55, 0.55, 0.55)
probeInfo = { spellID = 2974, minRange = 0, maxRange = 5 }
result = false
addon.Refresh()
assert(tracking[2974] == true)
color(1, 0.1, 0.1)
result = true
emit("SPELL_RANGE_CHECK_UPDATE")
color(0.1, 1, 0.1)
result = secret
emit("SPELL_RANGE_CHECK_UPDATE")
color(0.55, 0.55, 0.55)
-- No learned melee probe means unavailable swing checks must remain gray.
probeInfo = nil
addon.Refresh()
color(0.55, 0.55, 0.55)
-- Ordinary melee labels use the same swing check, with the selected spell as fallback.
addon.db.spellID = 1752
result, swingResult = true, false
addon.Refresh()
color(1, 0.1, 0.1)
swingResult = nil
result = false
emit("PLAYER_SWING_RANGE_UPDATE")
color(1, 0.1, 0.1)
result = true
emit("SPELL_RANGE_CHECK_UPDATE")
color(0.1, 1, 0.1)
assert(addon.UsesMeleeRange(889) == true, "normalize whitespace, casing, and color codes")
assert(addon.UsesMeleeRange(888) == false, "never classify from descriptions")
assert(addon.UsesMeleeRange(890) == false, "never inspect secret label text")
tooltipMissing = true
emit("SPELL_TEXT_UPDATE")
color(0.55, 0.55, 0.55)
assert(addon.UsesMeleeRange(1752) == nil)
tooltipMissing = false
emit("SPELL_TEXT_UPDATE")
color(0.1, 1, 0.1)
addon.db.spellID = 75
result = false
addon.Refresh()
assert(not swingTracking and tracking[2974] == false and tracking[75] == true)
color(1, 0.1, 0.1)
-- Dynamic mode overrides the manual choice and follows the shared rotation source.
result = false
assert(addon.CheckAbilityRange(75) == false, "ranged helper must report out of range")
result = true
assert(addon.CheckAbilityRange(75) == true)
swingResult = false
assert(addon.CheckAbilityRange(1752) == false, "melee helper must use swing reach")
swingResult = nil
result = false
assert(addon.CheckAbilityRange(1752) == false, "ordinary melee helper must use its spell fallback")
result = secret
assert(addon.CheckAbilityRange(75) == nil, "restricted range must remain unknown")
local rotationSpell
function addon.GetCurrentRotationSpell() return rotationSpell end
addon.db.dynamicIndicator = true
result = true
addon.Refresh()
color(0.55, 0.55, 0.55)
assert(addon.db.spellID == 75, "dynamic mode must preserve the manual selection")
rotationSpell = { spellID = 123 }
result = false
addon.RefreshIndicatorSource()
assert(tracking[123] == true and tracking[75] == false)
color(1, 0.1, 0.1)
rotationSpell = { spellID = 1752 }
swingResult = false
result = true
addon.RefreshIndicatorSource()
assert(swingTracking and tracking[123] == false)
color(1, 0.1, 0.1)
swingResult = true
emit("PLAYER_SWING_RANGE_UPDATE")
color(0.1, 1, 0.1)
rotationSpell = nil
addon.RefreshIndicatorSource()
color(0.55, 0.55, 0.55)
addon.db.dynamicIndicator = false
addon.Refresh()
assert(tracking[75] == true and not swingTracking)
color(0.1, 1, 0.1)
target = nil
emit("PLAYER_TARGET_CHANGED")
assert(not indicator.shown, "clearing target must hide indicator")
print("Range indicator tests passed")
