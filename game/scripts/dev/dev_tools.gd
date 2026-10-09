class_name DevTools
extends Node
## Developer tools behind command-line options: --selftest (decode every sound and map,
## parse every script, list unit stats), --report-after (print stockpiles, frame times and,
## with --profile, timed sections while a match runs headless, then quit) and --screenshot
## (save a frame and quit).

var main: Main


## The tools for this match (added to it as a child, so they can wait for frames).
static func attach(match_node: Main) -> DevTools:
	var tools := DevTools.new()
	tools.main = match_node
	match_node.add_child(tools)
	return tools


var _report_clock := 0


func report_after(frames: int) -> void:
	_report_clock = Time.get_ticks_usec()
	Prof.enabled = GameData.cmdline_option("profile") != ""
	for i in frames:
		await get_tree().process_frame
		if i % (60 if GameData.cmdline_option("trace-workers") != "" else 300) == 0:
			_print_report(i)
	_print_report(frames)
	get_tree().quit()


func _print_report(frame: int) -> void:
	if GameData.cmdline_option("trace-workers") != "":
		for node in main.units_root.get_children():
			if node is Unit and node.team == 1 and node.unit_type.is_hunter():
				print("  hunter state=%d hunting=%s target=%s pos=%s carrying=%s" % [node.state, node.work.hunting, node.target, node.position.round(), node.work.carrying])
			if node is Unit and node.team == 1 and node.state == Unit.State.GATHERING:
				print("  worker phase=%d action=%s carrying='%s' inside=%s" % [node.work.phase, node._action, node.work.carrying, node.inside])
	var alive := {}
	for node in main.units_root.get_children():
		if node is Unit and node.is_alive():
			alive[node.team] = alive.get(node.team, 0) + 1
	for object in MapObject.structures:
		if object.is_building() and object.owner_index == 1:
			print("  %s complete=%s progress=%.2f queue=%s" % [object.display_name(), object.complete, object.build_progress, object.production.queue])
		elif object.is_field() and object.owner_index == 1:
			print("  field state=%d progress=%.2f amount=%d" % [object.stock.field_state, object.stock.field_progress, object.stock.amount])
	var states := [0, 0, 0]
	for object in MapObject.all_objects:
		if object.is_tree():
			states[object.stock.tree_state] += 1
	print("  trees standing/felled/stumps: %s" % [states])
	var mines_heard := MapObject.all_objects.filter(func(o: MapObject) -> bool:
		return o.is_mine() and o.stock._mine_sound != null and o.stock._mine_sound.playing).size()
	print("  mines with work sound playing: %d" % mines_heard)
	var carcasses := Unit.all_units.filter(func(u: Unit) -> bool: return u.team == 0 and not u.is_alive() and u.animal.has_meat())
	print("  carcasses: %s" % [carcasses.map(func(u: Unit) -> int: return u.animal.meat_left)])
	var now := Time.get_ticks_usec()
	print("frame %d: %.2f ms per frame, %d units, %d objects" % [frame, (now - _report_clock) / 1000.0 / 300.0,
			Unit.all_units.size(), MapObject.all_objects.size()])
	_report_clock = now
	if Prof.enabled:
		Prof.report(300)
	for index in main.players:
		print("frame %d (%ds) player %d: %s units=%d" % [frame, int(main.game_time), index, main.players[index].resources, alive.get(index, 0)])
		if frame % 1800 == 0 and frame > 0:
			var kinds := {}
			for node in main.units_root.get_children():
				if node is Unit and node.is_alive() and node.team == index:
					kinds[node.display_name()] = kinds.get(node.display_name(), 0) + 1
			var buildings := {}
			for object in MapObject.structures:
				if object.is_building() and object.owner_index == index and object.is_alive():
					buildings[object.display_name()] = buildings.get(object.display_name(), 0) + 1
			print("    units %s\n    buildings %s" % [kinds, buildings])


func screenshot(path: String) -> void:
	main.camera.input_enabled = false
	Unit.debug_paths = GameData.cmdline_option("debug-paths") != ""
	if GameData.cmdline_option("scenario") == "":
		# Exercise the move order so walking animations show up in the capture.
		var ours := main.units_root.get_children().filter(func(u: Node) -> bool: return u is Unit and u.team == 1)
		var count := GameData.cmdline_option("select", "0").to_int()  # --select=n: only the first n
		main.selection._select(ours.slice(0, count) if count > 0 else ours, false)
		main.selection._order_move(main._vector_option("order", main.camera.position + Vector2(-200, -120)))
	for i in GameData.cmdline_option("frames", "90").to_int():
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("fps %d, %d units, %d objects" % [Engine.get_frames_per_second(), Unit.all_units.size(), MapObject.all_objects.size()])
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


