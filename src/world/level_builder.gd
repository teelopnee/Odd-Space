class_name LevelBuilder
extends RefCounted
## Builds HD-2D level geometry from an ASCII layout. One char = one 2x2 m tile.
## Edit layouts as plain text (great on a tablet); the builder does the 3D.
##
## STRUCTURE           PROPS                         ACTORS / MARKERS
##   #  wall            =  crate                      1-4 spawn (cryo_bay/cargo_hold/medbay/server_room)
##   .  floor           S  stash (stealable)          P   default player spawn
##   ' ' void           C  cryo pod                   D   dock / landing pad (3x3 block)
##   b  building block  V  vending machine (AIR-O-MAT) E repo drone   G compliance officer
##                      A  holo ad billboard          B   grub        H debt collector
##                      L  neon light                 R   pirate      N civilian
##                      T  terminal (causality log)   M   merchant    W recruitable crew
##                      K  pillar   X explosive tank  m   med-station
##   planet decor: r rock  c crystal  u mushroom  p pipe  t tank  n antenna  z ruin
##
## Walls whose NORTH neighbour is floor are built LOW (the camera looks north),
## so they never hide the player - the classic HD-2D diorama cut-away.

const TILE := 2.0
const WALL_H := 3.4
const LOW_WALL_H := 0.7
const FLOOR_T := 0.3
const CHUNK := 6
const LAYER_WORLD := 1
const LAYER_OCCLUDER := 128
const WALKABLE_EXCLUDE := ["#", " ", "b"]
const SPAWN_CHARS := {"1": "cryo_bay", "2": "cargo_hold", "3": "medbay", "4": "server_room", "P": "default"}
const ACTOR_CHARS := ["E", "G", "B", "H", "R", "N", "M", "W"]

var root: Node3D
var palette: Dictionary
var rng := RandomNumberGenerator.new()
var outdoor := false
var owner_faction := ""
var grid: Array[String] = []
var width := 0
var height := 0
var result := {"spawns": {}, "entities": [], "dock": Vector3.ZERO, "has_dock": false, "size": Vector2.ZERO}

var _mats: Dictionary = {}
var _neon_index := 0
var _walls_body: StaticBody3D


func _init(p_root: Node3D, p_palette: Dictionary, p_seed: int, p_outdoor: bool = false, p_owner_faction: String = "") -> void:
	root = p_root
	palette = p_palette
	rng.seed = p_seed
	outdoor = p_outdoor
	owner_faction = p_owner_faction


func build(layout: Array) -> Dictionary:
	width = 0
	for row in layout:
		width = maxi(width, str(row).length())
	for row in layout:
		grid.append(str(row).rpad(width, " "))
	height = grid.size()
	result.size = Vector2(width * TILE, height * TILE)
	_make_materials()
	_walls_body = StaticBody3D.new()
	_walls_body.name = "Walls"
	_walls_body.collision_layer = LAYER_WORLD
	root.add_child(_walls_body)
	_build_floor()
	_build_walls()
	_build_buildings()
	_build_cells()
	_build_floor_collision()
	return result


# --- Grid helpers ----------------------------------------------------------------------

func cell(x: int, z: int) -> String:
	if z < 0 or z >= height or x < 0 or x >= width:
		return " "
	return grid[z][x]


func walkable(x: int, z: int) -> bool:
	return not WALKABLE_EXCLUDE.has(cell(x, z))


func center(x: int, z: int) -> Vector3:
	return Vector3(x * TILE + TILE * 0.5, 0.0, z * TILE + TILE * 0.5)


func pcolor(key: String, fallback: String = "#808080") -> Color:
	return Color.from_string(str(palette.get(key, fallback)), Color.GRAY)


func next_neon() -> Color:
	var list: Array = palette.get("neon", ["#ff3ec8", "#3ee6ff"])
	_neon_index += 1
	return Color.from_string(str(list[_neon_index % list.size()]), Color.MAGENTA)


# --- Materials ---------------------------------------------------------------------------

