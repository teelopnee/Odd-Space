# ODD-SPACE — notes for AI coding sessions

Sci-fi HD-2D action-RPG (Octopath-style visuals, original retro-80s dark-satire setting) in
**Godot 4.7, GDScript, Mobile renderer**. The owner develops on a **Samsung Galaxy Tab S12 Ultra**
with the Godot Android editor and syncs through GitHub (`main`), so:

- Commit + push finished work to `main` regularly (the owner explicitly wants this for cross-device work).
  Always `git pull --rebase origin main` first — the tablet pushes too.
- Talk to the owner in **Thai**; in-game text, code and comments are **English**.
- Keep everything editable on a tablet: prefer data in `data/*.json`, ASCII level layouts, and
  small scripts over giant scenes. Touch controls must keep working (`src/ui/hud.gd`).
- Original IP only: never copy Octopath Traveler (or any game's) characters, art, music, names.

## Layout
- `src/autoload/` singletons (order matters, see `project.godot`): `EventBus`, `DataDB`, `Game`,
  `Factions`, `Causality`, `Origin`, `Crew`, `FlawPerk`, `Encounters`, `Saga`, `Stories`, `Interactions`, `ShipAI`, `Audio`, `Router`.
  `Origin` = 6 tag categories (class incl. 5 Consortium heirs .. beggar, age + exact years, background, personality,
  motivation, secret; `data/tags.json`). `Saga` = branching procedural main story (`data/saga.json`: approaches per beat,
  surrender choices, twist, 15+ finales, composed endings, early motivation endings). `Stories` = per-planet local arcs
  + street events (`data/stories.json`). `Interactions` = character-dependent verbs on NPCs (`data/interactions.json`).
  Story/interaction choices share one requirement grammar (flag/any_flag/tag/age/min_wealth/... see the `_doc` keys).
  Systems communicate via `EventBus` signals. Persistent systems implement `reset()/to_save()/from_save()`
  and are registered in `Game._systems()` + `Game.save_game()/load_game()`.
- `src/actors/` Player / Enemy (data-driven subsystems) / NPC (witness, dialogue) / Projectile.
- `src/world/` `LevelBuilder` (ASCII → 3D: normal-mapped kit, wall dressing, windows, shafts, foliage,
  horizons, water `~`, cliffs `^`, street props k q j g w i v o Y, facades, low lantern cables, landing-bay paint),
  `WorldGen` (per-biome dense map generators + connectivity fix; preview with `tools/print_world.gd`),
  `Level` base (lighting/bloom, weather, navmesh bake, spawning, HUD, `refresh_quests()` for Saga),
  `station_prologue.gd` (intro cutscene), `planet_surface.gd` (WorldGen + per-seed palette variation +
  landing sequence), `CameraRig` (HD-2D lens post shader, punch/shake/look-ahead, occluder fade),
  `Critter` (ambient life: bot, drone, flyby, sky-traffic car, street traffic that brakes for people),
  `Hologram` (giant additive character ads, `holo_sprite.gdshader`), `Flicker` (failing neon).
  Outdoor builds also add road paint/crosswalks/manholes, litter + stains (MultiMesh), wet-street neon
  reflections (`_glow_spots`), neon facade tubes, low lantern cables, biome extras (mist, lily pads, dust devils),
  shop-front venues (`data/venues.json` via `Interactions.open_venue`), wanted posters and news billboards.
- NPC life: `life_spot` markers (bench seats, stall queues, hologram dance floors) -> `NPC._pick_activity`
  (sit / phone / queue / dance), waving at friends, cheering on `story_event`; reactive barks (`data/barks.json`).
- `src/core/character_look.gd` random looks (variant + palette colours); sprites are palette-indexed.
- `src/core/copy.gd` procedural copywriter over `data/copy.json` (Tracery-style `#symbol#` grammar): billboards,
  hologram slogans, shop/stall/street names, HUD news ticker, wall flyers + graffiti, menus, PA announcements,
  NPC small talk + replies, NPC/robot/merchant names, drone pitches, venue greetings (`<venue>_scene/_keeper`).
  Preview: `tools/print_copy.gd -- [symbol] [count]`. Add variety by adding alternatives there.
  Grammar also works inside `barks.json`, `venues.json` greet lines and `interactions.json` lines (`Interactions.fill`).
  Modifiers: `.cap` `.upper` `.lower` `.a`; vars `{planet}`/`{PLANET}`, `{player}`, barks also `{name}`.
- Barks: `pair` lines `"A -- B -- C"` alternate between two NPCs (`NPC._converse`); enemies talk via
  `Enemy.bark()` from `<taunt|hurt|yield|standdown>:<enemy_type>` keys (throttled across the fight).
- NPC eyes & memory + voices: `src/core/npc_voice.gd` (`NPCVoice`). Acts in an NPC's line of sight (`NPC.witness_act`,
  fed by `interaction_done`, `action_recorded`, `enemy_killed`, `perfect_dodge`, `player_parried`, `EventBus.player_act`
  for dance/hurt) map to an act KIND and a STANCE per NPC voice (`data/reactions.json`), shift attitude, are remembered
  (`NPC.memories`) and gossiped planet-wide (`Game.flags["street_<planet>"]`, saved). Talking opens with a memory, gossip
  or a remark about who you are (`pc_class_/pc_age_/pc_bg_/pc_pers_/pc_goal_/pc_secret_<tag>`, wounds, money, bounty,
  fame, crew, saga, planet) voiced by mood (`open_<mood>`) + voice (`close_<voice>`) + the NPC's own `tic`. Grammar:
  `data/copy_people.json`, `data/copy_reactions.json` (merged into Copy). Memory-driven verbs use the requirement keys
  `npc_saw` / `npc_heard` / `npc_mood` and effects `forget`, `street_rep`. Test: `tools/voice_test.gd -- <class> <age> <bg>`;
  size of the line space: `python3 tools/count_copy.py`.
