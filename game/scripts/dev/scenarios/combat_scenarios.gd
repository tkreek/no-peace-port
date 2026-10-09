class_name CombatScenarios
extends Scenario
## Developer scenarios: fighting, quarters, projectiles, damage and fire, robbing, camouflage, traps, magic, surrender.


## Two infantry lines facing each other in front of the camera.
func _scenario_battle() -> void:
	var centre: Vector2 = main.camera.position
	main._spawn_squad(main.FACTIONS[main.players[1].faction].army, 1, centre + Vector2(-60, 120), 9)
	main._spawn_squad(main.FACTIONS[main.players[2].faction].army, 2, centre + Vector2(60, -160), 9)


## A tower manned by riflemen while enemy infantry walk up to it.
func _scenario_quarters() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var tower_guid: int = {"mex": 213, "usa": 413, "des": 313, "ind": 111}[main.players[1].faction]
	var type := ObjectTypes.get_type(GameData.type_for_guid(tower_guid, main.terrain.biome))
	var tower := MapObject.new()
	tower.position = AiBuilder.find_spot(type, hq.position)
	tower.setup(type, 1)
	main.units_root.add_child(tower)
	main.nav.block_footprint(type, tower.position)
	var army: int = main.FACTIONS[main.players[1].faction].army
	main._spawn_squad(army, 1, tower.position + Vector2(0, 160), 4)
	var squad := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 \
			and n.unit_type.guid() == army)
	main.selection._select(squad, false)
	main.selection.order_quarters(tower)
	await get_tree().create_timer(8.0).timeout
	print("capacity %d, quartered %d, outside %d" % [tower.defence.capacity(), tower.defence.garrison.size(),
			squad.filter(func(u: Unit) -> bool: return not u.inside).size()])
	# Beyond the soldiers' range in the open, within it from the walls.
	for u: Unit in Unit.all_units:
		if u.team == 1 and not u.inside:
			u.stance = Unit.Stance.PASSIVE  # only those inside fight
	var walls := tower.work_rect()
	var reach := BuildingDefence.garrison_range(squad[0])
	var spot := Vector2(walls.end.x + squad[0].attack_range() * 1.1, walls.get_center().y)
	main._spawn_squad(main.FACTIONS[main.players[2].faction].army, 2, spot, 3)
	var enemies := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2 \
			and n.position.distance_to(spot) < 120)
	print("enemies %s px from the walls; range in the open %d, from the walls %d" % [enemies.map(func(u: Unit) -> int:
			return int(u.position.distance_to(tower.wall_point(u.position)))), squad[0].attack_range(), reach])
	for e: Unit in enemies:
		e.stance = Unit.Stance.PASSIVE
	await get_tree().create_timer(30.0).timeout
	print("hit beyond the open range: %s" % enemies.any(func(u: Unit) -> bool: return not is_instance_valid(u) or u.health < u.max_health))
	print("enemy energy after 30 s: ", enemies.map(func(u: Unit) -> int: return int(u.health) if is_instance_valid(u) else -1),
			" quartered energy: ", tower.defence.garrison.map(func(u: Unit) -> int: return int(u.health)))
	main.selection.select_building(tower)
	tower.defence.release()
	await get_tree().process_frame
	print("after release: quartered %d, outside %d" % [tower.defence.garrison.size(),
			squad.filter(func(u: Unit) -> bool: return not u.inside).size()])
	get_tree().quit()


## Cannons, archers and a knife thrower against infantry; a nurse tends a wounded soldier.
func _scenario_projectiles() -> void:
	var centre := main.camera.position
	main._spawn_squad(465, 1, centre + Vector2(-140, 160), 2)   # cannons
	main._spawn_squad(156, 1, centre + Vector2(0, 160), 3)      # arrow shooters
	main._spawn_squad(163, 1, centre + Vector2(120, 160), 1)    # knife thrower
	main._spawn_squad(457, 1, centre + Vector2(220, 200), 1)    # nurse
	main._spawn_squad(458, 1, centre + Vector2(260, 200), 1)    # wounded infantryman
	main._spawn_squad(258, 2, centre + Vector2(0, -150), 6)
	var wounded: Unit = null
	for n in main.units_root.get_children():
		if n is Unit and n.team == 1 and n.unit_type.guid() == 458:
			wounded = n
	wounded.health = 40.0
	for n in main.units_root.get_children():
		if n is Unit and n.team == 2:
			n.stance = Unit.Stance.PASSIVE
	var shooters := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 \
			and not n.unit_type.attack_anims.is_empty() and n != wounded)
	print("shooters: ", shooters.map(func(u: Unit) -> String: return "%s ranged=%s proj=%d range=%d" % [u.display_name(), u.unit_type.ranged, u.unit_type.projectile_anim, u.attack_range()]))
	await get_tree().create_timer(float(GameData.cmdline_option("wait", "20"))).timeout
	var enemies := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2)
	print("enemy energy: ", enemies.map(func(u: Unit) -> int: return int(u.health)), " wounded now ", int(wounded.health))
	if GameData.cmdline_option("screenshot") == "":
		get_tree().quit()


