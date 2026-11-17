local addon = {}
local secret = {}
local health, maximum, points = 250, 1000, 3
local class = "ROGUE"
function issecretvalue(value) return value == secret end
function UnitClass() return class, class, 4 end
function UnitHealth(unit, predicted) assert(unit == "player" and predicted == false); return health end
function UnitHealthMax(unit) assert(unit == "player"); return maximum end
function UnitPower() return points end
Enum = { PowerType = { Mana = 0, Rage = 1, Energy = 3, ComboPoints = 4 } }
assert(loadfile("EnhancedCombatForever/Conditions.lua"))("EnhancedCombatForever", addon)
assert(loadfile("EnhancedCombatForever/Rotations.lua"))("EnhancedCombatForever", addon)
local c = { type = "healthPercent", value = 25 }
local cases = { gt = false, lt = false, eq = true, ge = true, le = true }
for op, expected in pairs(cases) do
    c.operator = op
    assert(addon.EvaluateRotationCondition(c) == expected, "incorrect percent comparison: " .. op)
end
assert(addon.EvaluateRotationCondition({ type = "healthPercent", value = 30, operator = "lt" }))
assert(addon.EvaluateRotationCondition({ type = "healthNumber", value = 200, operator = "gt" }))
assert(not addon.EvaluateRotationCondition({ type = "healthNumber", value = 250, operator = "lt" }))
assert(addon.EvaluateRotationCondition({ type = "comboPoints", value = 3 }), "legacy combo condition must default to >=")
assert(not addon.EvaluateRotationCondition({ type = "comboPoints", value = 3, operator = "gt" }))
assert(addon.EvaluateRotationCondition({ type = "comboPoints", value = 3, operator = "eq" }))
health = secret
assert(addon.EvaluateRotationCondition(c) == nil, "restricted health cannot be used for arithmetic")
health, maximum = 100, secret
assert(addon.EvaluateRotationCondition(c) == nil)
maximum = 0
assert(addon.EvaluateRotationCondition(c) == nil, "zero maximum must not divide")
assert(addon.EvaluateRotationCondition({ type = "healthNumber", value = 100, operator = "eq" }), "raw health does not depend on maximum")
maximum = secret
function UnitHealthPercent(unit, predicted)
    assert(unit == "player" and predicted == false)
    return 70
end
assert(addon.EvaluateRotationCondition({ type = "healthPercent", value = 70, operator = "ge" }),
    "dedicated percent API must work when raw maximum health is restricted")
UnitHealthPercent = nil
local protectedPercent = 70
local function secretNumber(value) return { secret = true, value = value } end
function issecretvalue(value) return value == secret or type(value) == "table" and value.secret == true end
function CreateFrame()
    local holder = {}
    function holder:Hide() end
    function holder:CreateFontString()
        local fs = {}
        function fs:ClearText() self.text = nil end
        function fs:SetText(text)
            if text == "" then self.text = nil else self.text = text end
        end
        function fs:GetText() return self.text end
        return fs
    end
    return holder
end
C_StringUtil = { TruncateWhenZero = function(value)
    return value.value == 0 and "" or secretNumber("1")
end }
C_CurveUtil = { CreateCurve = function()
    local curve = { points = {} }
    function curve:SetType() end
    function curve:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
    return curve
end }
Enum.LuaCurveType = { Linear = 0 }
function UnitHealthPercent(_, _, curve)
    local boundary = (curve.points[2][1] + curve.points[3][1]) / 2
    return secretNumber(protectedPercent / 100 >= boundary and 100 or 0)
end
local protectedPower = { [0] = 20, [1] = 80, [3] = 50 }
function UnitPowerPercent(_, powerType, _, curve)
    local value = protectedPower[powerType]
    if not curve then return secretNumber(value) end
    local boundary = (curve.points[2][1] + curve.points[3][1]) / 2
    return secretNumber(value / 100 >= boundary and 100 or 0)
end
local protectedCases = {
    { "ge", 70, true }, { "gt", 70, false }, { "le", 70, true },
    { "lt", 70, false }, { "eq", 70, true }, { "ge", 71, false },
}
for _, case in ipairs(protectedCases) do
    assert(addon.EvaluateProtectedHealthPercentCondition({
        type = "healthPercent", operator = case[1], value = case[2],
    }) == case[3], "protected percentage comparison failed: " .. case[1])
