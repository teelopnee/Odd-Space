extends SceneTree
## Prints procedurally generated planet layouts as ASCII (legend: src/world/level_builder.gd).
##   godot --headless --path . --script res://tools/print_world.gd -- [biome] [seed]
## biome: neon_sprawl | toxic_swamp | ad_desert | rust_canyon | crystal_moon | all

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var args := OS.get_cmdline_user_args()
	var biome := args[0] if args.size() > 0 else "all"
	var seed_value := int(args[1]) if args.size() > 1 else 1234
	var gen: Script = load("res://src/world/world_gen.gd")
	var biomes := ["neon_sprawl", "toxic_swamp", "ad_desert", "rust_canyon", "crystal_moon"] if biome == "all" else [biome]
	for b in biomes:
		var out: Dictionary = gen.call("generate", seed_value, b, "halcyon", {"id": "ad_overload", "enemy_mult": 1.0}, {}, 2, true)
		print("== %s seed %d  (%dx%d)" % [b, seed_value, out.w, out.h])
		for row in out.layout:
			print(row)
	quit(0)
	return true
