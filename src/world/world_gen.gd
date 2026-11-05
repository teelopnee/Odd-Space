class_name WorldGen
extends RefCounted
## Procedural planet layouts - a different algorithm per biome, random size,
## dense dressing, crowds, and a reachability pass so nothing important ends
## up on an unreachable island. Output is the same ASCII grammar LevelBuilder
## reads (legend in level_builder.gd), so generated maps stay tablet-readable.
##
##   neon_sprawl  : street grid, building blocks, plazas, market rows, parked cars
##   toxic_swamp  : noise waterways, boardwalks, huts, giant trees & mushrooms
##   ad_desert    : dune rocks, ruined billboard towers, a domed settlement
##   rust_canyon  : mesa cliffs, mining rigs, shack town
##   crystal_moon : crystal fields, glowing pools, habitat domes

var r := RandomNumberGenerator.new()
var w := 40
var h := 30
var g: Array = []
var biome := ""
var pad := Vector2i.ZERO
var spawn := Vector2i.ZERO
var noise := FastNoiseLite.new()
var crisis_id := ""


static func generate(seed_value: int, env_id: String, controller: String, crisis: Dictionary, anomaly_fx: Dictionary,
		difficulty: int, recruit_ok: bool) -> Dictionary:
	var gen := WorldGen.new()
	return gen._run(seed_value, env_id, controller, crisis, anomaly_fx, difficulty, recruit_ok)


func _run(seed_value: int, env_id: String, controller: String, crisis: Dictionary, anomaly_fx: Dictionary,
		difficulty: int, recruit_ok: bool) -> Dictionary:
	r.seed = seed_value
	biome = env_id
	crisis_id = str(crisis.get("id", ""))
	noise.seed = seed_value
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	if biome == "neon_sprawl":
		w = r.randi_range(44, 54)
		h = r.randi_range(32, 40)
	else:
		w = r.randi_range(38, 50)
		h = r.randi_range(28, 36)
	g = []
	for z in h:
		var row := []
		for x in w:
			row.append("#" if x == 0 or z == 0 or x == w - 1 or z == h - 1 else ".")
		g.append(row)
	pad = Vector2i(w / 2 - 1, h - 9)
	spawn = Vector2i(w / 2, h - 5)
	match biome:
		"neon_sprawl":
			_city()
		"toxic_swamp":
			_swamp()
		"ad_desert":
			_desert()
		"rust_canyon":
			_canyon()
		"crystal_moon":
			_crystal()
		_:
			_desert()
	if biome != "neon_sprawl":
		_settlement()
	_landing_zone()
	_services()
	_population(controller, crisis, anomaly_fx, difficulty, recruit_ok)
	_connect()
	var out := []
	for row in g:
		out.append("".join(PackedStringArray(row)))
	return {"layout": out, "w": w, "h": h}


# --- helpers ------------------------------------------------------------------------------

func at(x: int, z: int) -> String:
	if x < 0 or z < 0 or x >= w or z >= h:
		return "#"
	return g[z][x]


func put(x: int, z: int, c: String) -> void:
	if x > 0 and z > 0 and x < w - 1 and z < h - 1:
		g[z][x] = c


func is_free(x: int, z: int) -> bool:
	return at(x, z) == "." and not _near_pad(x, z)


func _near_pad(x: int, z: int) -> bool:
	return absi(x - (pad.x + 1)) <= 2 and z >= pad.y - 1 and z <= spawn.y + 1


func rect_free(x0: int, z0: int, rw: int, rh: int) -> bool:
	for z in range(z0, z0 + rh):
		for x in range(x0, x0 + rw):
			if not is_free(x, z):
				return false
	return true


func fill_rect(x0: int, z0: int, rw: int, rh: int, c: String) -> void:
	for z in range(z0, z0 + rh):
		for x in range(x0, x0 + rw):
			put(x, z, c)


func scatter(c: String, count: int, z_min: int = 2, z_max: int = -1, spacing: int = 1) -> void:
	if z_max < 0:
		z_max = h - 3
	for i in count:
		for attempt in 30:
			var x := r.randi_range(1, w - 2)
			var z := r.randi_range(z_min, z_max)
			if is_free(x, z) and (spacing <= 0 or _clear_around(x, z, spacing)):
				put(x, z, c)
				break


func _clear_around(x: int, z: int, rad: int) -> bool:
	for dz in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var c := at(x + dx, z + dz)
			if c != "." and c != "," and c != "_":
				return false
	return true


func cluster(c: String, cx: int, cz: int, count: int, radius: int) -> void:
	for i in count:
		var x := cx + r.randi_range(-radius, radius)
		var z := cz + r.randi_range(-radius, radius)
		if is_free(x, z):
			put(x, z, c)


# --- biomes -------------------------------------------------------------------------------

