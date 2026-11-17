local _, addon = ...
local states = {}
local active

local function listeners()
    if type(addon.db.listeners) ~= "table" then addon.db.listeners = {} end
    return addon.db.listeners
end

function addon.ResetListenerState()
    states, active = {}, nil
end

local function conditionNeedsTarget(condition)
    return condition.type == "inRange"
end

local function allowsNoTarget(listener)
    local independent = false
    for _, condition in ipairs(listener.conditions) do
        if conditionNeedsTarget(condition) then return false end
        if condition.type == "noTarget" or condition.type == "healthPercent"
            or condition.type == "healthNumber" or condition.type == "manaPercent"
            or condition.type == "ragePercent" or condition.type == "energyPercent"
            or condition.type == "buffRemaining"
            or condition.type == "shootToggle"
            or condition.type == "shootToggleOn" or condition.type == "shootToggleOff" then
            independent = true
        end
    end
    return independent
end

function addon.ListenerAllowsNoTarget()
    return active and allowsNoTarget(active) or false
end

local function listenerAbilityReady(ability)
    local infoOK, info = pcall(C_Spell.GetSpellInfo, tonumber(ability) or ability)
    if not infoOK or issecretvalue(info) or type(info) ~= "table"
        or issecretvalue(info.spellID) or type(info.spellID) ~= "number" then return nil end

    local chargesOK, charges = pcall(C_Spell.GetSpellCharges, info.spellID)
    if chargesOK and charges ~= nil then
        if issecretvalue(charges) or type(charges) ~= "table" or issecretvalue(charges.currentCharges)
            or type(charges.currentCharges) ~= "number" then return nil end
        return charges.currentCharges > 0
    end

    local durationOK, duration = pcall(C_Spell.GetSpellCooldownDuration, info.spellID, true)
    if not durationOK or not duration or type(duration.GetRemainingDuration) ~= "function" then return nil end
    local remainingOK, remaining = pcall(duration.GetRemainingDuration, duration)
    if not remainingOK or issecretvalue(remaining) or type(remaining) ~= "number" then return nil end
    return remaining <= 0
end

function addon.GetListenerDiagnostics(targetReady)
    local diagnostics = {}
    for i, listener in ipairs(listeners()) do
        local state = states[listener]
        local item = {
            index = i,
            ability = listener.ability,
            enabled = listener.enabled == true,
            active = listener == active,
            latched = state and state.latched == true or false,
            targetEligible = targetReady or allowsNoTarget(listener),
            cooldownReady = listenerAbilityReady(listener.ability),
            conditions = {},
        }
        for conditionIndex, condition in ipairs(listener.conditions or {}) do
            local curveProbe
            if condition.type == "healthPercent" and condition.operator == "ge" then
                curveProbe = addon.ProbeHealthPercentAtLeast(tonumber(condition.value))
            elseif (condition.type == "manaPercent" or condition.type == "ragePercent"
                or condition.type == "energyPercent") and condition.operator == "ge" then
                local powerType = condition.type == "manaPercent" and Enum.PowerType.Mana
                    or condition.type == "ragePercent" and Enum.PowerType.Rage or Enum.PowerType.Energy
                curveProbe = addon.ProbePowerPercentAtLeast(powerType, tonumber(condition.value))
            end
            item.conditions[conditionIndex] = {
                type = condition.type,
                operator = addon.ConditionOperator(condition),
                value = condition.value,
                result = addon.EvaluateRotationCondition(condition, listener.ability),
                curveProbe = curveProbe,
            }
        end
        diagnostics[i] = item
    end
    return diagnostics
end

function addon.CompleteCurrentListener()
    if not active then return false end
    states[active].latched = true
    active = nil
    return true
end

function addon.CurrentListenerAbility()
    return active and active.ability
end

