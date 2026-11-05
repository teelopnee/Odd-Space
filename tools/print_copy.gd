extends SceneTree
## Prints sample lines from the procedural copywriter (data/copy.json).
##   godot --headless --path . --script res://tools/print_copy.gd -- [symbol] [count]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var cp: Script = load("res://src/core/copy.gd")
	var syms := ["headline", "ad_body", "slogan", "food_name", "bar_name", "street", "news", "flyer", "graffiti", "pa", "menu", "chatter", "floor_notice"]
	if args.size() > 0:
		syms = [args[0]]
	var n := int(args[1]) if args.size() > 1 else 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for s in syms:
		print("== ", s)
		for i in n:
			print("  ", str(cp.call("make", s, rng, {"planet": "Toraka"})).replace("\n", " | "))
	quit(0)
