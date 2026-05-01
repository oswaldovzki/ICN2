-- ============================================================
-- ICN2_HUD.lua
-- On-screen HUD: hunger, thirst, fatigue.
-- Draggable, scalable.
-- ============================================================

ICN2 = ICN2 or {}

local L = setmetatable({}, { __index = function(_, k)
    return ICN2.L and ICN2.L[k] or k
end })

-- ── Module state ──────────────────────────────────────────────────────────────
local hudFrame
local chrome = {}
local bars   = {}

-- ── Layout constants ──────────────────────────────────────────────────────────
local BAR_H       = 20
local BAR_GAP     = 8
local ICON_SIZE   = 24
local NUM_BLOCKS  = 10
local BLOCK_GAP   = 2
local INDICATOR_W = 30
local HEADER_H    = 26
local CHROME_PAD  = 6

local BASE_BAR_W  = (BAR_H + BLOCK_GAP) * NUM_BLOCKS   -- 220px at scale 1.0

local NEED_KEYS = { "hunger", "thirst", "fatigue" }

-- ── Default need icons ────────────────────────────────────────────────────────
local NEED_ICONS = {
    hunger  = "Interface\\Icons\\inv_misc_food_cooked_greatpabanquet_general",
    thirst  = "Interface\\Icons\\inv_drink_18_color03",
    fatigue = "Interface\\Icons\\ui_campcollection",
}

-- ── Fallback bar colors ───────────────────────────────────────────────────────
local BLOCK_COLORS = {
    hunger  = { 0.2, 0.9,  0.2 },
    thirst  = { 0.2, 0.5,  1.0 },
    fatigue = { 1.0, 0.85, 0.1 },
}

local DEFAULT_FILL_TEX = "Interface\\TargetingFrame\\UI-StatusBar"

-- ═══ SECTION 1 — Theme descriptors ═════════════════════════════════════════════
-- This is a Work In Progress for future implementation.
-- Only the "smooth" theme is fully supported at the moment; the others are placeholders for testing new textures and ideas.
ICN2.HUD_THEMES = {

    smooth = {
        id    = "smooth",
        label = "Smooth",
        mode  = "smooth",
        chrome = {
            bgCenter      = { 0.05, 0.05, 0.05, 0.88 },
            cornerTL      = nil, cornerTR = nil,
            cornerBL      = nil, cornerBR = nil,
            edgeTop       = nil, edgeBottom = nil,
            edgeLeft      = nil, edgeRight  = nil,
            titleStrip    = nil,
            cornerSize    = 8, edgeThickness = 4,
        },
        bar = {
            bg      = { 0.12, 0.12, 0.12, 0.9 },
            fill    = DEFAULT_FILL_TEX,
            overlay = nil,
        },
        barColors = nil,
    },

    blocky = {
        id    = "blocky",
        label = "Blocky",
        mode  = "blocky",
        chrome = {
            bgCenter      = { 0.05, 0.05, 0.05, 0.88 },
            cornerTL      = nil, cornerTR = nil,
            cornerBL      = nil, cornerBR = nil,
            edgeTop       = nil, edgeBottom = nil,
            edgeLeft      = nil, edgeRight  = nil,
            titleStrip    = nil,
            cornerSize    = 8, edgeThickness = 4,
        },
        bar = {
            bg      = { 0.12, 0.12, 0.12, 0.9 },
            fill    = DEFAULT_FILL_TEX,
            overlay = nil,
        },
        barColors = nil,
    },

    folk = {
        id    = "folk",
        label = "Folk  |cFF888888(WIP)|r",
        mode  = "smooth",
        chrome = {
            bgCenter      = { 0.08, 0.05, 0.02, 0.92 },
            cornerTL      = nil, cornerTR = nil,
            cornerBL      = nil, cornerBR = nil,
            edgeTop       = nil, edgeBottom = nil,
            edgeLeft      = nil, edgeRight  = nil,
            titleStrip    = nil,
            cornerSize    = 8, edgeThickness = 4,
        },
        bar = {
            bg      = { 0.10, 0.07, 0.04, 0.95 },
            fill    = DEFAULT_FILL_TEX,
            overlay = nil,
        },
        barColors = {
            hunger  = { 0.85, 0.55, 0.15 },
            thirst  = { 0.30, 0.65, 0.90 },
            fatigue = { 0.70, 0.85, 0.30 },
        },
    },

    necromancer = {
        id    = "necromancer",
        label = "Necromancer  |cFF888888(WIP)|r",
        mode  = "smooth",
        chrome = {
            bgCenter      = { 0.03, 0.03, 0.04, 0.96 },
            cornerTL      = "Necrolord-NineSlice-CornerTopLeft", cornerTR = "Necrolord-NineSlice-CornerTopRight",
            cornerBL      = nil, cornerBR = nil,
            edgeTop       = nil, edgeBottom = nil,
            edgeLeft      = "Necrolord-NineSlice-CornerBottomLeft", edgeRight  = "Necrolord-NineSlice-CornerBottomRight",
            titleStrip    = "UI-Frame-Necrolord-Ribbon",
            cornerSize    = 8,
            edgeThickness = 4,
        },
        bar = {
            bg      = { 0.06, 0.06, 0.06, 0.98 },
            fill    = DEFAULT_FILL_TEX,
            overlay = "UI-Frame-Necrolord-TitleLeft",
        },
        barColors = {
            hunger  = { 0.55, 0.85, 0.30 },
            thirst  = { 0.50, 0.20, 0.80 },
            fatigue = { 0.18, 0.18, 0.18 },
        },
    },

    dastardly = {
        id    = "dastardly",
        label = "Dastardly",
        mode  = "smooth",
        chrome = {
            bgCenter      = { 0.04, 0.04, 0.04, 0.92 },
            cornerTL      = "UI-Frame-DastardlyDuos-CornerTopLeft",
            cornerTR      = "UI-Frame-DastardlyDuos-CornerTopRight",
            cornerBL      = "UI-Frame-DastardlyDuos-CornerBottomLeft",
            cornerBR      = "UI-Frame-DastardlyDuos-CornerBottomRight",
            edgeTop       = "UI-Frame-DastardlyDuos-Line-Top",
            edgeBottom    = "UI-Frame-DastardlyDuos-Line-Bottom",
            edgeLeft      = nil,
            edgeRight     = nil,
            titleStrip    = "UI-Frame-DastardlyDuos-Line-Top",
            cornerSize    = 16,
            edgeThickness = 8,
        },
        bar = {
            bg      = { 0.08, 0.06, 0.03, 0.95 },
            fill    = DEFAULT_FILL_TEX,
            overlay = "UI-Frame-DastardlyDuos-Bar-Frame-gold",
        },
        barColors = {
            hunger  = { 0.85, 0.55, 0.15 },
            thirst  = { 0.30, 0.65, 0.90 },
            fatigue = { 0.70, 0.85, 0.30 },
        },
    },
}

