-- ============================================================
-- Hooks WoW's native food/drink buff events via UNIT_AURA.
-- Food/drink tier system
-- ──────────────────────────────────────────────────────────────
-- Tier is detected once when the eating/drinking buff first
-- appears, by scanning the player's bags for a food/drink item
-- and inspecting its on-use spell description via:
--
--   GetItemSpell(itemLink)  → spellName, spellID
--   GetSpellDescription(spellID) → desc   (global; C_Spell.GetSpellDescription DNE in TWW 12.0)
--
-- If desc contains "well fed" (case-insensitive), the item grants a secondary stat buff → COMPLEX tier.
-- If the eating aura name contains feast keywords → FEAST tier.
-- Otherwise → SIMPLE tier.
--
-- Tiers:
--   SIMPLE  — 30% trickle over duration + 10% completion bonus
--   COMPLEX — 40% trickle over duration + 15% completion bonus
--   FEAST   — 60% trickle over duration + 20% completion bonus
--             (applies to BOTH hunger and thirst simultaneously)
--
-- The per-second trickle is applied in Core's _ApplyFoodDrinkRecovery.
-- The completion bonus is a lump-sum applied here on natural expiry.
--
-- Well Fed rework
-- ──────────────────────────────────────────────────────────────
-- Well Fed no longer restores hunger/thirst directly.
-- When the aura applies, it pauses hunger decay for 5 minutes
-- by setting ICN2._wellFedPauseExpiry, read by Core's
-- _ApplyWellFedPause modifier.
-- ============================================================

ICN2 = ICN2 or {}

-- ── Constants ─────────────────────────────────────────────────────────────────
-- Tier data defines the recovery rates and completion bonuses for each food/drink tier
local TIER_DATA = {
    simple  = { trickle = 30.0, bonus = 10.0 },  -- Basic food/drink: 30% over duration + 10% bonus
    complex = { trickle = 40.0, bonus = 15.0 },  -- Well-fed granting items: 40% over duration + 15% bonus
    feast   = { trickle = 60.0, bonus = 20.0 },  -- Feast items: 60% over duration + 20% bonus (both needs)
}

local WELLFED_PAUSE_SECS = 300  -- 5 minutes of hunger decay pause from well-fed buff

-- ── Public state (read by Core) ───────────────────────────────────────────────
ICN2._wellFedPauseExpiry = 0    -- GetTime() timestamp when well-fed pause expires; 0 = not active

-- ── Internal state ────────────────────────────────────────────────────────────
-- Tracks current food and drink consumption states
local foodState  = { active = false, startTime = nil, duration = nil, tier = nil }
local drinkState = { active = false, startTime = nil, duration = nil, tier = nil }

-- ── Aura name patterns ────────────────────────────────────────────────────────
-- Patterns used to identify different types of food/drink auras by name
local FOOD_AURA_PATTERNS   = { "food", "refreshment", "eating" }
local DRINK_AURA_PATTERNS  = { "drink", "drinking", "hydration" }
local DRINK_EXTRA_PATTERNS = { "conjured water", "mana tea", "morning glory" }  -- Special drink types
local WELLFED_PATTERNS     = { "well fed" }
local FEAST_NAME_PATTERNS  = { "feast", "banquet", "spread", "bountiful" }

-- ── Aura helpers ──────────────────────────────────────────────────────────────
-- Checks if a string matches any of the provided patterns (case-insensitive substring search)
-- @param name: The aura name to check
-- @param patterns: Array of pattern strings to match against
-- @return: true if any pattern matches, false otherwise
local function matchesAny(name, patterns)
    if not name then return false end
    local lower = string.lower(name)
    for _, p in ipairs(patterns) do
        if lower:find(p, 1, true) then return true end
    end
    return false
end

-- Finds the first aura on the player that matches any of the given patterns
-- @param patterns: Primary patterns to match against aura names
-- @param extraPatterns: Optional additional patterns to check
-- @return: The first matching aura data table, or nil if none found
local function findAura(patterns, extraPatterns)
    local i = 1
    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        if matchesAny(aura.name, patterns) then return aura end
        if extraPatterns and matchesAny(aura.name, extraPatterns) then return aura end
        i = i + 1
    end
    return nil
