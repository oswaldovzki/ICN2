-- ============================================================
-- Core engine: initialization, tick scheduler, persistence, rate engine, and module coordination.--
-- Pipeline
--   Game World
--     ↓
--   ICN2_State.lua  — ICN2:UpdateState()
--     writes ICN2.State (inCombat, isSwimming, isSitting, …)
--     ↓
--   Rate Engine  — ICN2:GetCurrentRates()
--     reads ICN2.State, never calls WoW APIs directly
--     └─ _ApplyBaseDecay
--     └─ _ApplySituationModifiers
--     └─ _ApplyRaceClassModifiers
--     └─ _ApplyArmorModifier
--     └─ _ApplyFoodDrinkRecovery
--     └─ _ApplyFatigueRecovery
--     └─ _ApplyWellFedPause
--     ↓
--   tick()  — applies rates → clamp → HUD → emotes
--
-- Core owns: scheduler, persistence, rate engine, events.
-- Core does NOT own: condition detection (→ ICN2_State.lua).
-- ============================================================

ICN2 = ICN2 or {}

-- ── Frame and tick ────────────────────────────────────────────────────────────
local frame        = CreateFrame("Frame", "ICN2Frame", UIParent)
local tickInterval = 1.0
local elapsed      = 0

-- ── Armor fatigue cache ───────────────────────────────────────────────────────
-- GetItemInfo is async — we cache on login/equipment-change and never call it from inside the tick or the rate engine.
local armorFatigueCache = nil

-- ── Public state (read by HUD, FoodDrink, PrintDetails) ──────────────────────
ICN2._lastRates             = { hunger = 0, thirst = 0, fatigue = 0 }
ICN2._lastWellFedInstanceID = nil
ICN2._wellFedPauseExpiry    = 0      -- GetTime() timestamp; 0 = not active
ICN2._fatigueRecoveryTier   = "none" -- "none" | "slow" | "fast"  (for PrintDetails)
ICN2._fatigueRecoverySrc    = ""     -- human-readable source list (for PrintDetails)

-- ══ SECTION 1 — Initialization helpers ════════════════════════════════════════
local function deepCopy(orig) -- for copying tables from DEFAULTS into the saved variable without reference links
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = (type(v) == "table") and deepCopy(v) or v
    end
    return copy
end

local function migrateCustomDecayBiasFromLegacy()
    local maxM = ICN2.CUSTOM_DECAY_MULTIPLIER_MAX or 30
    local cb = ICN2DB.settings.customDecayBias
    if not cb then
        ICN2DB.settings.customDecayBias = deepCopy(ICN2.DEFAULTS.settings.customDecayBias)
        return
    end
    for _, need in ipairs({ "hunger", "thirst", "fatigue" }) do
        local v = cb[need]
        if v == nil then
            cb[need] = 1
        else
            v = tonumber(v) or 0
            local vi = math.floor(v + 0.5)
            -- Legacy -10..10 bias scale → multiplier, then integer 0..maxM
            if v >= -10 and v <= 10 and math.abs(v - vi) < 0.001 then
                local m = math.max(0, 1 + vi * 0.2)
                cb[need] = math.max(0, math.min(maxM, math.floor(m + 0.5)))
            else
                cb[need] = math.max(0, math.min(maxM, vi))
            end
        end
    end
end

local function initDB() -- ensures all keys from ICN2.DEFAULTS are present in ICN2DB, without overwriting existing values
    if not ICN2DB then
        ICN2DB = deepCopy(ICN2.DEFAULTS)
        ICN2DB.lastLogout = time()
        return
    end
    -- One-time: old -10..10 custom scale → 0..max (must run before merging customDecayBiasVersion from defaults)
    if ICN2DB.settings.customDecayBiasVersion ~= 2 then
        migrateCustomDecayBiasFromLegacy()
        ICN2DB.settings.customDecayBiasVersion = 2
    end
    for k, v in pairs(ICN2.DEFAULTS) do
        if ICN2DB[k] == nil then
            ICN2DB[k] = (type(v) == "table") and deepCopy(v) or v
        end
    end
    for k, v in pairs(ICN2.DEFAULTS.settings) do
        if ICN2DB.settings[k] == nil then
            ICN2DB.settings[k] = (type(v) == "table") and deepCopy(v) or v
        end
    end
    -- Nested merge for customDecayBias (added after v1.0 saves)
    local dcb = ICN2.DEFAULTS.settings.customDecayBias
    if not ICN2DB.settings.customDecayBias then
        ICN2DB.settings.customDecayBias = deepCopy(dcb)
    else
        for k, v in pairs(dcb) do
            if ICN2DB.settings.customDecayBias[k] == nil then
                ICN2DB.settings.customDecayBias[k] = v
            end
        end
    end
