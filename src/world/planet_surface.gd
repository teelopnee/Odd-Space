extends Level
## A procedurally generated planet surface built from its 4-layer matrix:
## environment -> palette/props, controller -> who guards it & owns the stuff,
## crisis -> enemy density/prices, anomaly -> gravity, fog, ad ghosts, rain...

const W := 36
const H := 26
const PROP_CHARS := {"rock": "r", "crystal": "c", "mushroom": "u", "pipe": "p", "tank": "t", "antenna": "n", "ruin": "z", "crate": "="}
const CONTROLLER_ENEMIES := {
	"paragon": {"G": 4},
	"halcyon": {"E": 3, "H": 1},
	"gristle": {"B": 5, "G": 1},
	"oxy": {"G": 2, "E": 2},
	"lumen": {"G": 2, "E": 2},
	"": {"R": 4, "B": 2},
}

var planet: Dictionary = {}
var env_layer: Dictionary = {}
var crisis_layer: Dictionary = {}
var anomaly_layer: Dictionary = {}
var _grid: Array = []


func _setup() -> void:
	planet = Game.planet_by_id(Router.params.get("planet_id", ""))
	if planet.is_empty() and not Game.galaxy.is_empty():
		planet = Game.galaxy[0]
	env_layer = PlanetGenerator.layer(planet, "environments")
	crisis_layer = PlanetGenerator.layer(planet, "crises")
	anomaly_layer = PlanetGenerator.layer(planet, "anomalies")
	palette = env_layer.duplicate()
	owner_faction = planet.get("controller", "")
	level_seed = int(planet.get("seed", 1))
	music = "derelict_ambient"
	spawn_key = "default"
	var fx: Dictionary = anomaly_layer.get("effects", {})
	gravity_scale = float(fx.get("gravity_scale", 1.0))
	enemy_speed_mult = float(fx.get("enemy_speed_mult", 1.0))
	# Outdoor maps are bigger and brighter: thin the fog a little.
	palette["fog_density"] = float(palette.get("fog_density", 0.012)) * 0.7
	if fx.has("fog_add"):
		palette["fog_density"] = float(palette.get("fog_density", 0.01)) + float(fx["fog_add"])
	Game.enter_planet(planet)
	planet["visited"] = true


func _is_outdoor() -> bool:
	return true


func _get_layout() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = level_seed
	_grid = []
	for z in H:
		var row := []
		for x in W:
			row.append("#" if x == 0 or z == 0 or x == W - 1 or z == H - 1 else ".")
		_grid.append(row)
	var pad_x := W / 2 - 1
	var pad_z := H - 9
	# Landing zone (kept clear).
	for z in range(pad_z, pad_z + 3):
		for x in range(pad_x, pad_x + 3):
			_grid[z][x] = "D"
	_grid[H - 5][W / 2] = "P"
	# Buildings.
	var tries := int(18 * float(env_layer.get("building_density", 0.5)))
	for i in tries:
		var bw := r.randi_range(2, 4)
		var bh := r.randi_range(2, 3)
		var bx := r.randi_range(2, W - bw - 3)
		var bz := r.randi_range(2, H - bh - 12)
		if _area_free(bx - 1, bz - 1, bw + 2, bh + 2):
			for z in range(bz, bz + bh):
				for x in range(bx, bx + bw):
					_grid[z][x] = "b"
	# Decor props from the environment's list.
	var props: Array = env_layer.get("props", ["rock"])
	for i in 26:
		_place(r, PROP_CHARS.get(props[r.randi() % props.size()], "r"), 1, H - 2)
	for i in 8:
		_place(r, "L", 1, H - 2)
	var ad_count := 4 + (4 if planet.get("crisis", "") == "ad_overload" else 0)
	for i in ad_count:
		_place(r, "A", 2, H - 8)
	for i in 3:
		_place(r, "X", 2, H - 8)
		_place(r, "S", 2, H - 8)
	# Services near the landing pad.
	_place_near(r, "V", pad_x - 3, pad_z)
	_place_near(r, "m", pad_x + 5, pad_z)
	_place_near(r, "M", pad_x - 3, pad_z + 2)
	_place_near(r, "T", pad_x + 5, pad_z + 2)
	# Locals.
	for i in r.randi_range(5, 8):
		_place(r, "N", 2, H - 4)
	if not Crew.is_full() and r.randf() < 0.55:
		_place(r, "W", 2, H - 8)
	# Enemies, by who controls the place and how bad the crisis is.
	var mult := float(crisis_layer.get("enemy_mult", 1.0)) * (0.8 + 0.2 * int(planet.get("difficulty", 1)))
	var table: Dictionary = CONTROLLER_ENEMIES.get(owner_faction, CONTROLLER_ENEMIES[""])
	for ch in table:
		for i in roundi(int(table[ch]) * mult):
			_place(r, ch, 2, H - 13)
	var fx: Dictionary = anomaly_layer.get("effects", {})
	for i in int(fx.get("extra_bugs", 0)):
		_place(r, "B", 2, H - 13)
	var out := []
	for row in _grid:
		out.append("".join(PackedStringArray(row)))
	return out


