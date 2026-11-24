extends RefCounted

const Physics = preload("res://flight/ship_physics.gd")
const MODEL = preload("res://flight/models/drone.tres")
const HULL := 24.0
const ORBIT_RADIUS := 156.0
const ORBIT_SPIN := 0.64
const COOLDOWN := 3.4

var body := Physics.Body.new()
var health := HULL
var carrier_id := 0
var orbit_slot := 0
var shutdown_time := -1.0
var cooldown := 0.0
var disabled_time := 0.0
var hit_time := 0.0
var phase := 0.0
var shot_requested := false
var damage_enabled := true


func _init(at: Vector2, angle: float) -> void:
	body.model = MODEL
	body.position = at
	phase = angle
	cooldown = 0.7 + fposmod(angle, 1.5)


func disabled() -> bool:
	return health <= 0.0


func strike(damage: float) -> void:
	if damage_enabled:
		health = maxf(0.0, health - damage)
		hit_time = 0.18


func advance(delta: float, center: Vector2, center_velocity: Vector2, target: Vector2) -> void:
	hit_time = move_toward(hit_time, 0.0, delta)
	shot_requested = false
	if disabled_time > 0.0:
		disabled_time = move_toward(disabled_time, 0.0, delta)
		body.position += body.velocity * delta
		return
	cooldown = move_toward(cooldown, 0.0, delta)
	phase = wrapf(phase + ORBIT_SPIN * delta, -PI, PI)
	var offset := Vector2.from_angle(phase) * ORBIT_RADIUS
	var desired := center_velocity + offset.rotated(PI * 0.5) * ORBIT_SPIN
	desired += (center + offset - body.position).limit_length(215.0) * 1.4
	body.velocity = body.velocity.move_toward(desired.limit_length(310.0), 260.0 * delta)
	body.position += body.velocity * delta
	var aim := body.position.angle_to_point(target)
	body.heading = rotate_toward(body.heading, aim, 6.0 * delta)
	if cooldown <= 0.0 and body.position.distance_to(center + offset) < 48.0 and absf(angle_difference(body.heading, aim)) < 0.14:
		shot_requested = true
		cooldown = COOLDOWN
