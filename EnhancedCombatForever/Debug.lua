local _, addon = ...
local window, body
local history = {}
local running = false
local elapsed, clock = 0, 0
local previousKey

local function status(ok, value)
    if not ok then return "unavailable" end
    if issecretvalue(value) then return "restricted" end
    if value == nil then return "unavailable" end
    return value and "in" or "out"
end

-- Kept separate from the window so unavailable/restricted values can be tested.
function addon.DebugSample()
    local exists = UnitExists("target")
    if issecretvalue(exists) or not exists then
        return "No readable target", "no-target"
    end
    local shotOK, shot = pcall(function()
        if not C_SpellBook.IsSpellKnown(75) then return nil end
        return C_Spell.IsSpellInRange(75, "target")
    end)
    local meleeOK, melee = pcall(C_SwingTimer.IsTargetWithinSwingRange, Enum.PlayerSwingType.MainHand)
    local distanceOK, squared, checked = pcall(UnitDistanceSquared, "target")
    local distance, band = "unavailable", "unavailable"
    if distanceOK then
        if issecretvalue(checked) or issecretvalue(squared) then
            distance, band = "restricted", "restricted"
        elseif checked and type(squared) == "number" and squared >= 0 and squared < math.huge then
            local yards = math.sqrt(squared)
            distance = string.format("%.1f yd", yards)
            band = tostring(math.floor(yards))
        end
    end
    local shotText, meleeText = status(shotOK, shot), status(meleeOK, melee)
    return "Distance: " .. distance .. " | Shot: " .. shotText .. " | Melee: " .. meleeText,
        band .. ":" .. shotText .. ":" .. meleeText
end

local function render(current)
    local lines = { running and "LIVE (0.1 second samples)" or "PAUSED", current or "",
        "", "Recent changes (distance logged in 1-yard bands):" }
    for i = math.max(1, #history - 7), #history do lines[#lines + 1] = history[i] end
    lines[#lines + 1] = "\n/ecfdebug pause | resume | clear | dump\nDrag the window to move it. /ecfdebug hides/shows it."
    body:SetText(table.concat(lines, "\n"))
end

local current = ""
local function sample()
    local key
    current, key = addon.DebugSample()
    if key ~= previousKey then
        previousKey = key
        history[#history + 1] = string.format("%5.1fs  %s", clock, current)
        if #history > 60 then table.remove(history, 1) end
    end
    render(current)
end

local function createWindow()
    window = CreateFrame("Frame", nil, UIParent)
    window:SetSize(620, 310)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local background = window:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.85)
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Enhanced Combat Forever - Range Debug")
    body = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 12, -42)
    body:SetPoint("BOTTOMRIGHT", -12, 12)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    window:RegisterEvent("PLAYER_TARGET_CHANGED")
    window:SetScript("OnEvent", function()
        if running then
            history[#history + 1] = string.format("%5.1fs  Target changed", clock)
            if #history > 60 then table.remove(history, 1) end
            previousKey = nil
            sample()
        end
    end)
    window:SetScript("OnUpdate", function(_, delta)
        if not running then return end
        clock = clock + delta
        elapsed = elapsed + delta
        if elapsed >= 0.1 then
            elapsed = 0
            sample()
        end
    end)
    window:Hide()
end

SLASH_ENHANCEDCOMBATFOREVERDEBUG1 = "/ecfdebug"
SlashCmdList.ENHANCEDCOMBATFOREVERDEBUG = function(command)
    command = command:lower():match("^%s*(.-)%s*$")
    if command == "dump" then
        print("ECF range debug: recent changes (in-memory history)")
        for _, line in ipairs(history) do print(line) end
        return
    end
    if command ~= "" and command ~= "pause" and command ~= "resume" and command ~= "clear" then
        print("Usage: /ecfdebug [pause|resume|clear|dump]")
        return
    end
    if not window then createWindow() end
    if command == "pause" then
        running = false
        window:Show()
        render(current)
    elseif command == "clear" then
        history = {}
        previousKey, clock = nil, 0
        window:Show()
        render(current)
    elseif command == "resume" or not window:IsShown() then
        running, previousKey = true, nil
        window:Show()
        sample()
    else
        running = false
        window:Hide()
    end
end
