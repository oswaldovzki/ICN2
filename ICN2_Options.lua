-- ============================================================
-- ICN2_Options.lua
-- Tabbed options: General (HUD, immersion, emotes, manual) and
-- Decay & rates (presets + per-need bias sliders for Custom).
-- ============================================================

ICN2 = ICN2 or {}

local optFrame
local panelGeneral
local panelDecay
local tabBtnGeneral
local tabBtnDecay
local presetBtns = {}
local decaySliders = {}

-- ── Utility: create a simple label ───────────────────────────────────────────
local function makeLabel(parent, text, x, y, r, g, b) -- color optional (default white)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

-- ── Utility: create a checkbox ───────────────────────────────────────────────
local function makeCheckbox(parent, label, x, y, getter, setter) -- getter/setter for boolean value
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb:SetSize(24, 24)
    cb.text:SetText(label)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked())
    end)
    return cb
end

-- ── Utility: create a simple slider (float) ──────────────────────────────────
local function makeSlider(parent, labelText, x, y, minVal, maxVal, step, getter, setter) -- getter/setter for numeric value
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetWidth(180)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(getter())

    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))
    slider.Text:SetText(labelText .. ": " .. string.format("%.2f", getter()))

    slider:SetScript("OnValueChanged", function(self, val)
        setter(val)
        self.Text:SetText(labelText .. ": " .. string.format("%.2f", val))
    end)
    return slider
end

-- ── Decay bias slider: integer 0..max (0 = no passive decay; max = 10× Fast), optional read-only ──
local function formatBiasLabel(needLabel, sliderPos, decayMult, readOnly)
    local ro = readOnly and "  |cFF888888(preset)|r" or ""
    return string.format("%s: %d  (×%.2f vs Medium base)%s", needLabel, sliderPos, decayMult, ro)
end

local function roundBias(n)
    return math.floor((tonumber(n) or 0) + 0.5)
end

local function getBiasForUI(needKey) -- Converts from internal multiplier to slider position, applying preset if needed.
    local s = ICN2DB.settings
    if s.preset == "custom" then
        local v = s.customDecayBias and s.customDecayBias[needKey]
        if v == nil then v = 1 end
        return roundBias(v)
    end
    local m = ICN2.PRESETS[s.preset] or 1.0
    return roundBias(ICN2:PresetMultiplierToBiasDisplay(m))
end

local function refreshDecaySliders() -- Updates slider positions and labels based on current settings. Called when opening the tab and when changing presets.
    local s = ICN2DB.settings
    local isCustom = (s.preset == "custom")
    local presetGlobal = ICN2.PRESETS[s.preset] or 1.0
    for _, row in ipairs(decaySliders) do
        row.slider:Enable()
        local bias = getBiasForUI(row.needKey)
        local decayMult
        if isCustom then
            local v = s.customDecayBias and s.customDecayBias[row.needKey]
            if v == nil then v = 1 end
            decayMult = ICN2:DecayBiasToMultiplier(v)
        else
            decayMult = presetGlobal
        end
        row.slider:SetValue(bias)
        row.slider.Text:SetText(formatBiasLabel(row.needLabel, bias, decayMult, not isCustom))
        if isCustom then
            row.slider:Enable()
        else
            row.slider:Disable()
        end
    end
end

local function makeDecayBiasSlider(parent, needKey, needLabel, x, y) -- Creates a slider for adjusting decay bias for a specific need. The slider is read-only unless the "Custom" preset is selected.
    local maxM = ICN2.CUSTOM_DECAY_MULTIPLIER_MAX or 30
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetWidth(300)
    slider:SetMinMaxValues(0, maxM)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    slider.Low:SetText("0")
    slider.High:SetText(tostring(maxM))

    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        if val < 0 then val = 0 elseif val > maxM then val = maxM end
        if ICN2DB.settings.preset ~= "custom" then
            self:SetValue(getBiasForUI(needKey))
            return
        end
        if not ICN2DB.settings.customDecayBias then
            ICN2DB.settings.customDecayBias = { hunger = 1, thirst = 1, fatigue = 1 }
        end
        ICN2DB.settings.customDecayBias[needKey] = val
        local mult = ICN2:DecayBiasToMultiplier(val)
        self.Text:SetText(formatBiasLabel(needLabel, val, mult, false))
    end)

    table.insert(decaySliders, { slider = slider, needKey = needKey, needLabel = needLabel })
    return slider
end

-- ── Utility: thin horizontal separator line ───────────────────────────────────
local function makeSeparator(parent, x, y, width)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    tex:SetSize(width or 350, 1)
    tex:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    return tex
end