end

-- ── Custom decay slider (0..CUSTOM_DECAY_MULTIPLIER_MAX) ───────────────────
-- Value is passive decay multiplier vs Medium (1×). 0 = no passive decay; max = 10× Fast.

function ICN2:DecayBiasToMultiplier(bias)
    local maxM = ICN2.CUSTOM_DECAY_MULTIPLIER_MAX or 30
    local b = tonumber(bias) or 0
    if b < 0 then b = 0 elseif b > maxM then b = maxM end
    return b
end

-- Preset global multiplier (e.g. fast = 3.0) → same integer scale as the custom sliders (read-only).
function ICN2:PresetMultiplierToBiasDisplay(mult)
    local maxM = ICN2.CUSTOM_DECAY_MULTIPLIER_MAX or 30
    local m = tonumber(mult) or 1
    return math.max(0, math.min(maxM, math.floor(m + 0.5)))
end

function ICN2:GetEffectiveDecayMultiplier(needKey)
    local s = ICN2DB.settings
    if s.preset == "custom" then
        local cb = s.customDecayBias
        local bias = (cb and cb[needKey])
        if bias == nil then bias = 1 end
        return self:DecayBiasToMultiplier(bias)
    end
    return ICN2.PRESETS[s.preset] or 1.0
end

-- ── Offline decay ─────────────────────────────────────────────────────────────
local function applyOfflineDecay() -- applies decay based on the time elapsed since last logout, up to a max of 8 hours
    if not ICN2DB.lastLogout then return end
    if ICN2DB.settings.freezeOfflineNeeds then return end

    local delta = math.min(time() - ICN2DB.lastLogout, 8 * 3600)
    if delta <= 0 then return end

    local s    = ICN2DB.settings
    local rest = ICN2.SITUATION_MODIFIERS.resting

    local mh = ICN2:GetEffectiveDecayMultiplier("hunger")
    local mt = ICN2:GetEffectiveDecayMultiplier("thirst")
    local mf = ICN2:GetEffectiveDecayMultiplier("fatigue")

    ICN2DB.hunger  = math.max(0, ICN2DB.hunger  - s.decayRates.hunger  * mh * rest.hunger  * delta)
    ICN2DB.thirst  = math.max(0, ICN2DB.thirst  - s.decayRates.thirst  * mt * rest.thirst  * delta)
    ICN2DB.fatigue = math.max(0, ICN2DB.fatigue - s.decayRates.fatigue * mf * rest.fatigue * delta)

    ICN2:UpdateHUD()
end

-- ── Armor cache ───────────────────────────────────────────────────────────────
local function refreshArmorCache() -- checks the player's equipped chest armor and updates armorFatigueCache accordingly; defaults to CLOTH if info is unavailable
    local itemLink = GetInventoryItemLink("player", 5)
    if not itemLink then
        armorFatigueCache = ICN2.ARMOR_FATIGUE.CLOTH
        return
    end
---@diagnostic disable-next-line: deprecated
    local _, _, _, _, _, _, subType = GetItemInfo(itemLink)
    if not subType then
        if not armorFatigueCache then armorFatigueCache = ICN2.ARMOR_FATIGUE.CLOTH end
        return
    end
    if     subType:find("Plate")   then armorFatigueCache = ICN2.ARMOR_FATIGUE.PLATE
    elseif subType:find("Mail")    then armorFatigueCache = ICN2.ARMOR_FATIGUE.MAIL
    elseif subType:find("Leather") then armorFatigueCache = ICN2.ARMOR_FATIGUE.LEATHER
    else                                armorFatigueCache = ICN2.ARMOR_FATIGUE.CLOTH
    end
