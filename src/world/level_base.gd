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

const ENEMY_CHARS := {"E": "repo_drone", "G": "paragon_officer", "B": "gristle_grub", "H": "debt_brute", "R": "pirate",
	"U": "riot_trooper", "F": "street_punk", "Q": "boom_bot", "J": "swarm_drone", "Z": "vat_golem"}
const CIVILIAN_NAMES := ["Marla", "Dex", "Old Ivo", "Juno", "Tam", "Priya", "Bex", "Otto", "Sunny", "Kaz", "Wen", "Lula", "Rico", "Nan"]
const CIVILIAN_SPRITES := ["civilian_a", "civilian_b", "civilian_c"]

var palette: Dictionary = {}
var owner_faction := ""
var music := "derelict_ambient"
var level_seed := 1
var spawn_key := "default"
var gravity_scale := 1.0
var enemy_speed_mult := 1.0
var camera_pitch := 36.0
var camera_distance := 14.5
var camera_fov := 31.0

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
var builder: LevelBuilder
var _dying := false
var _quest_spawned: Dictionary = {}
const GUARD_TYPES := {"paragon": "paragon_officer", "halcyon": "repo_drone", "gristle": "gristle_grub", "oxy": "paragon_officer", "lumen": "paragon_officer", "": "pirate"}


func _ready() -> void:
	add_to_group("level")
	_setup()
	rng.seed = level_seed
	_build_environment()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "World"
	add_child(nav_region)
	builder = LevelBuilder.new(nav_region, palette, level_seed, _is_outdoor(), owner_faction)
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
	Audio.play_ambience("")


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
	environment.tonemap_exposure = float(palette.get("exposure", 1.1))
	environment.tonemap_white = 6.0
	# Dreamy HD-2D bloom: wide, soft halos around every light and neon strip.
	environment.glow_enabled = true
	environment.glow_intensity = 0.85
	environment.glow_strength = 1.1
	environment.glow_bloom = 0.06
	environment.glow_hdr_threshold = 0.8
	environment.glow_hdr_scale = 2.2
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.set_glow_level(0, 0.0)
	environment.set_glow_level(1, 0.4)
	environment.set_glow_level(2, 0.8)
	environment.set_glow_level(3, 1.0)
	environment.set_glow_level(4, 0.8)
	environment.set_glow_level(5, 0.5)
	# Atmospheric depth fog.
	environment.fog_enabled = true
	environment.fog_light_color = pcolor("fog", "#3a1060")
	environment.fog_light_energy = 1.0
	environment.fog_density = float(palette.get("fog_density", 0.012))
	environment.fog_sky_affect = 0.0
	# Retro colour punch.
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.22
	environment.adjustment_contrast = 1.1
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = pcolor("sun", "#9a7dff")
	sun.light_energy = float(palette.get("sun_energy", 0.4))
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.shadow_opacity = 0.85
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
	_spawn_keepers()


## Shop owners: one at every venue door, the same person every visit (saved per planet).
const KEEPER_STYLE := {"arcade": "punk", "tattoo": "punk", "tapes": "punk", "clinic": "worker", "implants": "robot",
	"loans": "corporate", "corp_store": "corporate", "fortune": "civilian", "bar": "worker", "karaoke": "punk"}
const KEEPER_TRAITS := {"corp_store": "corporate", "loans": "corporate", "clinic": "worker", "arcade": "artsy", "tattoo": "artsy",
	"tapes": "artsy", "fortune": "weird", "implants": "weird", "karaoke": "artsy"}


func _spawn_keepers() -> void:
	if builder == null:
		return
	for it in builder.venue_spots:
		if is_instance_valid(it) and it.is_inside_tree():
			spawn_keeper(it)


