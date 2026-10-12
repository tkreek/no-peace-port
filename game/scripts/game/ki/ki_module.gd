class_name KiModule
extends RefCounted
## One of the original's compiled AI scripts ("KI modules", campaign/<set>/ai/%08d.mod):
## "KIMODULE", u32 size, then sections {char[8] name, u32 length}: HEADER, VARIABLE (slot
## declarations), CONSTDAT (initial values, literals included), CODEDATA (one instruction
## per word: opcode in the top 4 bits), VARMAP (names, unused here) and DEBUGGER (the
## source file's name, for the mission overlay; its line table is unused).
## docs/technical/ki.md describes the machine that runs them (KiTask, KiPlayer).

const FOLDERS := ["campaign/base/ai", "campaign/expansion/ai"]

static var _cache := {}  # module number -> KiModule (or null when there is none)

var number := 0
var code := PackedInt32Array()
## VARIABLE: [descriptor (class<<24 | type<<16), slot count] per block.
var blocks: Array[PackedInt32Array] = []
## CONSTDAT: variable id -> initial value.
var initial := {}
## DEBUGGER: the script it was compiled from, without ".aml" (e.g. "ind01_angriff").
var source := ""


## Module `number` (the base game's and the expansion's numbers never overlap), or null.
static func load(module_number: int) -> KiModule:
	if _cache.has(module_number):
		return _cache[module_number]
	var module: KiModule = null
	for folder in FOLDERS:
		var asset := "%s/%08d.mod" % [folder, module_number]
		if GameData.exists(asset):
			module = from_bytes(GameData.read(asset), module_number)
			break
	_cache[module_number] = module
	return module


static func from_bytes(bytes: PackedByteArray, module_number: int) -> KiModule:
	if bytes.size() < 12 or bytes.slice(0, 8).get_string_from_ascii() != "KIMODULE":
		push_warning("Not an AI module: %08d" % module_number)
		return null
	var module := KiModule.new()
	module.number = module_number
	var at := 12
	while at + 12 <= bytes.size():
		var name := bytes.slice(at, at + 8).get_string_from_ascii().strip_edges()
		var length := bytes.decode_u32(at + 8)
		var body := bytes.slice(at + 12, at + 12 + length)
		at += 12 + length
		match name:
			"VARIABLE":
				for i in body.decode_u32(0):
					module.blocks.append(PackedInt32Array([body.decode_u32(4 + i * 8), body.decode_u32(8 + i * 8)]))
			"CONSTDAT":
				for i in body.decode_u32(0):
					module.initial[body.decode_u32(4 + i * 8)] = body.decode_s32(8 + i * 8)
			"CODEDATA":
				module.code = body.to_int32_array()
			"DEBUGGER":
				var end := body.find(0)
				module.source = body.slice(0, end if end >= 0 and end < 256 else 256).get_string_from_ascii().get_basename()
	return module
