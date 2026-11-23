extends Node

@export var sprite: Texture2D
@export var travel_speed := 510.0
@export var lifetime := 3.0
@export var sprite_size := 20.0

var hostile := false
var damage := 0.0
var breach_chance := 0.0
var crew_damage := 0.0
var position := Vector2.ZERO
var velocity := Vector2.ZERO
var remaining := 0.0


func launch(origin: Vector2, direction: Vector2) -> void:
	position = origin
	velocity = direction.normalized() * travel_speed
	remaining = lifetime


func advance(delta: float) -> void:
	position += velocity * minf(delta, remaining)
	remaining = maxf(0.0, remaining - delta)
