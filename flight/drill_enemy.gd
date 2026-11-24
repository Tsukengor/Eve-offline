extends "res://flight/enemy_ship.gd"

const CRUISE_SPEED := 155.0
const RETREAT_DISTANCE := 215.0

var _retreating := false
var _retreat_origin := Vector2.ZERO
var _retreat_direction := Vector2.ZERO
var _retreat_age := 0.0


func _configure_deck() -> void:
	deck.layout_path = DeckSimulation.DRILL_LAYOUT


func _steer(delta: float, target_position: Vector2, target_velocity: Vector2) -> void:
	if _conserve_if_low(16.0):
		var away := target_position.direction_to(position)
		_fly_towards(delta, away * 52.0, _recovery_throttle(), away.angle())
		return
	if _retreating:
		_retreat_age += delta
		var progress := (position - _retreat_origin).dot(_retreat_direction)
		if progress >= RETREAT_DISTANCE or _retreat_age >= 9.0:
			_retreating = false
		else:
			var speed := clampf(RETREAT_DISTANCE - progress, 52.0, CRUISE_SPEED)
			_fly_towards(delta, _retreat_direction * speed)
			return

	var offset := target_position - position
	var lead_time := clampf(offset.length() / CRUISE_SPEED, 0.0, 1.5)
	var intercept := offset + target_velocity * lead_time
	_fly_towards(delta, intercept.normalized() * CRUISE_SPEED)


func on_ram(point: Vector2) -> void:
	super.on_ram(point)
	_retreat_direction = point.direction_to(position)
	if _retreat_direction == Vector2.ZERO:
		_retreat_direction = -Vector2.from_angle(heading)
	_retreat_origin = position
	_retreat_age = 0.0
	_retreating = true


func can_ram() -> bool:
	return not _retreating
