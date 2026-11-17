local _, addon = ...
local definitions = {
    { type = "always", label = "Always" },
    { type = "inRange", label = "Ability in range" },
    { type = "noTarget", label = "No target" },
    { type = "outOfCombat", label = "Out of combat" },
    { type = "outOfCombatToggleOn", label = "Out of Combat - Toggle on" },
    { type = "outOfCombatToggleOff", label = "Out of Combat - Toggle off" },
    { type = "comboPoints", label = "Combo points", numeric = true, value = 5, operator = "ge", min = 1, max = 5, integer = true, combo = true },
    { type = "healthPercent", label = "Player health (%)", numeric = true, value = 30, operator = "le", min = 0, max = 100 },
    { type = "healthNumber", label = "Player health (number)", numeric = true, value = 100, operator = "le", min = 0, integer = true },
    { type = "manaPercent", label = "Player mana (%)", numeric = true, value = 30, operator = "le", min = 0, max = 100 },
    { type = "ragePercent", label = "Player rage (%)", numeric = true, value = 30, operator = "ge", min = 0, max = 100 },
    { type = "energyPercent", label = "Player energy (%)", numeric = true, value = 30, operator = "ge", min = 0, max = 100 },
    { type = "buffRemaining", label = "Buff remaining (seconds)", numeric = true, value = 5, operator = "lt", min = 0, max = 86400 },
    { type = "shootToggle", label = "Shoot - Toggle" },
    { type = "shootToggleOn", label = "Shoot - Toggle on" },
    { type = "shootToggleOff", label = "Shoot - Toggle off" },
    { type = "runAfterPrevious", label = "Run only after previous" },
    { type = "mustRunBeforeNext", label = "Must run before next" },
}
local byType = {}
for _, definition in ipairs(definitions) do byType[definition.type] = definition end
local operators = {
    { "gt", "Greater than (>)", ">" }, { "lt", "Less than (<)", "<" },
    { "eq", "Equal to (=)", "=" }, { "ge", "Greater than or equal to (>=)", ">=" },
    { "le", "Less than or equal to (<=)", "<=" },
}
local comparisons = {
    gt = function(a, b) return a > b end, lt = function(a, b) return a < b end,
    eq = function(a, b) return a == b end, ge = function(a, b) return a >= b end,
    le = function(a, b) return a <= b end,
}
local thresholdCurves = {}
local secondsCurves = {}
local zeroScratch, checkScratch

local function newScratchText()
    local ok, holder = pcall(CreateFrame, "Frame")
    if not ok or not holder then return nil end
    holder:Hide()
    local fontOK, fontString = pcall(holder.CreateFontString, holder, nil, "BACKGROUND", "GameFontNormal")
    if not fontOK or not fontString then return nil end
    return fontString
end

local function textReadbackWorks()
    if checkScratch == nil then checkScratch = newScratchText() or false end
    if not checkScratch then return false end
    local ok, value = pcall(function()
        if checkScratch.ClearText then checkScratch:ClearText() end
        checkScratch:SetText("1")
        return checkScratch:GetText()
    end)
    return ok and value == "1"
end

local function secretZero(value)
    if value == nil then return nil end
    if not issecretvalue(value) then
        if type(value) == "number" then return value == 0 end
        return nil
    end
    if not C_StringUtil or not C_StringUtil.TruncateWhenZero then return nil end
    if zeroScratch == nil then zeroScratch = newScratchText() or false end
    if not zeroScratch then return nil end
    local ok, text = pcall(function()
        if zeroScratch.ClearText then zeroScratch:ClearText() end
        zeroScratch:SetText(C_StringUtil.TruncateWhenZero(value) or "")
        return zeroScratch:GetText()
    end)
    if not ok then return nil end
    if text then return false end
    if not textReadbackWorks() then return nil end
    return true
end

local function getAtLeastCurve(threshold)
    local key = math.floor(threshold * 10 + 0.5) / 10
    if thresholdCurves[key] ~= nil then return thresholdCurves[key] or nil end
    local curve
    local ok = pcall(function()
        curve = C_CurveUtil.CreateCurve()
        curve:SetType(Enum.LuaCurveType.Linear)
        local point = math.max(0.002, math.min(0.998, key / 100))
        curve:AddPoint(0, 0)
        curve:AddPoint(math.max(0, point - 0.001), 0)
        curve:AddPoint(math.min(1, point + 0.001), 100)
        curve:AddPoint(1, 100)
    end)
    thresholdCurves[key] = ok and curve or false
    return thresholdCurves[key] or nil
end

