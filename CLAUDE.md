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
  horizons, water `~`, cliffs `^`, street props k q j g w i v o Y, facades, rooftop cables),
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

Commit the generated `*.uid` / `*.import` files; never commit `.godot/`.

## Gotchas learned the hard way (Godot 4.7)
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
- Godot's GUI focus + default `ui_*` actions give gamepad menu navigation; always `grab_focus()` the
  first button of every screen/modal. `Router.input_device` tracks touch/keyboard/gamepad for prompts.
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