func _city() -> void:
	# Avenues: a jittered grid of 2-wide streets; blocks between them get buildings.
	var xs := [1]
	var x := 1
	while x < w - 8:
		x += r.randi_range(8, 11)
		xs.append(mini(x, w - 3))
	var zs := [1]
	var z := 1
	while z < h - 12:
		z += r.randi_range(7, 9)
		zs.append(z)
	for sx in xs:
		for zz in range(1, h - 1):
			put(sx, zz, ",")
			put(sx + 1, zz, ",")
	for sz in zs:
		for xx in range(1, w - 1):
			put(xx, sz, ",")
			put(xx, sz + 1, ",")
	# Blocks (the strip south of the last avenue counts too; the pad clears its own space).
	zs.append(h - 1)
	for bi in range(xs.size() - 1):
		for bj in range(zs.size() - 1):
			var x0: int = xs[bi] + 3
			var x1: int = xs[bi + 1] - 2
			var z0: int = zs[bj] + 3
			var z1: int = zs[bj + 1] - 2
			if x1 - x0 < 2 or z1 - z0 < 2:
				continue
			var roll := r.randf()
			if roll < 0.16:
				_plaza(x0, z0, x1, z1)
			elif roll < 0.32:
				_market(x0, z0, x1, z1)
			else:
				# One or two buildings with an alley between, sidewalk dressing around.
				if x1 - x0 >= 6 and r.randf() < 0.5:
					var mid := (x0 + x1) / 2
					fill_rect(x0, z0, mid - x0, z1 - z0 + 1, "b")
					fill_rect(mid + 1, z0, x1 - mid, z1 - z0 + 1, "b")
					cluster("j", mid, (z0 + z1) / 2, 2, 1)
				else:
					fill_rect(x0, z0, x1 - x0 + 1, z1 - z0 + 1, "b")
	# Sidewalk dressing along the avenues (lamps alternate sides to respect the
	# Mobile renderer's 8-lights-per-mesh budget).
	var k := 0
	for sx in xs:
		for zz in range(2, h - 2, 3):
			k += 1
			var side: int = -1 if k % 2 == 0 else 2
			var px: int = sx + side
			if is_free(px, zz):
				put(px, zz, "L" if k % 3 == 0 else ["j", "q", "i", "w", "v", "g", "A", "j"][r.randi() % 8])
	# Crosswalk-side vendors and crowds hang around the intersections.
	for sx in xs:
		for sz in zs:
			if r.randf() < 0.35:
				cluster("N", sx + 1, sz + 1, 2, 2)
	scatter("q", 6, 2, h - 10, 1)
	scatter("g", 6, 2, h - 6, 1)


func _plaza(x0: int, z0: int, x1: int, z1: int) -> void:
	var cx := (x0 + x1) / 2
	var cz := (z0 + z1) / 2
	put(cx, cz, "h")
	for dx in [-2, 2]:
		put(cx + dx, cz - 1, "w")
		put(cx + dx, cz + 1, "g")
	put(x0, z0, "L")
	put(x1, z1, "L")


func _market(x0: int, z0: int, x1: int, z1: int) -> void:
	for zz in range(z0, z1 + 1, 2):
		for xx in range(x0, x1 + 1, 2):
			if r.randf() < 0.75:
				put(xx, zz, "k")
	put(x0, z1, "L")
	put(x1, z0, "L")
	cluster("N", (x0 + x1) / 2, (z0 + z1) / 2, 3, 2)


func _swamp() -> void:
	noise.frequency = 0.07
	for z in range(1, h - 1):
		for x in range(1, w - 1):
			var n := noise.get_noise_2d(x, z)
			if n > 0.22:
				put(x, z, "~")
	# Boardwalk crossings every few columns/rows.
	for x in range(3, w - 3, r.randi_range(6, 9)):
		for z in range(1, h - 1):
			if at(x, z) == "~":
				put(x, z, ",")
	for z in range(3, h - 3, r.randi_range(6, 8)):
		for x in range(1, w - 1):
			if at(x, z) == "~":
				put(x, z, ",")
	for i in r.randi_range(3, 6):
		var bx := r.randi_range(2, w - 6)
		var bz := r.randi_range(2, h - 14)
		if rect_free(bx - 1, bz - 1, 4, 4):
			fill_rect(bx, bz, 2, 2, "b")
	scatter("g", 14, 2, h - 3, 1)
	scatter("u", 18, 2, h - 3, 0)
	scatter("z", 4, 2, h - 10, 1)
	scatter("L", 7, 2, h - 3, 2)


