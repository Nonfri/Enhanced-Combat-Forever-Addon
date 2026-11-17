local _, addon = ...

function addon.CreateSettings()
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Enhanced Combat Forever")
    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    description:SetText("Target nameplate: green = in range, red = out of range, gray = unavailable.\nRange alone does not check facing, line of sight, resources, or cooldowns.")
    local indicators = CreateFrame("Frame", nil, panel)
    indicators:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -125)
    indicators:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    local tab = CreateFrame("Button", nil, panel, "PanelTabButtonTemplate")
    tab:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -12)
    tab:SetText("Indicators")
    PanelTemplates_TabResize(tab, 0, 130)
    PanelTemplates_SelectTab(tab)
    local dynamic = CreateFrame("CheckButton", nil, indicators, "UICheckButtonTemplate")
    dynamic:SetPoint("TOPLEFT", 12, -4)
    dynamic:SetSize(26, 26)
    local dynamicLabel = indicators:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    dynamicLabel:SetPoint("LEFT", dynamic, "RIGHT", 4, 0)
    dynamicLabel:SetText("Dynamic Indicator (use current rotation ability)")
    local manual = CreateFrame("Frame", nil, indicators)
    manual:SetPoint("TOPLEFT", indicators, "TOPLEFT", 0, -45)
    manual:SetPoint("TOPRIGHT", indicators, "TOPRIGHT", 0, -45)
    manual:SetHeight(85)
    local shared = CreateFrame("Frame", nil, indicators)
    shared:SetPoint("BOTTOMRIGHT", indicators, "BOTTOMRIGHT", 0, 0)
    local inputs = {}
    local function input(key, label, y)
        local owner = key == "spell" and manual or shared
        local text = owner:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        text:SetPoint("TOPLEFT", 16, y)
        text:SetText(label)
        local box = CreateFrame("EditBox", nil, owner, "InputBoxTemplate")
        box:SetSize(220, 24)
        box:SetPoint("TOPLEFT", 240, y + 6)
        box:SetAutoFocus(false)
        box:SetMaxLetters(100)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        inputs[key] = box
    end
    input("spell", "Ability name or spell ID", -20)
    local check = CreateFrame("Button", nil, manual, "UIPanelButtonTemplate")
    check:SetSize(120, 24)
    check:SetPoint("TOPLEFT", 16, -55)
    check:SetText("Check ability")
    local checkResult = manual:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    checkResult:SetPoint("LEFT", check, "RIGHT", 12, 0)
    checkResult:SetWidth(330)
    checkResult:SetJustifyH("LEFT")
    local function validateAbility()
        local text = inputs.spell:GetText():match("^%s*(.-)%s*$")
        local info = text ~= "" and C_Spell.GetSpellInfo(tonumber(text) or text)
        if not info then return nil, "Does not work: ability not found." end
        if not C_SpellBook.IsSpellKnown(info.spellID) then
            return nil, "Does not work: this character has not learned it."
        end
        local isMelee = addon.UsesMeleeRange(info.spellID)
        if isMelee == nil then return nil, "Tooltip data unavailable. Check ability again shortly." end
        if not isMelee and not C_Spell.SpellHasRange(info.spellID) then
            return nil, "Does not work: this ability has no range check."
        end
        if isMelee then
            return info, "Learned ability. Uses melee reach. Click Save to use it."
        end
        return info, "Learned ability with a range check. Click Save to use it."
    end
    local function checkAbility()
        local info, result = validateAbility()
        checkResult:SetText(result)
        if info then checkResult:SetTextColor(0.1, 1, 0.1)
        else checkResult:SetTextColor(1, 0.3, 0.3) end
        return info
    end
    check:SetScript("OnClick", checkAbility)
    inputs.spell:SetScript("OnTextChanged", function() checkResult:SetText("") end)
    input("size", "Dot size (8 to 48)", -20)
    input("offsetX", "Gap from bar (-200 to 200)", -60)
    input("offsetY", "Vertical offset (-200 to 200)", -100)
    local message = shared:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    message:SetPoint("TOPLEFT", 16, -190)
    message:SetWidth(460)
    message:SetJustifyH("LEFT")

    local function updateMode()
        local enabled = addon.db.dynamicIndicator == true
        dynamic:SetChecked(enabled)
        manual:SetShown(not enabled)
        shared:SetShown(not enabled)
        if enabled then
            for _, box in pairs(inputs) do box:ClearFocus() end
        end
        shared:ClearAllPoints()
        shared:SetPoint("TOPLEFT", indicators, "TOPLEFT", 0, -130)
        shared:SetPoint("BOTTOMRIGHT", indicators, "BOTTOMRIGHT", 0, 0)
        checkResult:SetText("")
        if enabled then
            message:SetText("Dynamic Indicator follows the current ability in your active rotation. No usable rotation ability means gray.")
        else
            message:SetText(addon.db.abilitySelected and "" or "Choose and save an ability to activate range colors. Until then, the indicator stays gray.")
        end
    end
    dynamic:SetScript("OnClick", function(self)
        addon.db.dynamicIndicator = self:GetChecked() == true
        addon.Refresh()
        updateMode()
    end)
    local function populate()
        inputs.spell:SetText(addon.db.spellID > 0
            and (C_Spell.GetSpellName(addon.db.spellID) or tostring(addon.db.spellID)) or "")
        for _, key in ipairs({ "size", "offsetX", "offsetY" }) do
            inputs[key]:SetText(tostring(addon.db[key]))
        end
        updateMode()
    end
    local save = CreateFrame("Button", nil, shared, "UIPanelButtonTemplate")
    save:SetSize(110, 24)
    save:SetPoint("TOPLEFT", 16, -150)
    save:SetText("Save")
    save:SetScript("OnClick", function()
        local info
        if not addon.db.dynamicIndicator then
            info = checkAbility()
            if not info then return end
        end
        local values = {}
        for _, key in ipairs({ "size", "offsetX", "offsetY" }) do
            local value = tonumber(inputs[key]:GetText())
            local minimum = key == "size" and 8 or -200
            local maximum = key == "size" and 48 or 200
            if not value or value ~= value or value < minimum or value > maximum then
                message:SetText("Enter numbers within the displayed size and offset limits.")
                return
            end
            values[key] = value
        end
        if info then
            addon.db.spellID = info.spellID
            addon.db.abilitySelected = true
        end
        for key, value in pairs(values) do addon.db[key] = value end
        for _, box in pairs(inputs) do box:ClearFocus() end
        addon.Refresh()
        if info then
            checkResult:SetText(addon.UsesMeleeRange(info.spellID)
                and "Learned ability. Melee reach check active."
                or "Learned ability with a range check. Active.")
            message:SetText("Saved. Tracking " .. info.name .. ".")
        else
            message:SetText("Saved. Dynamic Indicator follows your active rotation.")
        end
    end)
    local reset = CreateFrame("Button", nil, shared, "UIPanelButtonTemplate")
    reset:SetSize(110, 24)
    reset:SetPoint("LEFT", save, "RIGHT", 12, 0)
    reset:SetText("Reset")
    reset:SetScript("OnClick", function() addon.Reset(); populate() end)
    local rotations = addon.CreateRotationsSettings(panel)
    local rotationsTab = CreateFrame("Button", nil, panel, "PanelTabButtonTemplate")
    rotationsTab:SetPoint("LEFT", tab, "RIGHT", 4, 0)
    rotationsTab:SetText("Rotations")
    PanelTemplates_TabResize(rotationsTab, 0, 130)
    PanelTemplates_DeselectTab(rotationsTab)
    local listeners = addon.CreateListenersSettings(panel)
    local listenersTab = CreateFrame("Button", nil, panel, "PanelTabButtonTemplate")
    listenersTab:SetPoint("LEFT", rotationsTab, "RIGHT", 4, 0)
    listenersTab:SetText("Listeners")
    PanelTemplates_TabResize(listenersTab, 0, 130)
    PanelTemplates_DeselectTab(listenersTab)
    local tabs = { { tab, indicators }, { rotationsTab, rotations }, { listenersTab, listeners } }
    for _, selected in ipairs(tabs) do
        selected[1]:SetScript("OnClick", function()
            for _, entry in ipairs(tabs) do
                entry[2]:SetShown(entry == selected)
                if entry == selected then PanelTemplates_SelectTab(entry[1])
                else PanelTemplates_DeselectTab(entry[1]) end
            end
        end)
    end
    panel:SetScript("OnShow", populate)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Enhanced Combat Forever")
    Settings.RegisterAddOnCategory(category)
    SLASH_ENHANCEDCOMBATFOREVER1 = "/ecf"
    SlashCmdList.ENHANCEDCOMBATFOREVER = function() Settings.OpenToCategory(category:GetID()) end
end