end

-- ══ SECTION 2 — Condition detection ════════════════════════════════════════════
-- ICN2:UpdateState() is called from OnUpdate each tick.
-- ICN2.State is the single source of truth for all condition flags.
-- These stubs exist only for backward compatibility with any external callers.

function ICN2:DetectConditions()
    ICN2:UpdateState()
end

function ICN2:DetectFatigueRecovery()
    ICN2:UpdateState()
end

-- ══ SECTION 3 — Rate Engine ════════════════════════════════════════════════════
-- Each modifier function receives the rates table and mutates it.
-- Sign convention: positive rate = gaining (recovery), negative = losing (decay).
-- The engine builds up a net rate per need in % per second.
--
-- Pipeline:
--   GetCurrentRates()
--     1. _ApplyBaseDecay          → sets the starting negative rate
--     2. _ApplySituationModifiers → scales rates by activity/location
--     3. _ApplyRaceClassModifiers → scales rates by biological traits
--     4. _ApplyArmorModifier      → scales fatigue decay by armor type
--     5. _ApplyFoodDrinkRecovery  → adds positive recovery while eating/drinking
--     6. _ApplyFatigueRecovery    → adds positive fatigue recovery when resting
--     7. _ApplyWellFedPause       → zeroes hunger decay when Well Fed is active

-- ── 1. Base decay ─────────────────────────────────────────────────────────────
function ICN2:_ApplyBaseDecay(rates) -- applies the configured base rates × preset (or custom per-need bias) as negative values.
    local s = ICN2DB.settings

    local mh = ICN2:GetEffectiveDecayMultiplier("hunger")
    local mt = ICN2:GetEffectiveDecayMultiplier("thirst")
    local mf = ICN2:GetEffectiveDecayMultiplier("fatigue")

    rates.hunger  = rates.hunger  - s.decayRates.hunger  * mh
    rates.thirst  = rates.thirst  - s.decayRates.thirst  * mt
    rates.fatigue = rates.fatigue - s.decayRates.fatigue * mf
end

-- ── 2. Situation modifiers ────────────────────────────────────────────────────
-- Scales the current rates by activity/location multipliers from ICN2_Data. Multipliers > 1 = faster decay, < 1 = slower decay.
function ICN2:_ApplySituationModifiers(rates) -- reads ICN2.State and applies the relevant modifiers from ICN2.SITUATION_MODIFIERS
    local sm = ICN2.SITUATION_MODIFIERS
    local st = ICN2.State

    if st.isResting then -- resting is exclusive; if true, skip all other modifiers
        rates.hunger  = rates.hunger  * sm.resting.hunger
        rates.thirst  = rates.thirst  * sm.resting.thirst
        rates.fatigue = rates.fatigue * sm.resting.fatigue
        return  -- resting is exclusive; skip all other situations
    end

    if st.isMounted then -- mounting is not exclusive; it can stack with combat, flying, indoors, etc., but not resting
        rates.hunger  = rates.hunger  * sm.mounted.hunger
        rates.thirst  = rates.thirst  * sm.mounted.thirst
        rates.fatigue = rates.fatigue * sm.mounted.fatigue
    end
    if st.isFlying then -- flying is not exclusive; it can stack with mounted, combat, indoors, etc., but not resting
        rates.hunger  = rates.hunger  * sm.flying.hunger
        rates.thirst  = rates.thirst  * sm.flying.thirst
        rates.fatigue = rates.fatigue * sm.flying.fatigue
    end
    if st.isSwimming then -- swimming is not exclusive; it can stack with combat, indoors, etc., but not resting or mounted
        rates.hunger  = rates.hunger  * sm.swimming.hunger
        rates.thirst  = rates.thirst  * sm.swimming.thirst
        rates.fatigue = rates.fatigue * sm.swimming.fatigue
    end
    if st.inCombat then -- combat is not exclusive; it can stack with flying, swimming, etc., but not resting or mounted
        rates.hunger  = rates.hunger  * sm.combat.hunger
        rates.thirst  = rates.thirst  * sm.combat.thirst
        rates.fatigue = rates.fatigue * sm.combat.fatigue
    end
    if st.isIndoors and not st.inCombat and not st.isMounted then -- indoors is exclusive with combat and mounting, but can stack with flying, swimming, etc.
        rates.hunger  = rates.hunger  * sm.indoors.hunger
        rates.thirst  = rates.thirst  * sm.indoors.thirst
        rates.fatigue = rates.fatigue * sm.indoors.fatigue
    end
