-- ============================================================
-- ICN2_FoodDrink.lua
-- Tracks food and drink buffs, detects their tiers, and applies completion bonuses.
-- Uses aura scanning for reliable detection of buffs that apply/expire during combat.
-- ============================================================

ICN2 = ICN2 or {}

local L = setmetatable({}, { __index = function(_, k)
    return ICN2.L and ICN2.L[k] or k
end })

-- ── Constants ─────────────────────────────────────────────────────────────────
-- Tier data defines the recovery rates and completion bonuses for each food/drink tier
-- All values are in FIXED POINTS (not percentages), same for all races
local TIER_DATA = {
    simple  = { trickle = 50.0, bonus = 10.0 },  -- Simple items: 20 points over duration + 10 point bonus
    complex = { trickle = 60.0, bonus = 15.0 },  -- Complex items: 40 points over duration + 15 point bonus
    feast   = { trickle = 80.0, bonus = 20.0 },  -- Feasts: 60 points over duration + 20 point bonus, applies to both hunger and thirst
}

local WELLFED_PAUSE_SECS = 300  -- 5 minutes of hunger decay pause from well-fed buff

-- ── Public state (read by Core) ───────────────────────────────────────────────
ICN2._wellFedPauseExpiry = 0    -- GetTime() timestamp when well-fed pause expires; 0 = not active

-- ── Internal state ────────────────────────────────────────────────────────────
-- Tracks current food and drink consumption states
local foodState  = { active = false, startTime = nil, duration = nil, tier = nil }
local drinkState = { active = false, startTime = nil, duration = nil, tier = nil }

-- ── Aura name patterns ────────────────────────────────────────────────────────
local FOOD_AURA_PATTERNS   = { "food", "refreshment", "eating" }  -- No ^ anchor - these are safe
local DRINK_AURA_PATTERNS  = { "^drink", "^drinking", "hydration" }  -- ^ anchor to avoid false matches
local DRINK_EXTRA_PATTERNS = { "conjured water", "mana tea", "morning glory" }
local WELLFED_PATTERNS     = { "well fed" }
local FEAST_NAME_PATTERNS  = { "feast", "banquet", "spread", "bountiful" }

