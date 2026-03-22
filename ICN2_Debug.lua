-- ============================================================
-- ICN2_Debug.lua  (v1.5.0)
-- Standalone debug overlay. NOT included in release builds.
--
-- Usage: /icn2 debug
--
-- Opens a scrollable window showing a full JSON snapshot of
-- every modifier, state flag, rate component, and internal
-- value in the addon at the moment the command is run.
-- The snapshot is shown in a selectable edit box so it can be
-- copied without posting to chat.
--
-- Load order: last in ICN2.toc (after all other modules).
-- To enable:  add "ICN2_Debug.lua" to ICN2.toc
-- To disable: remove it — no other file depends on this one.
-- ============================================================

ICN2 = ICN2 or {}

-- ── Layout ────────────────────────────────────────────────────────────────────
-- Constants defining the debug window's appearance and layout
local DEBUG_W    = 640  -- Window width
local DEBUG_H    = 520  -- Window height
local DEBUG_FONT = "Fonts\\FRIZQT__.TTF"  -- Font file path
local DEBUG_SIZE = 11   -- Font size

-- Global reference to the debug frame (created lazily)
local debugFrame = nil

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION 1 — Snapshot builder
-- Collects every piece of observable state into a plain Lua table,
-- then serializes it to a pretty-printed JSON-like string.
-- No game-state is modified here.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Armor tier from equipped chest ───────────────────────────────────────────
-- Determines the armor type worn by the player based on chest armor subtype.
-- Returns "PLATE", "MAIL", "LEATHER", "CLOTH", or appropriate fallback.
local function getArmorTier()
    local itemLink = GetInventoryItemLink("player", 5)
    if not itemLink then return "none (no chest)" end
---@diagnostic disable-next-line: deprecated
    local _, _, _, _, _, _, subType = GetItemInfo(itemLink)
    if not subType then return "unknown (not cached)" end
    if subType:find("Plate")   then return "PLATE"   end
    if subType:find("Mail")    then return "MAIL"    end
    if subType:find("Leather") then return "LEATHER" end
    return "CLOTH"
end

-- ── Stand state string ────────────────────────────────────────────────────────
-- Maps stand state IDs to human-readable names for display
local STAND_NAMES = { [0]="standing", [1]="sitting", [2]="laying", [3]="kneeling" }
-- Returns the current stand state of the player as a string
local function getStandState()
    local v = GetUnitStandState and GetUnitStandState("player") or 0
    return STAND_NAMES[v] or ("unknown("..tostring(v)..")")
end

-- ── Resolve active situation modifiers ───────────────────────────────────────
-- Returns a table of currently active situation modifiers based on the player's state.
-- Situation modifiers are applied based on conditions like resting, mounted, flying, etc.
-- Resting is exclusive and overrides all other modifiers.
local function getActiveSituations()
    local st  = ICN2.State or {}
    local sm  = ICN2.SITUATION_MODIFIERS or {}
    local out = {}

    if st.isResting then
        out.resting = sm.resting or {}
        -- resting is exclusive — nothing else applies
        return out
    end
    if st.isMounted  then out.mounted  = sm.mounted  or {} end
    if st.isFlying   then out.flying   = sm.flying   or {} end
    if st.isSwimming then out.swimming = sm.swimming or {} end
    if st.inCombat   then out.combat   = sm.combat   or {} end
    if st.isIndoors and not st.inCombat and not st.isMounted then
        out.indoors = sm.indoors or {}
    end
    return out
end

-- ── Race + class modifiers ────────────────────────────────────────────────────
-- Retrieves the player's race and class, and looks up their corresponding modifiers
-- from the global modifier tables. Returns a table with race and class info.
local function getRaceClassModifiers()
    local race   = select(2, UnitRace("player"))
    local _, cls = UnitClass("player")
    return {
        race  = { name = race,  modifiers = ICN2.RACE_MODIFIERS[race]  or "none" },
        class = { name = cls,   modifiers = ICN2.CLASS_MODIFIERS[cls]  or "none" },
    }
end