## Three of the people's grain stores side by side at 60%, 25% and 0% energy.
func _scenario_damage() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var guid: int = {"mex": 208, "usa": 408, "ind": 108, "des": 308}[main.players[1].faction]
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
	var built: Array[MapObject] = []
	for ratio in [0.6, 0.25, 0.0]:
		var b := MapObject.new()
		b.position = AiBuilder.find_spot(type, hq.position + Vector2(-500, 300))
		b.setup(type, 1)
		main.units_root.add_child(b)
		main.nav.block_footprint(type, b.position)
		b.take_damage(b.max_health * (1.0 - ratio) + (1.0 if ratio == 0.0 else 0.0))
		built.append(b)
	main.camera.position = built[1].position + Vector2(0, -60)
	if GameData.cmdline_option("repair") != "":
		var builders := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.anim_index("build") >= 0)
		main.selection._select(builders, false)
		main.selection.order_build(built[1])
		var wood: int = main.players[1].resources.wood
		for i in 6:
			await get_tree().create_timer(5.0).timeout
			print("repair t=%ds energy %d%% anim %d fires %d wood -%d" % [(i + 1) * 5, int(100 * built[1].health / built[1].max_health), built[1]._body_anim, built[1].condition._fires.size(), wood - main.players[1].resources.wood])
		get_tree().quit()
	print("damage: ", built.map(func(b: MapObject) -> String: return "%d%% anim %d fires %d" % [int(100 * b.health / b.max_health), b._body_anim, b.condition._fires.size()]))


## Outlaws rob an enemy gold warehouse and a barber steals an enemy wagon.
func _scenario_rob() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var enemy_store := 419 if main.players[2].faction == "usa" else 206
	var type := ObjectTypes.get_type(GameData.type_for_guid(enemy_store, main.terrain.biome))
	var store := MapObject.new()
	store.position = AiBuilder.find_spot(type, hq.position + Vector2(300, 300))
	store.setup(type, 2)
	main.units_root.add_child(store)
	main.nav.block_footprint(type, store.position)
	store.stock.stored_gold = 300
	main._spawn_squad(455 if main.players[2].faction == "usa" else 255, 2, store.position + Vector2(-200, 120), 1)
	main._spawn_squad(353, 1, hq.position + Vector2(0, 220), 1)
	var robber: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.guid() == 352)[0]
	var barber: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == 353)[0]
	var wagon: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2 and n.unit_type.is_transport())[0]
	print("robber can rob %s, barber can steal %s" % [robber.work.can_rob(), barber.work.can_steal()])
	robber.rob(store)
	barber.steal(wagon)
	var gold: int = main.players[1].resources.gold
	for i in 8:
		await get_tree().create_timer(5.0).timeout
		print("t=%ds store %d, our gold +%d, robber phase %d carrying %d inside %s; wagon team %d" % [(i + 1) * 5, store.stock.stored_gold,
				main.players[1].resources.gold - gold, robber.work.phase, robber.work.carried, robber.inside, wagon.team])
	get_tree().quit()


## Camouflaged riflemen beside enemy infantry go unseen until a trapper comes along.
func _scenario_camouflage() -> void:
	var centre := Vector2(main.terrain.map.pixel_size()) / 2.0  # away from both bases
	centre = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre))) + Vector2(0.5, 0.5)) * NavGrid.CELL
	main.players[1].researched[915] = true
	main._spawn_squad(160, 1, centre, 2)
	var hiders := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.guid() == 160)
	for h: Unit in hiders:
		h.stance = Unit.Stance.PASSIVE
		h.conceal()
	main._spawn_squad(458, 2, centre + Vector2(150, 0), 3)
	await get_tree().create_timer(10.0).timeout
	print("unseen: concealed %s, energy %s, fogged to player 2's eyes n/a" % [hiders.map(func(h: Unit) -> bool: return h.stealth.concealed), hiders.map(func(h: Unit) -> int: return int(h.health))])
	main._spawn_squad(461, 2, centre + Vector2(220, 40), 1)
	await get_tree().create_timer(12.0).timeout
	print("after the trapper: energy %s" % [hiders.map(func(h: Unit) -> int: return int(h.health))])
	get_tree().quit()