end

-- ── 3. Race + class modifiers ─────────────────────────────────────────────────
function ICN2:_ApplyRaceClassModifiers(rates) -- Scales the current rates by biological trait multipliers from ICN2_Data.
    local race = select(2, UnitRace("player"))
    local rm   = ICN2.RACE_MODIFIERS[race]
    if rm then
        rates.hunger  = rates.hunger  * rm.hunger
        rates.thirst  = rates.thirst  * rm.thirst
        rates.fatigue = rates.fatigue * rm.fatigue
    end

    local _, class = UnitClass("player")
    local cm = ICN2.CLASS_MODIFIERS[class]
    if cm then
        rates.hunger  = rates.hunger  * cm.hunger
        rates.thirst  = rates.thirst  * cm.thirst
        rates.fatigue = rates.fatigue * cm.fatigue
    end
end

-- ── 4. Armor modifier ─────────────────────────────────────────────────────────
function ICN2:_ApplyArmorModifier(rates) -- Scales fatigue decay by armor type. Uses the cached armorFatigueCache set by refreshArmorCache(), or defaults to CLOTH if the cache is not yet available.
    local armor = armorFatigueCache or ICN2.ARMOR_FATIGUE.CLOTH
    rates.fatigue = rates.fatigue * armor
end

-- ── 5. Food / drink recovery ──────────────────────────────────────────────────
-- Adds a positive trickle to hunger/thirst while the eating/drinking buff is active. The trickle is spread evenly over the buff duration.
local FOOD_TRICKLE = { simple = 30.0, complex = 40.0, feast = 60.0 }

function ICN2:_ApplyFoodDrinkRecovery(rates) -- checks for active food/drink buffs and applies the appropriate trickle recovery based on tier and duration; also applies thirst recovery during feasts
    if ICN2:IsEating() then
        local duration = ICN2:GetFoodDuration() or 30
        local tier     = ICN2:GetFoodTier()
        local trickle  = FOOD_TRICKLE[tier] or FOOD_TRICKLE.simple
        local perSec   = trickle / math.max(1, duration)
        rates.hunger   = rates.hunger + perSec
        -- Feasts also restore thirst during the eating animation
        if tier == "feast" then
            rates.thirst = rates.thirst + perSec
        end
    end

    if ICN2:IsDrinking() then
        local duration = ICN2:GetDrinkDuration() or 30
        local tier     = ICN2:GetDrinkTier()
        local trickle  = FOOD_TRICKLE[tier] or FOOD_TRICKLE.simple
        rates.thirst   = rates.thirst + (trickle / math.max(1, duration))
    end
end