-- ── Food / drink state ────────────────────────────────────────────────────────
-- Gathers information about the player's current eating and drinking states,
-- including active status, tiers, durations, and calculated trickle rates.
-- Also includes well-fed status and remaining time.
local function getFoodDrinkState()
    local isEating   = ICN2.IsEating   and ICN2:IsEating()   or false
    local isDrinking = ICN2.IsDrinking and ICN2:IsDrinking() or false

    -- Trickle rates per second for different food/drink tiers
    local foodTrickle, drinkTrickle = 0, 0
    local TRICKLE = { simple = 30.0, complex = 40.0, feast = 60.0 }

    if isEating then
        local dur  = (ICN2.GetFoodDuration  and ICN2:GetFoodDuration())  or 30
        local tier = (ICN2.GetFoodTier      and ICN2:GetFoodTier())      or "simple"
        foodTrickle = (TRICKLE[tier] or 30.0) / math.max(1, dur)
    end
    if isDrinking then
        local dur  = (ICN2.GetDrinkDuration and ICN2:GetDrinkDuration()) or 30
        local tier = (ICN2.GetDrinkTier     and ICN2:GetDrinkTier())     or "simple"
        drinkTrickle = (TRICKLE[tier] or 30.0) / math.max(1, dur)
    end

    -- Well-fed pause expiry and remaining time
    local wfExpiry    = ICN2._wellFedPauseExpiry or 0
    local wfRemaining = (wfExpiry > 0) and math.max(0, math.ceil(wfExpiry - GetTime())) or 0

    return {
        eating = {
            active   = isEating,
            tier     = isEating   and (ICN2.GetFoodTier   and ICN2:GetFoodTier()   or "simple") or nil,
            duration = isEating   and (ICN2.GetFoodDuration and ICN2:GetFoodDuration() or nil) or nil,
            trickle_per_sec = isEating and foodTrickle or nil,
        },
        drinking = {
            active   = isDrinking,
            tier     = isDrinking and (ICN2.GetDrinkTier  and ICN2:GetDrinkTier()  or "simple") or nil,
            duration = isDrinking and (ICN2.GetDrinkDuration and ICN2:GetDrinkDuration() or nil) or nil,
            trickle_per_sec = isDrinking and drinkTrickle or nil,
        },
        well_fed = {
            active            = wfRemaining > 0,
            remaining_seconds = wfRemaining > 0 and wfRemaining or nil,
            hunger_decay_paused = wfRemaining > 0,
        },
    }
end

-- ── Fatigue recovery state ────────────────────────────────────────────────────
-- Determines the current fatigue recovery tier and gain rate based on internal state.
-- Fatigue recovery provides bonus fatigue gain under certain conditions.
local function getFatigueRecovery()
    local tier = ICN2._fatigueRecoveryTier or "none"
    local src  = ICN2._fatigueRecoverySrc  or ""
    local fr   = ICN2.FATIGUE_RECOVERY or {}
    return {
        tier         = tier,
        sources      = src ~= "" and src or nil,
        gain_per_sec = tier == "fast" and fr.fast
                    or tier == "slow" and fr.slow
                    or 0,
        fast_threshold = "IsResting AND (nearCampfire OR inHousing)",
        slow_threshold = "any single: isResting | isSitting | nearCampfire | inHousing | eating/drinking",
    }
end

-- ── Preset and base decay ─────────────────────────────────────────────────────
-- Retrieves the current preset settings and calculates base decay rates.
-- Presets multiply the base decay rates for hunger, thirst, and fatigue.
local function getPresetInfo()
    local s      = ICN2DB and ICN2DB.settings or {}
    local preset = ICN2.PRESETS and (ICN2.PRESETS[s.preset] or 1.0) or 1.0
    local dr     = s.decayRates or {}
    return {
        name       = s.preset or "unknown",
        multiplier = preset,
        base_decay_per_sec = {
            hunger  = (dr.hunger  or 0) * preset,
            thirst  = (dr.thirst  or 0) * preset,
            fatigue = (dr.fatigue or 0) * preset,
        },
    }
end

-- ── Settings snapshot ─────────────────────────────────────────────────────────
-- Collects all user-configurable settings from the saved variables.
-- These control various aspects of the addon's behavior and UI.
local function getSettings()
    local s = ICN2DB and ICN2DB.settings or {}
    return {
        preset           = s.preset,
        hudEnabled       = s.hudEnabled,
        hudLocked        = s.hudLocked,
        hudScale         = s.hudScale,
        hudAlpha         = s.hudAlpha,
        blockyBars       = s.blockyBars,
        emotesEnabled    = s.emotesEnabled,
        emoteChance      = s.emoteChance,
        emoteMinInterval = s.emoteMinInterval,
        freezeOfflineNeeds = s.freezeOfflineNeeds,
    }
