class_name LevelBuilder
extends RefCounted
## Builds HD-2D level geometry from an ASCII layout. One char = one 2x2 m tile.
## Edit layouts as plain text (great on a tablet); the builder does the 3D.
##
## STRUCTURE           PROPS                         ACTORS / MARKERS
##   #  wall            =  crate                      1-4 spawn (cryo_bay/cargo_hold/medbay/server_room)
##   .  floor           S  stash (stealable)          P   default player spawn
##   ,  grate floor     C  cryo pod                   D   dock / landing pad (3x3 block)
##   _  tiled floor     V  vending machine (AIR-O-MAT) E repo drone   G compliance officer
##   O  window to space h  hologram projector
##   ' ' void
##   b  building block
##                      A  holo ad billboard          B   grub        H debt collector
##                      L  neon light                 R   pirate      N civilian
##                      T  terminal (causality log)   M   merchant    W recruitable crew
##                      K  pillar   X explosive tank  m   med-station
##   planet decor: r rock  c crystal  u mushroom  p pipe  t tank  n antenna  z ruin
##   street life : k market stall  q parked hovercar  j trash  g tree  w bench
##                 i street sign  v steam vent  o habitat dome  Y billboard tower
##   terrain     : ~ water/sludge (blocks walking)  ^ cliff / mesa (fades when in the way)
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
const WALKABLE_EXCLUDE := ["#", " ", "b", "O", "~", "^"]
const WATER_SHADER := "res://assets/shaders/water.gdshader"
const STREETS := ["NEON AVE", "DEBT ST", "PASTE BLVD", "OBEY LN", "4TH QTR", "AIR WAY", "COLLATERAL RD", "SYNERGY SQ", "MARKUP ALLEY", "REFUND? NO", "LOYALTY PKWY", "CLAUSE 9 ST"]
const STALL_SIGNS := ["NOODLES", "PASTE", "AIR 2GO", "CHIPS", "REPAIR", "DUMPLINGS", "SYNTH-RAMEN", "PAWN", "FORTUNES", "CRYO-POPS", "IMPLANTS", "TAPES"]
const SHAFT_TEX := "res://assets/textures/light_shaft.png"
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
var _roofs: Array = []  # [top_center: Vector3, half_size: Vector2] per building, for overhead cables


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
	_build_water()
	_build_cliffs()
	_build_cells()
	_build_floor_collision()
	_build_atmosphere()
	if outdoor:
		_build_outdoor()
		_build_cables()
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