func _desert() -> void:
	# Glacier ridges of compacted billboard plastic, then shard fields and dead ad towers.
	noise.frequency = 0.07
	for z in range(1, h - 12):
		for x in range(1, w - 1):
			var n := noise.get_noise_2d(x, z)
			if n > 0.36:
				put(x, z, "^")
			elif n > 0.22 and r.randf() < 0.3:
				put(x, z, "c")
	for i in r.randi_range(6, 10):
		cluster("r", r.randi_range(3, w - 4), r.randi_range(3, h - 12), r.randi_range(3, 6), 2)
	for i in r.randi_range(4, 6):
		var x := r.randi_range(3, w - 4)
		var z := r.randi_range(3, h - 12)
		if is_free(x, z) and _clear_around(x, z, 1):
			put(x, z, "Y")
			cluster("z", x, z, 3, 2)
			cluster("A", x, z, 1, 3)
	scatter("A", 6, 2, h - 6, 1)
	scatter("n", 4, 2, h - 6, 1)
	scatter("L", 6, 2, h - 3, 2)
	scatter("c", 10, 2, h - 3, 0)
	scatter("j", 6, 2, h - 3, 0)


func _canyon() -> void:
	noise.frequency = 0.11
	for z in range(1, h - 1):
		for x in range(1, w - 1):
			if noise.get_noise_2d(x, z) > 0.3 and z < h - 10:
				put(x, z, "^")
	for i in r.randi_range(4, 7):
		var cx := r.randi_range(4, w - 5)
		var cz := r.randi_range(4, h - 12)
		cluster("t", cx, cz, 2, 1)
		cluster("p", cx, cz, 2, 2)
		cluster("=", cx, cz, 3, 2)
	for i in r.randi_range(3, 5):
		var bx := r.randi_range(2, w - 6)
		var bz := r.randi_range(h - 16, h - 11)
		if rect_free(bx - 1, bz - 1, 4, 4):
			fill_rect(bx, bz, 2, 2, "b")
	scatter("r", 12, 2, h - 3, 0)
	scatter("L", 6, 2, h - 3, 2)
	scatter("v", 4, 2, h - 6, 1)


func _crystal() -> void:
	noise.frequency = 0.08
	for z in range(1, h - 1):
		for x in range(1, w - 1):
			var n := noise.get_noise_2d(x, z)
			if n > 0.38:
				put(x, z, "~")
			elif n > 0.18 and r.randf() < 0.35:
				put(x, z, "c")
	for i in r.randi_range(3, 5):
		scatter("o", 1, 2, h - 6, 2)
	scatter("n", 3, 2, h - 6, 1)
	scatter("L", 6, 2, h - 3, 2)
	scatter("z", 4, 2, h - 8, 1)


# --- common ---------------------------------------------------------------------------------

## The rows between the spawn and the bottom edge sit right in front of the camera:
## dress them so the diorama has a foreground (lamps, benches, junk, stalls, plants).
func _foreground() -> void:
	var options := ["L", "w", "j", "=", "k", "g", "i", "j", "N", "t" if biome == "rust_canyon" else "u" if biome == "toxic_swamp" else "c" if biome == "crystal_moon" else "r"]
	for z in range(spawn.y + 1, h - 1):
		for x in range(1, w - 1, 2):
			if r.randf() < 0.45 and is_free(x, z) and _clear_around(x, z, 0):
				put(x, z, options[r.randi() % options.size()])


## Outside the Sprawl, a little frontier town grows around the landing pad:
## huts or domes, a market lane, lamps, benches and junk - then the wilds beyond.
func _settlement() -> void:
	var cx := pad.x + 1
	var cz := pad.y + 1
	var hut := "o" if biome == "crystal_moon" or biome == "ad_desert" else "b"
	var spots := [Vector2i(-9, -4), Vector2i(8, -4), Vector2i(-10, 2), Vector2i(9, 2), Vector2i(-5, -8), Vector2i(4, -8)]
	spots.shuffle()
	for i in r.randi_range(3, 5):
		var o: Vector2i = spots[i]
		var x := cx + o.x
		var z := cz + o.y
		if hut == "b":
			if rect_free(x - 1, z - 1, 4, 4):
				fill_rect(x, z, 2, 2, "b")
		elif is_free(x, z) and _clear_around(x, z, 1):
			put(x, z, "o")
	# Market lane north of the pad.
	var lane_z := cz - 6
	for x in range(cx - 6, cx + 7, 2):
		if r.randf() < 0.6 and is_free(x, lane_z):
			put(x, lane_z, "k")
	cluster("N", cx, lane_z + 1, 4, 3)
	for o in [Vector2i(-7, -6), Vector2i(7, -6), Vector2i(-6, 2), Vector2i(6, 2)]:
		if is_free(cx + o.x, cz + o.y):
			put(cx + o.x, cz + o.y, "L")
	cluster("w", cx, cz - 3, 2, 5)
	cluster("j", cx, cz - 2, 3, 7)
	cluster("=", cx, cz, 3, 8)
	cluster("i", cx, cz - 4, 1, 4)

