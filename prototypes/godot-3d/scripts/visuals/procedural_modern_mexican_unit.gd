@tool
extends Node3D

const ROOT_NAME := "ModernMexicanUnitVisual"

@export_enum("infantryman", "cavalryman", "militiaman", "gunslinger", "priest", "cannon") var unit_variant := "infantryman"
@export var display_name := "Mexican Infantryman"
@export var animate_idle := true

var visual_root: Node3D
var left_arm: MeshInstance3D
var right_arm: MeshInstance3D
var left_leg: MeshInstance3D
var right_leg: MeshInstance3D
var prop: MeshInstance3D
var horse_root: Node3D
var time := 0.0

func _ready() -> void:
	_rebuild()

func _process(delta: float) -> void:
	if not animate_idle or visual_root == null:
		return

	time += delta
	var pace := 2.2
	if unit_variant == "cavalryman":
		pace = 1.7
	var bob := sin(time * pace) * 0.035
	visual_root.position.y = bob
	if left_arm != null:
		left_arm.rotation_degrees.z = 11.0 + sin(time * pace) * 4.0
	if right_arm != null:
		right_arm.rotation_degrees.z = -13.0 - sin(time * pace) * 4.0
	if left_leg != null:
		left_leg.rotation_degrees.z = -4.0 + sin(time * pace) * 2.0
	if right_leg != null:
		right_leg.rotation_degrees.z = 4.0 - sin(time * pace) * 2.0
	if prop != null:
		prop.rotation_degrees.z = -20.0 + sin(time * pace) * 2.5
	if horse_root != null:
		horse_root.position.y = sin(time * 1.7) * 0.025

func _rebuild() -> void:
	var old_root := get_node_or_null(ROOT_NAME)
	if old_root != null:
		old_root.queue_free()

	visual_root = Node3D.new()
	visual_root.name = ROOT_NAME
	add_child(visual_root)
	if Engine.is_editor_hint():
		visual_root.owner = get_tree().edited_scene_root

	match unit_variant:
		"cavalryman":
			_build_cavalryman()
		"militiaman":
			_build_foot_unit(Color(0.42, 0.30, 0.18), Color(0.23, 0.21, 0.17), Color(0.60, 0.42, 0.22), "musket")
		"gunslinger":
			_build_foot_unit(Color(0.12, 0.12, 0.13), Color(0.34, 0.22, 0.13), Color(0.10, 0.09, 0.08), "pistol")
		"priest":
			_build_foot_unit(Color(0.10, 0.10, 0.095), Color(0.08, 0.08, 0.075), Color(0.86, 0.78, 0.54), "cross")
		"cannon":
			_build_cannon()
		_:
			_build_foot_unit(Color(0.23, 0.34, 0.58), Color(0.48, 0.40, 0.29), Color(0.68, 0.56, 0.36), "rifle")
	_add_label()

