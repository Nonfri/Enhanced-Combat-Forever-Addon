local _, addon = ...
local window, edit

local function text(value)
    if issecretvalue(value) then return "[restricted]" end
    if value == nil then return "[unavailable]" end
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return tostring(value) end
    return "[unsupported value]"
end

local function query(func, id)
    local ok, value = pcall(func, id)
    if not ok then return "[API unavailable]" end
    return text(value)
end

function addon.BuildSpellReport(identifier)
    local ok, info = pcall(C_Spell.GetSpellInfo, identifier)
    if not ok or issecretvalue(info) or type(info) ~= "table" then
        return "Ability not found or spell data unavailable. Enter an exact localized name or spell ID."
    end
    local id = info.spellID
    if issecretvalue(id) or type(id) ~= "number" then return "Spell ID unavailable or restricted." end
    local version, build, _, interface = GetBuildInfo()
    local lines = {
        "Enhanced Combat Forever - Spell inspection",
        "Client: " .. text(version) .. " / " .. text(build) .. " / Interface " .. text(interface),
    }
    for _, field in ipairs({ "name", "spellID", "iconID", "castTime", "minRange", "maxRange" }) do
        lines[#lines + 1] = field .. ": " .. text(info[field])
    end
    lines[#lines + 1] = "Learned: " .. query(C_SpellBook.IsSpellKnown, id)
    lines[#lines + 1] = "Has range check: " .. query(C_Spell.SpellHasRange, id)
    lines[#lines + 1] = "Subtext: " .. query(C_Spell.GetSpellSubtext, id)
    lines[#lines + 1] = "\nDescription:\n" .. query(C_Spell.GetSpellDescription, id)
    lines[#lines + 1] = "\nTooltip lines (raw line type; left text; right text):"
    local tooltipOK, data = pcall(C_TooltipInfo.GetSpellByID, id)
    if tooltipOK and not issecretvalue(data) and type(data) == "table"
        and not issecretvalue(data.lines) and type(data.lines) == "table" then
        for i, line in ipairs(data.lines) do
            if issecretvalue(line) or type(line) ~= "table" then
                lines[#lines + 1] = tostring(i) .. ": [unavailable or restricted]"
            else
                lines[#lines + 1] = tostring(i) .. ": type=" .. text(line.type)
                    .. " | " .. text(line.leftText) .. " | " .. text(line.rightText)
            end
        end
    else
        lines[#lines + 1] = "Tooltip unavailable or restricted."
    end
    lines[#lines + 1] = "\nBlank descriptions can mean data is still loading; run the command again."
    return table.concat(lines, "\n")
end

local function createWindow()
    window = CreateFrame("Frame", nil, UIParent)
    window:SetSize(680, 460)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local background = window:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.95)
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Spell inspection - Ctrl+A, Ctrl+C to copy")
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function() window:Hide() end)
    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", -32, 16)
    edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(620)
    edit:SetHeight(1)
    edit:SetScript("OnEscapePressed", function() edit:ClearFocus(); window:Hide() end)
    scroll:SetScrollChild(edit)
    -- Allow selecting/copying while keeping the captured report stable.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(self.report or "") end
    end)
end

function addon.ShowInspectionReport(report)
    if not window then createWindow() end
    edit.report = report
    edit:SetText(report)
    window:Show()
    edit:SetFocus()
    edit:HighlightText()
    edit:SetCursorPosition(0)
end

SLASH_ENHANCEDCOMBATFOREVERSPELL1 = "/ecfspell"
SlashCmdList.ENHANCEDCOMBATFOREVERSPELL = function(command)
    local identifier = command:match("^%s*(.-)%s*$")
    if identifier == "" then
        if not addon.db or not addon.db.abilitySelected then
            print("ECF: Enter /ecfspell <ability name or spell ID>, for example /ecfspell Raptor Strike")
            return
        end
        identifier = addon.db.spellID
    else
        identifier = tonumber(identifier) or identifier
    end
    local report = addon.BuildSpellReport(identifier)
    addon.ShowInspectionReport(report)
end
