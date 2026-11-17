local _, addon = ...

local function trim(value)
    return value:match("^%s*(.-)%s*$")
end

local function profiles()
    if type(addon.db.rotationProfiles) ~= "table" then addon.db.rotationProfiles = {} end
    return addon.db.rotationProfiles
end

function addon.SupportsComboPointConditions()
    local _, class = UnitClass("player")
    return not issecretvalue(class) and (class == "ROGUE" or class == "DRUID")
end

function addon.CopyRotationEntry(entry)
    if type(entry) ~= "table" then return entry end
    return { ability = entry.ability, condition = addon.CopyCondition(entry.condition) }
end

function addon.RotationDraftChanged(profile, draft)
    if #draft ~= #profile.abilities then return true end
    for i, entry in ipairs(draft) do
        local saved = profile.abilities[i]
        local name = type(entry) == "table" and entry.ability or entry
        local savedName = type(saved) == "table" and saved.ability or saved
        if trim(name) ~= trim(savedName) then return true end
        local condition = type(entry) == "table" and entry.condition
        local savedCondition = type(saved) == "table" and saved.condition
        local kind = condition and condition.type or "always"
        local savedKind = savedCondition and savedCondition.type or "always"
        if kind ~= savedKind then return true end
        if addon.ConditionIsNumeric(kind) then
            if tonumber(condition.value) ~= tonumber(savedCondition.value) then return true end
            if addon.ConditionOperator(condition) ~= addon.ConditionOperator(savedCondition) then return true end
        end
    end
    return false
end

function addon.IsOutOfCombatCondition(kind)
    return kind == "outOfCombat" or kind == "outOfCombatToggleOn" or kind == "outOfCombatToggleOff"
end

local function toggleState(ability)
    local ok, info = pcall(C_Spell.GetSpellInfo, tonumber(ability) or ability)
    if not ok or issecretvalue(info) or type(info) ~= "table" then return nil end
    -- Prefer the stance bar's active flag for forms/Stealth, even if hidden.
    if StanceBar and StanceBar.actionButtons then
        for slot, button in pairs(StanceBar.actionButtons) do
            local formOK, _, active, _, id = pcall(GetShapeshiftFormInfo, button.index or slot)
            if formOK and not issecretvalue(id) and type(id) == "number" then
                local nameOK, name = pcall(C_Spell.GetSpellName, id)
                local matches = not issecretvalue(info.spellID) and info.spellID == id
                if not matches and nameOK and not issecretvalue(name) and not issecretvalue(info.name) then
                    matches = type(name) == "string" and name == info.name
                end
                if matches then
                    if issecretvalue(active) or type(active) ~= "boolean" then return nil end
                    return active
                end
            end
        end
    end
    local activeOK, active = pcall(C_Spell.IsActiveSpell, tonumber(ability) or ability, "player")
    if activeOK and not issecretvalue(active) and type(active) == "boolean" then return active end
end

local powerConditions = {
    manaPercent = function() return Enum.PowerType.Mana end,
    ragePercent = function() return Enum.PowerType.Rage end,
    energyPercent = function() return Enum.PowerType.Energy end,
}