## A pitfall between enemy infantry and our base: they walk into it, our own unit does not.
func _scenario_pitfall() -> void:
	var centre := Vector2(main.terrain.map.pixel_size()) / 2.0
	centre = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre))) + Vector2(0.5, 0.5)) * NavGrid.CELL
	var type := ObjectTypes.get_type(GameData.type_for_guid(MapObject.PITFALL_GUID, main.terrain.biome))
	var pit := MapObject.new()
	pit.position = centre
	pit.setup(type, 1)
	main.units_root.add_child(pit)
	main._spawn_squad(458, 2, centre + Vector2(-200, 0), 4)
	main._spawn_squad(152, 1, centre + Vector2(-120, 60), 1)
	var friend: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.guid() == 152 and n.position.distance_to(centre) < 200)[0]
	friend.move_to(pit.footprint_rect().get_center() + Vector2(60, 0))
	for n in main.units_root.get_children():
		if n is Unit and n.team == 2 and n.position.distance_to(centre) < 300:
			n.stance = Unit.Stance.PASSIVE
			n.move_to(pit.footprint_rect().get_center() + Vector2(220, 0))
	await get_tree().create_timer(12.0).timeout
	var foes := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2 and n.position.distance_to(centre) < 400)
	print("enemies alive %s; our warrior alive %s; pit %s" % [foes.map(func(f: Unit) -> bool: return f.is_alive()), friend.is_alive(),
			"spent" if not is_instance_valid(pit) or not pit.is_alive() else "%d kills" % pit.defence.trap_kills])
	get_tree().quit()


## A medicine man calls lightning on enemy infantry and shields a warrior; a priest converts.
func _scenario_magic() -> void:
	var centre := Vector2(main.terrain.map.pixel_size()) / 2.0
	centre = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre))) + Vector2(0.5, 0.5)) * NavGrid.CELL
	for spell in [918, 919, 920, 921, 922, 948]:
		main.players[1].researched[spell] = true
	var caster_guid := 164 if main.players[1].faction == "ind" else 257
	main._spawn_squad(caster_guid, 1, centre, 1)
	main._spawn_squad(152 if main.players[1].faction == "ind" else 252, 1, centre + Vector2(40, 0), 1)
	main._spawn_squad(458, 2, centre + Vector2(0, -260), 4)
	var caster: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == caster_guid)[0]
	var friend: Unit = main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.position.distance_to(centre + Vector2(40, 0)) < 40)[0]
	var foes := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2 and n.position.distance_to(centre) < 400)
	for f: Unit in foes:
		f.stance = Unit.Stance.PASSIVE
	caster.stance = Unit.Stance.PASSIVE
	main.camera.position = centre + Vector2(0, -120)
	if caster_guid == 164:
		caster.cast(919, foes[0].position)
		await get_tree().create_timer(10.0).timeout
		caster.magic.magic_energy = 100.0
		caster.cast(922, friend.position, friend)
		await get_tree().create_timer(4.0).timeout
		print("lightning: enemy energy %s; warrior shielded %.0fs; magic left %d" % [foes.map(func(f: Unit) -> int: return int(f.health)), friend.magic.shield_time, caster.magic.magic_energy])
	else:
		caster.cast(948, foes[0].position, foes[0])
		await get_tree().create_timer(8.0).timeout
		print("conversion: target now team %d" % foes[0].team)
	get_tree().quit()


## The computer's main building burns down; with its builders gone too it gives up.
func _scenario_surrender() -> void:
	await get_tree().create_timer(2.0).timeout
	if GameData.cmdline_option("keep-builders") == "":
		for n in main.units_root.get_children():
			if n is Unit and n.team == 2 and n.unit_type.can_build():
				n.take_damage(10000.0)
	main.players[2].main_building().take_damage(100000.0)
	await get_tree().create_timer(30.0).timeout
	print("player 2 surrendered: %s; game over: %s; rebuilding: %s" % [main.players[2].surrendered, main._game_over,
			MapObject.all_objects.filter(func(o: MapObject) -> bool: return o.owner_index == 2 and o.guid in MapObject.MAIN_BUILDINGS and o.is_alive()).map(func(o: MapObject) -> String: return "%d%%" % int(o.build_progress * 100))])
	if GameData.cmdline_option("screenshot") == "":
		get_tree().quit()