func _build_foot_unit(shirt_color: Color, pants_color: Color, accent_color: Color, equipment: String) -> void:
	var skin := _mat(Color(0.70, 0.47, 0.30), 0.82)
	var shirt := _mat(shirt_color, 0.86)
	var pants := _mat(pants_color, 0.84)
	var leather := _mat(Color(0.20, 0.11, 0.05), 0.74)
	var accent := _mat(accent_color, 0.82)
	var hat_band := _mat(Color(accent_color.r * 0.45, accent_color.g * 0.42, accent_color.b * 0.40), 0.78)
	var eye_mat := _mat(Color(0.05, 0.04, 0.04), 0.4)

	_add_capsule("Torso", 0.31, 0.78, Vector3(0.0, 1.05, 0.0), shirt)
	_add_sphere("Head", 0.23, Vector3(0.0, 1.62, 0.0), skin)
	_add_sphere("EyeL", 0.028, Vector3(-0.085, 1.66, -0.205), eye_mat)
	_add_sphere("EyeR", 0.028, Vector3(0.085, 1.66, -0.205), eye_mat)
	_add_capsule("Neck", 0.085, 0.10, Vector3(0.0, 1.46, 0.0), skin)
	_add_box("Belt", Vector3(0.66, 0.10, 0.66), Vector3(0.0, 0.78, 0.0), leather)
	_add_box("BeltBuckle", Vector3(0.13, 0.10, 0.04), Vector3(0.0, 0.78, -0.32), _mat(Color(0.78, 0.62, 0.22), 0.4))

	if equipment == "cross":
		_add_cylinder("Collar", 0.19, 0.055, Vector3(0.0, 1.42, -0.22), _mat(Color(0.92, 0.88, 0.78), 0.8), Vector3(90.0, 0.0, 0.0))
		_add_cylinder("PriestHat", 0.22, 0.08, Vector3(0.0, 1.83, 0.0), _mat(Color(0.07, 0.065, 0.06), 0.88))
	else:
		_add_cylinder("HatBrim", 0.36, 0.045, Vector3(0.0, 1.80, 0.0), accent)
		_add_cylinder("HatCrownLower", 0.21, 0.05, Vector3(0.0, 1.83, 0.0), accent)
		_add_cylinder("HatBand", 0.215, 0.05, Vector3(0.0, 1.86, 0.0), hat_band)
		_add_cylinder("HatCrown", 0.18, 0.16, Vector3(0.0, 1.95, 0.0), accent)

	left_arm = _add_limb("LeftArm", Vector3(-0.34, 1.18, 0.0), 0.075, 0.55, shirt, Vector3(0.0, 0.0, 11.0))
	right_arm = _add_limb("RightArm", Vector3(0.34, 1.18, 0.0), 0.075, 0.55, shirt, Vector3(0.0, 0.0, -13.0))
	_add_sphere("LeftHand", 0.085, Vector3(-0.39, 0.88, 0.0), skin)
	_add_sphere("RightHand", 0.085, Vector3(0.39, 0.88, 0.0), skin)
	left_leg = _add_limb("LeftLeg", Vector3(-0.15, 0.48, 0.0), 0.085, 0.62, pants, Vector3(0.0, 0.0, -4.0))
	right_leg = _add_limb("RightLeg", Vector3(0.15, 0.48, 0.0), 0.085, 0.62, pants, Vector3(0.0, 0.0, 4.0))
	_add_box("LeftBoot", Vector3(0.22, 0.12, 0.36), Vector3(-0.17, 0.10, -0.04), leather)
	_add_box("RightBoot", Vector3(0.22, 0.12, 0.36), Vector3(0.17, 0.10, -0.04), leather)
	_add_box("LeftBootHeel", Vector3(0.18, 0.08, 0.10), Vector3(-0.17, 0.05, 0.10), _mat(Color(0.12, 0.07, 0.03), 0.7))
	_add_box("RightBootHeel", Vector3(0.18, 0.08, 0.10), Vector3(0.17, 0.05, 0.10), _mat(Color(0.12, 0.07, 0.03), 0.7))

	match equipment:
		"rifle", "musket":
			prop = _add_cylinder("LongGun", 0.035, 1.22, Vector3(0.48, 1.08, -0.16), _mat(Color(0.11, 0.10, 0.09), 0.55), Vector3(0.0, 0.0, -20.0))
			_add_box("GunStock", Vector3(0.16, 0.22, 0.08), Vector3(0.31, 0.66, -0.16), leather, Vector3(0.0, 0.0, -20.0))
			if equipment == "musket":
				_add_box("Bedroll", Vector3(0.48, 0.22, 0.20), Vector3(-0.40, 1.0, 0.18), accent)
		"pistol":
			prop = _add_box("Pistol", Vector3(0.28, 0.12, 0.08), Vector3(0.45, 1.18, -0.19), _mat(Color(0.10, 0.10, 0.09), 0.52), Vector3(0.0, 0.0, -18.0))
			_add_box("Holster", Vector3(0.16, 0.32, 0.08), Vector3(-0.30, 0.84, -0.24), leather, Vector3(0.0, 0.0, -12.0))
			_add_box("Vest", Vector3(0.42, 0.50, 0.08), Vector3(0.0, 1.12, -0.25), _mat(Color(0.08, 0.075, 0.07), 0.82))
		"cross":
			prop = _add_box("Staff", Vector3(0.055, 1.10, 0.055), Vector3(0.48, 0.95, -0.12), _mat(Color(0.36, 0.22, 0.10), 0.75), Vector3(0.0, 0.0, -8.0))
			_add_box("HandCrossVertical", Vector3(0.07, 0.34, 0.045), Vector3(0.59, 1.55, -0.12), _mat(Color(0.86, 0.78, 0.54), 0.62))
			_add_box("HandCrossHorizontal", Vector3(0.28, 0.06, 0.045), Vector3(0.59, 1.61, -0.12), _mat(Color(0.86, 0.78, 0.54), 0.62))

