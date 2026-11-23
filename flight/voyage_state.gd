extends Node

signal changed

const DeckSimulation = preload("res://deck/deck_simulation.gd")
const WeaponProfile = preload("res://flight/weapon_profile.gd")
const Projectile = preload("res://flight/projectile.gd")
const EnemyShip = preload("res://flight/enemy_ship.gd")
const Physics = preload("res://flight/ship_physics.gd")
const RESCUE_MODEL = preload("res://flight/models/rescue_ship.tres")
const STATION_MODEL = preload("res://flight/models/station.tres")
const DRILL_SCENE := preload("res://flight/drill_enemy.tscn")
const FIGHTER_SCENE := preload("res://flight/fighter_enemy.tscn")
const MAX_TEST_ENEMIES := 16

enum Opponent { DRILL, FIGHTER }

enum Stage { ANSWER_DISTRESS, DELIVER_SURVIVORS, COMPLETE }

const HOME := 0
const DISTRESS := 1
const REFUGE := 2
const SYSTEMS := [
	{"name": "Гавань", "station": "Маяк", "map": Vector2(138, 305),
		"position": Vector2(563, 200), "arrival": Vector2(167, 316)},
	{"name": "Искра", "station": "Каскад", "map": Vector2(376, 142),
		"position": Vector2(592, 159), "arrival": Vector2(119, 353)},
	{"name": "Рубеж", "station": "Перевал", "map": Vector2(601, 292),
		"position": Vector2(579, 291), "arrival": Vector2(126, 129)},
]
# Start system, end system and fuel cost. Routes work in both directions.
const ROUTES := [Vector3i(HOME, DISTRESS, 2), Vector3i(DISTRESS, REFUGE, 3)]
const FULL_FUEL := 5
const RESCUE_COUNT := 8
const DOCK_RANGE := 105.0
const DOCK_SPEED := 34.0
const CONTACT_RADIUS := 82.0
const MAX_SPEED := 225.0
const MAX_SPIN := 3.3
const FLASH_SECONDS := 0.10

@export var weapon: WeaponProfile

var deck: DeckSimulation
var current_system := HOME
var fuel := FULL_FUEL
var stage := Stage.ANSWER_DISTRESS
var survivors_onboard := 0
var delivered := 0
var body := Physics.Body.new()
var station_body := Physics.Body.new()
var ship_position: Vector2:
	get: return body.position
	set(value): body.position = value
var velocity: Vector2:
	get: return body.velocity
	set(value): body.velocity = value
var heading: float:
	get: return body.heading
	set(value): body.heading = value
var angular_velocity: float:
	get: return body.spin
	set(value): body.spin = value
var acceleration := Vector2.ZERO
var turn_input := 0.0
var projectiles: Array[Projectile] = []
var weapon_cooldown := 0.0
var flash_remaining := 0.0
var flash_direction := Vector2.RIGHT
var thrusting := false
var docked := false
var manual_control := true
var simulation_speed := 1.0
var flight_computer := true
var scan_enemy := false
var incident_seen := false
var notice := ""
var in_arena := false
var enemies: Array[EnemyShip] = []
var enemy: EnemyShip:
	get:
		return null if enemies.is_empty() else enemies[scan_index % enemies.size()]
var scan_index := 0
var player_damage := true
var enemy_damage := true
var test_mass := 1.0
var test_thrust := 1.0
var _spawn_slot := 0
var _cascade_enemy: EnemyShip
var battle_result := ""


func configure(ship_deck: DeckSimulation) -> void:
	deck = ship_deck
	body.model = RESCUE_MODEL
	body.power = deck.power
	station_body.model = STATION_MODEL
	station_body.fixed = true
	deck.changed.connect(changed.emit)
	reset()


