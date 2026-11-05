extends Level
## A procedurally generated planet surface built from its 4-layer matrix:
## environment -> palette/props, controller -> who guards it & owns the stuff,
## crisis -> enemy density/prices, anomaly -> gravity, fog, ad ghosts, rain...

var planet: Dictionary = {}
var env_layer: Dictionary = {}
var crisis_layer: Dictionary = {}
var anomaly_layer: Dictionary = {}


func _setup() -> void:
	planet = Game.planet_by_id(Router.params.get("planet_id", ""))
	if planet.is_empty() and not Game.galaxy.is_empty():
		planet = Game.galaxy[0]
	env_layer = PlanetGenerator.layer(planet, "environments")
	crisis_layer = PlanetGenerator.layer(planet, "crises")
	anomaly_layer = PlanetGenerator.layer(planet, "anomalies")
	# Planet stories leave scars (or relief) that change the place for good.
	match str(planet.get("crisis_state", "")):
		"resolved":
			crisis_layer = crisis_layer.duplicate()
			crisis_layer["enemy_mult"] = float(crisis_layer.get("enemy_mult", 1.0)) * 0.6
			crisis_layer["name"] = "After the " + str(crisis_layer.get("name", "crisis"))
		"worse":
			crisis_layer = crisis_layer.duplicate()
			crisis_layer["enemy_mult"] = float(crisis_layer.get("enemy_mult", 1.0)) * 1.4
			crisis_layer["name"] = str(crisis_layer.get("name", "crisis")) + " (worse)"
	palette = env_layer.duplicate(true)
	owner_faction = planet.get("controller", "")
	level_seed = int(planet.get("seed", 1))
	_vary_palette()
	# Outdoors the camera tilts up a little to show the horizon.
	camera_pitch = 30.0
	camera_distance = 16.0
	camera_fov = 32.0
	music = {"neon_sprawl": "neon_city", "toxic_swamp": "bog_hymn", "ad_desert": "glacier_static",
		"rust_canyon": "rust_run", "crystal_moon": "crystal_lull"}.get(str(env_layer.get("id", "")), "derelict_ambient")
	spawn_key = "default"
	var fx: Dictionary = anomaly_layer.get("effects", {})
	gravity_scale = float(fx.get("gravity_scale", 1.0))
	enemy_speed_mult = float(fx.get("enemy_speed_mult", 1.0))
	# Outdoor maps are bigger and brighter: thin the fog a little.
	palette["fog_density"] = float(palette.get("fog_density", 0.012)) * 0.5
	if fx.has("fog_add"):
		palette["fog_density"] = float(palette.get("fog_density", 0.01)) + float(fx["fog_add"])
	Game.enter_planet(planet)
	planet["visited"] = true


func _is_outdoor() -> bool:
	return true


func _get_layout() -> Array:
	var gen := WorldGen.generate(level_seed, str(env_layer.get("id", "")), owner_faction, crisis_layer,
		anomaly_layer.get("effects", {}), int(planet.get("difficulty", 1)), not Crew.is_full())
	return gen.layout


## Every planet of the same biome still looks different: nudge hues, fog, light and
## weather from the planet seed (same seed -> same look, so saves stay consistent).
func _vary_palette() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = level_seed * 7 + 3
	for key in ["ground", "ground_alt", "wall", "fog", "ambient", "plant"]:
		if palette.has(key):
			var c := Color.from_string(str(palette[key]), Color.GRAY)
			c.h = fposmod(c.h + r.randf_range(-0.035, 0.035), 1.0)
			c.v = clampf(c.v * r.randf_range(0.88, 1.14), 0.0, 1.0)
			palette[key] = "#" + c.to_html(false)
	var neon: Array = palette.get("neon", ["#ff3ec8", "#3ee6ff"]).duplicate()
	for i in neon.size():
		var c := Color.from_string(str(neon[i]), Color.MAGENTA)
		c.h = fposmod(c.h + r.randf_range(-0.05, 0.05), 1.0)
		neon[i] = "#" + c.to_html(false)
	neon.append("#" + Color.from_hsv(r.randf(), 0.75, 1.0).to_html(false))
	palette["neon"] = neon
	palette["fog_density"] = float(palette.get("fog_density", 0.012)) * r.randf_range(0.7, 1.35)
	palette["sun_energy"] = float(palette.get("sun_energy", 0.5)) * r.randf_range(0.8, 1.25)
	var sun := Color.from_string(str(palette.get("sun", "#ffffff")), Color.WHITE)
	sun = sun.lerp(Color.from_hsv(r.randf_range(0.0, 0.12) if r.randf() < 0.5 else r.randf_range(0.6, 0.8), 0.5, 1.0), r.randf_range(0.0, 0.35))
	palette["sun"] = "#" + sun.to_html(false)
	if palette.get("weather", "") == "rain" and r.randf() < 0.3:
		palette["weather"] = ""
	elif palette.get("weather", "") == "" and r.randf() < 0.3:
		palette["weather"] = ["rain", "motes", "embers"][r.randi() % 3]


