class_name Cheats
extends RefCounted
## Playtesting cheats, in campaign missions (or any single-player match with --cheats=1):
## lift the fog, more of every resource, kill what is selected, win at once, fire a mission
## trigger whatever its conditions say, and run the game faster. The keys (MissionDebug)
## only give orders (Orders.cheat); the cheats happen here, in a game step like every other
## change to the game, so a recorded match with cheats in it replays the same.

const KINDS := ["reveal", "resources", "kill", "win", "fire", "speed"]
const GIFT := 1000
const GIFTED := ["food", "wood", "gold", "guns"]
## Game speeds Ctrl+Shift+T cycles through, times the match's own.
const SPEEDS := [1.0, 4.0, 8.0]

## Whether cheat orders are carried out in this match (never in a network game).
static var enabled := false
static var speed_index := 0
static var _main: Main
static var _base_speed := 1.0


static func setup(game: Main, base_speed: float) -> void:
	_main = game
	_base_speed = base_speed
	speed_index = 0
	enabled = not Net.active and (game.mission != null or GameData.cmdline_option("cheats") != "" \
			or "--cheats" in OS.get_cmdline_user_args())


## The speed the next Ctrl+Shift+T gives.
static func next_speed() -> float:
	return SPEEDS[(speed_index + 1) % SPEEDS.size()]


## Carries out cheat `kind` for people `people` (Orders.execute, in a game step).
static func execute(people: int, kind: String, args: Array, ids: Array) -> void:
	if not enabled or not is_instance_valid(_main):
		return
	match kind:
		"reveal":
			_main.fog.enabled = not _main.fog.enabled
			_main.fog.update_now()
		"resources":
			var player: Player = Player.by_index.get(people)
			if player:
				for key in GIFTED:
					player.add(key, GIFT)
		"kill":
			for id in ids:
				var node := Sim.find(int(id))
				if node is Unit and node.is_alive():
					node.health = 0.0
					node.die()
				elif node is MapObject and node.is_building() and node.is_alive():
					node.health = 0.0
					node.condition.destroy()
		"win":
			if _main.mission:
				_main.mission.finish(people, true)
		"fire":
			if _main.mission and not args.is_empty():
				_main.mission.force(int(args[0]))
		"speed":
			speed_index = (speed_index + 1) % SPEEDS.size()
			Sim.set_speed(_base_speed * SPEEDS[speed_index])
