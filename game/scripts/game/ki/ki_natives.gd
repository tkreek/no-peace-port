class_name KiNatives
extends RefCounted
## The engine calls KI modules make (AmericaAddOn.exe dispatcher 0x43a250): arithmetic,
## arrays, waiting, the people's shared tables and semaphores, questions about objects and
## the stockpiles, searches, and orders to units and buildings. Arguments are pushed left
## to right, so the last one is on top. Ids the original leaves out do nothing.
## docs/technical/ki.md lists every native with its original behaviour.

## Arguments taken by each native (the rest take none).
const ARGS := {
	1: 2, 2: 2, 3: 2, 4: 2, 5: 2, 6: 2, 7: 2, 8: 2, 10: 2, 11: 2, 12: 2, 13: 2, 14: 2, 15: 2,
	20: 2, 21: 2, 22: 1, 31: 2, 32: 3, 33: 2, 40: 1, 41: 1, 42: 2, 43: 3, 44: 2, 45: 2, 46: 3,
	47: 2, 48: 2, 49: 3, 50: 2, 101: 1, 102: 1, 103: 1, 104: 1, 105: 1, 106: 1, 107: 4, 108: 4,
	109: 4, 110: 1, 111: 1, 112: 1, 113: 2, 114: 2, 115: 2, 116: 2, 117: 2, 118: 2, 120: 1,
	121: 1, 122: 1, 123: 1, 124: 1, 125: 1, 130: 2, 131: 2, 132: 1, 133: 2, 134: 4, 135: 4,
	136: 1, 137: 1, 138: 2, 139: 4, 140: 4, 141: 4, 142: 2, 143: 3, 144: 2, 145: 2, 146: 2,
	147: 1, 148: 1, 149: 2, 189: 1, 200: 5, 201: 5, 202: 5, 203: 5, 204: 5, 205: 5, 206: 1,
	207: 2, 210: 2, 211: 2, 212: 2, 213: 2, 214: 2, 215: 1, 216: 1, 217: 1, 218: 1, 219: 1,
	220: 2, 221: 1, 222: 1, 223: 1, 228: 2, 229: 3, 231: 1, 232: 1, 233: 3, 234: 3, 235: 3,
	236: 3, 237: 2, 238: 2, 239: 2, 240: 2, 241: 2, 242: 2, 243: 2, 244: 2, 245: 3, 246: 3,
	247: 3, 248: 3, 250: 2, 251: 2, 252: 2, 253: 2, 270: 1, 280: 2, 281: 1, 282: 1, 283: 1,
	284: 1, 285: 1, 286: 1, 287: 1, 288: 1, 290: 1, 291: 1, 292: 4, 295: 1, 296: 1, 297: 1,
	300: 1, 302: 1, 303: 1, 306: 1, 307: 1, 311: 3, 312: 1, 320: 3, 321: 3, 322: 2, 323: 2,
	324: 2, 325: 2, 326: 2, 327: 3, 328: 3, 334: 1, 335: 2, 336: 1, 337: 1, 338: 1, 339: 5,
	340: 2, 341: 1, 342: 1, 343: 2, 344: 2, 345: 1, 346: 2, 347: 2, 348: 1, 351: 1, 353: 1,
	354: 5, 355: 3, 356: 1, 357: 1, 358: 1, 359: 1, 360: 2, 361: 2, 365: 2, 366: 2, 367: 1,
	368: 5, 369: 1, 370: 5, 371: 5, 372: 4, 373: 1, 374: 2, 375: 5, 376: 1, 377: 1, 378: 1,
	379: 1, 380: 1, 381: 2, 382: 2, 383: 5, 384: 5, 385: 3, 386: 3, 387: 4, 389: 5, 390: 4,
	391: 4, 392: 5, 393: 5, 394: 3, 395: 5, 398: 4, 399: 1, 400: 1, 401: 3,
}
## Natives that only push a number.
const CONSTANTS := {
	150: 0x20000, 151: 8, 152: 4, 153: 2, 154: 0x40, 155: 0x10, 156: 1, 157: 0x800,
	158: 0x1000000, 159: 4, 160: 0x8000, 161: 0x1a3, 162: 0x199, 163: 0x1c7, 164: 8, 165: 0x10,
	166: 0x40000, 167: 2, 168: 0x80, 169: 0x20, 170: 0x400, 171: 0x1000, 172: 0x2000,
	173: 0x4000, 174: 0x10000, 175: 0x80000, 176: 0x100000, 177: 0x200000, 178: 0x400000,
	179: 0x800000, 180: 0x2000000, 181: 0x4000000, 182: 0, 183: 1, 184: 2, 185: 3, 186: 0x191,
	187: 0x40, 190: 0x100, 191: 0x200, 192: 1, 193: 2, 194: 4, 195: 8, 196: 0x400, 197: 0x800,
	198: 0x10, 310: 0x20, 350: 0x1000, 362: 0,
}
const STOCKS := {271: "wood", 272: "gold", 273: "horses", 274: "food", 278: "guns",
		281: "wood", 282: "gold", 283: "horses", 284: "food", 288: "guns"}