func reset() -> void:
	_clear_enemies()
	if is_instance_valid(_cascade_enemy) and not _cascade_enemy.is_queued_for_deletion():
		_cascade_enemy.queue_free()
	_cascade_enemy = null
	battle_result = ""
	scan_enemy = false
	current_system = HOME
	fuel = FULL_FUEL
	stage = Stage.ANSWER_DISTRESS
	survivors_onboard = 0
	delivered = 0
	incident_seen = false
	_spawn_ship()
	set_test_physics(test_mass, test_thrust)
	set_test_damage(player_damage, enemy_damage)
	notice = "Получен сигнал бедствия со станции «Каскад»."
	deck.reset(true)
	if in_arena:
		notice = "Полигон готов."
	changed.emit()


func add_test_enemy(kind: Opponent) -> EnemyShip:
	if not in_arena or enemies.size() >= MAX_TEST_ENEMIES:
		return null
	var bearing := heading if _spawn_slot == 0 else heading + _spawn_slot * 2.39996
	var distance := 360.0 + float(_spawn_slot % 4) * 48.0
	_spawn_slot += 1
	var hostile := _spawn_enemy(ship_position + Vector2.from_angle(bearing) * distance, kind)
	enemies.append(hostile)
	changed.emit()
	return hostile


func clear_test_enemies() -> void:
	if not in_arena:
		return
	_clear_enemies()
	for index in range(projectiles.size() - 1, -1, -1):
		projectiles[index].queue_free()
		projectiles.remove_at(index)
	scan_enemy = false
	changed.emit()


func _clear_enemies() -> void:
	for hostile in enemies:
		hostile.queue_free()
	enemies.clear()
	scan_index = 0
	_spawn_slot = 0


func set_test_physics(mass: float, thrust: float) -> void:
	test_mass = clampf(mass, 0.5, 3.0)
	test_thrust = clampf(thrust, 0.25, 2.0)
	body.mass_scale = test_mass if in_arena else 1.0
	body.thrust_scale = test_thrust if in_arena else 1.0


func set_test_damage(player: bool, hostiles: bool) -> void:
	player_damage = player
	enemy_damage = hostiles
	deck.damage_enabled = not in_arena or player
	for hostile in enemies:
		hostile.deck.damage_enabled = not in_arena or hostiles


func _spawn_enemy(at: Vector2, kind: Opponent = Opponent.DRILL) -> EnemyShip:
	var scene := FIGHTER_SCENE if kind == Opponent.FIGHTER else DRILL_SCENE
	var hostile := scene.instantiate() as EnemyShip
	hostile.position = at
	hostile.heading = at.angle_to_point(ship_position)
	add_child(hostile)
	hostile.deck.damage_enabled = not in_arena or enemy_damage
	return hostile


func _spawn_ship() -> void:
	for projectile in projectiles:
		projectile.queue_free()
	projectiles.clear()
	weapon_cooldown = 0.0
	flash_remaining = 0.0
	angular_velocity = 0.0
	body.active.clear()
	station_body.position = station_position()
	acceleration = Vector2.ZERO
	turn_input = 0.0
	body.fixed = false
	ship_position = SYSTEMS[current_system].arrival
	velocity = Vector2.ZERO
	heading = ship_position.angle_to_point(station_position())
	docked = false
	thrusting = false


func station_position() -> Vector2:
	return SYSTEMS[current_system].position


func distance_to_station() -> float:
	return ship_position.distance_to(station_position())


func route_cost(destination: int) -> int:
	for route: Vector3i in ROUTES:
		if (route.x == current_system and route.y == destination
				or route.y == current_system and route.x == destination):
			return route.z
	return 0


func jump_blocker(destination: int) -> String:
	if in_arena:
		return "Полигон находится вне звёздной карты."
	if stage == Stage.COMPLETE or not battle_result.is_empty():
		return "Рейс завершён."
	if destination < 0 or destination >= SYSTEMS.size():
		return "Выберите систему на карте."
	if destination == current_system:
		return "Корабль уже в этой системе."
	var cost := route_cost(destination)
	if cost == 0:
		return "Прямого маршрута нет."
	if deck.engine_health < 1.0 or not deck.module_online(deck.engine_tile):
		return "Сначала восстановите двигатель."
	if fuel < cost:
		return "Недостаточно топлива."
	return ""


