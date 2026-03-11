-- ============================================================
-- ICN2_HUD.lua
-- On-screen status bars: hunger, thirst, fatigue.
-- Draggable, scalable. Supports smooth bar OR blocky 10-block mode.
--
-- Frame hierarchy:
-- ICN2HUDFrame
--  ├─ Background
--  ├─ Bordered border
--  ├─ Row (hunger)
--  │   ├─ Icon
--  │   ├─ BarFrame
--  │   │   ├─ SmoothBar (StatusBar)
--  │   │   ├─ SmoothBG (Texture)
--  │   │   ├─ BlockFrames[1..10]
--  │   │   │   ├─ Geo (border, bevels, innerBG)
--  │   │   │   └─ Fill (Texture)
--  │   └─ Indicator (FontString)
--  ├─ Row (thirst) — same structure as hunger
--  └─ Row (fatigue) — same structure as hunger
-- ============================================================

ICN2 = ICN2 or {}

local hudFrame
local bars = {}

-- ── Layout constants ──────────────────────────────────────────────────────────
local BLOCK_SIZE  = 24
local BAR_GAP     = 6
local ICON_SIZE   = 24
local NUM_BLOCKS  = 10
local BLOCK_GAP   = 2
local INDICATOR_W = 18

local NEED_KEYS = { "hunger", "thirst", "fatigue" }

-- ── Icons ─────────────────────────────────────────────────────────────────────
local ICONS = {
    hunger  = "Interface\\Icons\\inv_misc_food_cooked_greatpabanquet_general",
    thirst  = "Interface\\Icons\\inv_drink_18_color03",
    fatigue = "Interface\\Icons\\ui_campcollection",
}

-- ── Bar fill colors ───────────────────────────────────────────────────────────
-- Atlas textures removed — blocks use a pure 3D geometry look.
local BLOCK_COLORS = {
    hunger  = { 0.2, 0.9,  0.2 },
    thirst  = { 0.2, 0.5,  1.0 },
    fatigue = { 1.0, 0.85, 0.1 },
}

-- ── Indicator thresholds (% per second) ──────────────────────────────────────
local IND_FASTER_UP     =  1.00
local IND_FAST_UP       =  0.30
local IND_UP            =  0.00
local IND_DOWN          =  0.00
local IND_FAST_DOWN     = -0.30
local IND_FASTER_DOWN   = -1.00

