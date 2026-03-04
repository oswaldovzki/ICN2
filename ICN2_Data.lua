-- ============================================================
-- ICN2_Data.lua
-- Static tables: defaults, race/class modifiers, emotes
-- ============================================================

ICN2 = ICN2 or {}

-- ── Default SavedVariables structure ──────────────────────────────────────────
ICN2.DEFAULTS = {
    hunger  = 100.0,   -- percentage 0-100
    thirst  = 100.0,
    fatigue = 100.0,
    lastLogout = nil,  -- timestamp via time()

    settings = {
        -- "fast" | "medium" | "slow" | "realistic" | "custom"
        preset = "medium",

        -- Decay per real-time second (% lost per second) for each preset
        -- These are base rates; situational multipliers are applied on top.
        -- Custom rates can override these individually.
        decayRates = {
            hunger  = 0.0014,   -- ~100% in ~20 minutes at medium
            thirst  = 0.0028,   -- ~100% in ~10 minutes at medium
            fatigue = 0.0007,   -- ~100% in ~40 minutes at medium
        },

        -- HUD
        hudEnabled   = true,
        hudLocked    = false,
        hudScale     = 1.0,
        hudAlpha     = 0.9,
        hudX         = nil,   -- set dynamically on first load
        hudY         = nil,

        -- v1.1: Offline decay
        freezeOfflineNeeds = false,  -- if true, needs are frozen while logged out

        -- v1.1: Blocky bar display
        blockyBars = false,  -- if true, HUD shows 10 discrete blocks instead of smooth bar

        -- Emotes
        emotesEnabled    = true,
        emoteChance      = 0.3,  -- probability per threshold crossing (0-1)
        emoteMinInterval = 120,  -- minimum seconds between emotes

        -- Bar colors (r, g, b)
        colorHunger  = {0.2, 0.8, 0.2},
        colorThirst  = {0.2, 0.5, 1.0},
        colorFatigue = {1.0, 0.85, 0.1},
    },
}

-- ── Preset multipliers (applied to base decay) ────────────────────────────────
ICN2.PRESETS = {
    fast      = 3.0,
    medium    = 1.0,
    slow      = 0.5,
    realistic = 0.15,
    custom    = 1.0,  -- user sets their own rates directly
}

-- ── Situational decay multipliers ─────────────────────────────────────────────
-- These modify the decay rate based on what the player is doing.
-- All three needs are multiplied by the *combined* modifier.
ICN2.SITUATION_MODIFIERS = {
    swimming   = { hunger = 1.4, thirst = 1.5, fatigue = 1.8 },
    flying     = { hunger = 0.9, thirst = 1.0, fatigue = 0.6 },
    mounted    = { hunger = 0.8, thirst = 0.9, fatigue = 0.5 },
    resting    = { hunger = 0.5, thirst = 0.6, fatigue = 0.2 },
    combat     = { hunger = 1.2, thirst = 1.3, fatigue = 1.5 },
    indoors    = { hunger = 0.9, thirst = 0.9, fatigue = 0.9 },
    -- default (walking/idle outdoors) = 1.0 multiplier
}

