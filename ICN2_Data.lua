-- ============================================================
-- ICN2_Data.lua
-- Static tables: defaults, race/class modifiers, emotes
-- ============================================================

ICN2 = ICN2 or {}  -- Safely initialize the global ICN2 table to avoid overwriting existing data

-- ── Default SavedVariables structure ──────────────────────────────────────────
ICN2.DEFAULTS = {
    hunger  = 100.0,   -- stored in race-specific points (0–maxValue); Human baseline = 100
    thirst  = 100.0,
    fatigue = 100.0,
    lastLogout = nil,  -- timestamp via time()

    settings = {
        -- "fast" | "medium" | "slow" | "realistic" | "custom"
        preset = "medium",

        -- Only when preset == "custom". Integer 0..CUSTOM_DECAY_MULTIPLIER_MAX (see below).
        -- Value is passive decay multiplier vs Medium (1×). 0 = none; max = 10× Fast.
        customDecayBias = {
            hunger  = 1,
            thirst  = 1,
            fatigue = 1,
        },
        -- Bumped when customDecayBias scale changes; used for one-time migration from old saves.
        customDecayBiasVersion = 2,

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
-- Multipliers for decay rates: higher values mean faster decay (needs deplete quicker).
ICN2.PRESETS = {
    fast      = 3.0,
    medium    = 1.0,
    slow      = 0.5,
    realistic = 0.15,
    custom    = 1.0  -- user sets their own rates directly
}

-- Custom sliders: 0 = no passive decay; max = 10 × Fast (×3) = ×30 vs Medium base.
ICN2.CUSTOM_DECAY_MULTIPLIER_MAX = 10 * ICN2.PRESETS.fast

-- ── Situational decay multipliers ─────────────────────────────────────────────
-- These modify the decay rate based on the player's current activity.
-- Each situation applies its multipliers to hunger, thirst, and fatigue.
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
    ["Orc"]                 = { hunger = 0.95, thirst = 1.00, fatigue = 0.92 }, -- strong constitution, excellent endurance},
    ["Scourge"]             = { hunger = 0.60, thirst = 0.75, fatigue = 0.70 }, -- undead don't need food/water, but still get tired from body parts decaying
    ["Tauren"]              = { hunger = 1.08, thirst = 1.00, fatigue = 0.88 }, -- large body, great endurance: big appetite but slower fatigue
    ["Troll"]               = { hunger = 1.00, thirst = 1.08, fatigue = 1.00 }, -- regeneration balances tropical thirst, but active lifestyle causes more hunger and fatigue
    ["BloodElf"]            = { hunger = 1.00, thirst = 1.00, fatigue = 1.00 }, -- refined but unremarkable needs
    ["Goblin"]              = { hunger = 1.15, thirst = 1.15, fatigue = 1.12 }, -- hyperactive metabolism and high-stress lifestyle cause faster decay, but small frame means they burn through reserves quicker
    ["Nightborne"]          = { hunger = 1.22, thirst = 1.22, fatigue = 1.35 }, -- arcane realiance causes faster decay
    ["HighmountainTauren"]  = { hunger = 1.10, thirst = 1.00, fatigue = 0.85 }, -- mountain endurance, hearty appetite: slightly faster hunger, but slower fatigue
    ["MagharOrc"]           = { hunger = 0.90, thirst = 0.93, fatigue = 0.88 }, -- Draenor-hardened survivors: slower decay due to harsh upbringing
    ["Vulpera"]             = { hunger = 1.08, thirst = 0.60, fatigue = 1.02 }, -- Desert adaptation: amazing water conservation
    ["ZandalariTroll"]      = { hunger = 1.00, thirst = 1.00, fatigue = 0.93 }, -- Proud empire builders, balanced

    -- Alliance
    ["Human"]               = { hunger = 1.00, thirst = 1.00, fatigue = 1.00 }, -- baseline
    ["Dwarf"]               = { hunger = 1.05, thirst = 1.00, fatigue = 0.95 }, -- Hardy mountain folk: great stamina, moderate hunger
    ["NightElf"]            = { hunger = 0.90, thirst = 0.92, fatigue = 0.88 }, -- Efficient metabolism, excellent rest
    ["Gnome"]               = { hunger = 1.12, thirst = 1.12, fatigue = 1.10 }, -- Small frame = small reserves, fast burn
    ["Draenei"]             = { hunger = 0.88, thirst = 0.90, fatigue = 0.85 }, -- Light-sustained endurance
    ["Worgen"]              = { hunger = 1.15, thirst = 1.05, fatigue = 1.08 }, -- Cursed metabolism causes faster decay, but also more reserves
    ["VoidElf"]             = { hunger = 0.92, thirst = 0.93, fatigue = 0.90 }, -- Void-touched efficiency
    ["LightforgedDraenei"]  = { hunger = 0.85, thirst = 0.88, fatigue = 0.80 }, -- Light-sustained endurance, but relentless warriors
    ["DarkIronDwarf"]       = { hunger = 1.05, thirst = 1.02, fatigue = 0.93 }, -- Forge-hardened constitution, but still needs sustenance
    ["KulTiran"]            = { hunger = 1.03, thirst = 1.00, fatigue = 0.97 }, -- Seafaring resilience, but hard work takes its toll
    ["Mechagnome"]          = { hunger = 0.75, thirst = 0.70, fatigue = 0.78 }, -- cybernetic body requires less sustenance but still gets worn down

    -- Neutral
    ["Pandaren"]            = { hunger = 0.93, thirst = 0.93, fatigue = 0.88 }, -- Zen discipline, love of food balanced by efficiency
    ["Dracthyr"]            = { hunger = 0.85, thirst = 0.88, fatigue = 0.85 }, -- Draconic metabolism = efficient
    ["EarthenDwarf"]        = { hunger = 0.72, thirst = 0.68, fatigue = 0.75 }, -- Living stone: tiny reserves but slow drain
    ["Haranir"]             = { hunger = 1.05, thirst = 1.15, fatigue = 1.05 }, -- Forest spirits: hunger and thirst decay faster due to their active nature, but fatigue is moderate
}
-- ── Race max values (point pools) ─────────────────────────────────────────────
-- Defines how large each need's pool is per race. Larger pools mean the need takes longer to deplete in absolute game time
-- Human = 100/100/100 is the baseline. All other values are relative to that.
ICN2.RACE_MAX_VALUES = {
    -- Horde
    ["Orc"]                = { hunger = 108, thirst = 102, fatigue = 112 }, -- Strong constitution, excellent endurance
    ["Scourge"]            = { hunger = 50,  thirst = 50,  fatigue = 140 }, -- Undead: minimal food/water, decay causes fatigue
    ["Tauren"]             = { hunger = 125, thirst = 110, fatigue = 118 }, -- large body, great endurance
    ["Troll"]              = { hunger = 102, thirst = 108, fatigue = 100 }, -- Regeneration balances tropical thirst
    ["BloodElf"]           = { hunger = 92,  thirst = 95,  fatigue = 98  }, -- Refined but unremarkable needs 
    ["Goblin"]             = { hunger = 82,  thirst = 82,  fatigue = 88  }, -- Hyperactive metabolism, small reserves
    ["Nightborne"]         = { hunger = 85,  thirst = 85,  fatigue = 78  }, -- arcane realiance causes smaller pools
    ["HighmountainTauren"] = { hunger = 120, thirst = 108, fatigue = 122 }, -- Mountain endurance, hearty appetite
    ["MagharOrc"]          = { hunger = 112, thirst = 105, fatigue = 115 }, -- Draenor-hardened survivors
    ["Vulpera"]            = { hunger = 85,  thirst = 75,  fatigue = 95  }, -- desert-adapted: small but efficient
    ["ZandalariTroll"]     = { hunger = 105, thirst = 105, fatigue = 108 }, -- Proud empire builders, balanced
    -- Alliance
    ["Human"]              = { hunger = 100, thirst = 100, fatigue = 100 }, -- baseline
    ["Dwarf"]              = { hunger = 110, thirst = 105, fatigue = 115 }, -- hearty constitution, but still gets tired from mining and drinking
    ["NightElf"]           = { hunger = 95,  thirst = 95,  fatigue = 110 }, -- efficient metabolism, but need more rest
    ["Gnome"]              = { hunger = 80,  thirst = 80,  fatigue = 85  }, -- small frame, small pools
    ["Draenei"]            = { hunger = 105, thirst = 100, fatigue = 110 }, -- Light-sustained endurance
    ["Worgen"]             = { hunger = 110, thirst = 100, fatigue = 105 }, -- Large appetite, decent reserves
    ["VoidElf"]            = { hunger = 92,  thirst = 95,  fatigue = 100 }, -- Void-touched efficiency
    ["LightforgedDraenei"] = { hunger = 95,  thirst = 92,  fatigue = 115 }, -- Light sustains them heavily
    ["DarkIronDwarf"]      = { hunger = 108, thirst = 102, fatigue = 110 }, -- Forge-hardened constitution
    ["KulTiran"]           = { hunger = 115, thirst = 105, fatigue = 108 }, -- Hearty sailors with reserves
    ["Mechagnome"]         = { hunger = 65,  thirst = 60,  fatigue = 85  }, -- Cybernetic efficiency, tiny reserves
    -- Neutral/Other
    ["Pandaren"]           = { hunger = 105, thirst = 100, fatigue = 105 }, -- Zen discipline, love of food balanced by efficiency
    ["Dracthyr"]           = { hunger = 98,  thirst = 95,  fatigue = 100 }, -- Draconic metabolism = efficient
    ["EarthenDwarf"]       = { hunger = 75,  thirst = 70,  fatigue = 90  }, -- Living stone: tiny reserves but slow drain
    ["Haranir"]            = { hunger = 95,  thirst = 95,  fatigue = 110 }, -- Forest spirits: moderate pools, but need more rest
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
-- Tables of emote commands triggered when needs reach certain thresholds or are satisfied.
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
-- Thresholds are always percentages (0–100) regardless of point pool size.
ICN2.THRESHOLDS = {
    critical = 15,
    low      = 35,
    ok       = 100,
}


-- ── Need helpers ──────────────────────────────────────────────────────────────
-- Returns the max point value for a need given the player's race.
-- Falls back to 100 for any race not in RACE_MAX_VALUES.
function ICN2:GetMaxValue(need)
    local race = select(2, UnitRace and UnitRace("player") or "Human", "")
    local raceMax = ICN2.RACE_MAX_VALUES[race]
    if raceMax and raceMax[need] then return raceMax[need] end
    return 100
end

-- Returns the current need as a 0–100 percentage (used by HUD, emotes, thresholds).
function ICN2:GetNeedPercent(need)
    local current = ICN2DB and ICN2DB[need] or 0
    local maxVal  = ICN2:GetMaxValue(need)
    return (current / maxVal) * 100
end

-- ── Self-modifier curves (Phase 2 — non-linear decay) ─────────────────────────
-- When a need is already low, its decay accelerates — creating urgency without
-- punishing the player at normal levels.
--
-- Breakpoints (percentages):
--   above low_threshold  → multiplier = 1.0  (no change)
--   low to critical      → low_mult           (mild acceleration)
--   at/below critical    → crit_mult          (strong acceleration)
--
-- Only applies to decay (negative rates). Recovery is never scaled here.
ICN2.SELF_MODIFIER_CURVES = {
    hunger = {
        low_threshold  = 35,   -- matches ICN2.THRESHOLDS.low
        crit_threshold = 15,   -- matches ICN2.THRESHOLDS.critical
        low_mult       = 1.10, -- 25% faster between low and critical
        crit_mult      = 1.20, -- 60% faster at critical (starving panic)
    },
    thirst = {
        low_threshold  = 35,
        crit_threshold = 15,
        low_mult       = 1.15, -- thirst accelerates slightly more than hunger
        crit_mult      = 1.30, -- dehydration is acutely urgent
    },
    fatigue = {
        low_threshold  = 35,
        crit_threshold = 15,
        low_mult       = 1.20,
        crit_mult      = 1.40,
    },
}

-- ── Cross-need rules (Phase 2 — inter-need coupling) ──────────────────────────
-- One need's low level can accelerate another need's decay rate.
-- Rules only influence delta calculations — never direct value writes.
-- Kept to a small number to stay debuggable.
--
-- If multiple rules match the same source→target pair, the last matching rule
-- wins (most severe threshold takes effect).
--
-- label is shown in /icn2 details when the rule is active.
ICN2.CROSS_NEED_RULES = {
    {
        source    = "hunger",
        target    = "fatigue",
        threshold = 35,    -- activates below 35% hunger
        mult      = 1.15,
        label     = "hungry→fatigue×1.15",
    },
    {
        source    = "hunger",
        target    = "fatigue",
        threshold = 15,    -- stronger effect below 15% (overrides above)
        mult      = 1.35,
        label     = "starving→fatigue×1.35",
    },
}

-- ── Housing zone detection ────────────────────────────────────────────────────
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
    slow = 100 / 600,   -- 0.333% per second → full bar in ~10 minutes
    fast = 100 / 300,   -- 0.833% per second → full bar in ~5 minutes
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
