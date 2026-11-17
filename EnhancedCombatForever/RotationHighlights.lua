local _, addon = ...
local events = CreateFrame("Frame")
local glows = {}
local profile, savedAbilities
local index = 1
local elapsed = 0
local waitRemaining = 0
local POST_CAST_WAIT = 0.2
local listenerOwnsStep = false

local function readable(value)
    return not issecretvalue(value)
end

local function attackableTarget()
    local canAttack = UnitCanAttack("player", "target")
    local dead = UnitIsDeadOrGhost("target")
    return readable(canAttack) and canAttack == true and readable(dead) and dead == false
end

local autoRepeatActive = false
local autoShotActive = false
local lastCastIndex = 0

local function entryHasConditionType(entry, condType)
    if type(entry) ~= "table" then return false end
    local conditions = entry.conditions
    if type(conditions) ~= "table" then return false end
    for _, c in ipairs(conditions) do
        if c.type == condType then return true end
    end
    return false
end

local function isAutoRepeatActive()
    return autoRepeatActive
end

function addon.IsAutoRepeatActive()
    return autoRepeatActive
end

function addon.IsAutoShotActive()
    return autoShotActive
end


local function currentSpell()
    if not addon.db then return end
    local active = addon.GetActiveRotationProfile()
    if active ~= profile or (active and active.abilities ~= savedAbilities) then
        profile = active
        savedAbilities = active and active.abilities
        index = 1
        waitRemaining = 0
        lastCastIndex = 0
        autoShotActive = false
        if addon.ResetListenerState then addon.ResetListenerState() end
    end
    -- Cast success can arrive before combo points and other resources update.
    -- All readers, including Dynamic Indicator, must wait before skipping rows.
    if waitRemaining > 0 then return end
    if isAutoRepeatActive() then
        if savedAbilities then
            for _, entry in ipairs(savedAbilities) do
                if addon.RotationEntryIsShootRow(entry) then
                    local ability = type(entry) == "table" and entry.ability or entry
                    local ok, info = pcall(C_Spell.GetSpellInfo, tonumber(ability) or ability)
                    if ok and readable(info) and type(info) == "table" then return info end
                end
            end
        end
        return
    end
    local targetReady = attackableTarget()
    listenerOwnsStep = false
    if addon.GetListenerSpell then
        local info, owns = addon.GetListenerSpell(targetReady)
        listenerOwnsStep = owns
        if owns then return info end
    end
    -- Visit at most #savedAbilities rows total to prevent infinite loops.
    for _ = 1, savedAbilities and #savedAbilities or 0 do
        local entry = savedAbilities[index]
        local thisIndex = index

        -- runAfterPrevious: skip if the previous ability wasn't the last cast (first row always passes).
        if thisIndex > 1 and entryHasConditionType(entry, "runAfterPrevious")
            and lastCastIndex ~= thisIndex - 1 then
            index = index % #savedAbilities + 1
        else
            local passes = addon.EvaluateRotationEntry(entry, targetReady)
            if passes == nil then return end -- Unreadable condition: wait rather than guess.
            if passes then
                local ability = type(entry) == "table" and entry.ability or entry
                local ok, info = pcall(C_Spell.GetSpellInfo, tonumber(ability) or ability)
                if ok and readable(info) and type(info) == "table" then return info end
                return
            end
            -- mustRunBeforeNext: restart from row 1 instead of advancing.
            -- Don't return — let the loop continue so row 1 can be highlighted immediately.
            if entryHasConditionType(entry, "mustRunBeforeNext") then
                index = 1
            else
                index = index % #savedAbilities + 1
            end
        end
    end
    if not targetReady then index = 1 end
end

-- Shared by action-bar guidance and the optional dynamic nameplate indicator.
function addon.GetCurrentRotationSpell()
    return currentSpell()
end

local function targetIndependentRow()
    if listenerOwnsStep then return addon.ListenerAllowsNoTarget() end
    local entry = savedAbilities and savedAbilities[index]
    return entry ~= nil and addon.RotationEntryIsTargetIndependent(entry)
end