ICN2.HUD_THEME_LIST = {
    ICN2.HUD_THEMES.smooth,
    ICN2.HUD_THEMES.blocky,
    ICN2.HUD_THEMES.folk,
    ICN2.HUD_THEMES.necromancer,
    ICN2.HUD_THEMES.dastardly,
}

local function getTheme()
    local id = ICN2DB and ICN2DB.settings and ICN2DB.settings.barTheme or "smooth"
    return ICN2.HUD_THEMES[id] or ICN2.HUD_THEMES.smooth
end

-- ══ SECTION 2 — Indicator logic ════════════════════════════════════════════════
local IND_FASTER_UP   =  0.50
local IND_FAST_UP     =  0.30
local IND_FAST_DOWN   = -0.30
local IND_FASTER_DOWN = -0.50
local STABLE_EPSILON  =  0.002

local PULSE_PERIOD = 2.0
local PULSE_MIN    = 0.25
local PULSE_MAX    = 1.0

local function shouldPulse(glyph)  return glyph ~= "##"  end

local function getNeedColor(key, val) -- returns r,g,b in 0..1 range
    if val <= ICN2.THRESHOLDS.critical then return 0.9, 0.1, 0.1
    elseif val <= ICN2.THRESHOLDS.low  then return 0.9, 0.6, 0.1
    else
        local theme = getTheme()
        local fc = (theme.barColors and theme.barColors[key]) or BLOCK_COLORS[key]
        return fc[1], fc[2], fc[3]
    end
end