function addon.GetListenerSpell(targetReady)
    local saved = listeners()
    if active and (not active.enabled or (not targetReady and not allowsNoTarget(active))) then active = nil end
    if not active then
        for _, listener in ipairs(saved) do
            local state = states[listener]
            if not state or state.conditions ~= listener.conditions or state.ability ~= listener.ability then
                state = { conditions = listener.conditions, ability = listener.ability, latched = false }
                states[listener] = state
            end
            if listener.enabled and #listener.conditions > 0 then
                local passes, unknown = true, false
                for _, condition in ipairs(listener.conditions) do
                    local result = addon.EvaluateRotationCondition(condition, listener.ability)
                    if result == false then passes = false end
                    if result == nil then unknown = true end
                end
                if not passes or unknown then state.latched = false end
                local cooldownReady = listenerAbilityReady(listener.ability)
                if passes and not unknown and not state.latched and cooldownReady == true
                    and (targetReady or allowsNoTarget(listener)) then
                    active = listener
                    break
                end
            end
        end
    end
    if not active then return nil, false end
    local ok, info = pcall(C_Spell.GetSpellInfo, tonumber(active.ability) or active.ability)
    if ok and not issecretvalue(info) and type(info) == "table" then return info, true end
    return nil, true -- Listener owns the step even if spell data is temporarily unavailable.
end

function addon.SaveListener(listener, ability, conditions, enabled)
    ability = ability:match("^%s*(.-)%s*$")
    if ability == "" then return false, "Choose a learned ability." end
    local infoOK, info = pcall(C_Spell.GetSpellInfo, tonumber(ability) or ability)
    if not infoOK or not info or not C_SpellBook.IsSpellKnown(info.spellID) then return false, "Choose a learned ability." end
    if #conditions == 0 then return false, "Add at least one condition." end
    local saved = {}
    for i, condition in ipairs(conditions) do
        local normalized, message = addon.ValidateCondition(condition)
        if not normalized then return false, message end
        saved[i] = normalized
    end
    listener.ability, listener.conditions, listener.enabled = info.name, saved, enabled
    addon.ResetListenerState()
    if addon.UpdateRotationHighlights then addon.UpdateRotationHighlights() end
    return true, "Saved. All conditions must be met."
end

