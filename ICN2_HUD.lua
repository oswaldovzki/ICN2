-- ============================================================
-- ICN2_HUD.lua  (v1.1)
-- On-screen status bars: hunger, thirst, fatigue.
-- Draggable, scalable. Supports smooth bar OR blocky 10-block mode.
-- ============================================================

ICN2 = ICN2 or {}

local hudFrame
local bars = {}  -- keyed by need name

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

    hudFrame = CreateFrame("Frame", "ICN2HUDFrame", UIParent)
    hudFrame:SetWidth(ICON_SIZE + BAR_WIDTH + 14)
    hudFrame:SetHeight((BAR_HEIGHT + BAR_GAP) * 3 + 14)
    hudFrame:SetFrameStrata("MEDIUM")
    hudFrame:SetClampedToScreen(true)
    hudFrame:SetPoint("CENTER", UIParent, "CENTER", s.hudX or 200, s.hudY or -250)

    -- Background
    local bg = hudFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

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

    -- Build each need row
    for i, key in ipairs(NEED_KEYS) do
        local yOffset = -((i - 1) * (BAR_HEIGHT + BAR_GAP)) - 7
        local xBase   = ICON_SIZE + 9
        local c = s["color" .. (key:sub(1,1):upper() .. key:sub(2))]

        -- Icon
        local icon = hudFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 5, yOffset - 1)
        icon:SetTexture(ICONS[key])
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- ── Smooth bar ───────────────────────────────────────────────────────
        local smoothBG = CreateFrame("Frame", nil, hudFrame)
        smoothBG:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", xBase, yOffset)
        smoothBG:SetSize(BAR_WIDTH, BAR_HEIGHT)
        local bgTex = smoothBG:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints()
        bgTex:SetColorTexture(0.12, 0.12, 0.12, 0.9)

        local smoothBar = CreateFrame("StatusBar", "ICN2SmoothBar_" .. key, hudFrame)
        smoothBar:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", xBase, yOffset)
        smoothBar:SetSize(BAR_WIDTH, BAR_HEIGHT)
        smoothBar:SetMinMaxValues(0, 100)
        smoothBar:SetValue(100)
        smoothBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        smoothBar:SetStatusBarColor(c[1], c[2], c[3])

        local smoothLabel = smoothBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        smoothLabel:SetPoint("RIGHT", smoothBar, "RIGHT", -3, 0)
        smoothLabel:SetText("100%")

        -- ── Blocky bar (10 discrete blocks) ──────────────────────────────────
        local blockFrames = {}
        for b = 1, NUM_BLOCKS do
            local bx = xBase + (b - 1) * (BLOCK_WIDTH + BLOCK_GAP)

            -- Empty slot (always shown in blocky mode)
            local emptyTex = hudFrame:CreateTexture(nil, "ARTWORK")
            emptyTex:SetSize(BLOCK_WIDTH, BAR_HEIGHT)
            emptyTex:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", bx, yOffset)
            emptyTex:SetColorTexture(0.12, 0.12, 0.12, 0.9)
            emptyTex:Hide()

            -- Filled block (shown when this block is active)
            local fillTex = hudFrame:CreateTexture(nil, "OVERLAY")
            fillTex:SetSize(BLOCK_WIDTH, BAR_HEIGHT)
            fillTex:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", bx, yOffset)
            fillTex:SetColorTexture(c[1], c[2], c[3], 1.0)
            fillTex:Hide()

            blockFrames[b] = { fill = fillTex, empty = emptyTex }
        end

        -- Block count label  "7/10"
        local blockLabel = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        blockLabel:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", xBase + BAR_WIDTH - 28, yOffset - 1)
        blockLabel:SetText("10/10")
        blockLabel:Hide()

        bars[key] = {
            smoothBar   = smoothBar,
            smoothBG    = smoothBG,
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
            local val  = values[key] or 0
            local r, g, b = getNeedColor(key, val)

            if blocky then
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