-- ── Aura helpers ──────────────────────────────────────────────────────────────
-- Checks if a string matches any of the provided patterns (case-insensitive substring search)
local function matchesAny(name, patterns)
    if not name or not patterns then return false end

    local success, lower = pcall(string.lower, name)
    if not success then
        return false
    end
    
    for _, p in ipairs(patterns) do
        if p:sub(1,1) == "^" then
            local pat = p:sub(2)
            if lower:sub(1, #pat) == pat then return true end
        else
            if lower:find(p, 1, true) then return true end
        end
    end
    return false
end

-- ── Persistent aura cache ─────────────────────────────────────────────────────
-- Maps auraInstanceID → auraData for all current HELPFUL buffs on the player.
-- Built once on login, then patched on each UNIT_AURA event using updateInfo deltas.
-- A nil updateInfo is a full-refresh signal — we rebuild from scratch.
-- State.lua reads this cache for campfire/sitting detection instead of ForEachAura.
ICN2._auraCache = {}  -- public so State.lua can read it

local function rebuildAuraCache()
    local cache = {}
    local i = 1
    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        if aura.auraInstanceID then
            cache[aura.auraInstanceID] = aura
        end
        i = i + 1
    end
    ICN2._auraCache = cache
end

local function patchAuraCache(updateInfo)
    -- updateInfo.addedAuras / updatedAuraInstanceIDs: fetch fresh data and upsert
    -- updateInfo.removedAuraInstanceIDs: delete from cache
    local cache = ICN2._auraCache

    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            if aura.auraInstanceID then
                cache[aura.auraInstanceID] = aura
            end
        end
    end

    if updateInfo.updatedAuraInstanceIDs then
        for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
            local fresh = C_UnitAuras.GetAuraDataByAuraInstanceID("player", id)
            if fresh then
                cache[id] = fresh
            else
                cache[id] = nil  -- expired between event and fetch
            end
        end
    end

    if updateInfo.removedAuraInstanceIDs then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
            cache[id] = nil
        end
    end
end

-- Searches the cache for the first aura matching any pattern set.
-- Returns the auraData table or nil.
local function findAuraInCache(patterns, extraPatterns)
    for _, aura in pairs(ICN2._auraCache) do
        if matchesAny(aura.name, patterns) then return aura end
        if extraPatterns and matchesAny(aura.name, extraPatterns) then return aura end
    end
    return nil
end

-- Seeds the cache on login. Called from Core after a 1-second delay (same as armor cache).
function ICN2:InitAuraCache()
    rebuildAuraCache()
end

-- ── Tier detection ────────────────────────────────────────────────────────────
-- Determines the tier of food/drink by scanning player bags for the item
-- Checks for feast keywords in aura name first, then scans bags for food/drink items and their tooltips to detect well-fed buffs.
-- Not ideal, I~m still looking for a better way to detect well-fed buffs without relying on tooltip text
local function detectTierFromBags(isFeast)
    if isFeast then return "feast" end
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                
                if itemID then
                    -- GetItemInfo returns item metadata including class/subclass IDs
                    -- classID 0 = Consumable, subClassID 5 = Food & Drink
                    local _, _, _, _, _, _, _, classID, subClassID = GetItemInfo(itemID)
                    
                    -- Filter: only process actual food/drink items
                    -- Consumable (classID = 0), Food & Drink subclass (subClassID = 5)
                    if classID == 0 and subClassID == 5 then
                        local tooltipData = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
                        if tooltipData and tooltipData.lines then
                            for _, line in ipairs(tooltipData.lines) do
                                local text = line.leftText or ""
                                if text:lower():find("well fed", 1, true) then
                                    return "complex"
                                end
                            end
                        else
                            local itemLink = C_Container.GetContainerItemLink(bag, slot)
                            if itemLink then
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
    end

    return "simple"  -- Default tier if no special effects found
end

-- Detects food tier, checking for feast keywords in aura name first
local function detectFoodTier(foodAura)
    local isFeast = matchesAny(foodAura.name, FEAST_NAME_PATTERNS)
    return detectTierFromBags(isFeast)
end

-- Detects drink tier, inheriting feast status from food if applicable
local function detectDrinkTier()
    if foodState.active and foodState.tier == "feast" then return "feast" end
    return detectTierFromBags(false)
end

-- ── Apply completion bonus ─────────────────────────────────
local function applyBonus(state, need, natural)
    if not state.tier or not natural then return end

    local data   = TIER_DATA[state.tier] or TIER_DATA.simple
    local bonus  = data.bonus
    local isFeast = state.tier == "feast"

    if need == "hunger" or isFeast then
        local maxH = ICN2:GetMaxValue("hunger")
        ICN2DB.hunger = math.min(maxH, ICN2DB.hunger + bonus)
        ICN2:TriggerEmote("satisfied", "hunger")
    end
    if need == "thirst" or isFeast then
        local maxT = ICN2:GetMaxValue("thirst")
        ICN2DB.thirst = math.min(maxT, ICN2DB.thirst + bonus)
        ICN2:TriggerEmote("satisfied", "thirst")
    end

    ICN2:UpdateHUD()

    local needStr
    if isFeast then
        needStr = L["FOOD_BONUS_BOTH"]
    elseif need == "hunger" then
        needStr = L["FOOD_BONUS_HUNGER"]
    else
        needStr = L["FOOD_BONUS_THIRST"]
    end
    print(string.format("|cFFFF6600ICN2|r " .. L["FOOD_BONUS_MSG"], needStr, bonus, state.tier))
end

-- ── Main aura handler ────────────────────────────────────────────────────────
-- Entry point called by Core's UNIT_AURA event with the raw updateInfo payload.
-- Step 1: Update the shared aura cache (delta patch or full rebuild).
-- Step 2: Derive food/drink/wellfed state from the now-current cache.
-- State.lua reads ICN2._auraCache directly for campfire/sitting — no extra scan needed.
function ICN2:OnUnitAura(updateInfo)
    -- ── Step 1: maintain the cache ────────────────────────────────────────────
    -- updateInfo == nil is Blizzard's signal for a full refresh (login, reload, etc.)
    if not updateInfo then
        rebuildAuraCache()
    else
        patchAuraCache(updateInfo)
    end

    -- ── Step 2: derive state from cache ───────────────────────────────────────
    if ICN2.State and ICN2.State.inInstance then return end
    if UnitAffectingCombat("player") then return end

    local now = GetTime()

    -- ── Food aura handling ─────────────────────────────────────────────────────
    local foodAura = findAuraInCache(FOOD_AURA_PATTERNS)
    if foodAura then
        if not foodState.active then
            foodState.active    = true
            foodState.startTime = now
            foodState.duration  = foodAura.duration or 30
            foodState.tier      = detectFoodTier(foodAura)
            ICN2DB.wellFedEligible = true
        end
    else
        if foodState.active then
            local elapsed = now - (foodState.startTime or now)
            local natural = elapsed >= (foodState.duration or 30) * 0.85
            applyBonus(foodState, "hunger", natural)
            foodState.active    = false
            foodState.startTime = nil
            foodState.duration  = nil
            foodState.tier      = nil
        end
    end

    -- ── Well Fed aura handling (with eating-linked eligibility) ───────────────
    local wellFedAura = findAuraInCache(WELLFED_PATTERNS)
    if wellFedAura then
        local id = wellFedAura.auraInstanceID or 0
        if id ~= ICN2._lastWellFedInstanceID and ICN2DB.wellFedEligible then
            ICN2._lastWellFedInstanceID = id
            ICN2._wellFedPauseExpiry    = now + WELLFED_PAUSE_SECS
            ICN2DB.wellFedEligible      = false
            
            print(string.format(
                "|cFFFF6600ICN2|r " .. L["WELLFED_MSG"],
                math.floor(WELLFED_PAUSE_SECS / 60)))
        end
    else
        ICN2._lastWellFedInstanceID = nil
    end

    -- ── Drink aura handling ───────────────────────────────────────────────────
    local drinkAura = findAuraInCache(DRINK_AURA_PATTERNS, DRINK_EXTRA_PATTERNS)
    if drinkAura then
        if not drinkState.active then
            drinkState.active    = true
            drinkState.startTime = now
            drinkState.duration  = drinkAura.duration or 30
            drinkState.tier      = detectDrinkTier()
        end
    else
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
function ICN2:GetFoodTier()
    return foodState.tier or "simple"
end

-- Returns the current drink tier: "simple", "complex", or "feast"
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