local function sameSpell(expected, id)
    if not readable(id) or type(id) ~= "number" then return false end
    if not readable(expected.spellID) then return false end
    if expected.spellID == id then return true end
    -- Spell names match across ranks. No per-class or per-ability lists.
    local ok, name = pcall(C_Spell.GetSpellName, id)
    return ok and readable(name) and type(name) == "string"
        and readable(expected.name) and name == expected.name
end

local function hideGlow(glow)
    if glow:IsShown() then
        glow.ProcStartAnim:Stop()
        glow.ProcLoop:Stop()
        glow:Hide()
    end
end

local function showGlow(button)
    local glow = glows[button]
    if not glow then
        -- Own frame: never replace or hide Blizzard's genuine proc alert.
        glow = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
        glow:EnableMouse(false)
        glow:SetPoint("TOPLEFT", button, "TOPLEFT", -8, 8)
        glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 8, -8)
        glows[button] = glow
    end
    if not glow:IsShown() then
        glow:Show()
        glow.ProcLoop:Play()
    end
end

local function forEachStanceButton(callback)
    if not StanceBar or not StanceBar.actionButtons then return end
    for formIndex, button in pairs(StanceBar.actionButtons) do
        if not button:IsForbidden() and button:IsVisible() then
            local slot = button.index or formIndex
            if readable(slot) and type(slot) == "number" then
                local ok, _, active, _, id = pcall(GetShapeshiftFormInfo, slot)
                if ok and readable(id) and type(id) == "number" then callback(button, id, slot, active) end
            end
        end
    end
end

function addon.UpdateRotationHighlights(reset)
    if reset then
        index = 1; waitRemaining = 0; listenerOwnsStep = false; lastCastIndex = 0; autoShotActive = false
        addon.cachedRangedRange = nil; addon.cachedMeleeRange = nil
        if addon.ResetListenerState then addon.ResetListenerState() end
    end
    local expected = currentSpell()
    local wanted = {}
    if expected and (attackableTarget() or targetIndependentRow()) then
        local function highlight(button)
            local native = button.SpellActivationAlert
            if native and native:IsShown() then return end
            wanted[button] = true
            showGlow(button)
        end
        if ActionBarButtonEventsFrame then ActionBarButtonEventsFrame:ForEachFrame(function(button)
            if button:IsForbidden() or not button:IsVisible() then return end
            local action = button.action
            if not readable(action) or type(action) ~= "number" then return end
            local ok, kind, id, subType = pcall(GetActionInfo, action)
            if not ok or not readable(kind) or not readable(subType) then return end
            local spellAction = kind == "spell" and subType ~= "assistedcombat"
            local spellMacro = kind == "macro" and subType == "spell"
            if not (spellAction or spellMacro) or not sameSpell(expected, id) then return end
            highlight(button)
        end) end
        forEachStanceButton(function(button, id)
            if sameSpell(expected, id) then highlight(button) end
        end)
    end
    for button, glow in pairs(glows) do
        if not wanted[button] then hideGlow(glow) end
    end
    if addon.db and addon.db.dynamicIndicator and addon.RefreshIndicatorSource then
        addon.RefreshIndicatorSource()
    end
end

events:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if not addon.db then return end
    if (event == "UNIT_POWER_UPDATE" or event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_AURA")
        and (not readable(unit) or unit ~= "player") then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not readable(unit) or unit ~= "player" then return end
        local expected = currentSpell()
        if not attackableTarget() and not targetIndependentRow() then return end
        if expected and sameSpell(expected, spellID) then
            if listenerOwnsStep then
                addon.CompleteCurrentListener()
                listenerOwnsStep = false
            else
                lastCastIndex = index
                index = index % #savedAbilities + 1
            end
            waitRemaining = POST_CAST_WAIT
        end
        addon.UpdateRotationHighlights()
    elseif event == "START_AUTOREPEAT_SPELL" then
        -- Distinguish hunter-style Auto Shot (weave, don't lock) from wand Shoot (lock).
        local hasAutoShot = false
        if savedAbilities then
            for _, entry in ipairs(savedAbilities) do
                if entryHasConditionType(entry, "autoShotToggle") then hasAutoShot = true; break end
            end
        end
        if hasAutoShot then
            autoShotActive = true
        else
            autoRepeatActive = true
        end
        addon.UpdateRotationHighlights()
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        if autoShotActive then
            autoShotActive = false
            -- Point index back at the Auto Shot row so it highlights immediately.
            if savedAbilities then
                for i, entry in ipairs(savedAbilities) do
                    if entryHasConditionType(entry, "autoShotToggle") then
                        index = i; break
                    end
                end
            end
        else
            autoRepeatActive = false
            if savedAbilities then
                for i, entry in ipairs(savedAbilities) do
                    if addon.RotationEntryIsShootRow(entry) then
                        index = i % #savedAbilities + 1
                        break
                    end
                end
            end
        end
        addon.UpdateRotationHighlights()
    else
        addon.UpdateRotationHighlights(event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED")
    end
end)

-- Refresh after action bar paging, native procs, target death/faction changes,
-- or newly visible buttons, without touching secure action attributes.
events:SetScript("OnUpdate", function(_, delta)
    if waitRemaining > 0 then
        waitRemaining = math.max(0, waitRemaining - delta)
        if waitRemaining == 0 then
            elapsed = 0
            addon.UpdateRotationHighlights()
            return
        end
    end
    elapsed = elapsed + delta
    if elapsed >= 0.15 then
        elapsed = 0
        if addon.UpdateRangeMonitors then addon.UpdateRangeMonitors() end
        addon.UpdateRotationHighlights()
    end
end)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UNIT_FLAGS",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_UPDATE",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UPDATE_SHAPESHIFT_FORMS", "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_AURA", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL" }) do
    events:RegisterEvent(event)
end