local function getIndicator(rate)
    if math.abs(rate) <= STABLE_EPSILON then return "##",  0.5, 0.5, 0.5
    elseif rate >= IND_FASTER_UP        then return ">>>", 0.0, 1.0, 0.0
    elseif rate >= IND_FAST_UP          then return ">>",  0.2, 0.9, 0.1
    elseif rate >  0                    then return ">",   0.7, 0.9, 0.4
    elseif rate <= IND_FASTER_DOWN      then return "<<<", 1.0, 0.0, 0.0
    elseif rate <= IND_FAST_DOWN        then return "<<",  0.9, 0.2, 0.1
    else                                     return "<",   0.9, 0.7, 0.1
    end
end

-- ══ SECTION 3 — Texture slot helper ════════════════════════════════════════════
local function applyTexSlot(tex, value) -- value can be nil (hide), string (SetAtlas) or table (SetColorTexture); tex can be nil (no-op)
    if not tex then return end
    if value == nil then
        tex:Hide()
    elseif type(value) == "string" then
        tex:SetAtlas(value, true)
        tex:Show()
    elseif type(value) == "table" then
        tex:SetColorTexture(value[1], value[2], value[3], value[4] or 1)
        tex:Show()
    end
end

-- ══  SECTION 4 — Build HUD  ════════════════════════════════════════════════════
function ICN2:BuildHUD() -- called once on demand when HUD is first shown; builds entire frame hierarchy and saves references in module state
    local s        = ICN2DB.settings
    local barScale = s.hudBarScale or 1.0
    local barW     = math.floor(BASE_BAR_W * barScale)
    local innerW   = ICON_SIZE + 4 + barW + INDICATOR_W
    local frameW   = innerW + CHROME_PAD * 2 + 8
    local frameH   = HEADER_H + (#NEED_KEYS * (BAR_H + BAR_GAP)) + CHROME_PAD * 2

    -- ── Root frame ────────────────────────────────────────────────────────────
    hudFrame = CreateFrame("Frame", "ICN2HUDFrame", UIParent)
    hudFrame:SetSize(frameW, frameH)
    hudFrame:SetFrameStrata("MEDIUM")
    hudFrame:SetClampedToScreen(true)
    hudFrame:SetPoint("CENTER", UIParent, "CENTER", s.hudX or 200, s.hudY or -250)
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
        GameTooltip:SetText(L["TOOLTIP_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(string.format(L["TOOLTIP_HUNGER"],  ICN2:GetNeedPercent("hunger")),  0.2, 0.8, 0.2)
        GameTooltip:AddLine(string.format(L["TOOLTIP_THIRST"],  ICN2:GetNeedPercent("thirst")),  0.2, 0.5, 1.0)
        GameTooltip:AddLine(string.format(L["TOOLTIP_FATIGUE"], ICN2:GetNeedPercent("fatigue")), 1.0, 0.85, 0.1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["TOOLTIP_HINT"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    hudFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Nine-slice chrome slots (all created hidden; ApplyHUDTheme drives them)
    chrome.bgCenter = hudFrame:CreateTexture(nil, "BACKGROUND")
    chrome.bgCenter:SetAllPoints()
    chrome.bgCenter:Hide()

    -- Corners: fixed squares anchored to each corner of hudFrame
    local cornerAnchors = {
        cornerTL = { "TOPLEFT",     "TOPLEFT"     },
        cornerTR = { "TOPRIGHT",    "TOPRIGHT"    },
        cornerBL = { "BOTTOMLEFT",  "BOTTOMLEFT"  },
        cornerBR = { "BOTTOMRIGHT", "BOTTOMRIGHT" },
    }
    for slot, anchors in pairs(cornerAnchors) do
        local tex = hudFrame:CreateTexture(nil, "BORDER")
        tex:SetPoint(anchors[1], hudFrame, anchors[2], 0, 0)
        tex:Hide()
        chrome[slot] = tex
    end

    -- Edges: stretch between opposite corners
    chrome.edgeTop = hudFrame:CreateTexture(nil, "BORDER")
    chrome.edgeTop:SetPoint("TOPLEFT",  hudFrame, "TOPLEFT",  0, 0)
    chrome.edgeTop:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", 0, 0)
    chrome.edgeTop:Hide()

    chrome.edgeBottom = hudFrame:CreateTexture(nil, "BORDER")
    chrome.edgeBottom:SetPoint("BOTTOMLEFT",  hudFrame, "BOTTOMLEFT",  0, 0)
    chrome.edgeBottom:SetPoint("BOTTOMRIGHT", hudFrame, "BOTTOMRIGHT", 0, 0)
    chrome.edgeBottom:Hide()

    chrome.edgeLeft = hudFrame:CreateTexture(nil, "BORDER")
    chrome.edgeLeft:SetPoint("TOPLEFT",    hudFrame, "TOPLEFT",    0, 0)
    chrome.edgeLeft:SetPoint("BOTTOMLEFT", hudFrame, "BOTTOMLEFT", 0, 0)
    chrome.edgeLeft:Hide()

    chrome.edgeRight = hudFrame:CreateTexture(nil, "BORDER")
    chrome.edgeRight:SetPoint("TOPRIGHT",    hudFrame, "TOPRIGHT",    0, 0)
    chrome.edgeRight:SetPoint("BOTTOMRIGHT", hudFrame, "BOTTOMRIGHT", 0, 0)
    chrome.edgeRight:Hide()

    -- Title strip: full-width band across the top of the frame
    chrome.titleStrip = hudFrame:CreateTexture(nil, "ARTWORK")
    chrome.titleStrip:SetPoint("TOPLEFT",  hudFrame, "TOPLEFT",  0, 0)
    chrome.titleStrip:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", 0, 0)
    chrome.titleStrip:SetHeight(HEADER_H)
    chrome.titleStrip:Hide()

    -- ── Header ────────────────────────────────────────────────────────────────
    local headerFrame = CreateFrame("Frame", nil, hudFrame)
    headerFrame:SetHeight(HEADER_H)
    headerFrame:SetPoint("TOPLEFT",  hudFrame, "TOPLEFT",  CHROME_PAD, -CHROME_PAD)
    headerFrame:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -CHROME_PAD, -CHROME_PAD)

    local title = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", headerFrame, "LEFT", 4, 0)
    title:SetText(L["HUD_TITLE"])

    local btnOptions = CreateFrame("Button", nil, headerFrame)
    btnOptions:SetSize(20, 20)
    btnOptions:SetPoint("RIGHT", headerFrame, "RIGHT", -2, 0)
    local bOptTex = btnOptions:CreateTexture(nil, "ARTWORK")
    bOptTex:SetAllPoints()
    bOptTex:SetAtlas("glues-characterSelect-icon-notify-inProgress-hover")
    btnOptions:SetScript("OnClick", function() ICN2:ToggleOptions() end)

    local btnDetails = CreateFrame("Button", nil, headerFrame)
    btnDetails:SetSize(20, 20)
    btnDetails:SetPoint("RIGHT", btnOptions, "LEFT", -2, 0)
    local bDetTex = btnDetails:CreateTexture(nil, "ARTWORK")
    bDetTex:SetAllPoints()
    bDetTex:SetAtlas("loreobject-32x32")
    btnDetails:SetScript("OnClick", function() ICN2:PrintDetails() end)

    -- ── Content area ──────────────────────────────────────────────────────────
    local contentFrame = CreateFrame("Frame", nil, hudFrame)
    contentFrame:SetPoint("TOPLEFT",     headerFrame, "BOTTOMLEFT",  0, -4)
    contentFrame:SetPoint("BOTTOMRIGHT", hudFrame,    "BOTTOMRIGHT", -CHROME_PAD, CHROME_PAD)

    -- ── Need rows ─────────────────────────────────────────────────────────────
    for i, key in ipairs(NEED_KEYS) do
        local fc   = BLOCK_COLORS[key]
        local rowY = -((i - 1) * (BAR_H + BAR_GAP)) - 4

        local rowFrame = CreateFrame("Frame", "ICN2Row_" .. key, contentFrame)
        rowFrame:SetSize(innerW, BAR_H)
        rowFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", CHROME_PAD - 2, rowY)

        -- Need icon
        local icon = rowFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)
        icon:SetTexture(NEED_ICONS[key])
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Bar container frame
        local barFrame = CreateFrame("Frame", "ICN2BarFrame_" .. key, rowFrame)
        barFrame:SetSize(barW, BAR_H)
        barFrame:SetPoint("LEFT", rowFrame, "LEFT", ICON_SIZE + 4, 0)

        -- Bar background track  (slot: barBG)
        local barBG = barFrame:CreateTexture(nil, "BACKGROUND")
        barBG:SetAllPoints()
        barBG:SetColorTexture(0.12, 0.12, 0.12, 0.9)

        -- Animated fill  (slot: barFill)
        local barFill = CreateFrame("StatusBar", "ICN2BarFill_" .. key, barFrame)
        barFill:SetAllPoints()
        barFill:SetMinMaxValues(0, 100)
        barFill:SetValue(100)
        barFill:SetStatusBarTexture(DEFAULT_FILL_TEX)
        barFill:SetStatusBarColor(fc[1], fc[2], fc[3])

        -- Percentage label
        local barLabelLeft = barFill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        barLabelLeft:SetPoint("LEFT", barFill, "LEFT", 3, 0)
        barLabelLeft:SetText("")
        barLabelLeft:Hide()

        local barLabelRight = barFill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        barLabelRight:SetPoint("RIGHT", barFill, "RIGHT", -3, 0)
        barLabelRight:SetText("")
        barLabelRight:Hide()

        -- Decorative overlay above fill  (slot: barOverlay)
        local barOverlay = barFrame:CreateTexture(nil, "OVERLAY")
        barOverlay:SetAllPoints()
        barOverlay:Hide()

        -- ── Blocky blocks ──────────────────────────────────────────────────────
        local BEVEL = 1
        local INSET = 2
        local blockFrames = {}

        for b = 1, NUM_BLOCKS do
            local bx = (b - 1) * (BAR_H + BLOCK_GAP)

            local borderTex = barFrame:CreateTexture(nil, "BACKGROUND")
            borderTex:SetSize(BAR_H, BAR_H)
            borderTex:SetPoint("TOPLEFT", barFrame, "TOPLEFT", bx, 0)
            borderTex:SetColorTexture(0.05, 0.05, 0.05, 1.0)
            borderTex:Hide()

            local bevelTop = barFrame:CreateTexture(nil, "BORDER")
            bevelTop:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + BEVEL,         -BEVEL)
            bevelTop:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BAR_H - BEVEL, -(BEVEL + 1))
            bevelTop:SetColorTexture(0.55, 0.55, 0.55, 0.9)
            bevelTop:Hide()

            local bevelLeft = barFrame:CreateTexture(nil, "BORDER")
            bevelLeft:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + BEVEL,     -BEVEL)
            bevelLeft:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BEVEL + 1, -(BAR_H - BEVEL))
            bevelLeft:SetColorTexture(0.55, 0.55, 0.55, 0.9)
            bevelLeft:Hide()

            local bevelBottom = barFrame:CreateTexture(nil, "BORDER")
            bevelBottom:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + BEVEL,         -(BAR_H - BEVEL - 1))
            bevelBottom:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BAR_H - BEVEL, -(BAR_H - BEVEL))
            bevelBottom:SetColorTexture(0.0, 0.0, 0.0, 0.9)
            bevelBottom:Hide()

            local bevelRight = barFrame:CreateTexture(nil, "BORDER")
            bevelRight:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + BAR_H - BEVEL - 1, -BEVEL)
            bevelRight:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BAR_H - BEVEL,     -(BAR_H - BEVEL))
            bevelRight:SetColorTexture(0.0, 0.0, 0.0, 0.9)
            bevelRight:Hide()

            local innerBG = barFrame:CreateTexture(nil, "ARTWORK")
            innerBG:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + INSET,         -INSET)
            innerBG:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BAR_H - INSET, -(BAR_H - INSET))
            innerBG:SetColorTexture(0.10, 0.10, 0.10, 1.0)
            innerBG:Hide()

            local fillTex = barFrame:CreateTexture(nil, "OVERLAY")
            fillTex:SetPoint("TOPLEFT",     barFrame, "TOPLEFT", bx + INSET,         -INSET)
            fillTex:SetPoint("BOTTOMRIGHT", barFrame, "TOPLEFT", bx + BAR_H - INSET, -(BAR_H - INSET))
            fillTex:SetColorTexture(fc[1], fc[2], fc[3], 0.90)
            fillTex:Hide()

            blockFrames[b] = {
                fill = fillTex,
                geo  = { borderTex, bevelTop, bevelLeft, bevelBottom, bevelRight, innerBG },
            }
        end

        -- ── Glyph indicator + pulse ────────────────────────────────────────────
        local glyphText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- separate from bar labels so it can pulse independently
        glyphText:SetPoint("RIGHT", rowFrame, "RIGHT", -2, 0)
        glyphText:SetText("##")
        glyphText:SetTextColor(0.5, 0.5, 0.5)
        glyphText:SetAlpha(1.0)

        local pulseFrame   = CreateFrame("Frame", nil, rowFrame)
        local pulseElapsed = 0
        local pulseRunning = false

        pulseFrame:SetScript("OnUpdate", function(_, dt)
            if not pulseRunning then return end
            pulseElapsed = pulseElapsed + dt
            local t = (pulseElapsed % PULSE_PERIOD) / PULSE_PERIOD
            local a = PULSE_MIN + (PULSE_MAX - PULSE_MIN)
                      * (0.5 + 0.5 * math.sin(t * math.pi * 2 - math.pi / 2))
            glyphText:SetAlpha(a)
        end)

        bars[key] = {
            rowFrame      = rowFrame,
            icon          = icon,
            barFrame      = barFrame,
            barBG         = barBG,
            barFill       = barFill,
            barOverlay    = barOverlay,
            barLabelLeft  = barLabelLeft,
            barLabelRight = barLabelRight,
            blocks        = blockFrames,
            glyphText     = glyphText,
            setPulse      = function(active)
                pulseRunning = active
                if not active then
                    pulseElapsed = 0
                    glyphText:SetAlpha(1.0)
                end
            end,
        }
    end

    -- Apply saved state
    hudFrame:SetAlpha(s.hudAlpha or 1.0)
    hudFrame:SetScale(s.hudScale or 1.0)

    -- Migrate legacy blockyBars
    if not s.barTheme then
        s.barTheme = s.blockyBars and "blocky" or "smooth"
    end
    ICN2:ApplyHUDTheme(s.barTheme)
    if not s.hudEnabled then hudFrame:Hide() end