-- ── Indicator pulse animation ─────────────────────────────────────────────────
-- Indicators pulse when the net rate is changing in a direction that would cross a threshold
-- The neutral glyph (##) stays dim and static — no pulse.
local PULSE_PERIOD = 2.00 -- seconds for a full pulse cycle (min → max → min)
local PULSE_MIN    = 0.25 -- minimum alpha for pulse (at trough)
local PULSE_MAX    = 1.00 -- maximum alpha for pulse (at peak)

local function shouldPulse(glyph)
    return glyph == "<" or glyph == "<<" or glyph == ">" or glyph == ">>"
end

-- ── Color helper ──────────────────────────────────────────────────────────────
local function getNeedColor(key, val)
    if val <= ICN2.THRESHOLDS.critical then return 0.9, 0.1, 0.1
    elseif val <= ICN2.THRESHOLDS.low  then return 0.9, 0.6, 0.1
    else
        local fc = BLOCK_COLORS[key]
        return fc[1], fc[2], fc[3]
    end
end

-- ── Indicator glyph + color from net rate ─────────────────────────────────────
local function getIndicator(rate)
    if rate >= IND_FASTER_UP then
        return ">>>", 0.0, 1.0, 0.0 -- pure green for very fast positive rates
    elseif rate >= IND_FAST_UP then
        return ">>", 0.2, 0.9, 0.1 -- bright green for moderate positive rates
    elseif rate >= IND_UP then
        return ">",  0.7, 0.9, 0.4 -- light green for slow positive rates
    elseif rate < IND_DOWN then
        return "<",  0.9, 0.7, 0.1 -- orange for slow negative rates
    elseif rate < IND_FAST_DOWN then
        return "<<", 0.9, 0.2, 0.1 -- red-orange for moderate negative rates
    elseif rate < IND_FASTER_DOWN then
        return "<<<", 1.0, 0.0, 0.0 -- pure red for very fast negative rates
    else
        return "##", 1.0, 1.0, 1.0 -- white as fallback (should never happen)
    end
end

-- ── Build the HUD ─────────────────────────────────────────────────────────────
function ICN2:BuildHUD()
    local s = ICN2DB.settings

    local barW   = (BLOCK_SIZE + BLOCK_GAP) * NUM_BLOCKS
    local frameW = ICON_SIZE + 4 + barW + INDICATOR_W + 14
    local frameH = (BLOCK_SIZE + BAR_GAP) * #NEED_KEYS + 14

    hudFrame = CreateFrame("Frame", "ICN2HUDFrame", UIParent)
    hudFrame:SetSize(frameW, frameH)
    hudFrame:SetFrameStrata("MEDIUM")
    hudFrame:SetClampedToScreen(true)
    hudFrame:SetPoint("CENTER", UIParent, "CENTER", s.hudX or 200, s.hudY or -250)

    local bg = hudFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    bg:SetVertexColor(0, 0, 0, 0.6)

    local border = CreateFrame("Frame", nil, hudFrame, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    hudFrame:EnableMouse(true)
    hudFrame:SetMovable(true)
    hudFrame:RegisterForDrag("LeftButton")
    hudFrame:SetScript("OnDragStart", function(self)
        if not ICN2DB.settings.hudLocked then self:StartMoving() end
    end)
    hudFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        ICN2DB.settings.hudX = x
        ICN2DB.settings.hudY = y
    end)

    hudFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("|cFFFF6600ICN2 - Character Needs|r", 1, 1, 1)
        GameTooltip:AddLine(string.format("Hunger:  %.1f%%", ICN2DB.hunger),  0.2, 0.8, 0.2)
        GameTooltip:AddLine(string.format("Thirst:  %.1f%%", ICN2DB.thirst),  0.2, 0.5, 1.0)
        GameTooltip:AddLine(string.format("Fatigue: %.1f%%", ICN2DB.fatigue), 1.0, 0.85, 0.1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFAAAAAA/icn2 details — show active modifiers|r", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    hudFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Build rows ────────────────────────────────────────────────────────────
    for i, key in ipairs(NEED_KEYS) do
        local fc = BLOCK_COLORS[key]

        local rowFrame = CreateFrame("Frame", "ICN2Row_" .. key, hudFrame)
        rowFrame:SetSize(frameW - 8, BLOCK_SIZE)
        rowFrame:SetPoint("TOPLEFT", hudFrame, "TOPLEFT",
            4, -((i - 1) * (BLOCK_SIZE + BAR_GAP)) - 7)

        local icon = rowFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)
        icon:SetTexture(ICONS[key])
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local barFrame = CreateFrame("Frame", "ICN2BarFrame_" .. key, rowFrame)
        barFrame:SetSize(barW, BLOCK_SIZE)
        barFrame:SetPoint("LEFT", rowFrame, "LEFT", ICON_SIZE + 4, 0)

        -- Smooth bar
        local smoothBG = barFrame:CreateTexture(nil, "BACKGROUND")
        smoothBG:SetAllPoints()
        smoothBG:SetColorTexture(0.12, 0.12, 0.12, 0.9)

        local smoothBar = CreateFrame("StatusBar", "ICN2SmoothBar_" .. key, barFrame)
        smoothBar:SetAllPoints()
        smoothBar:SetMinMaxValues(0, 100)
        smoothBar:SetValue(100)
        smoothBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        smoothBar:SetStatusBarColor(fc[1], fc[2], fc[3])

        local smoothLabel = smoothBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        smoothLabel:SetPoint("RIGHT", smoothBar, "RIGHT", -3, 0)
        smoothLabel:SetText("100%")

        -- ── Blocky blocks — 3D bevelled, no atlas textures ────────────────────
        -- ALL geometry textures start hidden. ApplyBarMode is the sole
        -- authority for showing/hiding them, which prevents the block shells
        -- from bleeding through behind the smooth bar when blocky mode is off.
        local BEVEL = 1
        local INSET = 2

        local blockFrames = {}
        for b = 1, NUM_BLOCKS do
            local bx = (b - 1) * (BLOCK_SIZE + BLOCK_GAP)

            local borderTex = barFrame:CreateTexture(nil, "BACKGROUND")
            borderTex:SetSize(BLOCK_SIZE, BLOCK_SIZE)
            borderTex:SetPoint("TOPLEFT", barFrame, "TOPLEFT", bx, 0)
            borderTex:SetColorTexture(0.05, 0.05, 0.05, 1.0)
            borderTex:Hide()

            local bevelTop = barFrame:CreateTexture(nil, "BORDER")
            bevelTop:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + BEVEL,              -BEVEL)
            bevelTop:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BLOCK_SIZE - BEVEL, -(BEVEL + 1))
            bevelTop:SetColorTexture(0.55, 0.55, 0.55, 0.9)
            bevelTop:Hide()

            local bevelLeft = barFrame:CreateTexture(nil, "BORDER")
            bevelLeft:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + BEVEL,     -BEVEL)
            bevelLeft:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BEVEL + 1, -(BLOCK_SIZE - BEVEL))
            bevelLeft:SetColorTexture(0.55, 0.55, 0.55, 0.9)
            bevelLeft:Hide()

            local bevelBottom = barFrame:CreateTexture(nil, "BORDER")
            bevelBottom:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + BEVEL,              -(BLOCK_SIZE - BEVEL - 1))
            bevelBottom:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BLOCK_SIZE - BEVEL, -(BLOCK_SIZE - BEVEL))
            bevelBottom:SetColorTexture(0.0, 0.0, 0.0, 0.9)
            bevelBottom:Hide()

            local bevelRight = barFrame:CreateTexture(nil, "BORDER")
            bevelRight:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + BLOCK_SIZE - BEVEL - 1, -BEVEL)
            bevelRight:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BLOCK_SIZE - BEVEL,     -(BLOCK_SIZE - BEVEL))
            bevelRight:SetColorTexture(0.0, 0.0, 0.0, 0.9)
            bevelRight:Hide()

            local innerBG = barFrame:CreateTexture(nil, "ARTWORK")
            innerBG:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + INSET,              -INSET)
            innerBG:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BLOCK_SIZE - INSET, -(BLOCK_SIZE - INSET))
            innerBG:SetColorTexture(0.10, 0.10, 0.10, 1.0)
            innerBG:Hide()

            local fillTex = barFrame:CreateTexture(nil, "OVERLAY")
            fillTex:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + INSET,              -INSET)
            fillTex:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BLOCK_SIZE - INSET, -(BLOCK_SIZE - INSET))
            fillTex:SetColorTexture(fc[1], fc[2], fc[3], 0.90)
            fillTex:Hide()

            blockFrames[b] = {
                fill = fillTex, -- the colored fill that gets shown/hidden based on value
                geo  = { borderTex, bevelTop, bevelLeft, bevelBottom, bevelRight, innerBG }, -- the geometry textures that are shown/hidden as a group based on bar mode
            }
        end

        -- ── Indicator + pulse driver ──────────────────────────────────────────
        local indicator = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        indicator:SetPoint("RIGHT", rowFrame, "RIGHT", -2, 0)
        indicator:SetText("##")
        indicator:SetTextColor(0.3, 0.3, 0.3)
        indicator:SetAlpha(1.0)

        local pulseFrame   = CreateFrame("Frame", nil, rowFrame)
        local pulseElapsed = 0
        local pulseRunning = false

        pulseFrame:SetScript("OnUpdate", function(_, dt)
            if not pulseRunning then return end
            pulseElapsed = pulseElapsed + dt
            local t = (pulseElapsed % PULSE_PERIOD) / PULSE_PERIOD
            local a = PULSE_MIN + (PULSE_MAX - PULSE_MIN)
                      * (0.5 + 0.5 * math.sin(t * math.pi * 2 - math.pi / 2))
            indicator:SetAlpha(a)
        end)

        bars[key] = {
            rowFrame    = rowFrame,
            barFrame    = barFrame,
            smoothBar   = smoothBar,
            smoothBG    = smoothBG,
            smoothLabel = smoothLabel,
            blocks      = blockFrames,
            indicator   = indicator,
            setPulse    = function(active)
                pulseRunning = active
                if not active then
                    pulseElapsed = 0
                    indicator:SetAlpha(1.0)
                end
            end,
        }
    end

    -- ── Command buttons ───────────────────────────────────────────────────────
    local cmdButton1 = CreateFrame("Button", "ICN2CmdButton1", hudFrame, "UIPanelButtonTemplate")
    cmdButton1:SetSize(24, 24)
    cmdButton1:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", 0, 24)
    local configTex = cmdButton1:CreateTexture(nil, "ARTWORK")
    configTex:SetAllPoints()
    configTex:SetAtlas("poi-workorders")
    cmdButton1:SetScript("OnClick", function() ICN2:ToggleOptions() end)

    local cmdButton2 = CreateFrame("Button", "ICN2CmdButton2", hudFrame, "UIPanelButtonTemplate")
    cmdButton2:SetSize(24, 24)
    cmdButton2:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -24, 24)
    local infoTex = cmdButton2:CreateTexture(nil, "ARTWORK")
    infoTex:SetAllPoints()
    infoTex:SetAtlas("loreobject-32x32")
    cmdButton2:SetScript("OnClick", function() ICN2:PrintDetails() end)

    hudFrame:SetAlpha(s.hudAlpha)
    hudFrame:SetScale(s.hudScale)
    ICN2:ApplyBarMode()
    if not s.hudEnabled then hudFrame:Hide() end
