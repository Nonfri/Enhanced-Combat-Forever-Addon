local addonName, addon = ...
local defaults = { spellID = 0, abilitySelected = false, dynamicIndicator = false, size = 16, offsetX = 8, offsetY = 0 }
local plates = {}
local activeUnit
local activePlate
local trackedSpell
local indicatorSpellID
local trackingMelee = false
local rangeModeReady = false
local meleeProbe
local elapsed = 0
local events = CreateFrame("Frame")
local indicator = CreateFrame("Frame", nil, UIParent)
indicator:EnableMouse(false)
indicator:Hide()
local dot = indicator:CreateTexture(nil, "OVERLAY")
dot:SetAllPoints()
dot:SetAtlas("WhiteCircle-RaidBlips")

local function readable(value)
    return not issecretvalue(value)
end

local function resolveIndicatorSpell()
    if addon.db.dynamicIndicator then
        local info = addon.GetCurrentRotationSpell and addon.GetCurrentRotationSpell()
        if info and readable(info.spellID) and type(info.spellID) == "number" then return info.spellID end
        return nil -- Dynamic mode never falls back to the manual selection.
    end
    if addon.db.abilitySelected then return addon.db.spellID end
end

local function normalizeLabel(value)
    if issecretvalue(value) or type(value) ~= "string" then return nil end
    return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " "):match("^%s*(.-)%s*$"):lower()
end

function addon.UsesMeleeRange(spellID)
    local ok, tooltip = pcall(C_TooltipInfo.GetSpellByID, spellID)
    if not ok or issecretvalue(tooltip) or type(tooltip) ~= "table"
        or issecretvalue(tooltip.lines) or type(tooltip.lines) ~= "table" or #tooltip.lines == 0 then
        return nil -- Tooltip not ready; do not guess a range mode.
    end
    local meleeLabel = normalizeLabel(_G.MELEE_RANGE or "Melee Range")
    local nextLabel = normalizeLabel(_G.SPELL_ON_NEXT_SWING or "Next melee")
    local melee = false
    for _, line in ipairs(tooltip.lines) do
        -- Restrict detection to header labels, never spell names/descriptions.
        if not issecretvalue(line) and type(line) == "table"
            and not issecretvalue(line.type) and line.type == 0 then
            for _, field in ipairs({ "leftText", "rightText" }) do
                local label = normalizeLabel(line[field])
                if label then
                    if label:find(nextLabel, 1, true) then return true, "swing" end
                    if label == meleeLabel then melee = true end
                end
            end
        end
    end
    if melee then return true, "melee" end
    return false, "spell"
end

local function findMeleeProbe(selectedID, kind)
    -- An ordinary melee ability can supply its own fallback. Next-swing
    -- abilities need a different learned melee ability, found in the spellbook.
    if kind == "melee" then return selectedID end
    for lineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        if line then
            for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
                local id = item and item.spellID
                if id and id ~= selectedID and C_SpellBook.IsSpellKnown(id) then
                    local isMelee, candidateKind = addon.UsesMeleeRange(id)
                    if isMelee and candidateKind == "melee" and C_Spell.SpellHasRange(id) then return id end
                end
            end
        end
    end
end

local function meleeRange(probe)
    local ok, value = pcall(C_SwingTimer.IsTargetWithinSwingRange, Enum.PlayerSwingType.MainHand)
    if ok and readable(value) and type(value) == "boolean" then return value end
    if probe then
        local probeOK, inRange = pcall(C_Spell.IsSpellInRange, probe, "target")
        if probeOK then return inRange end
    end
    return nil
end

-- Independent of the indicator's selected source, so rotation conditions can
-- check a candidate without recursing through Dynamic Indicator selection.
function addon.CheckAbilityRange(spellID)
    if not C_SpellBook.IsSpellKnown(spellID) then return nil end
    local isMelee, kind = addon.UsesMeleeRange(spellID)
    if isMelee == nil then return nil end
    local ok, value
    if isMelee then
        value = meleeRange(findMeleeProbe(spellID, kind))
        ok = true
    elseif C_Spell.SpellHasRange(spellID) then
        ok, value = pcall(C_Spell.IsSpellInRange, spellID, "target")
    end
    if ok and readable(value) and type(value) == "boolean" then return value end
    return nil
end

local function paint(inRange)
    if not readable(inRange) or inRange == nil then
        dot:SetVertexColor(0.55, 0.55, 0.55)
    elseif inRange then
        dot:SetVertexColor(0.1, 1, 0.1)
    else
        dot:SetVertexColor(1, 0.1, 0.1)
    end
end