end

-- ── Tier detection ────────────────────────────────────────────────────────────
-- Determines the tier of food/drink by scanning player bags for the item
-- and checking its tooltip for "Well Fed" secondary effects.
-- @param isFeast: If true, returns "feast" tier immediately
-- @return: "feast", "complex", or "simple"
local function detectTierFromBags(isFeast)
    if isFeast then return "feast" end

    -- Scan all bags and slots for food/drink items
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemLink = C_Container.GetContainerItemLink(bag, slot)
                if itemLink then
                    -- Extract item ID from the item link
                    local itemID = C_Item.GetItemIDByGUID and
                        select(1, strsplit(":", itemLink:match("|Hitem:([%d:]+)|"))) or nil
                    if not itemID then
                        -- Fallback: parse item ID directly from link
                        itemID = tonumber(itemLink:match("|Hitem:(%d+):"))
                    end
                    if itemID then
                        -- Use modern tooltip API to check for "Well Fed" in item tooltip
                        local tooltipData = C_TooltipInfo and C_TooltipInfo.GetItemByID(tonumber(itemID))
                        if tooltipData and tooltipData.lines then
                            for _, line in ipairs(tooltipData.lines) do
                                local text = line.leftText or ""
                                if text:lower():find("well fed", 1, true) then
                                    return "complex"  -- Item grants well-fed buff
                                end
                            end
                        else
                            -- Fallback for older API: check spell description
                            local _, spellID = GetItemSpell(itemLink)
                            if spellID then
                                local desc = GetSpellDescription and GetSpellDescription(spellID) or ""
                                if desc:lower():find("well fed", 1, true) then
                                    return "complex"
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return "simple"  -- Default tier if no special effects found
end

-- Detects food tier, checking for feast keywords in aura name first
-- @param foodAura: The food aura data table
-- @return: "feast", "complex", or "simple"
local function detectFoodTier(foodAura)
    local isFeast = matchesAny(foodAura.name, FEAST_NAME_PATTERNS)
    return detectTierFromBags(isFeast)
end

-- Detects drink tier, inheriting feast status from food if applicable
-- @return: "feast", "complex", or "simple"
local function detectDrinkTier()
    if foodState.active and foodState.tier == "feast" then return "feast" end
    return detectTierFromBags(false)
end

-- ── Apply completion bonus ─────────────────────────────
-- Applies the completion bonus when food/drink consumption finishes naturally.
-- Only applies if the session completed naturally (not interrupted).
-- @param state: The foodState or drinkState table
-- @param need: "hunger" or "thirst"
-- @param natural: true if completed naturally, false if interrupted
local function applyBonus(state, need, natural) -- On natural completion we add a lump-sum bonus. Interrupted sessions get nothing.
    if not state.tier or not natural then return end

    local data   = TIER_DATA[state.tier] or TIER_DATA.simple
    local bonus  = data.bonus
    local isFeast = state.tier == "feast"

    if need == "hunger" or isFeast then
        ICN2DB.hunger = math.min(100, ICN2DB.hunger + bonus)
        ICN2:TriggerEmote("satisfied", "hunger")
    end
    if need == "thirst" or isFeast then
        ICN2DB.thirst = math.min(100, ICN2DB.thirst + bonus)
        ICN2:TriggerEmote("satisfied", "thirst")
    end

    ICN2:UpdateHUD()

    local needStr = (need == "hunger") and "|cFF00FF00Hunger|r" or "|cFF4499FFThirst|r"
    if isFeast then needStr = "|cFF00FF00Hunger|r & |cFF4499FFThirst|r" end
    print(string.format("|cFFFF6600ICN2|r %s completion bonus! (+%.0f%% — %s tier)",
        needStr, bonus, state.tier))
end

