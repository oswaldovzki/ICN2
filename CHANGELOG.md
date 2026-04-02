# v1.7.1
## WA-1 Refactor race modifiers and max pools
- Update and normalize ICN2.RACE_MODIFIERS values and comments, adjusting hunger/thirst/fatigue modifiers for many races for better balance.
- Introduce a consolidated ICN2.RACE_MAX_VALUES table (moved earlier) with per-race point pools and added neutral/other races (Pandaren, Dracthyr, EarthenDwarf, Haranir).
- Remove the old duplicate RACE_MAX_VALUES block at the end and clean up explanatory comments.
- TOC update to 1.7.1.

# v1.8.0
## WA-1 Switch needs to fixed-point values; add localization
- Convert hunger/thirst/fatigue recovery and bonuses from percentage-based to fixed-point values so all races gain the same absolute points.
- Update food/drink trickle, feast behavior, manual Eat/Drink/Rest defaults, and fatigue recovery logic/comments to use points/sec semantics.
- Improve item detection for food/drink (use container item IDs and class/subclass filtering + tooltip API) and adjust completion bonus math/printouts accordingly.
- Add ICN2_Localization.lua (English + ptBR), laying the ground for future languages support.
- Also fix race name typo (Harronir) and simplify race lookup in GetMaxValue.
- TOC update to 1.8.0.

# v1.8.1
## Track Well Fed eligibility to prevent reapply
- Add a wellFedEligible saved flag and eating-linked eligibility logic to prevent the Well Fed hunger-pause from reapplying across UI reloads/portals.
- ICN2_Data.lua: introduce defaults.wellFedEligible. ICN2_FoodDrink.lua: document the rework, persist wellFedEligible in ICN2DB, set it true when eating starts, and consume it when the Well Fed pause is applied (checked alongside auraInstanceID).
- Also minor comment and formatting tweaks.
- TOC update to 1.8.1.