func _textured(tex_name: String, color: Color, scale: float = 0.5, rough: float = 0.75, metal: float = 0.2, normal_strength: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _tex(tex_name)
	var n := _tex(tex_name + "_n")
	if n != null and normal_strength > 0.0:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = normal_strength
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
	var floor_tex: String = palette.get("ground_tex", "ground_rock") if outdoor else "floor_metal"
	var floor_mat := _textured(floor_tex, Color.WHITE, 0.5, 0.85 if outdoor else 0.38, 0.1 if outdoor else 0.45, 1.4)
	floor_mat.vertex_color_use_as_albedo = true
	_mats["floor"] = floor_mat
	for kind in [["grate", "floor_grate", 0.5, 0.6], ["tile", "floor_tile", 0.5, 0.2], ["hazard", "hazard", 0.5, 0.5]]:
		var m := _textured(kind[1], Color.WHITE, 0.5, kind[3], 0.3, 1.2)
		m.vertex_color_use_as_albedo = true
		_mats["floor_" + kind[0]] = m
	var path_tex: String = palette.get("path_tex", "floor_grate")
	var path := _textured(path_tex, Color.WHITE, 0.5, 0.35 if path_tex == "asphalt" else 0.7, 0.25, 1.3)
	path.vertex_color_use_as_albedo = true
	_mats["floor_path"] = path
	var water := ShaderMaterial.new()
	water.shader = load(WATER_SHADER)
	water.set_shader_parameter("deep", pcolor("water", "#05060c"))
	water.set_shader_parameter("glow", pcolor("water_glow", "#3ee6ff"))
	water.set_shader_parameter("glow_strength", float(palette.get("water_glow_strength", 0.1)))
	_mats["water"] = water
	_mats["wall"] = _textured("rock_cliff" if outdoor else "wall_panel", pcolor("wall", "#4a3f6b"), 0.5, 0.8, 0.25, 1.6)
	_mats["crate"] = _textured("crate", Color(0.85, 0.75, 0.6), 0.75, 0.8, 0.1, 1.4)
	_mats["metal"] = _textured("wall_panel", Color(0.55, 0.58, 0.68), 1.0, 0.4, 0.6, 1.2)
	_mats["dark"] = _textured("wall_panel", Color(0.18, 0.16, 0.24), 1.0, 0.6, 0.4, 1.2)
	_mats["rock"] = _textured("rock_cliff", pcolor("ground_alt", "#556070").lightened(0.1), 0.6, 0.95, 0.0, 1.8)
	_mats["concrete"] = _textured("concrete", pcolor("wall", "#4a3f6b").lightened(0.15), 0.5, 0.85, 0.05, 1.2)
	var pipe := StandardMaterial3D.new()
	pipe.albedo_color = Color(0.42, 0.44, 0.52)
	pipe.metallic = 0.75
	pipe.roughness = 0.35
	_mats["pipe"] = pipe
	var shaft := StandardMaterial3D.new()
	shaft.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shaft.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shaft.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shaft.cull_mode = BaseMaterial3D.CULL_DISABLED
	shaft.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	shaft.albedo_texture = load(SHAFT_TEX) if ResourceLoader.exists(SHAFT_TEX) else null
	_mats["shaft"] = shaft
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

func _floor_kind(x: int, z: int) -> String:
	var c := cell(x, z)
	if c == "~":
		return "water"
	if outdoor:
		if c == ",":
			return "floor_path"
		if c == "_":
			return "floor_tile"
		return "floor"
	if c == ",":
		return "floor_grate"
	if c == "_":
		return "floor_tile"
	# Doorway thresholds get hazard stripes: a gap in a wall row/column.
	if (cell(x - 1, z) == "#" and cell(x + 1, z) == "#") or (cell(x, z - 1) == "#" and cell(x, z + 1) == "#"):
		return "floor_hazard"
	return "floor"


var _ground_noise := FastNoiseLite.new()


func _build_floor() -> void:
	_ground_noise.seed = rng.randi()
	_ground_noise.frequency = 0.12
	var a := pcolor("ground", "#2a2440")
	var b := pcolor("ground_alt", "#352c52")
	var gap := 1.0 if outdoor else 0.985
	var tile_mesh := box(Vector3(TILE * gap, FLOOR_T, TILE * gap))
	for cz in range(0, height, CHUNK):
		for cx in range(0, width, CHUNK):
			var groups := {}  # kind -> [positions, colors]
			for z in range(cz, mini(cz + CHUNK, height)):
				for x in range(cx, mini(cx + CHUNK, width)):
					var c := cell(x, z)
					if c == " " or c == "#" or c == "O" or c == "^":
						continue
					var p := center(x, z)
					p.y = -FLOOR_T * 0.5
					var kind := _floor_kind(x, z)
					if kind == "water":
						p.y -= 0.22
					elif outdoor:
						p.y += rng.randf_range(-0.015, 0.015)
					if not groups.has(kind):
						groups[kind] = [[], []]
					groups[kind][0].append(p)
					var base := a if (x + z) % 2 == 0 else b
					if outdoor:
						# Organic patches instead of a checkerboard.
						base = a.lerp(b, clampf(_ground_noise.get_noise_2d(x, z) * 0.9 + 0.5, 0.0, 1.0))
					if kind == "floor_path" and outdoor:
						base = Color(0.78, 0.78, 0.84)
					elif kind != "floor":
						base = Color(0.8, 0.8, 0.85) if kind != "floor_hazard" else Color(1, 1, 1)
					groups[kind][1].append(base.lightened(rng.randf_range(-0.06, 0.08)))
			for kind in groups:
				var positions: Array = groups[kind][0]
				var colors: Array = groups[kind][1]
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_colors = true
				mm.mesh = tile_mesh
				mm.instance_count = positions.size()
				for i in positions.size():
					var basis := Basis()
					if outdoor and kind == "floor":
						basis = Basis(Vector3.UP, rng.randi_range(0, 3) * PI * 0.5)
					mm.set_instance_transform(i, Transform3D(basis, positions[i]))
					mm.set_instance_color(i, colors[i])
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "Floor_%s_%d_%d" % [kind, cx, cz]
				mmi.multimesh = mm
				mmi.material_override = _mats[kind]
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
		for x in width:
			if cell(x, z) == "O":
				_window(x, z)
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
		_dress_wall(x0, x1, z, h)
	# Ceiling cap: a dark beam on top of tall walls frames the diorama.
	if not low:
		add_mesh(root, box(Vector3(length + 0.05, 0.25, TILE + 0.1)), _mats["dark"], Vector3(cx, h + 0.12, cz), 0.0, false)


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
	var hr: Array = palette.get("building_h", [4.0, 8.5])
	var h := rng.randf_range(float(hr[0]), float(hr[1]))
	var pos := Vector3((x0 + x1 + 1) * TILE * 0.5, 0.0, (z0 + z1 + 1) * TILE * 0.5)
	var body := static_body(pos, LAYER_WORLD | LAYER_OCCLUDER)
	body.name = "Building"
	add_box_collider(body, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	var mat := _textured("building_panel", pcolor("wall", "#4a3f6b").lightened(rng.randf_range(-0.1, 0.15)), 0.5, 0.7, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	# Rooftops face the camera: keep them light and textured (tar-paper concrete in the city,
	# weathered planks on frontier huts) so they never read as black slabs.
	var hut := float(hr[1]) < 7.0
	var roof_mat := _textured("planks" if hut else "concrete", pcolor("wall", "#4a3f6b").lightened(0.45 if hut else 0.3), 0.5, 0.85, 0.05, 1.4)
	roof_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	add_mesh(body, box(Vector3(w, h, d)), mat, Vector3(0, h * 0.5, 0))
	add_mesh(body, box(Vector3(w + 0.3, 0.25, d + 0.3)), roof_mat, Vector3(0, h + 0.12, 0))
	# Parapet lip + rooftop clutter: from this camera the roofs are a big part of the frame.
	for side in [-1.0, 1.0]:
		add_mesh(body, box(Vector3(w + 0.3, 0.35, 0.12)), mat, Vector3(0, h + 0.4, side * (d * 0.5 + 0.09)))
		add_mesh(body, box(Vector3(0.12, 0.35, d + 0.3)), mat, Vector3(side * (w * 0.5 + 0.09), h + 0.4, 0))
	for i in rng.randi_range(1, 3):
		var unit := Vector3(rng.randf_range(-w * 0.35, w * 0.35), h + 0.45, rng.randf_range(-d * 0.35, d * 0.35))
		add_mesh(body, box(Vector3(rng.randf_range(0.5, 1.1), rng.randf_range(0.4, 0.7), rng.randf_range(0.5, 0.9))), _mats["metal"], unit, rng.randf() * 0.3)
	if rng.randf() < 0.5:
		add_mesh(body, box(Vector3(0.5, 0.06, 0.5)), emissive(next_neon(), 2.5), Vector3(rng.randf_range(-w * 0.3, w * 0.3), h + 0.28, rng.randf_range(-d * 0.3, d * 0.3)), 0.0, false)
	_roofs.append([pos + Vector3(0, h, 0), Vector2(w, d) * 0.5])
	var deco: Array[Node] = []
	var front := d * 0.5
	# Lit windows on the camera-facing (south) side: one MultiMesh = one draw call.
	var win_col := next_neon().lerp(Color(1, 0.9, 0.6), 0.5)
	var floors := int((h - 2.4) / 1.4)
	var cols := int(w / 1.1)
	var spots: Array[Vector3] = []
	for fy in floors:
		for fx in cols:
			if rng.randf() < 0.45:
				continue
			spots.append(Vector3(-w * 0.5 + 0.55 + fx * 1.1, 3.0 + fy * 1.4, front + 0.02))
	if not spots.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box(Vector3(0.55, 0.6, 0.04))
		mm.instance_count = spots.size()
		for i in spots.size():
			mm.set_instance_transform(i, Transform3D(Basis(), spots[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = emissive(win_col, 1.6)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mmi)
		deco.append(mmi)
	# Street-level shop front: glowing glass, awning, and a name board.
	var sign_color := next_neon()
	var fid := owner_faction
	if fid != "" and DataDB.factions.has(fid) and rng.randf() < 0.45:
		sign_color = DataDB.faction_color(fid)
	var shop_w := minf(w - 0.5, rng.randf_range(2.0, 4.0))
	var shop_x := rng.randf_range(-(w - shop_w) * 0.5, (w - shop_w) * 0.5)
	deco.append(add_mesh(body, box(Vector3(shop_w, 1.5, 0.05)), emissive(sign_color.lerp(Color(1, 0.95, 0.85), 0.55), 1.3), Vector3(shop_x, 1.0, front + 0.03), 0.0, false))
	var awning := add_mesh(body, box(Vector3(shop_w + 0.4, 0.08, 0.9)), _mats["dark"], Vector3(shop_x, 2.05, front + 0.42), 0.0, true)
	awning.rotation.x = 0.22
	deco.append(awning)
	deco.append(add_mesh(body, box(Vector3(shop_w + 0.4, 0.06, 0.06)), emissive(sign_color, 4.0), Vector3(shop_x, 1.95, front + 0.86), 0.0, false))
	var label := Label3D.new()
	var corp_label: bool = fid != "" and DataDB.factions.has(fid) and sign_color == DataDB.faction_color(fid)
	label.text = DataDB.factions.get(fid, {}).get("short", "OPEN 25/8") if corp_label else ["NOODLES", "BAR", "CLINIC?", "PAWN", "CRYO-MOTEL", "ARCADE", "KARAOKE", "TATTOO", "PASTE HUT", "LOANS!", "TAPES", "HOTEL"][rng.randi() % 12]
	label.font_size = 96
	label.pixel_size = 0.009
	label.modulate = sign_color * 2.2
	label.outline_size = 0
	label.position = Vector3(shop_x, 2.55, front + 0.08)
	body.add_child(label)
	deco.append(label)
	if rng.randf() < 0.6:
		var shop_light := OmniLight3D.new()
		shop_light.light_color = sign_color.lerp(Color(1, 0.9, 0.7), 0.4)
		shop_light.light_energy = 1.3
		shop_light.omni_range = 5.5
		shop_light.position = Vector3(shop_x, 1.4, front + 1.3)
		body.add_child(shop_light)
	# Vertical neon blade sign on a corner.
	if h > 5.0 and rng.randf() < 0.6:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var word: String = ["HOTEL", "BAR", "LOANS", "CLUB", "RAMEN", "DEBT", "CRYO", "SALE", "OBEY", "NOVA"][rng.randi() % 10]
		var blade_h := 0.42 * word.length() + 0.4
		var bx := side * (w * 0.5 - 0.1)
		var by := minf(h - blade_h * 0.5 - 0.3, 3.0 + blade_h * 0.5)
		var col := next_neon()
		deco.append(add_mesh(body, box(Vector3(0.08, blade_h, 0.7)), _mats["dark"], Vector3(bx, by, front - 0.2), 0.0, false))
		deco.append(add_mesh(body, box(Vector3(0.1, blade_h + 0.08, 0.04)), emissive(col, 4.0), Vector3(bx, by, front + 0.16), 0.0, false))
		var vl := Label3D.new()
		var stacked := PackedStringArray()
		for ci in word.length():
			stacked.append(word[ci])
		vl.text = "\n".join(stacked)
		vl.font_size = 64
		vl.pixel_size = 0.0075
		vl.line_spacing = -18.0
		vl.modulate = col * 2.4
		vl.outline_size = 0
		vl.position = Vector3(bx + side * 0.06, by, front - 0.2)
		vl.rotation.y = side * PI * 0.5
		body.add_child(vl)
		deco.append(vl)
	# AC units and balconies break up the flat facade.
	for i in rng.randi_range(1, 3):
		var ac_pos := Vector3(rng.randf_range(-w * 0.5 + 0.4, w * 0.5 - 0.4), rng.randf_range(3.2, maxf(3.3, h - 0.8)), front + 0.2)
		deco.append(add_mesh(body, box(Vector3(0.6, 0.45, 0.4)), _mats["metal"], ac_pos, 0.0, true))
	if floors > 1 and rng.randf() < 0.5:
		var bal_y := 3.0 + rng.randi_range(1, floors - 1) * 1.4 - 0.45
		deco.append(add_mesh(body, box(Vector3(minf(w * 0.6, 3.0), 0.08, 0.6)), _mats["dark"], Vector3(rng.randf_range(-w * 0.2, w * 0.2), bal_y, front + 0.3), 0.0, true))
	body.set_meta("fade_mats", [mat, roof_mat])
	body.set_meta("fade_hide", deco)
	# Roof clutter: antenna beacons, water tanks, and the odd rooftop billboard.
	var roll := rng.randf()
	if roll < 0.35:
		add_mesh(body, cylinder(0.05, 2.0, 4), _mats["metal"], Vector3(w * 0.3, h + 1.0, 0))
		add_mesh(body, box(Vector3(0.18, 0.18, 0.18)), emissive(Color(1, 0.2, 0.2), 5.0), Vector3(w * 0.3, h + 2.0, 0), 0.0, false)
	elif roll < 0.6:
		add_mesh(body, cylinder(0.55, 1.1, 8), _mats["metal"], Vector3(-w * 0.25, h + 0.8, -d * 0.2))
		add_mesh(body, cylinder(0.05, 0.6, 4), _mats["dark"], Vector3(-w * 0.25, h + 0.25, -d * 0.2))
	elif roll < 0.85 and w > 3.0:
		var ads: Array = DataDB.ads.get("list", [])
		var ad: Dictionary = ads[rng.randi() % ads.size()] if not ads.is_empty() else {"faction": "lumen", "headline": "LUMEN"}
		var ad_col := DataDB.faction_color(ad.get("faction", "lumen"))
		add_mesh(body, box(Vector3(w * 0.8, 1.6, 0.1)), emissive(ad_col.darkened(0.55), 1.2), Vector3(0, h + 1.3, -d * 0.1), 0.0, true)
		add_mesh(body, box(Vector3(w * 0.8 + 0.1, 0.06, 0.12)), emissive(ad_col, 4.0), Vector3(0, h + 2.12, -d * 0.1), 0.0, false)
		var al := Label3D.new()
		al.text = str(ad.get("headline", ""))
		al.font_size = 96
		al.pixel_size = 0.009
		al.modulate = ad_col * 2.4
		al.outline_size = 0
		al.position = Vector3(0, h + 1.3, -d * 0.1 + 0.07)
		body.add_child(al)


## Sagging power/data cables with paper lanterns strung between nearby rooftops.
func _build_cables() -> void:
	if _roofs.size() < 2:
		return
	var cable_mat: Material = _mats["dark"]
	var count := 0
	for i in _roofs.size():
		for j in range(i + 1, _roofs.size()):
			if count > 26:
				return
			var a: Vector3 = _roofs[i][0]
			var b: Vector3 = _roofs[j][0]
			var dist := Vector2(a.x - b.x, a.z - b.z).length()
			if dist < 6.0 or dist > 16.0 or rng.randf() < 0.5:
				continue
			count += 1
			a.y -= rng.randf_range(0.4, 1.6)
			b.y -= rng.randf_range(0.4, 1.6)
			var sag := rng.randf_range(0.8, 2.0)
			var segs := 8
			var prev := a
			var lantern_col := next_neon()
			for k in range(1, segs + 1):
				var t := float(k) / segs
				var p := a.lerp(b, t)
				p.y -= sin(t * PI) * sag
				var mid := (prev + p) * 0.5
				var seg_len := prev.distance_to(p)
				var mi := add_mesh(root, box(Vector3(0.04, 0.04, seg_len)), cable_mat, mid, 0.0, false)
				mi.look_at_from_position(mid, p, Vector3.UP if absf((p - prev).normalized().y) < 0.99 else Vector3.RIGHT)
				if k < segs and k % 2 == 0 and rng.randf() < 0.7:
					var lantern := SphereMesh.new()
					lantern.radius = 0.14
					lantern.height = 0.3
					lantern.radial_segments = 6
					lantern.rings = 3
					add_mesh(root, lantern, emissive(lantern_col, 3.5), p - Vector3(0, 0.2, 0), 0.0, false)
				prev = p


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
				"h":
					_holo_projector(p)
				"k":
					_stall(p)
				"q":
					_hovercar(p)
				"j":
					_trash(p)
				"g":
					_tree(p)
				"w":
					_bench(p)
				"i":
					_street_sign(p)
				"v":
					_vent(p)
				"o":
					_dome(p)
				"Y":
					_ad_tower(p)
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
		add_mesh(root, cylinder(0.02, 0.6, 4), _mats["dark"], p + Vector3(0, 3.35, 0), 0.0, false)
		add_light(p + Vector3(0, 2.7, 0), col, 2.2, 7.5)
		light_shaft(p + Vector3(0, 1.45, 0.05), col, 2.6, 2.9)


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


# --- Terrain: water channels & cliffs ------------------------------------------------------

## Water tiles are drawn by the floor pass; here they get knee-high colliders (blocks
## walking and the navmesh, not bullets) and a dark bank lip.
func _build_water() -> void:
	var bank := box(Vector3(TILE, 0.12, 0.18))
	for z in height:
		var x := 0
		while x < width:
			if cell(x, z) != "~":
				x += 1
				continue
			var start := x
			while x < width and cell(x, z) == "~":
				x += 1
			var length := (x - start) * TILE
			add_box_collider(_walls_body, Vector3(length, 0.6, TILE), Vector3(start * TILE + length * 0.5, 0.3, z * TILE + TILE * 0.5))
		for xi in width:
			if cell(xi, z) != "~":
				continue
			var c := center(xi, z)
			if cell(xi, z + 1) != "~" and walkable(xi, z + 1):
				add_mesh(root, bank, _mats["rock"], c + Vector3(0, 0.0, TILE * 0.5), 0.0, false)
			if cell(xi, z - 1) != "~" and walkable(xi, z - 1):
				add_mesh(root, bank, _mats["rock"], c + Vector3(0, 0.0, -TILE * 0.5), 0.0, false)


## '^' cells become stacked rock mesas. Each row-run is its own body on the occluder
## layer so the camera can fade whatever slab stands between it and the player.
func _build_cliffs() -> void:
	for z in height:
		var x := 0
		while x < width:
			if cell(x, z) != "^":
				x += 1
				continue
			var start := x
			while x < width and cell(x, z) == "^":
				x += 1
			var length := (x - start) * TILE
			var h := rng.randf_range(2.6, 5.2)
			if cell(start, z + 1) != "^":
				h = rng.randf_range(1.6, 3.0)  # front ledge is lower: a terraced mesa
			var pos := Vector3(start * TILE + length * 0.5, 0.0, z * TILE + TILE * 0.5)
			var body := static_body(pos, LAYER_WORLD | LAYER_OCCLUDER)
			body.name = "Cliff"
			add_box_collider(body, Vector3(length, maxf(h, WALL_H), TILE), Vector3(0, maxf(h, WALL_H) * 0.5, 0))
			var mat := _textured("rock_cliff", pcolor("wall", "#4a2a20").lightened(rng.randf_range(-0.08, 0.12)), 0.5, 0.95, 0.0, 1.8)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
			add_mesh(body, box(Vector3(length + 0.2, h, TILE + 0.1)), mat, Vector3(rng.randf_range(-0.1, 0.1), h * 0.5, 0))
			var top := mat.duplicate() as StandardMaterial3D
			top.albedo_color = mat.albedo_color.lightened(0.18)
			add_mesh(body, box(Vector3(length + 0.4, 0.3, TILE + 0.3)), top, Vector3(0, h, 0))
			body.set_meta("fade_mats", [mat, top])
			body.set_meta("fade_hide", [])


# --- Street life props ---------------------------------------------------------------------

func _stall(p: Vector3) -> void:
	var body := static_body(p)
	var col := next_neon()
	var rot := 0.0 if rng.randf() < 0.7 else PI * 0.5
	body.rotation.y = rot
	add_mesh(body, box(Vector3(1.7, 0.9, 0.8)), _mats["crate"], Vector3(0, 0.45, 0))
	add_mesh(body, box(Vector3(1.75, 0.05, 0.85)), _mats["dark"], Vector3(0, 0.92, 0))
	for sx in [-0.8, 0.8]:
		add_mesh(body, cylinder(0.04, 2.2, 4), _mats["dark"], Vector3(sx, 1.1, -0.35))
	var awning := add_mesh(body, box(Vector3(2.0, 0.06, 1.3)), emissive(col.darkened(0.45), 0.9), Vector3(0, 2.2, 0.1))
	awning.rotation.x = 0.2
	add_mesh(body, box(Vector3(2.0, 0.08, 0.05)), emissive(col, 4.0), Vector3(0, 2.07, 0.74), 0.0, false)
	for i in rng.randi_range(3, 6):
		var goods := box(Vector3(rng.randf_range(0.15, 0.3), rng.randf_range(0.12, 0.3), 0.2))
		add_mesh(body, goods, emissive(Color.from_hsv(rng.randf(), 0.6, 0.9), 0.6), Vector3(rng.randf_range(-0.7, 0.7), 1.05, rng.randf_range(-0.2, 0.2)), 0.0, false)
	var lantern := SphereMesh.new()
	lantern.radius = 0.16
	lantern.height = 0.34
	lantern.radial_segments = 6
	lantern.rings = 3
	add_mesh(body, lantern, emissive(Color(1.0, 0.75, 0.35), 4.0), Vector3(0.6, 1.8, 0.5), 0.0, false)
	var label := Label3D.new()
	label.text = STALL_SIGNS[rng.randi() % STALL_SIGNS.size()]
	label.font_size = 64
	label.pixel_size = 0.0075
	label.modulate = col * 2.4
	label.outline_size = 0
	label.position = Vector3(0, 2.45, 0.6)
	body.add_child(label)
	if rng.randf() < 0.45:
		add_light(p + Vector3(0, 1.7, 0.8), Color(1.0, 0.8, 0.5), 1.2, 4.5)
	add_box_collider(body, Vector3(1.7, 1.0, 0.8), Vector3(0, 0.5, 0))


func _hovercar(p: Vector3) -> void:
	var body := static_body(p + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)))
	body.rotation.y = [0.0, PI, PI * 0.5, -PI * 0.5][rng.randi() % 4] + rng.randf_range(-0.15, 0.15)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.8), rng.randf_range(0.35, 0.8))
	paint.metallic = 0.7
	paint.roughness = 0.25
	var hover := 0.32
	add_mesh(body, box(Vector3(2.3, 0.45, 1.05)), paint, Vector3(0, hover + 0.22, 0))
	var nose := add_mesh(body, box(Vector3(0.5, 0.3, 1.0)), paint, Vector3(1.25, hover + 0.18, 0))
	nose.rotation.z = -0.3
	add_mesh(body, box(Vector3(1.1, 0.38, 0.9)), _mats["glass"], Vector3(-0.15, hover + 0.62, 0), 0.0, false)
	add_mesh(body, box(Vector3(0.06, 0.1, 0.8)), emissive(Color(1.0, 0.95, 0.8), 5.0), Vector3(1.46, hover + 0.22, 0), 0.0, false)
	add_mesh(body, box(Vector3(0.06, 0.1, 0.9)), emissive(Color(1.0, 0.15, 0.2), 4.0), Vector3(-1.16, hover + 0.3, 0), 0.0, false)
	add_mesh(body, box(Vector3(2.0, 0.04, 0.9)), emissive(next_neon(), 3.0), Vector3(0, hover - 0.02, 0), 0.0, false)
	add_box_collider(body, Vector3(2.4, 1.0, 1.1), Vector3(0, 0.5, 0))


func _trash(p: Vector3) -> void:
	var body := static_body(p + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)))
	for i in rng.randi_range(2, 4):
		var bag := SphereMesh.new()
		bag.radius = rng.randf_range(0.22, 0.38)
		bag.height = bag.radius * 1.5
		bag.radial_segments = 6
		bag.rings = 3
		var bm := StandardMaterial3D.new()
		bm.albedo_color = [Color(0.08, 0.08, 0.1), Color(0.12, 0.14, 0.2), Color(0.25, 0.2, 0.1)][rng.randi() % 3]
		bm.roughness = 0.3
		bm.metallic = 0.2
		add_mesh(body, bag, bm, Vector3(rng.randf_range(-0.4, 0.4), bag.height * 0.4, rng.randf_range(-0.3, 0.3)))
	if rng.randf() < 0.6:
		add_mesh(body, box(Vector3(0.5, 0.35, 0.4)), _mats["crate"], Vector3(rng.randf_range(-0.3, 0.3), 0.18, rng.randf_range(-0.3, 0.3)), rng.randf() * TAU)
	if rng.randf() < 0.5:
		add_mesh(body, cylinder(0.06, 0.14, 6), emissive(next_neon(), 0.8), Vector3(rng.randf_range(-0.6, 0.6), 0.07, rng.randf_range(-0.5, 0.5)), 0.0, false)
	add_box_collider(body, Vector3(1.0, 0.45, 0.8), Vector3(0, 0.22, 0))


