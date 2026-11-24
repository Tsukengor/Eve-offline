extends Node

const DeckSimulation = preload("res://deck/deck_simulation.gd")
const Physics = preload("res://flight/ship_physics.gd")
const Model = preload("res://flight/ship_model.gd")
const WeaponProfile = preload("res://flight/weapon_profile.gd")
const HIT_SECONDS := 0.23

@export var call_sign := "Неизвестный корабль"
@export var sprite: Texture2D
@export var hull_wreck: Texture2D
@export var crew_derelict: Texture2D
@export var sprite_size := 76.0
@export var weapon: WeaponProfile
@export var model: Model = preload("res://flight/models/drill.tres")
@export var ram_damage := 27.0
@export var ram_self_damage := 8.0

var deck: DeckSimulation
var body := Physics.Body.new()
var position: Vector2:
	get: return body.position
	set(value): body.position = value
var velocity: Vector2:
	get: return body.velocity
	set(value): body.velocity = value
var heading: float:
	get: return body.heading
	set(value): body.heading = value
var _crew_interval := 0.0
var shot_requested := false
var conserving_power := false
var weapons_cooldown := 0.0
var flash_remaining := 0.0
var hit_remaining := 0.0
var hit_side := Vector2.UP


func _ready() -> void:
	body.model = model
	deck = DeckSimulation.new()
	_configure_deck()
	add_child(deck)
	body.power = deck.power
	deck.set_physics_process(false)
	deck.reset(true)
	deck.hit_received.connect(_mark_hit)
	for index in range(deck.crew.size()):
		deck.crew[index].title = "%s · %d" % [call_sign, index + 1]


func _configure_deck() -> void:
	pass


func disabled() -> bool:
	return deck.disabled()


func advance(delta: float, target_position: Vector2, target_velocity: Vector2) -> void:
	if disabled():
		return
	shot_requested = false
	weapons_cooldown = maxf(0.0, weapons_cooldown - delta)
	flash_remaining = maxf(0.0, flash_remaining - delta)
	deck._physics_process(delta)
	_crew_interval -= delta
	if _crew_interval <= 0.0:
		_crew_interval = 0.45
		_assign_crew()
	_steer(delta, target_position, target_velocity)
	position += velocity * delta


func _mark_hit(side: Vector2) -> void:
	if hit_remaining > HIT_SECONDS * 0.45:
		return
	hit_side = side.normalized() if not side.is_zero_approx() else Vector2.UP
	hit_remaining = HIT_SECONDS


func _steer(_delta: float, _target_position: Vector2, _target_velocity: Vector2) -> void:
	pass


func _conserve_if_low(reserve: float) -> bool:
	if conserving_power:
		conserving_power = deck.power.energy < reserve + 24.0
	else:
		conserving_power = deck.power.energy < reserve
	return conserving_power


func _recovery_throttle() -> float:
	# Even with several nozzles active, normal recovery retains a net energy gain.
	return minf(0.18, deck.energy_recovery_rate() / 52.0)


func _fly_towards(delta: float, goal_velocity: Vector2, throttle := 1.0, aim: Variant = null) -> void:
	var pilot := deck.pilot_efficiency()
	var drive := deck.hull.condition(deck.engine_tile) * pilot
	if pilot <= 0.0 or not deck.module_online(deck.engine_tile):
		body.advance(delta, 0.0, 0.0, 0.0, false)
		return
	var goal := goal_velocity * lerpf(0.45, 1.0, drive)
	var course := goal.angle() if aim == null else float(aim)
	var forward := Vector2.from_angle(heading)
	var error := absf(angle_difference(heading, course))
	var deficit := (goal - velocity).dot(forward)
	var main := clampf(deficit / 35.0, 0.0, 1.0) * drive if error < 0.48 else 0.0
	# Bleed sideways drift while applying forward thrust, and brake while turning.
	var trim := goal if aim != null or error < 0.48 else Vector2.ZERO
	body.advance(delta, main * throttle, body.turn_toward(course, pilot) * throttle,
		drive * 0.70 * throttle, false, true, trim)


func can_ram() -> bool:
	return false


func on_ram(point: Vector2) -> void:
	deck.apply_hit(ram_self_damage, 0.0, 0.0, (point - position).rotated(-heading - PI * 0.5), deck.weapons_tile)


func _assign_crew() -> void:
	var posted := {}
	var sealing := {}
	var repairing := {}
	for index in range(deck.crew.size()):
		var member := deck.crew[index]
		if member.health <= 0.0 or member.target == deck.INVALID_CELL or member.blocked:
			continue
		if member.order == deck.Order.POST and member.target == deck.reactor_tile and deck.hull.condition(deck.reactor_tile) < 1.0:
			deck.assign_order(index, deck.reactor_tile)
		match member.order:
			deck.Order.POST:
				posted[member.target] = true
			deck.Order.SEAL:
				sealing[member.target] = true
			deck.Order.REPAIR_ROOM:
				repairing[deck.hull.room_at[member.target]] = true

	var jobs: Array[Vector2i] = []
	for breach in deck.hull.breaches:
		if not sealing.has(breach):
			jobs.append(breach)
	for module: Vector2i in [deck.reactor_tile, deck.engine_tile, deck.bridge_tile, deck.life_support_tile, deck.weapons_tile, deck.airlock_tile]:
		_add_repair_job(module, repairing, jobs)
	for room in deck.hull.rooms:
		for tile in room.tiles:
			if not deck.hull.breaches.has(tile):
				_add_repair_job(tile, repairing, jobs)
				break
	if not posted.has(deck.bridge_tile) and deck.module_online(deck.bridge_tile) and deck.hull.condition(deck.bridge_tile) == 1.0:
		jobs.append(deck.bridge_tile)

	if not posted.has(deck.weapons_tile) and deck.module_online(deck.weapons_tile):
		jobs.append(deck.weapons_tile)

	for index in range(deck.crew.size()):
		if jobs.is_empty():
			break
		var member := deck.crew[index]
		if member.health <= 0.0 or (member.order != deck.Order.IDLE and not member.blocked
				and not (member.order == deck.Order.POST and member.target == deck.reactor_tile)):
			continue
		deck.assign_order(index, jobs.pop_front())

	if jobs.is_empty() and not posted.has(deck.reactor_tile) and deck.hull.condition(deck.reactor_tile) == 1.0:
		for index in range(deck.crew.size()):
			if deck.crew[index].health > 0.0 and deck.crew[index].order == deck.Order.IDLE:
				deck.assign_order(index, deck.reactor_tile)
				break


func _add_repair_job(tile: Vector2i, repairing: Dictionary, jobs: Array[Vector2i]) -> void:
	var room: int = deck.hull.room_at[tile]
	if deck.hull.condition(tile) < 1.0 and not repairing.has(room):
		jobs.append(tile)
		repairing[room] = true
