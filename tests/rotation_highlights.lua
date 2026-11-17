local addon = { db = {} }
SlashCmdList = {}
local indicatorSpell
addon.db.dynamicIndicator = true
function addon.RefreshIndicatorSource()
    local current = addon.GetCurrentRotationSpell()
    indicatorSpell = current and current.spellID
end
local secret = {}
local points = 0
local candidateRange = true
local combat = false
local toggled = false
function UnitAffectingCombat() return combat end
function UnitClass() return "Rogue", "ROGUE", 4 end
function UnitPower() return points end
Enum = { PowerType = { ComboPoints = 4 } }
local attackable, dead = false, false
local active = { name = "Kite", abilities = { "Auto Shot", "Arcane Shot" } }
local info = {
    [75] = { spellID = 75, name = "Auto Shot" },
    [3044] = { spellID = 3044, name = "Arcane Shot" },
    [14281] = { spellID = 14281, name = "Arcane Shot" },
    [1784] = { spellID = 1784, name = "Stealth" },
}
local actionInfo = { [1] = { "spell", 75 }, [2] = { "spell", 3044 } }
local frames, overlays = {}, {}
local function frame(parent, template)
    local f = { parent = parent, shown = template ~= "ActionButtonSpellAlertTemplate", scripts = {} }
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown end
    function f:IsForbidden() return false end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetPoint() end
    function f:EnableMouse() end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:RegisterEvent() end
    local function animation() return { Play = function() end, Stop = function() end } end
    f.ProcStartAnim, f.ProcLoop = animation(), animation()
    return f