func _tree(p: Vector3) -> void:
	var body := static_body(p)
	var plant := pcolor("plant", "#7ad06a")
	var glow := float(palette.get("plant_glow", 0.0))
	var urban := not palette.has("foliage") or float(palette.get("building_density", 0.0)) > 0.7
	if urban:
		add_mesh(body, box(Vector3(1.2, 0.4, 1.2)), _mats["concrete"], Vector3(0, 0.2, 0))
	var hgt := rng.randf_range(2.0, 3.6)
	var trunk := add_mesh(body, cylinder(0.12, hgt, 6, 0.08), _mats["rock"], Vector3(0, hgt * 0.5, 0))
	trunk.rotation.z = rng.randf_range(-0.12, 0.12)
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = plant.darkened(0.25)
	leaf.roughness = 0.9
	if glow > 0.0:
		leaf.emission_enabled = true
		leaf.emission = plant
		leaf.emission_energy_multiplier = glow * 0.6
	for i in rng.randi_range(2, 4):
		var blob := SphereMesh.new()
		blob.radius = rng.randf_range(0.55, 0.95)
		blob.height = blob.radius * 1.6
		blob.radial_segments = 7
		blob.rings = 4
		add_mesh(body, blob, leaf, Vector3(rng.randf_range(-0.5, 0.5), hgt + rng.randf_range(-0.3, 0.4), rng.randf_range(-0.4, 0.4)))
	add_box_collider(body, Vector3(0.5 if not urban else 1.2, 2.0, 0.5 if not urban else 1.2), Vector3(0, 1.0, 0))