function addon.CreateListenersSettings(parent)
    local root = CreateFrame("Frame", nil, parent)
    root:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -125)
    root:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    local function button(owner, label, width)
        local b = CreateFrame("Button", nil, owner, "UIPanelButtonTemplate")
        b:SetSize(width or 120, 24); b:SetText(label)
        return b
    end
    local add = button(root, "Add listener")
    add:SetPoint("TOPLEFT", 16, -8)
    local description = root:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", 16, -40)
    description:SetPoint("TOPRIGHT", -34, -40); description:SetJustifyH("LEFT")
    description:SetText("All conditions must be met. First matching listener takes priority; cast its ability to resume.")
    local scroll = CreateFrame("ScrollFrame", nil, root, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -80); scroll:SetPoint("BOTTOMRIGHT", -34, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(450, 1); scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(math.max(100, width)) end)
    local editors = {}
    local layout
    local function addEditor(listener)
        local e = { listener = listener, conditions = {}, rows = {}, expanded = false }
        for i, c in ipairs(listener.conditions) do e.conditions[i] = addon.CopyCondition(c) end
        e.frame = CreateFrame("Frame", nil, content)
        e.header = button(e.frame, "+ Listener")
        e.header:SetPoint("TOPLEFT"); e.header:SetPoint("TOPRIGHT", -78, 0)
        local remove = button(e.frame, "Delete", 70); remove:SetPoint("TOPRIGHT")
        e.header:SetScript("OnClick", function() e.expanded = not e.expanded; layout() end)
        e.body = CreateFrame("Frame", nil, e.frame)
        e.body:SetPoint("TOPLEFT", 8, -32); e.body:SetPoint("BOTTOMRIGHT")
        local abilityLabel = e.body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        abilityLabel:SetPoint("TOPLEFT", 0, -10); abilityLabel:SetText("Ability:")
        e.input = CreateFrame("EditBox", nil, e.body, "InputBoxTemplate")
        e.input:SetPoint("TOPLEFT", 75, -4); e.input:SetSize(200, 24)
        e.input:SetAutoFocus(false); e.input:SetMaxLetters(100); e.input:SetText(listener.ability)
        e.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        e.enabled = CreateFrame("CheckButton", nil, e.body, "UICheckButtonTemplate")
        e.enabled:SetPoint("LEFT", e.input, "RIGHT", 12, 0); e.enabled:SetSize(26, 26); e.enabled:SetChecked(true)
        local enabledLabel = e.body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        enabledLabel:SetPoint("LEFT", e.enabled, "RIGHT", 4, 0); enabledLabel:SetText("Enabled")
        if listener.ability ~= "" then e.enabled:SetChecked(listener.enabled) end
        e.addCondition = button(e.body, "Add condition")
        e.addCondition:SetPoint("TOPLEFT", 0, -40)
        e.status = e.body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        e.status:SetWidth(290); e.status:SetJustifyH("LEFT")
        e.save = button(e.body, "Save", 90)
        e.status:SetPoint("LEFT", e.save, "RIGHT", 10, 0)
        local function changed() e.status:SetText("Unsaved changes.") end
        e.input:SetScript("OnTextChanged", function(_, userInput) if userInput then changed() end end)
        e.enabled:SetScript("OnClick", changed)
        e.addCondition:SetScript("OnClick", function()
            e.conditions[#e.conditions + 1] = { type = "inRange" }; changed(); layout()
        end)
        e.save:SetScript("OnClick", function()
            local _, message = addon.SaveListener(listener, e.input:GetText(), e.conditions, e.enabled:GetChecked() == true)
            e.status:SetText(message); e.input:ClearFocus(); layout()
        end)
        remove:SetScript("OnClick", function()
            for i, value in ipairs(listeners()) do if value == listener then table.remove(listeners(), i); break end end
            for i, value in ipairs(editors) do if value == e then table.remove(editors, i); break end end
            e.frame:Hide(); addon.ResetListenerState(); layout()
            if addon.UpdateRotationHighlights then addon.UpdateRotationHighlights() end
        end)
        editors[#editors + 1] = e
    end
    local function conditionRow(e, i)
        local row = CreateFrame("Frame", nil, e.body)
        row:SetHeight(28)
        row.controls = addon.CreateConditionControls(row,
            function() return e.conditions[i] end,
            function(condition) e.conditions[i] = condition end,
            function() e.status:SetText("Unsaved changes.") end, function() layout() end)
        row.controls:SetPoint("LEFT")
        row.dropdown, row.value = row.controls.dropdown, row.controls.value
        local remove = button(row, "Delete", 70); remove:SetPoint("RIGHT")
        remove:SetScript("OnClick", function() row.value:ClearFocus(); table.remove(e.conditions, i); e.status:SetText("Unsaved changes."); layout() end)
        e.rows[i] = row
        return row
    end
    layout = function()
        local y = 0
        for i, e in ipairs(editors) do
            local height = e.expanded and (144 + #e.conditions * 34) or 32
            e.frame:ClearAllPoints(); e.frame:SetPoint("TOPLEFT", 0, -y); e.frame:SetPoint("TOPRIGHT", 0, -y); e.frame:SetHeight(height)
            e.header:SetText((e.expanded and "- " or "+ ") .. "Listener " .. i .. ": " .. (e.listener.ability ~= "" and e.listener.ability or "Choose ability"))
            e.body:SetShown(e.expanded)
            for j = #e.conditions + 1, #e.rows do e.rows[j]:Hide() end
            if e.expanded then
                for j in ipairs(e.conditions) do
                    local row = e.rows[j] or conditionRow(e, j)
                    row:SetPoint("TOPLEFT", 0, -74 - (j - 1) * 34); row:SetPoint("TOPRIGHT", 0, -74 - (j - 1) * 34)
                    row.controls:Refresh()
                    row:Show()
                end
                e.save:ClearAllPoints(); e.save:SetPoint("TOPLEFT", 0, -82 - #e.conditions * 34)
            end
            y = y + height + 8
        end
        content:SetHeight(math.max(1, y))
    end
    add:SetScript("OnClick", function()
        local listener = { ability = "", enabled = false, conditions = {} }
        table.insert(listeners(), listener); addEditor(listener)
        editors[#editors].expanded = true; layout(); editors[#editors].input:SetFocus()
    end)
    for _, listener in ipairs(listeners()) do addEditor(listener) end
    layout(); root:Hide()
    return root
end
