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
	var spots := {}
	for u: Unit in squad:
		spots[main.nav.cell_of(u.position)] = true
	print("after release: quartered %d, outside %d on %d cells" % [tower.defence.garrison.size(),
			squad.filter(func(u: Unit) -> bool: return not u.inside).size(), spots.size()])
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


## A computer player's soldiers attacking a damaged house go for the workers repairing it,
## then back to the house; a human player's soldiers keep at the house.
func _scenario_repairshot() -> void:
	var hq: MapObject = null
	for object in MapObject.all_objects:
		if object.is_building() and object.owner_index == 1:
			hq = object
	var guid: int = {"mex": 208, "usa": 408, "ind": 108, "des": 308}[main.players[1].faction]
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
	var house := MapObject.new()
	house.position = AiBuilder.find_spot(type, hq.position + Vector2(-500, 300))
	house.setup(type, 1)
	main.units_root.add_child(house)
	main.nav.block_footprint(type, house.position)
	house.take_damage(house.max_health * 0.9)
	var builders := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 1 and n.unit_type.anim_index("build") >= 0)
	builders = builders.slice(0, 2)
	main.selection._select(builders, false)
	main.selection.order_build(house)
	await get_tree().create_timer(6.0).timeout
	var repairing := builders.filter(func(u: Unit) -> bool: return u.state == Unit.State.BUILDING)
	main.players[2].computer = GameData.cmdline_option("human-attackers") == ""
	main._spawn_squad(main.FACTIONS[main.players[2].faction].army, 2, house.position + Vector2(0, -260), 3)
	var soldiers := main.units_root.get_children().filter(func(n: Node) -> bool: return n is Unit and n.team == 2 and n.is_alive())
	for i in soldiers.size():
		var soldier: Unit = soldiers[i]
		soldier.position = house.position + Vector2(-60 + 40 * (i % 4), -200 - 30 * (i / 4))  # a test shortcut
		soldier.guard_position = soldier.position
		soldier.attack(house, true)
	var at_workers := 0
	for i in 60:
		await get_tree().create_timer(0.5).timeout
		at_workers = maxi(at_workers, soldiers.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.target is Unit).size())
		if repairing.all(func(u: Unit) -> bool: return not u.is_alive()):
			break
	await get_tree().create_timer(3.0).timeout
	print("repairshot: computer %s, repairing %d, soldiers at workers %d, workers dead %d, back at the house %d" % [
			main.players[2].computer, repairing.size(), at_workers,
			repairing.filter(func(u: Unit) -> bool: return not u.is_alive()).size(),
			soldiers.filter(func(u: Unit) -> bool: return is_instance_valid(u) and u.is_alive() and u.target == house).size()])
	get_tree().quit()


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
		caster.cast(918, centre + Vector2(300, 0))
		await get_tree().create_timer(3.0).timeout
		print("eagle eye: eagles circling %d" % main.ambience.get_children().filter(func(n: Node) -> bool:
				return n is Ambience.Flyer and n.set_path == Ambience.EAGLE).size())
		caster.magic.magic_energy = 100.0
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