- Impact layer (NPC "Impact" section + `Interactions.resolve`): every verb result ends with a `>` block saying what changed
  (relationship before -> after, call cut / sped up, who saw it and how they took it, who is still calling Paragon).
  `relation_label()` tags over heads (FRIENDLY, OWES YOU ONE, DEVOTED, DISLIKES YOU, FURIOUS, SCARED OF YOU, REPOSSESSED,
  KEEPS QUIET) change behaviour: favours come back as gifts, grudges become `complaint` reports (stoppable calls),
  scared NPCs back off, furious ones heckle, attitude >= 45 or loyal = they won't report you, attitude scales call speed.
  Verb effect `"react": grateful|scared|bow|leave|repossessed|grudge|smitten` triggers these. New strangers on a planet
  start biased by its street memory (`NPCVoice.street_bias/street_feared`). Only `Causality.PHONE_VERBS` get phoned in;
  other witnessed acts become public at once. `WitnessComponent.can_see` (memory) vs `can_witness` (will report).
  A silenced witness MUST go back to normal life (`on_report_finished`) - it used to stay "reporting" forever.
  Test: `tools/impact_test.gd` (exit code = failures).
- NPCs always answer back: after every verb `Interactions.present_counter` shows a counter-move from `data/counters.json`
  (`counters.<kind>_<ok|fail>`, `served` after the family lawyer) with choices (reply / effects / chance / cost / verb).
  Outcomes with no `react` get `reactions.json` `default_react[kind]` (talk->warm/cold, charity->grateful, threat->scared/grudge,
  theft->robbed (they notice later and may accuse you), show->fan/heckler, beg->pity, deal->partner, weird->intrigued/spooked).
  NPCs also come to YOU (`NPC._schedule_approach` -> state "approach" -> `counters.approach.<kind>`: thanks, pity, partner,
  fan, confront (before a grudge becomes a complaint), smitten); "follow" state for crushes / curious people. One approach
  per 25 s, never in combat or over an open dialogue. `Interactions.force_outcome` forces rolls for tests.
  Test: `tools/interact_back_test.gd` (every verb x outcome answers back + changes something; every counter choice played).