func _landing_zone() -> void:
	for z in range(pad.y - 1, spawn.y + 2):
		for x in range(pad.x - 1, pad.x + 4):
			put(x, z, ".")
	for z in range(pad.y, pad.y + 3):
		for x in range(pad.x, pad.x + 3):
			put(x, z, "D")
	put(spawn.x, spawn.y, "P")


func _place_near(c: String, x: int, z: int) -> void:
	for attempt in 30:
		var spread := 1 if attempt < 10 else 2
		var px := clampi(x + r.randi_range(-spread, spread), 1, w - 2)
		var pz := clampi(z + r.randi_range(-spread, spread), 1, h - 2)
		if at(px, pz) == "." and not _near_pad(px, pz):
			put(px, pz, c)
			return


func _services() -> void:
	_place_near("V", pad.x - 3, pad.y)
	_place_near("m", pad.x + 5, pad.y)
	_place_near("M", pad.x - 3, pad.y + 3)
	_place_near("T", pad.x + 5, pad.y + 3)
	_place_near("L", pad.x - 2, pad.y - 2)
	_place_near("L", pad.x + 4, pad.y - 2)
	_place_near("L", pad.x - 2, spawn.y + 1)
	_place_near("L", pad.x + 4, spawn.y + 1)
	_place_near("=", pad.x - 3, pad.y + 1)
	_place_near("w", pad.x + 5, spawn.y)
	_place_near("j", pad.x - 3, spawn.y)
	_place_near("N", pad.x - 2, spawn.y - 1)
	_place_near("N", pad.x + 4, pad.y + 4)
	if biome == "neon_sprawl":
		# Landing plaza: a giant hologram and benches right beside the pad - the first thing you see.
		_place_near("h", pad.x + 5, pad.y + 1)
		_place_near("w", pad.x - 3, pad.y + 4)
		_place_near("k", pad.x - 4, pad.y - 2)
		_place_near("L", pad.x + 2, pad.y - 3)
	_foreground()
	scatter("A", 3 + r.randi() % 3 + (6 if crisis_id == "ad_overload" else 0), 2, h - 6, 1)
	scatter("X", 2 + r.randi() % 3, 2, h - 10, 1)
	scatter("S", 2 + r.randi() % 3, 2, h - 8, 1)
	scatter("=", 6, 2, h - 3, 0)
	scatter("j", 5, 2, h - 3, 0)


func _population(controller: String, crisis: Dictionary, fx: Dictionary, difficulty: int, recruit_ok: bool) -> void:
	var crowd := 10 if biome == "neon_sprawl" else 6
	for i in crowd + r.randi() % 6:
		scatter("N", 1, 2, h - 3, 0)
	if recruit_ok and r.randf() < 0.6:
		scatter("W", 1, 2, h - 10, 1)
	var table := {
		"paragon": {"G": 4}, "halcyon": {"E": 3, "H": 1}, "gristle": {"B": 5, "G": 1},
		"oxy": {"G": 2, "E": 2}, "lumen": {"G": 2, "E": 2}, "": {"R": 4, "B": 2}}
	var t: Dictionary = table.get(controller, table[""])
	var mult := float(crisis.get("enemy_mult", 1.0)) * (0.8 + 0.25 * difficulty)
	for ch in t:
		for i in roundi(int(t[ch]) * mult):
			scatter(ch, 1, 2, h - 13, 0)
	for i in int(fx.get("extra_bugs", 0)):
		scatter("B", 1, 2, h - 13, 0)


## Flood fill from the spawn; carve a path from any unreachable pocket to the reachable area.
func _connect() -> void:
	var walk := func(c: String) -> bool:
		return not ["#", "b", "~", "^", " "].has(c)
	for pass_i in 6:
		var seen := {}
		var stack := [spawn]
		seen[spawn] = true
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + d
				if not seen.has(q) and walk.call(at(q.x, q.y)):
					seen[q] = true
					stack.append(q)
		var orphan := Vector2i(-1, -1)
		for z in range(1, h - 1):
			for x in range(1, w - 1):
				if walk.call(at(x, z)) and not seen.has(Vector2i(x, z)):
					orphan = Vector2i(x, z)
					break
			if orphan.x >= 0:
				break
		if orphan.x < 0:
			return
		# Walk a straight-ish path from the orphan toward the spawn, opening blockers.
		var cur := orphan
		var guard := 0
		while not seen.has(cur) and guard < 200:
			guard += 1
			var dx := signi(spawn.x - cur.x)
			var dz := signi(spawn.y - cur.y)
			cur += Vector2i(dx, 0) if absi(spawn.x - cur.x) > absi(spawn.y - cur.y) else Vector2i(0, dz)
			if not walk.call(at(cur.x, cur.y)):
				put(cur.x, cur.y, ",")
	# Anything still unreachable after a few passes becomes scenery (water/rock).