end

-- ── Build the full snapshot table ─────────────────────────────────────────────
-- Assembles all debug information into a single table structure.
-- This includes current needs, rates, state flags, modifiers, and settings.
local function buildSnapshot()
    local st    = ICN2.State or {}
    local rates = ICN2.GetCurrentRates and ICN2:GetCurrentRates()
                  or { hunger = 0, thirst = 0, fatigue = 0 }

    return {
        timestamp = date("%Y-%m-%d %H:%M:%S"),
        version   = C_AddOns and C_AddOns.GetAddOnMetadata("ICN2", "Version") or "unknown",

        needs = {
            hunger  = ICN2DB and math.floor((ICN2DB.hunger  or 0) * 10 + 0.5) / 10 or 0,
            thirst  = ICN2DB and math.floor((ICN2DB.thirst  or 0) * 10 + 0.5) / 10 or 0,
            fatigue = ICN2DB and math.floor((ICN2DB.fatigue or 0) * 10 + 0.5) / 10 or 0,
        },

        net_rates_per_sec = {
            hunger  = rates.hunger,
            thirst  = rates.thirst,
            fatigue = rates.fatigue,
        },

        state = {
            inCombat    = st.inCombat    or false,
            isSwimming  = st.isSwimming  or false,
            isSitting   = st.isSitting   or false,
            isResting   = st.isResting   or false,
            isFlying    = st.isFlying    or false,
            isMounted   = st.isMounted   or false,
            isIndoors   = st.isIndoors   or false,
            nearCampfire = st.nearCampfire or false,
            inHousing   = st.inHousing   or false,
            standState  = getStandState(),
        },

        preset_and_base_decay = getPresetInfo(),

        active_situation_modifiers = getActiveSituations(),

        race_class = getRaceClassModifiers(),

        armor = {
            tier       = getArmorTier(),
            multiplier = ICN2.ARMOR_FATIGUE and ICN2.ARMOR_FATIGUE[getArmorTier():match("^%u+")]
                         or (ICN2.ARMOR_FATIGUE and ICN2.ARMOR_FATIGUE.CLOTH or 0.9),
        },

        food_drink = getFoodDrinkState(),

        fatigue_recovery = getFatigueRecovery(),

        settings = getSettings(),
    }
end

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION 2 — Serializer
-- Converts the snapshot table to a pretty-printed JSON-like string.
-- Uses 2-space indentation. Handles booleans, numbers, strings, nil, and nested
-- tables. Functions and userdata are skipped. Arrays are detected and formatted
-- differently from objects.
-- ══════════════════════════════════════════════════════════════════════════════