-- ── Tab switching ─────────────────────────────────────────────────────────────
local function selectOptionsTab(which)
    if which == 1 then
        panelGeneral:Show()
        panelDecay:Hide()
        tabBtnGeneral:SetAlpha(1)
        tabBtnDecay:SetAlpha(0.55)
    else
        panelGeneral:Hide()
        panelDecay:Show()
        tabBtnGeneral:SetAlpha(0.55)
        tabBtnDecay:SetAlpha(1)
        refreshDecaySliders()
    end
end

local function makeTabButton(parent, text, x, y, onClick) -- Utility: creates a button to switch between options tabs. onClick should call selectOptionsTab with the appropriate tab number.
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(130, 26)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- ── Build options panel ───────────────────────────────────────────────────────
function ICN2:BuildOptions() -- Called once on ADDON_LOADED to construct the options UI. The frame is hidden by default and shown when the user clicks "Options" in the slash command or via Interface Options.
    decaySliders = {}
    presetBtns = {}

    optFrame = CreateFrame("Frame", "ICN2OptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    optFrame:SetSize(460, 640)
    optFrame:SetPoint("CENTER")
    optFrame:SetFrameStrata("HIGH")
    optFrame:SetMovable(true)
    optFrame:EnableMouse(true)
    optFrame:RegisterForDrag("LeftButton")
    optFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    optFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    optFrame:Hide()

    optFrame.TitleText:SetText("|cFFFF6600ICN2|r – Character Needs  |cFF888888v1.5.0|r")

    -- Tabs
    tabBtnGeneral = makeTabButton(optFrame, "General", 14, -28, function() selectOptionsTab(1) end)
    tabBtnDecay   = makeTabButton(optFrame, "Decay & rates", 148, -28, function() selectOptionsTab(2) end)

    -- Content panels (shared area below tabs)
    panelGeneral = CreateFrame("Frame", nil, optFrame)
    panelGeneral:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 0, -58)
    panelGeneral:SetPoint("BOTTOMRIGHT", optFrame, "BOTTOMRIGHT", -6, 6)

    panelDecay = CreateFrame("Frame", nil, optFrame)
    panelDecay:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 0, -58)
    panelDecay:SetPoint("BOTTOMRIGHT", optFrame, "BOTTOMRIGHT", -6, 6)
    panelDecay:Hide()

    -- ══════════ GENERAL TAB ══════════════════════════════════════════════════
    makeLabel(panelGeneral, "HUD", 14, -6, 1, 0.8, 0)

    makeCheckbox(panelGeneral, "Enable HUD", 14, -26,
        function() return ICN2DB.settings.hudEnabled end,
        function(v) ICN2DB.settings.hudEnabled = v; ICN2:UpdateHUD() end)

    makeCheckbox(panelGeneral, "Lock HUD position", 14, -52,
        function() return ICN2DB.settings.hudLocked end,
        function(v) ICN2DB.settings.hudLocked = v; ICN2:LockHUD(v) end)

    makeLabel(panelGeneral, "Theme:", 200, -6, 1, 0.8, 0)

    local THEMES = ICN2.HUD_THEME_LIST or {
        { id = "smooth", label = "Smooth" },
        { id = "blocky", label = "Blocky" },
        { id = "folk", label = "Folk" },
        { id = "necromancer", label = "Necromancer" },
    }

    local themeDropdown = CreateFrame("Frame", "ICN2ThemeDropdown", panelGeneral, "UIDropDownMenuTemplate")
    themeDropdown:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 188, -20)

    local function themeLabel()
        local current = ICN2DB.settings.barTheme or "smooth"
        if ICN2.GetHUDTheme then
            return (ICN2:GetHUDTheme(current).label) or "Smooth"
        end
        for _, t in ipairs(THEMES) do
            if t.id == current then return t.label end
        end
        return "Smooth"
    end

    UIDropDownMenu_SetWidth(themeDropdown, 140)
    UIDropDownMenu_SetText(themeDropdown, themeLabel())

    UIDropDownMenu_Initialize(themeDropdown, function(self, level)
        for _, t in ipairs(THEMES) do
            local info   = UIDropDownMenu_CreateInfo()
            local themeId = t.id
            info.text    = t.label
            info.value   = themeId
            info.checked = (ICN2DB.settings.barTheme or "smooth") == themeId
            info.func    = function()
                UIDropDownMenu_SetText(themeDropdown, t.label)
                CloseDropDownMenus()
                ICN2:SetBarTheme(themeId)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local LABEL_MODES = {
    { id = "none",       label = "None" },
    { id = "percentage", label = "Percentage" },
    { id = "number",     label = "Number" },
    { id = "both",       label = "Both" },
}

    local labelDropdown = CreateFrame("Frame", "ICN2LabelDropdown", panelGeneral, "UIDropDownMenuTemplate")
    labelDropdown:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 188, -70)

    local function labelModeLabel()
        local current = ICN2DB.settings.barLabelMode or "percentage"
        for _, lm in ipairs(LABEL_MODES) do
            if lm.id == current then return lm.label end
        end
        return "Percentage"
    end

    UIDropDownMenu_SetWidth(labelDropdown, 140)
    UIDropDownMenu_SetText(labelDropdown, labelModeLabel())

    UIDropDownMenu_Initialize(labelDropdown, function(self, level)
        for _, lm in ipairs(LABEL_MODES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = lm.label
            info.value   = lm.id
            info.checked = (ICN2DB.settings.barLabelMode or "percentage") == lm.id
            info.func    = function()
                ICN2DB.settings.barLabelMode = lm.id
                UIDropDownMenu_SetText(labelDropdown, lm.label)
                CloseDropDownMenus()
                ICN2:UpdateHUD()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    makeSlider(panelGeneral, "Opacity", 14, -84, 0.1, 1.0, 0.05,
        function() return ICN2DB.settings.hudAlpha end,
        function(v)
            ICN2DB.settings.hudAlpha = v
            local f = _G["ICN2HUDFrame"]
            if f then f:SetAlpha(v) end
        end)

    makeSlider(panelGeneral, "Scale", 14, -129, 0.5, 2.0, 0.1,
        function() return ICN2DB.settings.hudScale end,
        function(v)
            ICN2DB.settings.hudScale = v
            local f = _G["ICN2HUDFrame"]
            if f then f:SetScale(v) end
        end)

    makeSlider(panelGeneral, "Bar length", 14, -172, 0.5, 1.5, 0.05,
        function() return ICN2DB.settings.hudBarScale or 1.0 end,
        function(v)
            ICN2DB.settings.hudBarScale = v
            ICN2:ResizeBarLength()
        end)

    makeSeparator(panelGeneral, 14, -217, 358)

    makeLabel(panelGeneral, "Immersion", 14, -225, 1, 0.8, 0)

    makeCheckbox(panelGeneral, "Freeze needs while offline  |cFF888888(no offline decay)|r", 14, -245,
        function() return ICN2DB.settings.freezeOfflineNeeds end,
        function(v) ICN2DB.settings.freezeOfflineNeeds = v end)

    local fdLabel = panelGeneral:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fdLabel:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 14, -277)
    fdLabel:SetText("|cFF888888Food/drink buffs are detected automatically.|r")
    fdLabel:SetWidth(400)

    makeSeparator(panelGeneral, 14, -302, 358)

    makeLabel(panelGeneral, "Emotes", 14, -310, 1, 0.8, 0)

    makeCheckbox(panelGeneral, "Enable automatic emotes", 14, -330,
        function() return ICN2DB.settings.emotesEnabled end,
        function(v) ICN2DB.settings.emotesEnabled = v end)

    makeSlider(panelGeneral, "Emote chance", 14, -360, 0.0, 1.0, 0.05,
        function() return ICN2DB.settings.emoteChance end,
        function(v) ICN2DB.settings.emoteChance = v end)

    makeSlider(panelGeneral, "Min interval (sec)", 14, -405, 30, 600, 10,
        function() return ICN2DB.settings.emoteMinInterval end,
        function(v) ICN2DB.settings.emoteMinInterval = v end)

    makeSeparator(panelGeneral, 14, -448, 358)

    makeLabel(panelGeneral, "Manual restore", 14, -456, 1, 0.8, 0)

    local eatBtn = CreateFrame("Button", nil, panelGeneral, "UIPanelButtonTemplate")
    eatBtn:SetSize(80, 24)
    eatBtn:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 14, -474)
    eatBtn:SetText("|cFF00FF00Eat|r")
    eatBtn:SetScript("OnClick", function() ICN2:Eat(50) end)

    local drinkBtn = CreateFrame("Button", nil, panelGeneral, "UIPanelButtonTemplate")
    drinkBtn:SetSize(80, 24)
    drinkBtn:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 102, -474)
    drinkBtn:SetText("|cFF4499FFDrink|r")
    drinkBtn:SetScript("OnClick", function() ICN2:Drink(50) end)

    local restBtn = CreateFrame("Button", nil, panelGeneral, "UIPanelButtonTemplate")
    restBtn:SetSize(80, 24)
    restBtn:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 190, -474)
    restBtn:SetText("|cFFFFDD00Rest|r")
    restBtn:SetScript("OnClick", function() ICN2:Rest(40) end)

    local resetBtn = CreateFrame("Button", nil, panelGeneral, "UIPanelButtonTemplate")
    resetBtn:SetSize(80, 24)
    resetBtn:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 278, -474)
    resetBtn:SetText("|cFFFF4444Reset|r")
    resetBtn:SetScript("OnClick", function()
        ICN2DB.hunger  = ICN2:GetMaxValue("hunger")
        ICN2DB.thirst  = ICN2:GetMaxValue("thirst")
        ICN2DB.fatigue = ICN2:GetMaxValue("fatigue")
        ICN2:UpdateHUD()
    end)

    makeLabel(panelGeneral, "Manual deplete", 14, -508, 1, 0.8, 0)

    local starveBtn = CreateFrame("Button", nil, panelGeneral, "UIPanelButtonTemplate")
    starveBtn:SetSize(80, 24)
    starveBtn:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 14, -526)
    starveBtn:SetText("|cFFFF4444Starve|r")
    starveBtn:SetScript("OnClick", function()
        ICN2DB.hunger = 0
        ICN2:UpdateHUD()
    end)

    local dehydrateBtn = CreateFrame("Button", nil, panelGeneral, "UIPanelButtonTemplate")
    dehydrateBtn:SetSize(80, 24)
    dehydrateBtn:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 102, -526)
    dehydrateBtn:SetText("|cFFFF4444Dehydrate|r")
    dehydrateBtn:SetScript("OnClick", function()
        ICN2DB.thirst = 0
        ICN2:UpdateHUD()
    end)

    local exhaustBtn = CreateFrame("Button", nil, panelGeneral, "UIPanelButtonTemplate")
    exhaustBtn:SetSize(80, 24)
    exhaustBtn:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 190, -526)
    exhaustBtn:SetText("|cFFFF4444Exhaust|r")
    exhaustBtn:SetScript("OnClick", function()
        ICN2DB.fatigue = 0
        ICN2:UpdateHUD()
    end)

    -- ══════════ DECAY TAB ════════════════════════════════════════════════════
    makeLabel(panelDecay, "Decay preset", 14, -6, 1, 0.8, 0)

    local presets = { "fast", "medium", "slow", "realistic", "custom" }
    presetBtns = {}
    for i, p in ipairs(presets) do
        local btn = CreateFrame("Button", nil, panelDecay, "UIPanelButtonTemplate")
        btn:SetSize(72, 24)
        btn:SetPoint("TOPLEFT", panelDecay, "TOPLEFT", 14 + (i - 1) * 76, -26)
        btn:SetText(p:sub(1, 1):upper() .. p:sub(2))
        btn:SetScript("OnClick", function()
            ICN2DB.settings.preset = p
            for name, b in pairs(presetBtns) do
                b:SetAlpha(name == p and 1.0 or 0.55)
            end
            refreshDecaySliders()
        end)
        presetBtns[p] = btn
    end

    for _, p in ipairs(presets) do
        presetBtns[p]:SetAlpha(ICN2DB.settings.preset == p and 1.0 or 0.55)
    end

    local help1 = panelDecay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help1:SetPoint("TOPLEFT", panelDecay, "TOPLEFT", 14, -58)
    help1:SetWidth(420)
    help1:SetJustifyH("LEFT")
    help1:SetText(
        "|cFFCCCCCCChoose a preset for global decay speed, or |cFFFFCC00Custom|r to tune each need.|r\n" ..
        "|cFF888888Custom multiplier vs Medium (1×): |cFFFFFFFF0|r = no passive decay; |cFFFFFFFF" ..
        tostring(ICN2.CUSTOM_DECAY_MULTIPLIER_MAX or 30) ..
        "|r = 10× Fast. Sliders are read-only unless Custom.|r"
    )

    makeSeparator(panelDecay, 14, -108, 400)

    makeLabel(panelDecay, "Per-need decay bias", 14, -118, 1, 0.8, 0)

    makeDecayBiasSlider(panelDecay, "hunger",  "Hunger",  14, -142)
    makeDecayBiasSlider(panelDecay, "thirst",  "Thirst",  14, -192)
    makeDecayBiasSlider(panelDecay, "fatigue", "Fatigue", 14, -242)

    refreshDecaySliders()

    optFrame:SetScript("OnShow", function()
        if panelDecay:IsShown() then
            refreshDecaySliders()
        end
        for _, p in ipairs(presets) do
            if presetBtns[p] then
                presetBtns[p]:SetAlpha(ICN2DB.settings.preset == p and 1.0 or 0.55)
            end
        end
    end)

    selectOptionsTab(1)
end

-- ── Toggle visibility ─────────────────────────────────────────────────────────
function ICN2:ToggleOptions()
    if optFrame:IsShown() then
        optFrame:Hide()
    else
        optFrame:Show()
    end
end
