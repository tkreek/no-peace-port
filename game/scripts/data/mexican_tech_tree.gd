@tool
extends RefCounted
class_name MexicanTechTree

const SPENDABLE_RESOURCES := ["food", "wood", "gold"]

const MANUAL_BUILDING_ENERGY_BY_NAME := {
	"Command Post": 4000,
	"Weapons Factory": 2800
}

const UNITS := {
	"infantryman": {
		"name": "Mexican Infantryman",
		"role": "infantry",
		"cost": {"food": 50, "gold": 75, "rifles": 1, "housing": 1},
		"production": "Barracks",
		"health": 70,
		"speed": 5.6,
		"range": 16.0,
		"damage": 11,
		"cooldown": 1.5,
		"time": 6.0
	},
	"cavalryman": {
		"name": "Mexican Cavalryman",
		"role": "cavalry",
		"cost": {"food": 50, "gold": 85, "housing": 1},
		"mounted_cost_delta": {"horses": 1},
		"production": "Barracks",
		"health": 60,
		"speed": 7.6,
		"range": 3.1,
		"damage": 12,
		"damage_on_foot": 15,
		"cooldown": 1.25,
		"time": 7.0
	},
	"militiaman": {
		"name": "Mexican Militiaman",
		"role": "militia",
		"cost": {"food": 50, "gold": 50, "rifles": 1, "housing": 1},
		"production": "Hacienda",
		"health": 40,
		"speed": 5.4,
		"range": 13.5,
		"damage": 10,
		"cooldown": 1.8,
		"time": 5.0
	},
	"gunslinger": {
		"name": "Mexican Gunslinger",
		"role": "gunslinger",
		"cost": {"food": 75, "gold": 90, "housing": 1},
		"production": "Cantina",
		"health": 100,
		"speed": 6.2,
		"range": 12.0,
		"damage": 12,
		"cooldown": 0.95,
		"time": 6.0
	},
	"priest": {
		"name": "Mexican Priest",
		"role": "support",
		"cost": {"food": 50, "gold": 80, "housing": 1},
		"production": "Church",
		"health": 40,
		"speed": 5.1,
		"range": 0.0,
		"damage": 0,
		"cooldown": 2.0,
		"time": 5.0
	},
	"cannon": {
		"name": "Mexican Cannon",
		"role": "cannon",
		"cost": {"wood": 100, "gold": 150, "housing": 1},
		"production": "Weapons Factory",
		"health": 100,
		"speed": 3.4,
		"range": 20.0,
		"damage": 40,
		"cooldown": 2.2,
		"time": 8.0
	}
}

const BUILDINGS := {
	"house": {"name": "House", "cost": {"wood": 150}, "requires": [], "energy": 900, "size": Vector3(2.8, 1.7, 2.5), "color": Color(0.48, 0.31, 0.17), "time": 4.0},
	"hacienda": {"name": "Hacienda", "cost": {"wood": 300}, "requires": ["command_post"], "energy": 1250, "size": Vector3(4.8, 2.2, 3.8), "color": Color(0.68, 0.50, 0.30), "time": 6.0},
	"cantina": {"name": "Cantina", "cost": {"wood": 300, "gold": 200}, "requires": ["hacienda", "finca"], "energy": 1200, "size": Vector3(4.2, 2.0, 3.2), "color": Color(0.40, 0.20, 0.13), "time": 6.5},
	"butcher": {"name": "Butcher", "cost": {"wood": 350}, "requires": ["hacienda"], "energy": 1200, "size": Vector3(3.8, 1.9, 3.0), "color": Color(0.48, 0.16, 0.12), "time": 5.5},
	"barracks": {"name": "Barracks", "cost": {"wood": 250, "gold": 250}, "requires": ["fort"], "energy": 1800, "size": Vector3(5.0, 2.2, 3.6), "color": Color(0.38, 0.34, 0.26), "time": 7.0},
	"gold_warehouse": {"name": "Gold Warehouse", "cost": {"wood": 150}, "requires": ["command_post"], "energy": 350, "size": Vector3(2.8, 1.4, 2.4), "color": Color(0.52, 0.43, 0.22), "time": 4.0},
	"finca": {"name": "Finca", "cost": {"wood": 250}, "requires": ["command_post"], "energy": 850, "size": Vector3(4.4, 1.9, 3.4), "color": Color(0.63, 0.46, 0.25), "time": 5.0},
	"field": {"name": "Field", "cost": {"wood": 150}, "requires": ["finca"], "energy": 200, "size": Vector3(3.8, 0.3, 3.2), "color": Color(0.22, 0.48, 0.18), "time": 3.0},
	"sawmill": {"name": "Sawmill", "cost": {"wood": 300}, "requires": ["command_post"], "energy": 500, "size": Vector3(5.2, 1.9, 3.8), "color": Color(0.45, 0.29, 0.14), "time": 5.5},
	"trading_post": {"name": "Trading Post", "cost": {"wood": 300}, "requires": ["butcher"], "energy": 500, "size": Vector3(4.2, 2.0, 3.2), "color": Color(0.40, 0.30, 0.16), "time": 5.5},
	"weapons_factory": {"name": "Weapons Factory", "cost": {"wood": 500, "gold": 300}, "requires": ["fort"], "energy": 2800, "size": Vector3(5.0, 2.4, 3.8), "color": Color(0.42, 0.29, 0.18), "time": 8.0},
	"wall": {"name": "Wall", "cost": {"wood": 25}, "requires": ["sawmill"], "energy": 800, "size": Vector3(3.8, 1.2, 0.8), "color": Color(0.36, 0.24, 0.13), "time": 2.0},
	"tower": {"name": "Tower", "cost": {"wood": 200}, "requires": ["sawmill"], "energy": 600, "size": Vector3(2.3, 3.4, 2.3), "color": Color(0.34, 0.24, 0.16), "time": 5.5},
	"wharf": {"name": "Wharf", "cost": {"wood": 250}, "requires": ["sawmill"], "energy": 800, "size": Vector3(5.6, 0.8, 3.0), "color": Color(0.30, 0.19, 0.09), "time": 4.5},
	"church": {"name": "Church", "cost": {"wood": 350, "gold": 200}, "requires": ["trading_post"], "energy": 2400, "size": Vector3(4.0, 3.0, 3.2), "color": Color(0.62, 0.58, 0.48), "time": 7.0},
	"mission": {"name": "Mission", "cost": {"wood": 400}, "requires": ["trading_post"], "energy": 2600, "size": Vector3(5.2, 2.8, 4.0), "color": Color(0.52, 0.45, 0.34), "time": 8.0},
	"fort": {"name": "Fort", "cost": {"wood": 800, "gold": 500}, "requires": ["cantina", "sawmill"], "energy": 3000, "size": Vector3(6.2, 3.2, 5.4), "color": Color(0.31, 0.26, 0.19), "time": 10.0}
}

const PRODUCTION := {
	"command_post": ["farmhand"],
	"hacienda": ["militiaman"],
	"cantina": ["gunslinger"],
	"barracks": ["infantryman", "cavalryman"],
	"church": ["priest"],
	"weapons_factory": ["cannon"]
}