end
assert(addon.EvaluateRotationCondition({ type = "manaPercent", operator = "le", value = 20 }))
assert(addon.EvaluateRotationCondition({ type = "ragePercent", operator = "ge", value = 80 }))
assert(addon.EvaluateRotationCondition({ type = "energyPercent", operator = "eq", value = 50 }))
assert(not addon.EvaluateRotationCondition({ type = "energyPercent", operator = "gt", value = 50 }))
local buffPresent, buffRemaining, buffProtected = true, 4, false
C_Spell = { GetSpellInfo = function(value)
    if value == "Battle Shout" or value == 6673 then return { name = "Battle Shout", spellID = 6673 } end
end }
C_UnitAuras = {
    GetPlayerAuraBySpellID = function() return buffPresent and { auraInstanceID = 9 } or nil end,
    GetAuraDuration = function()
        return {
            GetRemainingDuration = function()
                return buffProtected and secretNumber(buffRemaining) or buffRemaining
            end,
            EvaluateRemainingDuration = function(_, curve)
                local boundary = (curve.points[2][1] + curve.points[3][1]) / 2
                return secretNumber(buffRemaining >= boundary and 100 or 0)
            end,
        }
    end,
}
local buffCondition = { type = "buffRemaining", operator = "lt", value = 5 }
assert(addon.EvaluateRotationCondition(buffCondition, "Battle Shout"))
buffRemaining = 6
assert(not addon.EvaluateRotationCondition(buffCondition, "Battle Shout"))
buffRemaining, buffProtected = 4, true
assert(addon.EvaluateRotationCondition(buffCondition, "Battle Shout"), "protected buff duration must use curve gate")
buffPresent = false
assert(addon.EvaluateRotationCondition(buffCondition, "Battle Shout"), "missing buff must count as zero seconds")
for _, invalid in ipairs({
    { type = "healthPercent", value = 101 }, { type = "healthPercent", value = -1 },
    { type = "healthNumber", value = 1.5 }, { type = "healthNumber", value = math.huge },
    { type = "comboPoints", value = 6 }, { type = "healthNumber", value = 100, operator = "bad" },
}) do assert(not addon.ValidateCondition(invalid), "invalid threshold/operator accepted") end
local normalized = assert(addon.ValidateCondition({ type = "healthNumber", value = "500", operator = "lt" }))
assert(normalized.value == 500 and normalized.operator == "lt")
local copied = addon.CopyRotationEntry({ ability = "Heal", condition = normalized })
assert(copied.conditions[1].operator == "lt")
local profile = { abilities = { copied } }
assert(not addon.RotationDraftChanged(profile, { addon.CopyRotationEntry(copied) }))
local draft = addon.CopyRotationEntry(copied)
draft.conditions[1].operator = "le"
assert(addon.RotationDraftChanged(profile, { draft }), "operator edits must count as unsaved changes")
class = "HUNTER"
local choices = addon.GetConditionChoices()
local seen = {}
for _, d in ipairs(choices) do seen[d.type] = true end
assert(seen.always and seen.healthPercent and seen.healthNumber and seen.manaPercent
    and seen.ragePercent and seen.energyPercent and not seen.comboPoints)
-- Range monitor condition tests
addon.cachedRangedRange = nil
assert(addon.EvaluateRotationCondition({ type = "atRangedRange" }) == nil, "nil cache must return nil (wait)")
addon.cachedRangedRange = true
assert(addon.EvaluateRotationCondition({ type = "atRangedRange" }) == true, "cached true must pass")
addon.cachedRangedRange = false
assert(addon.EvaluateRotationCondition({ type = "atRangedRange" }) == false, "cached false must fail")
addon.cachedMeleeRange = nil
assert(addon.EvaluateRotationCondition({ type = "atMeleeRange" }) == nil, "nil cache must return nil (wait)")
addon.cachedMeleeRange = true
assert(addon.EvaluateRotationCondition({ type = "atMeleeRange" }) == true, "cached true must pass")
addon.cachedMeleeRange = false
assert(addon.EvaluateRotationCondition({ type = "atMeleeRange" }) == false, "cached false must fail")
local rangeChoices = addon.GetConditionChoices()
local rangeTypes = {}
for _, d in ipairs(rangeChoices) do rangeTypes[d.type] = true end
assert(rangeTypes.atRangedRange, "atRangedRange must appear in condition choices")
assert(rangeTypes.atMeleeRange, "atMeleeRange must appear in condition choices")
print("Range monitor condition tests passed")
print("Shared condition and numeric comparison tests passed")