## Fights end when sides change: two of our soldiers shoot it out with an enemy soldier until
## our priest converts him; then nobody fights on, his old orders gone with his colours. Then
## an enemy our soldiers are attacking becomes an ally.
func _scenario_turncoat() -> void:
	var centre := Vector2(main.terrain.map.pixel_size()) / 2.0
	centre = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre))) + Vector2(0.5, 0.5)) * NavGrid.CELL
	main.players[1].researched[948] = true
	var ours_guid: int = main.FACTIONS[main.players[1].faction].army
	var theirs_guid: int = main.FACTIONS[main.players[2].faction].army
	main._spawn_squad(257, 1, centre + Vector2(-80, 40), 1)  # priest
	main._spawn_squad(ours_guid, 1, centre, 2)
	main._spawn_squad(theirs_guid, 2, centre + Vector2(0, -150), 1)
	var priest: Unit = Unit.all_units.filter(func(u: Unit) -> bool: return u.unit_type.guid() == 257)[0]
	var ours := Unit.all_units.filter(func(u: Unit) -> bool: return u.team == 1 and u.unit_type.guid() == ours_guid)
	var foe: Unit = Unit.all_units.filter(func(u: Unit) -> bool: return u.team == 2 and u.position.distance_to(centre) < 300)[0]
	await get_tree().process_frame  # past the upgrades a new unit takes on
	for u: Unit in ours + [foe]:
		u.max_health = 5000.0  # nobody falls before the priest is done
		u.health = u.max_health
	priest.stance = Unit.Stance.PASSIVE
	var victim: Unit = ours[0]
	foe.attack(victim, true)
	ours[0].attack(foe, true)
	ours[1].attack(foe, true)
	for i in 80:  # until both have hit (shots miss at times)
		if foe.health < foe.max_health and victim.health < victim.max_health:
			break
		await get_tree().create_timer(0.25).timeout
	var hit_before := foe.health < foe.max_health and victim.health < victim.max_health
	priest.cast(948, foe.position, foe)
	for i in 60:
		if foe.team == 1:
			break
		await get_tree().create_timer(0.25).timeout
	var foe_energy := foe.health
	var victim_energy := victim.health
	await get_tree().create_timer(4.0).timeout
	print("turncoat: hit before %s, converted %s; then turncoat energy kept %s, ours kept %s; attackers on him %d, he attacks ours %s" % [
			hit_before, foe.team == 1, foe.health >= foe_energy, victim.health >= victim_energy,
			Unit.all_units.filter(func(u: Unit) -> bool: return u.target == foe).size(),
			is_instance_valid(foe.target) and Unit.at_peace(foe.team, foe.target)])
	# An alliance in mid-fight: our soldiers break off, and their scans pass the new ally by.
	main._spawn_squad(theirs_guid, 2, centre + Vector2(60, -120), 1)
	var other: Unit = Unit.all_units.filter(func(u: Unit) -> bool: return u.team == 2 and u.position.distance_to(centre) < 300)[0]
	await get_tree().process_frame
	other.max_health = 5000.0
	other.health = other.max_health
	other.stance = Unit.Stance.PASSIVE
	for u: Unit in ours:
		u.attack(other, true)
	await get_tree().create_timer(3.0).timeout
	var hit_ally := other.health < other.max_health
	Diplomacy.take_side(1, 2, true)
	await get_tree().create_timer(1.0).timeout
	var ally_energy := other.health
	await get_tree().create_timer(3.0).timeout
	print("alliance: hit before %s; then energy kept %s, attackers on him %d" % [hit_ally, other.health >= ally_energy,
			Unit.all_units.filter(func(u: Unit) -> bool: return u.target == other).size()])
	get_tree().quit()


## A sandbox for trying the medicine man's spells by hand (run with --faction=ind; leave
## the fog on to see Eagle eye lift it): two medicine men, selected, with every spell and
## magic energy kept full; a friendly warrior to shield; passive enemy infantry above to
## strike with lightning; a ripe field of ours on the left for the rain dance and an enemy
## one on the right for the hail dance. --spells-refill=0 lets the energy run down.
func _scenario_spells() -> void:
	var centre := Vector2(main.terrain.map.pixel_size()) / 2.0
	centre = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre))) + Vector2(0.5, 0.5)) * NavGrid.CELL
	for guid in UnitMagic.CASTERS[UnitMagic.MEDICINE_MAN] + UnitMagic.MAGIC_UPGRADES:
		main.players[1].researched[guid] = true
	var casters := _new_units(UnitMagic.MEDICINE_MAN, 1, centre, 2)
	var friends := _new_units(152, 1, centre + Vector2(60, 40), 2)
	var foes := _new_units(458, 2, centre + Vector2(0, -280), 5)
	for u: Unit in casters + friends + foes:
		u.stance = Unit.Stance.PASSIVE
	var fields := {}
	for side in [[1, Vector2(-320, 120)], [2, Vector2(320, 120)]]:
		var field_type := ObjectTypes.get_type(GameData.type_for_guid(MapObject.FIELD_GUID, main.terrain.biome))
		var field := MapObject.new()
		field.position = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre + side[1]))) + Vector2(0.5, 0.5)) * NavGrid.CELL
		field.setup(field_type, side[0])
		main.units_root.add_child(field)
		field.stock.field_state = ObjectStock.Field.RIPE
		field.stock.amount = ObjectStock.FIELD_YIELD
		field.refresh_sprites()
		fields[side[0]] = field
	main.camera.position = centre
	main.selection._select(casters, false)
	print("spells ready: %d medicine men with %s; our field food %d, enemy field food %d, %d enemies" % [casters.size(),
			", ".join(UnitMagic.CASTERS[UnitMagic.MEDICINE_MAN].map(func(s: int) -> String: return UnitMagic.SPELLS[s].name)),
			fields[1].stock.amount, fields[2].stock.amount, foes.size()])
	var refill := GameData.cmdline_option("spells-refill", "1") != "0"
	while true:
		await get_tree().create_timer(1.0).timeout
		if refill:
			for c: Unit in casters:
				if c.is_alive():
					c.magic.magic_energy = c.magic.magic_pool()


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


