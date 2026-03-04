-- ============================================================
-- ICN2_FoodDrink.lua  (v1.1)
-- Hooks WoW's native food/drink buff events via UNIT_AURA.
--
-- How it works:
--   1. When a "eating" or "drinking" aura appears on the player,
--      we record the buff start time and expected duration.
--   2. Every tick we grant proportional partial restoration.
--   3. If the buff expires naturally (buff gone after full duration)
--      → full 100% restore of hunger or thirst.
--   4. If the buff disappears early (cancelled by movement, combat,
--      standing up) → partial credit proportional to time elapsed.
--   5. "Well Fed" aura appearing = eating fully completed →
--      immediately top up hunger to 100%.
-- ============================================================

ICN2 = ICN2 or {}

-- ── State ─────────────────────────────────────────────────────────────────────
local foodState  = { active = false, startTime = nil, duration = nil, buffName = nil }
local drinkState = { active = false, startTime = nil, duration = nil, buffName = nil }

-- ── Known aura name fragments (lowercase) ─────────────────────────────────────
-- WoW food buffs all share "Food" or "Refreshment" in their name while active.
-- Drink buffs share "Drink" or "Refreshment" while drinking.
-- Well Fed is the completion buff granted when eating finishes.
-- These are checked with string.find for broad compatibility across expansions.
local FOOD_AURA_PATTERNS  = { "food", "refreshment", "eating" }
local DRINK_AURA_PATTERNS = { "drink", "thirst", "drinking", "hydration" }
local WELLFFED_PATTERNS   = { "well fed" }
-- Some racial/special drink buffs to also catch
local DRINK_EXTRA_PATTERNS = { "conjured water", "mana tea", "morning glory" }

-- Restoration rate while actively eating/drinking (% per second of buff).
-- The buff typically lasts 30s; we spread the gain across that window.
-- Partial credit on cancel = fraction of total 100% proportional to time.
local FULL_RESTORE = 100.0  -- % restored on full completion

-- ── Utility: scan unit auras using the v10+ API ──────────────────────────────
-- C_UnitAuras.GetAuraDataByIndex replaces the old UnitBuff in TWW.
local function scanAuras(unit, filter)
    local results = {}
    local i = 1
    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
        if not aura then break end
        table.insert(results, aura)
        i = i + 1
    end
    return results
end

-- ── Check if a name matches any pattern in a list ────────────────────────────
local function matchesAny(name, patterns)
    if not name then return false end
    local lower = name:lower()
    for _, p in ipairs(patterns) do
        if lower:find(p, 1, true) then return true end
    end
    return false
end

-- ── Find a specific aura type on the player ──────────────────────────────────
-- Returns auraData or nil
local function findAura(patterns, extraPatterns)
    local auras = scanAuras("player", "HELPFUL")
    for _, aura in ipairs(auras) do
        if matchesAny(aura.name, patterns) then
            return aura
        end
        if extraPatterns and matchesAny(aura.name, extraPatterns) then
            return aura
        end
    end
    return nil
end

-- ── Apply partial or full restoration ────────────────────────────────────────
local function applyRestore(state, need, full)
    if not state.startTime then return end

    local elapsed  = GetTime() - state.startTime
    local duration = state.duration or 30
    local fraction = math.min(1.0, elapsed / math.max(1, duration))
    local amount   = full and FULL_RESTORE or (FULL_RESTORE * fraction)

    if need == "hunger" then
        ICN2DB.hunger = math.min(100, ICN2DB.hunger + amount)
        ICN2:TriggerEmote("satisfied", "hunger")
    elseif need == "thirst" then
        ICN2DB.thirst = math.min(100, ICN2DB.thirst + amount)
        ICN2:TriggerEmote("satisfied", "thirst")
    end

    ICN2:UpdateHUD()

    if full then
        print(string.format("|cFFFF6600ICN2|r %s fully restored! (100%%)",
            need == "hunger" and "|cFF00FF00Hunger|r" or "|cFF4499FFThirst|r"))
    elseif amount > 1 then
        print(string.format("|cFFFF6600ICN2|r %s partially restored (+%.0f%% — interrupted).",
            need == "hunger" and "|cFF00FF00Hunger|r" or "|cFF4499FFThirst|r",
            amount))
    end
