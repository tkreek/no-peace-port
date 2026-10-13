class_name TeamScenarios
extends Scenario
## Developer scenarios: teams set at the start (--teams), alliances and resource packages
## from the Diplomacy page, and how a match with allies ends.


## The peoples' teams and how each stands to each other ("A" allied, "W" at war, "N"
## neutral; "+v" sharing sight with them), e.g. "1:t1 2:A+v 3:W 4:W".
func _relations() -> String:
	var rows := PackedStringArray()
	for a: int in main.players:
		var row := PackedStringArray(["%d:t%d" % [a, main.players[a].team]])
		for b: int in main.players:
			if a != b:
				var r := Diplomacy.relation(a, b)
				row.append("%d:%s%s" % [b, "A" if r & Diplomacy.ALLY else ("N" if r & Diplomacy.NEUTRAL else "W"),
						"+v" if r & Diplomacy.VISION else ""])
		rows.append(" ".join(row))
	return " | ".join(rows)


## Who hits whom from now on: {"allied": hits between allies, "enemy": the rest}.
func _count_hits() -> Dictionary:
	var hits := {"allied": 0, "enemy": 0}
	for p: Player in main.players.values():
		p.hit.connect(func(victim: Node2D, attacker: Unit) -> void:
			var victim_team: int = victim.team if victim is Unit else victim.owner_index
			hits["allied" if Diplomacy.allied(attacker.team, victim_team) else "enemy"] += 1)
	return hits


## Four computer players, two against two (--teams=1,1,2,2 --ai-vs-ai=1): for twelve game
## minutes nobody hits a teammate while the teams fight; then the second team is wiped out
## (a cheat order) and the first wins together.
func _scenario_teamgame() -> void:
	print("teams at the start: %s" % _relations())
	var hits := _count_hits()
	var minutes := GameData.cmdline_option("team-minutes", "12").to_int()
	for minute in minutes:
		var due := Sim.tick + Sim.RATE * 60
		while Sim.tick < due and not main._game_over:
			await get_tree().physics_frame
		var alive := main.players.keys().filter(func(i: int) -> bool: return main.players[i].population() > 0)
		print("minute %d: hits between allies %d, between enemies %d, peoples with units %s" % [minute + 1,
				hits.allied, hits.enemy, alive])
		if main._game_over:
			break
	if not main._game_over:
		var doomed := main.players.keys().filter(func(i: int) -> bool: return main.players[i].team != main.players[main.me].team)
		var targets := []
		for unit in Unit.all_units:
			if unit.is_alive() and unit.team in doomed:
				targets.append(unit)
		for object in MapObject.structures:
			if object.is_building() and object.is_alive() and object.owner_index in doomed:
				targets.append(object)
		print("wiping out %s: %d units and buildings" % [doomed, targets.size()])
		Orders.cheat("kill", [], targets)
		var due := Sim.tick + Sim.RATE * 6
		while Sim.tick < due and not main._game_over:
			await get_tree().physics_frame
	print("team game: hits between allies %d, between enemies %d; over %s" % [hits.allied, hits.enemy, main._game_over])
	get_tree().quit()


## Alliances and packages given as orders, the way the Diplomacy page gives them, with the
## announcements: an alliance is one-sided until answered, packages go to anyone marked, a
## game ends for allies only once neither side is at war with the other. --difficulty=1:
## the computer players make no alliances of their own (AiPlayer.plan_pacts).
func _scenario_diplomacy() -> void:
	main.hud.toggle_menu()
	main.hud.menu.show_diplomacy()
	print("diplomacy page rows: %d, menu entry %s" % [main.hud.menu._rows.size(), Diplomacy.negotiable])
	main.hud.toggle_menu()
	print("before: %s" % _relations())
	Orders.declare(2, true)
	await _orders_landed()
	print("1 allies 2: %s; 2 sees for 1 %s, 1 sees for 2 %s" % [_relations(), Diplomacy.sees_for(2, 1), Diplomacy.sees_for(1, 2)])
	await get_tree().create_timer(4.0).timeout
	print("the computer does not answer: %s" % _relations())
	var before := [main.players[1].resources.duplicate(), main.players[2].resources.duplicate(), main.players[3].resources.duplicate()]
	var score: int = main.players[2].score()
	for good in Diplomacy.PACKAGES:
		Orders.send(good, [2, 3])
	await _orders_landed()
	var given := PackedStringArray()
	for good in Diplomacy.PACKAGES:
		given.append("%s %+d/%+d/%+d" % [good, main.players[1].resources[good] - before[0][good],
				main.players[2].resources[good] - before[1][good], main.players[3].resources[good] - before[2][good]])
	print("sent (ours/2's/3's): %s; 2's score %+d" % [", ".join(given), main.players[2].score() - score])
	main.players[1].resources.gold = 150
	var gold_before: int = main.players[2].resources.gold
	Orders.send("gold", [2, 3])
	await _orders_landed()
	print("short of a second package: ours %d, 2's %+d" % [main.players[1].resources.gold, main.players[2].resources.gold - gold_before])
	Orders.declare(2, false)
	await _orders_landed()
	print("1 declares 2 an enemy: %s" % _relations())
	Orders.declare(2, true)
	await _orders_landed()
	# Player 3 is wiped out; 2 has not answered, so 1 has not won.
	var targets := []
	for unit in Unit.all_units:
		if unit.is_alive() and unit.team == 3:
			targets.append(unit)
	for object in MapObject.structures:
		if object.is_building() and object.is_alive() and object.owner_index == 3:
			targets.append(object)
	Orders.cheat("kill", [], targets)
	var due := Sim.tick + Sim.RATE * 6
	while Sim.tick < due:
		await get_tree().physics_frame
	print("3 gone, 2 not answering: game over %s" % main._game_over)
	# Player 2 answers (an order of its own): allies, the game is won together.
	Orders.local_player = 2
	Orders.declare(1, true)
	Orders.local_player = 1
	due = Sim.tick + Sim.RATE * 6
	while Sim.tick < due and not main._game_over:
		await get_tree().physics_frame
	print("2 answered: %s; game over %s" % [_relations(), main._game_over])
	get_tree().quit()


## Computer players pairing up on their own at the difficult level (--difficulty=3): every two
## of them allied both ways within two minutes, the human player left out.
func _scenario_pacts() -> void:
	while main.game_time < 135.0:
		await get_tree().physics_frame
	print("pacts: %s" % _relations())
	get_tree().quit()


## Teams kept by a saved game: the relations and each people's team before and after.
func _scenario_teamsave() -> void:
	if not main.loaded_game:
		await get_tree().create_timer(5.0).timeout
		Orders.declare(3, true)  # an alliance made in the game, across the teams
		await _orders_landed()
		print("before: %s" % _relations())
		SaveGame.save(main)
		Match.load_data = SaveGame.read()
		get_tree().reload_current_scene()
		return
	await get_tree().create_timer(1.0).timeout
	print("after:  %s" % _relations())
	get_tree().quit()