func jump(destination: int) -> bool:
	if not jump_blocker(destination).is_empty():
		return false
	fuel -= route_cost(destination)
	current_system = destination
	_spawn_ship()
	enemies.clear()
	scan_index = 0
	if destination == DISTRESS:
		if not is_instance_valid(_cascade_enemy):
			_cascade_enemy = _spawn_enemy(ship_position + Vector2.from_angle(heading) * 410.0)
		if is_instance_valid(_cascade_enemy) and not _cascade_enemy.disabled():
			enemies.append(_cascade_enemy)
	if destination == DISTRESS and not incident_seen:
		incident_seen = true
		notice = "Двигатель повреждён. Возле «Каскада» обнаружен вражеский бур."
		deck.damage_engine(0.30)
	else:
		notice = "Прыжок завершён. Система «%s»." % SYSTEMS[destination].name
	changed.emit()
	return true


func dock_blocker() -> String:
	if in_arena:
		return "На полигоне нет станции."
	if stage == Stage.COMPLETE or not battle_result.is_empty():
		return "Рейс завершён."
	if docked:
		return ""
	if distance_to_station() > DOCK_RANGE:
		return "Войдите в зону стыковки."
	if velocity.length() > DOCK_SPEED:
		return "Снизьте скорость до %d ед/с." % int(DOCK_SPEED)
	if current_system == DISTRESS and stage == Stage.ANSWER_DISTRESS and (deck.airlock_progress < 1.0 or not deck.module_online(deck.airlock_tile)):
		return "Подготовьте шлюз на палубе."
	return ""


func toggle_docking() -> bool:
	if not dock_blocker().is_empty():
		return false
	if docked:
		docked = false
		body.fixed = false
		notice = "Корабль отстыкован."
	else:
		_dock()
	changed.emit()
	return true


func _dock() -> void:
	docked = true
	body.fixed = true
	body.active.clear()
	thrusting = false
	turn_input = 0.0
	angular_velocity = 0.0
	acceleration = Vector2.ZERO
	flash_remaining = 0.0
	var approach := station_position().direction_to(ship_position)
	ship_position = station_position() + approach * (CONTACT_RADIUS + 4.0)
	velocity = Vector2.ZERO
	heading = ship_position.angle_to_point(station_position())
	if current_system == DISTRESS:
		if stage == Stage.ANSWER_DISTRESS:
			survivors_onboard = RESCUE_COUNT
			stage = Stage.DELIVER_SURVIVORS
			notice = "На борту %d человек. Доставьте их в Гавань или на Рубеж." % RESCUE_COUNT
		else:
			notice = "Выжившие с «Каскада» уже на борту."
		return
	fuel = FULL_FUEL
	if stage == Stage.DELIVER_SURVIVORS:
		delivered = survivors_onboard
		survivors_onboard = 0
		stage = Stage.COMPLETE
		notice = "На станцию «%s» доставлено %d человек." % [SYSTEMS[current_system].station, delivered]
	else:
		notice = "Стыковка со станцией «%s». Топливо пополнено." % SYSTEMS[current_system].station


func _physics_process(delta: float) -> void:
	delta *= simulation_speed
	var steering := 0.0
	var forward_thrust := false
	var braking := false
	if manual_control:
		steering = Input.get_axis("flight_turn_left", "flight_turn_right")
		forward_thrust = Input.is_action_pressed("flight_thrust")
		braking = Input.is_action_pressed("flight_brake")

	var stabilized := manual_control and Input.is_action_pressed("flight_stabilize")
	var changed_flight := advance_flight(delta, steering, forward_thrust, braking, stabilized)
	var changed_battle := _advance_battle(delta)
	var changed_weapons := _advance_weapons(delta)
	if manual_control and Input.is_action_pressed("flight_fire") and fire():
		return # Firing already notified the view.
	if changed_flight or changed_weapons or changed_battle:
		changed.emit()


