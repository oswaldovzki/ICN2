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

-- Spanish (esES, esMX)
if GetLocale() == "esES" or GetLocale() == "esMX" then
    L["HUNGER"] = "Hambre"
    L["THIRST"] = "Sed"
    L["FATIGUE"] = "Fatiga"
    L["MSG_RESET"] = "Necesidades restablecidas al 100%."
    L["MSG_SET"] = "%s establecido en 0%."
    L["OPT_HUD_ENABLED"] = "Activar HUD"
    L["OPT_EMOTES_ENABLED"] = "Activar emotos automáticos"
    L["OPT_IMMERSIVE"] = "Modo inmersivo (Ocultar al 100%)"
    L["OPT_DECAY_PRESET"] = "Preajuste de desgaste"
    L["OPT_HUD_SCALE"] = "Escala de la barra"
    L["DESC_DECAY"] = "Elige una velocidad de desgaste global o usa Personalizado para ajustar cada necesidad."
end

-- French (frFR)
if GetLocale() == "frFR" then
    L["HUNGER"] = "Faim"
    L["THIRST"] = "Soif"
    L["FATIGUE"] = "Fatigue"
    L["MSG_RESET"] = "Besoins rétablis à 100 %."
    L["MSG_SET"] = "%s défini à 0 %."
    L["OPT_HUD_ENABLED"] = "Activer le HUD"
    L["OPT_EMOTES_ENABLED"] = "Activer les émotes automatiques"
    L["OPT_IMMERSIVE"] = "Mode immersif (Cacher à 100 %)"
    L["OPT_DECAY_PRESET"] = "Préréglage de décroissance"
    L["OPT_HUD_SCALE"] = "Échelle de la barre"
    L["DESC_DECAY"] = "Choisissez une vitesse de décroissance globale ou utilisez Personnalisé pour ajuster chaque besoin."
end

-- German (deDE)
if GetLocale() == "deDE" then
    L["HUNGER"] = "Hunger"
    L["THIRST"] = "Durst"
    L["FATIGUE"] = "Erschöpfung"
    L["MSG_RESET"] = "Bedürfnisse auf 100 % zurückgesetzt."
    L["MSG_SET"] = "%s auf 0 % gesetzt."
    L["OPT_HUD_ENABLED"] = "HUD aktivieren"
    L["OPT_EMOTES_ENABLED"] = "Automatische Emotes aktivieren"
    L["OPT_IMMERSIVE"] = "Immersiver Modus (Bei 100 % ausblenden)"
    L["OPT_DECAY_PRESET"] = "Verfallsvorgabe"
    L["OPT_HUD_SCALE"] = "Leistenskalierung"
    L["DESC_DECAY"] = "Wähle eine globale Verfallsgeschwindigkeit oder nutze Benutzerdefiniert, um jedes Bedürfnis anzupassen."
end
