extends Node
## Autoload "Net": multiplayer over the network, in lockstep. Every machine runs the whole
## game (Sim) and only the players' orders (Orders) travel: after finishing step T a machine
## seals its orders for step T + DELAY and sends them as one batch, empty or not; nobody
## carries out a step before holding every human player's batch for it. The same orders on the same steps give the same game everywhere, and now and then
## a batch carries the sender's state checksum so a drift shows at once.
##
## One machine hosts (ENet, PORT by default); the others join it and all traffic passes
## through the host, which also holds the lobby: who plays which people, the map and the
## settings. The host starts the match for everyone.
##
## Command line (after `--`), for tests without the menu:
##   --host=port|default --humans=n   host, wait for n - 1 others, then start (--map, --players)
##   --join=address[:port]      join a host and play the next free people

signal lobby_changed  ## someone joined or left, or the host changed the slots
signal connection_failed(reason: String)
signal desynced(tick: int)
signal player_left(index: int)

const PORT := 47624
## Steps between giving an order and everyone carrying it out (133 ms at 30 steps a second).
const DELAY := 4
## Every this many steps a batch carries the sender's checksum.
const CHECK_EVERY := 30
const PROTOCOL := 1

## True from the start of a network match until it ends.
var active := false
var is_host := false
## The lobby, as the host keeps it: one entry per people in start-point order,
## {"faction", "kind": "human" or "ai", "peer": network id of whoever plays it (humans)}.
var slots: Array[Dictionary] = []
var map_path := ""
var settings := {}  ## game type, population limit, speed, supply, difficulty
var names := {}  ## peer id -> player name
var my_name := "Player"
var last_address := "127.0.0.1"  ## the host joined last time
const PREFS := "user://network.cfg"

var _humans := {}  # people index -> peer id, for the match being played
var _received := {}  # step -> {people index: true}, batches held
var _sealed := 0  # the last step whose orders this machine has sent
var _sums := {}  # step -> our checksum, kept a while to compare with others'
var _their_sums := {}  # step -> {people: checksum}, arrived before ours
var _left := {}  # people index -> last step of theirs to wait for
var _kept := {}  # on the host: people index -> {step: orders}, recent batches to pass on if they leave
var _auto_start := 0  # --humans=n: start once this many are here


func _ready() -> void:
	var prefs := ConfigFile.new()
	if prefs.load(PREFS) == OK:
		my_name = prefs.get_value("player", "name", my_name)
		last_address = prefs.get_value("player", "address", last_address)
	elif OS.has_environment("USER"):
		my_name = OS.get_environment("USER").capitalize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit("Could not reach the host"))
	multiplayer.server_disconnected.connect(_on_server_gone)
	var host_option := GameData.cmdline_option("host")
	if host_option != "":
		_auto_start = GameData.cmdline_option("humans", "2").to_int()
		host(host_option.to_int() if host_option.is_valid_int() else PORT)
	elif GameData.cmdline_option("join") != "":
		var parts := GameData.cmdline_option("join").split(":")
		join(parts[0], parts[1].to_int() if parts.size() > 1 else PORT)


# ------------------------------------------------------------------ the lobby

func save_prefs() -> void:
	var prefs := ConfigFile.new()
	prefs.set_value("player", "name", my_name)
	prefs.set_value("player", "address", last_address)
	prefs.save(PREFS)


## Who plays place `index` in the lobby, as the menu shows it.
func slot_caption(index: int) -> String:
	var slot: Dictionary = slots[index]
	if slot.kind == "ai":
		return "Computer"
	if int(slot.peer) == 0:
		return "Open"
	if int(slot.peer) == multiplayer.get_unique_id():
		return "You"
	return names.get(int(slot.peer), "Player")


func host(port := PORT) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 7)
	if error != OK:
		return "Could not open port %d (%s)" % [port, error_string(error)]
	multiplayer.multiplayer_peer = peer
	is_host = true
	names = {1: my_name}
	map_path = GameData.maps_dir().path_join("[2 Players] - close combat.ulf")
	_command_line_lobby()
	lobby_changed.emit()
	return ""


func join(address: String, port := PORT) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return "Could not connect to %s:%d (%s)" % [address, port, error_string(error)]
	multiplayer.multiplayer_peer = peer
	return ""