- Shop owners: `LevelBuilder.venue_spots` (venue doors) -> `Level.spawn_keeper` puts an NPC with role "keeper" beside every
  door (stands at `post_pos`, skips physics while idle; Talk disabled - the door is the way in, except mid-call). Same person
  every visit: state saved in `Game.flags["keepers_<planet>"][<venue>|<sign>]` (`persist_keeper` on change + `_exit_tree`;
  `{"dead": true}` -> the shop stays dark with its own scene). `Interactions.open_venue(..., door)` greets by memory /
  mood / regular / fan / partner, shows personal prices (`price_mult`: attitude, regular, fear), adds 3 owner verbs, turns
  away banned customers (`counters.venue.keeper_banned`). Every shop option maps to an act kind
  (`reactions.json venue_option_kind`) -> `_keeper_reacts`: mood + reaction (`reactions.json keeper`: regular, grateful,
  banned, robbed, fan, heckler, scared, grudge...) + afterword + counter `counters.venue.keeper_<kind>_<ok|fail>` (falls back
  to the person counters). Test: `tools/keeper_test.gd` (all 14 shop types x outcomes, bans, death, return visit).
- Combat pacing: `Enemy._take_token()` = attack tokens (max 2 attackers, 1 shooter at a time; saga bosses exempt);
  ranged foes kite rarely + slowly and stand still 0.9 s after each burst ("recover"); enemy bolts x0.78 speed;
  allies join within 8 m with a staggered delay; `WorldGen._scatter_enemy` spreads foes as patrols of 1-2 (swarms of 3).
  Player `DASH` state: MELEE with a hostile 3-9 m away dashes in (i-frames) and starts the combo on arrival.
- Enemies (`data/enemies.json`, map chars in `LevelBuilder` legend): G officer, E repo drone, B grub, H debt brute,
  R pirate, U riot unit (`guard`: blocks frontal shots/melee; flank, parry, charge, explode, katana or harpoon it),
  F gutter punk (`flank`), Q ad-bomb bot (`explode`, chain reactions), J ad-swarm drone (threes), Z vat golem (`slam`).
  `drops: {item: chance}`, `scale`, barks `<kind>:<type>`.
- Weapons: `src/core/arsenal.gd` + `data/weapons.json` (BLADE: pipe, baton, chain, katana, hammer; GUN: sidearm,
  scatter, arc, harpoon, grenade). Owned/equipped in `Game.flags.weapons/equip`; `weapon_<id>` items unlock on pickup
  (`Game.add_item`), sold by street traders / pawn / corp stores, dropped by enemies, start kit by background.
  Swap: `swap_melee` (1 / L3 / BLADE) and `swap_ranged` (2 / R3 / GUN). `Grenade` node, Projectile `pull/stun/push_force`.
  Test: `tools/combat_test.gd` (every enemy, tokens, every weapon, dash, riot guard, boom chain, unlocks).
- Player-facing polish: `src/core/tips.gd` + `data/tips.json` (one-time just-in-time tips, banner in HUD, seen list in
  device settings); `Interactions.should_counter` (big moments always, else Settings "followups"); `_impact_block` caps
  at 3 lines; HUD `_update_context_buttons` (touch buttons only when useful); Settings: difficulty (`Enemy.dmg_mult`,
  token limits), graphics (`Level.apply_quality/quality_mult`), ui_scale (root content_scale_factor), tips, followups.
  `Router._notification`: Android Back = close/open menu, app pause/focus-out = pause menu + autosave.
  Title "CREDITS & LICENSES" (Godot + third-party licence texts - required for distribution). PC: Windows/Linux presets,
  mouse (LMB melee, RMB fire; touch-emulated mouse ignored), F11 fullscreen. Critique log: `docs/REVIEW.md` - update it
  every pass (score, open issues, fix log).
