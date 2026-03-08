-- ============================================================
-- ICN2_HUD.lua  (v1.2.0-beta)
-- On-screen status bars: hunger, thirst, fatigue.
-- Draggable, scalable. Supports smooth bar OR blocky 10-block mode.
--
-- Frame hierarchy:
--   hudFrame
--    ├─ ICN2Row_hunger   (rowFrame)
--    │   ├─ icon
--    │   ├─ ICN2BarFrame_hunger  (barFrame)
--    │   │   ├─ smoothBG / smoothBar / smoothLabel
--    │   │   └─ block[1..10]: fillTex (BG) + emptyTex (ARTWORK)
--    │   └─ indicator FontString  ← NEW: ⇈ ↑ • ↓ ⇊
--    ├─ ICN2Row_thirst
--    └─ ICN2Row_fatigue
-- ============================================================

ICN2 = ICN2 or {}

local hudFrame
local bars = {}

-- ── Layout constants ──────────────────────────────────────────────────────────
local BLOCK_SIZE    = 24
local BAR_GAP       = 6
local ICON_SIZE     = 24
local NUM_BLOCKS    = 10
local BLOCK_GAP     = 2
local INDICATOR_W   = 16   -- width reserved for the indicator glyph

local NEED_KEYS = { "hunger", "thirst", "fatigue" }

-- ── Icons ─────────────────────────────────────────────────────────────────────
local ICONS = {
    hunger  = "Interface\\Icons\\INV_Misc_Food_15",
    thirst  = "Interface\\Icons\\INV_Drink_07",
    fatigue = "Interface\\Icons\\Spell_Nature_Sleep",
}

-- ── Atlas config — swap textures here ─────────────────────────────────────────
local BLOCK_ATLAS = {
    hunger  = { emptyAtlas = "Relic-Blood-TraitBG", fillColor = { 0.2, 0.9, 0.2 } },
    thirst  = { emptyAtlas = "Relic-Water-TraitBG", fillColor = { 0.2, 0.5, 1.0 } },
    fatigue = { emptyAtlas = "Relic-Wind-TraitBG",  fillColor = { 1.0, 0.85, 0.1 } },
}

-- ── Indicator thresholds (% per second) ──────────────────────────────────────
-- These define when to switch between indicator glyphs.
local IND_FAST_UP       =  0.50   -- >>  fast recovery
local IND_UP            =  0.05   -- >  slow recovery
local IND_STABLE_UP     =  0.00   -- >=  stable to slow recovery
local IND_STABLE_DOWN   =  0.00   -- =<  stable to slow decay
local IND_DOWN          = -0.05   -- <  slow decay
local IND_FAST_DOWN     = -0.50   -- <<  fast decay

-- ── Color helper ──────────────────────────────────────────────────────────────
local function getNeedColor(key, val)
    if val <= ICN2.THRESHOLDS.critical then return 0.9, 0.1, 0.1
    elseif val <= ICN2.THRESHOLDS.low  then return 0.9, 0.6, 0.1
    else
        local fc = BLOCK_ATLAS[key].fillColor
        return fc[1], fc[2], fc[3]
    end
end

-- ── Indicator glyph + color from net rate ────────────────────────────────────
local function getIndicator(rate)
    if rate >= IND_FAST_UP then
        return ">>", 0.1, 0.9, 0.1      -- >> bright green
    elseif rate >= IND_UP then
        return ">", 0.4, 0.9, 0.4       -- > green
    elseif rate > IND_STABLE_UP then
        return ">=", 0.55, 0.55, 0.55    -- >= gray
    elseif rate < IND_STABLE_DOWN then
        return "=<", 0.55, 0.55, 0.55    -- =< gray
    elseif rate < IND_DOWN then
    return "<", 0.9, 0.6, 0.1           -- < orange
    elseif rate < IND_FAST_DOWN then
        return "<<", 0.9, 0.1, 0.1      -- << red
    else
        return "##", 0, 0, 0            -- ## black fallback
    end
end

