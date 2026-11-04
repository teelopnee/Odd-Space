class_name Level
extends Node3D
## Base class for every playable 3D area. Subclasses provide:
##   _setup()          -> set palette / owner_faction / music / seed
##   _get_layout()     -> Array of ASCII rows (see LevelBuilder)
##   _is_outdoor()     -> bool
##   _post_build()     -> anything extra (anomalies, scripted events)
## The base builds lighting + post-processing (bloom, fog, DOF), the geometry,
## a baked navmesh, the player, actors, the camera rig and the HUD.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const ENEMY_SCENE := preload("res://scenes/actors/enemy.tscn")
const NPC_SCENE := preload("res://scenes/actors/npc.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")

const ENEMY_CHARS := {"E": "repo_drone", "G": "paragon_officer", "B": "gristle_grub", "H": "debt_brute", "R": "pirate"}
const CIVILIAN_NAMES := ["Marla", "Dex", "Old Ivo", "Juno", "Tam", "Priya", "Bex", "Otto", "Sunny", "Kaz", "Wen", "Lula", "Rico", "Nan"]
const CIVILIAN_SPRITES := ["civilian_a", "civilian_b", "civilian_c"]

var palette: Dictionary = {}
var owner_faction := ""
var music := "derelict_ambient"
var level_seed := 1
var spawn_key := "default"
var gravity_scale := 1.0
var enemy_speed_mult := 1.0

var nav_region: NavigationRegion3D
var actors: Node3D
var player: Player
var camera_rig: CameraRig
var hud: Node
var world_env: WorldEnvironment
var environment: Environment
var sun: DirectionalLight3D
var build: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _dying := false


func _ready() -> void:
	add_to_group("level")
	_setup()
	rng.seed = level_seed
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "World"
	add_child(nav_region)
	var builder := LevelBuilder.new(nav_region, palette, level_seed, _is_outdoor(), owner_faction)
	build = builder.build(_get_layout())
	actors = Node3D.new()
	actors.name = "Actors"
	add_child(actors)
	_spawn_player()
	_spawn_entities()
	_spawn_camera_and_hud()
	_post_build()
	_bake_navigation()
	Game.air_billing_active = true
	Audio.play_music(music)
	EventBus.player_died.connect(_on_player_died)


func _exit_tree() -> void:
	Game.air_billing_active = false


# --- Virtuals ----------------------------------------------------------------------------

func _setup() -> void:
	pass


func _get_layout() -> Array:
	return []


func _is_outdoor() -> bool:
	return false


func _post_build() -> void:
	pass


# --- Environment / post-processing ---------------------------------------------------------

func pcolor(key: String, fallback: String) -> Color:
	return Color.from_string(str(palette.get(key, fallback)), Color.GRAY)


func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = pcolor("bg", "#0b0420")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = pcolor("ambient", "#4a3a80")
	environment.ambient_light_energy = float(palette.get("ambient_energy", 0.7))
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	# Neon bloom.
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_strength = 1.05
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 0.85
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.set_glow_level(0, 0.0)
	environment.set_glow_level(1, 0.6)
	environment.set_glow_level(2, 1.0)
	environment.set_glow_level(3, 0.8)
	environment.set_glow_level(4, 0.5)
	# Atmospheric depth fog.
	environment.fog_enabled = true
	environment.fog_light_color = pcolor("fog", "#3a1060")
	environment.fog_light_energy = 1.0
	environment.fog_density = float(palette.get("fog_density", 0.012))
	environment.fog_sky_affect = 0.0
	# Retro colour punch.
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.18
	environment.adjustment_contrast = 1.06
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = pcolor("sun", "#9a7dff")
	sun.light_energy = float(palette.get("sun_energy", 0.4))
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# Light comes from the camera side & above-left so billboards are lit and
	# throw long diagonal shadows away from the viewer.
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	add_child(sun)


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	# Multiples of cell size/height to avoid voxel rounding warnings.
	nm.agent_radius = 0.5
	nm.agent_height = 1.5
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(true)