## Stances 0..3 (constants 182-185) and the remake's.
const STANCES := [Unit.Stance.AGGRESSIVE, Unit.Stance.DEFENSIVE, Unit.Stance.HOLD, Unit.Stance.PASSIVE]
## Things the neutral production order (142, or 138 given the same GUIDs) makes and the
## remake's queue entries.
const NEUTRAL_PRODUCTS := {480: BuildingProduction.HORSE_GUID, 482: BuildingProduction.COW_GUID,
		710: BuildingProduction.GUN_GUID, 711: BuildingProduction.LIQUOR_GUID}
## Spells by native (320-324).
const SPELL_NATIVES := {320: 918, 321: 919, 322: 920, 324: 921, 323: 922}
## How far build_near looks around its spot (16 px steps, up to 500 px each way).
const BUILD_SEARCH := 500
const ENEMY_REACH := 500.0
const WAY_CELL := 128.0  ## _in_the_way's cells


static func call_native(id: int, task: KiTask) -> void:
	if CONSTANTS.has(id):
		task.push(CONSTANTS[id])
		return
	var n: int = ARGS.get(id, 0)
	var a := PackedInt32Array()
	a.resize(n)
	for i in range(n - 1, -1, -1):
		a[i] = task.pop()
	var me := task.player.index
	if MissionStats.on:
		MissionStats.native(id, task, a)
	match id:
		# ---------------------------------------------------------- arithmetic
		1: task.push(a[0] + a[1])
		2: task.push(a[0] - a[1])
		3: task.push(a[0] * a[1])
		4: task.push(_div(a[0], a[1] if a[1] != 0 else 1))
		5: task.push(a[0] & a[1])
		6: task.push(a[0] | a[1])
		7: task.push(a[0] ^ a[1])
		8: task.push(a[0] - _div(a[0], a[1]) * a[1] if a[1] != 0 else 0)
		10: task.push(int(a[0] > a[1]))
		11: task.push(int(a[0] < a[1]))
		12: task.push(int(a[0] == a[1]))
		13: task.push(int(a[0] != a[1]))
		14: task.push(int(a[0] >= a[1]))
		15: task.push(int(a[0] <= a[1]))
		20: task.push(int(a[0] != 0 and a[1] != 0))
		21: task.push(int(a[0] != 0 or a[1] != 0))
		22: task.push(int(a[0] == 0))
		# ---------------------------------------------------------- arrays and waiting
		31, 42, 45, 48: task.push(task.store.get_element(a[0], a[1]))
		32, 43, 46, 49: task.store.set_element(a[0], a[1], a[2])
		33, 44, 47, 50: task.set_array(a[0], task.array(a[1]).duplicate())
		40, 41: task.sleep_ms = a[0]
		# ---------------------------------------------------------- shared state
		219: task.push(task.player.globals[a[0]] if a[0] >= 0 and a[0] < KiPlayer.GLOBALS else 0)
		220:
			if a[0] >= 0 and a[0] < KiPlayer.GLOBALS:
				task.player.globals[a[0]] = a[1]
		221:
			if a[0] >= 0 and a[0] < KiPlayer.SEMAPHORES:
				if task.player.semaphores[a[0]] == 0:
					task.player.semaphores[a[0]] = 1
				else:
					task.waits_for = a[0]
		222:
			if a[0] >= 0 and a[0] < KiPlayer.SEMAPHORES:
				task.player.semaphores[a[0]] = 0
		223: task.push(int(a[0] >= 0 and a[0] < KiPlayer.SEMAPHORES and task.player.semaphores[a[0]] != 0))
		233, 234, 235, 236:
			if _cell(a[0], a[1]):
				task.player.tables[a[0]][a[1]] = a[2]
		237, 238, 239, 240: task.push(task.player.tables[a[0]][a[1]] if _cell(a[0], a[1]) else 0)
		241, 242, 243, 244:
			if _cell(a[0], a[1]):
				var table := task.player.tables[a[0]]
				table.remove_at(a[1])
				table.append(0)
				task.player.tables[a[0]] = table
		245, 246, 247, 248:
			if _cell(a[0], a[1]):
				var table := task.player.tables[a[0]]
				table.insert(a[1], a[2])
				table.resize(KiPlayer.TABLE_SIZE)
				task.player.tables[a[0]] = table
		304:
			task.player.atomic = true
			task.player.atomic_slot = task.player.current_slot
		305: task.player.atomic = false
		329, 330:
			var queue := task.player.hurt_buildings if id == 329 else task.player.hurt_units
			if queue.is_empty():
				task.push(0)
			else:
				task.event_handle = queue.pop_front()
				task.push(1)
		331, 332: task.push(task.event_handle)
		# ---------------------------------------------------------- objects
		101, 103, 105: task.push(_x(a[0]))
		102, 104, 106: task.push(_y(a[0]))
		110, 111, 112: task.push(int(KiWorld.resolve(a[0]) != null))
		113, 114, 115:
			var node := KiWorld.resolve(a[0])
			task.push(int(node != null and KiWorld.state_bits(node) & a[1] == a[1]))
		116, 117, 118:
			var node := KiWorld.resolve(a[0])
			task.push(int(node != null and KiWorld.state_bits(node) & a[1] != 0))
		365:
			var node := KiWorld.resolve(a[0])
			task.push(int(node != null and KiWorld.class_bits(node) & a[1] == a[1]))
		366:
			var node := KiWorld.resolve(a[0])
			task.push(int(node != null and KiWorld.class_bits(node) & a[1] != 0))
		295, 296, 297:
			var node := KiWorld.resolve(a[0])
			task.push(KiWorld.guid_of(node) if node else -1)
		312, 367, 379:
			var node := KiWorld.resolve(a[0])
			task.push(KiWorld.owner_of(node) if node else 0)
		306, 307:
			var node := KiWorld.resolve(a[0])
			task.push(int(node.health * 100.0 / maxf(1.0, node.max_health)) if node else -1)
		132:
			var node := KiWorld.resolve(a[0]) as MapObject
			task.push(node.stock.amount if node and node.stock else 0)
		217:
			var node := KiWorld.resolve(a[0]) as MapObject
			task.push(node.defence.capacity() - node.defence.garrison.size() if node and node.defence else 0)
		218:
			var node := KiWorld.resolve(a[0]) as Unit
			task.push(node.water.capacity() - node.water.passengers.size() if node else 0)
		300, 359:
			var node := KiWorld.resolve(a[0]) as MapObject
			task.push(node.stock.amount if node and node.stock and node.is_gold_warehouse() else (-1 if id == 300 and node == null else 0))
		303:
			var node := KiWorld.resolve(a[0]) as Unit
			task.push(node.work.carried if node else 0)
		337:
			var node := KiWorld.resolve(a[0]) as MapObject
			task.push(node.production.queue[0] if node and node.production and not node.production.queue.is_empty() else 0)
		353:
			var node := KiWorld.resolve(a[0]) as Unit
			task.push(int(node.magic.magic_energy * 100.0 / maxf(1.0, node.magic.magic_pool())) if node and node.magic.has_energy() else 0)
		356:
			var node := KiWorld.resolve(a[0]) as Unit
			task.push(int(node.unit_type.speed) if node else 0)
		357: task.push(0)
		373:
			var node := KiWorld.resolve(a[0]) as Unit
			task.push(int(node.attack_range()) if node else 0)
		400: task.push(0)
		134:
			task.push(int(sqrt(float(a[2] - a[0]) ** 2 + float(a[3] - a[1]) ** 2)))
		# ---------------------------------------------------------- searches and claims
		107: task.push(KiWorld.find_claiming(me, me, a[0] | KiWorld.C_BUILDING, Vector2(a[1], a[2]), a[3]))
		108: task.push(KiWorld.find_claiming(me, 0, a[0], Vector2(a[1], a[2]), a[3]))
		109: task.push(KiWorld.find_claiming(me, me, a[0] | KiWorld.C_UNIT, Vector2(a[1], a[2]), a[3]))
		200: task.push(KiWorld.find_claiming(me, a[0], a[1] | KiWorld.C_BUILDING, Vector2(a[2], a[3]), a[4]))
		201: task.push(KiWorld.find_claiming(me, a[0], a[1], Vector2(a[2], a[3]), a[4]))
		202: task.push(KiWorld.find_claiming(me, a[0], a[1] | KiWorld.C_UNIT, Vector2(a[2], a[3]), a[4]))
		139, 140: task.push(KiWorld.find_type_claiming(me, me, a[0], Vector2(a[1], a[2]), a[3]))
		141: task.push(KiWorld.find_type_claiming(me, 0, a[0], Vector2(a[1], a[2]), a[3]))
		203, 204: task.push(KiWorld.find_type_claiming(me, a[0], a[1], Vector2(a[2], a[3]), a[4]))
		205: task.push(KiWorld.find_type_claiming(me, 0, a[1], Vector2(a[2], a[3]), a[4], a[0]))
		368: task.push(KiWorld.nearest_plain(a[0], Vector2(a[1], a[2]), a[3] | KiWorld.C_UNIT, -1, a[4], 0))
		389: task.push(KiWorld.nearest_plain(a[0], Vector2(a[1], a[2]), a[3], -1, a[4], 0))
		392: task.push(KiWorld.nearest_plain(a[0], Vector2(a[1], a[2]), a[3] | KiWorld.C_BUILDING, -1, a[4], 0))
		370: task.push(KiWorld.nearest_plain(a[0], Vector2(a[1], a[2]), a[3], -1, 0, a[4]))
		371, 393: task.push(KiWorld.nearest_plain(a[0], Vector2(a[1], a[2]), 0, a[3], 0, a[4]))
		383: task.push(KiWorld.claim_nearest(me, a[0], Vector2(a[1], a[2]), a[3] | KiWorld.C_UNIT, -1, a[4]))
		384: task.push(KiWorld.claim_nearest(me, a[0], Vector2(a[1], a[2]), 0, a[3], a[4]))
		385: task.push(KiWorld.claim_nearest(me, a[0], Vector2.ZERO, 0, -1, a[2]))
		386: task.push(KiWorld.claim_nearest(me, a[0], Vector2.ZERO, 0, a[1], a[2]))
		387, 398: task.push(KiWorld.enemy_near(me, Vector2(a[0], a[1]), a[2], a[3]))
		120: task.push(KiWorld.nearest_plain(me, Vector2.ZERO, a[0] | KiWorld.C_BUILDING, -1, 0, 0))
		121: task.push(KiWorld.nearest_plain(me, Vector2.ZERO, a[0] | KiWorld.C_UNIT, -1, 0, 0))
		122: task.push(KiWorld.nearest_plain(0, Vector2.ZERO, a[0], -1, 0, 0))
		372: task.push(_nearest_wall(a[0], Vector2(a[1], a[2]), a[3]))
		380:
			var node := KiWorld.resolve(a[0])
			if node:
				KiWorld.claim(node, me)
		123, 124, 125:
			var node := KiWorld.resolve(a[0])
			if node:
				KiWorld.release(node, me)
		339, 375: task.push(Mission.count(a[0], a[1], Rect2(a[2] - a[4], a[3] - a[4], a[4] * 2, a[4] * 2),
				id == 375, true))
		228:
			var water := _find_water(Vector2(a[0], a[1]))
			if water != Vector2.INF:
				task.found_spot = Vector2i(water)
			task.push(int(water != Vector2.INF))
		226: task.push(task.found_spot.x)
		227: task.push(task.found_spot.y)
		394, 395:
			var from := Vector2(_x(a[0]), _y(a[0])) if id == 394 else Vector2(a[1], a[2])
			var to := Vector2(a[1], a[2]) if id == 394 else Vector2(a[3], a[4])
			var reached := _reachable(from, to)
			task.reachable_spot = Vector2i(reached)
			task.push(int(reached != Vector2.INF))
		396: task.push(task.reachable_spot.x)
		397: task.push(task.reachable_spot.y)
		229, 230, 231, 232: task.push(0)
		# ---------------------------------------------------------- the peoples
		308: task.push(me)
		188: task.push(_nation(me))
		189: task.push(_nation(a[0]))
		271, 272, 273, 274, 278: task.push(_stock(me, STOCKS[id]))
		281, 282, 283, 284, 288: task.push(_stock(a[0], STOCKS[id]))
		301: task.push(_people(me).warehoused_gold() if _people(me) else 0)
		302: task.push(_people(a[0]).warehoused_gold() if _people(a[0]) else 0)
		275: task.push(_free_space(me))
		285: task.push(_free_space(a[0]))
		279: task.push(_people(me).population() if _people(me) else 0)
		289: task.push(Match.population_limit)
		270: task.push(_count(me, a[0]))
		280, 340: task.push(_count(a[0], a[1]) if a[0] >= 0 and a[0] <= 10 else 0)
		276: task.push(Mission.count(me, 108) + Mission.count(me, 208) + Mission.count(me, 408))
		286: task.push(Mission.count(a[0], 108) + Mission.count(a[0], 208) + Mission.count(a[0], 408))
		277: task.push(Mission.count(me, MapObject.FIELD_GUID))
		287: task.push(Mission.count(a[0], MapObject.FIELD_GUID))
		199: task.push(BuildingProduction.HORSE_BUILDINGS.reduce(func(t: int, g: int) -> int: return t + Mission.count(me, g), 0))
		334:
			var people := _people(me)
			task.push(int(people != null and a[0] >= 900 and a[0] < 1000 and (people.researched.has(a[0]) or people.is_researching(a[0]))))
		369:
			var people := _people(me)
			task.push(int(people != null and people.researched.has(a[0])))
		352: task.push(0 if _difficulty() == 0 else 4 - _difficulty())
		363: task.push(int(Match.game_type))
		364: task.push(Player.by_index.size())
		224: task.push(KiManager.current.map_size.x if KiManager.current else 0)
		225: task.push(KiManager.current.map_size.y if KiManager.current else 0)
		206: task.push(_relation(me, a[0]))
		207: task.push(_relation(a[0], a[1]))
		335:
			var low := a[0]
			var high := a[1]
			var drawn := low + int((high - low) * Sim.rng.randi_range(0, 32767) / 32767.0)
			task.push(mini(maxi(drawn, low), high - 1))
		136, 291: task.push(int(_can_have(me, a[0], true)))
		137, 290: task.push(int(_can_have(me, a[0], false)))
		376, 377, 378:
			var people := _people(me)
			if people:
				people.add({376: "food", 377: "wood", 378: "gold"}[id], a[0])
		381: Diplomacy.set_stance(a[0], a[1], Diplomacy.ALLY)
		382: Diplomacy.set_stance(a[0], a[1], Diplomacy.ENEMY)
		388:
			var people := _people(me)
			if people:
				people.surrendered = true
		# ---------------------------------------------------------- orders to units
		143, 311:
			var unit := _own_unit(a[0])
			if unit and a[1] > 0 and a[2] > 0 and not unit.inside:
				unit.move_to(Vector2(a[1], a[2]))
		328:
			var unit := _own_unit(a[0])
			if unit and a[1] > 0 and a[2] > 0:
				unit.attack_move(Vector2(a[1], a[2]))
		327:
			var unit := _own_unit(a[0])
			if unit:
				unit.patrol(Vector2(a[1], a[2]))
		145, 251, 250, 149:
			var unit := _own_unit(a[0])
			var target := KiWorld.resolve(a[1])
			if unit and target:
				if target is Unit and (target as Unit).animal.has_meat() and unit.unit_type.is_hunter():
					unit.hunt(target)
				else:
					unit.attack(target, true)
		146:
			var unit := _own_unit(a[0])
			if unit and a[1] >= 0 and a[1] < STANCES.size():
				unit.set_stance(STANCES[a[1]])
		336:
			var unit := _own_unit(a[0])
			if unit:
				unit.stop()
		326, 374:
			var unit := _own_unit(a[0])
			var leader := KiWorld.resolve(a[1]) as Unit
			if unit and leader:
				unit.follow(leader)
		211:
			var unit := _own_unit(a[0])
			var building := KiWorld.resolve(a[1]) as MapObject
			if unit and building and building.defence and building.defence.capacity() > 0:
				unit.take_quarters(building)
		212, 361:
			var animal := _own_unit(a[0])
			var building := KiWorld.resolve(a[1]) as MapObject
			if animal and building:
				if animal.animal.is_horse():
					animal.animal.stable(building)
				else:
					animal.animal.deliver(building)
		213:
			var unit := _own_unit(a[0])
			var boat := KiWorld.resolve(a[1]) as Unit
			if unit and boat:
				unit.board(boat)
		214, 358:
			var boat := _own_unit(a[0])
			if boat and not boat.water.passengers.is_empty():
				boat.unload_at(boat.position)
		130:
			var unit := _own_unit(a[0])
			var tree := KiWorld.resolve(a[1]) as MapObject
			if unit and tree:
				unit.gather(_tree_near(tree.position))
		131, 252:
			var unit := _own_unit(a[0])
			var source := KiWorld.resolve(a[1]) as MapObject
			if unit and source and (source.stock == null or source.stock.amount > 0 or source.is_field()):
				unit.gather(source)
		133, 360:
			var wagon := _own_unit(a[0])
			var building := KiWorld.resolve(a[1]) as MapObject
			if wagon and building:
				wagon.haul(building)
		253:
			var unit := _own_unit(a[0])
			var horse := KiWorld.resolve(a[1]) as Unit
			if unit and horse:
				unit.mount(horse)
		148:
			var unit := _own_unit(a[0])
			if unit:
				unit.dismount()
		144:
			var unit := _own_unit(a[0])
			var site := KiWorld.resolve(a[1]) as MapObject
			if unit and site:
				unit.build(site)
		135, 292:
			var guid := a[1] if id == 135 else a[3]
			var at := Vector2(a[2], a[3]) if id == 135 else Vector2(a[1], a[2])
			var spot := _build_near(task, _own_unit(a[0]), guid, at, id)
			if KiManager.current and KiManager.current.trace_level >= 2:
				print("KI t=%.1f p%d %08d build %d near %s: %s" % [Sim.time(), me, task.module.number, guid, at, spot])
			task.push(int(spot))
		293: task.push(task.build_spot.x)
		294: task.push(task.build_spot.y)
		147:
			var unit := _own_unit(a[0])
			if unit:
				unit.take_damage(unit.health + 1.0)
		215, 341:
			var unit := _own_unit(a[0])
			if unit:
				unit.conceal()
		216, 342:
			var unit := _own_unit(a[0])
			if unit:
				unit.stealth.uncover()
		320, 321:
			var unit := _own_unit(a[0])
			if unit:
				unit.cast(SPELL_NATIVES[id], Vector2(a[1], a[2]))
		322, 323, 324:
			var unit := _own_unit(a[0])
			var target := KiWorld.resolve(a[1])
			if unit and target:
				unit.cast(SPELL_NATIVES[id], target.position, target as Unit)
		346:
			var unit := _own_unit(a[0])
			var target := KiWorld.resolve(a[1]) as Unit
			if unit and target and UnitMagic.CASTERS.has(unit.unit_type.guid()):
				unit.cast(UnitMagic.CASTERS[unit.unit_type.guid()][0], target.position, target)
		347:
			pass  # healers tend the hurt nearby on their own
		325:
			var unit := _own_unit(a[0])
			var building := KiWorld.resolve(a[1]) as MapObject
			if unit and building:
				unit.rob(building)
		343:
			var unit := _own_unit(a[0])
			var trap := KiWorld.resolve(a[1]) as MapObject
			if unit and trap:
				unit.sabotage(trap)
		344:
			var wagon := _own_unit(a[0])
			var tepee := KiWorld.resolve(a[1]) as MapObject
			if wagon and tepee:
				wagon.pack(tepee)
		345:
			pass  # unpacking needs a spot; the scripts never ask for it
		354:
			for i in mini(20, a[1]):
				var unit := _own_unit(task.player.tables[a[0]][i] if a[0] >= 0 and a[0] < KiPlayer.TABLES else 0)
				if unit:
					unit.attack_move(Vector2(a[3], a[4]))
		390, 391:
			var target := KiWorld.resolve(a[3])
			for i in mini(20, a[1]):
				var unit := _own_unit(task.player.tables[a[0]][i] if a[0] >= 0 and a[0] < KiPlayer.TABLES else 0)
				if unit and target:
					unit.attack(target, true)
		# ---------------------------------------------------------- orders to buildings
		138, 142:
			var building := _own_building(a[0])
			if building and building.production:
				# The human player's order, without the build menu's limits (0x40cd10).
				var item: int = NEUTRAL_PRODUCTS.get(a[1], a[1])
				if not building.production.order(item) and MissionStats.on:
					var why := building.production.order_refusal(item)
					# The original turns these away too: the scripts poll until it takes them.
					var same := why in ["researched", "in research", "leader", "queue full"]
					MissionStats.refused(id, task, "%s: GUID %d (%s)" % ["as original" if same else "refused", a[1], why])
			elif building and MissionStats.on:
				MissionStats.refused(id, task, "building makes nothing")
		210, 351:
			var building := _own_building(a[0])
			if building and building.defence:
				building.defence.release()
		338:
			var building := _own_building(a[0])
			if building and building.production and not building.production.queue.is_empty():
				building.production.cancel(0)
		348:
			var building := _own_building(a[0])
			if building:
				building.take_damage(5000.0 / 256.0)
		355:
			var building := _own_building(a[0])
			if building and building.production and a[1] > 0 and a[2] > 0:
				building.production.set_rally(Vector2(a[1], a[2]))
		399, 401:
			pass  # building abilities: no mission uses them for anything that matters
		_:
			if MissionStats.on:
				MissionStats.unimplemented(id, task)
	if MissionStats.on:
		MissionStats.native_done(id, task, a)