-- ── Build the HUD ─────────────────────────────────────────────────────────────
function ICN2:BuildHUD()
    local s = ICN2DB.settings

    local barW   = (BLOCK_SIZE + BLOCK_GAP) * NUM_BLOCKS
    local frameW = ICON_SIZE + 4 + barW + INDICATOR_W + 14
    local frameH = (BLOCK_SIZE + BAR_GAP) * #NEED_KEYS + 14

    -- Root container
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

    -- Build rows
    for i, key in ipairs(NEED_KEYS) do
        local atlas = BLOCK_ATLAS[key]
        local fc    = atlas.fillColor

        -- Row container
        local rowFrame = CreateFrame("Frame", "ICN2Row_" .. key, hudFrame)
        rowFrame:SetSize(frameW - 8, BLOCK_SIZE)
        rowFrame:SetPoint("TOPLEFT", hudFrame, "TOPLEFT",
            4, -((i - 1) * (BLOCK_SIZE + BAR_GAP)) - 7)

        -- Icon
        local icon = rowFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)
        icon:SetTexture(ICONS[key])
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- barFrame
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

        -- Blocky blocks
        local blockFrames = {}
        for b = 1, NUM_BLOCKS do
            local bx = (b - 1) * (BLOCK_SIZE + BLOCK_GAP)

            local fillTex = barFrame:CreateTexture(nil, "BACKGROUND")
            fillTex:SetSize(BLOCK_SIZE, BLOCK_SIZE)
            fillTex:SetPoint("TOPLEFT", barFrame, "TOPLEFT", bx, 0)
            fillTex:SetColorTexture(fc[1], fc[2], fc[3], 0.85)
            fillTex:Hide()

            local emptyTex = barFrame:CreateTexture(nil, "ARTWORK")
            emptyTex:SetSize(BLOCK_SIZE, BLOCK_SIZE)
            emptyTex:SetPoint("TOPLEFT", barFrame, "TOPLEFT", bx, 0)
            emptyTex:SetAtlas(atlas.emptyAtlas)
            emptyTex:Hide()

            blockFrames[b] = { fill = fillTex, empty = emptyTex }
        end

        -- ── Indicator (right of barFrame, inside rowFrame) ────────────────────
        -- Anchored to the RIGHT of rowFrame so it never overlaps the bar.
        local indicator = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        indicator:SetPoint("RIGHT", rowFrame, "RIGHT", -2, 0)
        indicator:SetText("•")           -- starts as • (stable)
        indicator:SetTextColor(0.55, 0.55, 0.55)

        bars[key] = {
            rowFrame    = rowFrame,
            barFrame    = barFrame,
            smoothBar   = smoothBar,
            smoothBG    = smoothBG,
            smoothLabel = smoothLabel,
            blocks      = blockFrames,
            indicator   = indicator,
        }
    end

    -- Add command buttons for testing
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
                for _, bf in ipairs(data.blocks) do bf.empty:Show() end
            else
                data.smoothBar:Show()
                data.smoothBG:Show()
                data.smoothLabel:Show()
                for _, bf in ipairs(data.blocks) do
                    bf.fill:Hide()
                    bf.empty:Hide()
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
    -- Calculate current rates in real-time for accurate indicators
    local rates  = ICN2:GetCurrentRates()
    local blocky = ICN2DB.settings.blockyBars

    for _, key in ipairs(NEED_KEYS) do
        local data = bars[key]
        if data then
            local val     = values[key] or 0
            local r, g, b = getNeedColor(key, val)

            -- Bar / blocks
            if blocky then
                local filled = (val >= 100) and 10 or math.floor(val / 10)
                for b = 1, NUM_BLOCKS do
                    local bf = data.blocks[b]
                    if b <= filled then
                        bf.fill:SetColorTexture(r, g, b, 0.85)
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

            -- ── Indicator ─────────────────────────────────────────────────────
            local glyph, ir, ig, ib = getIndicator(rates[key] or 0)
            data.indicator:SetText(glyph)
            data.indicator:SetTextColor(ir, ig, ib)
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
