extends SceneTree
## Phone/tablet UI review shots for the critique log (docs/REVIEW.md): a fresh life with touch on,
## one shot with the Act I story popup, one in play (tip banner, touch buttons, HUD panel), one after
## standing still out of combat (status panel tucked away).
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1600x720x24" \
##     godot --path . --resolution 1600x720 --script res://tools/ui_review.gd -- <out_prefix>
var _step := 0
var _wait := 0
var _calm_frames := 0
func _process(_d: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			var g = root.get_node("Game")
			g.settings["touch"] = "on"
			g.settings["tips_seen"] = []
			g.new_game("Rex Vantablack", {"background": "smuggler"}, 4242)
			root.get_node("Router").params = {"planet_id": g.galaxy[0].id}
			change_scene_to_file("res://scenes/world/planet_surface.tscn")
			_step = 1; _wait = 330
		1:
			var img := root.get_texture().get_image()
			if img: img.save_png(OS.get_cmdline_user_args()[0] + "_bookend.png")
			var hud = get_first_node_in_group("hud")
			for i in 8:
				if hud and hud._dialogue_open: hud._on_choice("")
			paused = false
			_step = 2; _wait = 40
		2:
			var img := root.get_texture().get_image()
			if img: img.save_png(OS.get_cmdline_user_args()[0] + "_play.png")
			_step = 3
		3:
			# Stand still out of combat until the status panel tucks away (or give up after a while).
			var hud = get_first_node_in_group("hud")
			_calm_frames += 1
			if hud and not hud._tucked and _calm_frames < 2400:
				return false
			var img := root.get_texture().get_image()
			if img: img.save_png(OS.get_cmdline_user_args()[0] + "_calm.png")
			print("saved (tucked=%s after %d frames)" % [hud._tucked if hud else false, _calm_frames])
			quit(0)
	return false
