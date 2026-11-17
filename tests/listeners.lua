local addon = { db = {} }
local points, combat, inRange, cooldownSpell, cooldownRemaining, availableCharges = 4, false, false, nil, 0, nil
local secret = {}
function issecretvalue(v) return v == secret end
function UnitClass() return "Rogue", "ROGUE", 4 end
function UnitPower() return points end
function UnitAffectingCombat() return combat end
Enum = { PowerType = { ComboPoints = 4 } }
C_Spell = { GetSpellInfo = function(value)
    if value == "Stealth" or value == 1784 then return { name = "Stealth", spellID = 1784 } end
    if value == "Throw" or value == 2764 then return { name = "Throw", spellID = 2764 } end
end,
GetSpellCharges = function(spellID)
    if spellID == cooldownSpell and availableCharges ~= nil then return { currentCharges = availableCharges } end
end,
GetSpellCooldownDuration = function(spellID)
    return { GetRemainingDuration = function() return spellID == cooldownSpell and cooldownRemaining or 0 end }
end }
C_SpellBook = { IsSpellKnown = function() return true end }
function addon.CheckAbilityRange() return inRange end
assert(loadfile("EnhancedCombatForever/Conditions.lua"))("EnhancedCombatForever", addon)
assert(loadfile("EnhancedCombatForever/Rotations.lua"))("EnhancedCombatForever", addon)
assert(loadfile("EnhancedCombatForever/Listeners.lua"))("EnhancedCombatForever", addon)
local first = { ability = "Stealth", enabled = true, conditions = {
    { type = "comboPoints", value = 5 }, { type = "outOfCombat" },
} }
local second = { ability = "Throw", enabled = true, conditions = { { type = "inRange" } } }
addon.db.listeners = { first, second }
assert(addon.GetListenerSpell(false) == nil, "false player-state conditions must not trigger without a target")
assert(addon.GetListenerSpell(true) == nil, "all conditions must match")
points, combat = 5, true
assert(addon.GetListenerSpell(true) == nil)
combat, inRange = false, true
assert(addon.GetListenerSpell(true).spellID == 1784, "first matching listener wins")
points = 0
assert(addon.GetListenerSpell(true).spellID == 1784, "active listener must wait for its ability to be cast")
addon.CompleteCurrentListener()
assert(addon.GetListenerSpell(true).spellID == 2764, "another ready listener should take priority over resuming")
addon.CompleteCurrentListener()
assert(addon.GetListenerSpell(true) == nil, "completed listener cannot repeat while true")
points = 5
assert(addon.GetListenerSpell(true).spellID == 1784, "false conditions rearm a completed listener")
addon.ResetListenerState()
points, inRange = secret, false
assert(addon.GetListenerSpell(true) == nil, "unknown conditions cannot trigger")
addon.ResetListenerState()
points, inRange, cooldownSpell, cooldownRemaining = 5, true, 1784, 10
assert(addon.GetListenerSpell(true).spellID == 2764,
    "listener ability on cooldown must be skipped for another ready listener")
addon.ResetListenerState()
availableCharges = 1
assert(addon.GetListenerSpell(true).spellID == 1784,
    "an available charge must keep a listener ability eligible")
cooldownSpell, cooldownRemaining = nil, 0
availableCharges = nil
addon.ResetListenerState()
addon.db.listeners = { { ability = "Stealth", enabled = true, conditions = {
    { type = "healthPercent", value = 70, operator = "ge" },
} } }
function UnitHealth() return 700 end
function UnitHealthMax() return 1000 end
assert(addon.GetListenerSpell(false).spellID == 1784,
    "health listeners must be allowed without a target")
addon.ResetListenerState()
addon.db.listeners = { second }
inRange = true
assert(addon.GetListenerSpell(false) == nil, "range listeners must still require a target")
local diagnostics = addon.GetListenerDiagnostics(false)
assert(#diagnostics == 1 and diagnostics[1].targetEligible == false)
assert(diagnostics[1].cooldownReady == true)
assert(diagnostics[1].conditions[1].type == "inRange" and diagnostics[1].conditions[1].result == true)
local invalid = { ability = "Old", enabled = false, conditions = {} }
assert(not addon.SaveListener(invalid, "Stealth", {}, true))
assert(invalid.ability == "Old")
local draft = { { type = "comboPoints", value = "3" }, { type = "outOfCombat" } }
assert(addon.SaveListener(invalid, " Stealth ", draft, true))
assert(invalid.ability == "Stealth" and invalid.conditions[1].value == 3 and invalid.enabled)
draft[1].value = 5
assert(invalid.conditions[1].value == 3, "saved conditions must not alias drafts")
-- Exercise the editor's add/save/condition deletion/disable flow.
local objects = {}
local function object(kind, parent)
    local f = { kind = kind, parent = parent, scripts = {}, text = "" }
    setmetatable(f, { __index = function() return function() end end })
    function f:SetText(v) self.text = v end
    function f:GetText() return self.text end
    function f:SetChecked(v) self.checked = v end
    function f:GetChecked() return self.checked end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:SetupMenu(generator) self.generator = generator end
    function f:CreateFontString() return object("FontString", self) end
    objects[#objects + 1] = f
    return f
end
function CreateFrame(kind, _, parent) return object(kind, parent) end
addon.db.listeners = {}
local root = addon.CreateListenersSettings(object("Frame"))
local function find(kind, label, parent)
    for _, o in ipairs(objects) do
        if o.kind == kind and (not label or o.text == label) and (not parent or o.parent == parent) then return o end
    end
    error("control missing: " .. tostring(label or kind))
end
local function click(button) button.scripts.OnClick(button) end
click(find("Button", "Add listener", root))
local addCondition = find("Button", "Add condition")
local body = addCondition.parent
find("EditBox", nil, body):SetText("Throw")
click(addCondition); click(addCondition)
click(find("Button", "Save", body))
assert(#addon.db.listeners[1].conditions == 2 and addon.db.listeners[1].enabled)
local deleteCondition
for _, o in ipairs(objects) do
    if o.kind == "Button" and o.text == "Delete" and o.parent.parent == body then deleteCondition = o; break end
end
click(deleteCondition)
assert(#addon.db.listeners[1].conditions == 2, "condition deletion must stay in draft until saved")
click(find("Button", "Save", body))
assert(#addon.db.listeners[1].conditions == 1)
find("CheckButton", nil, body):SetChecked(false)
click(find("Button", "Save", body))
assert(not addon.db.listeners[1].enabled)
local row = deleteCondition.parent
local function choose(dropdown, wanted)
    local menu = {}
    function menu:CreateRadio(_, _, callback, value)
        if value == wanted then self.choose = function() callback(value) end end
    end
    dropdown.generator(dropdown, menu)
    assert(menu.choose); menu.choose()
end
choose(row.controls.dropdown, "healthPercent")
choose(row.controls.operator, "lt")
row.controls.value:SetText("35")
row.controls.value.scripts.OnTextChanged(row.controls.value, true)
click(find("Button", "Save", body))
local savedCondition = addon.db.listeners[1].conditions[1]
assert(savedCondition.type == "healthPercent" and savedCondition.operator == "lt" and savedCondition.value == 35)
print("Listener model and editor tests passed")