end

-- ═══ SECTION 5 — Theme application ══════════════════════════════════════════
function ICN2:ApplyHUDTheme(themeId) -- walks theme descriptor and applies textures/colors to named slots; called on theme change and on initial build
    if not hudFrame then return end

    local theme = ICN2.HUD_THEMES[themeId] or ICN2.HUD_THEMES.smooth
    ICN2DB.settings.barTheme   = theme.id
    ICN2DB.settings.blockyBars = (theme.mode == "blocky")

    local c          = theme.chrome or {}
    local cornerSize = c.cornerSize    or 8
    local edgeThick  = c.edgeThickness or 4

    -- Background
    applyTexSlot(chrome.bgCenter, c.bgCenter)

    -- Corners
    for _, slot in ipairs({ "cornerTL", "cornerTR", "cornerBL", "cornerBR" }) do
        chrome[slot]:SetSize(cornerSize, cornerSize)
        applyTexSlot(chrome[slot], c[slot])
    end

    -- Edges
    chrome.edgeTop:SetHeight(edgeThick)
    applyTexSlot(chrome.edgeTop, c.edgeTop)

    chrome.edgeBottom:SetHeight(edgeThick)
    applyTexSlot(chrome.edgeBottom, c.edgeBottom)

    chrome.edgeLeft:SetWidth(edgeThick)
    applyTexSlot(chrome.edgeLeft, c.edgeLeft)

    chrome.edgeRight:SetWidth(edgeThick)
    applyTexSlot(chrome.edgeRight, c.edgeRight)

    -- Title strip
    applyTexSlot(chrome.titleStrip, c.titleStrip)

    -- Per-bar slots
    local barDef     = theme.bar or {}
    local barBGColor = barDef.bg   or { 0.12, 0.12, 0.12, 0.9 }
    local fillTex    = barDef.fill or DEFAULT_FILL_TEX

    for _, key in ipairs(NEED_KEYS) do
        local data = bars[key]
        if data then
            data.barBG:SetColorTexture(
                barBGColor[1], barBGColor[2], barBGColor[3], barBGColor[4] or 1)
            data.barFill:SetStatusBarTexture(fillTex)
            if barDef.overlay then
                data.barOverlay:SetAtlas(barDef.overlay, true)
                data.barOverlay:Show()
            else
                data.barOverlay:Hide()
            end
        end
    end

    ICN2:ApplyBarMode()