function addon.BuildRotationReport()
    local function text(value)
        if not readable(value) then return "[restricted]" end
        if value == nil then return "[unavailable]" end
        return tostring(value)
    end
    local selected = currentSpell()
    local active = addon.db and addon.GetActiveRotationProfile()
    local healthOK, playerHealth = pcall(UnitHealth, "player", false)
    local maxHealthOK, playerHealthMax = pcall(UnitHealthMax, "player")
    local percentOK, playerHealthPercent = false, nil
    if type(UnitHealthPercent) == "function" then
        percentOK, playerHealthPercent = pcall(UnitHealthPercent, "player", false)
    end
    local lines = {
        "Enhanced Combat Forever - Rotation inspection",
        "Active profile: " .. (active and active.name or "none"),
        "In combat: " .. text(UnitAffectingCombat("player")),
        "Attackable living target: " .. text(attackableTarget()),
        "Current row: " .. index .. " | Last cast row: " .. lastCastIndex,
        "Current ability: " .. (selected and text(selected.name) or "none / waiting"),
        "Active listener: " .. (addon.CurrentListenerAbility and addon.CurrentListenerAbility() or "none"),
        "Post-cast wait: " .. string.format("%.2fs", waitRemaining),
        "Auto-repeat active (Shoot gate): " .. tostring(isAutoRepeatActive()) .. " | Auto Shot active: " .. tostring(autoShotActive),
        "Player health API: current=" .. (healthOK and text(playerHealth) or "[call failed]")
            .. " | max=" .. (maxHealthOK and text(playerHealthMax) or "[call failed]")
            .. " | percent=" .. (percentOK and text(playerHealthPercent) or "[call unavailable]"),
        "\nSaved rows (unsaved editor changes are not used):",
    }
    if active then
        for i, rawEntry in ipairs(active.abilities) do
            local entry = addon.GetMigratedEntry(rawEntry)
            local ability = entry.ability or ""
            local conditions = entry.conditions or {}
            local passes = addon.EvaluateRotationEntry(entry, attackableTarget())
            local condDesc = #conditions == 0 and "always"
                or table.concat((function()
                    local parts = {}
                    for _, c in ipairs(conditions) do
                        local result = addon.EvaluateRotationCondition(c, ability)
                        parts[#parts + 1] = c.type
                            .. (c.operator and (" " .. c.operator .. " " .. text(c.value)) or "")
                            .. "=" .. text(result)
                    end
                    return parts
                end)(), " AND ")
            lines[#lines + 1] = i .. ". " .. ability .. " | conditions=[" .. condDesc .. "] | passes=" .. text(passes)
        end
    end
    lines[#lines + 1] = "\nSaved listeners:"
    local rangedProbe = addon.db and addon.db.rangedRangeAbility or ""
    local meleeProbe = addon.db and addon.db.meleeRangeAbility or ""
    lines[#lines + 1] = "Ranged range probe: " .. (rangedProbe ~= "" and rangedProbe or "(none)")
        .. " | cached=" .. text(addon.cachedRangedRange)
    lines[#lines + 1] = "Melee range probe:  " .. (meleeProbe ~= "" and meleeProbe or "(none)")
        .. " | cached=" .. text(addon.cachedMeleeRange)
    local listenerDiagnostics = addon.GetListenerDiagnostics and addon.GetListenerDiagnostics(attackableTarget()) or {}
    if #listenerDiagnostics == 0 then lines[#lines + 1] = "none" end
    for _, listener in ipairs(listenerDiagnostics) do
        lines[#lines + 1] = listener.index .. ". " .. text(listener.ability)
            .. " | enabled=" .. text(listener.enabled)
            .. " | targetEligible=" .. text(listener.targetEligible)
            .. " | cooldownReady=" .. text(listener.cooldownReady)
            .. " | active=" .. text(listener.active)
            .. " | latched=" .. text(listener.latched)
        if #listener.conditions == 0 then lines[#lines + 1] = "   no conditions" end
        for conditionIndex, condition in ipairs(listener.conditions) do
            local comparison = condition.operator and (condition.operator .. " " .. text(condition.value)) or ""
            lines[#lines + 1] = "   " .. conditionIndex .. ". " .. text(condition.type)
                .. (comparison ~= "" and (" " .. comparison) or "")
                .. " | passes=" .. text(condition.result)
                .. ((condition.type == "healthPercent" or condition.type == "manaPercent"
                    or condition.type == "ragePercent" or condition.type == "energyPercent")
                    and condition.operator == "ge"
                    and (" | curveProbe=" .. text(condition.curveProbe)) or "")
        end
    end
    lines[#lines + 1] = "\nVisible action buttons (action type / ID / name / current-ability match):"
    if ActionBarButtonEventsFrame then
        ActionBarButtonEventsFrame:ForEachFrame(function(button)
            if button:IsForbidden() or not button:IsVisible() then return end
            local action = button.action
            if not readable(action) or type(action) ~= "number" then return end
            local ok, kind, id, subType = pcall(GetActionInfo, action)
            if not ok then return end
            local name
            if readable(id) and type(id) == "number" then
                local nameOK, value = pcall(C_Spell.GetSpellName, id)
                if nameOK then name = value end
            end
            local matches = false
            if selected then matches = sameSpell(selected, id) end
            lines[#lines + 1] = "Slot " .. action .. " | " .. text(kind) .. " / " .. text(id)
                .. " / " .. text(name) .. " | subtype=" .. text(subType) .. " | match=" .. text(matches)
        end)
    end
    lines[#lines + 1] = "\nVisible stance / stealth buttons:"
    forEachStanceButton(function(_, id, slot, activeForm)
        local nameOK, name = pcall(C_Spell.GetSpellName, id)
        local matches = selected and sameSpell(selected, id) or false
        lines[#lines + 1] = "Form " .. slot .. " | spell=" .. text(id) .. " / "
            .. (nameOK and text(name) or "[unavailable]") .. " | active=" .. text(activeForm)
            .. " | match=" .. text(matches)
    end)
    return table.concat(lines, "\n")
end

SLASH_ENHANCEDCOMBATFOREVERROTATION1 = "/ecfrotation"
SlashCmdList.ENHANCEDCOMBATFOREVERROTATION = function()
    addon.ShowInspectionReport(addon.BuildRotationReport())
end