end
function CreateFrame(_, _, parent, template)
    local f = frame(parent, template)
    frames[#frames + 1] = f
    if template then overlays[parent] = f end
    return f
end
function issecretvalue(value) return value == secret end
function UnitCanAttack() return attackable end
function UnitExists() return attackable end
function UnitIsDeadOrGhost() return dead end
local _unpack = table.unpack or unpack
function GetActionInfo(action) return _unpack(actionInfo[action] or {}) end
C_Spell = {
    GetSpellInfo = function(value)
        if value == "Auto Shot" then return info[75] end
        if value == "Arcane Shot" then return info[3044] end
        if value == "Stealth" then return info[1784] end
        return info[value]
    end,
    GetSpellName = function(id) return info[id] and info[id].name end,
    IsActiveSpell = function() return toggled end,
    GetSpellCharges = function() return nil end,
    GetSpellCooldownDuration = function()
        return { GetRemainingDuration = function() return 0 end }
    end,
}
assert(loadfile("EnhancedCombatForever/Conditions.lua"))("EnhancedCombatForever", addon)
assert(loadfile("EnhancedCombatForever/Rotations.lua"))("EnhancedCombatForever", addon)
assert(loadfile("EnhancedCombatForever/Listeners.lua"))("EnhancedCombatForever", addon)
function addon.GetActiveRotationProfile() return active end
function addon.CheckAbilityRange() return candidateRange end
local first, second = frame(), frame()
first.action, second.action = 1, 2
ActionBarButtonEventsFrame = { ForEachFrame = function(_, callback) callback(first); callback(second) end }
assert(loadfile("EnhancedCombatForever/RotationHighlights.lua"))("EnhancedCombatForever", addon)
local events = frames[1]
local function emit(event, unit, spellID, hold)
    events.scripts.OnEvent(events, event, unit, "cast-guid", spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" and not hold then events.scripts.OnUpdate(events, 0.21) end
end
local function shown(button) return overlays[button] and overlays[button].shown or false end
addon.UpdateRotationHighlights()
assert(not shown(first) and not shown(second), "friendly/no target must not glow")
attackable = true
emit("PLAYER_TARGET_CHANGED")
assert(shown(first) and not shown(second), "only the first entry should glow")
assert(indicatorSpell == 75, "dynamic indicator must share the highlighted step")
emit("UNIT_SPELLCAST_SUCCEEDED", "pet", 75)
assert(shown(first), "pet casts must not advance rotation")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 3044)
assert(shown(first), "out-of-order casts must not advance rotation")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 75)
assert(not shown(first) and shown(second), "matching cast should advance")
assert(indicatorSpell == 3044, "dynamic indicator must advance with the glow after settling")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 14281)
assert(shown(first) and not shown(second), "another rank should match and final entry should loop")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 75)
emit("PLAYER_TARGET_CHANGED")
assert(shown(first) and not shown(second), "new target should restart rotation")
assert(indicatorSpell == 75)
first.SpellActivationAlert = frame()
addon.UpdateRotationHighlights()
assert(not shown(first) and first.SpellActivationAlert.shown, "native proc must remain untouched")
first.SpellActivationAlert:Hide()
addon.UpdateRotationHighlights()
assert(shown(first), "own glow should return after native proc ends")
dead = true
addon.UpdateRotationHighlights()
assert(not shown(first), "dead target must not glow")
dead = false
actionInfo[1] = { "spell", 3044 }
addon.UpdateRotationHighlights()
assert(not shown(first), "replaced action must lose glow")
actionInfo[1] = { "macro", 75, "spell" }
addon.UpdateRotationHighlights()
assert(shown(first), "spell macros should match their displayed spell")
actionInfo[1] = { "spell", secret }
addon.UpdateRotationHighlights()
assert(not shown(first), "restricted action data must be skipped")
actionInfo[1] = { "spell", 75 }
active = { name = "Other", abilities = { "Arcane Shot" } }
addon.UpdateRotationHighlights(true)
assert(not shown(first) and shown(second), "switching profiles should replace glow")
active.abilities = { "Auto Shot", "Arcane Shot" }
addon.UpdateRotationHighlights()
assert(shown(first) and not shown(second), "saving active list should restart sequence")
attackable = secret
addon.UpdateRotationHighlights()
assert(not shown(first) and not shown(second), "restricted target checks must not glow")
attackable, active = true, nil
addon.UpdateRotationHighlights()
assert(not shown(first) and not shown(second), "no active profile should clear glows")
active = { name = "Conditional", abilities = {
    { ability = "Arcane Shot", condition = { type = "comboPoints", value = 5 } },
    "Auto Shot",
} }
points = 4
addon.UpdateRotationHighlights(true)
assert(shown(first) and not shown(second), "unmet condition must skip to next ability")
points = 5
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 75)
assert(shown(second) and not shown(first), "met condition must select its ability when reached in order")
assert(indicatorSpell == 3044, "dynamic indicator must use the conditional selection")
points = 0
emit("UNIT_POWER_UPDATE", "player")
assert(shown(first) and not shown(second), "condition becoming false must move to next ability")
active = { name = "Only conditions", abilities = {
    { ability = "Arcane Shot", condition = { type = "comboPoints", value = 5 } },
} }
addon.UpdateRotationHighlights(true)
assert(not shown(first) and not shown(second) and indicatorSpell == nil, "all-false conditions must produce no selection")
points = 5
emit("UNIT_POWER_UPDATE", "player")
assert(shown(second), "power updates must reevaluate conditions")
points = secret
emit("UNIT_POWER_UPDATE", "player")
assert(not shown(first) and not shown(second) and indicatorSpell == nil, "restricted combo points must not be compared")
points = 0
active = { name = "Range condition", abilities = {
    { ability = "Auto Shot", condition = { type = "inRange" } },
    "Arcane Shot",
} }
candidateRange = false
addon.UpdateRotationHighlights(true)
assert(not shown(first) and shown(second), "out-of-range row must be skipped")
candidateRange = true
addon.UpdateRotationHighlights(true)
assert(shown(first) and not shown(second), "in-range row must be selected")
candidateRange = nil
addon.UpdateRotationHighlights()
assert(not shown(first) and not shown(second) and indicatorSpell == nil, "unknown range must wait rather than skip")
candidateRange = false
addon.UpdateRotationHighlights()
assert(shown(second), "resolved out-of-range check must move to the next row")
candidateRange = true
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 3044)
assert(shown(first), "looping must recheck the range condition")
-- Regression: success arrives with old combo points; updated points arrive later.
active = { name = "Delayed combo points", abilities = {
    { ability = "Arcane Shot", condition = { type = "comboPoints", value = 2 } },
    "Auto Shot",
} }
points = 1
addon.UpdateRotationHighlights(true)
assert(shown(first))
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 75, true)
assert(not shown(first) and not shown(second) and indicatorSpell == nil, "wait must suppress premature next-step selection")
-- Even another reader/event must not skip the finisher using stale points.
addon.GetCurrentRotationSpell()
emit("UNIT_POWER_UPDATE", "player")
events.scripts.OnUpdate(events, 0.1)
assert(not shown(first) and not shown(second))
points = 2
emit("UNIT_POWER_UPDATE", "player")
assert(not shown(first) and not shown(second), "resource event must not bypass the settling window")
events.scripts.OnUpdate(events, 0.11)
assert(shown(second) and indicatorSpell == 3044, "finisher must highlight on reaching two points, without a third builder")
-- Resetting target/profile cancels the pending wait immediately.
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 3044, true)
emit("PLAYER_TARGET_CHANGED")
assert(shown(second), "target change must cancel the old wait and restart")
active = { name = "Stealth opener", abilities = {
    { ability = "Auto Shot", condition = { type = "outOfCombat" } },
    "Arcane Shot",
} }
attackable, combat = false, false
addon.UpdateRotationHighlights(true)
assert(not shown(first) and indicatorSpell == nil, "out-of-combat rows require a target")
attackable = true
emit("PLAYER_TARGET_CHANGED")
assert(shown(first), "out-of-combat reminder should work with an enemy target")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 75)
assert(not shown(first) and shown(second), "casting reminder ability should advance")
attackable, combat = true, true
emit("PLAYER_REGEN_DISABLED")
assert(shown(second) and not shown(first), "combat must skip the out-of-combat opener")
combat = false
emit("PLAYER_REGEN_ENABLED")
assert(shown(first), "leaving combat should restart the opening reminder")
combat = secret
addon.UpdateRotationHighlights()
assert(not shown(first) and not shown(second) and indicatorSpell == nil, "unknown combat state must wait safely")
combat = false
local report = addon.BuildRotationReport()
assert(report:find("conditions=[outOfCombat] | passes=true", 1, true))
assert(report:find("Current ability: Auto Shot", 1, true))
assert(report:find("match=true", 1, true))
local stance = frame()
stance.index = 1
StanceBar = { actionButtons = { stance } }
local stanceID = 1784
local stanceActive = false
function GetShapeshiftFormInfo(slot)
    assert(slot == 1)
    return 132320, stanceActive, true, stanceID
