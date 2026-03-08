-- ============================================================
-- ICN2_Core.lua  (v1.2.0)
-- Core engine: initialization, decay tick, persistence,
-- situational detection, race/class modifiers.
-- ============================================================

ICN2 = ICN2 or {}

-- ── Internal state ────────────────────────────────────────────────────────────
local frame        = CreateFrame("Frame", "ICN2Frame", UIParent)
local tickInterval = 1.0
local elapsed      = 0

local inCombat   = false
local isSwimming = false

-- Rest stance: "sit" or nil. Set by DetectRestStance() each tick.
-- Retail TWW only exposes UnitIsSitting("player") — no pose granularity.
local restStance = nil

-- Cached armor fatigue modifier. Populated on PLAYER_LOGIN and whenever
-- the chest slot changes (PLAYER_EQUIPMENT_CHANGED). Avoids calling
-- C_Item.GetItemInfo every tick, which can return nil until the item
-- data is server-cached.
local armorFatigueCache = nil

-- Last computed net rates (% per second). Positive = gaining, negative = losing.
ICN2._lastRates             = { hunger = 0, thirst = 0, fatigue = 0 }
ICN2._lastWellFedInstanceID = nil

-- ── Deep copy ─────────────────────────────────────────────────────────────────
local function deepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = (type(v) == "table") and deepCopy(v) or v
    end
    return copy
end

-- ── Init / merge saved variables ─────────────────────────────────────────────
local function initDB()
    if not ICN2DB then
        ICN2DB = deepCopy(ICN2.DEFAULTS)
        ICN2DB.lastLogout = time()
        return
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
end

-- ── Offline decay ─────────────────────────────────────────────────────────────
local function applyOfflineDecay()
    if not ICN2DB.lastLogout then return end
    if ICN2DB.settings.freezeOfflineNeeds then return end

    local delta = math.min(time() - ICN2DB.lastLogout, 8 * 3600)
    if delta <= 0 then return end

    local s      = ICN2DB.settings
    local preset = ICN2.PRESETS[s.preset] or 1.0
    local rest   = ICN2.SITUATION_MODIFIERS.resting

    ICN2DB.hunger  = math.max(0, ICN2DB.hunger  - s.decayRates.hunger  * preset * rest.hunger  * delta)
    ICN2DB.thirst  = math.max(0, ICN2DB.thirst  - s.decayRates.thirst  * preset * rest.thirst  * delta)
    ICN2DB.fatigue = math.max(0, ICN2DB.fatigue - s.decayRates.fatigue * preset * rest.fatigue * delta)

    ICN2:UpdateHUD()
end

-- ── Armor fatigue cache ───────────────────────────────────────────────────────
-- C_Item.GetItemInfo is asynchronous — it queues a server request and
-- returns nil until the item data arrives in the client cache.
-- We call it once on login / equipment change and store the result.
-- The fallback is CLOTH (0.9) so a Warrior with uncached data gets a
-- slightly lower multiplier until the cache populates, which is conservative.
local function refreshArmorCache()
    local itemLink = GetInventoryItemLink("player", 5)  -- chest slot
    if not itemLink then
        armorFatigueCache = ICN2.ARMOR_FATIGUE.CLOTH
        return
    end
    
    -- WoW 12.0 Retail: Use GetItemInfo() global function which returns:
    -- name, link, rarity, level, minLevel, type, subType, stackCount, texture, vendorPrice
    local name, _, _, _, _, itemType, subType = GetItemInfo(itemLink)
    
    if not subType then
        -- Data not yet cached; keep previous value (or default) and retry next equipment change
        if not armorFatigueCache then
            armorFatigueCache = ICN2.ARMOR_FATIGUE.CLOTH
        end
        return
    end
    
    if subType:find("Plate")   then 
        armorFatigueCache = ICN2.ARMOR_FATIGUE.PLATE
    elseif subType:find("Mail") then 
        armorFatigueCache = ICN2.ARMOR_FATIGUE.MAIL
    elseif subType:find("Leather") then 
        armorFatigueCache = ICN2.ARMOR_FATIGUE.LEATHER
    else
        armorFatigueCache = ICN2.ARMOR_FATIGUE.CLOTH
    end