func _bench(p: Vector3) -> void:
	var body := static_body(p)
	body.rotation.y = 0.0 if rng.randf() < 0.6 else PI * 0.5
	add_mesh(body, box(Vector3(1.6, 0.08, 0.5)), _mats["crate"], Vector3(0, 0.45, 0))
	add_mesh(body, box(Vector3(1.6, 0.4, 0.06)), _mats["crate"], Vector3(0, 0.75, -0.24))
	for sx in [-0.65, 0.65]:
		add_mesh(body, box(Vector3(0.08, 0.45, 0.45)), _mats["dark"], Vector3(sx, 0.22, 0))
	add_box_collider(body, Vector3(1.6, 0.5, 0.5), Vector3(0, 0.25, 0))


func _street_sign(p: Vector3) -> void:
	var body := static_body(p + Vector3(0.6, 0, 0.6))
	add_mesh(body, cylinder(0.05, 2.8, 5), _mats["metal"], Vector3(0, 1.4, 0))
	var names := STREETS.duplicate()
	for i in 2:
		var name: String = names[rng.randi() % names.size()]
		names.erase(name)
		var blade := add_mesh(body, box(Vector3(1.3, 0.28, 0.05)), emissive(Color(0.1, 0.45, 0.35), 1.2), Vector3(0.45, 2.55 - i * 0.34, 0), 0.0, false)
		blade.rotation.y = i * PI * 0.5
		var l := Label3D.new()
		l.text = name
		l.font_size = 40
		l.pixel_size = 0.006
		l.modulate = Color(1.6, 1.6, 1.6)
		l.outline_size = 0
		l.position = blade.position + (Vector3(0, 0, 0.04) if i == 0 else Vector3(0.04, 0, 0))
		l.rotation.y = blade.rotation.y
		if i == 1:
			l.position = Vector3(0, 2.55 - 0.34, 0.45)
			blade.position = l.position - Vector3(0.03, 0, 0)
			l.position.x += 0.04
		body.add_child(l)
	add_box_collider(body, Vector3(0.2, 2.8, 0.2), Vector3(0, 1.4, 0))


