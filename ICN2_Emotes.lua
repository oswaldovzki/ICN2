-- ============================================================
-- ICN2_Emotes.lua
-- Threshold-based automatic emotes and reaction system.
-- ============================================================

ICN2 = ICN2 or {}

local lastEmoteTime = 0

-- ── Helper: get threshold tier ───────────────────────────────────────────────
local function getTier(val)
    if val <= ICN2.THRESHOLDS.critical then return "critical"
    elseif val <= ICN2.THRESHOLDS.low   then return "low"
    else return "ok" end
end

-- ── Fire a single emote command ───────────────────────────────────────────────
local function fireEmote(emoteCmd)
    if not ICN2DB.settings.emotesEnabled then return end
    -- Strip leading slash and use DoEmote
    local token = emoteCmd:upper():sub(2)  -- "/yawn" → "YAWN"
    DoEmote(token)
end

-- ── Random pick from a table ──────────────────────────────────────────────────
local function pick(t)
    return t[math.random(1, #t)]
end

-- ── Trigger a satisfied emote externally (on eat/drink/rest) ─────────────────
function ICN2:TriggerEmote(category, subKey)
    if not ICN2DB.settings.emotesEnabled then return end
    local now = GetTime()
    if (now - lastEmoteTime) < ICN2DB.settings.emoteMinInterval then return end

    local group = ICN2.EMOTES[category]
    if not group then return end

    local list = subKey and group[subKey] or group
    if type(list) == "table" and #list > 0 then
        lastEmoteTime = now
        -- Small delay so it fires after the eat/drink animation starts
        C_Timer.After(0.5, function()
            fireEmote(pick(list))
        end)
    end
end

-- ── Check for threshold crossings and trigger emotes ─────────────────────────
-- Called every tick with old values to detect when we cross a threshold.
function ICN2:CheckEmotes(oldHunger, oldThirst, oldFatigue)
    if not ICN2DB.settings.emotesEnabled then return end

    local now = GetTime()
    if (now - lastEmoteTime) < ICN2DB.settings.emoteMinInterval then return end

    -- Random gate: only fire if we roll under emoteChance
    if math.random() > ICN2DB.settings.emoteChance then return end

    local fired = false

    -- Check hunger threshold crossings (old was ok/low, new is lower tier)
    local oldTH = getTier(oldHunger)
    local newTH = getTier(ICN2DB.hunger)
    if oldTH ~= newTH and newTH ~= "ok" then
        local list = ICN2.EMOTES.hungry[newTH]
        if list then
            fireEmote(pick(list))
            fired = true
        end
    end

    if not fired then
        local oldTT = getTier(oldThirst)
        local newTT = getTier(ICN2DB.thirst)
        if oldTT ~= newTT and newTT ~= "ok" then
            local list = ICN2.EMOTES.thirsty[newTT]
            if list then
                fireEmote(pick(list))
                fired = true
            end
        end
    end

    if not fired then
        local oldTF = getTier(oldFatigue)
        local newTF = getTier(ICN2DB.fatigue)
        if oldTF ~= newTF and newTF ~= "ok" then
            local list = ICN2.EMOTES.tired[newTF]
            if list then
                fireEmote(pick(list))
            end
        end
    end

    if fired then
        lastEmoteTime = now
    end
end
