class_name DrawOverlay
extends Node2D
## Draws its parent's `_draw_overlay(canvas)` above every sprite (health bars, selection rings,
## progress), since a parent's own _draw would sit underneath its sprite children.

func _ready() -> void:
	z_index = 100
	z_as_relative = false


func _draw() -> void:
	get_parent()._draw_overlay(self)