local function positionIndicator()
    if not activePlate then return end
    local unitFrame = activePlate.UnitFrame
    local container = unitFrame and unitFrame.HealthBarsContainer
    local healthBar = container and container.healthBar
    -- Use the health bar rather than the name or its aura layout.
    -- Custom nameplate layouts without Blizzard's bar fall back to the plate.
    local anchor = healthBar or container or activePlate
    indicator:ClearAllPoints()
    indicator:SetPoint("RIGHT", anchor, "LEFT", -addon.db.offsetX, addon.db.offsetY)
end

local function refreshRange()
    if not activeUnit then return end
    positionIndicator()
    -- Unknown spells and invalid targets are an unknown range, never red.
    local spellID = indicatorSpellID
    if not spellID or not rangeModeReady or not C_SpellBook.IsSpellKnown(spellID) then
        paint(nil)
        return
    end
    if trackingMelee then
        paint(meleeRange(meleeProbe))
        return
    end
    if not C_Spell.SpellHasRange(spellID) then paint(nil); return end
    local ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, "target")
    if ok then paint(inRange) else paint(nil) end
end

local function attachTarget()
    activeUnit = nil
    activePlate = nil
    indicator:Hide()
    indicator:ClearAllPoints()
    indicator:SetParent(UIParent)
    for unit in pairs(plates) do
        local isTarget = UnitIsUnit(unit, "target")
        if readable(isTarget) and isTarget then
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            if plate and not plate:IsForbidden() then
                activeUnit = unit
                activePlate = plate
                indicator:SetParent(plate)
                indicator:SetSize(addon.db.size, addon.db.size)
                -- Parenting also hides the dot when the nameplate is hidden.
                indicator:Show()
                refreshRange()
                return
            end
        end
    end
end

function addon.Refresh()
    if trackedSpell then
        C_Spell.EnableSpellRangeCheck(trackedSpell, false)
    end
    trackedSpell = nil
    if trackingMelee then C_SwingTimer.EnableRangeCheck(Enum.PlayerSwingType.MainHand, false) end
    trackingMelee, meleeProbe, rangeModeReady = false, nil, false
    indicatorSpellID = resolveIndicatorSpell()
    if indicatorSpellID and C_SpellBook.IsSpellKnown(indicatorSpellID) then
        local isMelee, kind = addon.UsesMeleeRange(indicatorSpellID)
        rangeModeReady = isMelee ~= nil
        if isMelee then
            trackingMelee = true
            C_SwingTimer.EnableRangeCheck(Enum.PlayerSwingType.MainHand, true)
            meleeProbe = findMeleeProbe(indicatorSpellID, kind)
            trackedSpell = meleeProbe
        elseif rangeModeReady and C_Spell.SpellHasRange(indicatorSpellID) then
            trackedSpell = indicatorSpellID
        end
        if trackedSpell then C_Spell.EnableSpellRangeCheck(trackedSpell, true) end
    end
    attachTarget()
end

function addon.RefreshIndicatorSource()
    if not addon.db then return end
    if resolveIndicatorSpell() ~= indicatorSpellID then
        addon.Refresh()
    else
        refreshRange()
    end
end

function addon.Reset()
    for key, value in pairs(defaults) do addon.db[key] = value end
    addon.Refresh()
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        if type(EnhancedCombatForeverDB) ~= "table" then EnhancedCombatForeverDB = {} end
        addon.db = EnhancedCombatForeverDB
        for key, value in pairs(defaults) do
            if type(addon.db[key]) ~= type(value) then addon.db[key] = value end
        end
        addon.db.size = math.max(8, math.min(48, addon.db.size))
        addon.db.offsetX = math.max(-200, math.min(200, addon.db.offsetX))
        addon.db.offsetY = math.max(-200, math.min(200, addon.db.offsetY))
        addon.CreateSettings()
        addon.Refresh()
        return
    end
    if not addon.db then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        plates[arg1] = true
        attachTarget()
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        plates[arg1] = nil
        if arg1 == activeUnit then attachTarget() end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        attachTarget()
    elseif event == "SPELLS_CHANGED" or event == "SPELL_TEXT_UPDATE" then
        addon.Refresh()
    elseif event == "SPELL_RANGE_CHECK_UPDATE" or event == "PLAYER_SWING_RANGE_UPDATE" then
        -- Query the current target again rather than using an event payload
        -- that could belong to a target we have just switched away from.
        addon.RefreshIndicatorSource()
    end
end)

-- Some abilities do not deliver range events consistently. A modest fallback
-- checks only while our target's nameplate is visible, including in combat.
indicator:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed >= 0.15 then
        elapsed = 0
        addon.RefreshIndicatorSource()
    end
end)

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "SPELLS_CHANGED", "SPELL_RANGE_CHECK_UPDATE",
    "PLAYER_SWING_RANGE_UPDATE", "SPELL_TEXT_UPDATE" }) do
    events:RegisterEvent(event)
end
