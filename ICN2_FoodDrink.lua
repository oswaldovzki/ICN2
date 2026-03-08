-- ============================================================
-- ICN2_FoodDrink.lua  (v1.2.0)
-- Hooks WoW's native food/drink buff events via UNIT_AURA.
--
-- How it works:
--   1. UNIT_AURA fires when food/drink buffs appear or disappear.
--   2. On buff appear: record start time + duration.
--   3. FoodDrinkTick() trickles 50% across the buff duration so
--      the bar visually fills while eating/drinking.
--   4. On buff expire naturally (>=85% duration): +50% restore.
--   5. On buff cancelled early: proportional fraction of 50%.
--   6. Well Fed aura: sets hunger+thirst to 100%, one-shot per
--      unique auraInstanceID.
-- ============================================================

ICN2 = ICN2 or {}

-- ── State ─────────────────────────────────────────────────────────────────────
local foodState  = { active = false, startTime = nil, duration = nil }
local drinkState = { active = false, startTime = nil, duration = nil }

-- ── Aura name patterns (lowercase, plain string match) ────────────────────────
local FOOD_AURA_PATTERNS   = { "food", "refreshment", "eating" }
local DRINK_AURA_PATTERNS  = { "drink", "drinking", "hydration" }
local DRINK_EXTRA_PATTERNS = { "conjured water", "mana tea", "morning glory" }
local WELLFED_PATTERNS     = { "well fed" }

-- Full session restores exactly 50%; partial cancel = proportional fraction.
local FULL_SESSION_RESTORE = 50.0

-- ── Scan all helpful auras on unit ────────────────────────────────────────────
local function scanAuras(unit)
    local results = {}
    local i = 1
    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then break end
        results[i] = aura
        i = i + 1
    end
    return results
end

-- ── Match aura name against a pattern list ────────────────────────────────────
local function matchesAny(name, patterns)
    if not name then return false end
    local lower = string.lower(name)
    for _, p in ipairs(patterns) do
        if lower:find(p, 1, true) then return true end
    end
    return false
end

-- ── Find first matching aura ──────────────────────────────────────────────────
local function findAura(patterns, extraPatterns)
    local auras = scanAuras("player")
    for _, aura in ipairs(auras) do
        if matchesAny(aura.name, patterns) then return aura end
        if extraPatterns and matchesAny(aura.name, extraPatterns) then return aura end
    end
    return nil
end

-- ── Apply restoration on buff end ─────────────────────────────────────────────
local function applyRestore(state, need, full)
    if not state.startTime then return end
    local elapsed  = GetTime() - state.startTime
    local duration = state.duration or 30
    local fraction = math.min(1.0, elapsed / math.max(1, duration))
    local amount   = full and FULL_SESSION_RESTORE or (FULL_SESSION_RESTORE * fraction)

    if need == "hunger" then
        ICN2DB.hunger = math.min(100, ICN2DB.hunger + amount)
        ICN2:TriggerEmote("satisfied", "hunger")
    elseif need == "thirst" then
        ICN2DB.thirst = math.min(100, ICN2DB.thirst + amount)
        ICN2:TriggerEmote("satisfied", "thirst")
    end

    ICN2:UpdateHUD()

    if full then
        print(string.format("|cFFFF6600ICN2|r %s restored! (+50%%)",
            need == "hunger" and "|cFF00FF00Hunger|r" or "|cFF4499FFThirst|r"))
    elseif amount >= 1 then
        print(string.format("|cFFFF6600ICN2|r %s partially restored (+%.0f%% — interrupted).",
            need == "hunger" and "|cFF00FF00Hunger|r" or "|cFF4499FFThirst|r", amount))
    end
end

-- ── Main aura scan — called on every UNIT_AURA for player ─────────────────────
function ICN2:OnUnitAura()
    -- Skip aura processing during combat to avoid taint issues
    if UnitAffectingCombat("player") then return end
    
    local now = GetTime()

    -- Food aura
    local foodAura = findAura(FOOD_AURA_PATTERNS)
    if foodAura then
        if not foodState.active then
            foodState.active    = true
            foodState.startTime = now
            foodState.duration  = foodAura.duration or 30
        end
    else
        if foodState.active then
            local elapsed = now - (foodState.startTime or now)
            local natural = (elapsed >= (foodState.duration or 30) * 0.85)
            applyRestore(foodState, "hunger", natural)
            foodState.active    = false
            foodState.startTime = nil
            foodState.duration  = nil
        end
    end

    -- Well Fed aura — one-shot per unique auraInstanceID
    local wellFedAura = findAura(WELLFED_PATTERNS)
    if wellFedAura then
        local id = wellFedAura.auraInstanceID or 0
        if id ~= ICN2._lastWellFedInstanceID then
            ICN2._lastWellFedInstanceID = id
            ICN2DB.hunger = 100.0
            ICN2DB.thirst = 100.0
            ICN2:UpdateHUD()
            ICN2:TriggerEmote("satisfied", "hunger")
            print("|cFFFF6600ICN2|r |cFF00FF00Well Fed!|r Hunger and Thirst set to 100%%.")
        end
    else
        ICN2._lastWellFedInstanceID = nil
    end

    -- Drink aura
    local drinkAura = findAura(DRINK_AURA_PATTERNS, DRINK_EXTRA_PATTERNS)
    if drinkAura then
        if not drinkState.active then
            drinkState.active    = true
            drinkState.startTime = now
            drinkState.duration  = drinkAura.duration or 30
        end
    else
        if drinkState.active then
            local elapsed = now - (drinkState.startTime or now)
            local natural = (elapsed >= (drinkState.duration or 30) * 0.85)
            applyRestore(drinkState, "thirst", natural)
            drinkState.active    = false
            drinkState.startTime = nil
            drinkState.duration  = nil
        end
    end
end

-- ── Combat break hook ─────────────────────────────────────────────────────────
-- WoW cancels food/drink buffs on combat enter, so UNIT_AURA handles the
-- partial credit automatically. This stub is kept for future expansion.
function ICN2:OnCombatBreakFoodDrink()
end

-- ── Trickle tick — called from Core every second ──────────────────────────────
-- Recovery is now handled entirely through rate calculations in the main tick.
-- This function is kept for potential future visual feedback features.
function ICN2:FoodDrinkTick()
    -- Recovery now handled in calculateCurrentRates() to avoid double application
    -- Visual feedback during eating/drinking could be added here in the future
end

-- ── Status queries ────────────────────────────────────────────────────────────
function ICN2:IsEating()   return foodState.active  end
function ICN2:IsDrinking() return drinkState.active end

-- ── Duration getters for rate calculations ────────────────────────────────────
function ICN2:GetFoodDuration()   return foodState.duration  end
function ICN2:GetDrinkDuration()  return drinkState.duration end