-- ── 6. Fatigue recovery ───────────────────────────────────────────────────────
-- Tiers:
--   fast → IsResting() AND (nearCampfire OR inHousing)   — ~2 min to full
--   slow → any single condition                           — ~5 min to full
--   none → no qualifying condition, or in combat
function ICN2:_ApplyFatigueRecovery(rates) -- checks for qualifying conditions and applies the appropriate fatigue recovery; also sets _fatigueRecoveryTier and _fatigueRecoverySrc for PrintDetails
    local st = ICN2.State

    if st.inCombat then
        ICN2._fatigueRecoveryTier = "none"
        ICN2._fatigueRecoverySrc  = ""
        return
    end

    local isEatDrink = ICN2:IsEating() or ICN2:IsDrinking()
    local src        = {}
    local gain       = 0
    local tier       = "none"

    if st.isResting and (st.nearCampfire or st.inHousing) then
        gain = ICN2.FATIGUE_RECOVERY.fast
        tier = "fast"
        table.insert(src, "rested area")
        if st.nearCampfire then table.insert(src, "campfire") end
        if st.inHousing    then table.insert(src, "housing")  end

    elseif st.isResting or st.isSitting or st.nearCampfire or st.inHousing or isEatDrink then
        gain = ICN2.FATIGUE_RECOVERY.slow
        tier = "slow"
        if st.isResting    then table.insert(src, "rested area")     end
        if st.isSitting    then table.insert(src, "sitting")         end
        if st.nearCampfire then table.insert(src, "campfire")        end
        if st.inHousing    then table.insert(src, "housing")         end
        if isEatDrink      then table.insert(src, "eating/drinking") end
    end

    rates.fatigue             = rates.fatigue + gain
    ICN2._fatigueRecoveryTier = tier
    ICN2._fatigueRecoverySrc  = table.concat(src, ", ")
end

-- ── 7. Well Fed pause ─────────────────────────────────────────────────────────
function ICN2:_ApplyWellFedPause(rates) -- if the Well Fed buff was refreshed within the last 5 minutes, pause hunger decay by zeroing out any negative hunger rate; does not affect thirst or fatigue
    if ICN2._wellFedPauseExpiry and GetTime() < ICN2._wellFedPauseExpiry then
        if rates.hunger < 0 then rates.hunger = 0 end
    end
end

-- ── GetCurrentRates — the single public entry point ───────────────────────────
function ICN2:GetCurrentRates() -- calculates the current hunger/thirst/fatigue rates by applying all modifiers in sequence and returns a table with the final rates; also updates _lastRates for external access and debugging
    local rates = { hunger = 0, thirst = 0, fatigue = 0 }

    self:_ApplyBaseDecay(rates)
    self:_ApplySituationModifiers(rates)
    self:_ApplyRaceClassModifiers(rates)
    self:_ApplyArmorModifier(rates)
    self:_ApplyFoodDrinkRecovery(rates)
    self:_ApplyFatigueRecovery(rates)
    self:_ApplyWellFedPause(rates)

    return rates
end

-- ══ SECTION 4 — Tick ═══════════════════════════════════════════════════════════
local function clamp(v) -- utility function to clamp a value between 0 and 100
    if v < 0   then return 0   end
    if v > 100 then return 100 end
    return v
end

local function tick() -- applies the current rates to the player's hunger/thirst/fatigue, clamps the values, updates the HUD, and triggers emotes based on thresholds
    local oldH = ICN2DB.hunger
    local oldT = ICN2DB.thirst
    local oldF = ICN2DB.fatigue

    local rates = ICN2:GetCurrentRates()

    ICN2DB.hunger  = clamp(ICN2DB.hunger  + rates.hunger)
    ICN2DB.thirst  = clamp(ICN2DB.thirst  + rates.thirst)
    ICN2DB.fatigue = clamp(ICN2DB.fatigue + rates.fatigue)

    ICN2._lastRates = rates

    ICN2:UpdateHUD()
    ICN2:CheckEmotes(oldH, oldT, oldF)
end

-- ══ SECTION 5 ══════════════════════════════════════════════════════════════════
-- Manual recovery (slash commands / options panel)
function ICN2:Eat(amount)
    ICN2DB.hunger = clamp(ICN2DB.hunger + (amount or 30))
    self:UpdateHUD()
    self:TriggerEmote("satisfied", "hunger")
end

function ICN2:Drink(amount)
    ICN2DB.thirst = clamp(ICN2DB.thirst + (amount or 30))
    self:UpdateHUD()
    self:TriggerEmote("satisfied", "thirst")
end

function ICN2:Rest(amount)
    ICN2DB.fatigue = clamp(ICN2DB.fatigue + (amount or 20))
    self:UpdateHUD()
    self:TriggerEmote("satisfied", "fatigue")
end

-- ══ SECTION 6 — Events ═════════════════════════════════════════════════════════

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_AURA")