end
active = { name = "Stance opener", abilities = {
    { ability = "Stealth", condition = { type = "outOfCombat" } }, "Arcane Shot",
} }
combat, attackable = false, true
addon.UpdateRotationHighlights(true)
assert(shown(stance) and not shown(first) and not shown(second), "Stealth on the stance bar must glow with an enemy")
assert(addon.BuildRotationReport():find("Form 1 | spell=1784 / Stealth | active=false | match=true", 1, true))
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 1784)
assert(not shown(stance), "casting stance ability must advance the rotation and clear its glow")
addon.UpdateRotationHighlights(true)
assert(shown(stance))
stance:Hide()
emit("UPDATE_SHAPESHIFT_FORMS")
assert(not shown(stance), "hidden stance button must not keep an addon glow")
stance:Show()
stanceID = secret
addon.UpdateRotationHighlights()
assert(not shown(stance), "restricted stance data must be skipped")
stanceID, combat, attackable = 1784, true, true
emit("PLAYER_REGEN_DISABLED")
assert(not shown(stance) and shown(second), "combat must skip Stealth and highlight the next action-bar ability")
active.abilities = { { ability = "Stealth", condition = { type = "outOfCombatToggleOn" } }, "Arcane Shot" }
combat, attackable, stanceActive = false, true, false
addon.UpdateRotationHighlights(true)
assert(shown(stance), "toggle-on must suggest inactive Stealth")
stanceActive = true
emit("UPDATE_SHAPESHIFT_FORM")
assert(not shown(stance), "toggle-on must stop suggesting Stealth once already stealthed")
active.abilities = { { ability = "Stealth", condition = { type = "outOfCombatToggleOff" } }, "Arcane Shot" }
addon.UpdateRotationHighlights(true)
assert(shown(stance), "toggle-off must suggest currently active Stealth")
stanceActive = false
emit("UPDATE_SHAPESHIFT_FORM")
assert(not shown(stance), "toggle-off must stop suggesting an inactive toggle")
stanceActive = secret
addon.UpdateRotationHighlights(true)
assert(not shown(stance) and indicatorSpell == nil, "restricted toggle state must wait")
combat = true
assert(addon.EvaluateRotationCondition({ type = "outOfCombatToggleOn" }, "Stealth") == false)
assert(addon.EvaluateRotationCondition({ type = "outOfCombatToggleOff" }, "Stealth") == false)
combat, StanceBar, toggled = false, nil, true
assert(addon.EvaluateRotationCondition({ type = "outOfCombatToggleOn" }, "Stealth") == false)
assert(addon.EvaluateRotationCondition({ type = "outOfCombatToggleOff" }, "Stealth") == true)
toggled = secret
assert(addon.EvaluateRotationCondition({ type = "outOfCombatToggleOff" }, "Stealth") == nil)
-- Clearing a target clears Stealth and cancels pending guidance.
StanceBar = { actionButtons = { stance } }
stanceActive, combat, attackable = false, false, true
active.abilities = { { ability = "Stealth", condition = { type = "outOfCombatToggleOn" } }, "Arcane Shot" }
emit("PLAYER_TARGET_CHANGED")
assert(shown(stance))
attackable = false
emit("PLAYER_TARGET_CHANGED")
assert(not shown(stance) and not shown(first) and not shown(second) and indicatorSpell == nil)
assert(addon.BuildRotationReport():find("Current row: 1 | Last cast row: 0", 1, true), "clearing target should reset the order")
attackable = true
emit("PLAYER_TARGET_CHANGED")
assert(shown(stance), "retargeting should start at the opening ability")
active.abilities = { { ability = "Stealth", condition = { type = "noTarget" } }, "Arcane Shot" }
attackable = false
emit("PLAYER_TARGET_CHANGED")
assert(shown(stance), "explicit No target condition should allow target-free guidance")
attackable = true
emit("PLAYER_TARGET_CHANGED")
assert(not shown(stance) and shown(second), "No target condition should skip once a target exists")
-- Listener interrupts at row two, then resumes that exact row after its cast.
active = { name = "Listener test", abilities = { "Auto Shot", "Arcane Shot" } }
combat, attackable, stanceActive = false, true, false
addon.db.listeners = {}
addon.UpdateRotationHighlights(true)
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 75)
assert(shown(second))
addon.db.listeners = { { ability = "Stealth", enabled = true,
    conditions = { { type = "outOfCombatToggleOn" } } } }