## What the dead leave: a soldier, a cavalryman and a buffalo die in front of the camera and
## their remains rot; a building falls and its ruins smoulder; gulls fly over.
## --remains-wait=<s> sets how long to wait before reporting (default 14).
func _scenario_remains() -> void:
	var at: Vector2 = main.camera.position
	main._spawn_squad(Main.FACTIONS.usa.army, 2, at + Vector2(-120, 60), 1)
	main._spawn_squad(GameData.guid_for_type(ObjectTypes.named("mexicans_cavalryman_mounted")), 2, at + Vector2(0, 80), 1)
	main._spawn_squad("animals/buffalo", 0, at + Vector2(120, 60), 1)
	var dead: Array = Unit.all_units.filter(func(u: Unit) -> bool: return u.is_alive() and u.position.distance_to(at + Vector2(0, 70)) < 160 and u.team != 1)
	for u: Unit in dead:
		u.health = 0
		u.die()
		u.animal.hunted = true  # no meat waiting for a hunter: rot at once
	var house: MapObject = null
	for object in MapObject.structures:
		if object.is_building() and object.owner_index == 1:
			house = object
	if house:
		house.health = 0.0
		house.condition.destroy()
	var water := main.ambience._water_in(main.ambience._view())
	if water != Vector2.INF:
		main.ambience._add(Ambience.Flyer.new(Ambience.GULLS, water, Vector2.ZERO, 0, 40.0))
	var plumes := func() -> int:
		return house.get_children().filter(func(n: Node) -> bool: return n is OrderMarker).size() if is_instance_valid(house) else -1
	await get_tree().create_timer(5.0).timeout
	var smoking: int = plumes.call()
	await get_tree().create_timer(GameData.cmdline_option("remains-wait", "14").to_float() - 5.0).timeout
	print("remains: %s" % [dead.map(func(u: Unit) -> String:
			return "%s step %d" % [u.unit_type.directory.get_file(), u._remains._step if u._remains else -1])])
	print("smoke plumes: %d, after %ds %d, flyers: %d" % [smoking, GameData.cmdline_option("remains-wait", "14").to_int(), plumes.call(),
			main.ambience.get_child_count()])
	if GameData.cmdline_option("screenshot").is_empty():
		get_tree().quit()


func _new_units(guid: int, team: int, at: Vector2, count: int) -> Array:
	var before := Unit.all_units.duplicate()
	main._spawn_squad(guid, team, at, count)
	return Unit.all_units.filter(func(u: Unit) -> bool: return u not in before)


func _new_building(guid: int, owner: int, at: Vector2) -> MapObject:
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, main.terrain.biome))
	var building := MapObject.new()
	building.position = AiBuilder.find_spot(type, at, 300)
	building.setup(type, owner)
	main.units_root.add_child(building)
	main.nav.block_footprint(type, building.position)
	return building