-- ── Main aura scan ────────────────────────────────────────────────────────────
-- Main function called on UNIT_AURA events. Handles food, drink, and well-fed aura detection.
-- More reliable than native buff events as it catches buffs that apply/expire during combat.
function ICN2:OnUnitAura()
    if UnitAffectingCombat("player") then return end

    local now = GetTime()

    -- ── Food aura handling ─────────────────────────────────────────────────────
    local foodAura = findAura(FOOD_AURA_PATTERNS)
    if foodAura then
        -- Food aura is active - start or continue tracking
        if not foodState.active then
            foodState.active    = true
            foodState.startTime = now
            foodState.duration  = foodAura.duration or 30
            foodState.tier      = detectFoodTier(foodAura)
        end
    else
        -- Food aura ended - apply completion bonus if natural
        if foodState.active then
            local elapsed = now - (foodState.startTime or now)
            local natural = elapsed >= (foodState.duration or 30) * 0.85  -- 85% completion threshold
            applyBonus(foodState, "hunger", natural)
            foodState.active    = false
            foodState.startTime = nil
            foodState.duration  = nil
            foodState.tier      = nil
        end
    end

    -- ── Well Fed aura handling ────────────────────────────────────────────────
    local wellFedAura = findAura(WELLFED_PATTERNS)
    if wellFedAura then
        -- New well-fed aura detected - start hunger pause
        local id = wellFedAura.auraInstanceID or 0
        if id ~= ICN2._lastWellFedInstanceID then
            ICN2._lastWellFedInstanceID = id
            ICN2._wellFedPauseExpiry    = now + WELLFED_PAUSE_SECS
            print(string.format(
                "|cFFFF6600ICN2|r |cFF00FF00Well Fed!|r Hunger decay paused for %d min.",
                math.floor(WELLFED_PAUSE_SECS / 60)))
        end
    else
        ICN2._lastWellFedInstanceID = nil
        -- Do NOT clear _wellFedPauseExpiry here — the pause runs its full
        -- 5 minutes even if the aura drops before the timer expires.
    end

    -- ── Drink aura handling ───────────────────────────────────────────────────
    local drinkAura = findAura(DRINK_AURA_PATTERNS, DRINK_EXTRA_PATTERNS)
    if drinkAura then
        -- Drink aura is active - start or continue tracking
        if not drinkState.active then
            drinkState.active    = true
            drinkState.startTime = now
            drinkState.duration  = drinkAura.duration or 30
            drinkState.tier      = detectDrinkTier()
        end
    else
        -- Drink aura ended - apply completion bonus if natural
        if drinkState.active then
            local elapsed = now - (drinkState.startTime or now)
            local natural = elapsed >= (drinkState.duration or 30) * 0.85
            applyBonus(drinkState, "thirst", natural)
            drinkState.active    = false
            drinkState.startTime = nil
            drinkState.duration  = nil
            drinkState.tier      = nil
        end
    end
end

-- ── Stubs ─────────────────────────────────────────────────────────────────────
-- Legacy function stubs for compatibility (no longer used in current implementation)
function ICN2:OnCombatBreakFoodDrink() end
function ICN2:FoodDrinkTick()          end

-- ── Status queries (read by Core rate engine) ─────────────────────────────────
-- Functions that provide current food/drink state information to the core rate calculation engine

-- Returns true if player currently has an active food buff (eating or post-eating phase)
function ICN2:IsEating()
    return foodState.active
end

-- Returns true if player currently has an active drink buff (drinking or post-drinking phase)
function ICN2:IsDrinking()
    return drinkState.active
end

-- Returns the current food tier: "simple", "complex", or "feast"
-- Defaults to "simple" when not eating for rate calculation purposes
function ICN2:GetFoodTier()
    return foodState.tier or "simple"
end

-- Returns the current drink tier: "simple", "complex", or "feast"
-- Defaults to "simple" when not drinking for rate calculation purposes
function ICN2:GetDrinkTier()
    return drinkState.tier or "simple"
end

-- Returns the total duration of the current food buff in seconds, or nil if not eating
function ICN2:GetFoodDuration()
    return foodState.duration
end

-- Returns the total duration of the current drink buff in seconds, or nil if not drinking
function ICN2:GetDrinkDuration()
    return drinkState.duration
end