- Authored act bookends: `data/bookends.json` -> `Saga.play_bookend(open|close, act)` (once per life, flag
  `bookend_<kind>_<act>`): openings by motivation + wealth band, closings by `Saga.dominant_axis()` + crew. Act numbers in
  saga beats are floats ("1.0") - normalise with int(). Authored meetings `bookends.json meet.<scene>` ->
  `Saga.play_meet` (flag `meet_<scene>`): ally on first contact, lieutenant + antagonist face-off when the elite first
  enters "chase" (`Enemy._set_state` -> `Saga.on_boss_sighted`), the antagonist's call on reaching the MacGuffin beat;
  parts picked by personality / persona trait / wealth band or `feud` / lieutenant_fate / ally_fate / axis.
  `idle.<role>.<beat>` = saga people talked to outside their beat (points you at the next goal).
  `Saga.fill`: `{faction}` = display name (world.faction is the id). Legacy titles are scored (`legacy_strength`),
  not first-match. Test: `tools/story_test.gd`.
- `src/core/first_day.gd`: 4-step onboarding checklist for a new life (talk / shop / fight / change), shown as the first
  objective line; steps fire from NPC talk, open_venue, enemy kills, relation changes. UI review shots: `tools/ui_review.gd`.
- `src/ui/` HUD (code-built), touch controls, pause menu, title, character creation, star map.
- `docs/ARCHITECTURE.md` explains the systems; `docs/GDD.md` the design.

## Validate before every push
Download Godot once (Linux x86_64) into your scratchpad:
`https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`
```bash
godot --headless --path . --import                                  # (re)generate .godot cache, *.uid, *.import
godot --headless --path . --script res://tools/check_project.gd     # compiles all scripts + scenes, exit code = failures
godot --headless --path . --script res://tools/smoke_test.gd        # station -> ship -> planets -> saga -> 6 random lives to endings
```
`grep "SCRIPT ERROR"` on the smoke-test output must be empty. `tools/count_endings.gd` prints the ending space;
`tools/print_world.gd -- <biome|all> <seed>` prints generated maps.
Screenshots (software Vulkan): `apt-get install mesa-vulkan-drivers xvfb`, then
`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x800x24" godot --path . --resolution 1280x800 --script res://tools/capture_screens.gd -- <out_dir>`
(options: `--quick`, `--biome=<env>`, `--street` = also walk to the nearest shop front, `--creator`; ~10 min per biome on lavapipe).
`--street --probe` also works with `--headless` (no images): prints the ASCII map around the hero plus every mesh/collider
on the camera sight line - the fastest way to find out what is blocking or darkening a shot.

Commit the generated `*.uid` / `*.import` files; never commit `.godot/`.

## Gotchas learned the hard way (Godot 4.7)
- Outdoor camera (pitch 30, fov 32, distance 16) only sees ground ~8-32 m ahead and things below ~5 m:
  sky, rooftop props and anything taller never appear in frame. Put "wow" at street level; keep holograms ~2.4-3x.
- Thin particles (rain < ~0.05 m wide) turn into screen noise; prefer fewer, larger streaks.
- Outdoor low walls (southern map rim, river banks) are built as `_street_edge` (pale kerb + slim barrier/rail): the camera
  looks down on their 2 m-deep top face, which read as a black band in front of the hero when it was a dark wall box.
- Occluder cut-away (`CameraRig._update_occluders`) sweeps a 5 m box along the sight line (layer 128), so a whole
  row of buildings across a narrow street fades together; a single ray left a dark band over the hero.
- Never run `--import` while `tools/sprite_forge.py` is still writing sheets: a half-written PNG gets imported as
  `valid=false`. Fix: delete that `.png.import` and re-import.