function addon.EvaluateRotationCondition(condition, ability)
    if condition.type == "always" then return true end
    if condition.type == "buffRemaining" then return addon.EvaluateBuffRemainingCondition(condition, ability) end
    if condition.type == "shootToggle" then return true end
    if condition.type == "shootToggleOn" or condition.type == "shootToggleOff" then
        local active = addon.IsAutoRepeatActive and addon.IsAutoRepeatActive() or false
        if condition.type == "shootToggleOn" then return not active end
        return active
    end
    if condition.type == "healthPercent" or condition.type == "healthNumber" then
        if condition.type == "healthPercent" and type(UnitHealthPercent) == "function" then
            local percentOK, percent = pcall(UnitHealthPercent, "player", false)
            if percentOK and not issecretvalue(percent) and type(percent) == "number" then
                return addon.CompareCondition(percent, condition)
            end
            local protectedResult = addon.EvaluateProtectedHealthPercentCondition(condition)
            if protectedResult ~= nil then return protectedResult end
        end
        local ok, health = pcall(UnitHealth, "player", false)
        if not ok or issecretvalue(health) or type(health) ~= "number" then return nil end
        if condition.type == "healthPercent" then
            local maxOK, maximum = pcall(UnitHealthMax, "player")
            if not maxOK or issecretvalue(maximum) or type(maximum) ~= "number" or maximum <= 0 then return nil end
            health = health / maximum * 100
        end
        return addon.CompareCondition(health, condition)
    end
    local powerType = powerConditions[condition.type] and powerConditions[condition.type]()
    if powerType then
        if type(UnitPowerPercent) == "function" then
            local percentOK, percent = pcall(UnitPowerPercent, "player", powerType, false)
            if percentOK and not issecretvalue(percent) and type(percent) == "number" then
                return addon.CompareCondition(percent, condition)
            end
            local protectedResult = addon.EvaluateProtectedPowerPercentCondition(condition, powerType)
            if protectedResult ~= nil then return protectedResult end
        end
        return nil
    end
    if condition.type == "noTarget" then
        local ok, exists = pcall(UnitExists, "target")
        if not ok or issecretvalue(exists) or type(exists) ~= "boolean" then return nil end
        return not exists
    end
    if addon.IsOutOfCombatCondition(condition.type) then
        local ok, combat = pcall(UnitAffectingCombat, "player")
        if not ok or issecretvalue(combat) or type(combat) ~= "boolean" then return nil end
        if combat then return false end
        if condition.type == "outOfCombat" then return true end
        local active = toggleState(ability)
        if active == nil then return nil end
        if condition.type == "outOfCombatToggleOn" then return not active end
        return active
    end
    if condition.type == "inRange" then
        local ok, info = pcall(C_Spell.GetSpellInfo, tonumber(ability) or ability)
        if not ok or issecretvalue(info) or type(info) ~= "table"
            or issecretvalue(info.spellID) or type(info.spellID) ~= "number" then return nil end
        return addon.CheckAbilityRange(info.spellID)
    end
    if condition.type ~= "comboPoints" or not addon.SupportsComboPointConditions() then return false end
    local ok, points = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
    if not ok or issecretvalue(points) or type(points) ~= "number" then return nil end
    return addon.CompareCondition(points, condition)
end

function addon.AddRotationProfile(name)
    name = trim(name)
    if name == "" then return nil, "Enter a profile name." end
    for _, profile in ipairs(profiles()) do
        if profile.name:lower() == name:lower() then return nil, "A profile with this name already exists." end
    end
    local profile = { name = name, abilities = {} }
    table.insert(profiles(), profile)
    return profile
end

function addon.SaveRotationProfile(profile, abilities, skipRefresh)
    local saved = {}
    for i, ability in ipairs(abilities) do
        local conditional = type(ability) == "table"
        local name = trim(conditional and ability.ability or ability)
        if name == "" then return false, "Enter an ability name in row " .. i .. "." end
        if conditional then
            local condition, message = addon.ValidateCondition(ability.condition)
            if not condition then return false, message .. " (row " .. i .. ")." end
            saved[i] = { ability = name, condition = condition }
        else
            saved[i] = name
        end
    end
    profile.abilities = saved
    if not skipRefresh and addon.UpdateRotationHighlights then addon.UpdateRotationHighlights() end
    return true, "Saved."
end

function addon.GetActiveRotationProfile()
    for _, profile in ipairs(profiles()) do
        if profile.name == addon.db.activeRotationProfile then return profile end
    end
end

function addon.ActivateRotationProfile(profile)
    for _, saved in ipairs(profiles()) do
        if saved == profile then
            addon.db.activeRotationProfile = saved.name
            if addon.UpdateRotationHighlights then addon.UpdateRotationHighlights(true) end
            return true
        end
    end
    return false
end

