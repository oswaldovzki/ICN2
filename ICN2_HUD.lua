-- ============================================================
-- ICN2_HUD.lua  (v1.1.3)
-- On-screen status bars: hunger, thirst, fatigue.
-- Draggable, scalable. Supports smooth bar OR blocky 10-block mode.
--
-- Frame hierarchy (v1.1.3):
--   hudFrame
--    ├─ hungerRow  (rowFrame)
--    │   ├─ icon
--    │   ├─ smoothBG / smoothBar / smoothLabel
--    │   └─ blockFrames[1..10] + blockLabel
--    ├─ thirstRow
--    └─ fatigueRow
--
-- Each row is a self-contained Frame child of hudFrame.
-- This makes it easy to animate entire rows later (shake, pulse, etc.)
-- without touching individual blocks or the parent.
-- ============================================================

ICN2 = ICN2 or {}

local hudFrame
-- bars[key] = { rowFrame, smoothBar, smoothBG, smoothLabel, blocks, blockLabel }
local bars = {}

local BAR_WIDTH   = 160
local BAR_HEIGHT  = 16
local BAR_GAP     = 6
local ICON_SIZE   = 18
local NUM_BLOCKS  = 10
local BLOCK_GAP   = 2
local BLOCK_WIDTH = math.floor((BAR_WIDTH - (NUM_BLOCKS - 1) * BLOCK_GAP) / NUM_BLOCKS)

local ICONS = {
    hunger  = "Interface\\Icons\\INV_Misc_Food_15",
    thirst  = "Interface\\Icons\\INV_Drink_07",
    fatigue = "Interface\\Icons\\Spell_Nature_Sleep",
}

local NEED_KEYS = { "hunger", "thirst", "fatigue" }

-- ── Color helper ──────────────────────────────────────────────────────────────
local function getNeedColor(key, val)
    if val <= ICN2.THRESHOLDS.critical then
        return 0.9, 0.1, 0.1
    elseif val <= ICN2.THRESHOLDS.low then
        return 0.9, 0.6, 0.1
    else
        local c = ICN2DB.settings["color" .. (key:sub(1,1):upper() .. key:sub(2))]
        return c[1], c[2], c[3]
    end
end