end

-- ── Public entry points ────────────────────────────────────────────────────────
function ICN2:SetBarTheme(themeId)
    ICN2:ApplyHUDTheme(themeId)
    ICN2:UpdateHUD()
end

function ICN2:SetBlockyBars(enabled)  -- legacy shim
    ICN2:SetBarTheme(enabled and "blocky" or "smooth")
end

-- ══  SECTION 6 — Bar mode  ═════════════════════════════════════════════════════
function ICN2:ApplyBarMode() -- show/hide bar fill vs blocks based on current theme.mode; called from ApplyHUDTheme and on initial build
    if not hudFrame then return end
    local mode = getTheme().mode

    for _, key in ipairs(NEED_KEYS) do
        local data = bars[key]
        if data then
            if mode == "blocky" then
                data.barFill:Hide()
                data.barBG:Hide()
                data.barLabelLeft:Hide()
                data.barLabelRight:Hide()
                data.barOverlay:Hide()
                for _, bf in ipairs(data.blocks) do
                    for _, tex in ipairs(bf.geo) do tex:Show() end
                end
            else
                -- Smooth mode: show smooth bar, hide blocks
                data.barFill:Show()
                data.barBG:Show()
                -- Labels handled by UpdateHUD based on labelMode
                for _, bf in ipairs(data.blocks) do
                    bf.fill:Hide()
                    for _, tex in ipairs(bf.geo) do tex:Hide() end
                end
            end
        end
    end