func spawn_keeper(it: Node3D) -> NPC:
	var vid := str(it.get("venue_id"))
	var sign := str(it.get("venue_sign"))
	var key := "%s|%s" % [vid, sign]
	var saved: Dictionary = Game.flags.get("keepers_" + Game.location_id, {}).get(key, {})
	if saved.get("dead", false):
		return null  # the shop stays dark (Interactions.open_venue shows what's left)
	var krng := RandomNumberGenerator.new()
	krng.seed = hash(key + Game.location_id + str(Game.world_seed))
	var n: NPC = NPC_SCENE.instantiate()
	n.role = "keeper"
	n.keeper_key = key
	n.keeper_loc = Game.location_id
	n.venue_id = vid
	n.venue_sign = sign
	var fac := str(it.get("owner_faction"))
	n.faction = fac if fac != "" else owner_faction
	if saved.is_empty():
		var style: String = KEEPER_STYLE.get(vid, ["worker", "civilian", "worker", "punk"][krng.randi() % 4])
		if style == "corporate":
			style = "corporate:" + n.faction if n.faction != "" else "worker"
		elif style == "robot" and krng.randf() < 0.5:
			style = "worker"
		n.look = CharacterLook.random_look(krng, style)
		n.npc_name = Copy.make("robot_name" if style == "robot" else ("merchant_name" if krng.randf() < 0.4 else "npc_name"), krng)
		var t1: String = KEEPER_TRAITS.get(vid, ["worker", "poor", "worker", "rebel"][krng.randi() % 4])
		n.traits.assign([t1, ["poor", "worker", "artsy", "corporate", "rebel", "weird"][krng.randi() % 6]])
	else:
		n.look = saved.get("look", {})
		n.npc_name = str(saved.get("name", "Owner"))
		n.traits.assign(saved.get("traits", ["worker"]))
	n.gravity_scale = gravity_scale
	actors.add_child(n)
	var fwd: Vector3 = it.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.BACK
	var side := fwd.cross(Vector3.UP).normalized()
	var p: Vector3 = it.global_position + fwd * 0.6 + side * 1.25
	n.global_position = Vector3(p.x, 0.1, p.z)
	n.post_pos = n.global_position
	n.post_face = fwd
	n.job = "owner of %s" % sign.capitalize()
	if not saved.is_empty():
		n.restore_keeper(saved)
	it.set_meta("keeper", n)
	n.refresh_label()
	return n


func spawn_enemy(type_id: String, pos: Vector3, extra: Dictionary = {}) -> Enemy:
	var e: Enemy = ENEMY_SCENE.instantiate()
	e.enemy_type = type_id
	e.display_name_override = extra.get("name", "")
	e.sprite_override = extra.get("sprite", "")
	e.look_override = extra.get("look", {})
	e.force_hostile = extra.get("hostile", false)
	e.gravity_scale = gravity_scale
	e.world_speed_mult = enemy_speed_mult
	actors.add_child(e)
	e.global_position = pos + Vector3(rng.randf_range(-0.3, 0.3), 0.1, rng.randf_range(-0.3, 0.3))
	if extra.has("tag"):
		e.set_meta("saga_tag", extra["tag"])
	if extra.get("elite", false):
		var boss: bool = extra.get("boss", false)
		e.max_hp *= 5.0 if boss else 2.6
		e.hp = e.max_hp
		e.shield_max += 6 if boss else 3
		e.shield = e.shield_max
		e.sprite.scale_base = 1.4 if boss else 1.2
		e.call_deferred("_refresh_shield")
	return e


func spawn_npc(role: String, pos: Vector3, recruit_id: String = "") -> NPC:
	var n: NPC = NPC_SCENE.instantiate()
	n.role = role
	n.recruit_id = recruit_id
	n.faction = owner_faction
	var style: String = "worker" if role == "merchant" else ["civilian", "civilian", "civilian", "worker", "punk", "robot"][rng.randi() % 6]
	n.npc_name = Copy.make("robot_name" if style == "robot" else "npc_name", rng) if rng.randf() < 0.85 \
		else CIVILIAN_NAMES[rng.randi() % CIVILIAN_NAMES.size()]
	if owner_faction != "" and rng.randf() < 0.25:
		style = "corporate:" + owner_faction
	n.look = CharacterLook.random_look(rng, style)
	if role == "merchant":
		n.npc_name = Copy.make("merchant_name", rng)
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
	camera_rig.configure(camera_pitch, camera_distance, camera_fov)
	camera_rig.target = player
	camera_rig.snap_to_target()
	_build_weather(str(palette.get("weather", "")))
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


## Splashes where drops hit the ground, plus distant lightning that flashes the whole scene.
func _rain_extras() -> void:
	var sp := CPUParticles3D.new()
	sp.local_coords = false
	sp.amount = 70
	sp.lifetime = 0.3
	sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(14, 0.02, 10)
	sp.position = Vector3(0, 0.04, 0)
	sp.direction = Vector3.UP
	sp.spread = 35.0
	sp.gravity = Vector3(0, -14, 0)
	sp.initial_velocity_min = 1.2
	sp.initial_velocity_max = 2.4
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = Color(0.75, 0.85, 1.0, 0.35)
	q.material = m
	sp.mesh = q
	camera_rig.add_child(sp)
	var t := Timer.new()
	t.wait_time = rng.randf_range(6.0, 14.0)
	t.autostart = true
	t.timeout.connect(_lightning.bind(t))
	add_child(t)


