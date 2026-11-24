extends "res://flight/enemy_ship.gd"

const BREAK_OFF_DISTANCE := 160.0
const REENGAGE_DISTANCE := 390.0
const CRUISE_SPEED := 195.0
const MISSILE_STANDOFF := 292.0

var _disengaging := false
var _retreat_course := Vector2.ZERO


func _configure_deck() -> void:
	deck.layout_path = DeckSimulation.FIGHTER_LAYOUT


func _steer(delta: float, target_position: Vector2, target_velocity: Vector2) -> void:
	var offset := target_position - position
	var distance := offset.length()
	var forward := offset.normalized() if distance > 0.0 else Vector2.from_angle(heading)
	var reserve := 16.0 + (weapon.energy_cost if weapon != null else 0.0)
	var low_power := _conserve_if_low(reserve)
	var closing := maxf(0.0, (velocity - target_velocity).dot(forward))
	if low_power:
		var throttle := _recovery_throttle() if distance > 145.0 else maxf(0.32, _recovery_throttle())
		_fly_towards(delta, -forward * 54.0, throttle, (-forward).angle())
		return

	if weapon != null and weapon.kind == WeaponProfile.Kind.MISSILE:
		_missile_pass(delta, forward, distance, closing, target_velocity, reserve)
		return

	if not _disengaging and distance < BREAK_OFF_DISTANCE:
		_disengaging = true
		_retreat_course = -forward
	elif _disengaging and distance > REENGAGE_DISTANCE:
		_disengaging = false
	if _disengaging:
		_fly_towards(delta, _retreat_course * CRUISE_SPEED)
		return

	var intercept := offset + target_velocity * minf(distance / 510.0, 1.0)
	_fly_towards(delta, intercept.normalized() * CRUISE_SPEED)
	_request_shot(distance, intercept.angle(), reserve, 0.065)


func _missile_pass(delta: float, forward: Vector2, distance: float, closing: float,
		target_velocity: Vector2, reserve: float) -> void:
	# Match drift around gun range. The engagement velocity is independent from nose aim.
	var predicted_distance := distance - closing * 1.05
	if predicted_distance < 160.0:
		var retreat := (target_velocity - forward * 145.0).limit_length(CRUISE_SPEED)
		_fly_towards(delta, retreat, 1.0, (-forward).angle())
		return
	var approach := clampf((distance - MISSILE_STANDOFF) * 0.85, -105.0, 105.0)
	var aim := forward.angle()
	_fly_towards(delta, (target_velocity + forward * approach).limit_length(145.0), 0.72, aim)
	_request_shot(distance, aim, reserve, 0.20)


func _request_shot(distance: float, aim: float, reserve: float, tolerance: float) -> void:
	shot_requested = (weapon != null and weapons_cooldown <= 0.0 and deck.weapons_are_manned()
		and deck.power.energy >= reserve and distance < 420.0
		and absf(angle_difference(heading, aim)) < tolerance)