addon.UpdateRotationHighlights()
assert(shown(stance) and not shown(second) and indicatorSpell == 1784, "listener must own both glow and Dynamic Indicator")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 75)
assert(shown(stance), "unrelated casts must not advance the paused rotation")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 1784)
assert(not shown(stance) and shown(second) and indicatorSpell == 3044, "listener completion must resume row two, not advance it")
addon.UpdateRotationHighlights()
assert(shown(second), "listener must not retrigger while conditions remain true")
stanceActive = true
addon.UpdateRotationHighlights()
stanceActive = false
addon.UpdateRotationHighlights()
assert(shown(stance), "false-to-true condition transition must rearm listener")
attackable = false
emit("PLAYER_TARGET_CHANGED")
assert(not shown(stance) and indicatorSpell == nil, "clearing target must cancel a target-dependent listener")
addon.db.listeners = { { ability = "Stealth", enabled = true, conditions = {
    { type = "noTarget" }, { type = "outOfCombatToggleOn" },
} } }
addon.UpdateRotationHighlights()
assert(shown(stance), "explicit No target listener should work without a target")
local health = 800
function UnitHealth() return health end
function UnitHealthMax() return 1000 end
function UnitHealthPercent() return health / 10 end
active = { name = "Health listener", abilities = { "Auto Shot", "Arcane Shot" } }
attackable = true
addon.db.listeners = { { ability = "Stealth", enabled = true, conditions = {
    { type = "healthPercent", operator = "le", value = 25 },
    { type = "healthNumber", operator = "lt", value = 300 },
} } }
addon.UpdateRotationHighlights(true)
assert(shown(first) and not shown(stance))
health = 200
emit("UNIT_HEALTH", "player")
assert(shown(stance) and indicatorSpell == 1784, "health thresholds must interrupt immediately on player health updates")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 1784)
assert(shown(first), "health listener must resume the paused rotation")
health = 800
emit("UNIT_HEALTH", "player")
health = 100
emit("UNIT_HEALTH", "player")
assert(shown(stance), "crossing health threshold again must rearm the listener")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 1784)
health, attackable = 700, false
addon.db.listeners = { { ability = "Stealth", enabled = true, conditions = {
    { type = "healthPercent", operator = "ge", value = 70 },
} } }
addon.UpdateRotationHighlights(true)
assert(shown(stance) and indicatorSpell == 1784,
    "player-health listeners must glow at the >= boundary without a target")
