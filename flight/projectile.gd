extends Node

const Profile = preload("res://flight/weapon_profile.gd")
const Physics = preload("res://flight/ship_physics.gd")
const Deck = preload("res://deck/deck_simulation.gd")

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
var profile: Profile
var shooter: Physics.Body
var mount := Vector2.ZERO
var aim_offset := 0.0
var target_body: Physics.Body
var target_deck: Deck
var angle := 0.0
var reach := 0.0
var end := Vector2.ZERO
var blast_time := 0.0
var affected: Dictionary[Physics.Body, bool] = {}
var contact_body: Physics.Body
var contact_tile := Deck.INVALID_CELL


func launch(origin: Vector2, direction: Vector2) -> void:
	position = origin
	velocity = direction.normalized() * travel_speed
	remaining = lifetime


func advance(delta: float) -> void:
	position += velocity * minf(delta, remaining)
	remaining = maxf(0.0, remaining - delta)