end

-- ── Situation multipliers ─────────────────────────────────────────────────────
local function getSituationMultipliers(collectLabels)
    local mH, mT, mF = 1.0, 1.0, 1.0
    local labels = collectLabels and {} or nil

    if IsResting() then
        local r = ICN2.SITUATION_MODIFIERS.resting
        mH, mT, mF = mH * r.hunger, mT * r.thirst, mF * r.fatigue
        if labels then table.insert(labels, string.format("resting (H×%.2f T×%.2f F×%.2f)", r.hunger, r.thirst, r.fatigue)) end
    else
        if IsMounted() then
            local m = ICN2.SITUATION_MODIFIERS.mounted
            mH, mT, mF = mH * m.hunger, mT * m.thirst, mF * m.fatigue
            if labels then table.insert(labels, string.format("mounted (H×%.2f T×%.2f F×%.2f)", m.hunger, m.thirst, m.fatigue)) end
        end
        if IsFlying() then
            local f = ICN2.SITUATION_MODIFIERS.flying
            mH, mT, mF = mH * f.hunger, mT * f.thirst, mF * f.fatigue
            if labels then table.insert(labels, string.format("flying (H×%.2f T×%.2f F×%.2f)", f.hunger, f.thirst, f.fatigue)) end
        end
        if isSwimming then
            local sw = ICN2.SITUATION_MODIFIERS.swimming
            mH, mT, mF = mH * sw.hunger, mT * sw.thirst, mF * sw.fatigue
            if labels then table.insert(labels, string.format("swimming (H×%.2f T×%.2f F×%.2f)", sw.hunger, sw.thirst, sw.fatigue)) end
        end
        if inCombat then
            local c = ICN2.SITUATION_MODIFIERS.combat
            mH, mT, mF = mH * c.hunger, mT * c.thirst, mF * c.fatigue
            if labels then table.insert(labels, string.format("combat (H×%.2f T×%.2f F×%.2f)", c.hunger, c.thirst, c.fatigue)) end
        end
        if IsIndoors() and not inCombat and not IsMounted() then
            local ind = ICN2.SITUATION_MODIFIERS.indoors
            mH, mT, mF = mH * ind.hunger, mT * ind.thirst, mF * ind.fatigue
            if labels then table.insert(labels, string.format("indoors (H×%.2f T×%.2f F×%.2f)", ind.hunger, ind.thirst, ind.fatigue)) end
        end
    end

    local race = select(2, UnitRace("player"))
    local rm   = ICN2.RACE_MODIFIERS[race]
    if rm then
        mH, mT, mF = mH * rm.hunger, mT * rm.thirst, mF * rm.fatigue
        if labels then table.insert(labels, string.format("race:%s (H×%.2f T×%.2f F×%.2f)", race, rm.hunger, rm.thirst, rm.fatigue)) end
    end

    local _, class = UnitClass("player")
    local cm = ICN2.CLASS_MODIFIERS[class]
    if cm then
        mH, mT, mF = mH * cm.hunger, mT * cm.thirst, mF * cm.fatigue
        if labels then table.insert(labels, string.format("class:%s (H×%.2f T×%.2f F×%.2f)", class, cm.hunger, cm.thirst, cm.fatigue)) end
    end

    return mH, mT, mF, labels
end