## Expansion: outlaw saboteurs against an American fort with five soldiers inside. Each one
## that gets in throws out three and dies; the last takes the empty fort (--faction=des).
func _scenario_saboteur() -> void:
	var at: Vector2 = main.camera.position + Vector2(300, 0)
	var fort := _new_building(417, 2, at)
	for soldier: Unit in _new_units(458, 2, fort.position + Vector2(0, 200), 5):
		soldier.stance = Unit.Stance.PASSIVE
		fort.defence.enter(soldier)
	var counts := [fort.defence.garrison.size()]
	var saboteurs := _new_units(369, 1, fort.position + Vector2(-260, 220), 3)
	for saboteur: Unit in saboteurs:
		saboteur.sabotage(fort)
		for i in 60:
			await get_tree().create_timer(0.5).timeout
			if not saboteur.is_alive():
				break
		counts.append(fort.defence.garrison.size())
		for u: Unit in Unit.all_units:
			if u.team == 2 and u.is_alive() and not u.inside:
				u.stance = Unit.Stance.PASSIVE
	print("saboteur: garrison %s, fort now player %d, saboteurs left %d" % [counts, fort.owner_index,
			saboteurs.filter(func(u: Unit) -> bool: return u.is_alive()).size()])
	if GameData.cmdline_option("screenshot").is_empty():
		get_tree().quit()


## A saboteur disarms a Native pitfall: four seconds at it with his trap animation, then
## it is his people's and he lives on (--faction=des).
func _scenario_disarm() -> void:
	var centre := Vector2(main.terrain.map.pixel_size()) / 2.0
	centre = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre))) + Vector2(0.5, 0.5)) * NavGrid.CELL
	var type := ObjectTypes.get_type(GameData.type_for_guid(MapObject.PITFALL_GUID, main.terrain.biome))
	var pit := MapObject.new()
	pit.position = centre
	pit.setup(type, 2)
	main.units_root.add_child(pit)
	main.camera.position = centre
	var saboteur: Unit = _new_units(369, 1, centre + Vector2(-160, 40), 1)[0]
	saboteur.sabotage(pit)
	var working := false
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if saboteur._anim == saboteur.unit_type.anim_index("trap"):
			working = true
			break
	var started := Sim.msec()
	if not GameData.cmdline_option("screenshot").is_empty():
		return
	while pit.owner_index != 1 and Sim.msec() - started < 8000:
		await get_tree().create_timer(0.25).timeout
	print("disarm: trap animation %s, trap now player %d after %.1f s, saboteur alive %s" % [working, pit.owner_index,
			(Sim.msec() - started) / 1000.0, saboteur.is_alive()])
	get_tree().quit()


## Walls: dragging out the people's wall (stockade, wall, barricade) from corner to corner
## (the build controller's own drag) puts down a closed diamond of pieces; finished, it
## keeps a soldier inside in and one outside out (--faction=usa, mex or des).
func _scenario_wall() -> void:
	var n := 6
	var walls := await _wall_diamond(n)
	var centre: Vector2 = walls[0]
	var planned: int = walls[1]
	var pieces: Array = walls[2]
	var inside: Unit = _new_units(458, 1, centre, 1)[0]
	var outside: Unit = _new_units(458, 1, centre + Vector2(0, 220), 1)[0]
	inside.move_to(centre + Vector2(0, 400))
	outside.move_to(centre)
	if not GameData.cmdline_option("screenshot").is_empty():
		return
	await get_tree().create_timer(15.0).timeout
	var within := func(u: Unit) -> bool:
		var d := u.position - centre
		return absf(d.x) / (WallLine.STEP_LEFT.x * n) + absf(d.y) / (WallLine.STEP_LEFT.y * n) < 1.0
	print("wall: planned %d pieces, built %d (%s), all walls %s; inside stays in %s, outside stays out %s" % [
			planned, pieces.size(), pieces[0].display_name() if not pieces.is_empty() else "-",
			pieces.all(func(o: MapObject) -> bool: return o.complete), within.call(inside), not within.call(outside)])
	get_tree().quit()


