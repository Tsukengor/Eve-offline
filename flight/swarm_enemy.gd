extends "res://flight/enemy_ship.gd"

const Drone = preload("res://flight/drone.gd")

const STANDOFF := 420.0
const DRONE_LIMIT := 6
const LAUNCH_INTERVAL := 3.0

var launch_timer := 2.0
var orbit_phase := 0.0


func _configure_deck() -> void:
	deck.layout_path = "res://deck/layouts/swarm.json"


func _steer(delta: float, target_position: Vector2, target_velocity: Vector2) -> void:
	var offset := target_position - position
	var bearing := offset.normalized()
	var throttle := _recovery_throttle() if _conserve_if_low(14.0) else 0.56
	var radial := clampf((offset.length() - STANDOFF) * 1.25, -105.0, 55.0)
	var goal := (target_velocity + bearing * radial + bearing.orthogonal() * 24.0).limit_length(105.0)
	_fly_towards(delta, goal, throttle)
	launch_timer = move_toward(launch_timer, 0.0, delta)
	orbit_phase = wrapf(orbit_phase + Drone.ORBIT_SPIN * delta, -PI, PI)