local function getAtLeastSecondsCurve(threshold)
    local key = math.floor(threshold * 10 + 0.5) / 10
    if secondsCurves[key] ~= nil then return secondsCurves[key] or nil end
    local curve
    local ok = pcall(function()
        curve = C_CurveUtil.CreateCurve()
        curve:SetType(Enum.LuaCurveType.Linear)
        local point = math.max(0.002, key)
        local epsilon = 0.001
        curve:AddPoint(0, 0)
        curve:AddPoint(math.max(0, point - epsilon), 0)
        curve:AddPoint(math.min(86400, point + epsilon), 100)
        curve:AddPoint(86400, 100)
    end)
    secondsCurves[key] = ok and curve or false
    return secondsCurves[key] or nil
end

-- Experimental diagnostic only. The live client decides whether its secret-value
-- and FontString access rules allow a readable threshold verdict.
function addon.ProbeHealthPercentAtLeast(threshold)
    if type(threshold) ~= "number" or threshold < 0 or threshold > 100
        or not C_CurveUtil or not C_CurveUtil.CreateCurve or not UnitHealthPercent then return nil end
    local curve = getAtLeastCurve(threshold)
    if not curve then return nil end
    local ok, result = pcall(UnitHealthPercent, "player", false, curve)
    if not ok or result == nil then return nil end
    local zero = secretZero(result)
    if zero == nil then return nil end
    return not zero
end

function addon.ProbePowerPercentAtLeast(powerType, threshold)
    if type(powerType) ~= "number" or type(threshold) ~= "number" or threshold < 0 or threshold > 100
        or not C_CurveUtil or not C_CurveUtil.CreateCurve or not UnitPowerPercent then return nil end
    local curve = getAtLeastCurve(threshold)
    if not curve then return nil end
    local ok, result = pcall(UnitPowerPercent, "player", powerType, false, curve)
    if not ok or result == nil then return nil end
    local zero = secretZero(result)
    if zero == nil then return nil end
    return not zero
end

local function evaluateProtectedPercentCondition(condition, probe)
    local normalized = addon.ValidateCondition(condition)
    if not normalized then return nil end
    local threshold, operator = normalized.value, normalized.operator
    if operator == "ge" and threshold == 0 then return true end
    if operator == "lt" and threshold == 0 then return false end
    if operator == "gt" and threshold == 100 then return false end
    if operator == "le" and threshold == 100 then return true end

    local atThreshold = probe(threshold)
    if atThreshold == nil then return nil end
    if operator == "ge" then return atThreshold end
    if operator == "lt" then return not atThreshold end

    -- Percentage thresholds are stored at 0.1% resolution. Testing the next
    -- tenth makes >, <=, and = deterministic without revealing exact health.
    local nextThreshold = math.min(100, threshold + 0.1)
    local atNext = probe(nextThreshold)
    if atNext == nil then return nil end
    if operator == "gt" then return atNext end
    if operator == "le" then return not atNext end
    return atThreshold and not atNext
end


function addon.EvaluateProtectedHealthPercentCondition(condition)
    if not condition or condition.type ~= "healthPercent" then return nil end
    return evaluateProtectedPercentCondition(condition, addon.ProbeHealthPercentAtLeast)
end

function addon.EvaluateProtectedPowerPercentCondition(condition, powerType)
    return evaluateProtectedPercentCondition(condition, function(threshold)
        return addon.ProbePowerPercentAtLeast(powerType, threshold)
    end)
end

local function probeDurationAtLeast(duration, threshold)
    if not duration or type(duration.EvaluateRemainingDuration) ~= "function" then return nil end
    local curve = getAtLeastSecondsCurve(threshold)
    if not curve then return nil end
    local ok, result = pcall(duration.EvaluateRemainingDuration, duration, curve)
    if not ok or result == nil then return nil end
    local zero = secretZero(result)
    if zero == nil then return nil end
    return not zero
end

local function evaluateProtectedSecondsCondition(condition, duration)
    local normalized = addon.ValidateCondition(condition)
    if not normalized or normalized.type ~= "buffRemaining" then return nil end
    local threshold, operator = normalized.value, normalized.operator
    if operator == "ge" and threshold == 0 then return true end
    if operator == "lt" and threshold == 0 then return false end
    local atThreshold = probeDurationAtLeast(duration, threshold)
    if atThreshold == nil then return nil end
    if operator == "ge" then return atThreshold end
    if operator == "lt" then return not atThreshold end
    local atNext = probeDurationAtLeast(duration, math.min(86400, threshold + 0.1))
    if atNext == nil then return nil end
    if operator == "gt" then return atNext end
    if operator == "le" then return not atNext end
    return atThreshold and not atNext
end