end

-- ══  SECTION 7 — Update loop  ═══════════════════════════════════════════════════
function ICN2:UpdateHUD() -- called every tick from OnUpdate script; updates bar fill levels, colors, labels, and indicators based on current need values and rates
    if not hudFrame then return end
    if not ICN2DB.settings.hudEnabled then hudFrame:Hide(); return end
    hudFrame:Show()

    local values = {
        hunger  = ICN2:GetNeedPercent("hunger"),
        thirst  = ICN2:GetNeedPercent("thirst"),
        fatigue = ICN2:GetNeedPercent("fatigue"),
    }
    local rates     = ICN2:GetCurrentRates()
    local mode      = getTheme().mode
    local labelMode = ICN2DB.settings.barLabelMode or "percentage"

    for _, key in ipairs(NEED_KEYS) do -- main loop: update each bar based on current value/rate and theme mode
        local data = bars[key]
        if data then
            local val     = values[key] or 0
            local r, g, b = getNeedColor(key, val)

            if mode == "blocky" then
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
                data.barFill:SetValue(val)
                data.barFill:SetStatusBarColor(r, g, b)
                local current = ICN2DB[key] or 0
                local maxVal  = ICN2:GetMaxValue(key)
                local pctText = string.format("%.0f%%", val)
                local numText = string.format("%.0f/%.0f", current, maxVal)

                if labelMode == "none" then
                    data.barLabelLeft:Hide()
                    data.barLabelRight:Hide()
                elseif labelMode == "percentage" then
                    data.barLabelLeft:Hide()
                    data.barLabelRight:SetText(pctText)
                    data.barLabelRight:Show()
                elseif labelMode == "number" then
                    data.barLabelLeft:Hide()
                    data.barLabelRight:SetText(numText)
                    data.barLabelRight:Show()
                elseif labelMode == "both" then
                    data.barLabelLeft:SetText(numText)
                    data.barLabelLeft:Show()
                    data.barLabelRight:SetText(pctText)
                    data.barLabelRight:Show()
                end
            end

            local glyph, ir, ig, ib = getIndicator(rates[key] or 0)
            data.glyphText:SetText(glyph)
            data.glyphText:SetTextColor(ir, ig, ib)
            data.setPulse(shouldPulse(glyph))
        end
    end
end

-- ══  SECTION 8 — Resize / Lock  ════════════════════════════════════════════════
function ICN2:ResizeBarLength() -- called when user changes bar scale; recalculates bar and frame widths and applies to all relevant elements
    if not hudFrame then return end

    local barScale = ICN2DB.settings.hudBarScale or 1.0
    local barW     = math.floor(BASE_BAR_W * barScale)
    local innerW   = ICON_SIZE + 4 + barW + INDICATOR_W
    local frameW   = innerW + CHROME_PAD * 2 + 8
    local frameH   = HEADER_H + (#NEED_KEYS * (BAR_H + BAR_GAP)) + CHROME_PAD * 2

    hudFrame:SetSize(frameW, frameH)

    for _, key in ipairs(NEED_KEYS) do
        local data = bars[key]
        if data then
            data.rowFrame:SetSize(innerW, BAR_H)
            data.barFrame:SetSize(barW, BAR_H)
        end
    end
end

function ICN2:LockHUD(locked) -- called when user toggles HUD lock; enables/disables mouse interaction on hudFrame to allow dragging when unlocked
    if hudFrame then hudFrame:EnableMouse(not locked) end
end