-- ── Calculate current net rates ───────────────────────────────────────────────
local function calculateCurrentRates()
    local s        = ICN2DB.settings
    local preset   = ICN2.PRESETS[s.preset] or 1.0
    local mH, mT, mF = getSituationMultipliers()
    local armor    = armorFatigueCache or ICN2.ARMOR_FATIGUE.CLOTH

    local dH = s.decayRates.hunger  * preset * mH
    local dT = s.decayRates.thirst  * preset * mT
    local dF = s.decayRates.fatigue * preset * mF * armor

    local stanceGain = (restStance and ICN2.REST_STANCE_RATES[restStance] or 0)
    
    -- Include recovery rates from eating/drinking
    local foodRecovery = 0
    local drinkRecovery = 0
    
    if ICN2:IsEating() then
        local duration = ICN2:GetFoodDuration() or 30
        foodRecovery = 50.0 / math.max(1, duration)  -- FULL_SESSION_RESTORE / duration
    end
    if ICN2:IsDrinking() then
        local duration = ICN2:GetDrinkDuration() or 30
        drinkRecovery = 50.0 / math.max(1, duration)  -- FULL_SESSION_RESTORE / duration
    end
    
    return {
        hunger  = foodRecovery - dH,
        thirst  = drinkRecovery - dT,
        fatigue = stanceGain - dF,
    }
end

-- ── Public function to get current rates ──────────────────────────────────────
function ICN2:GetCurrentRates()
    return calculateCurrentRates()
end

-- ── Main decay tick ───────────────────────────────────────────────────────────
local function tick()
    local oldH = ICN2DB.hunger
    local oldT = ICN2DB.thirst
    local oldF = ICN2DB.fatigue

    local rates = calculateCurrentRates()
    
    ICN2DB.hunger  = math.max(0, ICN2DB.hunger  + rates.hunger)
    ICN2DB.thirst  = math.max(0, ICN2DB.thirst  + rates.thirst)
    ICN2DB.fatigue = math.max(0, ICN2DB.fatigue + rates.fatigue)

    ICN2._lastRates = rates

    ICN2:UpdateHUD()
    ICN2:CheckEmotes(oldH, oldT, oldF)
end

-- ── Recovery ──────────────────────────────────────────────────────────────────
function ICN2:Eat(amount)
    ICN2DB.hunger = math.min(100, ICN2DB.hunger + (amount or 30))
    self:UpdateHUD()
    self:TriggerEmote("satisfied", "hunger")
end

function ICN2:Drink(amount)
    ICN2DB.thirst = math.min(100, ICN2DB.thirst + (amount or 30))
    self:UpdateHUD()
    self:TriggerEmote("satisfied", "thirst")
end

function ICN2:Rest(amount)
    ICN2DB.fatigue = math.min(100, ICN2DB.fatigue + (amount or 20))
    self:UpdateHUD()
    self:TriggerEmote("satisfied", "fatigue")
end

-- ── Events ────────────────────────────────────────────────────────────────────
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_AURA")

frame:SetScript("OnEvent", function(self, event, ...)
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
        -- Delay armor cache refresh by 1s to allow item data to arrive
        C_Timer.After(1, function() refreshArmorCache() end)
        ICN2:UpdateHUD()

    elseif event == "PLAYER_LOGOUT" then
        ICN2DB.lastLogout = time()

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat   = true
        restStance = nil

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        ICN2:OnCombatBreakFoodDrink()

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = ...
        if slot == 5 then  -- chest slot changed
            refreshArmorCache()
        end

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then ICN2:OnUnitAura() end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then ICN2:HandleAbilityRecovery(spellID) end
    end
end)

-- ── OnUpdate ──────────────────────────────────────────────────────────────────
frame:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed >= tickInterval then
        elapsed = 0
        isSwimming = (IsSubmerged and IsSubmerged()) and true or false
        ICN2:DetectRestStance()
        ICN2:FoodDrinkTick()
        ICN2:RestStanceTick()
        tick()
    end
end)

-- ── Rest stance detection ─────────────────────────────────────────────────────
-- Retail: UnitIsSitting("player") returns true for any seated pose.
-- No API exists to distinguish sit/sleep/kneel in retail, so all map to "sit".
-- Note: UnitIsSitting was removed in Retail 12.0, check if function exists.
function ICN2:DetectRestStance()
    if inCombat or IsMounted() then
        restStance = nil
        return
    end
    -- SafelyCheck if UnitIsSitting exists before calling it
    if UnitIsSitting then
        restStance = UnitIsSitting("player") and "sit" or nil
    else
        restStance = nil
    end