## C division: truncates toward zero.
static func _div(x: int, y: int) -> int:
	var q := absi(x) / absi(y)
	return q if (x < 0) == (y < 0) else -q


static func _cell(table: int, i: int) -> bool:
	return table >= 0 and table < KiPlayer.TABLES and i >= 0 and i < KiPlayer.TABLE_SIZE


static func _x(h: int) -> int:
	var node := KiWorld.resolve(h)
	return int(node.position.x) if node else -1


static func _y(h: int) -> int:
	var node := KiWorld.resolve(h)
	return int(node.position.y) if node else -1


## Scripts order any people's units (the original does not check), but a dead or missing
## one does nothing.
static func _own_unit(h: int) -> Unit:
	return KiWorld.resolve(h) as Unit


static func _own_building(h: int) -> MapObject:
	return KiWorld.resolve(h) as MapObject


static func _people(index: int) -> Player:
	return Player.by_index.get(index)


static func _stock(index: int, key: String) -> int:
	var people := _people(index)
	return int(people.resources.get(key, 0)) if people else 0


static func _free_space(index: int) -> int:
	var people := _people(index)
	return people.population_limit() - people.population() if people else 0


static func _nation(index: int) -> int:
	var people := _people(index)
	return MissionData.PEOPLES.find(people.faction) if people else -1