# --- Spawning ---------------------------------------------------------------------------

func get_spawn_position() -> Vector3:
	var spawns: Dictionary = build.get("spawns", {})
	if spawns.has(spawn_key):
		return spawns[spawn_key]
	if spawns.has("default"):
		return spawns["default"]
	if not spawns.is_empty():
		return spawns.values()[0]
	return Vector3(4, 0, 4)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.gravity_scale = gravity_scale
	actors.add_child(player)
	player.global_position = get_spawn_position() + Vector3(0, 0.1, 0.9)


func _spawn_entities() -> void:
	for e in build.get("entities", []):
		var c: String = e["char"]
		var pos: Vector3 = e["pos"]
		if ENEMY_CHARS.has(c):
			spawn_enemy(ENEMY_CHARS[c], pos)
		elif c == "N":
			spawn_npc("civilian", pos)
		elif c == "M":
			spawn_npc("merchant", pos)
		elif c == "W":
			var id := Crew.random_recruit_id()
			if id != "" and not Crew.is_full():
				spawn_npc("recruit", pos, id)
			else:
				spawn_npc("civilian", pos)


func spawn_enemy(type_id: String, pos: Vector3, extra: Dictionary = {}) -> Enemy:
	var e: Enemy = ENEMY_SCENE.instantiate()
	e.enemy_type = type_id
	e.display_name_override = extra.get("name", "")
	e.sprite_override = extra.get("sprite", "")
	e.force_hostile = extra.get("hostile", false)
	e.gravity_scale = gravity_scale
	e.world_speed_mult = enemy_speed_mult
	actors.add_child(e)
	e.global_position = pos + Vector3(rng.randf_range(-0.3, 0.3), 0.1, rng.randf_range(-0.3, 0.3))
	return e


func spawn_npc(role: String, pos: Vector3, recruit_id: String = "") -> NPC:
	var n: NPC = NPC_SCENE.instantiate()
	n.role = role
	n.recruit_id = recruit_id
	n.faction = owner_faction
	n.npc_name = CIVILIAN_NAMES[rng.randi() % CIVILIAN_NAMES.size()]
	n.sprite_name = "merchant" if role == "merchant" else CIVILIAN_SPRITES[rng.randi() % CIVILIAN_SPRITES.size()]
	if role == "merchant":
		n.npc_name = ["Sal the Fence", "VEND-O-TRON", "Auntie Credit", "Mr. Markup"][rng.randi() % 4]
		n.traits.assign(["corporate"] if rng.randf() < 0.5 else ["poor"])
	else:
		var pool := ["poor", "worker", "artsy", "corporate", "rebel", "weird"]
		n.traits.assign([pool[rng.randi() % pool.size()], pool[rng.randi() % pool.size()]])
	n.gravity_scale = gravity_scale
	actors.add_child(n)
	n.global_position = pos + Vector3(0, 0.1, 0)
	return n


func _spawn_camera_and_hud() -> void:
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.target = player
	camera_rig.snap_to_target()
	hud = HUD_SCENE.instantiate()
	add_child(hud)
	hud.bind_player(player, camera_rig)


# --- Flow ---------------------------------------------------------------------------------

func exit_to_ship() -> void:
	if Router.busy:
		return
	Causality.flush_pending()
	Game.air_billing_active = false
	Game.enter_ship()
	Game.save_game()
	ShipAI.say("on_board", {}, true)
	Audio.play_sfx("warp", 0.0, -6.0)
	Router.goto(Router.STAR_MAP)


func _on_player_died() -> void:
	if _dying:
		return
	_dying = true
	Game.air_billing_active = false
	await get_tree().create_timer(1.8).timeout
	if is_instance_valid(hud) and hud.has_method("show_death_screen"):
		hud.show_death_screen()