func advance_flight(delta: float, steering: float, forward_thrust: bool, braking: bool,
		stabilized := false) -> bool:
	if docked or stage == Stage.COMPLETE or not battle_result.is_empty() or delta <= 0.0:
		return false
	var previous_velocity := velocity
	var previous_acceleration := acceleration
	var previous_angular := angular_velocity
	var had_visuals := not body.active.is_empty()
	var pilot := deck.pilot_efficiency()
	var engine := deck.hull.condition(deck.engine_tile)
	var drive := lerpf(0.38, 1.0, deck.engine_health) * engine * pilot
	turn_input = steering * pilot
	if turn_input * angular_velocity > 0.0 and absf(angular_velocity) >= MAX_SPIN * pilot:
		turn_input = 0.0
	var main := drive if forward_thrust and not braking else 0.0
	var brake := engine * pilot if braking else 0.0
	var supply := body.advance(delta, main, turn_input, brake,
		pilot > 0.0 and (stabilized or braking and flight_computer), flight_computer)
	thrusting = main > 0.0 and supply > 0.0
	if thrusting:
		velocity = velocity.limit_length(maxf(MAX_SPEED * drive, previous_velocity.length()))
	ship_position += velocity * delta
	if not in_arena:
		_resolve_contact()
	acceleration = (velocity - previous_velocity) / delta
	return (had_visuals or not body.active.is_empty() or previous_angular != 0.0
		or not velocity.is_zero_approx() or previous_velocity != velocity
		or previous_acceleration != acceleration)


func weapon_status() -> String:
	if weapon == null or weapon.projectile == null:
		return "Не установлено"
	if not deck.module_online(deck.weapons_tile):
		return "Орудие отключено"
	if not deck.weapons_are_manned():
		return "Пост свободен"
	if docked or stage == Stage.COMPLETE or not battle_result.is_empty():
		return "Заблокировано"
	if weapon_cooldown > 0.0:
		return "Перезарядка"
	return "Готово" if deck.power.can_spend(weapon.energy_cost) else "Зарядка"


func fire() -> bool:
	if weapon == null or weapon.projectile == null or docked or stage == Stage.COMPLETE or not battle_result.is_empty():
		return false
	if weapon_cooldown > 0.0 or deck.disabled() or not deck.weapons_are_manned() or not deck.power.can_spend(weapon.energy_cost):
		return false
	var instance := weapon.projectile.instantiate()
	var projectile := instance as Projectile
	if projectile == null:
		instance.free()
		push_error("Weapon projectile must inherit projectile.gd")
		return false
	deck.power.spend(weapon.energy_cost)
	var gunner := deck.operator_at(deck.WorkPose.WEAPONS)
	var spread := (1.0 - deck.hull.condition(deck.weapons_tile)) * weapon.damaged_spread_degrees
	if gunner.role != "Наводчик":
		spread += 5.0
	var angle := heading + deg_to_rad(randf_range(-spread, spread))
	var direction := Vector2.from_angle(angle)
	flash_direction = direction
	flash_remaining = FLASH_SECONDS
	projectile.damage = weapon.damage
	projectile.breach_chance = weapon.breach_chance
	projectile.crew_damage = weapon.crew_damage
	projectile.launch(muzzle_position(), direction)
	add_child(projectile)
	projectiles.append(projectile)
	weapon_cooldown = weapon.cooldown
	changed.emit()
	return true


func muzzle_position() -> Vector2:
	var mount := body.model.muzzle
	mount.y = -weapon.muzzle_offset if weapon != null else mount.y
	return body.model.world_point(mount, ship_position, heading)


func _advance_weapons(delta: float) -> bool:
	var updated := not projectiles.is_empty() or weapon_cooldown > 0.0 or flash_remaining > 0.0
	weapon_cooldown = move_toward(weapon_cooldown, 0.0, delta)
	flash_remaining = move_toward(flash_remaining, 0.0, delta)
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		var before := projectile.position
		projectile.advance(delta)
		if projectile.remaining <= 0.0 or _projectile_hit(projectile, before):
			projectiles.remove_at(index)
			projectile.queue_free()
	return updated