func _tex(file_name: String) -> Texture2D:
	var path := "res://assets/textures/%s.png" % file_name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _textured(tex_name: String, color: Color, scale: float = 0.5, rough: float = 0.75, metal: float = 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _tex(tex_name)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = rough
	m.metallic = metal
	return m


func emissive(color: Color, energy: float = 3.0) -> StandardMaterial3D:
	var key := "emit_%s_%.1f" % [color.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


func _make_materials() -> void:
	var floor_tex := "ground_rock" if outdoor else "floor_metal"
	var floor_mat := _textured(floor_tex, Color.WHITE, 0.5, 0.85, 0.1 if outdoor else 0.35)
	floor_mat.vertex_color_use_as_albedo = true
	_mats["floor"] = floor_mat
	_mats["wall"] = _textured("rock_cliff" if outdoor else "wall_panel", pcolor("wall", "#4a3f6b"), 0.5, 0.8, 0.25)
	_mats["crate"] = _textured("crate", Color(0.85, 0.75, 0.6), 0.75, 0.8, 0.1)
	_mats["metal"] = _textured("wall_panel", Color(0.55, 0.58, 0.68), 1.0, 0.45, 0.6)
	_mats["dark"] = _textured("wall_panel", Color(0.18, 0.16, 0.24), 1.0, 0.6, 0.4)
	_mats["rock"] = _textured("rock_cliff", pcolor("ground_alt", "#556070").lightened(0.1), 0.6, 0.95, 0.0)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.4, 0.95, 1.0, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = Color(0.3, 0.9, 1.0)
	glass.emission_energy_multiplier = 1.5
	glass.roughness = 0.1
	_mats["glass"] = glass


# --- Primitive helpers ---------------------------------------------------------------------

func add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_y: float = 0.0, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func cylinder(radius: float, h: float, sides: int = 10, top_radius: float = -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius if top_radius < 0.0 else top_radius
	c.bottom_radius = radius
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	return c


func add_box_collider(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


func static_body(pos: Vector3, layer: int = LAYER_WORLD) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = pos
	root.add_child(body)
	return body


func add_light(pos: Vector3, color: Color, energy: float = 2.0, light_range: float = 7.0, shadows: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadows
	l.position = pos
	root.add_child(l)
	return l


# --- Floor ----------------------------------------------------------------------------------

func _build_floor() -> void:
	var a := pcolor("ground", "#2a2440")
	var b := pcolor("ground_alt", "#352c52")
	var gap := 1.0 if outdoor else 0.97
	var tile_mesh := box(Vector3(TILE * gap, FLOOR_T, TILE * gap))
	for cz in range(0, height, CHUNK):
		for cx in range(0, width, CHUNK):
			var positions: Array[Vector3] = []
			var colors: Array[Color] = []
			for z in range(cz, mini(cz + CHUNK, height)):
				for x in range(cx, mini(cx + CHUNK, width)):
					var c := cell(x, z)
					if c == " " or c == "#":
						continue
					var p := center(x, z)
					p.y = -FLOOR_T * 0.5
					if outdoor:
						p.y += rng.randf_range(-0.04, 0.04)
					positions.append(p)
					var base := a if (x + z) % 2 == 0 else b
					colors.append(base.lightened(rng.randf_range(-0.05, 0.08)))
			if positions.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = tile_mesh
			mm.instance_count = positions.size()
			for i in positions.size():
				mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
				mm.set_instance_color(i, colors[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Floor_%d_%d" % [cx, cz]
			mmi.multimesh = mm
			mmi.material_override = _mats["floor"]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)


func _build_floor_collision() -> void:
	var body := static_body(Vector3(width * TILE * 0.5, -0.5, height * TILE * 0.5))
	body.name = "FloorCollision"
	add_box_collider(body, Vector3(width * TILE, 1.0, height * TILE), Vector3.ZERO)


# --- Walls ------------------------------------------------------------------------------------

func _wall_is_low(x: int, z: int) -> bool:
	return walkable(x, z - 1)


func _build_walls() -> void:
	for z in height:
		var x := 0
		while x < width:
			if cell(x, z) != "#":
				x += 1
				continue
			var low := _wall_is_low(x, z)
			var start := x
			while x < width and cell(x, z) == "#" and _wall_is_low(x, z) == low:
				x += 1
			_wall_run(start, x - 1, z, low)


func _wall_run(x0: int, x1: int, z: int, low: bool) -> void:
	var length := (x1 - x0 + 1) * TILE
	var h := LOW_WALL_H if low else WALL_H
	var cx := (x0 + x1 + 1) * TILE * 0.5
	var cz := z * TILE + TILE * 0.5
	if outdoor and not low:
		h = WALL_H + rng.randf_range(-0.6, 1.2)
	add_mesh(root, box(Vector3(length, h, TILE)), _mats["wall"], Vector3(cx, h * 0.5, cz))
	# Collision is always full height so low walls still block movement.
	add_box_collider(_walls_body, Vector3(length, WALL_H, TILE), Vector3(cx, WALL_H * 0.5, cz))
	var faces_room := walkable(x0, z + 1) or walkable(x1, z + 1)
	if outdoor:
		return
	if low:
		# Neon cap strip on the ledge.
		add_mesh(root, box(Vector3(length, 0.06, 0.12)), emissive(next_neon(), 2.5),
			Vector3(cx, h + 0.03, cz + TILE * 0.5 - 0.06), 0.0, false)
	elif faces_room:
		# Neon trim along the top of back walls, plus a darker skirting.
		add_mesh(root, box(Vector3(length, 0.08, 0.06)), emissive(next_neon(), 3.0),
			Vector3(cx, h - 0.35, cz + TILE * 0.5 + 0.03), 0.0, false)
		add_mesh(root, box(Vector3(length, 0.3, 0.1)), _mats["dark"], Vector3(cx, 0.15, cz + TILE * 0.5 + 0.05), 0.0, false)


# --- Buildings (planets) --------------------------------------------------------------------

func _build_buildings() -> void:
	var seen := {}
	for z in height:
		for x in width:
			if cell(x, z) != "b" or seen.has(Vector2i(x, z)):
				continue
			# Grow a rectangle right then down.
			var x1 := x
			while cell(x1 + 1, z) == "b":
				x1 += 1
			var z1 := z
			var full := true
			while full:
				for xi in range(x, x1 + 1):
					if cell(xi, z1 + 1) != "b":
						full = false
						break
				if full:
					z1 += 1
			for zz in range(z, z1 + 1):
				for xx in range(x, x1 + 1):
					seen[Vector2i(xx, zz)] = true
			_building(x, z, x1, z1)


func _building(x0: int, z0: int, x1: int, z1: int) -> void:
	var w := (x1 - x0 + 1) * TILE - 0.3
	var d := (z1 - z0 + 1) * TILE - 0.3
	var h := rng.randf_range(4.0, 8.5)
	var pos := Vector3((x0 + x1 + 1) * TILE * 0.5, 0.0, (z0 + z1 + 1) * TILE * 0.5)
	var body := static_body(pos, LAYER_WORLD | LAYER_OCCLUDER)
	body.name = "Building"
	add_box_collider(body, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	var mat := _textured("building_panel", pcolor("wall", "#4a3f6b").lightened(rng.randf_range(-0.1, 0.15)), 0.5, 0.7, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	var roof_mat := mat.duplicate() as StandardMaterial3D
	roof_mat.albedo_color = roof_mat.albedo_color.darkened(0.3)
	add_mesh(body, box(Vector3(w, h, d)), mat, Vector3(0, h * 0.5, 0))
	add_mesh(body, box(Vector3(w + 0.3, 0.25, d + 0.3)), roof_mat, Vector3(0, h + 0.12, 0))
	var deco: Array[Node] = []
	# Windows on the camera-facing (south) side.
	var win_col := next_neon().lerp(Color(1, 0.9, 0.6), 0.5)
	var floors := int(h / 1.4)
	var cols := int(w / 1.1)
	for fy in floors:
		for fx in cols:
			if rng.randf() < 0.45:
				continue
			var wp := Vector3(-w * 0.5 + 0.55 + fx * 1.1, 0.9 + fy * 1.4, d * 0.5 + 0.02)
			deco.append(add_mesh(body, box(Vector3(0.55, 0.6, 0.04)), emissive(win_col, 1.6), wp, 0.0, false))
	# Neon corporate board.
	var sign_color := next_neon()
	var fid := owner_faction
	if fid != "" and DataDB.factions.has(fid):
		sign_color = DataDB.faction_color(fid)
	var label := Label3D.new()
	label.text = DataDB.factions.get(fid, {}).get("short", "OPEN 25/8") if fid != "" else ["NOODLES", "BAR", "CLINIC?", "PAWN", "CRYO-MOTEL"][rng.randi() % 5]
	label.font_size = 96
	label.pixel_size = 0.01
	label.modulate = sign_color * 2.2
	label.outline_size = 0
	label.position = Vector3(0, minf(h - 0.8, 3.2), d * 0.5 + 0.08)
	body.add_child(label)
	deco.append(label)
	deco.append(add_mesh(body, box(Vector3(minf(w - 0.4, 3.4), 0.08, 0.06)), emissive(sign_color, 4.0), Vector3(0, label.position.y - 0.5, d * 0.5 + 0.06), 0.0, false))
	body.set_meta("fade_mats", [mat, roof_mat])
	body.set_meta("fade_hide", deco)
	if rng.randf() < 0.4:
		add_mesh(body, cylinder(0.05, 2.0, 4), _mats["metal"], Vector3(w * 0.3, h + 1.0, 0))
		add_mesh(body, box(Vector3(0.18, 0.18, 0.18)), emissive(Color(1, 0.2, 0.2), 5.0), Vector3(w * 0.3, h + 2.0, 0), 0.0, false)


# --- Cells: props, lights, markers --------------------------------------------------------

func _build_cells() -> void:
	var dock_tiles: Array[Vector3] = []
	for z in height:
		for x in width:
			var c := cell(x, z)
			var p := center(x, z)
			if SPAWN_CHARS.has(c):
				result.spawns[SPAWN_CHARS[c]] = p
			elif ACTOR_CHARS.has(c):
				result.entities.append({"char": c, "pos": p})
			match c:
				"D":
					dock_tiles.append(p)
				"=":
					_crate(p, false)
				"S":
					_crate(p, true)
				"C":
					_cryo_pod(p)
				"V":
					_vending(p)
				"A":
					_ad_sign(p)
				"L":
					_lamp(p)
				"T":
					_terminal(p)
				"K":
					_pillar(p)
				"X":
					_tank(p, true)
				"t":
					_tank(p, false)
				"m":
					_med_station(p)
				"r":
					_rock(p)
				"c":
					_crystal(p)
				"u":
					_mushroom(p)
				"p":
					_pipe(p)
				"n":
					_antenna(p)
				"z":
					_ruin(p)
	if not dock_tiles.is_empty():
		var sum := Vector3.ZERO
		for t in dock_tiles:
			sum += t
		_dock(sum / dock_tiles.size())


func _crate(p: Vector3, stash: bool) -> void:
	var s := rng.randf_range(1.0, 1.35)
	var body := static_body(p)
	var mat: Material = _mats["crate"]
	if stash:
		mat = _textured("crate", DataDB.faction_color(owner_faction if owner_faction != "" else "halcyon").lerp(Color.WHITE, 0.45), 0.75, 0.8, 0.1)
	var rot := rng.randf_range(-0.3, 0.3)
	add_mesh(body, box(Vector3.ONE * s), mat, Vector3(0, s * 0.5, 0), rot)
	add_box_collider(body, Vector3.ONE * s, Vector3(0, s * 0.5, 0))
	if not stash and rng.randf() < 0.35:
		var s2 := s * 0.7
		add_mesh(body, box(Vector3.ONE * s2), mat, Vector3(rng.randf_range(-0.1, 0.1), s + s2 * 0.5, 0), rot + rng.randf_range(-0.4, 0.4))
	if stash:
		add_mesh(body, box(Vector3(s * 0.9, 0.06, 0.04)), emissive(Color(1.0, 0.85, 0.2), 3.0), Vector3(0, s * 0.75, s * 0.5 + 0.02), rot, false)
		var it := PropInteractable.new()
		it.kind = "stash"
		it.owner_faction = owner_faction if owner_faction != "" else "halcyon"
		it.prompt = "Inspect Consortium crate"
		it.position = Vector3(0, 0.8, 0)
		body.add_child(it)


func _cryo_pod(p: Vector3) -> void:
	var body := static_body(p)
	add_mesh(body, cylinder(0.65, 0.35, 12), _mats["metal"], Vector3(0, 0.17, 0))
	add_mesh(body, cylinder(0.5, 1.9, 12), _mats["glass"], Vector3(0, 1.3, 0), 0.0, false)
	add_mesh(body, cylinder(0.65, 0.3, 12), _mats["metal"], Vector3(0, 2.4, 0))
	add_mesh(body, cylinder(0.3, 1.6, 8), emissive(Color(0.3, 0.9, 1.0), 1.2), Vector3(0, 1.3, 0), 0.0, false)
	add_box_collider(body, Vector3(1.3, 2.6, 1.3), Vector3(0, 1.3, 0))
	add_light(p + Vector3(0, 1.4, 0.8), Color(0.3, 0.9, 1.0), 0.9, 3.5)
	var it := PropInteractable.new()
	it.kind = "cryo"
	it.prompt = "Read pod label"
	it.position = Vector3(0, 0.8, 0.7)
	body.add_child(it)


func _vending(p: Vector3) -> void:
	var body := static_body(p)
	add_mesh(body, box(Vector3(1.3, 2.1, 0.8)), _mats["metal"], Vector3(0, 1.05, 0))
	var c := DataDB.faction_color("oxy")
	add_mesh(body, box(Vector3(1.0, 1.1, 0.04)), emissive(c, 2.2), Vector3(0, 1.3, 0.41), 0.0, false)
	add_box_collider(body, Vector3(1.3, 2.1, 0.8), Vector3(0, 1.05, 0))
	var label := Label3D.new()
	label.text = "AIR-O-MAT\nby OxyGenix"
	label.font_size = 40
	label.pixel_size = 0.006
	label.modulate = Color(0.05, 0.1, 0.2)
	label.position = Vector3(0, 1.45, 0.44)
	body.add_child(label)
	add_light(p + Vector3(0, 1.4, 1.0), c, 1.2, 4.0)
	var it := PropInteractable.new()
	it.kind = "vending"
	it.owner_faction = "oxy"
	it.prompt = "Use AIR-O-MAT"
	it.position = Vector3(0, 0.8, 0.8)
	body.add_child(it)


func _ad_sign(p: Vector3) -> void:
	var ads: Array = DataDB.ads.get("list", [])
	var ad: Dictionary = ads[rng.randi() % ads.size()] if not ads.is_empty() else {"faction": "lumen", "headline": "LUMEN", "text": "Watch more."}
	var board := ShootableProp.new()
	board.kind = "ad"
	board.owner_faction = ad.get("faction", "lumen")
	board.position = p
	root.add_child(board)
	var col := DataDB.faction_color(board.owner_faction)
	add_mesh(board, cylinder(0.06, 2.0, 6), _mats["dark"], Vector3(0, 1.0, 0))
	var frame := add_mesh(board, box(Vector3(2.4, 1.3, 0.08)), emissive(col.darkened(0.6), 1.0), Vector3(0, 2.6, 0), 0.0, true)
	var border := add_mesh(board, box(Vector3(2.5, 0.06, 0.1)), emissive(col, 4.0), Vector3(0, 3.27, 0), 0.0, false)
	var border2 := add_mesh(board, box(Vector3(2.5, 0.06, 0.1)), emissive(col, 4.0), Vector3(0, 1.93, 0), 0.0, false)
	var head := Label3D.new()
	head.text = ad.get("headline", "")
	head.font_size = 72
	head.pixel_size = 0.0075
	head.modulate = col * 2.5
	head.position = Vector3(0, 2.95, 0.06)
	board.add_child(head)
	var body_text := Label3D.new()
	body_text.text = ad.get("text", "")
	body_text.font_size = 40
	body_text.pixel_size = 0.0065
	body_text.modulate = Color(1.6, 1.6, 1.8)
	body_text.position = Vector3(0, 2.45, 0.06)
	board.add_child(body_text)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.2
	light.omni_range = 6.0
	light.position = Vector3(0, 2.4, 1.0)
	board.add_child(light)
	board.glow_nodes = [frame, border, border2, head, body_text, light]
	board.add_collision(Vector3(2.4, 1.3, 0.3), Vector3(0, 2.6, 0))
	board.flicker = rng.randf() < 0.35


func _lamp(p: Vector3) -> void:
	var col := next_neon()
	if outdoor:
		var body := static_body(p)
		add_mesh(body, cylinder(0.08, 3.2, 6), _mats["dark"], Vector3(0, 1.6, 0))
		add_mesh(body, box(Vector3(0.9, 0.12, 0.3)), emissive(col, 4.0), Vector3(0.3, 3.2, 0), 0.0, false)
		add_box_collider(body, Vector3(0.3, 3.2, 0.3), Vector3(0, 1.6, 0))
		add_light(p + Vector3(0.4, 2.9, 0.2), col, 2.4, 8.0)
	else:
		add_mesh(root, box(Vector3(1.2, 0.08, 0.25)), emissive(col, 5.0), p + Vector3(0, 3.0, 0), 0.0, false)
		add_light(p + Vector3(0, 2.7, 0), col, 2.0, 7.5)


func _terminal(p: Vector3) -> void:
	var body := static_body(p)
	add_mesh(body, box(Vector3(1.1, 1.0, 0.6)), _mats["dark"], Vector3(0, 0.5, 0))
	add_mesh(body, box(Vector3(1.0, 0.7, 0.08)), emissive(Color(0.3, 1.0, 0.6), 2.0), Vector3(0, 1.35, 0.1), -0.0, false)
	add_box_collider(body, Vector3(1.1, 1.0, 0.6), Vector3(0, 0.5, 0))
	add_light(p + Vector3(0, 1.4, 0.8), Color(0.3, 1.0, 0.6), 0.8, 3.0)
	var label := Label3D.new()
	label.text = "CAUSALITY\nLOG"
	label.font_size = 28
	label.pixel_size = 0.006
	label.modulate = Color(0.05, 0.2, 0.1)
	label.position = Vector3(0, 1.35, 0.15)
	body.add_child(label)
	var it := PropInteractable.new()
	it.kind = "terminal"
	it.prompt = "Access Causality terminal"
	it.position = Vector3(0, 0.8, 0.7)
	body.add_child(it)


func _pillar(p: Vector3) -> void:
	var body := static_body(p)
	add_mesh(body, cylinder(0.45, WALL_H, 8), _mats["metal"], Vector3(0, WALL_H * 0.5, 0))
	add_mesh(body, cylinder(0.5, 0.1, 8), emissive(next_neon(), 3.0), Vector3(0, 1.9, 0), 0.0, false)
	add_box_collider(body, Vector3(0.9, WALL_H, 0.9), Vector3(0, WALL_H * 0.5, 0))


func _tank(p: Vector3, explosive: bool) -> void:
	if explosive:
		var tank := ShootableProp.new()
		tank.kind = "tank"
		tank.hp = 15.0
		tank.position = p
		root.add_child(tank)
		add_mesh(tank, cylinder(0.55, 1.5, 10), _textured("hazard", Color(1, 0.85, 0.3), 1.0, 0.5, 0.4), Vector3(0, 0.75, 0))
		add_mesh(tank, cylinder(0.3, 0.2, 8), emissive(Color(1, 0.3, 0.1), 3.0), Vector3(0, 1.6, 0), 0.0, false)
		tank.add_collision(Vector3(1.1, 1.5, 1.1), Vector3(0, 0.75, 0))
	else:
		var body := static_body(p)
		add_mesh(body, cylinder(0.8, 2.2, 12), _mats["metal"], Vector3(0, 1.1, 0))
		add_mesh(body, cylinder(0.82, 0.12, 12), emissive(next_neon(), 2.0), Vector3(0, 1.6, 0), 0.0, false)
		add_box_collider(body, Vector3(1.5, 2.2, 1.5), Vector3(0, 1.1, 0))


func _med_station(p: Vector3) -> void:
	var body := static_body(p)
	add_mesh(body, box(Vector3(1.2, 1.8, 0.7)), _mats["metal"], Vector3(0, 0.9, 0))
	var green := Color(0.3, 1.0, 0.5)
	add_mesh(body, box(Vector3(0.6, 0.18, 0.04)), emissive(green, 4.0), Vector3(0, 1.4, 0.37), 0.0, false)
	add_mesh(body, box(Vector3(0.18, 0.6, 0.04)), emissive(green, 4.0), Vector3(0, 1.4, 0.37), 0.0, false)
	add_box_collider(body, Vector3(1.2, 1.8, 0.7), Vector3(0, 0.9, 0))
	add_light(p + Vector3(0, 1.4, 0.9), green, 1.0, 3.5)
	var it := PropInteractable.new()
	it.kind = "medstation"
	it.owner_faction = "halcyon"
	it.prompt = "Use MediCredit(tm) station"
	it.position = Vector3(0, 0.8, 0.7)
	body.add_child(it)


func _rock(p: Vector3) -> void:
	var body := static_body(p + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)))
	var s := rng.randf_range(0.7, 1.4)
	var rock := SphereMesh.new()
	rock.radius = s
	rock.height = s * 1.3
	rock.radial_segments = 6
	rock.rings = 3
	add_mesh(body, rock, _mats["rock"], Vector3(0, s * 0.4, 0), rng.randf() * TAU)
	add_box_collider(body, Vector3(s * 1.5, s, s * 1.5), Vector3(0, s * 0.5, 0))


func _crystal(p: Vector3) -> void:
	var body := static_body(p)
	var col := next_neon()
	for i in 3:
		var hgt := rng.randf_range(0.8, 2.2)
		var m := cylinder(0.25, hgt, 5, 0.0)
		var mi := add_mesh(body, m, emissive(col, 1.8), Vector3(rng.randf_range(-0.4, 0.4), hgt * 0.5, rng.randf_range(-0.4, 0.4)), rng.randf() * TAU)
		mi.rotation.z = rng.randf_range(-0.35, 0.35)
	add_light(p + Vector3(0, 1.0, 0), col, 1.0, 4.0)
	add_box_collider(body, Vector3(1.2, 2.0, 1.2), Vector3(0, 1.0, 0))


func _mushroom(p: Vector3) -> void:
	var body := static_body(p)
	var hgt := rng.randf_range(1.2, 2.6)
	add_mesh(body, cylinder(0.18, hgt, 6), _mats["rock"], Vector3(0, hgt * 0.5, 0))
	var cap := SphereMesh.new()
	cap.radius = rng.randf_range(0.7, 1.1)
	cap.height = cap.radius
	cap.radial_segments = 8
	cap.rings = 3
	cap.is_hemisphere = true
	add_mesh(body, cap, emissive(next_neon().darkened(0.3), 1.2), Vector3(0, hgt, 0))
	add_box_collider(body, Vector3(0.6, hgt, 0.6), Vector3(0, hgt * 0.5, 0))


func _pipe(p: Vector3) -> void:
	var body := static_body(p)
	var m := cylinder(0.3, TILE, 8)
	var mi := add_mesh(body, m, _mats["metal"], Vector3(0, 0.45, 0))
	mi.rotation.z = PI * 0.5
	var collar := add_mesh(body, cylinder(0.36, 0.2, 8), _mats["dark"], Vector3(0, 0.45, 0))
	collar.rotation.z = PI * 0.5
	add_box_collider(body, Vector3(TILE, 0.9, 0.7), Vector3(0, 0.45, 0))


func _antenna(p: Vector3) -> void:
	var body := static_body(p)
	add_mesh(body, cylinder(0.08, 4.0, 5), _mats["metal"], Vector3(0, 2.0, 0))
	add_mesh(body, cylinder(0.6, 0.1, 8, 0.1), _mats["metal"], Vector3(0, 3.6, 0))
	add_mesh(body, box(Vector3(0.15, 0.15, 0.15)), emissive(Color(1, 0.2, 0.3), 6.0), Vector3(0, 4.1, 0), 0.0, false)
	add_box_collider(body, Vector3(0.4, 4.0, 0.4), Vector3(0, 2.0, 0))


func _ruin(p: Vector3) -> void:
	var body := static_body(p)
	for i in rng.randi_range(2, 3):
		var s := Vector3(rng.randf_range(0.5, 1.6), rng.randf_range(0.4, 2.4), rng.randf_range(0.4, 1.0))
		add_mesh(body, box(s), _mats["wall"], Vector3(rng.randf_range(-0.4, 0.4), s.y * 0.5, rng.randf_range(-0.3, 0.3)), rng.randf_range(-0.6, 0.6))
	add_box_collider(body, Vector3(1.6, 1.6, 1.2), Vector3(0, 0.8, 0))


func _dock(p: Vector3) -> void:
	result.dock = p
	result.has_dock = true
	add_mesh(root, cylinder(TILE * 1.45, 0.08, 24), _mats["dark"], p + Vector3(0, 0.04, 0), 0.0, false)
	add_mesh(root, cylinder(TILE * 1.5, 0.05, 24), emissive(Color(1.0, 0.75, 0.2), 2.5), p + Vector3(0, 0.02, 0), 0.0, false)
	_odd_duck(p + Vector3(0, 0, -0.6))
	var it := PropInteractable.new()
	it.kind = "dock"
	it.prompt = "Board the Odd Duck"
	it.radius = 2.4
	it.position = p + Vector3(0, 0.8, 1.6)
	root.add_child(it)


## The Odd Duck: a second-hand, duck-shaped freighter built from primitives.
func _odd_duck(p: Vector3) -> void:
	var ship := static_body(p)
	ship.name = "OddDuck"
	var hull_mat := _textured("wall_panel", Color(1.0, 0.72, 0.25), 1.0, 0.5, 0.5)
	var hull := CapsuleMesh.new()
	hull.radius = 0.95
	hull.height = 4.2
	hull.radial_segments = 10
	hull.rings = 4
	var hull_mi := add_mesh(ship, hull, hull_mat, Vector3(0, 1.35, 0))
	hull_mi.rotation.z = PI * 0.5
	var head := SphereMesh.new()
	head.radius = 0.75
	head.height = 1.5
	head.radial_segments = 10
	head.rings = 5
	add_mesh(ship, head, hull_mat, Vector3(1.9, 2.2, 0))
	var visor := add_mesh(ship, head, _mats["glass"], Vector3(2.05, 2.35, 0.25), 0.0, false)
	visor.scale = Vector3.ONE * 0.55
	var beak := PrismMesh.new()
	beak.size = Vector3(0.6, 0.9, 0.5)
	var beak_mi := add_mesh(ship, beak, emissive(Color(1.0, 0.45, 0.1), 0.6), Vector3(2.75, 2.1, 0))
	beak_mi.rotation.z = -PI * 0.5
	add_mesh(ship, box(Vector3(1.6, 0.12, 3.6)), hull_mat, Vector3(-0.3, 1.2, 0))
	for side in [-1.0, 1.0]:
		var engine := add_mesh(ship, cylinder(0.32, 0.9, 8), _mats["metal"], Vector3(-1.9, 1.15, side * 1.0))
		engine.rotation.z = PI * 0.5
		var flame := add_mesh(ship, cylinder(0.26, 0.05, 8), emissive(Color(0.3, 0.8, 1.0), 6.0), Vector3(-2.37, 1.15, side * 1.0), 0.0, false)
		flame.rotation.z = PI * 0.5
		add_mesh(ship, box(Vector3(0.15, 0.6, 0.15)), _mats["dark"], Vector3(0.6, 0.3, side * 0.6))
	var label := Label3D.new()
	label.text = "THE ODD DUCK"
	label.font_size = 48
	label.pixel_size = 0.006
	label.modulate = Color(0.25, 0.1, 0.05)
	label.position = Vector3(-0.3, 1.45, 0.97)
	ship.add_child(label)
	add_light(p + Vector3(-2.6, 1.2, 0), Color(0.3, 0.8, 1.0), 2.5, 5.0)
	add_box_collider(ship, Vector3(5.6, 2.6, 2.4), Vector3(0.2, 1.3, 0))
