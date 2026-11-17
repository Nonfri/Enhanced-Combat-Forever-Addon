local _, addon = ...

local function trim(value)
    return value:match("^%s*(.-)%s*$")
end

local function profiles()
    if type(addon.db.rotationProfiles) ~= "table" then addon.db.rotationProfiles = {} end
    return addon.db.rotationProfiles
end

-- Migrate a saved entry from the old single-condition format to the new multi-condition format.
local function migrateEntry(entry)
    if type(entry) == "string" then
        return { ability = entry, conditions = {} }
    end
    if type(entry) == "table" and entry.condition and not entry.conditions then
        local conditions = entry.condition.type ~= "always" and { entry.condition } or {}
        return { ability = entry.ability, conditions = conditions }
    end
    return entry
end

function addon.SupportsComboPointConditions()
    local _, class = UnitClass("player")
    return not issecretvalue(class) and (class == "ROGUE" or class == "DRUID")
end

function addon.CopyRotationEntry(entry)
    entry = migrateEntry(entry)
    local conditions = {}
    for i, c in ipairs(entry.conditions or {}) do conditions[i] = addon.CopyCondition(c) end
    return { ability = entry.ability, conditions = conditions }
end

function addon.RotationDraftChanged(profile, draft)
    if #draft ~= #profile.abilities then return true end
    for i, entry in ipairs(draft) do
        local saved = migrateEntry(profile.abilities[i])
        local name = trim(type(entry) == "table" and entry.ability or entry)
        if name ~= trim(saved.ability) then return true end
        local dc = type(entry) == "table" and entry.conditions or {}
        local sc = saved.conditions or {}
        if #dc ~= #sc then return true end
        for j, condition in ipairs(dc) do
            local savedCondition = sc[j]
            if condition.type ~= savedCondition.type then return true end
            if addon.ConditionIsNumeric(condition.type) then
                if tonumber(condition.value) ~= tonumber(savedCondition.value) then return true end
                if addon.ConditionOperator(condition) ~= addon.ConditionOperator(savedCondition) then return true end
            end
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
    -- Ordering conditions: logic handled in RotationHighlights; passthrough here.
    if condition.type == "runAfterPrevious" or condition.type == "mustRunBeforeNext" then return true end
    if condition.type == "autoShotToggle" then
        -- Highlight whenever Auto Shot is not already firing.
        if addon.IsAutoShotActive and addon.IsAutoShotActive() then return false end
        return true
    end
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
    if condition.type == "atRangedRange" then return addon.cachedRangedRange end
    if condition.type == "atMeleeRange" then return addon.cachedMeleeRange end
    if condition.type ~= "comboPoints" or not addon.SupportsComboPointConditions() then return false end
    local ok, points = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
    if not ok or issecretvalue(points) or type(points) ~= "number" then return nil end
    return addon.CompareCondition(points, condition)
end

-- Evaluate all conditions for a rotation entry. Returns true/false/nil.
function addon.EvaluateRotationEntry(entry, targetReady)
    entry = migrateEntry(entry)
    local ability = entry.ability
    local conditions = entry.conditions or {}

    -- Determine if any condition makes this row target-independent.
    local independent = false
    for _, c in ipairs(conditions) do
        if c.type == "inRange" then independent = false; break end
        if c.type == "noTarget" or c.type == "healthPercent" or c.type == "healthNumber"
            or c.type == "manaPercent" or c.type == "ragePercent" or c.type == "energyPercent"
            or c.type == "buffRemaining" or c.type == "shootToggle"
            or c.type == "shootToggleOn" or c.type == "shootToggleOff" then
            independent = true
        end
    end

    if not targetReady and not independent then return false end
    if #conditions == 0 then return true end -- no conditions = always

    local result = true
    for _, c in ipairs(conditions) do
        local r = addon.EvaluateRotationCondition(c, ability)
        if r == nil then return nil end -- wait, don't skip
        if r == false then result = false end
    end
    return result
end

function addon.RotationEntryIsTargetIndependent(entry)
    entry = migrateEntry(entry)
    local conditions = entry.conditions or {}
    for _, c in ipairs(conditions) do
        if c.type == "inRange" then return false end
    end
    for _, c in ipairs(conditions) do
        if c.type == "noTarget" or c.type == "healthPercent" or c.type == "healthNumber"
            or c.type == "manaPercent" or c.type == "ragePercent" or c.type == "energyPercent"
            or c.type == "buffRemaining" or c.type == "shootToggle"
            or c.type == "shootToggleOn" or c.type == "shootToggleOff" then
            return true
        end
    end
    return false
