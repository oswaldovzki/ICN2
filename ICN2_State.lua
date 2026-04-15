-- ============================================================
-- ICN2_State.lua
-- World-sensing module. Its only job is answering: "What is the player currently doing?"
--
-- ICN2.State is the single source of truth for all condition flags. Every field is a plain fact about the player
-- No gameplay math lives here.
-- ============================================================

ICN2 = ICN2 or {}

-- ── State table ───────────────────────────────────────────────────────────────
-- All fields default to their safest / most conservative value.
-- inCombat is the only field written by an event rather than UpdateState().
ICN2.State = {
    inCombat    = false, -- set by PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED events for zero-latency response
    isSwimming  = false, -- IsSubmerged()
    isSitting   = false, -- currently not working
    isResting   = false, -- IsResting() — inn, city, garrison, etc.
    isFlying    = false, -- IsFlying()
    isMounted   = false, -- IsMounted()
    isIndoors   = false, -- IsIndoors()
    nearCampfire = false,-- player has a Cozy Fire / campfire buff
    inHousing   = false, -- player is in a housing zone/plot
    inInstance  = false, -- IsInInstance() — dungeon, raid, BG, arena (aura scanning disabled)
}

local SIT_AURA_PATTERNS = { "restful", "resting", "sitting" } -- Currently not working

-- ── UpdateState ───────────────────────────────────────────────────────────────
function ICN2:UpdateState()
    local s = ICN2.State

    -- inCombat is NOT set here. It's set immediately by PLAYER_REGEN_* events in Core for zero-latency response.
    s.isSwimming = (IsSubmerged and IsSubmerged()) and true or false
    s.isResting  = IsResting()  and true or false
    s.isFlying   = IsFlying()   and true or false
    s.isMounted  = IsMounted()  and true or false
    s.isIndoors  = IsIndoors()  and true or false

    -- ── Instance detection ────────────────────────────────────────────────────
    -- Detect dungeons, raids, battlegrounds, arenas (all have tainted auras).
    -- This prevents "secret string" errors that occur when scanning encounter buffs.
    local inInst, instType = IsInInstance()
    s.inInstance = inInst and (instType == "party" or instType == "raid" 
                              or instType == "pvp" or instType == "arena")

    -- ── Instance mode: skip aura scanning ─────────────────────────────────────
    if s.inInstance then
        s.isSitting    = false
        s.nearCampfire = false
        s.inHousing    = false
        return  -- Exit early — no aura scanning in instances
    end

    -- ── Aura-based detection ──────────────────────────────────────────────
    -- Two guards before the scan:
    --   1. s.inCombat
    --   2. UnitAffectingCombat. Covers the rare window where encounter auras
    --      arrive via UNIT_AURA before PLAYER_REGEN_DISABLED fires.
    -- inHousing is intentionally NOT cleared on combat; the zone is unchanged.
    if s.inCombat or UnitAffectingCombat("player") then
        s.isSitting    = false
        s.nearCampfire = false
        return
    end

    local sitFound      = false
    local campfireFound = false
    local i = 1
    while true do -- Iterate over buffs until we run out or find both signals. (No need to scan debuffs)
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end

        -- pcall guards against any remaining tainted aura names that slip past the combat check).
        local ok, lower = pcall(function()
            return aura.name and string.lower(aura.name) or ""
        end)
        if not ok then
            -- Name is tainted (secret string). Skip this aura safely.
            i = i + 1
        else
            if not sitFound then
                for _, p in ipairs(SIT_AURA_PATTERNS) do
                    if lower:find(p, 1, true) then sitFound = true; break end
                end
            end
            if not campfireFound then
                for _, p in ipairs(ICN2.CAMPFIRE_PATTERNS) do
                    if lower:find(p, 1, true) then campfireFound = true; break end
                end
            end
            if sitFound and campfireFound then break end
            i = i + 1
        end
    end

    s.isSitting    = sitFound
    s.nearCampfire = campfireFound

    -- Housing: campfire buff is the primary signal. Map ID is a belt-and-suspenders fallback.
    local mapID = C_Map.GetBestMapForUnit("player")
    s.inHousing = campfireFound or (mapID ~= nil and ICN2.HOUSING_MAP_IDS[mapID] == true)
end