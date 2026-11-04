extends Level
## PROLOGUE - Cold Storage Lot 47, a derelict Halcyon cryo-station.
## You thaw in a pod (which room depends on your Background tag), meet QUACK,
## dodge repo drones, maybe rob a vending machine in front of witnesses,
## and board the Odd Duck at the dock.
##
## Edit the LAYOUT below to reshape the station (legend in level_builder.gd).

const LAYOUT := [
	"##################################",
	"#.L......#.....L....#.....L......#",
	"#.C.C.C..#..T....T..#..C....m.W..#",
	"#........#....4.....#.......3....#",
	"#.C.1.C..#..........#..C.........#",
	"#........#..=....=..#.....=......#",
	"#####.#######..###########.#######",
	"#...............A........A.......#",
	"#.L...K.....N.......V.......K..L.#",
	"#..........E.....M..........E....#",
	"#....A.......K..........K........#",
	"#.......N..........E.......N.....#",
	"#.L............................L.#",
	"######.##############.....########",
	"#.......=.=..#...................#",
	"#..S......=..#.......L.......L...#",
	"#.=..B.....2.#...................#",
	"#..==...B.........DDD............#",
	"#.=...S..=...#....DDD............#",
	"#.L......X...#....DDD........X...#",
	"##################################",
]

const PALETTE := {
	"bg": "#05020c", "ground": "#262536", "ground_alt": "#2e2d42", "wall": "#3a3552",
	"fog": "#1c0b34", "fog_density": 0.018,
	"sun": "#7a6aff", "sun_energy": 0.3, "ambient": "#3a3060", "ambient_energy": 0.55,
	"neon": ["#ff3ec8", "#3ee6ff", "#ffd23e"],
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
	if not Game.has_flag("prologue_woke"):
		Game.flags["prologue_woke"] = true
		Game.save_game()  # so death in the prologue reloads here
		_intro()


func _intro() -> void:
	await get_tree().create_timer(1.2).timeout
	ShipAI.say("on_wake", {}, true)
	for hint in HINTS:
		await get_tree().create_timer(6.5).timeout
		if not is_inside_tree():
			return
		EventBus.toast.emit(hint, Color(0.5, 1.0, 1.0))
