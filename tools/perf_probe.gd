extends SceneTree
## CPU budget probe (headless): loads every planet of a galaxy, lets the street settle, then times the
## game-logic cost the crowd puts on each physics step (player, NPCs, enemies incl. move_and_slide)
## and on each frame (character sprites, critters). The probe runs those callbacks itself, so the
## numbers are real averages: Godot's TIME_PHYSICS_PROCESS monitor is a per-second MAXIMUM, and a
## headless run sleeps ~6.9 ms every frame (no window to draw), so neither is a usable average.
## A phone core is ~3-5x slower than a desktop core: keep step + frame cost under ~2.5 ms here.
##   godot --headless --path . --script res://tools/perf_probe.gd -- [seed]
## Exit code = planets over budget.

const SETTLE := 200
const SAMPLES := 240
const BUDGET_MS := 2.5
const STEP_GROUPS := ["player", "npc", "enemy"]

var _step := 0
var _wait := 0
var _planet := 0
var _rows: Array = []
var _over := 0
var _measuring := false
var _step_us := {}
var _steps := 0
var _frame_us := 0
var _frames := 0
var _sprites: Array = []


func _physics_process(delta: float) -> bool:
	if not _measuring:
		return false
	_steps += 1
	for g in STEP_GROUPS:
		var t := Time.get_ticks_usec()
		for n in get_nodes_in_group(g):
			if is_instance_valid(n) and not n.is_queued_for_deletion() and n.is_inside_tree():
				n._physics_process(delta)
		_step_us[g] = int(_step_us.get(g, 0)) + Time.get_ticks_usec() - t
	return false


func _process(delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	var g = root.get_node("Game")
	match _step:
		0:
			var args := OS.get_cmdline_user_args()
			var seed_v := int(args[0]) if not args.is_empty() else 2024
			g.new_game("Perf Probe", {"class": "gig_worker", "personality": "joker"}, seed_v)
			g.flags["bookend_open_1"] = true
			_step = 1
		1:
			if _planet >= g.galaxy.size():
				_report()
				return true
			root.get_node("Router").params = {"planet_id": g.galaxy[_planet].id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_step = 2
			_wait = SETTLE
		2:
			_close()
			_take_over()
			_step = 3
		3:
			_close()
			var t := Time.get_ticks_usec()
			for s in _sprites:
				if is_instance_valid(s):
					s._process(delta)
			_frame_us += Time.get_ticks_usec() - t
			_frames += 1
			if _frames < SAMPLES:
				return false
			_measuring = false
			var p: Dictionary = g.galaxy[_planet]
			var row := {"name": str(p.get("name", "?")).left(26), "env": str(p.get("environment", "?")),
				"n_npc": get_nodes_in_group("npc").size(), "n_enemy": get_nodes_in_group("enemy").size(), "frame": _frame_us / 1000.0 / _frames}
			var total_step := 0.0
			for gname in STEP_GROUPS:
				row[gname] = float(_step_us.get(gname, 0)) / 1000.0 / maxf(1.0, _steps)
				total_step += row[gname]
			row["total"] = total_step + row.frame
			_rows.append(row)
			if row.total > BUDGET_MS:
				_over += 1
			_planet += 1
			_step = 1
	return false


## Stop the actors' own callbacks so the probe can run (and time) them itself.
func _take_over() -> void:
	for gname in STEP_GROUPS:
		for n in get_nodes_in_group(gname):
			n.set_physics_process(false)
	_sprites.clear()
	_collect_sprites(current_scene)
	for s in _sprites:
		s.set_process(false)
	_step_us.clear()
	_steps = 0
	_frame_us = 0
	_frames = 0
	_measuring = true


func _collect_sprites(n: Node) -> void:
	var sc: Script = n.get_script()
	if sc != null and sc.get_global_name() in ["BillboardSprite", "Critter"]:
		_sprites.append(n)
	for c in n.get_children():
		_collect_sprites(c)


func _close() -> void:
	var hud = get_first_node_in_group("hud")
	for i in 6:
		if hud and hud._dialogue_open:
			hud._on_choice("")
	paused = false


func _report() -> void:
	print("\n%-26s %-12s %4s %5s  %7s %7s %7s %8s  %7s" % ["planet", "biome", "npc", "enemy", "player", "npcs", "enemies", "sprites", "TOTAL"])
	for r in _rows:
		print("%-26s %-12s %4d %5d  %7.3f %7.3f %7.3f %8.3f  %7.3f%s" % [r.name, r.env, r.n_npc, r.n_enemy, r.player, r.npc, r.enemy, r.frame, r.total,
			"  <-- over budget" if r.total > BUDGET_MS else ""])
	print("(ms on this desktop core; player/npcs/enemies per physics step, sprites + critters per frame)")
	print("\nPERF PROBE DONE - %d planets over %.1f ms" % [_over, BUDGET_MS])
	quit(_over)