func _vent(p: Vector3) -> void:
	add_mesh(root, box(Vector3(1.2, 0.05, 1.2)), _textured("floor_grate", Color(0.6, 0.6, 0.7), 1.0, 0.5, 0.5), p + Vector3(0, 0.03, 0), 0.0, false)
	var steam := CPUParticles3D.new()
	steam.amount = 18
	steam.lifetime = 3.2
	steam.preprocess = 3.0
	steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	steam.emission_box_extents = Vector3(0.45, 0.05, 0.45)
	steam.direction = Vector3(0.1, 1, 0)
	steam.spread = 12.0
	steam.gravity = Vector3(0.15, 0.4, 0)
	steam.initial_velocity_min = 0.6
	steam.initial_velocity_max = 1.1
	steam.scale_amount_min = 0.8
	steam.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	steam.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.22))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	steam.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.85, 0.85, 0.95)
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 1))
	pg.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = pg
	puff.width = 32
	puff.height = 32
	m.albedo_texture = puff
	q.material = m
	steam.mesh = q
	steam.position = p + Vector3(0, 0.1, 0)
	root.add_child(steam)


func _dome(p: Vector3) -> void:
	var body := static_body(p)
	var shell := SphereMesh.new()
	shell.radius = 1.8
	shell.height = 1.8
	shell.is_hemisphere = true
	shell.radial_segments = 14
	shell.rings = 5
	add_mesh(body, shell, _mats["metal"], Vector3.ZERO)
	var col := next_neon()
	add_mesh(body, cylinder(1.82, 0.12, 14), emissive(col, 2.5), Vector3(0, 0.3, 0), 0.0, false)
	add_mesh(body, box(Vector3(0.7, 1.1, 0.1)), emissive(Color(1.0, 0.85, 0.55), 2.0), Vector3(0, 0.55, 1.72), 0.0, false)
	for i in 3:
		var a := -0.9 + i * 0.9
		add_mesh(body, box(Vector3(0.3, 0.22, 0.06)), emissive(Color(1.0, 0.9, 0.6), 1.6), Vector3(sin(a) * 1.45, 1.05, cos(a) * 1.15), a, false)
	add_mesh(body, cylinder(0.04, 1.4, 4), _mats["dark"], Vector3(0.6, 2.2, 0))
	add_mesh(body, box(Vector3(0.12, 0.12, 0.12)), emissive(Color(1, 0.25, 0.25), 6.0), Vector3(0.6, 2.95, 0), 0.0, false)
	add_light(p + Vector3(0, 1.0, 2.4), Color(1.0, 0.85, 0.55), 1.2, 4.5)
	add_box_collider(body, Vector3(3.2, 1.8, 3.2), Vector3(0, 0.9, 0))