## A finished diamond of the people's wall, `n` pieces a side, on flat open ground spiralling
## out from the middle of the map: [its centre, pieces planned, the pieces].
func _wall_diamond(n: int) -> Array:
	var p: Player = main.players[1]
	p.resources.wood = 50000
	var wall_guid: int = WallLine.PIECES[p.faction][0]
	var wall_type := ObjectTypes.get_type(GameData.type_for_guid(wall_guid, main.terrain.biome))
	var centre := Vector2.INF
	var middle := (Vector2(main.terrain.map.pixel_size()) / 2.0 / 16.0).round() * 16.0
	for ring in 40:
		for k in maxi(1, ring * 8):
			var at := middle + Vector2.from_angle(TAU * k / maxi(1, ring * 8)) * ring * 64.0
			at = (at / 16.0).round() * 16.0
			var free := true
			for side in 4:
				var top := at - WallLine.STEP_LEFT * (n / 2) - WallLine.STEP_RIGHT * (n / 2)
				for i in n + 1:
					for spot in [top + WallLine.STEP_LEFT * i, top + WallLine.STEP_RIGHT * i,
							top + WallLine.STEP_LEFT * n + WallLine.STEP_RIGHT * i, top + WallLine.STEP_RIGHT * n + WallLine.STEP_LEFT * i]:
						free = free and BuildController.can_place_for(wall_type, spot, 1)
			if free and main.nav.is_walkable(main.nav.cell_of(at)) and main.nav.is_walkable(main.nav.cell_of(at + Vector2(0, 220))):
				centre = at
				break
		if centre != Vector2.INF:
			break
	main.camera.position = centre
	var top := centre - WallLine.STEP_LEFT * (n / 2) - WallLine.STEP_RIGHT * (n / 2)
	var corners := [top, top + WallLine.STEP_LEFT * n, top + WallLine.STEP_LEFT * n + WallLine.STEP_RIGHT * n, top + WallLine.STEP_RIGHT * n]
	var bc: BuildController = main.build_controller
	var before := MapObject.structures.size()
	var planned := 0
	for i in 2:  # two L-shaped drags: top -> right -> bottom, then bottom -> left -> top
		bc.start(wall_type.id)
		bc._wall_from = corners[i * 2]
		bc._ghost.position = corners[i * 2] + WallLine.STEP_LEFT * n * (1 - 2 * i) + WallLine.STEP_RIGHT * n * (1 - 2 * i)
		bc._update_wall_ghosts()
		planned += bc._wall_plan.size()
		bc._place_wall(false)
	await get_tree().create_timer(0.5).timeout
	var pieces := MapObject.structures.slice(before)
	for piece: MapObject in pieces:
		piece.condition.add_build_work(1000.0)  # finished at once
	return [centre, planned, pieces]


## Attacking round barriers: a squad (--count, default 12) ordered against an enemy shut
## inside a diamond of wall walks as close as it can get, and the game keeps its pace;
## with --across=water the enemy is at the other headquarters on the 2 islands map, the
## long way round the water. --attacker=<GUID> picks the squad (default the people's
## soldiers; 362, the assassin, fights hand to hand). Prints the time the steps take.
func _scenario_wallattack() -> void:
	var n := 6
	var centre: Vector2
	var start: Vector2
	if GameData.cmdline_option("across") == "water":
		centre = main.players[2].main_building().position + Vector2(0, 160)
		start = main.players[1].main_building().position + Vector2(0, 160)
	else:
		centre = (await _wall_diamond(n))[0]
		start = centre + Vector2(0, WallLine.STEP_LEFT.y * n + 120)
	var victim: Unit = _new_units(458, 2, centre, 1)[0]
	victim.stance = Unit.Stance.PASSIVE
	var guid := GameData.cmdline_option("attacker", str(main.FACTIONS[main.players[1].faction].army)).to_int()
	var squad := _new_units(guid, 1, start, GameData.cmdline_option("count", "12").to_int())
	Prof.enabled = true
	Prof._totals.clear()
	Prof._counts.clear()
	var started_tick := Sim.tick
	for u: Unit in squad:
		u.order_attack(victim)
	var started := Time.get_ticks_usec()
	var worst := 0  # the longest the steps of one frame took (usec)
	var last := 0
	while Sim.tick - started_tick < 20 * Sim.RATE:
		await get_tree().physics_frame
		var spent: int = Prof._totals.get("sim step (all)", 0)
		worst = maxi(worst, spent - last)
		last = spent
	var steps := Sim.tick - started_tick
	var gap := squad.map(func(u: Unit) -> int: return int(u.position.distance_to(centre)))
	gap.sort()
	print("barrier attack: range %d, %d steps in %.1f s, step %.2f ms (worst %.1f ms), %d path searches %.2f ms per step, %d labellings %.1f ms" % [
			squad[0].attack_range(), steps, (Time.get_ticks_usec() - started) / 1e6,
			Prof._totals.get("sim step (all)", 0) / 1000.0 / maxi(1, steps), worst / 1000.0,
			Prof._counts.get("path search", 0), Prof._totals.get("path search", 0) / 1000.0 / maxi(1, steps),
			Prof._counts.get("nav regions", 0), Prof._totals.get("nav regions", 0) / 1000.0])
	print("barrier attack: nearest %s px, states %s, victim hurt %s" % [gap.slice(0, 3),
			squad.map(func(u: Unit) -> String: return Unit.State.keys()[u.state]), victim.health < victim.max_health])
	get_tree().quit()


