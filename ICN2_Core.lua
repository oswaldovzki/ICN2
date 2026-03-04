-- ============================================================
-- ICN2_Core.lua
-- Core engine: initialization, decay tick, persistence,
-- situational detection, race/class modifiers.
-- ============================================================

ICN2 = ICN2 or {}

-- ── Internal state ────────────────────────────────────────────────────────────
local frame = CreateFrame("Frame", "ICN2Frame", UIParent)
local tickInterval = 1.0   -- seconds between decay ticks
local elapsed      = 0

-- Track event-driven state
local inCombat   = false
local isSwimming = false

-- ── Deep copy utility ─────────────────────────────────────────────────────────
local function deepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- ── Initialize / merge saved variables ───────────────────────────────────────
local function initDB()
    if not ICN2DB then
        ICN2DB = deepCopy(ICN2.DEFAULTS)
        ICN2DB.lastLogout = time()
        return
    end

    -- Merge any missing keys from defaults (handles addon upgrades)
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

-- ── Calculate offline decay ───────────────────────────────────────────────────
-- When the player logs back in, time has passed. We simulate it using
-- an average "resting" multiplier (generous — they were offline, after all).
-- v1.1: skipped entirely if freezeOfflineNeeds is enabled.
local function applyOfflineDecay()
    if not ICN2DB.lastLogout then return end
    if ICN2DB.settings.freezeOfflineNeeds then return end  -- v1.1: frozen offline

    local now       = time()
    local delta     = now - ICN2DB.lastLogout
    if delta <= 0 then return end

    -- Cap offline time at 8 real-world hours to avoid draining to 0 after
    -- a long absence — realism, not punishment.
    delta = math.min(delta, 8 * 3600)

    local s = ICN2DB.settings
    local preset = ICN2.PRESETS[s.preset] or 1.0
    local rest   = ICN2.SITUATION_MODIFIERS.resting

    ICN2DB.hunger  = math.max(0, ICN2DB.hunger  - (s.decayRates.hunger  * preset * rest.hunger  * delta))
    ICN2DB.thirst  = math.max(0, ICN2DB.thirst  - (s.decayRates.thirst  * preset * rest.thirst  * delta))
    ICN2DB.fatigue = math.max(0, ICN2DB.fatigue - (s.decayRates.fatigue * preset * rest.fatigue * delta))

    ICN2:UpdateHUD()
end

-- ── Build combined decay modifier for this tick ───────────────────────────────
local function getSituationMultipliers()
    local mH, mT, mF = 1.0, 1.0, 1.0

    -- Resting (inn / capital city rested state)
    if IsResting() then
        local r = ICN2.SITUATION_MODIFIERS.resting
        mH, mT, mF = mH * r.hunger, mT * r.thirst, mF * r.fatigue
        return mH, mT, mF   -- resting overrides everything else
    end

    -- Mounted
    if IsMounted() then
        local m = ICN2.SITUATION_MODIFIERS.mounted
        mH, mT, mF = mH * m.hunger, mT * m.thirst, mF * m.fatigue
    end

    -- Flying (subset of mounted but distinct modifier for fatigue)
    if IsFlying() then
        local f = ICN2.SITUATION_MODIFIERS.flying
        mH, mT, mF = mH * f.hunger, mT * f.thirst, mF * f.fatigue
    end

    -- Swimming (IsFalling() doubles as underwater check via IsSubmerged if
    -- available, but we track UNIT_ENTERING_VEHICLE / move flags via combat log.
    -- We use a simple heuristic: IsSubmerged exists in some builds.)
    if isSwimming then
        local sw = ICN2.SITUATION_MODIFIERS.swimming
        mH, mT, mF = mH * sw.hunger, mT * sw.thirst, mF * sw.fatigue
    end

    -- Combat
    if inCombat then
        local c = ICN2.SITUATION_MODIFIERS.combat
        mH, mT, mF = mH * c.hunger, mT * c.thirst, mF * c.fatigue
    end

    -- Indoors (no combat, no mount)
    if IsIndoors() and not inCombat and not IsMounted() then
        local i = ICN2.SITUATION_MODIFIERS.indoors
        mH, mT, mF = mH * i.hunger, mT * i.thirst, mF * i.fatigue
    end

    -- Race modifier
    local race = select(2, UnitRace("player"))
    local rm = ICN2.RACE_MODIFIERS[race]
    if rm then
        mH, mT, mF = mH * rm.hunger, mT * rm.thirst, mF * rm.fatigue
    end

    -- Class modifier
    local _, class = UnitClass("player")
    local cm = ICN2.CLASS_MODIFIERS[class]
    if cm then
        mH, mT, mF = mH * cm.hunger, mT * cm.thirst, mF * cm.fatigue
    end

    return mH, mT, mF
end

-- ── Armor fatigue modifier ────────────────────────────────────────────────────
local function getArmorFatigueModifier()
    -- Check the chest slot (slot 5) for armor type
    local _, _, _, _, _, _, subType = GetItemInfo(GetInventoryItemLink("player", 5) or "")
    if subType then
        if subType:find("Plate")  then return ICN2.ARMOR_FATIGUE.PLATE  end
        if subType:find("Mail")   then return ICN2.ARMOR_FATIGUE.MAIL   end
        if subType:find("Leather")then return ICN2.ARMOR_FATIGUE.LEATHER end
    end
    return ICN2.ARMOR_FATIGUE.CLOTH
end