end

-- ── ApplyBarMode ──────────────────────────────────────────────────────────────
-- Sole authority for showing/hiding block geometry.
-- Smooth mode → all block geo hidden, smooth bar shown.
-- Blocky mode → smooth bar hidden, block geo shown (fill toggled in UpdateHUD).
function ICN2:ApplyBarMode()
    if not hudFrame then return end
    local blocky = ICN2DB.settings.blockyBars

    for _, key in ipairs(NEED_KEYS) do
        local data = bars[key]
        if data then
            if blocky then
                data.smoothBar:Hide()
                data.smoothBG:Hide()
                data.smoothLabel:Hide()
                for _, bf in ipairs(data.blocks) do
                    for _, tex in ipairs(bf.geo) do tex:Show() end
                end
            else
                data.smoothBar:Show()
                data.smoothBG:Show()
                data.smoothLabel:Show()
                for _, bf in ipairs(data.blocks) do
                    bf.fill:Hide()
                    for _, tex in ipairs(bf.geo) do tex:Hide() end
                end
            end
        end
    end
end

-- ── UpdateHUD ─────────────────────────────────────────────────────────────────
function ICN2:UpdateHUD()
    if not hudFrame then return end
    if not ICN2DB.settings.hudEnabled then hudFrame:Hide(); return end
    hudFrame:Show()

    local values = { hunger = ICN2DB.hunger, thirst = ICN2DB.thirst, fatigue = ICN2DB.fatigue }
    local rates  = ICN2:GetCurrentRates()
    local blocky = ICN2DB.settings.blockyBars

    for _, key in ipairs(NEED_KEYS) do
        local data = bars[key]
        if data then
            local val     = values[key] or 0
            local r, g, b = getNeedColor(key, val)

            if blocky then
                local filled = (val >= 100) and NUM_BLOCKS or math.floor(val / 10)
                for b = 1, NUM_BLOCKS do
                    local bf = data.blocks[b]
                    if b <= filled then
                        bf.fill:SetColorTexture(r, g, b, 0.90)
                        bf.fill:Show()
                    else
                        bf.fill:Hide()
                    end
                end
            else
                data.smoothBar:SetValue(val)
                data.smoothBar:SetStatusBarColor(r, g, b)
                data.smoothLabel:SetText(string.format("%.0f%%", val))
            end

            local glyph, ir, ig, ib = getIndicator(rates[key] or 0)
            data.indicator:SetText(glyph)
            data.indicator:SetTextColor(ir, ig, ib)
            data.setPulse(shouldPulse(glyph))
        end
    end
end

-- ── SetBlockyBars ─────────────────────────────────────────────────────────────
function ICN2:SetBlockyBars(enabled)
    ICN2DB.settings.blockyBars = enabled
    ICN2:ApplyBarMode()
    ICN2:UpdateHUD()
end

-- ── LockHUD ───────────────────────────────────────────────────────────────────
function ICN2:LockHUD(locked)
    if hudFrame then hudFrame:EnableMouse(not locked) end
end