function addon.CreateRotationsSettings(parent)
    local root = CreateFrame("Frame", nil, parent)
    root:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -125)
    root:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    local function button(owner, label, width)
        local b = CreateFrame("Button", nil, owner, "UIPanelButtonTemplate")
        b:SetSize(width or 130, 24)
        b:SetText(label)
        return b
    end
    local add = button(root, "Add rotation profile", 165)
    add:SetPoint("TOPLEFT", 16, -8)
    local form = CreateFrame("Frame", nil, root)
    form:SetPoint("TOPLEFT", 16, -42)
    form:SetSize(460, 28)
    local name = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    name:SetPoint("LEFT", 4, 0)
    name:SetSize(220, 24)
    name:SetAutoFocus(false)
    name:SetMaxLetters(64)
    local create = button(form, "Create", 90)
    create:SetPoint("LEFT", name, "RIGHT", 12, 0)
    local cancel = button(form, "Cancel", 90)
    cancel:SetPoint("LEFT", create, "RIGHT", 8, 0)
    form:Hide()
    local notice = root:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    notice:SetPoint("TOPLEFT", 16, -82)
    notice:SetText("Choose a condition for each ability. Numeric conditions support comparison operators.")
    local activeMessage = root:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    activeMessage:SetPoint("TOPLEFT", 16, -108)
    activeMessage:SetPoint("TOPRIGHT", -34, -108)
    activeMessage:SetJustifyH("LEFT")
    activeMessage:SetTextColor(0.1, 1, 0.1)
    local heading = root:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", activeMessage, "BOTTOMLEFT", 0, -12)
    heading:SetText("Profiles")
    local scroll = CreateFrame("ScrollFrame", nil, root, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -12)
    scroll:SetPoint("BOTTOMRIGHT", -34, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(450, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(math.max(100, width))
    end)

    local editors = {}
    local layout
    local function updateDraftStatus(editor)
        editor.status:SetText(addon.RotationDraftChanged(editor.profile, editor.draft) and "Unsaved changes." or "")
    end
    local function addEditor(profile)
        local editor = { profile = profile, draft = {}, rows = {}, expanded = false }
        for i, ability in ipairs(profile.abilities) do editor.draft[i] = addon.CopyRotationEntry(ability) end
        editor.frame = CreateFrame("Frame", nil, content)
        editor.header = button(editor.frame, "+ " .. profile.name)
        editor.header:SetPoint("TOPLEFT")
        editor.header:SetPoint("TOPRIGHT", editor.frame, "TOPRIGHT", -118, 0)
        editor.activate = button(editor.frame, "Activate", 110)
        editor.activate:SetPoint("TOPRIGHT")
        editor.activate:SetScript("OnClick", function()
            addon.ActivateRotationProfile(profile)
            layout()
        end)
        editor.header:SetScript("OnClick", function()
            editor.expanded = not editor.expanded
            layout()
        end)
        editor.body = CreateFrame("Frame", nil, editor.frame)
        editor.body:SetPoint("TOPLEFT", 8, -32)
        editor.body:SetPoint("BOTTOMRIGHT")
        editor.add = button(editor.body, "Add ability")
        editor.add:SetPoint("TOPLEFT")
        editor.status = editor.body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        editor.save = button(editor.body, "Save", 100)
        editor.status:SetPoint("LEFT", editor.save, "RIGHT", 12, 0)
        editor.status:SetWidth(280)
        editor.status:SetJustifyH("LEFT")
        editor.add:SetScript("OnClick", function()
            editor.draft[#editor.draft + 1] = { ability = "", condition = { type = "inRange" } }
            updateDraftStatus(editor)
            layout()
            editor.rows[#editor.draft].input:SetFocus()
        end)
        editor.save:SetScript("OnClick", function()
            local ok, message = addon.SaveRotationProfile(profile, editor.draft)
            editor.status:SetText(message)
            if ok then
                for i, ability in ipairs(profile.abilities) do editor.draft[i] = addon.CopyRotationEntry(ability) end
                layout()
            end
        end)
        editors[#editors + 1] = editor
    end

    local function createRow(editor, index)
        local row = CreateFrame("Frame", nil, editor.body)
        row:SetHeight(28)
        row.index = index
        row.number = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.number:SetPoint("TOPLEFT", 0, -6)
        row.number:SetWidth(26)
        row.delete = button(row, "Delete", 60)
        row.delete:SetPoint("TOPRIGHT", -4, -2)
        row.down = CreateFrame("Button", nil, row, "UIPanelScrollDownButtonTemplate")
        row.down:SetSize(24, 24)
        row.down:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
        row.up = CreateFrame("Button", nil, row, "UIPanelScrollUpButtonTemplate")
        row.up:SetSize(24, 24)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -6, 0)
        row.input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        row.input:SetPoint("LEFT", row.number, "RIGHT", 8, 0)
        row.input:SetPoint("RIGHT", row.up, "LEFT", -12, 0)
        row.input:SetHeight(24)
        row.input:SetAutoFocus(false)
        row.input:SetMaxLetters(100)
        row.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        row.input:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                local entry = editor.draft[index]
                if type(entry) == "table" then entry.ability = self:GetText()
                else editor.draft[index] = self:GetText() end
                updateDraftStatus(editor)
            end
        end)
        row.conditionLabel = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.conditionLabel:SetPoint("TOPLEFT", 34, -36)
        row.conditionLabel:SetText("Condition:")
        row.conditionControls = addon.CreateConditionControls(row,
            function()
                local entry = editor.draft[index]
                return type(entry) == "table" and entry.condition or { type = "always" }
            end,
            function(condition)
                local entry = editor.draft[index]
                local ability = type(entry) == "table" and entry.ability or entry
                if condition.type == "always" then editor.draft[index] = ability
                else editor.draft[index] = { ability = ability, condition = condition } end
            end,
            function() updateDraftStatus(editor) end, function() layout() end)
        row.conditionControls:SetPoint("LEFT", row.conditionLabel, "RIGHT", 8, 0)
        row.conditionType = row.conditionControls.dropdown
        row.threshold = row.conditionControls.value
        local function move(delta)
            local other = index + delta
            if other < 1 or other > #editor.draft then return end
            for _, entry in ipairs(editor.rows) do entry.input:ClearFocus(); entry.threshold:ClearFocus() end
            editor.draft[index], editor.draft[other] = editor.draft[other], editor.draft[index]
            updateDraftStatus(editor)
            layout()
        end
        row.up:SetScript("OnClick", function() move(-1) end)
        row.down:SetScript("OnClick", function() move(1) end)
        row.delete:SetScript("OnClick", function()
            if index > #editor.draft then return end
            for _, entry in ipairs(editor.rows) do entry.input:ClearFocus(); entry.threshold:ClearFocus() end
            table.remove(editor.draft, index)
            updateDraftStatus(editor)
            layout()
        end)
        editor.rows[index] = row
        return row
    end

    layout = function()
        local activeProfile = addon.GetActiveRotationProfile()
        activeMessage:SetText(activeProfile and ("Active profile: " .. activeProfile.name) or "No active rotation profile.")
        local y = 0
        for _, editor in ipairs(editors) do
            local rowsHeight = 0
            for _ in ipairs(editor.draft) do rowsHeight = rowsHeight + 68 end
            local height = editor.expanded and (104 + rowsHeight) or 32
            editor.frame:ClearAllPoints()
            editor.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            editor.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            editor.frame:SetHeight(height)
            editor.header:SetText((editor.expanded and "- " or "+ ") .. editor.profile.name)
            local active = addon.GetActiveRotationProfile() == editor.profile
            editor.activate:SetText(active and "Active" or "Activate")
            editor.activate:SetEnabled(not active)
            editor.body:SetShown(editor.expanded)
            for i = #editor.draft + 1, #editor.rows do editor.rows[i]:Hide() end
            if editor.expanded then
                local rowY = 32
                for i, ability in ipairs(editor.draft) do
                    local row = editor.rows[i] or createRow(editor, i)
                    local conditional = type(ability) == "table"
                    row:SetPoint("TOPLEFT", editor.body, "TOPLEFT", 0, -rowY)
                    row:SetPoint("TOPRIGHT", editor.body, "TOPRIGHT", 0, -rowY)
                    row:SetHeight(62)
                    row.number:SetText(i .. ".")
                    row.input:SetText(conditional and ability.ability or ability)
                    row.conditionControls:Refresh()
                    row.up:SetEnabled(i > 1)
                    row.down:SetEnabled(i < #editor.draft)
                    row:Show()
                    rowY = rowY + 68
                end
                editor.save:ClearAllPoints()
                editor.save:SetPoint("TOPLEFT", editor.body, "TOPLEFT", 0, -40 - rowsHeight)
            end
            y = y + height + 8
        end
        content:SetHeight(math.max(1, y))
    end

    add:SetScript("OnClick", function() form:Show(); name:SetFocus() end)
    local function cancelCreate() name:ClearFocus(); form:Hide() end
    cancel:SetScript("OnClick", cancelCreate)
    name:SetScript("OnEscapePressed", cancelCreate)
    local function createProfile()
        local profile, message = addon.AddRotationProfile(name:GetText())
        if not profile then notice:SetText(message); return end
        addEditor(profile)
        name:SetText("")
        cancelCreate()
        notice:SetText("Profile created. Select it below to add abilities.")
        layout()
    end
    create:SetScript("OnClick", createProfile)
    name:SetScript("OnEnterPressed", createProfile)
    for _, profile in ipairs(profiles()) do addEditor(profile) end
    layout()
    root:Hide()
    return root
end
