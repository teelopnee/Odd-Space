# Architecture

```
            ┌──────────── data/*.json (design: tags, factions, planets, encounters, crew, enemies...)
            │                         │ DataDB
            ▼                         ▼
 Player / Enemy / NPC / Props ──► Causality.record(verb, {position, target_faction, causes...})
            │                         │
            │      witnesses in range + line of sight ──► WitnessComponent (radio call, progress bar)
            │                         │                        │ finished      │ killed / bribed / threatened
            │                         ▼                        ▼               ▼
            │                 node.status: secret | pending → reported   |  suppressed
            │                         │ reported
            │                         ▼
            │         consequences.json → Factions.change_rep / add_bounty, Lumen headline (news ticker)
            │                         │
            ▼                         ▼
        EventBus  ◄──── every system emits/listens here ────►  HUD, ShipAI (QUACK), Crew (Morality),
                                                              FlawPerk (mishaps), Audio
```

## Autoloads (load order)
| Name | File | Role |
|---|---|---|
| `EventBus` | `event_bus.gd` | Global signals only. |
| `DataDB` | `data_db.gd` | Loads `data/*.json`. |
| `Game` | `game_state.gd` | Run state (credits, items, hp, flags, galaxy, location), StatBlock, air billing, save/load, device settings. |
| `Factions` | `faction_manager.gd` | Rep -100..100 with rival/ally spillover, bounties, price multipliers, hostility. |
| `Causality` | `causality_graph.gd` | The memory of the world: action nodes, witness lifecycle, consequences, queries (`known_crimes_at`, `chain_to`, headlines). |
| `Origin` | `origin_system.gd` | Tag engine: applies tags/synergies at new game, NPC reaction modifiers, origin story. |
| `Crew` | `crew_manager.gd` | Morality engine: approval = dot(action moral vector, member values); betrayals on warp. |
| `FlawPerk` | `flaw_perk_system.gd` | Mishap counters → flaw offers (+skill points); perk shop. |
| `Encounters` | `encounter_director.gd` | Weighted warp encounters, choice chances, effect DSL. |
| `ShipAI` | `ship_ai.gd` | QUACK commentary with cooldowns (`data/ai_lines.json`). |
| `Audio` | `audio_manager.gd` | Music/SFX by name; missing files are ignored. |
| `Router` | `scene_router.gd` | Scene changes with fade + params. |

## Stats
`StatBlock` = BASE + Σadd, × (1 + Σmul), grouped by source (`tag:`, `synergy:`, `perk:`, `flaw:`).
Every gameplay number that can be modified reads `Game.stat("name")`.

## Levels
`Level` (base) → builds `Environment` (glow, fog, ACES), sun with shadows, geometry via
`LevelBuilder` from an ASCII layout, bakes a navmesh from static colliders, spawns actors and the
HUD. `StationPrologue` uses a hand-written layout; `PlanetSurface` generates one from the planet's
4 layers and applies anomaly effects (gravity, fog, ad ghosts, reverse rain, mutineers...).

## Physics layers
1 world · 2 player · 3 enemy · 4 npc · 5 projectile · 6 interact · 7 target_pick (tap-to-target areas) · 8 occluder (fade buildings)

## Adding things
- **New enemy**: add to `data/enemies.json` (subsystems + effects), a sprite sheet, and a char in
  `Level.ENEMY_CHARS` / `PlanetSurface.CONTROLLER_ENEMIES`.
- **New crime/verb**: add to `data/consequences.json`, then `Causality.record("verb", {...})`.
- **New encounter**: append to `data/encounters.json` (see `_doc` for the effect DSL).
- **New tag / perk / flaw / crew member**: JSON only.