static func _difficulty() -> int:
	return Match.difficulty if Match.configured or not Match.campaign.is_empty() else 2


## The relation bits the scripts read: 1 hostile, 2 neutral, 4 allied, 0x20 sharing sight,
## 0x40 a computer player, 0x80 a human one; 8 itself, 0x10 when either is not playing.
static func _relation(a: int, b: int) -> int:
	if a == b:
		return 8
	if _people(a) == null or _people(b) == null:
		return 0x10
	var bits := Diplomacy.relation(a, b) & (Diplomacy.ENEMY | Diplomacy.NEUTRAL | Diplomacy.ALLY | Diplomacy.VISION)
	return bits | (0x80 if b == Orders.local_player else 0x40)


## How many `guid` people `index` has (0x42a0b0): its list's tally by type, which has no wall
## pieces (they are in list 10, see KiWorld.objects_of), so the scripts that start a
## production module for every building they own leave walls out.
static func _count(index: int, guid: int) -> int:
	return 0 if WallLine.is_wall(guid) else Mission.count(index, guid)


## Whether people `index` has what `guid` needs (and can pay for it, building costs for
## buildings; units: what training takes).
static func _can_have(index: int, guid: int, train: bool) -> bool:
	var people := _people(index)
	if people == null:
		return false
	if guid == MapObject.FIELD_GUID:
		# One field for every people; the stats file names the Native granary as what it
		# needs. As the build menu: a food store of one's own with room for another field.
		if MapObject.field_allowance(index) <= 0:
			return false
	elif not people.meets_prerequisites(guid):
		return false
	# Horses, cows, guns and liquor cost what the neutral production order (142) takes.
	var cost: Dictionary = MapRules.stats(index, NEUTRAL_PRODUCTS.get(guid, guid)).get("cost", {}).duplicate()
	if not train:
		if GameData.stats(guid).get("kind") == "unit":
			return true  # the scripts ask can_build about units for their prerequisites
		cost.erase("population")
	elif cost.has("population"):
		if _free_space(index) < int(cost.population):
			return false
		cost.erase("population")
	return people.can_afford(cost)