func _projectile_hit(projectile: Projectile, before: Vector2) -> bool:
	var nearest := INF
	if not in_arena:
		var station_hit: Variant = Physics.segment_hit(before, projectile.position, station_body.outline())
		if station_hit != null:
			nearest = before.distance_squared_to(station_hit)

	var target_body: Physics.Body
	var target_deck: DeckSimulation
	var impact := Vector2.ZERO
	if projectile.hostile:
		var point: Variant = Physics.segment_hit(before, projectile.position, body.outline())
		if point != null and before.distance_squared_to(point) < nearest:
			target_body = body
			target_deck = deck
			impact = point
	else:
		for hostile in enemies:
			if hostile.disabled():
				continue
			var point: Variant = Physics.segment_hit(before, projectile.position, hostile.body.outline())
			if point != null and before.distance_squared_to(point) < nearest:
				nearest = before.distance_squared_to(point)
				target_body = hostile.body
				target_deck = hostile.deck
				impact = point
	if target_deck == null:
		return nearest < INF
	var side := (impact - target_body.position).rotated(-target_body.heading - PI * 0.5)
	if side.is_zero_approx():
		side = -projectile.velocity.rotated(-target_body.heading - PI * 0.5)
	target_deck.apply_hit(projectile.damage, projectile.breach_chance, projectile.crew_damage, side)
	return true


func _advance_battle(delta: float) -> bool:
	if not battle_result.is_empty() or stage == Stage.COMPLETE:
		return false
	if deck.disabled():
		battle_result = "Корабль потерян"
		thrusting = false
		turn_input = 0.0
		acceleration = Vector2.ZERO
		body.active.clear()
		notice = "Корабль потерян. Нажмите «Сброс»."
		return true
	if enemies.is_empty():
		return false
	for index in range(enemies.size() - 1, -1, -1):
		var hostile := enemies[index]
		if hostile.disabled():
			notice = "%s выведен из строя." % hostile.call_sign
			if hostile != _cascade_enemy:
				hostile.queue_free()
			enemies.remove_at(index)
		else:
			hostile.advance(delta, ship_position, velocity)
			if hostile.shot_requested:
				_fire_hostile(hostile)

	for index in range(enemies.size()):
		var hostile := enemies[index]
		_resolve_enemy_contact(hostile, delta)
		for other in range(index + 1, enemies.size()):
			var hit := Physics.contact(hostile.body, enemies[other].body)
			if hit != null:
				Physics.resolve(hostile.body, enemies[other].body, hit, 0.18)
	return true


func _fire_hostile(hostile: EnemyShip) -> void:
	var profile := hostile.weapon
	if profile == null or profile.projectile == null or profile.mounts.is_empty():
		return
	if not hostile.deck.power.spend(profile.energy_cost):
		return
	var spread := (1.0 - hostile.deck.hull.condition(hostile.deck.weapons_tile)) * profile.damaged_spread_degrees
	for mount in profile.mounts:
		var projectile := profile.projectile.instantiate() as Projectile
		projectile.hostile = true
		projectile.damage = profile.damage
		projectile.breach_chance = profile.breach_chance
		projectile.crew_damage = profile.crew_damage
		var muzzle := hostile.model.world_point(mount, hostile.position, hostile.heading)
		var direction := Vector2.from_angle(hostile.heading + deg_to_rad(randf_range(-spread, spread)))
		projectile.launch(muzzle, direction)
		add_child(projectile)
		projectiles.append(projectile)
	hostile.weapons_cooldown = profile.cooldown
	hostile.flash_remaining = FLASH_SECONDS


func _resolve_enemy_contact(hostile: EnemyShip, delta: float) -> void:
	var hit := Physics.contact(body, hostile.body)
	if hit == null:
		return
	var before := velocity
	Physics.resolve(body, hostile.body, hit, 0.72 if hostile.can_ram() else 0.22)
	acceleration += (velocity - before) / delta
	if hostile.can_ram() and hit.closing_speed >= 12.0:
		var side := (hit.point - ship_position).rotated(-heading - PI * 0.5)
		deck.apply_hit(hostile.ram_damage, 0.35, 0.0, side)
		hostile.on_ram(hit.point)
		notice = "Удар бура. Проверьте отсеки на палубе."


func _resolve_contact() -> void:
	var hit := Physics.contact(body, station_body)
	if hit != null:
		Physics.resolve(body, station_body, hit, 0.0)