frame:SetScript("OnEvent", function(self, event, ...) -- main event handler for addon lifecycle, combat state, equipment changes, spell casts, and aura updates
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "ICN2" then
            initDB()
            ICN2:BuildHUD()
            ICN2:BuildOptions()
            print("|cFFFF6600ICN2|r loaded. Type |cFFFFFF00/icn2|r for options.")
        end

    elseif event == "PLAYER_LOGIN" then
        applyOfflineDecay()
        C_Timer.After(1, function() refreshArmorCache() end)
        ICN2:UpdateHUD()

    elseif event == "PLAYER_LOGOUT" then
        ICN2DB.lastLogout = time()

    elseif event == "PLAYER_REGEN_DISABLED" then
        ICN2.State.inCombat = true

    elseif event == "PLAYER_REGEN_ENABLED" then
        ICN2.State.inCombat = false
        ICN2:OnCombatBreakFoodDrink()

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = ...
        if slot == 5 then refreshArmorCache() end

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then ICN2:OnUnitAura() end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then ICN2:HandleAbilityRecovery(spellID) end
    end
end)

-- ── OnUpdate ──────────────────────────────────────────────────────────────────
frame:SetScript("OnUpdate", function(self, dt) -- accumulates elapsed time and triggers a tick when the interval is reached; also calls UpdateState and stubs for future use
    elapsed = elapsed + dt
    if elapsed >= tickInterval then
        elapsed = 0
        ICN2:UpdateState()    -- refresh ICN2.State before the rate engine runs
        ICN2:FoodDrinkTick()  -- stub; kept for future use
        ICN2:RestStanceTick() -- stub; kept for future use
        tick()
    end
end)

-- ── Stubs ─────────────────────────────────────────────────────────────────────
function ICN2:RestStanceTick() end -- stub for future use; called each tick after UpdateState, currently does nothing

-- ══ SECTION 7 — Racial / class ability recovery ════════════════════════════════

local ABILITY_RECOVERY = {
    [20577]  = function() ICN2:Eat(40)  end,   -- Cannibalize
    [108968] = function() ICN2:Drink(40) end,  -- Symbiosis (water)
    [204065] = function() ICN2:Eat(10); ICN2:Rest(10) end, -- Spirit Mend
    [58984]  = function() ICN2:Rest(5)  end, -- Shadowmeld
}

function ICN2:HandleAbilityRecovery(spellID)
    if ABILITY_RECOVERY[spellID] then ABILITY_RECOVERY[spellID]() end
end

-- ══ SECTION 8 — /icn2 details ══════════════════════════════════════════════════
local function getSituationLabels() -- generates a list of active situation labels with their corresponding modifiers for display in the /icn2 details output
    local labels = {}
    local sm = ICN2.SITUATION_MODIFIERS
    local st = ICN2.State

    if st.isResting then
        table.insert(labels, string.format("resting (H×%.2f T×%.2f F×%.2f)",
            sm.resting.hunger, sm.resting.thirst, sm.resting.fatigue))
        return labels  -- resting is exclusive
    end
    if st.isMounted then
        table.insert(labels, string.format("mounted (H×%.2f T×%.2f F×%.2f)",
            sm.mounted.hunger, sm.mounted.thirst, sm.mounted.fatigue))
    end
    if st.isFlying then
        table.insert(labels, string.format("flying (H×%.2f T×%.2f F×%.2f)",
            sm.flying.hunger, sm.flying.thirst, sm.flying.fatigue))
    end
    if st.isSwimming then
        table.insert(labels, string.format("swimming (H×%.2f T×%.2f F×%.2f)",
            sm.swimming.hunger, sm.swimming.thirst, sm.swimming.fatigue))
    end
    if st.inCombat then
        table.insert(labels, string.format("combat (H×%.2f T×%.2f F×%.2f)",
            sm.combat.hunger, sm.combat.thirst, sm.combat.fatigue))
    end
    if st.isIndoors and not st.inCombat and not st.isMounted then
        table.insert(labels, string.format("indoors (H×%.2f T×%.2f F×%.2f)",
            sm.indoors.hunger, sm.indoors.thirst, sm.indoors.fatigue))
    end

    local race = select(2, UnitRace("player"))
    local rm   = ICN2.RACE_MODIFIERS[race]
    if rm then
        table.insert(labels, string.format("race:%s (H×%.2f T×%.2f F×%.2f)",
            race, rm.hunger, rm.thirst, rm.fatigue))
    end

    local _, class = UnitClass("player")
    local cm = ICN2.CLASS_MODIFIERS[class]
    if cm then
        table.insert(labels, string.format("class:%s (H×%.2f T×%.2f F×%.2f)",
            class, cm.hunger, cm.thirst, cm.fatigue))
    end

    return labels