## A site of `guid` for `worker` near `at` (spiral in 16 px steps up to 500 px away) on the
## worker's height level where the footprint fits as it would for a player (the original's
## placement helper 0x429a20 knows no margins or gaps), its cost paid and the worker sent to
## build it; fields the same (AmericaAddOn.exe 0x438670).
static func _build_near(task: KiTask, worker: Unit, guid: int, at: Vector2, id := 135) -> bool:
	var manager := KiManager.current
	if worker == null or manager == null:
		return false
	var type := ObjectTypes.get_type(GameData.type_for_guid(guid, manager.biome))
	if type == null:
		if MissionStats.on:
			MissionStats.build_failed(id, task, guid, "no such building")
		return false
	var owner := worker.team
	var nav := NavGrid.current
	var level := _level(nav, worker.position)
	# The placement test wants the price at every spot: without it there is none (and the
	# spiral of up to 3969 spots, each looking at every unit, is spared).
	var people: Player = Player.by_index.get(owner)
	if people == null or not people.can_afford(BuildController._cost_of(type, owner)):
		if MissionStats.on:
			MissionStats.no_spot(id, task, owner, type, guid)
		return false
	var cells := {}  # the footprint test's answer per cell: the spots overlap
	var wall := WallLine.is_wall(GameData.guid_for_type(type.id))  # as can_place_for has it
	var way := _in_the_way(owner, GameData.guid_for_type(type.id) == MapObject.FIELD_GUID)
	for ring in range(0, BUILD_SEARCH / 16 + 1):
		for dy in range(-ring, ring + 1):
			# The ring alone, in order: its top and bottom rows whole, the two ends between.
			for dx in range(-ring, ring + 1, 1 if absi(dy) == ring else 2 * ring):
				var spot := at + Vector2(dx, dy) * 16.0
				if _level(nav, spot) == level and _footprint_fits(nav, type, spot, wall, cells) \
						and _clear_of(way, MapObject.footprint_rect_for(type, spot)) \
						and BuildController.can_place_for(type, spot, owner):
					var site := Orders.build_controller.place_site(owner, type.id, spot, false, null, [worker]) \
							if Orders.build_controller else null
					if site == null:
						if MissionStats.on:
							MissionStats.site_refused(id, task, owner, type, guid)
						return false
					task.build_spot = Vector2i(spot)
					return true
	if MissionStats.on:
		MissionStats.no_spot(id, task, owner, type, guid)
	return false


