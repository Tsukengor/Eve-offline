extends "res://flight/enemy_ship.gd"

const BREAK_OFF_DISTANCE := 160.0
const REENGAGE_DISTANCE := 390.0
const CRUISE_SPEED := 195.0

var _disengaging := false
var _retreat_course := Vector2.ZERO
var _maneuver_time := 0.0


func _configure_deck() -> void:
	deck.use_fighter_deck()


func _steer(delta: float, target_position: Vector2, target_velocity: Vector2) -> void:
	var offset := target_position - position
	var distance := offset.length()
	_maneuver_time = maxf(_maneuver_time - delta, 0.0)
	if not _disengaging and distance < BREAK_OFF_DISTANCE and _maneuver_time == 0.0:
		_disengaging = true
		_maneuver_time = 6.5
		_retreat_course = -offset.normalized()
		if _retreat_course == Vector2.ZERO:
			_retreat_course = -Vector2.from_angle(heading)
	elif _disengaging and (distance > REENGAGE_DISTANCE or _maneuver_time == 0.0):
		_disengaging = false
		_maneuver_time = 1.6

	if _disengaging:
		_fly_towards(delta, _retreat_course * CRUISE_SPEED)
		return

	var intercept := offset + target_velocity * minf(distance / 510.0, 1.0)
	_fly_towards(delta, intercept.normalized() * CRUISE_SPEED)
	shot_requested = weapons_cooldown <= 0.0 and deck.weapons_are_manned() and distance < 420.0 \
		and absf(angle_difference(heading, intercept.angle())) < 0.065
