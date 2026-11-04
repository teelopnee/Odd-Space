extends Level
## PROLOGUE - Cold Storage Lot 47, a derelict Halcyon cryo-station.
## You thaw in a pod (which room depends on your Background tag), meet QUACK,
## dodge repo drones, maybe rob a vending machine in front of witnesses,
## and board the Odd Duck at the dock.
##
## Edit the LAYOUT below to reshape the station (legend in level_builder.gd).

const LAYOUT := [
	"#OO#OO###OO##OO######OO##OO#######",
	"#.L......#.....L....#__.__L______#",
	"#.C.C.C..#..T....T..#_C____m_W___#",
	"#........#....4.....#_______3____#",
	"#.C.1.C..#..........#_C__________#",
	"#........#..=....=..#_____=______#",
	"#####,#######,,###########_#######",
	"#...............A........A.......#",
	"#.L...K.....N.......V.......K..L.#",
	"#..........E.....M..........E....#",
	"#....A.......K..h.......K........#",
	"#.......N..........E.......N.....#",
	"#.L............................L.#",
	"######,##############,,,,,########",
	"#.......=.=..#...,,,,,,,,,,,,....#",
	"#..S......=..#.......L.......L...#",
	"#.=..B.....2.#...................#",
	"#..==...B....,....DDD............#",
	"#.=...S..=...#....DDD............#",
	"#.L......X...#....DDD........X...#",
	"##################################",
]

const PALETTE := {
	"bg": "#05020c", "ground": "#3a3a52", "ground_alt": "#44445e", "wall": "#4a4562",
	"fog": "#1c0b34", "fog_density": 0.016,
	"sun": "#8a7aff", "sun_energy": 0.35, "ambient": "#2a2450", "ambient_energy": 0.45,
	"neon": ["#ff3ec8", "#3ee6ff", "#ffd23e"],
	"weather": "dust",
}

const HINTS := [
	"MOVE: left stick / WASD",
	"FIRE auto-aims. Tap an enemy's body part (or press PART) to target it.",
	"ROLL = i-frames. PARRY right when an enemy flashes ORANGE.",
	"Crimes seen by witnesses get REPORTED. Stop the call: bribe, threaten... or worse.",
]


func _setup() -> void:
	palette = PALETTE
	owner_faction = "halcyon"
	music = "derelict_ambient"
	level_seed = Game.world_seed + 47
	spawn_key = Origin.spawn_point()
	Game.enter_station()


func _get_layout() -> Array:
	return LAYOUT


func _post_build() -> void:
	Audio.play_ambience("amb_station")
	var w := 34 * LevelBuilder.TILE
	var h := 21 * LevelBuilder.TILE
	for i in 4:
		var bot := Critter.new()
		bot.kind = "bot"
		bot.bounds = Rect2(4, 15, w - 8, 8)
		bot.seed_value = level_seed + i
		add_child(bot)
	for i in 2:
		var ship := Critter.new()
		ship.kind = "flyby"
		ship.bounds = Rect2(0, -4.5, w, 1)
		ship.seed_value = level_seed + 10 + i
		add_child(ship)
	if not Game.has_flag("prologue_woke"):
		Game.flags["prologue_woke"] = true
		Game.save_game()  # so death in the prologue reloads here
		_intro()
	else:
		hud.title_card("COLD STORAGE LOT 47", "PROLOGUE")


## Opening cutscene: thaw, QUACK, a look at the repo drones, then control.
func _intro() -> void:
	player.set_cutscene(true)
	hud.cinematic(true)
	player.sprite.play("dead", true)
	player.sprite.speed_scale = 100.0
	camera_rig.configure(30.0, 9.5, 28.0)
	await get_tree().create_timer(1.6).timeout
	# Pod hisses open.
	Audio.play_sfx("pod_open")
	FX.dust(self, player.global_position + Vector3(0, 0.3, -0.6), 2.2)
	FX.dust(self, player.global_position + Vector3(0.6, 0.6, -0.4), 1.6)
	FXSprite.play_at(self, "break", player.global_position + Vector3(0, 1.2, -0.5), 2.2, 1.6, Color(0.6, 0.9, 1.0))
	FX.shake(get_tree(), 0.25)
	await get_tree().create_timer(0.9).timeout
	player.sprite.speed_scale = 1.0
	player.sprite.play("hurt", true)
	player.sprite.squash(Vector2(0.8, 1.2))
	await get_tree().create_timer(0.5).timeout
	player.sprite.play("idle", true)
	var tw := create_tween()
	tw.tween_method(func(k: float): camera_rig.configure(lerpf(30.0, camera_pitch, k), lerpf(9.5, camera_distance, k), lerpf(28.0, camera_fov, k)), 0.0, 1.0, 2.0).set_trans(Tween.TRANS_SINE)
	hud.title_card("COLD STORAGE LOT 47", "PROLOGUE", 2.2)
	await get_tree().create_timer(3.6).timeout
	await hud.say("Q.U.A.C.K.", "Oh good, you're thawed. I was about to list you on the secondhand market as \"vintage meat\".\n\nI'm QUACK, the ship AI of the Odd Duck. Technically I'm your ship. Technically you owe me rent.")
	# Pan to the drones in the concourse.
	var look := Node3D.new()
	add_child(look)
	var drone: Node3D = null
	for e in get_tree().get_nodes_in_group("enemy"):
		drone = e
		break
	look.global_position = drone.global_position if drone else player.global_position + Vector3(0, 0, 8)
	camera_rig.target = look
	camera_rig.follow_speed = 2.2
	await get_tree().create_timer(2.0).timeout
	await hud.say("Q.U.A.C.K.", "Those are Halcyon repo drones. They're repossessing the station. And everything in it. Including, legally, you.\n\nShoot their SENSORS to blind them. Parry when they flash orange. Or roll. Rolling is free. For now.")
	look.global_position = drone_dock_position()
	await get_tree().create_timer(2.0).timeout
	await hud.say("Q.U.A.C.K.", "I'm docked at the south bay. Walk in, don't die, and try not to commit crimes in front of witnesses. They have radios. And opinions.")
	camera_rig.target = player
	await get_tree().create_timer(1.0).timeout
	camera_rig.follow_speed = 6.5
	look.queue_free()
	hud.cinematic(false)
	player.set_cutscene(false)
	EventBus.toast.emit("Q.U.A.C.K. joined your comms (it was always there)", Color(1.0, 0.82, 0.24))


func drone_dock_position() -> Vector3:
	return build.get("dock", player.global_position) if build.get("has_dock", false) else player.global_position
