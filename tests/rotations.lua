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
local root = addon.CreateRotationsSettings(object("Frame"))
local function find(kind, label, parent, template)
    for _, o in ipairs(objects) do
        if o.kind == kind and (not label or o.text == label) and (not parent or o.parent == parent)
            and (not template or o.template == template) then return o end
    end
    error("missing control: " .. tostring(label or template or kind))
end
local function click(o) o.scripts.OnClick(o) end
local function typeText(o, text) o.text = text; if o.scripts.OnTextChanged then o.scripts.OnTextChanged(o, true) end end
local function chooseCondition(row, choice)
    local menu = {}
    function menu:CreateRadio(_, _, callback, value)
        if value == choice then self.choose = function() callback(value) end end
    end
    row.conditionType.generator(row.conditionType, menu)
    assert(menu.choose, "condition choice missing")
    menu.choose()
end
click(find("Button", "Add rotation profile", root))
local create = find("Button", "Create")
local name = find("EditBox", nil, create.parent)
typeText(name, "   ")
click(create)
assert(#addon.db.rotationProfiles == 0, "blank names must be rejected")
typeText(name, "  Kite  ")
click(create)
assert(#addon.db.rotationProfiles == 1 and addon.db.rotationProfiles[1].name == "Kite")
typeText(name, "kite")
click(create)
assert(#addon.db.rotationProfiles == 1, "duplicate names must be rejected")
local header = find("Button", "+ Kite")
local activate = find("Button", "Activate", header.parent)
assert(activate.enabled and addon.GetActiveRotationProfile() == nil)
click(activate)
assert(addon.GetActiveRotationProfile() == addon.db.rotationProfiles[1])
assert(activate.text == "Active" and not activate.enabled, "active profile button must be disabled")
assert(header.text == "+ Kite", "activation must not expand the profile")
click(header)
local body = find("Frame", nil, header.parent)
assert(body.shown)
local add = find("Button", "Add ability", body)
click(add)
local rows = {}
for _, o in ipairs(objects) do
    if o.kind == "EditBox" and o.parent.parent == body and o.parent.input == o then rows[#rows + 1] = o end
end
assert(#rows == 1)
typeText(rows[1], "Auto Shot")
local up = find("Button", nil, rows[1].parent, "UIPanelScrollUpButtonTemplate")
local down = find("Button", nil, rows[1].parent, "UIPanelScrollDownButtonTemplate")
assert(not up.enabled and not down.enabled, "one row must have disabled arrows")
click(up); click(down)
assert(rows[1].text == "Auto Shot")
click(add)
rows = {}
for _, o in ipairs(objects) do
    if o.kind == "EditBox" and o.parent.parent == body and o.parent.input == o then rows[#rows + 1] = o end
end
typeText(rows[2], "  Arcane Shot  ")
assert(#addon.db.rotationProfiles[1].abilities == 0, "editing must not save early")
click(down)
assert(rows[1].text == "  Arcane Shot  " and rows[2].text == "Auto Shot", "down must reorder ability values")
click(find("Button", nil, rows[2].parent, "UIPanelScrollUpButtonTemplate"))
assert(rows[1].text == "Auto Shot", "up must reorder ability values")
click(header)
assert(not body.shown, "clicking header must collapse profile")
click(header)
assert(body.shown and rows[2].text == "  Arcane Shot  ", "collapsing must preserve drafts")
click(find("Button", "Save", body))
local profile = addon.db.rotationProfiles[1]
assert(profile.abilities[1].ability == "Auto Shot" and profile.abilities[2].ability == "Arcane Shot")
assert(profile.abilities[1].condition.type == "inRange" and profile.abilities[2].condition.type == "inRange", "new ability rows must default to in-range checks")
typeText(rows[1], " ")
click(find("Button", "Save", body))
assert(profile.abilities[1].ability == "Auto Shot", "failed save must preserve saved profile")
typeText(rows[1], "Auto Shot")
click(add)
rows = {}
for _, o in ipairs(objects) do
    if o.kind == "EditBox" and o.parent.parent == body and o.parent.input == o then rows[#rows + 1] = o end
end
assert(#rows == 3)
typeText(rows[3], "Eviscerate")
chooseCondition(rows[3].parent, "comboPoints")
local threshold = rows[3].parent.threshold
assert(threshold.text == "5")
typeText(threshold, "0")
click(find("Button", "Save", body))
assert(#profile.abilities == 2, "invalid threshold must not partially save")
typeText(threshold, "5")
click(find("Button", nil, rows[3].parent, "UIPanelScrollUpButtonTemplate"))
assert(rows[2].text == "Eviscerate" and rows[2].parent.threshold.shown, "reordering must move the entire condition")
click(find("Button", "Save", body))
assert(profile.abilities[2].ability == "Eviscerate" and profile.abilities[2].condition.value == 5)
typeText(rows[2].parent.threshold, "4")
assert(profile.abilities[2].condition.value == 5, "condition drafts must not mutate saved state")
typeText(rows[1], " ")
typeText(name, "Second")
click(create)
assert(#addon.db.rotationProfiles == 2 and addon.db.rotationProfiles[2].abilities ~= profile.abilities)
local secondHeader = find("Button", "+ Second")
local secondActivate = find("Button", "Activate", secondHeader.parent)
click(secondActivate)
assert(addon.GetActiveRotationProfile() == addon.db.rotationProfiles[2])
assert(secondActivate.text == "Active" and not secondActivate.enabled)
assert(activate.text == "Activate" and activate.enabled, "switching must re-enable the previous profile")
assert(rows[1].text == " ", "activation must preserve unsaved draft edits")
assert(profile.abilities[1].ability == "Auto Shot", "activation must not save draft edits")
assert(not addon.ActivateRotationProfile({ name = "Unknown" }), "only stored profiles can be activated")
addon.CreateRotationsSettings(object("Frame"))
assert(profile.abilities[1].ability == "Auto Shot", "reopening must preserve saved values")
assert(addon.db.activeRotationProfile == "Second" and addon.GetActiveRotationProfile().name == "Second")
-- Existing ability rows can be changed to range-conditional rows and back.

typeText(rows[1], "Auto Shot")
chooseCondition(rows[1].parent, "inRange")
assert(not rows[1].parent.threshold.shown, "range conditions should not show a combo threshold")
click(find("Button", "Save", body))
assert(profile.abilities[1].ability == "Auto Shot" and profile.abilities[1].condition.type == "inRange")
chooseCondition(rows[1].parent, "always")
click(find("Button", "Save", body))
assert(profile.abilities[1] == "Auto Shot", "Always should restore an ordinary row")
chooseCondition(rows[1].parent, "outOfCombat")
assert(not rows[1].parent.threshold.shown)
click(find("Button", "Save", body))
assert(profile.abilities[1].condition.type == "outOfCombat", "out-of-combat condition must save")
chooseCondition(rows[1].parent, "outOfCombatToggleOn")
click(find("Button", "Save", body))
assert(profile.abilities[1].condition.type == "outOfCombatToggleOn")
chooseCondition(rows[1].parent, "outOfCombatToggleOff")
click(find("Button", "Save", body))
assert(profile.abilities[1].condition.type == "outOfCombatToggleOff")
chooseCondition(rows[1].parent, "always")
click(find("Button", "Save", body))
click(rows[2].parent.delete)
assert(rows[2].text == "Arcane Shot" and rows[2].parent.number.text == "2.", "deleting a middle row must shift and renumber remaining rows")
assert(not rows[3].parent.shown, "unused pooled rows must be hidden")
assert(#profile.abilities == 3, "deletion must remain a draft until saved")
click(find("Button", "Save", body))
assert(#profile.abilities == 2 and profile.abilities[2].ability == "Arcane Shot")
typeText(rows[1], "Changed ability")
local dirtyStatus = find("FontString", "Unsaved changes.", body)
typeText(rows[1], "Auto Shot")
assert(dirtyStatus.text == "", "restoring the saved name must clear dirty status")
chooseCondition(rows[1].parent, "inRange")
assert(dirtyStatus.text == "Unsaved changes.")
chooseCondition(rows[1].parent, "always")
assert(dirtyStatus.text == "", "restoring the saved condition must clear dirty status")
click(rows[1].parent.down)
assert(dirtyStatus.text == "Unsaved changes.")
click(rows[2].parent.up)
assert(dirtyStatus.text == "", "restoring the saved order must clear dirty status")
click(rows[1].parent.down)
assert(rows[1].text == "Arcane Shot" and rows[2].text == "Auto Shot", "arrows must still work after deletion")
click(rows[2].parent.delete)
assert(not rows[1].parent.up.enabled and not rows[1].parent.down.enabled)
click(rows[1].parent.delete)
assert(not rows[1].parent.shown and not rows[2].parent.shown, "deleting the final row should leave an empty list")
click(find("Button", "Save", body))
assert(#profile.abilities == 0, "empty profile should save correctly")
click(add)
assert(rows[1].parent.shown and rows[1].text == "", "adding after deletion must reuse a clean empty row")
assert(dirtyStatus.text == "Unsaved changes.")
click(rows[1].parent.delete)
assert(dirtyStatus.text == "", "adding then deleting an unsaved row must clear dirty status")
function UnitClass() return "Hunter", "HUNTER", 3 end
assert(addon.SaveRotationProfile(profile, { { ability = "Throw", condition = { type = "inRange" } } }),
    "range conditions must work for non-combo-point classes")
assert(not addon.SaveRotationProfile(profile, { { ability = "Throw", condition = { type = "comboPoints", value = 5 } } }))
print("Rotation profile and editor tests passed")