local healthReport = addon.BuildRotationReport()
assert(healthReport:find("Saved listeners:", 1, true))
assert(healthReport:find("healthPercent ge 70 | passes=true", 1, true))
assert(healthReport:find("targetEligible=true", 1, true))
assert(healthReport:find("percent=70", 1, true))
assert(healthReport:find("curveProbe=%[unavailable%]"), "unsupported test client must report unavailable probe")
-- Listeners are standalone reminders; a rotation is optional.
active, attackable, health = nil, false, 700
addon.db.listeners = { { ability = "Stealth", enabled = true, conditions = {
    { type = "healthPercent", operator = "ge", value = 70 },
} } }
addon.UpdateRotationHighlights(true)
assert(shown(stance) and indicatorSpell == 1784,
    "target-independent listener must glow without an active rotation profile")
-- ---- runAfterPrevious ----
-- Clear listeners and stance bar from previous tests to isolate ordering tests.
addon.db.listeners = {}
StanceBar = nil
-- Rotation: [Auto Shot, Arcane Shot(runAfterPrevious)]
-- On a fresh target, Arcane Shot must be skipped because Auto Shot hasn't been cast yet.
active = { name = "Order test", abilities = {
    { ability = "Auto Shot", conditions = {} },
    { ability = "Arcane Shot", conditions = { { type = "runAfterPrevious" } } },
} }
attackable, combat = true, false
addon.UpdateRotationHighlights(true)
assert(shown(first) and not shown(second), "runAfterPrevious must skip row 2 on fresh target")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 75)
assert(not shown(first) and shown(second), "after casting row 1, row 2 (runAfterPrevious) must become available")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 3044)
assert(shown(first) and not shown(second), "after casting row 2 the rotation loops back to row 1")
-- runAfterPrevious on the first row always passes.
active = { name = "Order first row", abilities = {
    { ability = "Auto Shot", conditions = { { type = "runAfterPrevious" } } },
    { ability = "Arcane Shot", conditions = {} },
} }
addon.UpdateRotationHighlights(true)
assert(shown(first) and not shown(second), "runAfterPrevious on row 1 must always pass")