## A scout (--disarmer=<GUID>: trapper 461, militiaman 261, hunter 358, arrow shooter 156)
## disarms a Native pitfall: four seconds with his butchering animation, then it is gone.
func _scenario_scoutdisarm() -> void:
	var centre := Vector2(main.terrain.map.pixel_size()) / 2.0
	centre = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre))) + Vector2(0.5, 0.5)) * NavGrid.CELL
	var type := ObjectTypes.get_type(GameData.type_for_guid(MapObject.PITFALL_GUID, main.terrain.biome))
	var pit := MapObject.new()
	pit.position = centre
	pit.setup(type, 2)
	main.units_root.add_child(pit)
	main.camera.position = centre
	var scout: Unit = _new_units(GameData.cmdline_option("disarmer", "461").to_int(), 1, centre + Vector2(-200, 40), 1)[0]
	scout.stance = Unit.Stance.PASSIVE
	var can := scout.saboteur.can_sabotage(pit)
	scout.sabotage(pit)
	var working := false
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if scout._anim == scout.unit_type.anim_index("butcher"):
			working = true
			break
	var started := Sim.msec()
	var shot := GameData.cmdline_option("screenshot")
	if not shot.is_empty():  # a frame a second into the work (run with a large --frames)
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
		return
	while is_instance_valid(pit) and pit.is_alive() and Sim.msec() - started < 8000:
		await get_tree().create_timer(0.25).timeout
	print("disarm by %s: can %s, butcher animation %s, trap gone %s after %.1f s, alive %s" % [scout.display_name(), can, working,
			not is_instance_valid(pit) or not pit.is_alive(), (Sim.msec() - started) / 1000.0, scout.is_alive()])
	get_tree().quit()


## An assassin digs in, lies under his mound of earth, and bursts out of it at an enemy
## walking by (--faction=des; --stage=mound stops there for a screenshot).
func _scenario_ambush() -> void:
	var centre := Vector2(main.terrain.map.pixel_size()) / 2.0
	centre = (Vector2(main.nav.nearest_walkable(main.nav.cell_of(centre))) + Vector2(0.5, 0.5)) * NavGrid.CELL
	main.camera.position = centre
	var assassin: Unit = _new_units(362, 1, centre, 1)[0]
	await get_tree().create_timer(0.5).timeout
	assassin.stealth.conceal()
	await get_tree().create_timer(4.0).timeout
	var mound := assassin.unit_type.anims_named("dig_fight")
	var buried := assassin._anim == mound[0] and assassin.stealth.concealed
	if GameData.cmdline_option("stage") == "mound":
		return
	var walker: Unit = _new_units(458, 2, centre + Vector2(-200, 0), 1)[0]
	walker.stance = Unit.Stance.PASSIVE
	walker.move_to(centre + Vector2(200, 0))
	var burst := false
	for i in 80:
		await get_tree().create_timer(0.1).timeout
		if assassin._anim == mound[1]:
			burst = true
		if assassin.state == Unit.State.ATTACKING:
			break
	print("ambush: under the mound %s, burst out %s, then attacking %s" % [buried, burst, assassin.state == Unit.State.ATTACKING])
	get_tree().quit()