## The footprint part of BuildController.can_place_for (false where it fails), each cell's
## answer kept in `cells`.
static func _footprint_fits(nav: NavGrid, type: ObjectTypes.ObjectType, at: Vector2, wall: bool, cells: Dictionary) -> bool:
	var origin := nav.cell_of(MapObject.footprint_rect_for(type, at).position)
	for i in type.footprint_cells.size():
		var own := type.footprint_cells[i]
		if (own & NavGrid.BLOCKED) == 0:
			continue
		var cell := origin + Vector2i(i % type.footprint_grid.x, i / type.footprint_grid.x)
		var key := Vector3i(cell.x, cell.y, int(own & NavGrid.SOLID != 0))
		var fits = cells.get(key)
		if fits == null:
			fits = nav.can_build_on(cell, own, wall)
			cells[key] = fits
		if not fits:
			return false
	return true


## What can_place_for finds in a site's way after the footprint, by 128 px cell: other
## peoples' living units ([0]) and the fields, and for a field the buildings too ([1], in
## every cell they cover). Nothing moves while build_near looks for a spot.
static func _in_the_way(owner: int, field: bool) -> Array:
	var units := {}
	for unit in Unit.all_units:
		if unit.is_alive() and unit.team != owner:
			units.get_or_add(Vector2i((unit.position / WAY_CELL).floor()), []).append(unit.position)
	var objects := {}
	for object in MapObject.structures:
		if object.is_field() or (field and object.is_building()):
			var rect := object.footprint_rect()
			var low := Vector2i((rect.position / WAY_CELL).floor())
			var high := Vector2i((rect.end / WAY_CELL).floor())
			for y in range(low.y, high.y + 1):
				for x in range(low.x, high.x + 1):
					objects.get_or_add(Vector2i(x, y), []).append(rect)
	return [units, objects]