function addon.EvaluateBuffRemainingCondition(condition, ability)
    local infoOK, info = pcall(C_Spell.GetSpellInfo, tonumber(ability) or ability)
    if not infoOK or issecretvalue(info) or type(info) ~= "table"
        or issecretvalue(info.spellID) or type(info.spellID) ~= "number" then return nil end
    local auraOK, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, info.spellID)
    if not auraOK or issecretvalue(aura) then return nil end
    if aura == nil then return addon.CompareCondition(0, condition) end
    if type(aura) ~= "table" or issecretvalue(aura.auraInstanceID)
        or type(aura.auraInstanceID) ~= "number" then return nil end
    local durationOK, duration = pcall(C_UnitAuras.GetAuraDuration, "player", aura.auraInstanceID)
    if not durationOK or not duration or issecretvalue(duration) then return nil end
    local remainingOK, remaining = pcall(duration.GetRemainingDuration, duration)
    if remainingOK and not issecretvalue(remaining) and type(remaining) == "number" then
        return addon.CompareCondition(remaining, condition)
    end
    return evaluateProtectedSecondsCondition(condition, duration)
end


function addon.GetConditionChoices()
    local choices = {}
    for _, d in ipairs(definitions) do
        if not d.combo or addon.SupportsComboPointConditions() then choices[#choices + 1] = d end
    end
    return choices
end

function addon.CopyCondition(c)
    return { type = c.type, value = c.value, operator = c.operator }
end

function addon.NewCondition(kind)
    local d = byType[kind]
    return { type = kind, value = d and d.value, operator = d and d.operator }
end

function addon.ConditionIsNumeric(kind)
    return byType[kind] and byType[kind].numeric == true
end

function addon.ConditionOperator(c)
    return c.operator or (byType[c.type] and byType[c.type].operator)
end

function addon.ValidateCondition(c)
    local d = c and byType[c.type]
    if not d or (d.combo and not addon.SupportsComboPointConditions()) then return nil, "Condition unavailable for this class." end
    local result = { type = c.type }
    if d.numeric then
        local value = tonumber(c.value)
        local op = addon.ConditionOperator(c)
        if not comparisons[op] then return nil, "Choose a valid comparison operator." end
        if not value or value ~= value or value == math.huge or value == -math.huge
            or value < d.min or (d.max and value > d.max) or (d.integer and value ~= math.floor(value)) then
            return nil, "Invalid threshold for " .. d.label .. "."
        end
        result.value, result.operator = value, op
    end
    return result
end

function addon.CompareCondition(value, c)
    if issecretvalue(value) or type(value) ~= "number" then return nil end
    local normalized = addon.ValidateCondition(c)
    if not normalized then return nil end
    return comparisons[normalized.operator](value, normalized.value)
end

-- Both settings features use this exact list, operator menu, and value editor.
function addon.CreateConditionControls(parent, getCondition, setCondition, changed, refresh)
    local controls = CreateFrame("Frame", nil, parent)
    controls:SetSize(334, 26)
    controls.dropdown = CreateFrame("DropdownButton", nil, controls, "WowStyle1DropdownTemplate")
    controls.dropdown:SetPoint("LEFT"); controls.dropdown:SetWidth(180)
    controls.dropdown:SetupMenu(function(_, menu)
        for _, d in ipairs(addon.GetConditionChoices()) do
            menu:CreateRadio(d.label, function(kind) return getCondition().type == kind end,
                function(kind) setCondition(addon.NewCondition(kind)); changed(); refresh() end, d.type)
        end
    end)
    controls.operator = CreateFrame("DropdownButton", nil, controls, "WowStyle1DropdownTemplate")
    controls.operator:SetPoint("LEFT", controls.dropdown, "RIGHT", 8, 0); controls.operator:SetWidth(74)
    controls.operator:SetupMenu(function(_, menu)
        for _, op in ipairs(operators) do
            menu:CreateRadio(op[2], function(kind) return addon.ConditionOperator(getCondition()) == kind end,
                function(kind)
                    local c = addon.CopyCondition(getCondition()); c.operator = kind
                    setCondition(c); changed(); refresh()
                end, op[1])
        end
    end)
    controls.value = CreateFrame("EditBox", nil, controls, "InputBoxTemplate")
    controls.value:SetPoint("LEFT", controls.operator, "RIGHT", 8, 0); controls.value:SetSize(64, 24)
    controls.value:SetAutoFocus(false); controls.value:SetMaxLetters(16)
    controls.value:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    controls.value:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            local c = addon.CopyCondition(getCondition()); c.value = self:GetText()
            setCondition(c); changed()
        end
    end)
    function controls:Refresh()
        local c = getCondition()
        local d = byType[c.type]
        local numeric = d and d.numeric == true
        self.dropdown:SetDefaultText(d and d.label or "Unknown condition"); self.dropdown:GenerateMenu()
        self.operator:SetShown(numeric); self.value:SetShown(numeric)
        if numeric then
            local symbol = "?"
            for _, op in ipairs(operators) do if op[1] == addon.ConditionOperator(c) then symbol = op[3] end end
            self.operator:SetDefaultText(symbol); self.operator:GenerateMenu()
            self.value:SetText(c.value == nil and "" or tostring(c.value))
        end
    end
    return controls
end