end

function ICN2:PrintDetails() -- prints detailed information about the current rates, active modifiers, and recovery sources to the chat window for debugging and transparency; called by /icn2 details
    local s = ICN2DB.settings
    local mh = ICN2:GetEffectiveDecayMultiplier("hunger")
    local mt = ICN2:GetEffectiveDecayMultiplier("thirst")
    local mf = ICN2:GetEffectiveDecayMultiplier("fatigue")
    local rates  = ICN2:GetCurrentRates()
    local armor  = armorFatigueCache or ICN2.ARMOR_FATIGUE.CLOTH
    local labels = getSituationLabels()

    local armorName = "CLOTH"
    if     armor == ICN2.ARMOR_FATIGUE.PLATE   then armorName = "PLATE"
    elseif armor == ICN2.ARMOR_FATIGUE.MAIL    then armorName = "MAIL"
    elseif armor == ICN2.ARMOR_FATIGUE.LEATHER then armorName = "LEATHER"
    end

    local fatigueGain = (ICN2._fatigueRecoveryTier == "fast" and ICN2.FATIGUE_RECOVERY.fast)
                     or (ICN2._fatigueRecoveryTier == "slow" and ICN2.FATIGUE_RECOVERY.slow)
                     or 0

    local P   = "|cFFFF6600ICN2|r"
    local sep = "|cFF555555--------------------------------|r"

    local presetLine
    if s.preset == "custom" then
        local function pbPrint(cb, key)
            if not cb or cb[key] == nil then return 1 end
            return math.floor(cb[key])
        end
        presetLine = string.format(
            "custom — H×%.2f  T×%.2f  F×%.2f  (multiplier %d / %d / %d)",
            mh, mt, mf,
            pbPrint(s.customDecayBias, "hunger"),
            pbPrint(s.customDecayBias, "thirst"),
            pbPrint(s.customDecayBias, "fatigue")
        )
    else
        local dispBias = ICN2:PresetMultiplierToBiasDisplay(ICN2.PRESETS[s.preset] or 1.0)
        presetLine = string.format("%s (global ×%.2f — slider display %d on 0–%d scale)",
            s.preset, ICN2.PRESETS[s.preset] or 1.0,
            dispBias,
            ICN2.CUSTOM_DECAY_MULTIPLIER_MAX or 30)
    end
    print(P .. " |cFFFFFF00Details|r — " .. presetLine)
    print(sep)
    print(string.format(P .. " |cFF00FF00Hunger|r  %.1f%%  net %+.4f%%/s",  ICN2DB.hunger,  rates.hunger))
    print(string.format(P .. " |cFF4499FFThirst|r  %.1f%%  net %+.4f%%/s",  ICN2DB.thirst,  rates.thirst))
    print(string.format(P .. " |cFFFFDD00Fatigue|r %.1f%%  net %+.4f%%/s  (recovery %+.4f/s [%s])",
        ICN2DB.fatigue, rates.fatigue, fatigueGain, ICN2._fatigueRecoveryTier))
    print(sep)
    print(P .. " |cFFAAAAAAActive modifiers:|r")
    if #labels == 0 then
        print("  |cFF888888none (walking/idle outdoors)|r")
    else
        for _, lbl in ipairs(labels) do print("  |cFFCCCCCC" .. lbl .. "|r") end
    end
    print(string.format("  |cFFCCCCCCarmor:%s (F×%.2f)|r", armorName, armor))
    if ICN2._fatigueRecoveryTier ~= "none" then
        print(string.format("  |cFFCCCCCCfatigue recovery: %s — sources: %s|r",
            ICN2._fatigueRecoveryTier,
            ICN2._fatigueRecoverySrc ~= "" and ICN2._fatigueRecoverySrc or "n/a"))
    end
    print(sep)
    if ICN2:IsEating() then
        print(string.format(P .. " |cFF00FF00Currently eating|r  (tier: %s)", ICN2:GetFoodTier()))
    end
    if ICN2:IsDrinking() then
        print(string.format(P .. " |cFF4499FFCurrently drinking|r (tier: %s)", ICN2:GetDrinkTier()))
    end
    local wfExpiry = ICN2._wellFedPauseExpiry or 0
    if wfExpiry > 0 and GetTime() < wfExpiry then
        local remaining = math.ceil(wfExpiry - GetTime())
        print(string.format(P .. " |cFF00FF00Well Fed|r — hunger decay paused (%ds remaining)", remaining))
    end