## Whether nothing of `way` (_in_the_way) stops a site on `rect` (else can_place_for says no).
static func _clear_of(way: Array, rect: Rect2) -> bool:
	var low := Vector2i((rect.position / WAY_CELL).floor())
	var high := Vector2i((rect.end / WAY_CELL).floor())
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			for point: Vector2 in way[0].get(Vector2i(x, y), []):
				if rect.has_point(point):
					return false
			for other: Rect2 in way[1].get(Vector2i(x, y), []):
				if other.intersects(rect):
					return false
	return true


## The height level (ground, plateau ...) at `at` (cell flag bits 12-13).
static func _level(nav: NavGrid, at: Vector2) -> int:
	return (nav.flags_at(nav.cell_of(at)) >> 12) & 3


static func _tree_near(at: Vector2) -> MapObject:
	return KiWorld.nearest_tree(at)


static func _nearest_wall(player: int, at: Vector2, radius: int) -> int:
	var best := KiWorld.nearest(MapObject.structures, at, func(o: MapObject) -> bool:
		return o.owner_index == player and WallLine.is_wall(o.guid) and o.is_alive() \
				and o.position.distance_to(at) <= radius)
	return KiWorld.handle(best)


static func _find_water(at: Vector2) -> Vector2:
	var nav := NavGrid.current
	var cell := nav.nearest_passable(nav.cell_of(at), 60, NavGrid.Layer.WATER)
	return nav.center_of(cell) if cell.x >= 0 else Vector2.INF


static func _reachable(from: Vector2, to: Vector2) -> Vector2:
	var nav := NavGrid.current
	if nav.find_path(from, to).is_empty():
		var cell := nav.nearest_walkable(nav.cell_of(to), 32)
		return nav.center_of(cell) if cell.x >= 0 else Vector2.INF
	return to