## A towering (often broken) billboard: the landmark of the ad-desert.
func _ad_tower(p: Vector3) -> void:
	var ads: Array = DataDB.ads.get("list", [])
	var ad: Dictionary = ads[rng.randi() % ads.size()] if not ads.is_empty() else {"faction": "lumen", "headline": "LUMEN", "text": "Watch more."}
	var col := DataDB.faction_color(ad.get("faction", "lumen"))
	var body := static_body(p)
	var hgt := rng.randf_range(4.5, 6.5)
	for sx in [-1.3, 1.3]:
		add_mesh(body, cylinder(0.12, hgt, 6), _mats["metal"], Vector3(sx, hgt * 0.5, 0))
	var panel := Node3D.new()
	panel.position = Vector3(0, hgt + 0.8, 0)
	panel.rotation.z = rng.randf_range(-0.12, 0.12)
	body.add_child(panel)
	add_mesh(panel, box(Vector3(4.4, 2.3, 0.12)), emissive(col.darkened(0.6), 1.0), Vector3.ZERO)
	add_mesh(panel, box(Vector3(4.5, 0.08, 0.14)), emissive(col, 4.0), Vector3(0, 1.17, 0), 0.0, false)
	add_mesh(panel, box(Vector3(4.5, 0.08, 0.14)), emissive(col, 4.0), Vector3(0, -1.17, 0), 0.0, false)
	var head := Label3D.new()
	head.text = str(ad.get("headline", ""))
	head.font_size = 128
	head.pixel_size = 0.009
	head.modulate = col * 2.6
	head.outline_size = 0
	head.position = Vector3(0, 0.35, 0.08)
	panel.add_child(head)
	var sub := Label3D.new()
	sub.text = str(ad.get("text", ""))
	sub.font_size = 56
	sub.pixel_size = 0.007
	sub.modulate = Color(1.5, 1.5, 1.7)
	sub.position = Vector3(0, -0.45, 0.08)
	panel.add_child(sub)
	add_light(p + Vector3(0, hgt, 1.5), col, 2.0, 9.0)
	add_box_collider(body, Vector3(3.0, 2.0, 0.5), Vector3(0, 1.0, 0))


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



# --- HD-2D dressing ----------------------------------------------------------------------------

## Fake volumetric light: an additive gradient quad facing the camera.
func light_shaft(pos: Vector3, color: Color, w: float = 2.4, h: float = 3.0, strength: float = 0.22) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var m: StandardMaterial3D = _mats["shaft"].duplicate()
	m.albedo_color = Color(color.r, color.g, color.b, strength)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	root.add_child(mi)


