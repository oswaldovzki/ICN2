local _, _ = ...
local L = setmetatable({}, { __index = function(t, k) return k end })
ICN2.L = L

-- English (Default)
L["HUNGER"] = "Hunger"
L["THIRST"] = "Thirst"
L["FATIGUE"] = "Fatigue"
L["MSG_RESET"] = "Needs reset to 100%."
L["MSG_SET"] = "%s set to 0%."
L["OPT_HUD_ENABLED"] = "Enable HUD"
L["OPT_EMOTES_ENABLED"] = "Enable Auto-Emotes"
L["OPT_IMMERSIVE"] = "Immersive Mode (Hide at 100%)"
L["OPT_DECAY_PRESET"] = "Global Decay Preset"
L["OPT_HUD_SCALE"] = "HUD Bar Scale"
L["DESC_DECAY"] = "Choose a preset for global decay speed, or Custom to tune each need."

-- Portuguese (ptBR)
if GetLocale() == "ptBR" then
    L["HUNGER"] = "Fome"
    L["THIRST"] = "Sede"
    L["FATIGUE"] = "Fadiga"
    L["MSG_RESET"] = "Necessidades restauradas para 100%."
    L["MSG_SET"] = "%s definido para 0%."
    L["OPT_HUD_ENABLED"] = "Habilitar HUD"
    L["OPT_EMOTES_ENABLED"] = "Habilitar Emotes Automáticos"
    L["OPT_IMMERSIVE"] = "Modo Imersivo (Esconder em 100%)"
    L["OPT_DECAY_PRESET"] = "Predefinição de Decaimento"
    L["OPT_HUD_SCALE"] = "Escala da Barra"
    L["DESC_DECAY"] = "Escolha a velocidade de decaimento global ou use Customizado para ajustar cada um."
end