end

-- ── Fatigue recovery tick ─────────────────────────────────────────────────────
function ICN2:RestStanceTick()
    -- Recovery now handled entirely through rate calculations in the main tick
    -- This function is kept for potential future features
end

-- ── Racial / class ability recovery ──────────────────────────────────────────
local ABILITY_RECOVERY = {
    [20577]  = function() ICN2:Eat(40) end,
    [204065] = function() ICN2:Eat(10); ICN2:Rest(10) end,
    [58984]  = function() ICN2:Rest(5) end,
}

function ICN2:HandleAbilityRecovery(spellID)
    if ABILITY_RECOVERY[spellID] then ABILITY_RECOVERY[spellID]() end
end

-- ── /icn2 details ────────────────────────────────────────────────────────────
function ICN2:PrintDetails()
    local s      = ICN2DB.settings
    local preset = ICN2.PRESETS[s.preset] or 1.0
    local mH, mT, mF, situLabels = getSituationMultipliers(true)
    local armor  = armorFatigueCache or ICN2.ARMOR_FATIGUE.CLOTH
    local rates  = ICN2:GetCurrentRates()

    local dH = s.decayRates.hunger  * preset * mH
    local dT = s.decayRates.thirst  * preset * mT
    local dF = s.decayRates.fatigue * preset * mF * armor
    local stanceGain = (restStance and ICN2.REST_STANCE_RATES[restStance] or 0)

    local armorName = "CLOTH"
    if     armor == ICN2.ARMOR_FATIGUE.PLATE   then armorName = "PLATE"
    elseif armor == ICN2.ARMOR_FATIGUE.MAIL    then armorName = "MAIL"
    elseif armor == ICN2.ARMOR_FATIGUE.LEATHER then armorName = "LEATHER"
    end

    local P   = "|cFFFF6600ICN2|r"
    local sep = "|cFF555555--------------------------------|r"

    print(P .. " |cFFFFFF00Details|r — preset: " .. s.preset .. string.format(" (x%.2f)", preset))
    print(sep)
    print(string.format(P .. " |cFF00FF00Hunger|r  %.1f%%  net %+.4f%%/s",  ICN2DB.hunger,  rates.hunger))
    print(string.format(P .. " |cFF4499FFThirst|r  %.1f%%  net %+.4f%%/s",  ICN2DB.thirst,  rates.thirst))
    print(string.format(P .. " |cFFFFDD00Fatigue|r %.1f%%  net %+.4f%%/s  (stance %+.4f/s)", ICN2DB.fatigue, rates.fatigue, stanceGain))
    print(sep)
    print(P .. " |cFFAAAAAASituation modifiers:|r")
    if #situLabels == 0 then
        print("  |cFF888888none (walking/idle outdoors)|r")
    else
        for _, lbl in ipairs(situLabels) do print("  |cFFCCCCCC" .. lbl .. "|r") end
    end
    print(string.format("  |cFFCCCCCCarmor:%s (F x%.2f)|r", armorName, armor))
    if restStance then
        print(string.format("  |cFFCCCCCCstance:%s (+%.4f%%/s fatigue)|r", restStance, stanceGain))
    end
    print(sep)
    if ICN2:IsEating()   then print(P .. " |cFF00FF00Currently eating|r")   end
    if ICN2:IsDrinking() then print(P .. " |cFF4499FFCurrently drinking|r") end
end

-- ── Slash commands ────────────────────────────────────────────────────────────
SLASH_ICN21 = "/icn2"
SlashCmdList["ICN2"] = function(msg)
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
        ICN2:UpdateHUD(); print("|cFFFF6600ICN2|r Needs reset to 100%%.")
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
        print("|cFFFF6600ICN2|r Commands: |cFFFFFF00/icn2|r [show|eat|drink|rest|reset|status|details|hud|lock]")
    end
end