-- ---- mustRunBeforeNext ----
-- Rotation: [Auto Shot, Arcane Shot(mustRunBeforeNext + comboPoints>=5), Auto Shot(row 3)]
-- When row 2 conditions fail (comboPoints=0), the rotation must restart at row 1
-- instead of advancing to row 3. slot 2 stays as Arcane Shot so second only glows for row 2.
active = { name = "MustRunBeforeNext skip test", abilities = {
    { ability = "Auto Shot", conditions = {} },
    { ability = "Arcane Shot", conditions = { { type = "mustRunBeforeNext" }, { type = "comboPoints", value = 5 } } },
    { ability = "Auto Shot", conditions = {} },
} }
points = 0
addon.UpdateRotationHighlights(true)
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 75)
-- Now at row 2: comboPoints fails, mustRunBeforeNext resets to row 1 instead of advancing to row 3.
assert(shown(first) and not shown(second), "mustRunBeforeNext: failed row must restart rotation at row 1, not skip to row 3")
-- After gaining combo points, row 2 is castable.
points = 5
emit("UNIT_POWER_UPDATE", "player")
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 75)
assert(shown(second), "after re-casting row 1, mustRunBeforeNext row must be highlighted when conditions pass")
-- ---- autoShotToggle ----
-- Rotation: [Auto Shot(autoShotToggle), Arcane Shot, Auto Shot(row 3)]
-- actionInfo slot 1=Auto Shot(75), slot 2=Arcane Shot(3044).
active = { name = "Auto Shot weave", abilities = {
    { ability = "Auto Shot", conditions = { { type = "autoShotToggle" } } },
    { ability = "Arcane Shot", conditions = {} },
} }
combat, attackable = true, true
addon.UpdateRotationHighlights(true)
-- In combat, Auto Shot not running → row 1 should glow.
assert(shown(first) and not shown(second), "autoShotToggle must highlight Auto Shot when in combat and not active")
-- Start auto-repeat: profile has autoShotToggle row → autoShotActive, not shoot lock.
emit("START_AUTOREPEAT_SPELL")
-- autoShotToggle returns false when active → row 1 skipped, rotation advances to row 2.
assert(not shown(first) and shown(second), "after Auto Shot starts, rotation must advance to Arcane Shot")
-- Casting Arcane Shot advances to row 1 again, but autoShotToggle returns false → skips, wraps.
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 3044)
assert(not shown(first) and shown(second), "while Auto Shot active, Auto Shot row must stay skipped on wrap")
-- Auto Shot stops → autoShotActive clears, in combat → row 1 available again.
emit("STOP_AUTOREPEAT_SPELL")
assert(shown(first) and not shown(second), "when Auto Shot stops mid-combat, its row must become available again")
-- Out of combat: autoShotToggle still highlights when Auto Shot is not active.
combat = false
emit("PLAYER_REGEN_ENABLED")
assert(shown(first), "autoShotToggle must highlight Auto Shot outside of combat when not active")
-- Shoot profile is unaffected: START_AUTOREPEAT_SPELL still uses autoRepeatActive (Shoot lock),
-- not autoShotActive, because the profile has no autoShotToggle row.
active = { name = "Shoot profile", abilities = {
    { ability = "Arcane Shot", conditions = {} },
    { ability = "Shoot", conditions = { { type = "shootToggle" } } },
} }
combat, attackable = true, true
addon.UpdateRotationHighlights(true)
-- Advance to Shoot row.
emit("UNIT_SPELLCAST_SUCCEEDED", "player", 3044)
-- START_AUTOREPEAT_SPELL: profile has no autoShotToggle → autoRepeatActive path.
emit("START_AUTOREPEAT_SPELL")
assert(addon.IsAutoRepeatActive() and not addon.IsAutoShotActive(),
    "Shoot profile must use autoRepeatActive, not autoShotActive")
-- STOP: advances index past the shoot row back to row 1 (Arcane Shot).
emit("STOP_AUTOREPEAT_SPELL")
assert(not addon.IsAutoRepeatActive(), "STOP must clear autoRepeatActive")
assert(shown(second), "Shoot STOP must advance past shoot row; Arcane Shot must glow")
print("Rotation highlight sequence and condition tests passed")