func _post_build() -> void:
	var fx: Dictionary = anomaly_layer.get("effects", {})
	if fx.has("ad_ghosts"):
		for i in int(fx["ad_ghosts"]):
			var ghost := AdGhost.new()
			ghost.bounds = Rect2(4, 4, builder.width * LevelBuilder.TILE - 8, (builder.height - 8) * LevelBuilder.TILE)
			ghost.seed_value = level_seed + i
			add_child(ghost)
	if fx.get("reverse_rain", false):
		_reverse_rain()
	# Crew who mutinied are waiting here, armed.
	for member_id in Crew.pop_mutineers():
		var d := Crew.def(member_id)
		var pos := get_spawn_position() + Vector3(rng.randf_range(-6, 6), 0, -10)
		spawn_enemy("pirate", pos, {"name": "%s (MUTINEER)" % d.get("name", member_id), "look": d.get("look", {}), "hostile": true})
		EventBus.toast.emit("%s is here, and they're not here to talk." % d.get("name", member_id), Color(1, 0.3, 0.3))
	Game.save_game()
	_ambient_life()
	Stories.begin_visit(planet.get("id", ""))
	refresh_quests()
	_landing()


func _ambient_life() -> void:
	var weather := str(palette.get("weather", ""))
	Audio.play_ambience("amb_rain" if weather == "rain" else "amb_wind")
	var area := Rect2(4, 4, builder.width * LevelBuilder.TILE - 8, builder.height * LevelBuilder.TILE - 10)
	var city := str(env_layer.get("id", "")) == "neon_sprawl"
	for i in (5 if city else 3):
		var d := Critter.new()
		d.kind = "drone"
		d.bounds = area
		d.seed_value = level_seed + i
		add_child(d)
	# Public-address announcements from whoever owns the place; street radio everywhere.
	var has_pa: bool = owner_faction != "" or city
	var pa := Timer.new()
	pa.wait_time = rng.randf_range(18.0, 30.0)
	pa.autostart = true
	pa.timeout.connect(func():
		pa.wait_time = rng.randf_range(25.0, 50.0)
		if has_pa and rng.randf() < 0.6:
			EventBus.toast.emit("PA  //  " + Copy.make("pa", rng), Color(0.7, 0.9, 1.0))
		else:
			EventBus.toast.emit("%s  //  %s" % [Copy.make("station", rng), Copy.make("radio", rng)], Color(1.0, 0.72, 0.95)))
	add_child(pa)
	# Street traffic along the avenues (city only).
	var lanes: Array = builder.road_lanes.duplicate()
	lanes.shuffle()
	for i in mini(lanes.size(), 8):
		var sc := Critter.new()
		sc.kind = "streetcar"
		sc.lane_from = lanes[i][0]
		sc.lane_to = lanes[i][1]
		sc.seed_value = level_seed * 11 + i
		add_child(sc)
	# Sky traffic over the rooftops (sparser out in the wilds).
	for i in (14 if city else 4):
		var car := Critter.new()
		car.kind = "car"
		car.bounds = area
		car.seed_value = level_seed * 3 + i
		add_child(car)


## The Odd Duck touches down; then you step out and the chapter card rolls.
func _landing() -> void:
	var ship: Node3D = nav_region.find_child("OddDuck", true, false) as Node3D
	player.set_cutscene(true)
	player.visible = false
	hud.cinematic(true)
	# Establishing crane shot: start high and wide over the district, glide down into play.
	camera_rig.pitch_degrees = 56.0
	camera_rig.distance = 36.0
	var crane := create_tween().set_parallel()
	crane.tween_property(camera_rig, "pitch_degrees", camera_pitch, 4.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	crane.tween_property(camera_rig, "distance", camera_distance, 4.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if ship:
		var final_y := ship.position.y
		ship.position.y = final_y + 14.0
		var tw := create_tween()
		tw.tween_property(ship, "position:y", final_y, 2.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		camera_rig.target = ship
		await tw.finished
		Audio.play_sfx("land")
		FX.shake(get_tree(), 0.5)
		FX.rumble(0.4, 0.6, 0.3)
		for i in 5:
			FX.dust(self, ship.global_position + Vector3(randf_range(-3, 3), 0.1, randf_range(-1.5, 1.5)), 2.0)
	await get_tree().create_timer(0.6).timeout
	player.visible = true
	player.sprite.squash(Vector2(0.8, 1.25))
	camera_rig.target = player
	var env := PlanetGenerator.layer(planet, "environments")
	var crisis := PlanetGenerator.layer(planet, "crises")
	hud.title_card(str(planet.get("name", "?")).to_upper(), "%s  //  %s" % [str(env.get("name", "")).to_upper(), str(crisis.get("name", "")).to_upper()], 2.4)
	await get_tree().create_timer(1.2).timeout
	hud.cinematic(false)
	player.set_cutscene(false)
	Tips.show("first_planet")


func _reverse_rain() -> void:
	var p := CPUParticles3D.new()
	p.amount = 400
	p.lifetime = 2.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(builder.width, 0.5, builder.height)
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
	p.position = Vector3(builder.width * LevelBuilder.TILE * 0.5, 0.1, builder.height * LevelBuilder.TILE * 0.5)
	add_child(p)