func _build_cavalryman() -> void:
	horse_root = Node3D.new()
	horse_root.name = "Horse"
	visual_root.add_child(horse_root)
	var horse_mat := _mat(Color(0.34, 0.20, 0.10), 0.82)
	var horse_dark := _mat(Color(0.18, 0.10, 0.05), 0.78)
	var hoof_mat := _mat(Color(0.08, 0.06, 0.04), 0.62)
	var mane_mat := _mat(Color(0.08, 0.05, 0.03), 0.92)
	var tack := _mat(Color(0.10, 0.06, 0.04), 0.74)
	var brass := _mat(Color(0.78, 0.58, 0.18), 0.4)
	var blanket_mat := _mat(Color(0.62, 0.18, 0.14), 0.85)
	var eye_dark := _mat(Color(0.04, 0.03, 0.02), 0.3)

	# Body: barrel-shaped torso made from a capsule plus chest/rump spheres so it tapers like a real horse.
	_add_child_capsule(horse_root, "HorseBody", 0.34, 1.20, Vector3(0.0, 0.94, 0.10), horse_mat, Vector3(0.0, 0.0, 90.0))
	_add_child_sphere(horse_root, "HorseChest", 0.36, Vector3(0.0, 0.94, -0.58), horse_mat)
	_add_child_sphere(horse_root, "HorseRump", 0.38, Vector3(0.0, 0.98, 0.72), horse_mat)
	_add_child_box(horse_root, "HorseBelly", Vector3(0.58, 0.32, 1.30), Vector3(0.0, 0.78, 0.06), horse_mat)

	# Neck: two tapered segments rising forward and up from the chest.
	_add_child_capsule(horse_root, "HorseLowerNeck", 0.17, 0.40, Vector3(0.0, 1.18, -0.78), horse_mat, Vector3(45.0, 0.0, 0.0))
	_add_child_capsule(horse_root, "HorseUpperNeck", 0.13, 0.36, Vector3(0.0, 1.46, -0.99), horse_mat, Vector3(28.0, 0.0, 0.0))

	# Head: elongated capsule oriented along the snout direction, plus a darker muzzle.
	_add_child_capsule(horse_root, "HorseHead", 0.13, 0.30, Vector3(0.0, 1.58, -1.22), horse_mat, Vector3(75.0, 0.0, 0.0))
	_add_child_box(horse_root, "HorseMuzzle", Vector3(0.18, 0.14, 0.22), Vector3(0.0, 1.48, -1.36), horse_dark)
	_add_child_box(horse_root, "HorseJaw", Vector3(0.18, 0.10, 0.20), Vector3(0.0, 1.40, -1.32), horse_dark)

	# Ears (pointed boxes pitched forward).
	_add_child_box(horse_root, "HorseEarL", Vector3(0.05, 0.16, 0.05), Vector3(-0.10, 1.72, -1.06), horse_mat, Vector3(-12.0, 0.0, -14.0))
	_add_child_box(horse_root, "HorseEarR", Vector3(0.05, 0.16, 0.05), Vector3(0.10, 1.72, -1.06), horse_mat, Vector3(-12.0, 0.0, 14.0))

	# Eyes.
	_add_child_sphere(horse_root, "HorseEyeL", 0.026, Vector3(-0.12, 1.60, -1.22), eye_dark)
	_add_child_sphere(horse_root, "HorseEyeR", 0.026, Vector3(0.12, 1.60, -1.22), eye_dark)

	# Mane: row of tufts following the neckline from poll down to withers.
	var mane_steps := 6
	for i in range(mane_steps):
		var t := float(i) / float(mane_steps - 1)
		var my := lerpf(1.66, 1.30, t)
		var mz := lerpf(-1.02, -0.50, t)
		var pitch := lerpf(35.0, 18.0, t)
		_add_child_box(horse_root, "ManeTuft%d" % i, Vector3(0.07, 0.18, 0.10), Vector3(0.0, my, mz), mane_mat, Vector3(pitch, 0.0, 0.0))
	_add_child_box(horse_root, "Forelock", Vector3(0.10, 0.10, 0.08), Vector3(0.0, 1.72, -1.10), mane_mat)

	# Tail: a tapered swatch hanging back and down from the rump.
	_add_child_capsule(horse_root, "TailBase", 0.07, 0.18, Vector3(0.0, 1.00, 0.96), mane_mat, Vector3(-12.0, 0.0, 0.0))
	_add_child_capsule(horse_root, "TailMid", 0.06, 0.45, Vector3(0.0, 0.78, 1.10), mane_mat, Vector3(-32.0, 0.0, 0.0))
	_add_child_capsule(horse_root, "TailTip", 0.05, 0.30, Vector3(0.0, 0.50, 1.20), mane_mat, Vector3(-46.0, 0.0, 0.0))

	# Saddle pad, saddle body, horn and cantle.
	_add_child_box(horse_root, "SaddleBlanket", Vector3(0.80, 0.05, 0.90), Vector3(0.0, 1.18, 0.0), blanket_mat)
	_add_child_box(horse_root, "Saddle", Vector3(0.58, 0.16, 0.58), Vector3(0.0, 1.28, -0.04), tack)
	_add_child_box(horse_root, "SaddleHorn", Vector3(0.10, 0.13, 0.10), Vector3(0.0, 1.41, -0.26), tack)
	_add_child_box(horse_root, "SaddleCantle", Vector3(0.48, 0.10, 0.08), Vector3(0.0, 1.40, 0.22), tack)

	# Legs: each leg has an upper limb, knee/cannon segment, and hoof for a recognisable horse stance.
	for spec in [
		[-0.20, -0.55, "FrontLeftLeg"],
		[0.20, -0.55, "FrontRightLeg"],
		[-0.20, 0.55, "RearLeftLeg"],
		[0.20, 0.55, "RearRightLeg"]
	]:
		var lx: float = spec[0]
		var lz: float = spec[1]
		var label: String = spec[2]
		_add_child_capsule(horse_root, label + "Upper", 0.085, 0.48, Vector3(lx, 0.60, lz), horse_mat)
		_add_child_sphere(horse_root, label + "Knee", 0.085, Vector3(lx, 0.30, lz), horse_dark)
		_add_child_capsule(horse_root, label + "Cannon", 0.055, 0.30, Vector3(lx, 0.14, lz), horse_dark)
		_add_child_box(horse_root, label + "Hoof", Vector3(0.16, 0.10, 0.18), Vector3(lx, -0.02, lz), hoof_mat)

	# Stirrups suspended off the saddle.
	for sign_x in [-1.0, 1.0]:
		_add_child_box(horse_root, "StirrupStrap", Vector3(0.03, 0.45, 0.04), Vector3(sign_x * 0.32, 1.04, -0.05), tack)
		_add_child_box(horse_root, "Stirrup", Vector3(0.06, 0.10, 0.14), Vector3(sign_x * 0.32, 0.78, -0.05), brass)

	var skin := _mat(Color(0.70, 0.47, 0.30), 0.82)
	var uniform := _mat(Color(0.18, 0.28, 0.50), 0.84)
	var uniform_trim := _mat(Color(0.78, 0.60, 0.20), 0.55)
	var pants := _mat(Color(0.54, 0.44, 0.28), 0.84)
	var hat := _mat(Color(0.74, 0.58, 0.30), 0.86)
	var hat_band := _mat(Color(0.34, 0.26, 0.13), 0.78)
	var eye_mat := _mat(Color(0.05, 0.04, 0.04), 0.4)
	_add_capsule("Torso", 0.28, 0.64, Vector3(0.0, 1.72, -0.05), uniform)
	_add_box("Sash", Vector3(0.62, 0.08, 0.62), Vector3(0.0, 1.50, -0.05), uniform_trim)
	_add_box("Epaulettes", Vector3(0.66, 0.06, 0.20), Vector3(0.0, 2.00, -0.05), uniform_trim)
	_add_capsule("Neck", 0.09, 0.10, Vector3(0.0, 2.05, -0.05), skin)
	_add_sphere("Head", 0.21, Vector3(0.0, 2.20, -0.05), skin)
	_add_sphere("EyeL", 0.025, Vector3(-0.08, 2.24, -0.24), eye_mat)
	_add_sphere("EyeR", 0.025, Vector3(0.08, 2.24, -0.24), eye_mat)
	_add_cylinder("HatBrim", 0.33, 0.045, Vector3(0.0, 2.38, -0.05), hat)
	_add_cylinder("HatBand", 0.20, 0.05, Vector3(0.0, 2.43, -0.05), hat_band)
	_add_cylinder("HatCrown", 0.18, 0.16, Vector3(0.0, 2.51, -0.05), hat)
	left_arm = _add_limb("LeftArm", Vector3(-0.30, 1.77, -0.04), 0.07, 0.50, uniform, Vector3(0.0, 0.0, 15.0))
	right_arm = _add_limb("RightArm", Vector3(0.30, 1.77, -0.04), 0.07, 0.50, uniform, Vector3(0.0, 0.0, -16.0))
	_add_sphere("LeftHand", 0.078, Vector3(-0.40, 1.53, -0.04), skin)
	_add_sphere("RightHand", 0.078, Vector3(0.40, 1.53, -0.04), skin)
	left_leg = _add_limb("LeftLeg", Vector3(-0.20, 1.25, -0.08), 0.075, 0.58, pants, Vector3(20.0, 0.0, 8.0))
	right_leg = _add_limb("RightLeg", Vector3(0.20, 1.25, -0.08), 0.075, 0.58, pants, Vector3(20.0, 0.0, -8.0))
	_add_box("LeftRidingBoot", Vector3(0.20, 0.48, 0.26), Vector3(-0.32, 0.92, -0.10), _mat(Color(0.10, 0.06, 0.03), 0.6))
	_add_box("RightRidingBoot", Vector3(0.20, 0.48, 0.26), Vector3(0.32, 0.92, -0.10), _mat(Color(0.10, 0.06, 0.03), 0.6))
	prop = _add_cylinder("Saber", 0.025, 1.05, Vector3(0.52, 1.78, -0.18), _mat(Color(0.78, 0.80, 0.78), 0.25), Vector3(0.0, 0.0, -20.0))
	_add_box("SaberHilt", Vector3(0.06, 0.16, 0.06), Vector3(0.46, 1.38, -0.10), brass, Vector3(0.0, 0.0, -20.0))

