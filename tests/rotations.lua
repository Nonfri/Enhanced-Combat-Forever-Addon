-- Tests for Rotations.lua: data model functions and collapsible-panel UI.
-- Access to the editor internals via body.editorRef (set by the addon for testability).
local addon = { db = {} }
function UnitClass() return "Rogue", "ROGUE", 4 end
function issecretvalue() return false end
local objects = {}
local function object(kind, parent, template)
    local f = { kind = kind, parent = parent, template = template, scripts = {}, text = "", shown = true }
    setmetatable(f, { __index = function() return function() end end })
    function f:SetText(text) self.text = text; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end end
    function f:GetText() return self.text end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetShown(value) self.shown = value end
    function f:SetEnabled(value) self.enabled = value end
    function f:SetupMenu(generator) self.generator = generator end
    function f:CreateFontString() return object("FontString", self) end
    objects[#objects + 1] = f
    return f
end
function CreateFrame(kind, _, parent, template) return object(kind, parent, template) end
assert(loadfile("EnhancedCombatForever/Conditions.lua"))("EnhancedCombatForever", addon)
assert(loadfile("EnhancedCombatForever/Rotations.lua"))("EnhancedCombatForever", addon)

-- Helpers
local function find(kind, label, parent)
    for _, o in ipairs(objects) do
        if o.kind == kind and (not label or o.text == label) and (not parent or o.parent == parent) then
            return o
        end
    end
    error("missing control: " .. tostring(label or kind))
end
local function click(o) o.scripts.OnClick(o) end
local function typeText(o, text)
    o.text = text
    if o.scripts.OnTextChanged then o.scripts.OnTextChanged(o, true) end
end
local function chooseCondition(condRow, choice)
    local controls = condRow.controls
    local menu = {}
    function menu:CreateRadio(_, _, callback, value)
        if value == choice then self.choose = function() callback(value) end end
    end
    controls.dropdown.generator(controls.dropdown, menu)
    assert(menu.choose, "condition choice not found: " .. tostring(choice))
    menu.choose()
end

-- ---- Profile creation ----
local root = addon.CreateRotationsSettings(object("Frame"))
click(find("Button", "Add rotation profile", root))
local create = find("Button", "Create")
local profileNameInput = find("EditBox", nil, create.parent)
typeText(profileNameInput, "   ")
click(create)
assert(#addon.db.rotationProfiles == 0, "blank names must be rejected")
typeText(profileNameInput, "  Kite  ")
click(create)
assert(#addon.db.rotationProfiles == 1 and addon.db.rotationProfiles[1].name == "Kite")
typeText(profileNameInput, "kite")
click(create)
assert(#addon.db.rotationProfiles == 1, "duplicate names must be rejected")

-- ---- Activate ----
local header = find("Button", "+ Kite")
local activate = find("Button", "Activate", header.parent)
assert(activate.enabled and addon.GetActiveRotationProfile() == nil)
click(activate)
assert(addon.GetActiveRotationProfile() == addon.db.rotationProfiles[1])
assert(activate.text == "Active" and not activate.enabled, "active profile button must be disabled")
assert(header.text == "+ Kite", "activation must not expand the profile")

-- ---- Expand editor and get body reference ----
click(header)
-- editor.body is the first Frame child of editor.frame (header.parent)
local body = find("Frame", nil, header.parent)
assert(body.shown)
local editor = body.editorRef
assert(editor, "editor reference must be set on body")
local add = find("Button", "Add ability", body)

-- Helper: get the panels array in display order
local function panels() return editor.panels end

-- ---- Add first ability ----
click(add)
assert(#panels() == 1, "one panel after first add")
assert(panels()[1].expanded, "new panels must be auto-expanded")
typeText(panels()[1].input, "Auto Shot")
assert(panels()[1].up.enabled == false and panels()[1].down.enabled == false, "one panel: arrows must be disabled")

-- ---- Add second ability ----
click(add)
assert(#panels() == 2)
typeText(panels()[2].input, "  Arcane Shot  ")
assert(panels()[1].up.enabled == false and panels()[1].down.enabled == true)
assert(panels()[2].up.enabled == true and panels()[2].down.enabled == false)
assert(#addon.db.rotationProfiles[1].abilities == 0, "editing must not save early")

-- ---- Reorder: move Arcane Shot up ----
click(panels()[2].up)
-- After up, Auto Shot is at index 2 and Arcane Shot is at index 1
assert(panels()[1].input.text == "  Arcane Shot  " and panels()[2].input.text == "Auto Shot",
    "up must reorder ability inputs")

-- ---- Restore order ----
click(panels()[1].down)
assert(panels()[1].input.text == "Auto Shot", "down must restore original order")

-- ---- Collapse and re-expand preserves drafts ----
click(header)
assert(not body.shown, "clicking header must collapse profile")
click(header)
assert(body.shown and panels()[2].input.text == "  Arcane Shot  ", "collapsing must preserve drafts")

-- ---- Save with no conditions (always cast) ----
click(find("Button", "Save", body))
local profile = addon.db.rotationProfiles[1]
assert(profile.abilities[1].ability == "Auto Shot" and profile.abilities[2].ability == "Arcane Shot",
    "ability names must be trimmed and saved")
assert(type(profile.abilities[1].conditions) == "table" and #profile.abilities[1].conditions == 0,
    "no conditions added means empty conditions array")

-- ---- Failed save leaves profile intact ----
typeText(panels()[1].input, " ")
click(find("Button", "Save", body))
assert(profile.abilities[1].ability == "Auto Shot", "failed save must preserve saved profile")
typeText(panels()[1].input, "Auto Shot")

-- ---- Add third ability with a condition ----
click(add)
assert(#panels() == 3)
typeText(panels()[3].input, "Eviscerate")
-- Expand it and add a condition
assert(panels()[3].expanded, "newly added panel must be expanded")
click(panels()[3].addCondition)
assert(#panels()[3].conditions == 1 and panels()[3].conditions[1].type == "inRange",
    "new condition must default to inRange")
-- Change to comboPoints
chooseCondition(panels()[3].condRows[1], "comboPoints")
local threshold = panels()[3].condRows[1].controls.value
assert(threshold.text == "5", "comboPoints default threshold must be 5")
typeText(threshold, "0")
click(find("Button", "Save", body))
assert(#profile.abilities == 2, "invalid threshold must not partially save")
typeText(threshold, "5")

-- ---- Reorder with condition ----
click(panels()[3].up)
assert(panels()[2].input.text == "Eviscerate" and panels()[2].condRows[1].controls.value.text == "5",
    "reordering must move the entire condition with the ability")
click(find("Button", "Save", body))
assert(profile.abilities[2].ability == "Eviscerate")
assert(profile.abilities[2].conditions[1].type == "comboPoints"
    and profile.abilities[2].conditions[1].value == 5)
-- After save, panels stay expanded as they were. Panel 2 (Eviscerate) was expanded
-- before the save, so condRows are still accessible.
assert(panels()[2].condRows[1], "condRows must survive a save")

-- ---- Condition drafts must not mutate saved state ----
typeText(panels()[2].condRows[1].controls.value, "4")
assert(profile.abilities[2].conditions[1].value == 5, "condition drafts must not mutate saved state")

-- ---- Second profile and switching ----
typeText(panels()[1].input, " ")
typeText(profileNameInput, "Second")
click(create)
assert(#addon.db.rotationProfiles == 2 and addon.db.rotationProfiles[2].abilities ~= profile.abilities)
local secondHeader = find("Button", "+ Second")
local secondActivate = find("Button", "Activate", secondHeader.parent)
click(secondActivate)
assert(addon.GetActiveRotationProfile() == addon.db.rotationProfiles[2])
assert(secondActivate.text == "Active" and not secondActivate.enabled)
assert(activate.text == "Activate" and activate.enabled, "switching must re-enable the previous profile")
assert(panels()[1].input.text == " ", "activation must preserve unsaved draft edits")
assert(profile.abilities[1].ability == "Auto Shot", "activation must not save draft edits")
assert(not addon.ActivateRotationProfile({ name = "Unknown" }), "only stored profiles can be activated")

-- ---- Reopen preserves saved values ----
addon.CreateRotationsSettings(object("Frame"))
assert(profile.abilities[1].ability == "Auto Shot", "reopening must preserve saved values")
assert(addon.db.activeRotationProfile == "Second" and addon.GetActiveRotationProfile().name == "Second")

-- ---- Add inRange condition to Auto Shot ----
typeText(panels()[1].input, "Auto Shot")
click(panels()[1].addCondition)
assert(#panels()[1].conditions == 1)
chooseCondition(panels()[1].condRows[1], "inRange")
assert(panels()[1].condRows[1].controls.value == nil or not panels()[1].condRows[1].controls.value.shown,
    "range conditions should not show a threshold")
click(find("Button", "Save", body))
assert(profile.abilities[1].conditions[1].type == "inRange")

-- ---- Remove condition (delete condition row makes it always-cast) ----
-- Delete the condition row via its delete button
local condRowDel = find("Button", "Delete", panels()[1].condRows[1])
click(condRowDel)
assert(#panels()[1].conditions == 0, "deleting the only condition must leave empty conditions list")
click(find("Button", "Save", body))
assert(#profile.abilities[1].conditions == 0, "empty conditions must save correctly")

-- ---- Out-of-combat conditions ----
click(panels()[1].addCondition)
chooseCondition(panels()[1].condRows[1], "outOfCombat")
click(find("Button", "Save", body))
assert(profile.abilities[1].conditions[1].type == "outOfCombat", "out-of-combat condition must save")

local condRowDel2 = find("Button", "Delete", panels()[1].condRows[1])
click(condRowDel2)
click(find("Button", "Save", body))
assert(#profile.abilities[1].conditions == 0)

-- ---- Multi-condition: add two conditions to Eviscerate ----
-- panels()[2] is Eviscerate with the comboPoints condition from earlier. Remove it first.
click(find("Button", "Delete", panels()[2].condRows[1]))
click(find("Button", "Save", body))  -- save Eviscerate with empty conditions
assert(#profile.abilities[2].conditions == 0, "cleared Eviscerate conditions must save")
-- Now add two fresh conditions.
click(panels()[2].addCondition)
click(panels()[2].addCondition)
assert(#panels()[2].conditions == 2, "must be able to add multiple conditions")
chooseCondition(panels()[2].condRows[1], "inRange")
chooseCondition(panels()[2].condRows[2], "manaPercent")
typeText(panels()[2].condRows[2].controls.value, "50")
-- Pick an operator if the controls support it
if panels()[2].condRows[2].controls.operator and type(panels()[2].condRows[2].controls.operator.scripts) == "table" then
    -- operator menus vary; just leave at default (ge)
end
click(find("Button", "Save", body))
assert(#profile.abilities[2].conditions == 2, "two conditions must save")
assert(profile.abilities[2].conditions[1].type == "inRange")
assert(profile.abilities[2].conditions[2].type == "manaPercent")

-- ---- Dirty status detection ----
typeText(panels()[1].input, "Changed ability")
local dirtyStatus = find("FontString", "Unsaved changes.", body)
typeText(panels()[1].input, "Auto Shot")
assert(dirtyStatus.text == "", "restoring the saved name must clear dirty status")
click(panels()[1].addCondition)
assert(dirtyStatus.text == "Unsaved changes.", "adding a condition marks dirty")
click(find("Button", "Delete", panels()[1].condRows[1]))
assert(dirtyStatus.text == "", "removing the added condition clears dirty status")

-- ---- Delete ability ----
click(panels()[3].delete)
assert(#panels() == 2, "delete must remove the panel from editor.panels")
assert(not panels()[3], "deleted panel index must be gone")
assert(#profile.abilities == 3, "deletion must remain a draft until saved")
click(find("Button", "Save", body))
assert(#profile.abilities == 2 and profile.abilities[2].ability == "Eviscerate")

-- ---- Final empty profile ----
click(panels()[1].delete)
click(panels()[1].delete)
assert(#panels() == 0, "deleting all panels must empty editor.panels")
click(find("Button", "Save", body))
assert(#profile.abilities == 0, "empty profile must save correctly")

-- ---- Re-add after deletion ----
click(add)
assert(#panels() == 1 and panels()[1].input.text == "", "adding after deletion must give a clean empty panel")
assert(dirtyStatus.text == "Unsaved changes.")
click(panels()[1].delete)
assert(dirtyStatus.text == "", "adding then deleting an unsaved panel must clear dirty status")

-- ---- SaveRotationProfile: validates old single-condition format via migration shim ----
function UnitClass() return "Hunter", "HUNTER", 3 end
assert(addon.SaveRotationProfile(profile, { { ability = "Throw", condition = { type = "inRange" } } }),
    "range conditions via old format must work for non-combo-point classes")
assert(not addon.SaveRotationProfile(profile,
    { { ability = "Throw", condition = { type = "comboPoints", value = 5 } } }),
    "comboPoints condition must be rejected for non-combo-point classes")

-- ---- Migration: plain string entries load correctly ----
local migrated = addon.GetMigratedEntry("Fireball")
assert(migrated.ability == "Fireball" and type(migrated.conditions) == "table" and #migrated.conditions == 0,
    "plain string must migrate to empty conditions")

-- ---- Migration: old single-condition format ----
local migratedCond = addon.GetMigratedEntry({ ability = "Fireball", condition = { type = "inRange" } })
assert(migratedCond.ability == "Fireball" and #migratedCond.conditions == 1
    and migratedCond.conditions[1].type == "inRange",
    "old condition format must migrate to conditions array")

-- ---- Migration: old 'always' condition becomes empty conditions ----
local migratedAlways = addon.GetMigratedEntry({ ability = "Fireball", condition = { type = "always" } })
assert(#migratedAlways.conditions == 0, "old always condition must migrate to empty conditions array")

-- ---- EvaluateRotationEntry: multi-condition AND semantics ----
local combat, points, attackable = false, 0, true
function UnitAffectingCombat() return combat end
function UnitPower() return points end
function UnitClass() return "Rogue", "ROGUE", 4 end
function UnitExists() return attackable end
Enum = { PowerType = { ComboPoints = 4 } }
C_Spell = { GetSpellInfo = function() return nil end }

-- No conditions: always passes
assert(addon.EvaluateRotationEntry({ ability = "X", conditions = {} }, true) == true)

-- Single false condition
assert(addon.EvaluateRotationEntry(
    { ability = "X", conditions = { { type = "comboPoints", value = 3 } } }, true) == false,
    "unmet condition must return false")

-- Both conditions must pass
points = 5
assert(addon.EvaluateRotationEntry(
    { ability = "X", conditions = { { type = "comboPoints", value = 3 }, { type = "outOfCombat" } } }, true) == true,
    "both conditions met must return true")

-- One condition fails → entry fails
combat = true
assert(addon.EvaluateRotationEntry(
    { ability = "X", conditions = { { type = "comboPoints", value = 3 }, { type = "outOfCombat" } } }, true) == false,
    "one condition failing must return false")

-- ---- RotationEntryIsShootRow ----
assert(addon.RotationEntryIsShootRow({ ability = "Shoot", conditions = { { type = "shootToggle" } } }))
assert(not addon.RotationEntryIsShootRow({ ability = "Shoot", conditions = { { type = "inRange" } } }))
assert(not addon.RotationEntryIsShootRow({ ability = "Shoot", conditions = {} }))

print("Rotation profile and editor tests passed")