## Pipes, vents, wall lamps and status LEDs along a tall wall facing the room.
func _dress_wall(x0: int, x1: int, z: int, h: float) -> void:
	var face_z := z * TILE + TILE + 0.12
	var x_start := x0 * TILE
	var x_end := (x1 + 1) * TILE
	var length := x_end - x_start
	# A pipe run (sometimes two) along the wall.
	var py := rng.randf_range(2.2, 2.8)
	var pipe := add_mesh(root, cylinder(0.11, length, 8), _mats["pipe"], Vector3((x_start + x_end) * 0.5, py, face_z + 0.05), 0.0, true)
	pipe.rotation.z = PI * 0.5
	if rng.randf() < 0.5:
		var pipe2 := add_mesh(root, cylinder(0.07, length, 6), _mats["pipe"], Vector3((x_start + x_end) * 0.5, py - 0.3, face_z + 0.05), 0.0, false)
		pipe2.rotation.z = PI * 0.5
	var x := x_start + 1.0
	while x < x_end - 0.5:
		var roll := rng.randf()
		if roll < 0.28:
			# Vent with a status LED.
			add_mesh(root, box(Vector3(0.9, 0.6, 0.06)), _mats["dark"], Vector3(x, 1.1, face_z), 0.0, false)
			for i in 4:
				add_mesh(root, box(Vector3(0.8, 0.05, 0.08)), _mats["metal"], Vector3(x, 0.9 + i * 0.13, face_z + 0.02), 0.0, false)
			add_mesh(root, box(Vector3(0.06, 0.06, 0.05)), emissive([Color(0.3, 1, 0.5), Color(1, 0.3, 0.3), Color(1, 0.8, 0.2)][rng.randi() % 3], 6.0), Vector3(x + 0.38, 1.48, face_z + 0.04), 0.0, false)
		elif roll < 0.42:
			# Wall lamp with a warm cone of light.
			var warm := Color(1.0, 0.72, 0.42)
			add_mesh(root, box(Vector3(0.36, 0.14, 0.22)), emissive(warm, 4.0), Vector3(x, 2.35, face_z + 0.08), 0.0, false)
			add_light(Vector3(x, 2.1, face_z + 0.6), warm, 1.1, 4.5)
			light_shaft(Vector3(x, 1.2, face_z + 0.2), warm, 1.3, 2.3, 0.16)
		elif roll < 0.55:
			# Cable bundle hanging from the pipe.
			var cable := add_mesh(root, cylinder(0.035, 1.6, 4), _mats["dark"], Vector3(x, py - 0.8, face_z + 0.1), 0.0, false)
			cable.rotation.z = rng.randf_range(-0.15, 0.15)
		elif roll < 0.64:
			# Info screen.
			add_mesh(root, box(Vector3(0.7, 0.45, 0.04)), emissive(next_neon().darkened(0.35), 1.6), Vector3(x, 1.6, face_z + 0.02), 0.0, false)
		x += rng.randf_range(1.6, 2.6)


## Window opening in a back wall, looking out onto deep space.
func _window(x: int, z: int) -> void:
	var cx := x * TILE + TILE * 0.5
	var cz := z * TILE + TILE * 0.5
	var bottom := 0.8
	var top := 2.9
	add_box_collider(_walls_body, Vector3(TILE, WALL_H, TILE), Vector3(cx, WALL_H * 0.5, cz))
	add_mesh(root, box(Vector3(TILE, bottom, TILE)), _mats["wall"], Vector3(cx, bottom * 0.5, cz))
	add_mesh(root, box(Vector3(TILE, WALL_H - top, TILE)), _mats["wall"], Vector3(cx, (top + WALL_H) * 0.5, cz))
	for side in [-1.0, 1.0]:
		add_mesh(root, box(Vector3(0.18, top - bottom, TILE)), _mats["metal"], Vector3(cx + side * (TILE * 0.5 - 0.09), (top + bottom) * 0.5, cz))
	add_mesh(root, box(Vector3(TILE, 0.12, 0.3)), emissive(Color(0.4, 0.8, 1.0), 2.0), Vector3(cx, bottom + 0.06, cz + TILE * 0.5 - 0.1), 0.0, false)
	add_mesh(root, box(Vector3(TILE, 0.25, TILE + 0.1)), _mats["dark"], Vector3(cx, WALL_H + 0.12, cz), 0.0, false)
	# Space backdrop far behind the opening (unshaded so it glows).
	if not _mats.has("space"):
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_texture = _tex("space_backdrop")
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sm.albedo_color = Color(1.4, 1.4, 1.5)
		_mats["space"] = sm
		var q := QuadMesh.new()
		q.size = Vector2(width * TILE + 30.0, (width * TILE + 30.0) * 0.5)
		q.material = sm
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(width * TILE * 0.5, 2.0, z * TILE - 6.0)
		root.add_child(mi)
	add_light(Vector3(cx, 1.9, cz + 1.4), Color(0.55, 0.45, 1.0), 1.2, 4.5)
	light_shaft(Vector3(cx, 1.2, cz + 1.5), Color(0.6, 0.5, 1.0), 2.0, 2.6, 0.14)


func _holo_projector(p: Vector3) -> void:
	var body := static_body(p)
	add_mesh(body, cylinder(0.7, 0.35, 12), _mats["metal"], Vector3(0, 0.17, 0))
	add_mesh(body, cylinder(0.55, 0.05, 12), emissive(Color(0.3, 0.9, 1.0), 4.0), Vector3(0, 0.37, 0), 0.0, false)
	add_box_collider(body, Vector3(1.4, 0.4, 1.4), Vector3(0, 0.2, 0))
	var holo := Label3D.new()
	holo.text = "THE CONSORTIUM\nloves you (terms apply)"
	holo.font_size = 48
	holo.pixel_size = 0.006
	holo.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	holo.modulate = Color(0.5, 1.6, 2.0, 0.85)
	holo.outline_size = 0
	holo.position = Vector3(0, 2.0, 0)
	body.add_child(holo)
	light_shaft(Vector3(0, 1.3, 0), Color(0.3, 0.9, 1.0), 1.5, 2.2, 0.3)
	add_light(p + Vector3(0, 1.5, 0.5), Color(0.3, 0.9, 1.0), 1.4, 5.0)
	var tw := holo.create_tween().set_loops()
	tw.tween_property(holo, "position:y", 2.2, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(holo, "position:y", 2.0, 1.6).set_trans(Tween.TRANS_SINE)


## Floating dust motes + a reflection probe for glossy floors.
func _build_atmosphere() -> void:
	var size := Vector3(width * TILE, 4.0, height * TILE)
	var probe := ReflectionProbe.new()
	probe.size = size + Vector3(0, 6, 0)
	probe.position = Vector3(size.x * 0.5, 2.0, size.z * 0.5)
	probe.box_projection = true
	probe.interior = not outdoor
	probe.intensity = 0.65
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	root.add_child(probe)
	if outdoor:
		return
	var motes := CPUParticles3D.new()
	motes.amount = 260
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = size * 0.5
	motes.direction = Vector3(0.3, 0.2, 0)
	motes.spread = 180.0
	motes.gravity = Vector3(0.05, 0.02, 0)
	motes.initial_velocity_min = 0.05
	motes.initial_velocity_max = 0.25
	motes.scale_amount_min = 0.6
	motes.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 0.045)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = Color(1.2, 1.1, 1.4, 0.6)
	q.material = m
	motes.mesh = q
	motes.position = Vector3(size.x * 0.5, 2.0, size.z * 0.5)
	root.add_child(motes)