func _build_cannon() -> void:
	var wood := _mat(Color(0.22, 0.13, 0.06), 0.76)
	var dark_wood := _mat(Color(0.12, 0.075, 0.035), 0.78)
	var iron := _mat(Color(0.10, 0.10, 0.095), 0.38)
	var dark_iron := _mat(Color(0.06, 0.06, 0.06), 0.5)
	var brass := _mat(Color(0.78, 0.56, 0.20), 0.32)
	var rope := _mat(Color(0.55, 0.42, 0.22), 0.92)

	# Compact carriage body
	var axle_y := 0.70
	var carriage_y := 0.96
	var barrel_y := 1.32
	_add_box("Carriage", Vector3(0.95, 0.30, 1.10), Vector3(0.0, carriage_y, 0.0), wood)
	_add_box("CarriageSideL", Vector3(0.10, 0.46, 1.20), Vector3(-0.48, carriage_y + 0.20, 0.0), dark_wood)
	_add_box("CarriageSideR", Vector3(0.10, 0.46, 1.20), Vector3(0.48, carriage_y + 0.20, 0.0), dark_wood)
	_add_box("CarriageFrontPlate", Vector3(0.95, 0.32, 0.08), Vector3(0.0, carriage_y + 0.04, -0.59), dark_wood)
	_add_box("Trail", Vector3(0.32, 0.22, 0.95), Vector3(0.0, axle_y + 0.16, 0.95), dark_wood)
	_add_box("TrailEnd", Vector3(0.42, 0.28, 0.22), Vector3(0.0, axle_y + 0.12, 1.50), dark_wood)
	# Barrel
	_add_cylinder("Barrel", 0.22, 1.95, Vector3(0.0, barrel_y, -0.46), iron, Vector3(90.0, 0.0, 0.0))
	_add_cylinder("BarrelReinforce", 0.26, 0.22, Vector3(0.0, barrel_y, -0.06), iron, Vector3(90.0, 0.0, 0.0))
	_add_cylinder("Breech", 0.29, 0.30, Vector3(0.0, barrel_y, 0.34), dark_iron, Vector3(90.0, 0.0, 0.0))
	_add_sphere("Cascabel", 0.10, Vector3(0.0, barrel_y, 0.52), dark_iron)
	_add_cylinder("MuzzleBand", 0.27, 0.20, Vector3(0.0, barrel_y, -1.32), brass, Vector3(90.0, 0.0, 0.0))
	_add_cylinder("MidBand", 0.24, 0.10, Vector3(0.0, barrel_y, -0.70), brass, Vector3(90.0, 0.0, 0.0))
	for sign_x in [-1.0, 1.0]:
		_add_cylinder("Trunnion", 0.07, 0.20, Vector3(sign_x * 0.50, barrel_y, -0.10), iron, Vector3(0.0, 0.0, 90.0))
	# Big wheels
	var wheel_x := 0.72
	var wheel_radius := 0.70
	_add_cylinder("Axle", 0.08, 1.55, Vector3(0.0, axle_y, 0.0), dark_iron, Vector3(0.0, 0.0, 90.0))
	for x in [-wheel_x, wheel_x]:
		_add_cylinder("WheelRim", wheel_radius, 0.12, Vector3(x, axle_y, 0.0), dark_wood, Vector3(0.0, 0.0, 90.0))
		_add_cylinder("WheelTire", wheel_radius + 0.02, 0.07, Vector3(x, axle_y, 0.0), iron, Vector3(0.0, 0.0, 90.0))
		_add_cylinder("Hub", 0.14, 0.24, Vector3(x, axle_y, 0.0), brass, Vector3(0.0, 0.0, 90.0))
		for i in range(4):
			var ang := i * 45.0
			_add_box("Spoke", Vector3(0.05, 0.05, (wheel_radius - 0.10) * 2.0), Vector3(x, axle_y, 0.0), wood, Vector3(ang, 0.0, 0.0))
	# Ammo at the rear of the trail
	for x in [-0.30, 0.30]:
		_add_box("AmmoCrate", Vector3(0.40, 0.30, 0.34), Vector3(x, axle_y + 0.04, 1.30), wood)
		_add_box("CrateStrap", Vector3(0.42, 0.05, 0.06), Vector3(x, axle_y + 0.18, 1.30), rope)
		for cz in [-0.10, 0.10]:
			_add_sphere("CannonBall", 0.07, Vector3(x - 0.08, axle_y + 0.22, 1.30 + cz), dark_iron)
			_add_sphere("CannonBall", 0.07, Vector3(x + 0.08, axle_y + 0.22, 1.30 + cz), dark_iron)
	# Ramrod hanging on the cheek
	_add_cylinder("Ramrod", 0.025, 1.85, Vector3(0.62, carriage_y + 0.10, 0.0), dark_wood, Vector3(90.0, 0.0, 0.0))
	_add_sphere("RamrodHead", 0.05, Vector3(0.62, carriage_y + 0.10, -0.90), iron)