## Riders shot from the saddle leave a wild horse; ordered to, soldiers shoot the horse and
## the rider fights on on foot; a hunter shoots a wild horse for food.
func _scenario_unhorse() -> void:
	var hq: MapObject = main.players[1].main_building()
	var at := hq.position + Vector2(0, 320)
	var shooter_guid: int = {"mex": 258, "usa": 458, "ind": 160, "des": 356}[main.players[1].faction]
	main._spawn_squad(shooter_guid, 1, at, 4)
	main._spawn_squad(264, 2, at + Vector2(0, 120), 1)  # mounted gaucho
	main._spawn_squad(264, 2, at + Vector2(140, 120), 1)
	var riders := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2 and n.unit_type.guid() == 264)
	for r: Unit in riders:
		r.stance = Unit.Stance.PASSIVE
	var shooters := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.unit_type.guid() == shooter_guid)
	main.selection._select(shooters.slice(0, 2), false)
	main.selection.order_attack(riders[0])
	main.selection._select(shooters.slice(2, 4), false)
	main.selection.order_attack(riders[1], true)
	for i in 8:
		await get_tree().create_timer(4.0).timeout
		var foot := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2 and n.unit_type.guid() == 263)
		var horses := Unit.all_units.filter(func(u: Unit) -> bool: return u.animal.is_horse())
		print("t=%ds riders %s | gauchos on foot alive %d dead %d | horses alive %d carcasses %d" % [(i + 1) * 4,
				riders.map(func(r) -> String: return "%d" % r.health if is_instance_valid(r) else "gone"),
				foot.filter(func(u: Unit) -> bool: return u.is_alive()).size(), foot.filter(func(u: Unit) -> bool: return not u.is_alive()).size(),
				horses.filter(func(u: Unit) -> bool: return u.is_alive()).size(), horses.filter(func(u: Unit) -> bool: return not u.is_alive()).size()])
	# A hunter (not Native) shoots the riderless horse for meat.
	var hunter_guid: int = {"mex": 261, "usa": 461, "ind": 156, "des": 358}[main.players[1].faction]
	main._spawn_squad(hunter_guid, 1, at + Vector2(60, 60), 1)
	var hunter: Unit = Unit.all_units.filter(func(u: Unit) -> bool: return u.unit_type.guid() == hunter_guid)[0]
	var horse: Unit = null
	for u in Unit.all_units:
		if u.animal.is_horse() and u.is_alive():
			horse = u
	if horse:
		hunter.hunt(horse)
	var food: int = main.players[1].resources.food
	for i in 6:
		await get_tree().create_timer(5.0).timeout
		print("  hunter state %d target==horse %s hunting %s carrying %d step %d cd %.1f action %s horse hp %.1f" % [hunter.state, hunter.target == horse, hunter.work.hunting, hunter.work.carried, hunter._attack_step, hunter._cooldown, hunter._action, horse.health if is_instance_valid(horse) else -1.0])
	print("hunter may hunt horses %s; horse alive %s; food +%d" % [hunter.work.may_hunt_horses(),
			is_instance_valid(horse) and horse.is_alive(), main.players[1].resources.food - food])
	get_tree().quit()


## Flaming arrow shooters set an enemy building alight; the fire spreads to its neighbour
## and a builder puts it out.
func _scenario_fire() -> void:
	var hq: MapObject = main.players[1].main_building()
	var guid: int = {"mex": 201, "usa": 401, "ind": 101, "des": 301}[main.players[2].faction]
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
	var houses: Array[MapObject] = []
	var spot := hq.position + Vector2(-520, 260)
	for i in 3:
		var b := MapObject.new()
		var rect := MapObject.footprint_rect_for(type, Vector2.ZERO)
		b.position = spot + Vector2(i * (rect.size.x + 8), 0)
		b.setup(type, 2)
		main.units_root.add_child(b)
		main.nav.block_footprint(type, b.position)
		houses.append(b)
	main.camera.position = houses[1].position
	print("wall gap %d px" % (houses[1].work_rect().position.x - houses[0].work_rect().end.x))
	var archer_guid := 158
	main._spawn_squad(archer_guid, 1, spot + Vector2(0, 260), 2)
	var archers := Unit.all_units.filter(func(u: Unit) -> bool: return u.unit_type.guid() == archer_guid)
	for a: Unit in archers:
		a.attack(houses[0], true)
	for i in 10:
		await get_tree().create_timer(3.0).timeout
		if i == 3:
			for a: Unit in archers:
				a.stop()
				a.stance = Unit.Stance.PASSIVE
		print("t=%ds %s" % [(i + 1) * 3, houses.map(func(b: MapObject) -> String:
				return "%d%%%s" % [int(100 * b.health / b.max_health), " burning" if b.condition.burning > 0.0 else ""] if is_instance_valid(b) else "gone")])
	get_tree().quit()
