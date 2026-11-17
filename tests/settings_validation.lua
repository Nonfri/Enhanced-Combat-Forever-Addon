local objects = {}
local function object(kind, parent)
    local f = { kind = kind, parent = parent, scripts = {}, text = "", shown = true }
    setmetatable(f, { __index = function() return function() end end })
    function f:SetText(text)
        self.text = text
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
    end
    function f:GetText() return self.text end
    function f:SetChecked(value) self.checked = value end
    function f:GetChecked() return self.checked end
    function f:SetShown(value) self.shown = value end
    function f:SetScript(event, callback) self.scripts[event] = callback end
    function f:CreateFontString() return object("FontString") end
    function f:GetID() return 1 end
    objects[#objects + 1] = f
    return f
end
function CreateFrame(kind, _, parent) return object(kind, parent) end
function PanelTemplates_TabResize() end
function PanelTemplates_SelectTab() end
function PanelTemplates_DeselectTab() end
Settings = {
    RegisterCanvasLayoutCategory = function(panel) return object("Category") end,
    RegisterAddOnCategory = function() end,
}
SlashCmdList = {}
local known, hasRange = true, true
C_SpellBook = { IsSpellKnown = function() return known end }
C_Spell = {
    GetSpellInfo = function(value)
        if value == "Auto Shot" or value == 75 then return { spellID = 75, name = "Auto Shot" } end
    end,
    SpellHasRange = function() return hasRange end,
    GetSpellName = function() return "Auto Shot" end,
}
local addon = { db = { spellID = 0, abilitySelected = false, size = 16, offsetX = 8, offsetY = 0 } }
function addon.UsesMeleeRange() return false end
function addon.Refresh() end
function addon.CreateRotationsSettings() return object("Frame") end
function addon.CreateListenersSettings() return object("Frame") end
function addon.Reset() addon.db.spellID = 0; addon.db.abilitySelected = false end
assert(loadfile("EnhancedCombatForever/Settings.lua"))("EnhancedCombatForever", addon)
addon.CreateSettings()
local function find(kind, text)
    for _, o in ipairs(objects) do if o.kind == kind and (not text or o.text == text) then return o end end
    error("missing " .. kind .. " " .. tostring(text))
end
local panel = find("Frame")
panel.scripts.OnShow()
local input = find("EditBox")
local check = find("Button", "Check ability")
local save = find("Button", "Save")
local function click(button) button.scripts.OnClick(button) end
local function hasText(fragment)
    for _, o in ipairs(objects) do
        if o.kind == "FontString" and o.text:find(fragment, 1, true) then return true end
    end
    return false
end
assert(input.text == "" and not addon.db.abilitySelected)
assert(input.parent.shown, "manual controls should initially be visible")
click(check)
assert(hasText("ability not found"))
input:SetText("Auto Shot")
known = false
click(check)
assert(hasText("has not learned it"))
click(save)
assert(not addon.db.abilitySelected)
known, hasRange = true, false
click(check)
assert(hasText("has no range check"))
hasRange = true
click(check)
assert(hasText("Learned ability") and not addon.db.abilitySelected, "checking must not activate selection")
click(save)
assert(addon.db.abilitySelected and addon.db.spellID == 75)
input:SetText("invalid")
assert(not hasText("Active."), "editing input must clear stale validation")
click(save)
assert(addon.db.spellID == 75 and addon.db.abilitySelected, "failed save must preserve active ability")
click(find("Button", "Reset"))
assert(not addon.db.abilitySelected and input.text == "")
local dynamic = find("CheckButton")
dynamic:SetChecked(true)
click(dynamic)
assert(addon.db.dynamicIndicator == true)
assert(not input.parent.shown, "dynamic mode should hide the manual control group")
assert(not save.parent.shown, "dynamic mode should also hide size, position, Save, Reset, and status")
click(save)
assert(not addon.db.abilitySelected, "dynamic settings must save without requiring a manual ability")
assert(hasText("Dynamic Indicator follows your active rotation"))
dynamic:SetChecked(false)
click(dynamic)
assert(addon.db.dynamicIndicator == false)
assert(input.parent.shown, "disabling dynamic mode should restore manual controls")
assert(save.parent.shown, "disabling dynamic mode should restore all remaining settings")
print("Settings validation tests passed")