# --- Outdoor: horizon, foliage, wider world ------------------------------------------------------

func _build_outdoor() -> void:
	var w := width * TILE
	var d := height * TILE
	# Ground continues past the playable area so the diorama has no hard edge.
	var outer := box(Vector3(w + 80.0, 0.1, d + 60.0))
	var om: StandardMaterial3D = _mats["floor"].duplicate()
	om.vertex_color_use_as_albedo = false
	om.albedo_color = pcolor("ground", "#404040").darkened(0.15)
	add_mesh(root, outer, om, Vector3(w * 0.5, -0.32, d * 0.5 - 5.0), 0.0, false)
	# Scattered decor outside the walls (no collision).
	for i in 46:
		var side := rng.randi() % 3
		var pos := Vector3.ZERO
		match side:
			0:
				pos = Vector3(rng.randf_range(-30.0, w + 30.0), 0, rng.randf_range(-24.0, -2.0))
			1:
				pos = Vector3(rng.randf_range(-30.0, -2.0), 0, rng.randf_range(-20.0, d + 10.0))
			_:
				pos = Vector3(rng.randf_range(w + 2.0, w + 30.0), 0, rng.randf_range(-20.0, d + 10.0))
		var s := rng.randf_range(1.2, 3.8)
		var rock := SphereMesh.new()
		rock.radius = s
		rock.height = s * rng.randf_range(1.0, 2.4)
		rock.radial_segments = 6
		rock.rings = 3
		add_mesh(root, rock, _mats["rock"], pos + Vector3(0, s * 0.3, 0), rng.randf() * TAU)
	_build_horizon(w, d)
	_build_foliage()
	_build_puddles()


func _build_horizon(w: float, d: float) -> void:
	var layers: Array = palette.get("horizon", ["skyline_mountains"])
	var far_col := pcolor("fog", "#404060")
	var near_col := pcolor("wall", "#303040").darkened(0.35)
	# Sky gradient plane far behind everything.
	var sky := QuadMesh.new()
	sky.size = Vector2(w + 260.0, 90.0)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://assets/shaders/sky_gradient.gdshader")
	sky_mat.set_shader_parameter("top", pcolor("bg", "#05030e"))
	sky_mat.set_shader_parameter("bottom", far_col.lightened(0.25))
	sky.material = sky_mat
	var sky_mi := MeshInstance3D.new()
	sky_mi.mesh = sky
	sky_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_mi.position = Vector3(w * 0.5, 30.0, -78.0)
	root.add_child(sky_mi)
	for i in 3:
		var tex_name: String = layers[i % layers.size()]
		var tex := _tex(tex_name)
		if tex == null:
			continue
		var q := QuadMesh.new()
		var dist := 30.0 + i * 16.0
		var scale := 1.0 + i * 0.5
		q.size = Vector2(160.0 * scale, 40.0 * scale)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		var t := float(i) / 2.0
		m.albedo_color = near_col.lerp(far_col, t)
		m.uv1_scale = Vector3(2.0, 1.0, 1.0) if i > 0 else Vector3.ONE
		q.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(w * 0.5 + rng.randf_range(-10, 10), q.size.y * 0.5 - 2.0, -dist)
		root.add_child(mi)


func _build_foliage() -> void:
	var density := float(palette.get("foliage", 0.5))
	if density <= 0.0:
		return
	var spots: Array[Vector3] = []
	for z in height:
		for x in width:
			if cell(x, z) != "." or rng.randf() > density:
				continue
			for k in rng.randi_range(1, 3):
				spots.append(center(x, z) + Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(-0.9, 0.9)))
	if spots.is_empty():
		return
	var cells: Array = palette.get("foliage_cells", [0, 1, 4, 5])
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	q.center_offset = Vector3(0, 0.55, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = spots.size()
	var base := pcolor("plant", "#7ad06a")
	for i in spots.size():
		var sc := rng.randf_range(0.6, 1.35)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc * (1 if rng.randf() < 0.5 else -1), sc, sc)), spots[i]))
		mm.set_instance_color(i, base.lightened(rng.randf_range(-0.2, 0.15)))
		mm.set_instance_custom_data(i, Color(float(cells[rng.randi() % cells.size()]), 0, 0, 0))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/foliage.gdshader")
	mat.set_shader_parameter("atlas", _tex("foliage"))
	mat.set_shader_parameter("emission_strength", float(palette.get("plant_glow", 0.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Foliage"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mmi)


func _build_puddles() -> void:
	var kind := str(palette.get("puddles", ""))
	if kind == "":
		return
	var m := StandardMaterial3D.new()
	if kind == "toxic":
		m.albedo_color = Color(0.05, 0.16, 0.05)
		m.emission_enabled = true
		m.emission = Color(0.25, 0.8, 0.15)
		m.emission_energy_multiplier = 0.18
	else:
		m.albedo_color = Color(0.03, 0.03, 0.06)
	m.roughness = 0.04 if kind != "toxic" else 0.25
	m.metallic = 0.85 if kind != "toxic" else 0.05
	for i in 14:
		var x := rng.randi_range(2, width - 3)
		var z := rng.randi_range(2, height - 3)
		if cell(x, z) != ".":
			continue
		var c := cylinder(rng.randf_range(0.6, 1.6), 0.02, 14)
		var mi := add_mesh(root, c, m, center(x, z) + Vector3(rng.randf_range(-0.5, 0.5), 0.012, rng.randf_range(-0.5, 0.5)), 0.0, false)
		mi.scale = Vector3(1.0, 1.0, rng.randf_range(0.5, 0.9))