func _area_free(x0: int, z0: int, w: int, h: int) -> bool:
	for z in range(z0, z0 + h):
		for x in range(x0, x0 + w):
			if z <= 0 or x <= 0 or z >= H - 1 or x >= W - 1 or _grid[z][x] != ".":
				return false
	return true


func _place(r: RandomNumberGenerator, ch: String, z_min: int, z_max: int) -> void:
	for attempt in 30:
		var x := r.randi_range(1, W - 2)
		var z := r.randi_range(z_min, z_max)
		if _grid[z][x] == "." and _area_free(x - 1, z - 1, 3, 3):
			_grid[z][x] = ch
			return


func _place_near(r: RandomNumberGenerator, ch: String, x: int, z: int) -> void:
	for attempt in 20:
		var px := clampi(x + r.randi_range(-1, 1), 1, W - 2)
		var pz := clampi(z + r.randi_range(-1, 1), 1, H - 2)
		if _grid[pz][px] == ".":
			_grid[pz][px] = ch
			return


func _post_build() -> void:
	var fx: Dictionary = anomaly_layer.get("effects", {})
	if fx.has("ad_ghosts"):
		for i in int(fx["ad_ghosts"]):
			var ghost := AdGhost.new()
			ghost.bounds = Rect2(4, 4, W * LevelBuilder.TILE - 8, (H - 8) * LevelBuilder.TILE)
			ghost.seed_value = level_seed + i
			add_child(ghost)
	if fx.get("reverse_rain", false):
		_reverse_rain()
	# Crew who mutinied are waiting here, armed.
	for member_id in Crew.pop_mutineers():
		var d := Crew.def(member_id)
		var pos := get_spawn_position() + Vector3(rng.randf_range(-6, 6), 0, -10)
		spawn_enemy("pirate", pos, {"name": "%s (MUTINEER)" % d.get("name", member_id), "sprite": d.get("sprite", ""), "hostile": true})
		EventBus.toast.emit("%s is here, and they're not here to talk." % d.get("name", member_id), Color(1, 0.3, 0.3))
	Game.save_game()


func _reverse_rain() -> void:
	var p := CPUParticles3D.new()
	p.amount = 400
	p.lifetime = 2.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(W, 0.5, H)
	p.direction = Vector3.UP
	p.spread = 2.0
	p.gravity = Vector3(0, 6, 0)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 7.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.0
	var streak := BoxMesh.new()
	streak.size = Vector3(0.03, 0.5, 0.03)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.9, 1.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.9, 1.0)
	mat.emission_energy_multiplier = 1.5
	streak.material = mat
	p.mesh = streak
	p.position = Vector3(W * LevelBuilder.TILE * 0.5, 0.1, H * LevelBuilder.TILE * 0.5)
	add_child(p)