-- ── Race modifiers (multiplied on top of situation) ───────────────────────────
-- 1.0 = normal, >1.0 = decays faster, <1.0 = decays slower
ICN2.RACE_MODIFIERS = {
    -- Horde
    ["Orc"]            = { hunger = 0.9,  thirst = 1.0,  fatigue = 0.9  },
    ["Undead"]         = { hunger = 0.6,  thirst = 0.7,  fatigue = 0.8  },  -- Cannibalize helps
    ["Tauren"]         = { hunger = 1.1,  thirst = 1.0,  fatigue = 0.85 },
    ["Troll"]          = { hunger = 1.0,  thirst = 1.1,  fatigue = 1.0  },
    ["BloodElf"]       = { hunger = 1.0,  thirst = 1.0,  fatigue = 1.0  },
    ["Goblin"]         = { hunger = 1.2,  thirst = 1.2,  fatigue = 1.1  },  -- hyperactive metabolism
    ["Nightborne"]     = { hunger = 0.9,  thirst = 0.9,  fatigue = 0.9  },
    ["HighmountainTauren"] = { hunger = 1.15, thirst = 1.0, fatigue = 0.8 },
    ["MagharOrc"]      = { hunger = 0.85, thirst = 0.9,  fatigue = 0.85 },
    ["Vulpera"]        = { hunger = 1.1,  thirst = 1.3,  fatigue = 1.0  },  -- desert dwellers: conserve water?
    ["ZandalariTroll"] = { hunger = 1.0,  thirst = 1.0,  fatigue = 0.9  },

    -- Alliance
    ["Human"]          = { hunger = 1.0,  thirst = 1.0,  fatigue = 1.0  },
    ["Dwarf"]          = { hunger = 1.1,  thirst = 1.0,  fatigue = 0.9  },
    ["NightElf"]       = { hunger = 0.85, thirst = 0.9,  fatigue = 0.85 },
    ["Gnome"]          = { hunger = 1.2,  thirst = 1.2,  fatigue = 1.2  },  -- small + fast = burns more
    ["Draenei"]        = { hunger = 0.8,  thirst = 0.85, fatigue = 0.8  },
    ["Worgen"]         = { hunger = 1.3,  thirst = 1.1,  fatigue = 1.1  },
    ["VoidElf"]        = { hunger = 0.9,  thirst = 0.9,  fatigue = 0.9  },
    ["LightforgedDraenei"] = { hunger = 0.75, thirst = 0.8, fatigue = 0.75 },
    ["DarkIronDwarf"]  = { hunger = 1.1,  thirst = 1.0,  fatigue = 0.9  },
    ["KulTiran"]       = { hunger = 1.05, thirst = 1.0,  fatigue = 0.95 },
    ["Mechagnome"]     = { hunger = 0.7,  thirst = 0.6,  fatigue = 0.7  },  -- cybernetic body

    -- Neutral/Other
    ["Pandaren"]       = { hunger = 0.9,  thirst = 0.9,  fatigue = 0.85 },
    ["Dracthyr"]       = { hunger = 0.8,  thirst = 0.85, fatigue = 0.8  },
    ["EarthenDwarf"]   = { hunger = 0.65, thirst = 0.6,  fatigue = 0.7  },  -- stone body

    -- Demon Hunter
    ["DemonHunter"]    = { hunger = 0.9,  thirst = 0.9,  fatigue = 0.9  },  -- soul feeding helps
}

-- ── Class modifiers ───────────────────────────────────────────────────────────
ICN2.CLASS_MODIFIERS = {
    ["WARRIOR"]     = { hunger = 1.15, thirst = 1.1,  fatigue = 1.1  },  -- heavy armor, constant exertion
    ["PALADIN"]     = { hunger = 1.0,  thirst = 1.0,  fatigue = 0.95 },  -- divine sustenance
    ["HUNTER"]      = { hunger = 0.9,  thirst = 0.95, fatigue = 0.9  },  -- used to the wild
    ["ROGUE"]       = { hunger = 1.0,  thirst = 1.0,  fatigue = 1.0  },
    ["PRIEST"]      = { hunger = 0.85, thirst = 0.85, fatigue = 0.85 },
    ["SHAMAN"]      = { hunger = 0.9,  thirst = 0.9,  fatigue = 0.9  },
    ["MAGE"]        = { hunger = 0.9,  thirst = 0.85, fatigue = 0.9  },  -- conjured food
    ["WARLOCK"]     = { hunger = 0.85, thirst = 0.9,  fatigue = 0.9  },  -- life tap sustains
    ["MONK"]        = { hunger = 0.9,  thirst = 0.9,  fatigue = 0.85 },
    ["DRUID"]       = { hunger = 0.9,  thirst = 0.9,  fatigue = 0.85 },
    ["DEMONHUNTER"] = { hunger = 0.85, thirst = 0.9,  fatigue = 0.9  },
    ["DEATHKNIGHT"] = { hunger = 0.7,  thirst = 0.6,  fatigue = 0.7  },  -- undead, reduced needs
    ["EVOKER"]      = { hunger = 0.85, thirst = 0.9,  fatigue = 0.8  },
}

-- ── Emote tables by state ─────────────────────────────────────────────────────
ICN2.EMOTES = {
    hungry = {
        critical = { "/lick", "/drool", "/hungry" },
        low      = { "/lick", "/drool", "/moan" },
    },
    thirsty = {
        critical = { "/cough", "/thirsty", "/sigh" },
        low      = { "/cough", "/thirsty" },
    },
    tired = {
        critical = { "/yawn", "/sleep", "/sigh", "/tired" },
        low      = { "/yawn", "/sigh" },
    },
    satisfied = {
        hunger  = { "/burp", "/smile", "/flex" },
        thirst  = { "/burp", "/cheer" },
        fatigue = { "/flex", "/cheer", "/dance" },
    },
}

-- ── Threshold levels (% remaining) ───────────────────────────────────────────
-- "critical" ≤ 15%, "low" ≤ 35%, "ok" > 35%
ICN2.THRESHOLDS = {
    critical = 15,
    low      = 35,
    ok       = 100,
}

-- ── Armor type fatigue multipliers ────────────────────────────────────────────
ICN2.ARMOR_FATIGUE = {
    PLATE  = 1.20,
    MAIL   = 1.10,
    LEATHER= 1.00,
    CLOTH  = 0.90,
}