end

-- ══ SECTION 9 — Slash commands ═════════════════════════════════════════════════
SLASH_ICN21 = "/icn2"
SlashCmdList["ICN2"] = function(msg) -- handles slash commands for showing the options panel, manually eating/drinking/resting, resetting needs, etc, called when the user types /icn2 followed by a command
    msg = msg:lower():trim()
    if msg == "show" or msg == "" then
        ICN2:ToggleOptions()
    elseif msg == "eat" then
        ICN2:Eat(50); print("|cFFFF6600ICN2|r You eat something. Hunger restored.")
    elseif msg == "drink" then
        ICN2:Drink(50); print("|cFFFF6600ICN2|r You drink something. Thirst restored.")
    elseif msg == "rest" then
        ICN2:Rest(40); print("|cFFFF6600ICN2|r You rest. Fatigue restored.")
    elseif msg == "reset" then
        ICN2DB.hunger = 100; ICN2DB.thirst = 100; ICN2DB.fatigue = 100
        ICN2:UpdateHUD(); print("|cFFFF6600ICN2|r Needs reset to 100%.")
    elseif msg == "starve" then
        ICN2DB.hunger = 0; ICN2:UpdateHUD()
        print("|cFFFF6600ICN2|r |cFF00FF00Hunger|r set to 0%.")
    elseif msg == "dehydrate" then
        ICN2DB.thirst = 0; ICN2:UpdateHUD()
        print("|cFFFF6600ICN2|r |cFF4499FFThirst|r set to 0%.")
    elseif msg == "exhaust" then
        ICN2DB.fatigue = 0; ICN2:UpdateHUD()
        print("|cFFFF6600ICN2|r |cFFFFDD00Fatigue|r set to 0%.")
    elseif msg == "status" then
        print(string.format("|cFFFF6600ICN2|r Hunger: |cFF00FF00%.1f%%|r  Thirst: |cFF4499FF%.1f%%|r  Fatigue: |cFFFFDD00%.1f%%|r",
            ICN2DB.hunger, ICN2DB.thirst, ICN2DB.fatigue))
    elseif msg == "details" then
        ICN2:PrintDetails()
    elseif msg == "hud" then
        ICN2DB.settings.hudEnabled = not ICN2DB.settings.hudEnabled
        ICN2:UpdateHUD()
        print("|cFFFF6600ICN2|r HUD " .. (ICN2DB.settings.hudEnabled and "|cFF00FF00enabled|r" or "|cFFFF0000disabled|r"))
    elseif msg == "lock" then
        ICN2DB.settings.hudLocked = not ICN2DB.settings.hudLocked
        ICN2:LockHUD(ICN2DB.settings.hudLocked)
        print("|cFFFF6600ICN2|r HUD " .. (ICN2DB.settings.hudLocked and "|cFFFF0000locked|r" or "|cFF00FF00unlocked|r"))
    else
        print("|cFFFF6600ICN2|r Commands: |cFFFFFF00/icn2|r [show|eat|drink|rest|reset|starve|dehydrate|exhaust|status|details|hud|lock]")
    end
end
    