func _lightning(t: Timer) -> void:
	t.wait_time = rng.randf_range(8.0, 22.0)
	if not is_instance_valid(sun):
		return
	var base_sun := sun.light_energy
	var base_amb := environment.ambient_light_energy
	var tw := create_tween()
	for i in rng.randi_range(1, 3):
		tw.tween_callback(func():
			sun.light_energy = base_sun + 3.5
			environment.ambient_light_energy = base_amb + 1.4)
		tw.tween_interval(0.06)
		tw.tween_callback(func():
			sun.light_energy = base_sun
			environment.ambient_light_energy = base_amb)
		tw.tween_interval(rng.randf_range(0.05, 0.16))
	tw.tween_interval(rng.randf_range(0.6, 1.6))
	tw.tween_callback(func(): Audio.play_sfx("thunder", 0.15, -6.0))


## Weather particles ride along with the camera so they always fill the view.
func _build_weather(kind: String) -> void:
	if kind == "" or kind == "dust" or OS.get_environment("ODD_NO_WEATHER") == "1":
		return
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	q.material = m
	p.mesh = q
	match kind:
		"rain":
			p.amount = 320
			p.lifetime = 0.9
			p.emission_box_extents = Vector3(18, 0.5, 14)
			p.position = Vector3(0, 10, 0)
			p.direction = Vector3(0.15, -1, 0)
			p.spread = 2.0
			p.gravity = Vector3(0, -30, 0)
			p.initial_velocity_min = 14.0
			p.initial_velocity_max = 18.0
			# Fewer, longer, wider streaks: thin sub-pixel drops just read as noise.
			q.size = Vector2(0.06, 1.0)
			m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			m.albedo_color = Color(0.65, 0.78, 1.0, 0.3)
			_rain_extras()
		"snow":
			p.amount = 360
			p.lifetime = 5.0
			p.preprocess = 5.0
			p.emission_box_extents = Vector3(18, 0.5, 14)
			p.position = Vector3(0, 9, 0)
			p.direction = Vector3(0.3, -1, 0)
			p.spread = 25.0
			p.gravity = Vector3(0.2, -1.2, 0)
			p.initial_velocity_min = 0.5
			p.initial_velocity_max = 1.2
			q.size = Vector2(0.07, 0.07)
			m.albedo_color = Color(0.95, 0.97, 1.0, 0.85)
		"spores", "embers", "motes":
			p.amount = 160
			p.lifetime = 6.0
			p.preprocess = 6.0
			p.emission_box_extents = Vector3(16, 2.5, 12)
			p.position = Vector3(0, 1.5, 0)
			p.direction = Vector3(0, 1, 0)
			p.spread = 50.0
			p.gravity = Vector3(0, 0.35 if kind != "motes" else 0.05, 0)
			p.initial_velocity_min = 0.1
			p.initial_velocity_max = 0.5
			q.size = Vector2(0.06, 0.06)
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			var c := {"spores": Color(0.6, 1.6, 0.5, 0.9), "embers": Color(2.2, 0.9, 0.3, 0.9), "motes": Color(1.4, 1.0, 2.2, 0.9)}[kind] as Color
			m.albedo_color = c
	camera_rig.add_child(p)


# --- Story & side quests (Saga) -----------------------------------------------------------------

## Random walkable floor tile at least min_dist from the player spawn.
func random_floor_position(min_dist: float = 8.0) -> Vector3:
	var spawn := get_spawn_position()
	for attempt in 200:
		var x := rng.randi_range(1, builder.width - 2)
		var z := rng.randi_range(1, builder.height - 2)
		if builder.cell(x, z) != "." and builder.cell(x, z) != "," and builder.cell(x, z) != "_":
			continue
		var p := builder.center(x, z)
		if p.distance_to(spawn) >= min_dist:
			return p
	return spawn + Vector3(4, 0, -4)


