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
| `Saga` | `saga.gd` | Procedural story per universe seed: cast (ally, antagonist, lieutenant, personal thread), MacGuffin, 7 beats over 3 acts laid across random planets, twist from your Secret, 3 endings, per-planet side quests, journal. Templates in `data/saga.json`. |
| `ShipAI` | `ship_ai.gd` | QUACK commentary with cooldowns (`data/ai_lines.json`). |
| `Audio` | `audio_manager.gd` | Music/SFX by name; missing files are ignored. |
| `Router` | `scene_router.gd` | Scene changes with fade + params. |

## Stats
`StatBlock` = BASE + Σadd, × (1 + Σmul), grouped by source (`tag:`, `synergy:`, `perk:`, `flaw:`).
Every gameplay number that can be modified reads `Game.stat("name")`.

## Levels
`Level` (base) → builds `Environment` (glow, fog, ACES), sun with shadows, geometry via
`LevelBuilder` from an ASCII layout, bakes a navmesh from static colliders, spawns actors and the
HUD. `StationPrologue` uses a hand-written layout; `PlanetSurface` asks `WorldGen` for one and
applies anomaly effects (gravity, fog, ad ghosts, reverse rain, mutineers...).

`WorldGen` (`src/world/world_gen.gd`) = one algorithm per biome, random map size, then shared
passes (landing zone, services, population by controller/crisis, flood-fill connectivity fix):
- `neon_sprawl`: jittered avenue grid → building blocks, alleys, plazas, market blocks, sidewalk
  dressing (lamps, cars, signs, vents, benches, trash), crowds at intersections.
- `toxic_swamp`: noise waterways (`~`) with boardwalk crossings, huts, trees, mushrooms.
- `ad_desert`: plastic glacier ridges (`^`), shard fields, billboard towers (`Y`), dome town.
- `rust_canyon`: noise mesas (`^`), mining rigs, shacks. `crystal_moon`: crystal fields, glowing pools, domes.
Non-city biomes also grow a frontier settlement around the pad. `PlanetSurface._vary_palette()`
nudges hues/fog/sun/weather from the planet seed, so two planets of one biome never look alike.
Preview any map as text: `godot --headless --path . --script res://tools/print_world.gd -- <biome|all> <seed>`.

`Level.refresh_quests()` spawns whatever `Saga.spawns_for(planet)` asks for: persona NPCs with
quest markers, quest-item crates with guards, elite/boss enemies tagged with `saga_tag`.

## Presentation layer
- `BillboardSprite` - JSON-driven 8-direction sprite player (squash & stretch, flashes, afterimages).
  Sheets are **palette-indexed** (R = slot*16+8, G = band*40+20): `indexed_sprite.gdshader` looks up
  a 6x16 palette texture, so one rendered body/outfit variant can wear any colours.
- `CharacterLook` - a look is `{"variant": "h07", "colors": {slot: "#hex"}}`; `random_look(rng, style)`
  (hero/civilian/worker/punk/corporate:faction/cop:faction/heavy/robot/drone/bug), faction uniforms,
  hue-shifted 6-step ramps. Every NPC, enemy, crew member, saga persona and the player is a look.
  `LookPreview` (UI) draws one with `indexed_sprite_2d.gdshader` as an 8-way turntable.
- `FXSprite` / `FX` - pixel VFX, damage numbers, hitstop, slow-mo, camera shake/punch, rumble.
- `CameraRig` - follow + look-ahead + combat zoom; `hd2d_post.gdshader` lens (tilt-shift, vignette,
  chromatic aberration, grain, split toning) on a CanvasLayer under the HUD.
- `LevelBuilder` dressing - pipes/vents/lamps on walls, windows onto a nebula backdrop, light shafts,
  dust motes, reflection probe, outdoor horizon silhouettes, wind-swayed foliage (MultiMesh shader).
- `HUD.cinematic()` / `title_card()` / `await say()` - cutscene tools; `Critter` - ambient life.

## Physics layers
1 world · 2 player · 3 enemy · 4 npc · 5 projectile · 6 interact · 7 target_pick (tap-to-target areas) · 8 occluder (fade buildings)

## Adding things
- **New enemy**: add to `data/enemies.json` (subsystems + effects + `look` style), and a char in
  `Level.ENEMY_CHARS` / `WorldGen._population()`.
- **New character variant** (hair/outfit/body/accessory combo): add to `variant_list()` in
  `tools/sprite_forge.py`, run `python3 tools/sprite_forge.py <id>`; tag it so `random_look` picks it.
- **New story content**: `data/saga.json` (names, jobs, schemes, MacGuffins, beats, twists, endings, side jobs).
- **New biome**: environment entry in `data/planets.json` + a generator func in `WorldGen`.
- **New crime/verb**: add to `data/consequences.json`, then `Causality.record("verb", {...})`.
- **New encounter**: append to `data/encounters.json` (see `_doc` for the effect DSL).
- **New tag / perk / flaw / crew member**: JSON only.
