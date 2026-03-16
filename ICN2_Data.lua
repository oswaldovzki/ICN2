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

        -- Decay per real-time second (% lost per second) at medium preset (multiplier = 1.0)
        -- hunger/thirst: 100% in 30 min  → 100 / (30×60) ≈ 0.05556% per second
        -- fatigue:       100% in 60 min  → 100 / (60×60) ≈ 0.02778% per second
        -- Situational and race/class multipliers are applied on top of these base values.
        decayRates = {
            hunger  = 0.05556,
            thirst  = 0.05556,
            fatigue = 0.02778,
        },

        -- HUD
        hudEnabled   = true,
        hudLocked    = false,
        hudScale     = 1.0,
        hudAlpha     = 1.0,   -- overall transparency of the HUD (0-1)
        hudBarScale  = 1.0,   -- bar length multiplier (0.5 = half, 1.5 = 150%)
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
    realistic = 0.15
    -- custom    = 1.0,  -- user sets their own rates directly
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
    indoors    = { hunger = 1.0, thirst = 1.0, fatigue = 0.8 },
    -- default (walking/idle outdoors) = 1.0 multiplier
}

-- ── Race modifiers (multiplied on top of situation) ───────────────────────────
-- 1.0 = normal, >1.0 = decays faster, <1.0 = decays slower
ICN2.RACE_MODIFIERS = {
    -- Horde
    ["Orc"]            = { hunger = 0.9,  thirst = 1.0,  fatigue = 0.9  },
    ["Scourge"]        = { hunger = 0.5,  thirst = 0.5,  fatigue = 0.8  },  -- undead don't need food/water, but still get tired from body parts decaying
    ["Tauren"]         = { hunger = 1.1,  thirst = 1.0,  fatigue = 0.85 },
    ["Troll"]          = { hunger = 1.0,  thirst = 1.1,  fatigue = 1.0  },
    ["BloodElf"]       = { hunger = 1.0,  thirst = 1.0,  fatigue = 1.0  },
    ["Goblin"]         = { hunger = 1.2,  thirst = 1.2,  fatigue = 1.1  },  -- hyperactive metabolism
    ["Nightborne"]     = { hunger = 1.3,  thirst = 1.3,  fatigue = 1.5  },  -- arcane addiction causes faster decay away from the Nightwell
    ["HighmountainTauren"] = { hunger = 1.15, thirst = 1.0, fatigue = 0.8 },
    ["MagharOrc"]      = { hunger = 0.85, thirst = 0.9,  fatigue = 0.85 },
    ["Vulpera"]        = { hunger = 1.1,  thirst = 0.8,  fatigue = 1.0  },  -- desert dwellers: conserve water
    ["ZandalariTroll"] = { hunger = 1.0,  thirst = 1.0,  fatigue = 0.9  },

    -- Alliance
    ["Human"]          = { hunger = 1.0,  thirst = 1.0,  fatigue = 1.0  }, -- baseline
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

}

-- ── Class modifiers ───────────────────────────────────────────────────────────
ICN2.CLASS_MODIFIERS = {
    ["WARRIOR"]     = { hunger = 1.15, thirst = 1.1,  fatigue = 1.1  },  -- heavy armor, constant exertion
    ["PALADIN"]     = { hunger = 1.0,  thirst = 1.0,  fatigue = 0.95 },  -- divine sustenance
    ["HUNTER"]      = { hunger = 0.9,  thirst = 0.95, fatigue = 0.9  },  -- used to the wild
    ["ROGUE"]       = { hunger = 1.0,  thirst = 1.0,  fatigue = 1.0  },
    ["PRIEST"]      = { hunger = 1.0,  thirst = 1.0,  fatigue = 0.85 },
    ["SHAMAN"]      = { hunger = 1.0,  thirst = 1.0,  fatigue = 1.0  },
    ["MAGE"]        = { hunger = 0.9,  thirst = 0.85, fatigue = 0.9  },  -- arcane knowledge helps conserve energy
    ["WARLOCK"]     = { hunger = 0.85, thirst = 1.0,  fatigue = 0.9  },  -- life tap sustains
    ["MONK"]        = { hunger = 0.9,  thirst = 0.9,  fatigue = 0.85 },  -- disciplined training and meditation
    ["DRUID"]       = { hunger = 0.9,  thirst = 0.95, fatigue = 0.9  },  -- used to the wild
    ["DEMONHUNTER"] = { hunger = 0.9,  thirst = 1.0,  fatigue = 0.9  },  -- soul feeding helps, but reckless playstyle increases needs
    ["DEATHKNIGHT"] = { hunger = 0.5,  thirst = 0.5,  fatigue = 0.5  },  -- undead, reduced needs
    ["EVOKER"]      = { hunger = 1.1,  thirst = 1.1,  fatigue = 1.1  },  -- draconic metabolism, but intense magic use can be draining
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
        hunger  = { "/burp", "/flex" },
        thirst  = { "/burp" },
        fatigue = { "/flex", "/smile" },
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
    PLATE  = 1.20, -- heaviest armor causes more fatigue
    MAIL   = 1.10, -- medium armor has a moderate effect
    LEATHER= 1.00, -- light armor has no additional fatigue
    CLOTH  = 0.90, -- cloth armor is comfortable and breathable. Default fallback.
}

-- ── Fatigue recovery rates (% per second) ────────────────────────────────────
-- Recovery only applies when NOT in combat and NOT mounted.
--
-- Tiers:
--   slow  — any single condition (sitting, campfire, eating/drinking)
--   fast  — rested area AND (campfire OR housing)
--
-- "rested area"  = IsResting() returns true (inn, city, garrison, etc.)
-- "campfire"     = player has a Cozy Fire / campfire aura (see CAMPFIRE_PATTERNS)
-- "eating/drink" = ICN2:IsEating() or ICN2:IsDrinking()
-- "housing"      = player is in their housing neighborhood or plot
--
-- These values are intentionally modest — fatigue is meant to be the
-- hardest need to recover, requiring deliberate downtime and helps with
-- taking IRL rest time on longer play sessions.
ICN2.FATIGUE_RECOVERY = {
    slow = 100 / 300,   -- 0.333% per second → full bar in ~5 minutes
    fast = 100 / 120,   -- 0.833% per second → full bar in ~2 minutes
}

-- ── Aura patterns for campfire / cozy fire detection ─────────────────────────
-- Matched against buff names on the player.
ICN2.CAMPFIRE_PATTERNS = {
    "cozy fire",
    "campfire",
    "warmth of the fire",
    "bonfire",
}

-- ── Housing zone detection ────────────────────────────────────────────────────
-- We primarily detect housing via the Cozy Fire aura; the map list below is
-- a fallback for when the buff hasn't applied yet.
-- Map IDs will need updating as Blizzard adds more housing zones.
ICN2.HOUSING_MAP_IDS = {
    [2736] = true,  -- Housing neighborhood (Razorwind Shores)
    [3027] = true,  -- Warband Housing neighborhood (Razorwind Shores)
    [2735] = true,   -- Housing neighborhood (Founders Point)
    [3026] = true  -- Warband Housing neighborhood (Founders Point)
}