## Spawn whatever the Saga needs here (call again after quest state changes).
func refresh_quests() -> void:
	if builder == null or not is_inside_tree():
		return
	var planet_id := Game.location_id
	for spec in Saga.spawns_for(planet_id) + Stories.spawns_for(planet_id):
		var key: String = spec.get("key", "%s:%s" % [spec.kind, spec.get("persona_id", spec.get("tag", ""))])
		if spec.kind == "guards" and not spec.has("key"):
			key = "guards:%d" % Saga.index
		if _quest_spawned.has(key):
			continue
		_quest_spawned[key] = true
		match spec.kind:
			"persona":
				var p: Dictionary = Saga.personas.get(spec.persona_id, {})
				var near_pad: bool = spec.get("quest", "") == "side"
				var pos := random_floor_position(4.0 if near_pad else 10.0)
				if near_pad:
					pos = get_spawn_position() + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, -2))
				var n := spawn_npc("civilian", pos)
				n.persona_id = p.get("id", "")
				n.npc_name = p.get("name", "?")
				n.look = p.get("look", {})
				n.sprite.set_look(n.look)
				n.name_label.text = n.npc_name + "\n<%s>" % str(p.get("job", "")).to_upper()
				n.faction = p.get("faction", "")
				attach_marker(n, "!" if spec.get("quest", "") == "main" else "?", Color(1.0, 0.82, 0.24) if spec.get("quest", "") == "main" else Color(0.5, 1.0, 0.9))
			"quest_item":
				var pos := random_floor_position(12.0)
				var body := builder.static_body(pos)
				builder.add_mesh(body, builder.box(Vector3(1.0, 0.8, 0.8)), builder.emissive(Color(1.0, 0.75, 0.2), 1.5), Vector3(0, 0.4, 0))
				builder.add_box_collider(body, Vector3(1.0, 0.8, 0.8), Vector3(0, 0.4, 0))
				var it := PropInteractable.new()
				it.kind = "quest_item"
				it.quest_tag = spec.tag
				it.prompt = "Take %s" % spec.get("label", "it")
				it.position = Vector3(0, 0.6, 0.6)
				body.add_child(it)
				attach_marker(body, "!", Color(1.0, 0.82, 0.24))
				if spec.tag == Saga.current().get("id", ""):
					_spawn_guards(pos, 2, Saga.world.get("faction", ""))
			"elite":
				var p: Dictionary = Saga.personas.get(spec.get("persona_id", ""), {})
				var pos := random_floor_position(14.0)
				var e := spawn_enemy(spec.get("enemy_type", "pirate"), pos, {"name": spec.get("name", p.get("name", "Elite")), "look": spec.get("look", p.get("look", {})),
					"hostile": true, "elite": true, "boss": spec.get("boss", false), "tag": spec.tag})
				attach_marker(e, "X", Color(1.0, 0.3, 0.3))
			"story_npc":
				var p: Dictionary = spec.get("persona", {})
				var n := spawn_npc("civilian", random_floor_position(5.0))
				n.story_id = spec.story_id
				n.npc_name = p.get("name", "?")
				n.look = p.get("look", {})
				n.sprite.set_look(n.look)
				n.faction = p.get("faction", "")
				n.name_label.text = n.npc_name + "\n<%s>" % str(p.get("job", "")).to_upper()
				n.add_to_group("story_npc")
				if str(spec.get("marker", "")) != "":
					attach_marker(n, spec.marker, spec.get("color", Color(0.75, 0.5, 1.0)))
			"street":
				var ev: Dictionary = spec.get("event", {})
				var center := random_floor_position(7.0)
				var who: Dictionary = ev.get("who", {})
				var n := spawn_npc("civilian", center)
				n.story_id = spec.story_id
				n.npc_name = str(who.get("name", "Stranger"))
				n.look = CharacterLook.random_look(rng, str(who.get("style", "civilian")))
				n.sprite.set_look(n.look)
				n.name_label.text = n.npc_name + "\n<%s>" % str(ev.get("title", "")).to_upper()
				n.add_to_group("story_npc")
				attach_marker(n, "!", spec.get("color", Color(1.0, 0.55, 0.2)))
				var victim: Dictionary = ev.get("victim", {})
				if not victim.is_empty():
					var v := spawn_npc("civilian", center + Vector3(1.4, 0, 0.4))
					v.npc_name = str(victim.get("name", "Bystander"))
					v.look = CharacterLook.random_look(rng, str(victim.get("style", "civilian")))
					v.sprite.set_look(v.look)
					v.name_label.text = v.npc_name
					v.set_meta("street_victim", spec.story_id)
			"guards":
				_spawn_guards(random_floor_position(12.0), int(spec.get("count", 2)), str(spec.get("faction", "")))


## Street events that turn violent.
func spawn_story_hostiles(type_id: String, count: int, display: String, near: Vector3) -> void:
	for i in count:
		var p := near + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		var e := spawn_enemy(type_id, p, {"hostile": true, "name": display})
		e.call_deferred("provoke")


func _spawn_guards(center: Vector3, count: int, faction: String) -> void:
	for i in count:
		spawn_enemy(GUARD_TYPES.get(faction, "pirate"), center + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)), {"hostile": true})


## Floating quest marker + golden light beam over a node.
func attach_marker(node: Node3D, text: String, color: Color) -> void:
	var holder := Node3D.new()
	holder.name = "QuestMarker"
	node.add_child(holder)
	holder.position = Vector3(0, 2.9, 0)
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0)
	l.outline_size = 16
	l.outline_modulate = Color(0.1, 0.05, 0.0)
	holder.add_child(l)
	var tw := holder.create_tween().set_loops()
	tw.tween_property(holder, "position:y", 3.2, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(holder, "position:y", 2.9, 0.6).set_trans(Tween.TRANS_SINE)
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 6.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = load("res://assets/textures/light_shaft.png")
	m.albedo_color = Color(color.r, color.g, color.b, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	var beam := MeshInstance3D.new()
	beam.mesh = q
	beam.rotation_degrees.z = 180.0
	beam.position = Vector3(0, 3.0, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(beam)