- `VirtualJoystick` is a **native class** in 4.7 → ours is `TouchStick`. Check `ClassDB.class_exists()` before naming classes.
- No `match` inside a multi-line lambda passed as a call argument (parser error). Use a named method.
- `var x := <Variant expression>` fails ("cannot infer type") → write `var x: bool = ...`.
- `%g` is not a GDScript format specifier.
- Controls created at runtime inside the tree: use `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`,
  not `set_anchors_preset` (that keeps the old zero-size rect).
- Don't pass `--rendering-driver vulkan` on the CLI: it silently switches the renderer to Forward+.
- `tools/*.gd` run with `--script`: autoloads only exist from the first `_process` frame, and
  referencing game `class_name`s at compile time poisons the script cache — compare by `get_global_name()`.
- Depth-based DOF (`CameraAttributesPractical`) blurred everything on lavapipe; default is the
  screen-space HD-2D lens (`assets/shaders/hd2d_post.gdshader`, tilt-shift etc.), selectable in Settings.
- Mobile renderer: max 8 omni lights per mesh → floors are built in 6x6-tile chunks.
- Particle quads with billboard materials ignore particle scale unless `billboard_keep_scale = true`.
- Godot's GUI focus + `ui_*` actions give gamepad menu navigation; always `grab_focus()` the first button of
  every screen/modal. BUT Godot 4.7's built-in `ui_accept`/`ui_cancel` have NO joypad buttons (and a joypad
  event added to `ui_accept` in project.godot is dropped on load) -> `Router.ensure_gamepad_ui()` binds
  A = confirm, B = back at runtime. Verify with `tools/pad_test.gd` (sends real joypad events headless).
  `Router.input_device` tracks touch/keyboard/gamepad for prompts.
- HUD dialogue pauses the tree; cutscenes use `await hud.say(...)` (SceneTreeTimers keep running).

## Art pipeline (all original, generated by code; replaceable 1:1 by hand-made art)
- `python3 tools/sprite_forge.py [variant...] [--preview]` - chibi characters: 3D SDF rig ->
  ray-marched **palette-indexed** pixel art (R = slot*16+8, G = band*40+20; 16 slots x 6 bands),
  sel-out outlines, eye decals. 64x64 frames, 19 anims (incl. sit, phone, dance, cheer, wave, surrender) x 5 directions (S, SE, E, NE, N; W mirrored
  in-engine) -> `<variant>.png/.json` + `variants.json`. Variants h00-h33 (humans), r00/r01 (robots),
  drone, drone_quad, grub; ~60 min for all on 4 cores. Colours are applied at runtime by
  `indexed_sprite.gdshader` from `CharacterLook` palettes - never bake colours into sheets.
- `python3 tools/gen_textures.py` - 64px pixel textures + normal maps (`*_n.png`, incl. asphalt, planks),
  space backdrop, horizon silhouettes, foliage atlas, light-shaft gradient.
- `python3 tools/gen_fx.py` - pixel VFX sheets (slashes, sparks, explosion, dust, break, telegraph) + fx.json.
- `python3 tools/gen_audio.py` - SFX, synthwave + Karplus-Strong music (one track per biome), ambience loops, thunder.
- Texture import defaults are lossless (pixel art!); `assets/textures/*.import` have mipmaps on.

## Android APK
- `export_presets.cfg` preset "Android" (arm64, Mobile renderer). Needs export templates + Android SDK
  build-tools + JDK; set `export/android/android_sdk_path` / `java_sdk_path` in the editor settings.
- Release signing via env: `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER(oddspace)/_PASSWORD`.
  The keystore is NOT in the repo (public). CI (`.github/workflows/android.yml`) reads it from the
  secrets `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` (the owner must add them; writing
  secrets from an agent session is blocked). APKs signed with a different key can't update in place.
- Publish: `gh release create vX.Y.Z build/odd-space.apk ...` (build/ is git-ignored).