## Expansion: the tepee of the ancestors invokes the warrior spirit over three warriors
## (--faction=ind).
func _scenario_spirit() -> void:
	var tepee := _new_building(116, 1, main.camera.position + Vector2(250, 0))
	var warriors := _new_units(152, 1, tepee.position + Vector2(0, 200), 3)
	var before: float = warriors[0].spirit_factor()
	var without_upgrade := tepee.production.invoke_spirit()
	main.players[1].researched[968] = true
	var invoked := tepee.production.invoke_spirit()
	var again := tepee.production.invoke_spirit()
	var auras := warriors.filter(func(u: Unit) -> bool: return is_instance_valid(u._aura)).size()
	print("spirit: before upgrade %s, invoked %s, damage x%.2f -> x%.2f, energy left %d, again %s, auras %d" % [
			without_upgrade, invoked, before, warriors[0].spirit_factor(), tepee.production.spirit_energy, again, auras])
	await get_tree().create_timer(BuildingProduction.SPIRIT_SECONDS + 1.0).timeout
	print("spirit: afterwards damage x%.2f, auras %d" % [warriors[0].spirit_factor(),
			warriors.filter(func(u: Unit) -> bool: return is_instance_valid(u._aura)).size()])
	if GameData.cmdline_option("screenshot").is_empty():
		get_tree().quit()


## Expansion: four Mexican soldiers board an armored stagecoach (two fit, four after the
## Enlarge stagecoach upgrade), shoot from it at an enemy, and die when it is wrecked
## (--faction=mex).
func _scenario_coach() -> void:
	var at: Vector2 = main.camera.position
	var coach: Unit = _new_units(266, 1, at, 1)[0]
	var guards := _new_units(258, 1, at + Vector2(-120, 80), 4)
	main.selection.order_board(coach, guards)
	await get_tree().create_timer(8.0).timeout
	var first := "%d / %d" % [coach.water.passengers.size(), coach.water.capacity()]
	main.players[1].researched[UnitWater.ENLARGE_COACH] = true
	main.selection.order_board(coach, guards.filter(func(u: Unit) -> bool: return not u.inside))
	await get_tree().create_timer(8.0).timeout
	var enlarged := "%d / %d" % [coach.water.passengers.size(), coach.water.capacity()]
	var enemy: Unit = _new_units(458, 2, coach.position + Vector2(160, 0), 1)[0]
	enemy.stance = Unit.Stance.PASSIVE
	var enemy_health := enemy.health
	await get_tree().create_timer(10.0).timeout
	var hit := enemy.health < enemy_health
	coach.take_damage(coach.max_health * 2.0)
	await get_tree().process_frame
	print("coach: aboard %s, enlarged %s, enemy hit %s, guards dead with the coach %d" % [first, enlarged, hit,
			guards.filter(func(u: Unit) -> bool: return not u.is_alive()).size()])
	if GameData.cmdline_option("screenshot").is_empty():
		get_tree().quit()


## A nurse tends three badly wounded soldiers: each point of life costs her a point of
## healing energy, and once it is spent she rests until it has come back.
func _scenario_heal() -> void:
	var at: Vector2 = main.players[1].main_building().position + Vector2(0, 260)
	main._spawn_squad(457, 1, at, 1)
	main._spawn_squad(main.FACTIONS[main.players[1].faction].army, 1, at + Vector2(60, 0), 3)
	var nurse: Unit = Unit.all_units.filter(func(u: Unit) -> bool: return u.unit_type.guid() == 457)[0]
	var wounded := Unit.all_units.filter(func(u: Unit) -> bool: return u.team == 1 and u != nurse and u.position.distance_to(at) < 150)
	var lost := 0.0
	for u: Unit in wounded:
		u.health = u.max_health * 0.1
		lost += u.max_health * 0.9
	var start := nurse.magic.magic_energy
	var life := func() -> float: return wounded.reduce(func(sum: float, u: Unit) -> float: return sum + u.health, 0.0)
	var before: float = life.call()
	await get_tree().create_timer(40.0).timeout
	var healed: float = life.call() - before
	print("heal: life lost %d; healed %d for %d energy, energy now %d" % [lost, healed,
			start + UnitMagic.MAGIC_REGEN * 40.0 - nurse.magic.magic_energy, nurse.magic.magic_energy])
	get_tree().quit()