end

-- ── Main aura scan — called on every UNIT_AURA for player ─────────────────────
function ICN2:OnUnitAura()
    local now = GetTime()

    -- ── Food aura ─────────────────────────────────────────────────────────────
    local foodAura = findAura(FOOD_AURA_PATTERNS)
    if foodAura then
        if not foodState.active then
            -- Buff just appeared — record state
            foodState.active    = true
            foodState.startTime = now
            foodState.duration  = foodAura.duration or 30
            foodState.buffName  = foodAura.name
        end
        -- Buff still present — nothing to do, tick handles progressive restore
    else
        if foodState.active then
            -- Buff disappeared — was it natural completion or cancellation?
            local elapsed  = now - (foodState.startTime or now)
            local duration = foodState.duration or 30
            local natural  = (elapsed >= duration * 0.85)  -- within 15% of end = natural

            applyRestore(foodState, "hunger", natural)
            foodState.active    = false
            foodState.startTime = nil
            foodState.duration  = nil
            foodState.buffName  = nil
        end
    end

    -- ── Well Fed aura (eating completion bonus) ───────────────────────────────
    -- Well Fed appears AFTER the food buff expires naturally.
    -- We check for it and top up to 100% unconditionally.
    local wellFedAura = findAura(WELLFFED_PATTERNS)
    if wellFedAura and not ICN2._wellFedApplied then
        ICN2._wellFedApplied = true
        ICN2DB.hunger = 100.0
        ICN2:UpdateHUD()
        ICN2:TriggerEmote("satisfied", "hunger")
        print("|cFFFF6600ICN2|r |cFF00FF00Well Fed!|r Hunger completely restored.")

        -- Reset flag after a short delay (buff can persist for minutes)
        C_Timer.After(5, function() ICN2._wellFedApplied = false end)
    elseif not wellFedAura then
        ICN2._wellFedApplied = false
    end

    -- ── Drink aura ────────────────────────────────────────────────────────────
    local drinkAura = findAura(DRINK_AURA_PATTERNS, DRINK_EXTRA_PATTERNS)
    if drinkAura then
        if not drinkState.active then
            drinkState.active    = true
            drinkState.startTime = now
            drinkState.duration  = drinkAura.duration or 30
            drinkState.buffName  = drinkAura.name
        end
    else
        if drinkState.active then
            local elapsed  = now - (drinkState.startTime or now)
            local duration = drinkState.duration or 30
            local natural  = (elapsed >= duration * 0.85)

            applyRestore(drinkState, "thirst", natural)
            drinkState.active    = false
            drinkState.startTime = nil
            drinkState.duration  = nil
            drinkState.buffName  = nil
        end
    end
end

-- ── Cancel eating/drinking on combat enter ────────────────────────────────────
-- When PLAYER_REGEN_DISABLED fires, WoW already cancels the buff,
-- so UNIT_AURA will fire shortly after and handle the partial credit.
-- This function is a safety net in case UNIT_AURA fires before our flag clears.
function ICN2:OnCombatBreakFoodDrink()
    -- Nothing to force here — UNIT_AURA will catch the buff disappearing.
    -- Kept as a named hook for future expansion (e.g., custom sound).
end

-- ── Tick-based progressive restoration (optional smooth feedback) ─────────────
-- Called from Core tick every second while a buff is active.
-- Gives a tiny trickle each second so the bar moves visually while eating.
function ICN2:FoodDrinkTick()
    if foodState.active and foodState.startTime and foodState.duration then
        local tickGain = (1 / math.max(1, foodState.duration)) * FULL_RESTORE * 0.5
        ICN2DB.hunger = math.min(100, ICN2DB.hunger + tickGain)
    end

    if drinkState.active and drinkState.startTime and drinkState.duration then
        local tickGain = (1 / math.max(1, drinkState.duration)) * FULL_RESTORE * 0.5
        ICN2DB.thirst = math.min(100, ICN2DB.thirst + tickGain)
    end
end

-- ── Status query (used by HUD tooltip) ───────────────────────────────────────
function ICN2:IsEating()  return foodState.active  end
function ICN2:IsDrinking() return drinkState.active end
