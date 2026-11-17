local addon = {}
local secret = {}
local exists, known, shot, melee = true, true, true, false
local squared, checked, fail = 49, true, false
SlashCmdList = {}
function issecretvalue(value) return value == secret end
function UnitExists() return exists end
function UnitDistanceSquared()
    if fail then error("not available") end
    return squared, checked
end
C_SpellBook = { IsSpellKnown = function() return known end }
C_Spell = { IsSpellInRange = function() return shot end }
C_SwingTimer = { IsTargetWithinSwingRange = function() return melee end }
Enum = { PlayerSwingType = { MainHand = 0 } }
local window
function CreateFrame()
    local f = { shown = true, scripts = {} }
    setmetatable(f, { __index = function() return function() end end })
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:CreateTexture() return self end
    function f:CreateFontString() return self end
    function f:SetText(value) self.text = value end
    window = f
    return f
end
assert(loadfile("EnhancedCombatForever/Debug.lua"))("EnhancedCombatForever", addon)
local function expect(fragment)
    local text = addon.DebugSample()
    assert(text:find(fragment, 1, true), text)
end
expect("Distance: 7.0 yd | Shot: in | Melee: out")
checked = false
expect("Distance: unavailable")
checked, squared = true, secret
expect("Distance: restricted")
squared, checked = 49, secret
expect("Distance: restricted")
checked, shot, melee = true, secret, nil
expect("Shot: restricted | Melee: unavailable")
shot, fail = false, true
expect("Distance: unavailable | Shot: out")
fail, known = false, false
expect("Shot: unavailable")
exists = false
expect("No readable target")
exists, known, shot, melee = true, true, true, false
SlashCmdList.ENHANCEDCOMBATFOREVERDEBUG("")
assert(window.shown and window.text:find("LIVE", 1, true), "first toggle should open live display")
SlashCmdList.ENHANCEDCOMBATFOREVERDEBUG("pause")
local frozen = window.text
shot = false
window.scripts.OnUpdate(window, 1)
assert(window.text == frozen, "pause should freeze display")
SlashCmdList.ENHANCEDCOMBATFOREVERDEBUG("resume")
assert(window.text:find("Shot: out", 1, true))
SlashCmdList.ENHANCEDCOMBATFOREVERDEBUG("")
assert(not window.shown, "second toggle should hide display")
print("Debug sample and window tests passed")