end

function addon.RotationEntryIsShootRow(entry)
    entry = migrateEntry(entry)
    for _, c in ipairs(entry.conditions or {}) do
        if c.type == "shootToggle" or c.type == "shootToggleOff" then return true end
    end
    return false
end

function addon.GetMigratedEntry(entry)
    return migrateEntry(entry)
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
    for i, entry in ipairs(abilities) do
        entry = migrateEntry(entry)
        local name = trim(entry.ability or "")
        if name == "" then return false, "Enter an ability name in row " .. i .. "." end
        local conditions = {}
        for j, condition in ipairs(entry.conditions or {}) do
            local normalized, message = addon.ValidateCondition(condition)
            if not normalized then return false, message .. " (row " .. i .. ")." end
            conditions[j] = normalized
        end
        saved[i] = { ability = name, conditions = conditions }
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
    local activeMessage = root:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    activeMessage:SetPoint("TOPLEFT", 16, -82)
    activeMessage:SetPoint("TOPRIGHT", -34, -82)
    activeMessage:SetJustifyH("LEFT")
    activeMessage:SetTextColor(0.1, 1, 0.1)
    local heading = root:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", activeMessage, "BOTTOMLEFT", 0, -8)
    heading:SetText("Profiles")
    local scroll = CreateFrame("ScrollFrame", nil, root, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", -34, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(450, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(math.max(100, width))
    end)

    local editors = {}
    local layout
    local function updateDraftStatus(editor)
        local changed = addon.RotationDraftChanged(editor.profile, editor.draft)
        editor.status:SetText(changed and "Unsaved changes." or "")
    end

    -- Creates a condition row within an ability panel.
    local function createConditionRow(panel, condIdx)
        local row = CreateFrame("Frame", nil, panel.body)
        row:SetHeight(28)
        row.controls = addon.CreateConditionControls(row,
            function() return panel.conditions[condIdx] end,
            function(condition)
                panel.conditions[condIdx] = condition
                updateDraftStatus(panel.editor)
            end,
            function() updateDraftStatus(panel.editor) end,
            function() layout() end)
        row.controls:SetPoint("LEFT")
        local del = button(row, "Delete", 70)
        del:SetPoint("RIGHT")
        del:SetScript("OnClick", function()
            table.remove(panel.conditions, condIdx)
            updateDraftStatus(panel.editor)
            layout()
        end)
        panel.condRows[condIdx] = row
        return row
    end

    -- Creates a collapsible ability panel inside a profile editor.
    local function createAbilityPanel(editor, abilityIdx)
        local panel = {
            editor = editor,
            index = abilityIdx,
            expanded = false,
            condRows = {},
        }
        -- Seed conditions from the draft entry.
        local entry = migrateEntry(editor.draft[abilityIdx])
        panel.conditions = {}
        for i, c in ipairs(entry.conditions or {}) do panel.conditions[i] = addon.CopyCondition(c) end

        panel.frame = CreateFrame("Frame", nil, editor.body)
        -- Panel header: row number + ability name + up/down/delete.
        panel.header = button(panel.frame, "")
        panel.header:SetPoint("TOPLEFT")
        panel.header:SetPoint("TOPRIGHT", panel.frame, "TOPRIGHT", -170, 0)
        panel.up = CreateFrame("Button", nil, panel.frame, "UIPanelScrollUpButtonTemplate")
        panel.up:SetSize(24, 24)
        panel.up:SetPoint("TOPRIGHT", panel.frame, "TOPRIGHT", -134, -4)
        panel.down = CreateFrame("Button", nil, panel.frame, "UIPanelScrollDownButtonTemplate")
        panel.down:SetSize(24, 24)
        panel.down:SetPoint("LEFT", panel.up, "RIGHT", 4, 0)
        panel.delete = button(panel.frame, "Delete", 70)
        panel.delete:SetPoint("TOPRIGHT", panel.frame, "TOPRIGHT", 0, -2)

        -- Panel body (shown when expanded).
        panel.body = CreateFrame("Frame", nil, panel.frame)
        panel.body:SetPoint("TOPLEFT", 8, -34)
        panel.body:SetPoint("BOTTOMRIGHT", 0, 0)

        -- Ability name input.
        local abilityLabel = panel.body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        abilityLabel:SetPoint("TOPLEFT", 0, -8)
        abilityLabel:SetText("Ability:")
        panel.input = CreateFrame("EditBox", nil, panel.body, "InputBoxTemplate")
        panel.body.input = panel.input -- exposed for testing
        panel.input:SetPoint("LEFT", abilityLabel, "RIGHT", 8, 0)
        panel.input:SetSize(200, 24)
        panel.input:SetAutoFocus(false)
        panel.input:SetMaxLetters(100)
        panel.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        panel.input:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local entry2 = migrateEntry(editor.draft[panel.index])
            entry2.ability = self:GetText()
            editor.draft[panel.index] = entry2
            updateDraftStatus(editor)
        end)

        -- Add condition button.
        panel.addCondition = button(panel.body, "Add condition", 130)
        panel.addCondition:SetPoint("TOPLEFT", 0, -40)
        panel.addCondition:SetScript("OnClick", function()
            panel.conditions[#panel.conditions + 1] = { type = "inRange" }
            local entry2 = migrateEntry(editor.draft[panel.index])
            entry2.conditions = panel.conditions
            editor.draft[panel.index] = entry2
            updateDraftStatus(editor)
            layout()
        end)

        panel.header:SetScript("OnClick", function()
            panel.expanded = not panel.expanded
            layout()
        end)
        panel.up:SetScript("OnClick", function()
            local idx = panel.index
            local other = idx - 1
            if other < 1 then return end
            editor.draft[idx], editor.draft[other] = editor.draft[other], editor.draft[idx]
            editor.panels[idx], editor.panels[other] = editor.panels[other], editor.panels[idx]
            editor.panels[idx].index, editor.panels[other].index = idx, other
            updateDraftStatus(editor)
            layout()
        end)
        panel.down:SetScript("OnClick", function()
            local idx = panel.index
            local other = idx + 1
            if other > #editor.draft then return end
            editor.draft[idx], editor.draft[other] = editor.draft[other], editor.draft[idx]
            editor.panels[idx], editor.panels[other] = editor.panels[other], editor.panels[idx]
            editor.panels[idx].index, editor.panels[other].index = idx, other
            updateDraftStatus(editor)
            layout()
        end)
        panel.delete:SetScript("OnClick", function()
            panel.frame:Hide()
            local idx = panel.index
            table.remove(editor.draft, idx)
            table.remove(editor.panels, idx)
            for i = idx, #editor.panels do editor.panels[i].index = i end
            updateDraftStatus(editor)
            layout()
        end)

        editor.panels[abilityIdx] = panel
        return panel
    end

    local function addEditor(profile)
        local editor = { profile = profile, draft = {}, panels = {}, expanded = false }
        for i, ability in ipairs(profile.abilities) do
            editor.draft[i] = addon.CopyRotationEntry(ability)
        end
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
        editor.body.editorRef = editor -- exposed for testing

        editor.addAbility = button(editor.body, "Add ability")
        editor.addAbility:SetPoint("TOPLEFT")

        editor.status = editor.body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        editor.save = button(editor.body, "Save", 100)
        editor.status:SetPoint("LEFT", editor.save, "RIGHT", 12, 0)
        editor.status:SetWidth(260)
        editor.status:SetJustifyH("LEFT")

        editor.addAbility:SetScript("OnClick", function()
            local idx = #editor.draft + 1
            editor.draft[idx] = { ability = "", conditions = {} }
            local panel = createAbilityPanel(editor, idx)
            panel.expanded = true
            updateDraftStatus(editor)
            layout()
            panel.input:SetFocus()
        end)
        editor.save:SetScript("OnClick", function()
            -- Sync panel conditions back into draft before saving.
            for i, panel in ipairs(editor.panels) do
                local entry2 = migrateEntry(editor.draft[i])
                entry2.conditions = panel.conditions
                editor.draft[i] = entry2
            end
            local ok, message = addon.SaveRotationProfile(profile, editor.draft)
            editor.status:SetText(message)
            if ok then
                -- Reload draft from the freshly saved profile without rebuilding panel frames,
                -- so expansion state and condRows are preserved.
                for i, ability in ipairs(profile.abilities) do
                    editor.draft[i] = addon.CopyRotationEntry(ability)
                    if editor.panels[i] then
                        local e = migrateEntry(ability)
                        editor.panels[i].conditions = {}
                        for j, c in ipairs(e.conditions or {}) do
                            editor.panels[i].conditions[j] = addon.CopyCondition(c)
                        end
                    end
                end
                layout()
            end
        end)

        -- Build initial panels.
        for i in ipairs(editor.draft) do createAbilityPanel(editor, i) end
        editors[#editors + 1] = editor
    end

    layout = function()
        local activeProfile = addon.GetActiveRotationProfile()
        activeMessage:SetText(activeProfile and ("Active profile: " .. activeProfile.name) or "No active rotation profile.")
        local y = 0
        for _, editor in ipairs(editors) do
            -- Calculate total body height.
            local panelsHeight = 0
            for _, panel in ipairs(editor.panels) do
                if panel.expanded then
                    panelsHeight = panelsHeight + 144 + #panel.conditions * 34
                else
                    panelsHeight = panelsHeight + 32
                end
                panelsHeight = panelsHeight + 4
            end
            local bodyHeight = 36 + panelsHeight + 36
            local height = editor.expanded and (32 + bodyHeight) or 32

            editor.frame:ClearAllPoints()
            editor.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            editor.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            editor.frame:SetHeight(height)
            editor.header:SetText((editor.expanded and "- " or "+ ") .. editor.profile.name)
            local active = addon.GetActiveRotationProfile() == editor.profile
            editor.activate:SetText(active and "Active" or "Activate")
            editor.activate:SetEnabled(not active)
            editor.body:SetShown(editor.expanded)

            if editor.expanded then
                local panelY = 36
                for i, panel in ipairs(editor.panels) do
                    local entry = migrateEntry(editor.draft[i])
                    local abilityName = trim(entry.ability or "")
                    local condCount = #panel.conditions
                    local label = (abilityName ~= "" and abilityName or "New ability")
                        .. (condCount > 0 and (" (" .. condCount .. " condition" .. (condCount == 1 and "" or "s") .. ")") or "")
                    panel.header:SetText((panel.expanded and "- " or "+ ") .. i .. ". " .. label)
                    panel.up:SetEnabled(i > 1)
                    panel.down:SetEnabled(i < #editor.panels)

                    local panelHeight
                    if panel.expanded then
                        panelHeight = 144 + #panel.conditions * 34
                    else
                        panelHeight = 32
                    end
                    panel.frame:ClearAllPoints()
                    panel.frame:SetPoint("TOPLEFT", editor.body, "TOPLEFT", 0, -panelY)
                    panel.frame:SetPoint("TOPRIGHT", editor.body, "TOPRIGHT", 0, -panelY)
                    panel.frame:SetHeight(panelHeight)
                    panel.body:SetShown(panel.expanded)
                    panel.frame:Show()

                    if panel.expanded then
                        panel.input:SetText(entry.ability or "")
                        -- Hide extra condition rows.
                        for j = #panel.conditions + 1, #panel.condRows do
                            if panel.condRows[j] then panel.condRows[j]:Hide() end
                        end
                        -- Show/create condition rows.
                        local condY = -74
                        for j in ipairs(panel.conditions) do
                            local row = panel.condRows[j] or createConditionRow(panel, j)
                            row:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, condY)
                            row:SetPoint("TOPRIGHT", panel.body, "TOPRIGHT", 0, condY)
                            row.controls:Refresh()
                            row:Show()
                            condY = condY - 34
                        end
                        panel.addCondition:ClearAllPoints()
                        panel.addCondition:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, condY - 4)
                    end

                    panelY = panelY + panelHeight + 4
                end
                editor.save:ClearAllPoints()
                editor.save:SetPoint("TOPLEFT", editor.body, "TOPLEFT", 0, -(36 + panelsHeight + 4))
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
        if not profile then
            activeMessage:SetText(message)
            return
        end
        addEditor(profile)
        name:SetText("")
        cancelCreate()
        layout()
    end
    create:SetScript("OnClick", createProfile)
    name:SetScript("OnEnterPressed", createProfile)
    for _, profile in ipairs(profiles()) do addEditor(profile) end
    layout()
    root:Hide()
    return root
end