func _add_label() -> void:
	var label := Label3D.new()
	label.name = "AssetLabel"
	label.text = display_name
	var label_height := 2.35
	if unit_variant == "cavalryman":
		label_height = 2.72
	elif unit_variant == "cannon":
		label_height = 1.75
	label.position = Vector3(0.0, label_height, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 20
	label.modulate = Color(0.95, 0.86, 0.58)
	visual_root.add_child(label)

func _add_limb(part_name: String, position: Vector3, radius: float, height: float, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var limb := _add_capsule(part_name, radius, height, position, material)
	limb.rotation_degrees = rotation
	return limb

func _add_capsule(part_name: String, radius: float, height: float, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	return _add_child_capsule(visual_root, part_name, radius, height, position, material, rotation)

func _add_sphere(part_name: String, radius: float, position: Vector3, material: Material) -> MeshInstance3D:
	return _add_child_sphere(visual_root, part_name, radius, position, material)

func _add_cylinder(part_name: String, radius: float, height: float, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = material
	visual_root.add_child(mesh_instance)
	return mesh_instance

func _add_box(part_name: String, size: Vector3, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	return _add_child_box(visual_root, part_name, size, position, material, rotation)

func _add_child_capsule(parent: Node3D, part_name: String, radius: float, height: float, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 6
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

func _add_child_sphere(parent: Node3D, part_name: String, radius: float, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 18
	mesh.rings = 9
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

func _add_child_box(parent: Node3D, part_name: String, size: Vector3, position: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
