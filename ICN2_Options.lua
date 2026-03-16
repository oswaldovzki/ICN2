-- ============================================================
-- ICN2_Options.lua  (v1.1)
-- In-game options panel: preset picker, emote toggles,
-- HUD opacity/scale, v1.1 toggles, manual need controls.
-- ============================================================

ICN2 = ICN2 or {}

local optFrame

-- ── Utility: create a simple label ───────────────────────────────────────────
local function makeLabel(parent, text, x, y, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

-- ── Utility: create a checkbox ───────────────────────────────────────────────
local function makeCheckbox(parent, label, x, y, getter, setter)
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

-- ── Utility: create a simple slider ──────────────────────────────────────────
local function makeSlider(parent, labelText, x, y, minVal, maxVal, step, getter, setter)
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

-- ── Utility: thin horizontal separator line ───────────────────────────────────
local function makeSeparator(parent, x, y, width)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    tex:SetSize(width or 350, 1)
    tex:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    return tex
end

-- ── Build options panel ───────────────────────────────────────────────────────
function ICN2:BuildOptions()
    -- v1.1: taller frame to accommodate two new sections
    optFrame = CreateFrame("Frame", "ICN2OptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    optFrame:SetSize(450, 660)
    optFrame:SetPoint("CENTER")
    optFrame:SetFrameStrata("HIGH")
    optFrame:SetMovable(true)
    optFrame:EnableMouse(true)
    optFrame:RegisterForDrag("LeftButton")
    optFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    optFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    optFrame:Hide()

    optFrame.TitleText:SetText("|cFFFF6600ICN2|r – Character Needs Options  |cFF888888v1.1|r")

    -- ── Section: Decay Preset ────────────────────────────────────────────────
    makeLabel(optFrame, "Decay Preset:", 14, -35, 1, 0.8, 0)

    local presets = { "fast", "medium", "slow", "realistic", "custom" }
    local presetBtns = {}
    for i, p in ipairs(presets) do
        local btn = CreateFrame("Button", nil, optFrame, "UIPanelButtonTemplate")
        btn:SetSize(64, 22)
        btn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 14 + (i - 1) * 68, -55)
        btn:SetText(p:sub(1,1):upper() .. p:sub(2))
        btn:SetScript("OnClick", function()
            ICN2DB.settings.preset = p
            for _, b in pairs(presetBtns) do b:SetAlpha(0.6) end
            btn:SetAlpha(1.0)
        end)
        btn:SetAlpha(ICN2DB.settings.preset == p and 1.0 or 0.6)
        presetBtns[p] = btn
    end

    makeSeparator(optFrame, 14, -84, 358)

    -- ── Section: HUD ─────────────────────────────────────────────────────────
    makeLabel(optFrame, "HUD Settings:", 14, -92, 1, 0.8, 0)

    makeCheckbox(optFrame, "Enable HUD", 14, -112,
        function() return ICN2DB.settings.hudEnabled end,
        function(v) ICN2DB.settings.hudEnabled = v; ICN2:UpdateHUD() end)

    makeCheckbox(optFrame, "Lock HUD Position", 14, -138,
        function() return ICN2DB.settings.hudLocked end,
        function(v) ICN2DB.settings.hudLocked = v; ICN2:LockHUD(v) end)

    -- v1.1: Blocky bars toggle
    makeCheckbox(optFrame, "Blocky Bars  |cFF888888(10 blocks, less precise)|r", 200, -112,
        function() return ICN2DB.settings.blockyBars end,
        function(v) ICN2:SetBlockyBars(v) end)

    makeSlider(optFrame, "Opacity", 14, -170, 0.1, 1.0, 0.05,
        function() return ICN2DB.settings.hudAlpha end,
        function(v)
            ICN2DB.settings.hudAlpha = v
            local f = _G["ICN2HUDFrame"]
            if f then f:SetAlpha(v) end
        end)

    makeSlider(optFrame, "Scale", 14, -215, 0.5, 2.0, 0.1,
        function() return ICN2DB.settings.hudScale end,
        function(v)
            ICN2DB.settings.hudScale = v
            local f = _G["ICN2HUDFrame"]
            if f then f:SetScale(v) end
        end)

    makeSlider(optFrame, "Bar Length", 14, -258, 0.5, 1.5, 0.05,
        function() return ICN2DB.settings.hudBarScale or 1.0 end,
        function(v)
            ICN2DB.settings.hudBarScale = v
            ICN2:ResizeBarLength()
        end)

    makeSeparator(optFrame, 14, -303, 358)

    -- ── Section: v1.1 Immersion Settings ─────────────────────────────────────
    makeLabel(optFrame, "Immersion:", 14, -266, 1, 0.8, 0)

    -- v1.1: Freeze offline needs
    makeCheckbox(optFrame, "Freeze needs while offline  |cFF888888(no offline decay)|r", 14, -286,
        function() return ICN2DB.settings.freezeOfflineNeeds end,
        function(v) ICN2DB.settings.freezeOfflineNeeds = v end)

    -- Food/drink info line
    local fdLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fdLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 14, -318)
    fdLabel:SetText("|cFF888888Eating/drinking: auto-detected via WoW food/drink buffs.|r")
    fdLabel:SetWidth(360)

    makeSeparator(optFrame, 14, -379, 358)

    -- ── Section: Emotes ───────────────────────────────────────────────────────
    makeLabel(optFrame, "Emotes:", 14, -387, 1, 0.8, 0)

    makeCheckbox(optFrame, "Enable automatic emotes", 14, -407,
        function() return ICN2DB.settings.emotesEnabled end,
        function(v) ICN2DB.settings.emotesEnabled = v end)

    makeSlider(optFrame, "Emote Chance", 14, -437, 0.0, 1.0, 0.05,
        function() return ICN2DB.settings.emoteChance end,
        function(v) ICN2DB.settings.emoteChance = v end)

    makeSlider(optFrame, "Min Interval (sec)", 14, -482, 30, 600, 10,
        function() return ICN2DB.settings.emoteMinInterval end,
        function(v) ICN2DB.settings.emoteMinInterval = v end)

    makeSeparator(optFrame, 14, -525, 358)

    -- ── Section: Manual restore buttons ──────────────────────────────────────
    makeLabel(optFrame, "Manual Restore:", 14, -533, 1, 0.8, 0)

    local eatBtn = CreateFrame("Button", nil, optFrame, "UIPanelButtonTemplate")
    eatBtn:SetSize(80, 24)
    eatBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 14, -551)
    eatBtn:SetText("|cFF00FF00Eat|r")
    eatBtn:SetScript("OnClick", function() ICN2:Eat(50) end)

    local drinkBtn = CreateFrame("Button", nil, optFrame, "UIPanelButtonTemplate")
    drinkBtn:SetSize(80, 24)
    drinkBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 102, -551)
    drinkBtn:SetText("|cFF4499FFDrink|r")
    drinkBtn:SetScript("OnClick", function() ICN2:Drink(50) end)

    local restBtn = CreateFrame("Button", nil, optFrame, "UIPanelButtonTemplate")
    restBtn:SetSize(80, 24)
    restBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 190, -551)
    restBtn:SetText("|cFFFFDD00Rest|r")
    restBtn:SetScript("OnClick", function() ICN2:Rest(40) end)

    local resetBtn = CreateFrame("Button", nil, optFrame, "UIPanelButtonTemplate")
    resetBtn:SetSize(80, 24)
    resetBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 278, -551)
    resetBtn:SetText("|cFFFF4444Reset|r")
    resetBtn:SetScript("OnClick", function()
        ICN2DB.hunger  = 100
        ICN2DB.thirst  = 100
        ICN2DB.fatigue = 100
        ICN2:UpdateHUD()
    end)

    -- ── Section: Manual deplete buttons ──────────────────────────────────────
    makeLabel(optFrame, "Manual Deplete:", 14, -585, 1, 0.8, 0)

    local starveBtn = CreateFrame("Button", nil, optFrame, "UIPanelButtonTemplate")
    starveBtn:SetSize(80, 24)
    starveBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 14, -603)
    starveBtn:SetText("|cFFFF4444Starve|r")
    starveBtn:SetScript("OnClick", function()
        ICN2DB.hunger = 0
        ICN2:UpdateHUD()
    end)

    local dehydrateBtn = CreateFrame("Button", nil, optFrame, "UIPanelButtonTemplate")
    dehydrateBtn:SetSize(80, 24)
    dehydrateBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 102, -603)
    dehydrateBtn:SetText("|cFFFF4444Dehydrate|r")
    dehydrateBtn:SetScript("OnClick", function()
        ICN2DB.thirst = 0
        ICN2:UpdateHUD()
    end)

    local exhaustBtn = CreateFrame("Button", nil, optFrame, "UIPanelButtonTemplate")
    exhaustBtn:SetSize(80, 24)
    exhaustBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 190, -603)
    exhaustBtn:SetText("|cFFFF4444Exhaust|r")
    exhaustBtn:SetScript("OnClick", function()
        ICN2DB.fatigue = 0
        ICN2:UpdateHUD()
    end)
end

-- ── Toggle visibility ─────────────────────────────────────────────────────────
function ICN2:ToggleOptions()
    if optFrame:IsShown() then
        optFrame:Hide()
    else
        optFrame:Show()
    end
end