-- Serializes a Lua value to a JSON-like string with proper indentation.
-- @param val: The value to serialize (table, string, number, boolean, nil)
-- @param indent: Current indentation level (number, defaults to 0)
-- @return: JSON-like string representation
local function serialize(val, indent)
    indent = indent or 0
    local pad  = string.rep("  ", indent)
    local pad2 = string.rep("  ", indent + 1)
    local t    = type(val)

    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "number" then
        -- Format floats to 6 decimal places, integers without decimals
        if val == math.floor(val) and math.abs(val) < 1e12 then
            return tostring(math.floor(val))
        else
            return string.format("%.6f", val)
        end
    elseif t == "string" then
        -- Escape quotes and backslashes
        return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
    elseif t == "table" then
        -- Detect array vs object: array = all keys are sequential integers from 1
        local isArray = true
        local n = 0
        for k, _ in pairs(val) do
            n = n + 1
            if type(k) ~= "number" or k ~= math.floor(k) then
                isArray = false; break
            end
        end
        if isArray and n > 0 then
            -- Sort array keys
            local arr = {}
            for i = 1, n do arr[i] = serialize(val[i], indent + 1) end
            if n <= 3 then
                -- Short arrays on one line
                return "[ " .. table.concat(arr, ", ") .. " ]"
            else
                return "[\n" .. pad2 .. table.concat(arr, ",\n" .. pad2) .. "\n" .. pad .. "]"
            end
        else
            -- Object
            local keys = {}
            for k, _ in pairs(val) do
                if type(k) == "string" then keys[#keys + 1] = k end
            end
            table.sort(keys)
            if #keys == 0 then return "{}" end
            local lines = {}
            for _, k in ipairs(keys) do
                local v = val[k]
                if type(v) ~= "function" then
                    lines[#lines + 1] = pad2 .. '"' .. k .. '": ' .. serialize(v, indent + 1)
                end
            end
            return "{\n" .. table.concat(lines, ",\n") .. "\n" .. pad .. "}"
        end
    else
        return '"[' .. t .. ']"'  -- function, userdata, thread
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION 3 — UI
-- Creates and manages the debug window UI components including the frame,
-- scrollable text area, and control buttons.
-- ══════════════════════════════════════════════════════════════════════════════

-- Creates the debug window frame with all UI elements.
-- Returns the frame object with attached methods for updating content.
local function buildDebugFrame()
    local f = CreateFrame("Frame", "ICN2DebugFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(DEBUG_W, DEBUG_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetClampedToScreen(true)
    f:Hide()

    f.TitleText:SetText("|cFFFF6600ICN2|r Debug Snapshot  |cFF888888v1.4.0|r")

    -- ── Scroll frame ──────────────────────────────────────────────────────────
    local scroll = CreateFrame("ScrollFrame", "ICN2DebugScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",    f, "TOPLEFT",    10, -32)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 10)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(DEBUG_W - 50, 1)  -- height set dynamically below
    scroll:SetScrollChild(content)

    local text = CreateFrame("EditBox", nil, content)
    text:SetFont(DEBUG_FONT, DEBUG_SIZE, "")
    text:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    text:SetWidth(DEBUG_W - 58)
    text:SetMultiLine(true)
    text:SetAutoFocus(false)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Calculates the height needed for the text content
    local function getTextHeight(json)
        local ok, h = pcall(text.GetStringHeight, text)
        if ok and type(h) == "number" and h > 0 then
            return h
        end
        local _, fontSize = text:GetFont()
        local lineHeight = (fontSize or DEBUG_SIZE) + 2
        local _, lines = json:gsub("\n", "")
        return (lines + 1) * lineHeight
    end

    -- Sets the JSON text in the edit box and adjusts container heights
    local function setDebugText(json)
        text:SetText(json)
        local height = math.max(DEBUG_H - 50, getTextHeight(json) + 10)
        text:SetHeight(height)
        content:SetHeight(height)
        scroll:SetVerticalScroll(0)
    end

    -- ── Refresh button ────────────────────────────────────────────────────────
    local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -4)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        local snapshot = buildSnapshot()
        local json     = serialize(snapshot)
        setDebugText(json)
    end)

    -- ── Select-all button (for easy copy) ─────────────────────────────────────
    local selectBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    selectBtn:SetSize(90, 22)
    selectBtn:SetPoint("TOPRIGHT", refreshBtn, "TOPLEFT", -4, 0)
    selectBtn:SetText("Select All")
    selectBtn:SetScript("OnClick", function()
        text:SetFocus()
        text:HighlightText()
    end)

    f._text    = text
    f._content = content
    f._scroll  = scroll
    f._setJson = setDebugText
    return f
end

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION 4 — Public entry point
-- ══════════════════════════════════════════════════════════════════════════════

-- Toggles the debug window visibility. Creates the frame if it doesn't exist,
-- then shows or hides it. Always refreshes the content when opening.
function ICN2:OpenDebug()
    if not debugFrame then
        debugFrame = buildDebugFrame()
    end

    -- Always refresh on open
    local snapshot = buildSnapshot()
    local json     = serialize(snapshot)
    debugFrame._setJson(json)

    if debugFrame:IsShown() then
        debugFrame:Hide()
    else
        debugFrame:Show()
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION 5 — Hook into /icn2 debug
-- Extends the existing slash handler by overriding it after Core registers it.
-- Uses a wrapper so Core's original handler still fires for all other commands.
-- ══════════════════════════════════════════════════════════════════════════════

-- Wait for ADDON_LOADED to ensure Core's SlashCmdList entry exists first.
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("ADDON_LOADED")
hookFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= "ICN2" then return end
    self:UnregisterEvent("ADDON_LOADED")

    local originalHandler = SlashCmdList["ICN2"]
    SlashCmdList["ICN2"] = function(msg)
        if msg:lower():trim() == "debug" then
            ICN2:OpenDebug()
        else
            originalHandler(msg)
        end
    end
end)