## Close the connection and forget the lobby (and any match being played).
func leave() -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	is_host = false
	slots.clear()
	names.clear()
	_humans.clear()


func is_connected_to_game() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## --map and --players=mex,usa,... set up the host's lobby from the command line.
func _command_line_lobby() -> void:
	var map_arg := GameData.cmdline_option("map")
	if map_arg != "":
		map_path = map_arg if map_arg.is_absolute_path() else GameData.maps_dir().path_join(map_arg)
	var factions := GameData.cmdline_option("players", "mex,usa").split(",")
	slots.clear()
	for i in factions.size():
		var human := i < _auto_start if _auto_start > 0 else true  # open places, played by the computer if nobody comes
		slots.append({"faction": factions[i], "kind": "human" if human else "ai", "peer": 1 if i == 0 else 0})


func _on_peer_connected(id: int) -> void:
	if not is_host:
		return
	_hello.rpc_id(id, PROTOCOL)


@rpc("authority", "reliable")
func _hello(protocol: int) -> void:
	if protocol != PROTOCOL:
		connection_failed.emit("The host runs another version of the game")
		leave()
		return
	_introduce.rpc_id(1, my_name)


## A new player on the host: give them the first free human place.
@rpc("any_peer", "reliable")
func _introduce(player_name: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	names[id] = player_name
	if active:
		return  # a match is on: no room
	for slot in slots:
		if slot.kind == "human" and slot.peer == 0:
			slot.peer = id
			break
	_share_lobby()
	if _auto_start > 0 and slots.filter(func(s: Dictionary) -> bool: return s.kind == "human" and s.peer != 0).size() >= _auto_start:
		start_match()


func _share_lobby() -> void:
	_lobby.rpc(slots, map_path.get_file(), settings, names)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _lobby(new_slots: Array, map_file: String, new_settings: Dictionary, new_names: Dictionary) -> void:
	slots.assign(new_slots)
	map_path = _local_map(map_file)
	settings = new_settings
	names = new_names
	lobby_changed.emit()


## The host changes a place: `kind` "human" (open for a player) or "ai", or a faction.
func set_slot(index: int, faction: String, kind: String) -> void:
	if not is_host or index >= slots.size():
		return
	slots[index].faction = faction
	if slots[index].kind != kind:
		slots[index].kind = kind
		slots[index].peer = 1 if kind == "human" and index == 0 else 0
	_share_lobby()


func set_map(path: String, player_count: int) -> void:
	if not is_host:
		return
	map_path = path
	while slots.size() < player_count:
		slots.append({"faction": Match.FACTIONS[slots.size() % Match.FACTIONS.size()], "kind": "human", "peer": 0})
	slots.resize(player_count)
	_share_lobby()


func set_settings(new_settings: Dictionary) -> void:
	if is_host:
		settings = new_settings
		_share_lobby()


## Maps travel by file name; each machine reads its own copy.
func _local_map(file: String) -> String:
	for candidate in GameData.map_files():
		if candidate.get_file() == file:
			return candidate
	return GameData.maps_dir().path_join(file)


func _on_connected() -> void:
	pass  # the host says hello first


func _on_peer_disconnected(id: int) -> void:
	names.erase(id)
	if active:
		for index in _humans:
			if _humans[index] == id:
				_drop(index)
		return
	if is_host:
		for slot in slots:
			if slot.peer == id:
				slot.peer = 0
		_share_lobby()


## Without the host nobody can pass orders on: the match ends here.
func _on_server_gone() -> void:
	connection_failed.emit("The host has left")


# ------------------------------------------------------------------ starting a match

## The host starts the match for everyone in the lobby (empty human places play as AI).
func start_match() -> void:
	if not is_host:
		return
	var seed_value := randi()
	_start.rpc(slots, map_path.get_file(), settings, seed_value)


@rpc("authority", "reliable", "call_local")
func _start(match_slots: Array, map_file: String, match_settings: Dictionary, seed_value: int) -> void:
	slots.assign(match_slots)
	var my_id := multiplayer.get_unique_id()
	var setup: Array[Dictionary] = []
	_humans.clear()
	var me := 0
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var human: bool = slot.kind == "human" and slot.peer != 0
		setup.append({"faction": slot.faction, "ai": not human})
		if human:
			_humans[i + 1] = int(slot.peer)
			if int(slot.peer) == my_id:
				me = i + 1
	Match.setup(_local_map(map_file), setup)
	Match.local_player = me
	Match.game_type = int(match_settings.get("game_type", Match.GameType.EVERYBODY)) as Match.GameType
	Match.population_limit = int(match_settings.get("population_limit", 100))
	Match.speed = float(match_settings.get("speed", 1.0))
	Match.supply = int(match_settings.get("supply", 0))
	Match.difficulty = int(match_settings.get("difficulty", 2))
	Match.seed_value = seed_value
	_received.clear()
	_sums.clear()
	_their_sums.clear()
	_left.clear()
	_kept.clear()
	_sealed = 0
	active = true
	Orders.delay = DELAY
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ------------------------------------------------------------------ lockstep

## Whether step `tick` may run: every human people's orders for it are here.
func can_step(tick: int) -> bool:
	if not active or tick <= DELAY:
		return true
	var held: Dictionary = _received.get(tick, {})
	for index in _humans:
		if not held.has(index) and not (_left.has(index) and tick > int(_left[index])):
			return false
	return true


## After step `tick`: send this machine's orders for step tick + DELAY.
func stepped(tick: int) -> void:
	if not active:
		return
	if tick % CHECK_EVERY == 0:
		_sums[tick] = Sim.checksum()
		_compare(tick)
		_sums.erase(tick - CHECK_EVERY * 20)
	var seal := tick + DELAY
	while _sealed < seal:
		_sealed += 1
		var orders := Orders.sealed(_sealed)
		var sum: String = _sums.get(tick, "") if _sealed == seal else ""
		_mark(_sealed, Match.local_player)
		_batch.rpc(_sealed, Match.local_player, orders, tick, sum)
	_received.erase(tick)


@rpc("any_peer", "reliable")
func _batch(tick: int, index: int, orders: Array, sum_tick: int, sum: String) -> void:
	if not active or _humans.get(index) != multiplayer.get_remote_sender_id():
		return  # only a people's own player gives its orders
	_take(tick, index, orders)
	if sum != "":
		var theirs: Dictionary = _their_sums.get(sum_tick, {})
		theirs[index] = sum
		_their_sums[sum_tick] = theirs
		_compare(sum_tick)


func _take(tick: int, index: int, orders: Array) -> void:
	if _received.get(tick, {}).has(index) or (_left.has(index) and tick > int(_left[index])):
		return
	for order: Dictionary in orders:
		if int(order.p) == index and int(order.t) == tick:
			Orders.queue(order)
	_mark(tick, index)
	if is_host:
		var kept: Dictionary = _kept.get(index, {})
		kept[tick] = orders
		kept.erase(tick - DELAY * 8)
		_kept[index] = kept


func _mark(tick: int, index: int) -> void:
	var held: Dictionary = _received.get(tick, {})
	held[index] = true
	_received[tick] = held


func _compare(tick: int) -> void:
	if not _sums.has(tick) or not _their_sums.has(tick):
		return
	for index in _their_sums[tick]:
		if _their_sums[tick][index] != _sums[tick]:
			push_error("Out of sync with player %d at step %d" % [index, tick])
			desynced.emit(tick)
	_their_sums.erase(tick)


## A player is gone: stop waiting for them after the last step whose orders arrived (the
## host relays everything, so it has them all; a machine short of some waits for them).
func _drop(index: int) -> void:
	var last := Sim.tick
	for tick in _received:
		if _received[tick].has(index):
			last = maxi(last, tick)
	_left[index] = last
	if is_host:
		_dropped.rpc(index, last, _kept.get(index, {}))
	player_left.emit(index)


@rpc("authority", "reliable")
func _dropped(index: int, last: int, batches: Dictionary) -> void:
	for tick in batches:
		if int(tick) <= last:
			_take(int(tick), index, batches[tick])
	_left[index] = last
	player_left.emit(index)


## The match is over or left: back to playing alone.
func end_match() -> void:
	active = false
	Orders.delay = 0
	leave()