## --selftest=1: decode all sounds and maps, print a summary and quit.
func selftest() -> void:
	if GameData.cmdline_option("selftest") == "stats":
		# --selftest=stats: the stats the game plays with, one JSON line per GUID.
		var guids := GameData.stats_guids()
		guids.sort()
		for guid in guids:
			print("STATS %d %s" % [guid, JSON.stringify(GameData.stats(guid))])
		get_tree().quit()
		return
	if GameData.cmdline_option("selftest") == "parse":
		# Load every script once so parse and type errors show up together.
		var count := 0
		var dirs := ["res://scripts"]
		while not dirs.is_empty():
			var dir: String = dirs.pop_back()
			for sub in DirAccess.get_directories_at(dir):
				dirs.append(dir.path_join(sub))
			for file in DirAccess.get_files_at(dir):
				if file.ends_with(".gd"):
					if load(dir.path_join(file)) == null:
						print("FAILED ", dir.path_join(file))
					count += 1
		print("parsed %d scripts" % count)
		get_tree().quit()
		return
	if GameData.cmdline_option("selftest") == "audio":
		Sound.play_music("mex")
		Sound.play_sound(198)  # "landarbeiter anklicken"
		for i in 90:
			await get_tree().process_frame
			if i % 15 == 0:
				print("music playing=%s stream=%s peak L=%.1f dB" % [Sound._music.playing, Sound._music.stream,
						AudioServer.get_bus_peak_volume_left_db(0, 0)])
		get_tree().quit()
		return
	var result := Sound.verify_all()
	print("sounds: %d ok, %d failed %s" % [result[0], result[1].size(), result[1]])
	var maps := 0
	var bad := PackedStringArray()
	for path in GameData.map_files():
		var map := AlfMap.load_from_file(path)
		if map and map.columns > 0 and map.grid_size != Vector2i.ZERO and not map.placements.is_empty():
			maps += 1
		else:
			bad.append(path.get_file())
	print("maps: %d ok, %d failed %s" % [maps, bad.size(), bad])
	print("object types: %d" % ObjectTypes.count())
	if GameData.cmdline_option("selftest") == "farm":
		for guid in [108, 208, 408, 149]:
			for biome in ["steppe", "wiese"]:
				var tid := GameData.type_for_guid(guid, biome)
				var t := ObjectTypes.get_type(tid)
				var bob := GameData.load_bob(t.anims) if t else null
				print("guid %d %s -> type %d %s %s anims=%d stats=%s" % [guid, biome, tid, t.name if t else "?", t.anims if t else "", bob.anims.size() if bob else -1, GameData.stats(guid).get("name")])
	if GameData.cmdline_option("selftest") == "units":
		# Every unit: its editor stats beside what the game derives (combat, animations).
		var ids := GameData.stats_guids()
		ids.sort()
		for guid in ids:
			var s := GameData.stats(guid)
			if s.get("kind") != "unit":
				continue
			var t := ObjectTypes.get_type(GameData.type_for_guid(guid))
			if t == null:
				print("%d %s NO TYPE" % [guid, s.get("name")])
				continue
			var ut := UnitType.for_guid(guid)
			if ut == null:
				continue
			print("%d %-24s %-18s hp=%s m%s/r%s spd%s sight%s rng%s mr%s rr%s minr%s | hp%d dmg%d %s rng%d reload%d sight%d spd%d atk=%s walk=%s die=%s idle=%s cost=%s" % [
				guid, s.get("name"), t.directory().get_file(), s.get("health"), s.get("melee"), s.get("ranged"),
				s.get("speed_tier"), s.get("sight_tier"), s.get("range_tier"), s.get("melee_rate_tier"),
				s.get("ranged_rate_tier"), s.get("min_range_tier"), ut.health, ut.damage,
				"R" if ut.ranged else "M", ut.attack_range, ut.reload_ms, ut.sight, ut.speed,
				Array(ut.attack_anims).map(func(i: int) -> String: return ut.bob.sub_sprites[ut.bob.anims[i].sub_sprite]),
				_anim_file(ut, "walk"), _anim_file(ut, "die"), _anim_file(ut, "idle"), s.get("cost")])
	if GameData.cmdline_option("selftest") == "stats":
		var d := DefaultsData.load()
		print("defaults entries: ", d.size(), " sample: ", d.get(258), " raw bytes: ", GameData.read("data/defaults.json").size())
		for guid in GameData.stats_guids():
			var st := GameData.stats(guid)
			if st.get("kind") in ["unit", "structure"]:
				print("  %d %s %s %s hp=%s dmg=%s cost=%s at=%s types=%s" % [guid, st.get("faction"), st.get("kind"), st.get("name"), st.get("health"), st.get("damage"), st.get("cost"), st.get("produced_at"), st.get("types")])
	get_tree().quit()


func _anim_file(ut: UnitType, action: String) -> String:
	var i := ut.anim_index(action)
	return ut.bob.sub_sprites[ut.bob.anims[i].sub_sprite].get_basename() if i >= 0 else "-"