-- ── Build the entire HUD ──────────────────────────────────────────────────────
function ICN2:BuildHUD()
    local s = ICN2DB.settings

    -- ── Root container ────────────────────────────────────────────────────────
    hudFrame = CreateFrame("Frame", "ICN2HUDFrame", UIParent)
    hudFrame:SetWidth(ICON_SIZE + BAR_WIDTH + 14)
    hudFrame:SetHeight((BAR_HEIGHT + BAR_GAP) * 3 + 14)
    hudFrame:SetFrameStrata("MEDIUM")
    hudFrame:SetClampedToScreen(true)
    hudFrame:SetPoint("CENTER", UIParent, "CENTER", s.hudX or 200, s.hudY or -250)

    -- Background (using WoW tooltip texture for consistent UI look)
    local bg = hudFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    bg:SetVertexColor(0, 0, 0, 0.6)

    -- Border
    local border = CreateFrame("Frame", nil, hudFrame, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    -- Drag
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

    -- Tooltip
    hudFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("|cFFFF6600ICN2 - Character Needs|r", 1, 1, 1)
        GameTooltip:AddLine(string.format("Hunger:  %.1f%%", ICN2DB.hunger),  0.2, 0.8, 0.2)
        GameTooltip:AddLine(string.format("Thirst:  %.1f%%", ICN2DB.thirst),  0.2, 0.5, 1.0)
        GameTooltip:AddLine(string.format("Fatigue: %.1f%%", ICN2DB.fatigue), 1.0, 0.85, 0.1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFAAAAAA/icn2 eat|drink|rest|reset|status|r", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    hudFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Build one row per need ────────────────────────────────────────────────
    for i, key in ipairs(NEED_KEYS) do
        local c   = s["color" .. (key:sub(1,1):upper() .. key:sub(2))]
        local cr, cg, cb = c[1], c[2], c[3]

        -- ── Row container ─────────────────────────────────────────────────────
        -- Anchored to hudFrame. Width = full bar area including icon.
        -- This is the frame you'd target for row-level animations later.
        local rowFrame = CreateFrame("Frame", "ICN2Row_" .. key, hudFrame)
        rowFrame:SetSize(ICON_SIZE + BAR_WIDTH + 9, BAR_HEIGHT)
        rowFrame:SetPoint(
            "TOPLEFT", hudFrame, "TOPLEFT",
            4,
            -((i - 1) * (BAR_HEIGHT + BAR_GAP)) - 7
        )

        -- ── Icon (child of rowFrame) ──────────────────────────────────────────
        local icon = rowFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)
        icon:SetTexture(ICONS[key])
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- ── barFrame: sub-container for all bar elements ──────────────────────
        -- Positioned to the right of the icon within the row.
        -- Blocks and smooth bar are both parented here.
        local barFrame = CreateFrame("Frame", "ICN2BarFrame_" .. key, rowFrame)
        barFrame:SetSize(BAR_WIDTH, BAR_HEIGHT)
        barFrame:SetPoint("LEFT", rowFrame, "LEFT", ICON_SIZE + 4, 0)

        -- ── Smooth bar ────────────────────────────────────────────────────────
        local smoothBG = barFrame:CreateTexture(nil, "BACKGROUND")
        smoothBG:SetAllPoints()
        smoothBG:SetColorTexture(0.12, 0.12, 0.12, 0.9)

        local smoothBar = CreateFrame("StatusBar", "ICN2SmoothBar_" .. key, barFrame)
        smoothBar:SetAllPoints()
        smoothBar:SetMinMaxValues(0, 100)
        smoothBar:SetValue(100)
        smoothBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        smoothBar:SetStatusBarColor(cr, cg, cb)

        local smoothLabel = smoothBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        smoothLabel:SetPoint("RIGHT", smoothBar, "RIGHT", -3, 0)
        smoothLabel:SetText("100%")

        -- ── Blocky bar (10 discrete blocks, all children of barFrame) ─────────
        -- Block positions are relative to barFrame, making layout trivial.
        local blockFrames = {}
        for b = 1, NUM_BLOCKS do
            local bx = (b - 1) * (BLOCK_WIDTH + BLOCK_GAP)

            -- Empty slot background (always visible in blocky mode)
            local emptyTex = barFrame:CreateTexture(nil, "ARTWORK")
            emptyTex:SetSize(BLOCK_WIDTH, BAR_HEIGHT)
            emptyTex:SetPoint("TOPLEFT", barFrame, "TOPLEFT", bx, 0)
            emptyTex:SetColorTexture(0.12, 0.12, 0.12, 0.9)
            emptyTex:Hide()

            -- Filled block — color set at update time via SetColorTexture
            -- (using SetColorTexture keeps it simple and avoids texture scoping issues)
            local fillTex = barFrame:CreateTexture(nil, "OVERLAY")
            fillTex:SetSize(BLOCK_WIDTH, BAR_HEIGHT)
            fillTex:SetPoint("TOPLEFT", barFrame, "TOPLEFT", bx, 0)
            fillTex:SetColorTexture(cr, cg, cb, 1.0)  -- initial color from build-time 'c'
            fillTex:Hide()

            blockFrames[b] = { fill = fillTex, empty = emptyTex }
        end

        -- Block count label "7/10", anchored inside barFrame
        local blockLabel = barFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        blockLabel:SetPoint("RIGHT", barFrame, "RIGHT", -2, 0)
        blockLabel:SetText("10/10")
        blockLabel:Hide()

        -- Store everything keyed by need name
        bars[key] = {
            rowFrame    = rowFrame,
            barFrame    = barFrame,
            smoothBar   = smoothBar,
            smoothBG    = smoothBG,   -- kept for show/hide in ApplyBarMode
            smoothLabel = smoothLabel,
            blocks      = blockFrames,
            blockLabel  = blockLabel,
        }
    end

    hudFrame:SetAlpha(s.hudAlpha)
    hudFrame:SetScale(s.hudScale)
    ICN2:ApplyBarMode()
    if not s.hudEnabled then hudFrame:Hide() end
end

-- ── Switch between smooth and blocky display modes ────────────────────────────
function ICN2:ApplyBarMode()
    if not hudFrame then return end
    local blocky = ICN2DB.settings.blockyBars

    for _, key in ipairs(NEED_KEYS) do
        local data = bars[key]
        if data then
            if blocky then
                data.smoothBar:Hide()
                -- smoothBG is a texture on barFrame — hide it separately
                data.smoothBG:Hide()
                data.smoothLabel:Hide()
                for _, bf in ipairs(data.blocks) do bf.empty:Show() end
                data.blockLabel:Show()
            else
                data.smoothBar:Show()
                data.smoothBG:Show()
                data.smoothLabel:Show()
                for _, bf in ipairs(data.blocks) do
                    bf.fill:Hide()
                    bf.empty:Hide()
                end
                data.blockLabel:Hide()
            end
        end
    end
end

-- ── Update all bars ───────────────────────────────────────────────────────────
function ICN2:UpdateHUD()
    if not hudFrame then return end

    if not ICN2DB.settings.hudEnabled then
        hudFrame:Hide()
        return
    end
    hudFrame:Show()

    local values = {
        hunger  = ICN2DB.hunger,
        thirst  = ICN2DB.thirst,
        fatigue = ICN2DB.fatigue,
    }
    local blocky = ICN2DB.settings.blockyBars

    for _, key in ipairs(NEED_KEYS) do
        local data = bars[key]
        if data then
            local val     = values[key] or 0
            local r, g, b = getNeedColor(key, val)

            if blocky then
                -- v1.1.3: math.floor = full blocks only (73% → 7 blocks, not 8)
                -- This preserves the intentional imprecision of the blocky mode.
                local filled = (val >= 100) and 10 or math.floor(val / 10)
                for b = 1, NUM_BLOCKS do
                    local bf = data.blocks[b]
                    if b <= filled then
                        bf.fill:SetColorTexture(r, g, b, 1.0)
                        bf.fill:Show()
                    else
                        bf.fill:Hide()
                    end
                end
                data.blockLabel:SetText(filled .. "/" .. NUM_BLOCKS)
                data.blockLabel:SetTextColor(r, g, b)
            else
                data.smoothBar:SetValue(val)
                data.smoothBar:SetStatusBarColor(r, g, b)
                data.smoothLabel:SetText(string.format("%.0f%%", val))
            end
        end
    end
end

-- ── Toggle blocky mode ────────────────────────────────────────────────────────
function ICN2:SetBlockyBars(enabled)
    ICN2DB.settings.blockyBars = enabled
    ICN2:ApplyBarMode()
    ICN2:UpdateHUD()
end

-- ── Lock/unlock dragging ──────────────────────────────────────────────────────
function ICN2:LockHUD(locked)
    if hudFrame then hudFrame:EnableMouse(not locked) end
end