-- ── Main decay tick ───────────────────────────────────────────────────────────
local function tick()
    local s = ICN2DB.settings
    local preset = ICN2.PRESETS[s.preset] or 1.0
    local mH, mT, mF = getSituationMultipliers()
    local armorMod   = getArmorFatigueModifier()

    local oldHunger  = ICN2DB.hunger
    local oldThirst  = ICN2DB.thirst
    local oldFatigue = ICN2DB.fatigue

    ICN2DB.hunger  = math.max(0, ICN2DB.hunger  - (s.decayRates.hunger  * preset * mH))
    ICN2DB.thirst  = math.max(0, ICN2DB.thirst  - (s.decayRates.thirst  * preset * mT))
    ICN2DB.fatigue = math.max(0, ICN2DB.fatigue - (s.decayRates.fatigue * preset * mF * armorMod))

    ICN2:UpdateHUD()
    ICN2:CheckEmotes(oldHunger, oldThirst, oldFatigue)
end

-- ── Recovery functions (called from outside / slash commands) ─────────────────
function ICN2:Eat(amount)
    amount = amount or 30
    ICN2DB.hunger = math.min(100, ICN2DB.hunger + amount)
    self:UpdateHUD()
    self:TriggerEmote("satisfied", "hunger")
end

function ICN2:Drink(amount)
    amount = amount or 30
    ICN2DB.thirst = math.min(100, ICN2DB.thirst + amount)
    self:UpdateHUD()
    self:TriggerEmote("satisfied", "thirst")
end

function ICN2:Rest(amount)
    amount = amount or 20
    ICN2DB.fatigue = math.min(100, ICN2DB.fatigue + amount)
    self:UpdateHUD()
    self:TriggerEmote("satisfied", "fatigue")
end

-- ── Event handler ─────────────────────────────────────────────────────────────
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_AURA")  -- v1.1: food/drink buff tracking

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
        ICN2:UpdateHUD()

    elseif event == "PLAYER_LOGOUT" then
        ICN2DB.lastLogout = time()

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        ICN2:OnCombatBreakFoodDrink()  -- v1.1: cancel eating/drinking on combat

    elseif event == "UNIT_AURA" then
        -- v1.1: delegate to FoodDrink module
        local unit = ...
        if unit == "player" then
            ICN2:OnUnitAura()
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Detect racial / class abilities that recover needs
        local unit, _, spellID = ...
        if unit == "player" then
            ICN2:HandleAbilityRecovery(spellID)
        end
    end
end)

-- ── Detect swimming via movement (OnUpdate heuristic) ─────────────────────────
-- IsSubmerged() is not always available; we use a safe fallback.
frame:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed >= tickInterval then
        elapsed = 0

        -- Swimming detection: check if player is submerged (water)
        -- IsSubmerged is available on retail
        if IsSubmerged and IsSubmerged() then
            isSwimming = true
        else
            isSwimming = false
        end

        ICN2:FoodDrinkTick()  -- v1.1: progressive bar fill while eating/drinking
        tick()
    end
end)

-- ── Racial / class ability recovery table ─────────────────────────────────────
local ABILITY_RECOVERY = {
    -- Undead: Cannibalize (20577) → hunger boost
    [20577] = function() ICN2:Eat(40) end,
    -- Demon Hunter: Soul Rending / Consume Soul passives (approximate)
    -- We hook a well-known DH soul fragment ability as a proxy
    [204065] = function() ICN2:Eat(10) ICN2:Rest(10) end,
    -- Night Elf: Shadowmeld (58984) → resting
    [58984]  = function() ICN2:Rest(5) end,
}

function ICN2:HandleAbilityRecovery(spellID)
    if ABILITY_RECOVERY[spellID] then
        ABILITY_RECOVERY[spellID]()
    end
end

-- ── Slash command ─────────────────────────────────────────────────────────────
SLASH_ICN21 = "/icn2"
SlashCmdList["ICN2"] = function(msg)
    msg = msg:lower():trim()
    if msg == "show" or msg == "" then
        ICN2:ToggleOptions()
    elseif msg == "eat" then
        ICN2:Eat(50)
        print("|cFFFF6600ICN2|r You eat something. Hunger restored.")
    elseif msg == "drink" then
        ICN2:Drink(50)
        print("|cFFFF6600ICN2|r You drink something. Thirst restored.")
    elseif msg == "rest" then
        ICN2:Rest(40)
        print("|cFFFF6600ICN2|r You rest. Fatigue restored.")
    elseif msg == "reset" then
        ICN2DB.hunger  = 100
        ICN2DB.thirst  = 100
        ICN2DB.fatigue = 100
        ICN2:UpdateHUD()
        print("|cFFFF6600ICN2|r Needs reset to 100%.")
    elseif msg == "status" then
        print(string.format("|cFFFF6600ICN2|r Hunger: |cFF00FF00%.1f%%|r  Thirst: |cFF4499FF%.1f%%|r  Fatigue: |cFFFFDD00%.1f%%|r",
            ICN2DB.hunger, ICN2DB.thirst, ICN2DB.fatigue))
    elseif msg == "hud" then
        ICN2DB.settings.hudEnabled = not ICN2DB.settings.hudEnabled
        ICN2:UpdateHUD()
        print("|cFFFF6600ICN2|r HUD " .. (ICN2DB.settings.hudEnabled and "|cFF00FF00enabled|r" or "|cFFFF0000disabled|r"))
    elseif msg == "lock" then
        ICN2DB.settings.hudLocked = not ICN2DB.settings.hudLocked
        ICN2:LockHUD(ICN2DB.settings.hudLocked)
        print("|cFFFF6600ICN2|r HUD " .. (ICN2DB.settings.hudLocked and "|cFFFF0000locked|r" or "|cFF00FF00unlocked|r"))
    else
        print("|cFFFF6600ICN2|r Commands: |cFFFFFF00/icn2|r [show|eat|drink|rest|reset|status|hud|lock]")
    end
end
