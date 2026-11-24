extends Node

signal changed
signal weapon_fired(kind: int)
signal defeat_started

const Adventure = preload("res://flight/adventure.gd")
const DeckSimulation = preload("res://deck/deck_simulation.gd")
const WeaponProfile = preload("res://flight/weapon_profile.gd")
const Projectile = preload("res://flight/projectile.gd")
const Weapons = preload("res://flight/weapon_combat.gd")
const EnemyShip = preload("res://flight/enemy_ship.gd")
const Physics = preload("res://flight/ship_physics.gd")
const RESCUE_MODEL = preload("res://flight/models/rescue_ship.tres")
const STATION_MODEL = preload("res://flight/models/station.tres")
const DRILL_SCENE := preload("res://flight/drill_enemy.tscn")
const FIGHTER_SCENE := preload("res://flight/fighter_enemy.tscn")
const SWARM_SCENE := preload("res://flight/swarm_enemy.tscn")
const SwarmShip = preload("res://flight/swarm_enemy.gd")
const Drone = preload("res://flight/drone.gd")
const DRONE_WEAPON := preload("res://flight/drone_weapon.tres")
const MISSILE_WEAPON := preload("res://flight/missile_weapon.tres")
const TEST_WEAPONS := [
	preload("res://flight/kinetic_weapon.tres"), preload("res://flight/laser_weapon.tres"),
	MISSILE_WEAPON, preload("res://flight/emp_weapon.tres"),
	preload("res://flight/rail_weapon.tres"),
]
const MAX_TEST_ENEMIES := 16

enum Opponent { DRILL, FIGHTER, MISSILE_FIGHTER, SWARM }

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
	{"name": "Свалка", "station": "Сборщик", "map": Vector2(302, 338),
		"position": Vector2(630, 252), "arrival": Vector2(100, 366)},
	{"name": "Гроза", "station": "Кромка", "map": Vector2(580, 115),
		"position": Vector2(660, 208), "arrival": Vector2(142, 410)},
	{"name": "Гнездо", "station": "Якорь", "map": Vector2(441, 237),
		"position": Vector2(690, 276), "arrival": Vector2(80, 315)},
]
# Start system, end system and fuel cost. Routes work in both directions.
const ROUTES := [Vector3i(HOME, DISTRESS, 2), Vector3i(DISTRESS, REFUGE, 3)]
const FULL_FUEL := 5
const RESCUE_COUNT := 8
const DOCK_RANGE := 264.0
const DOCK_SPEED := 34.0
const STATION_SIZE := 392.0
const STATION_SPIN := 0.035
const DOCK_RADIUS := 230.0
const DOCK_SECONDS := 1.65
const PLAYER_TURN_SCALE := 1.5
const PASSIVE_ANGULAR_DECELERATION := 0.24
const DEFEAT_SECONDS := 2.25
const ADVENTURE_FUEL := 8
const ION_CLOUDS := [Vector3(-330, 137, 116), Vector3(-130, 239, 91)]
const DEBRIS := preload("res://assets/flight/drill_enemy_derelict.png")
const MAX_SPEED := 225.0
const MAX_SPIN := 3.3
const FLASH_SECONDS := 0.10

class Wreck:
	var position: Vector2
	var velocity: Vector2
	var rotation: float
	var spin: float
	var texture: Texture2D
	var size: float
	var age := 0.0
	var broken_hull: bool
	var collider: Physics.Body
	var vanishes := false


@export var weapon: WeaponProfile

var deck: DeckSimulation
var current_system := HOME
var fuel := FULL_FUEL
var stage := Stage.ANSWER_DISTRESS
var survivors_onboard := 0
var delivered := 0
var body := Physics.Body.new()
var station_body := Physics.Body.new()
var docking_time := 0.0
var dock_angle := 0.0
var _dock_start_bearing := 0.0
var _dock_start_radius := 0.0
var _dock_start_heading := 0.0
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
var test_weapon := 0
var _voyage_weapon: WeaponProfile
var laser_beam: Projectile
var _laser_spent := false
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
var in_training := false
var training_can_dock := false
var training_hint := ""
var training_step := 1
var enemies: Array[EnemyShip] = []
var drones: Array[Drone] = []
var wrecks: Array[Wreck] = []
var _wrecks_by_system: Dictionary[int, Array] = {}
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
var defeat_elapsed := 0.0
var defeat_hull := false
var adventure: Adventure
var adventure_save_path := Adventure.SAVE_PATH


func configure(ship_deck: DeckSimulation) -> void:
	deck = ship_deck
	_voyage_weapon = weapon
	body.model = RESCUE_MODEL
	body.passive_angular_deceleration = PASSIVE_ANGULAR_DECELERATION
	body.turn_scale = PLAYER_TURN_SCALE
	body.power = deck.power
	body.shield = Physics.Shield.new()
	station_body.model = STATION_MODEL
	station_body.fixed = true
	station_body.spin = STATION_SPIN
	deck.changed.connect(changed.emit)
	reset()


func reset() -> void:
	weapon = TEST_WEAPONS[test_weapon] if in_arena else _voyage_weapon
	_clear_enemies()
	if is_instance_valid(_cascade_enemy) and not _cascade_enemy.is_queued_for_deletion():
		_cascade_enemy.queue_free()
	_cascade_enemy = null
	battle_result = ""
	defeat_elapsed = 0.0
	defeat_hull = false
	scan_enemy = false
	current_system = HOME
	fuel = FULL_FUEL
	stage = Stage.ANSWER_DISTRESS
	survivors_onboard = 0
	delivered = 0
	incident_seen = false
	wrecks.clear()
	_wrecks_by_system.clear()
	body.shield.reset()
	body.shield.online = false
	_spawn_ship()
	set_test_physics(test_mass, test_thrust)
	set_test_damage(player_damage, enemy_damage)
	notice = "Получен сигнал бедствия со станции «Каскад»."
	deck.reset(true)
	deck.reactor_multiplier = 1.0
	body.turn_scale = PLAYER_TURN_SCALE
	body.shield.capacity = Physics.Shield.CAPACITY
	body.shield.reset()
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


func spawn_training_target() -> EnemyShip:
	var target := _spawn_enemy(ship_position + Vector2.from_angle(heading) * 190.0, Opponent.FIGHTER)
	target.call_sign = "Учебная цель"
	enemies.append(target)
	return target


func finish_training_target(target: EnemyShip) -> void:
	if is_instance_valid(target):
		enemies.erase(target)
		if not target.is_queued_for_deletion():
			target.queue_free()
	for shot in projectiles:
		shot.queue_free()
	projectiles.clear()


func clear_test_enemies() -> void:
	if not in_arena:
		return
	wrecks.clear()
	stop_laser()
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
	drones.clear()
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
	for drone in drones:
		drone.damage_enabled = not in_arena or hostiles


func _spawn_enemy(at: Vector2, kind: Opponent = Opponent.DRILL) -> EnemyShip:
	var scene := FIGHTER_SCENE
	if kind == Opponent.DRILL:
		scene = DRILL_SCENE
	elif kind == Opponent.SWARM:
		scene = SWARM_SCENE
	var hostile := scene.instantiate() as EnemyShip
	if kind == Opponent.MISSILE_FIGHTER:
		hostile.weapon = MISSILE_WEAPON
		hostile.call_sign = "Ракетчик"
	hostile.position = at
	hostile.heading = at.angle_to_point(ship_position)
	add_child(hostile)
	if hostile.deck.shield_tile != DeckSimulation.INVALID_CELL:
		hostile.body.shield = Physics.Shield.new()
		hostile.body.shield.online = false
	hostile.deck.damage_enabled = not in_arena or enemy_damage
	return hostile


func _spawn_ship() -> void:
	stop_laser()
	_laser_spent = false
	for projectile in projectiles:
		projectile.queue_free()
	projectiles.clear()
	weapon_cooldown = 0.0
	flash_remaining = 0.0
	angular_velocity = 0.0
	body.active.clear()
	station_body.position = station_position()
	station_body.heading = -PI * 0.5
	docking_time = 0.0
	acceleration = Vector2.ZERO
	turn_input = 0.0
	body.fixed = false
	ship_position = SYSTEMS[current_system].arrival
	velocity = Vector2.ZERO
	heading = ship_position.angle_to_point(station_position())
	docked = false
	thrusting = false


func system_count() -> int:
	return SYSTEMS.size() if adventure != null else 3


func routes() -> Array:
	return ROUTES + Adventure.ROUTES if adventure != null else ROUTES


func fuel_capacity() -> int:
	return ADVENTURE_FUEL if adventure != null else FULL_FUEL


func station_position() -> Vector2:
	return SYSTEMS[current_system].position


func distance_to_station() -> float:
	return ship_position.distance_to(station_position())


func route_cost(destination: int) -> int:
	for route: Vector3i in routes():
		if (route.x == current_system and route.y == destination
				or route.y == current_system and route.x == destination):
			return route.z
	return 0


func jump_blocker(destination: int) -> String:
	if docking_time > 0.0:
		return "Дождитесь завершения стыковки."
	if in_training:
		return "Учебный рейс проходит в одной системе."
	if in_arena:
		return "Полигон находится вне звёздной карты."
	if stage == Stage.COMPLETE or not battle_result.is_empty():
		return "Рейс завершён."
	if destination < 0 or destination >= system_count():
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
	_wrecks_by_system[current_system] = wrecks.duplicate()
	current_system = destination
	wrecks.assign(_wrecks_by_system.get(destination, []))
	_spawn_ship()
	if adventure != null:
		_clear_enemies()
		_enter_adventure_sector()
		notice = "Вход в систему «%s»." % SYSTEMS[destination].name
		changed.emit()
		return true
	enemies.clear()
	drones.clear()
	scan_index = 0
	if destination == DISTRESS:
		if not is_instance_valid(_cascade_enemy):
			_cascade_enemy = _spawn_enemy(ship_position + Vector2.from_angle(heading) * 260.0)
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
	if docking_time > 0.0:
		return "Идёт стыковка."
	if in_training and not training_can_dock:
		return "Сначала выполни учебные задачи."
	if in_arena:
		return "На полигоне нет станции."
	if stage == Stage.COMPLETE or not battle_result.is_empty():
		return "Рейс завершён."
	if docked:
		return ""
	if adventure != null and (not enemies.is_empty() or not drones.is_empty()):
		return "Причал закрыт во время боя."
	if distance_to_station() > DOCK_RANGE:
		return "Войдите в зону стыковки."
	if velocity.length() > DOCK_SPEED:
		return "Снизьте скорость до %d ед/с." % int(DOCK_SPEED)
	if adventure == null and current_system == DISTRESS and stage == Stage.ANSWER_DISTRESS and (deck.airlock_progress < 1.0 or not deck.module_online(deck.airlock_tile)):
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
		_begin_docking()
	changed.emit()
	return true


func _begin_docking() -> void:
	stop_laser()
	body.fixed = true
	body.active.clear()
	thrusting = false
	turn_input = 0.0
	angular_velocity = 0.0
	acceleration = Vector2.ZERO
	flash_remaining = 0.0
	velocity = Vector2.ZERO
	var station_rotation := station_body.heading + PI * 0.5
	_dock_start_bearing = station_position().angle_to_point(ship_position) - station_rotation
	dock_angle = snappedf(_dock_start_bearing, PI * 0.5)
	_dock_start_radius = distance_to_station()
	_dock_start_heading = heading
	docking_time = DOCK_SECONDS


func _advance_station(delta: float) -> void:
	if docking_time <= 0.0 and not docked:
		return
	if deck.disabled():
		docking_time = 0.0
		docked = false
		body.fixed = false
		return
	var was_docking := docking_time > 0.0
	docking_time = move_toward(docking_time, 0.0, delta)
	var approach := smoothstep(0.0, 1.0, 1.0 - docking_time / DOCK_SECONDS)
	var angle := lerp_angle(_dock_start_bearing, dock_angle, approach) + station_body.heading + PI * 0.5
	var radius := lerpf(_dock_start_radius, DOCK_RADIUS, approach)
	ship_position = station_position() + Vector2.from_angle(angle) * radius
	heading = lerp_angle(_dock_start_heading, angle + PI, approach)
	if was_docking and docking_time == 0.0:
		_finish_docking()


func _finish_docking() -> void:
	docked = true
	if adventure != null:
		_arrive_at_adventure_station()
		return
	if in_training:
		deck.board_passengers(RESCUE_COUNT)
		delivered = RESCUE_COUNT
		stage = Stage.COMPLETE
		return
	if current_system == DISTRESS:
		if stage == Stage.ANSWER_DISTRESS:
			survivors_onboard = RESCUE_COUNT
			deck.board_passengers(survivors_onboard)
			stage = Stage.DELIVER_SURVIVORS
			notice = "На борту %d человек. Доставьте их в Гавань или на Рубеж." % RESCUE_COUNT
		else:
			notice = "Выжившие с «Каскада» уже на борту."
		return
	fuel = FULL_FUEL
	if stage == Stage.DELIVER_SURVIVORS:
		delivered = survivors_onboard
		survivors_onboard = 0
		deck.unload_passengers()
		stage = Stage.COMPLETE
		notice = "На станцию «%s» доставлено %d человек." % [SYSTEMS[current_system].station, delivered]
	else:
		notice = "Стыковка со станцией «%s». Топливо пополнено." % SYSTEMS[current_system].station


func _physics_process(delta: float) -> void:
	delta *= simulation_speed
	if not battle_result.is_empty():
		_advance_defeat(delta)
		return
	_apply_ion_hazards(delta)
	if not in_arena:
		station_body.heading = wrapf(station_body.heading + station_body.spin * delta, -PI, PI)
	var firing := (manual_control and not docked and docking_time <= 0.0 and stage != Stage.COMPLETE
		and battle_result.is_empty() and Input.is_action_pressed("flight_fire"))
	if not firing:
		stop_laser()
		_laser_spent = false
	var steering := 0.0
	var forward_thrust := false
	var braking := false
	if manual_control:
		steering = Input.get_axis("flight_turn_left", "flight_turn_right")
		forward_thrust = Input.is_action_pressed("flight_thrust")
		braking = Input.is_action_pressed("flight_brake")

	var stabilized := manual_control and Input.is_action_pressed("flight_stabilize")
	var changed_shield := body.shield.advance(delta, deck.operator_at(DeckSimulation.WorkPose.SHIELD) != null)
	var changed_flight := advance_flight(delta, steering, forward_thrust, braking, stabilized)
	var changed_battle := _advance_battle(delta)
	if not battle_result.is_empty():
		changed.emit()
		return
	if not in_arena:
		_advance_station(delta)
	var changed_wrecks := _advance_wrecks(delta)
	var channeling := weapon != null and weapon.kind == WeaponProfile.Kind.LASER
	if firing and channeling:
		fire()
	var changed_weapons := _advance_weapons(delta)
	if firing and not channeling and fire():
		return # Firing already notified the view.
	if changed_flight or changed_weapons or changed_battle or changed_wrecks or changed_shield or not in_arena:
		changed.emit()


func advance_flight(delta: float, steering: float, forward_thrust: bool, braking: bool,
		stabilized := false) -> bool:
	if docked or docking_time > 0.0 or stage == Stage.COMPLETE or not battle_result.is_empty() or delta <= 0.0:
		return false
	var previous_velocity := velocity
	var previous_acceleration := acceleration
	var previous_angular := angular_velocity
	var had_visuals := not body.active.is_empty()
	var pilot := deck.pilot_efficiency()
	var engine_online := deck.module_online(deck.engine_tile)
	var engine := deck.hull.condition(deck.engine_tile) if engine_online else 0.0
	var drive := lerpf(0.38, 1.0, deck.engine_health) * engine * pilot
	turn_input = steering * pilot if engine_online else 0.0
	if turn_input * angular_velocity > 0.0 and absf(angular_velocity) >= MAX_SPIN * pilot:
		turn_input = 0.0
	var main := drive if forward_thrust and not braking else 0.0
	var brake := engine * pilot if braking else 0.0
	var supply := body.advance(delta, main, turn_input, brake,
		engine_online and pilot > 0.0 and (stabilized or braking and flight_computer), flight_computer)
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


func select_test_weapon(index: int) -> void:
	if not in_arena or index < 0 or index >= TEST_WEAPONS.size():
		return
	stop_laser()
	test_weapon = index
	weapon = TEST_WEAPONS[index]
	changed.emit()


func weapon_status() -> String:
	if weapon == null or weapon.projectile == null:
		return "Не установлено"
	if not deck.module_online(deck.weapons_tile):
		return "Орудие отключено"
	if not deck.weapons_are_manned():
		return "Пост свободен"
	if docked or docking_time > 0.0 or stage == Stage.COMPLETE or not battle_result.is_empty():
		return "Заблокировано"
	if weapon.kind == WeaponProfile.Kind.LASER:
		return "Луч активен" if is_instance_valid(laser_beam) else ("Зарядка" if _laser_spent or deck.power.energy <= 0.0 else "Готово")
	if weapon_cooldown > 0.0:
		return "Перезарядка"
	return "Готово" if deck.power.can_spend(weapon.energy_cost) else "Зарядка"


func fire() -> bool:
	if weapon == null or weapon.projectile == null or docked or docking_time > 0.0 or stage == Stage.COMPLETE or not battle_result.is_empty():
		return false
	if deck.disabled() or not deck.weapons_are_manned():
		return false
	var is_laser := weapon.kind == WeaponProfile.Kind.LASER
	if is_laser:
		if is_instance_valid(laser_beam) or _laser_spent or deck.power.energy <= 0.0:
			return false
	elif weapon_cooldown > 0.0 or not deck.power.can_spend(weapon.energy_cost):
		return false
	var gunner := deck.operator_at(deck.WorkPose.WEAPONS)
	var spread := (1.0 - deck.hull.condition(deck.weapons_tile)) * weapon.damaged_spread_degrees
	if gunner.role != "Наводчик":
		spread += 5.0
	var angle := heading + deg_to_rad(randf_range(-spread, spread))
	var mount := body.model.muzzle
	mount.y = -weapon.muzzle_offset
	if not _launch_shot(weapon, body, mount, angle, false):
		return false
	if is_laser:
		laser_beam = projectiles.back()
	else:
		deck.power.spend(weapon.energy_cost)
		weapon_fired.emit(weapon.kind)
	flash_direction = Vector2.from_angle(angle)
	flash_remaining = FLASH_SECONDS if weapon.kind in [WeaponProfile.Kind.KINETIC, WeaponProfile.Kind.MISSILE, WeaponProfile.Kind.RAIL] else 0.0
	if not is_laser:
		weapon_cooldown = weapon.cooldown
	changed.emit()
	return true


func stop_laser() -> void:
	if not is_instance_valid(laser_beam):
		return
	projectiles.erase(laser_beam)
	laser_beam.queue_free()
	laser_beam = null
	changed.emit()


func muzzle_position() -> Vector2:
	var mount := body.model.muzzle
	mount.y = -weapon.muzzle_offset if weapon != null else mount.y
	return body.model.world_point(mount, ship_position, heading)


func _advance_weapons(delta: float) -> bool:
	var updated := not projectiles.is_empty() or weapon_cooldown > 0.0 or flash_remaining > 0.0
	weapon_cooldown = move_toward(weapon_cooldown, 0.0, delta)
	flash_remaining = move_toward(flash_remaining, 0.0, delta)
	if not projectiles.is_empty():
		var targets := _weapon_targets()
		var station := null if in_arena else station_body
		for index in range(projectiles.size() - 1, -1, -1):
			var projectile := projectiles[index]
			if not Weapons.tick(projectile, delta, targets, station):
				if projectile == laser_beam:
					_laser_spent = deck.power.energy <= 0.0
					laser_beam = null
				projectiles.remove_at(index)
				projectile.queue_free()
	return updated


func _weapon_targets() -> Array[Weapons.Target]:
	var targets: Array[Weapons.Target] = [Weapons.Target.new(body, deck, false)]
	for hostile in enemies:
		targets.append(Weapons.Target.new(hostile.body, hostile.deck, true))
	for drone in drones:
		targets.append(Weapons.Target.new(drone.body, null, true, drone))
	return targets


func _launch_shot(profile: WeaponProfile, shooter: Physics.Body, mount: Vector2, angle: float, hostile: bool) -> bool:
	var instance := profile.projectile.instantiate()
	var shot := instance as Projectile
	if shot == null:
		instance.free()
		push_error("Weapon projectile must inherit projectile.gd")
		return false
	var targets: Array[Weapons.Target] = []
	if profile.kind == WeaponProfile.Kind.MISSILE:
		targets = _weapon_targets()
	Weapons.begin(shot, profile, shooter, mount, angle, hostile, targets)
	add_child(shot)
	projectiles.append(shot)
	return true


func _advance_battle(delta: float) -> bool:
	if not battle_result.is_empty() or stage == Stage.COMPLETE:
		return false
	if deck.disabled():
		_begin_defeat()
		return true
	if enemies.is_empty() and drones.is_empty():
		return false
	var obstacles := _wreck_colliders()
	for index in range(enemies.size() - 1, -1, -1):
		var hostile := enemies[index]
		if hostile.body.shield != null:
			hostile.body.shield.advance(delta, hostile.deck.operator_at(DeckSimulation.WorkPose.SHIELD) != null)
		hostile.hit_remaining = move_toward(hostile.hit_remaining, 0.0, delta)
		if hostile.disabled():
			if not in_training:
				_add_wreck(hostile)
			if adventure != null and hostile.encounter_slot >= 0:
				var away := ship_position.direction_to(hostile.position)
				if away.is_zero_approx():
					away = Vector2.UP
				var at := hostile.position + away.orthogonal() * 46.0
				var kind: int = Adventure.ENCOUNTERS[current_system][hostile.encounter_slot]
				adventure.record_defeat(current_system, hostile.encounter_slot, at, kind)
			notice = "%s выведен из строя." % hostile.call_sign
			if hostile != _cascade_enemy:
				hostile.queue_free()
			enemies.remove_at(index)
		elif not in_training:
			hostile.obstacles = obstacles
			hostile.advance(delta, ship_position, velocity)
			if hostile.shot_requested:
				_fire_hostile(hostile)
			if hostile is SwarmShip:
				_maybe_launch_drone(hostile)

	_advance_drones(delta)
	for index in range(enemies.size()):
		var hostile := enemies[index]
		_resolve_enemy_contact(hostile, delta)
		for other in range(index + 1, enemies.size()):
			var hit := Physics.contact(hostile.body, enemies[other].body)
			if hit != null:
				Physics.resolve(hostile.body, enemies[other].body, hit, 0.18)
	return true


func _maybe_launch_drone(carrier: SwarmShip) -> void:
	if carrier.launch_timer > 0.0 or not carrier.deck.weapons_are_manned():
		return
	var occupied: Array[int] = []
	for drone in drones:
		if drone.carrier_id == carrier.get_instance_id() and not drone.disabled():
			occupied.append(drone.orbit_slot)
	if occupied.size() >= SwarmShip.DRONE_LIMIT or not carrier.deck.power.spend(10.0):
		return
	var slot := 0
	while slot in occupied:
		slot += 1
	var phase := carrier.orbit_phase + slot * TAU / SwarmShip.DRONE_LIMIT
	var drone := Drone.new(carrier.position, phase)
	drone.carrier_id = carrier.get_instance_id()
	drone.orbit_slot = slot
	drone.body.velocity = carrier.velocity
	drone.damage_enabled = not in_arena or enemy_damage
	drones.append(drone)
	carrier.launch_timer = SwarmShip.LAUNCH_INTERVAL


func _advance_drones(delta: float) -> void:
	var carriers := {}
	for hostile in enemies:
		if hostile is SwarmShip:
			carriers[hostile.get_instance_id()] = true
	for index in range(drones.size() - 1, -1, -1):
		var drone := drones[index]
		if not carriers.has(drone.carrier_id):
			drone.shutdown_time = 3.0 if drone.shutdown_time < 0.0 else move_toward(drone.shutdown_time, 0.0, delta)
		if drone.disabled() or drone.shutdown_time == 0.0:
			var wreck := Wreck.new()
			wreck.position = drone.body.position
			wreck.velocity = drone.body.velocity * 0.45
			wreck.rotation = drone.body.heading + PI * 0.5
			wreck.spin = 0.7
			wreck.vanishes = true
			wreck.broken_hull = true
			wreck.size = 23.0
			wrecks.append(wreck)
			drones.remove_at(index)
			continue
		drone.advance(delta, ship_position, velocity, ship_position)
		if drone.shot_requested and _launch_shot(DRONE_WEAPON, drone.body, drone.body.model.muzzle, drone.body.heading, true):
			weapon_fired.emit(WeaponProfile.Kind.KINETIC)


func _add_wreck(hostile: EnemyShip) -> void:
	var wreck := Wreck.new()
	wreck.position = hostile.model.world_point(Vector2.ZERO, hostile.position, hostile.heading)
	wreck.velocity = hostile.velocity if hostile.deck.hull.integrity > 0.0 else hostile.velocity * 0.45
	wreck.rotation = hostile.heading + PI * 0.5
	wreck.spin = hostile.body.spin
	wreck.broken_hull = hostile.deck.hull.integrity <= 0.0
	wreck.texture = hostile.hull_wreck if wreck.broken_hull else hostile.crew_derelict
	wreck.size = hostile.sprite_size
	wreck.collider = Physics.Body.new()
	wreck.collider.model = hostile.body.model
	wreck.collider.position = hostile.body.position
	wreck.collider.velocity = wreck.velocity
	wreck.collider.heading = hostile.body.heading
	wreck.collider.spin = wreck.spin
	wrecks.append(wreck)


func _wreck_colliders() -> Array[Physics.Body]:
	var obstacles: Array[Physics.Body] = []
	for wreck in wrecks:
		if wreck.collider != null:
			obstacles.append(wreck.collider)
	return obstacles


func _advance_wrecks(delta: float) -> bool:
	var updated := not wrecks.is_empty()
	var previous_velocity := velocity
	for index in range(wrecks.size() - 1, -1, -1):
		var wreck := wrecks[index]
		wreck.age += delta
		if wreck.vanishes:
			wreck.position += wreck.velocity * delta
			if wreck.age >= 0.84:
				wrecks.remove_at(index)
			continue
		var obstacle := wreck.collider
		obstacle.position += obstacle.velocity * delta
		obstacle.heading = wrapf(obstacle.heading + obstacle.spin * delta, -PI, PI)
		if not in_arena:
			_resolve_wreck_contact(station_body, obstacle)
		_resolve_wreck_contact(body, obstacle)
		for hostile in enemies:
			_resolve_wreck_contact(hostile.body, obstacle)
		wreck.velocity = obstacle.velocity
		wreck.position = obstacle.model.world_point(Vector2.ZERO, obstacle.position, obstacle.heading)
		wreck.rotation = obstacle.heading + PI * 0.5
	if delta > 0.0:
		acceleration += (velocity - previous_velocity) / delta
	return updated


func _resolve_wreck_contact(ship: Physics.Body, obstacle: Physics.Body) -> void:
	var contact := Physics.contact(ship, obstacle)
	if contact != null:
		Physics.resolve(ship, obstacle, contact, 0.16)


func _fire_hostile(hostile: EnemyShip) -> void:
	var profile := hostile.weapon
	if profile == null or profile.projectile == null:
		return
	if not hostile.deck.power.can_spend(profile.energy_cost):
		return
	var spread := (1.0 - hostile.deck.hull.condition(hostile.deck.weapons_tile)) * profile.damaged_spread_degrees
	var mounts := profile.mounts
	if mounts.is_empty():
		var nose := hostile.body.model.muzzle
		nose.y = -profile.muzzle_offset
		mounts = PackedVector2Array([nose])
	for mount in mounts:
		var angle := hostile.heading + deg_to_rad(randf_range(-spread, spread))
		if not _launch_shot(profile, hostile.body, mount, angle, true):
			return
	hostile.deck.power.spend(profile.energy_cost)
	hostile.weapons_cooldown = profile.cooldown
	hostile.flash_remaining = FLASH_SECONDS
	weapon_fired.emit(profile.kind)


func _resolve_enemy_contact(hostile: EnemyShip, delta: float) -> void:
	var hit := Physics.contact(body, hostile.body)
	if hit == null:
		return
	var before := velocity
	Physics.resolve(body, hostile.body, hit, 0.72 if hostile.can_ram() else 0.22)
	acceleration += (velocity - before) / delta
	if hostile.can_ram() and hit.closing_speed >= 12.0:
		var side := (hit.point - ship_position).rotated(-heading - PI * 0.5)
		if body.shield.active():
			if deck.damage_enabled:
				body.shield.absorb(hostile.ram_damage)
		else:
			deck.apply_hit(hostile.ram_damage, 0.35, 0.0, side)
		hostile.on_ram(hit.point)
		notice = "Удар бура. Проверьте отсеки на палубе."


func start_adventure(continue_saved: bool) -> void:
	var saved := Adventure.new()
	saved.save_path = adventure_save_path
	var restored := continue_saved and saved.load_checkpoint(SYSTEMS.size())
	adventure = null
	reset()
	adventure = saved
	current_system = adventure.saved_system
	fuel = fuel_capacity()
	_spawn_ship()
	_enter_adventure_sector()
	_apply_adventure_upgrades()
	weapon = TEST_WEAPONS[adventure.slots[adventure.equipped]]
	_sync_freight()
	if restored:
		for index in adventure.crew_health.size():
			if adventure.crew_health[index] <= 0.0:
				deck._hurt_crew(deck.crew[index], 100.0)
	_moor_at_checkpoint()
	notice = "Загружено сохранение на станции." if restored else "Откройте верфь, чтобы взять первый контракт."
	if not continue_saved:
		_save_adventure()
	changed.emit()


func _moor_at_checkpoint() -> void:
	var approach := station_position().direction_to(ship_position)
	dock_angle = snappedf(approach.angle(), PI * 0.5)
	_dock_start_bearing = dock_angle
	_dock_start_radius = DOCK_RADIUS
	_dock_start_heading = dock_angle + PI
	body.fixed = true
	docked = true
	docking_time = 0.0
	_advance_station(0.0)


func _enter_adventure_sector() -> void:
	var opponents: Array = Adventure.ENCOUNTERS.get(current_system, [])
	for slot: int in adventure.remaining(current_system):
		var relative := Vector2(330.0 + 75.0 * slot, (155.0 if slot % 2 == 0 else -152.0))
		var at := ship_position + relative.rotated(heading)
		var from_station := at - station_position()
		if from_station.length() < DOCK_RANGE + 38.0:
			at = station_position() + from_station.normalized() * (DOCK_RANGE + 38.0)
		var hostile := _spawn_enemy(at, opponents[slot])
		hostile.encounter_slot = slot
		enemies.append(hostile)
	if current_system != Adventure.SCRAP or _wrecks_by_system.has(current_system):
		return
	for offset: Vector2 in [Vector2(-328, 76), Vector2(-315, -68), Vector2(-145, 248), Vector2(-54, -240)]:
		var debris := Wreck.new()
		var obstacle := Physics.Body.new()
		obstacle.model = RESCUE_MODEL
		obstacle.position = station_position() + offset
		obstacle.heading = offset.angle() + 0.78
		debris.collider = obstacle
		debris.position = obstacle.position
		debris.rotation = obstacle.heading + PI * 0.5
		debris.texture = DEBRIS
		debris.size = 72.0
		debris.age = 4.0
		wrecks.append(debris)


func _apply_ion_hazards(delta: float) -> void:
	if adventure == null or current_system != Adventure.ION:
		return
	if not docked and _inside_ion(ship_position):
		deck.power.spend(minf(deck.power.energy, 13.0 * delta))
	for hostile in enemies:
		if _inside_ion(hostile.position):
			hostile.deck.power.spend(minf(hostile.deck.power.energy, 13.0 * delta))


func _inside_ion(point: Vector2) -> bool:
	for cloud: Vector3 in ION_CLOUDS:
		var center := station_position() + Vector2(cloud.x, cloud.y)
		if point.distance_to(center) < cloud.z:
			return true
	return false


func _arrive_at_adventure_station() -> void:
	fuel = fuel_capacity()
	deck.service_at_station()
	body.shield.reset()
	var completed := adventure.settle(current_system)
	_sync_freight()
	notice = "Контракты сданы. Кредиты и детали зачислены." if not completed.is_empty() else "Станция пополнила топливо и обслужила корабль."
	_save_adventure()


func _save_adventure() -> void:
	var health: Array[float] = []
	for member in deck.crew:
		health.append(member.health)
	if adventure.save(current_system, health) != OK:
		notice += " Сохранение не записано."


func _sync_freight() -> void:
	deck.freight_count = 0
	if adventure != null:
		for index in adventure.accepted:
			if index not in adventure.settled and not Adventure.CONTRACTS[index].battle:
				deck.freight_count += 1


func salvage_contact() -> Adventure.SalvageCrate:
	if adventure == null or docked or not battle_result.is_empty():
		return null
	return adventure.nearest_container(current_system, ship_position)


func interact() -> void:
	var item := salvage_contact()
	if item == null:
		toggle_docking()
		return
	if velocity.length() > Adventure.PICKUP_SPEED:
		notice = "Сбавьте скорость до 75 ед/с для подбора."
	else:
		adventure.collect(current_system, item)
		notice = "Подобрано %d кр. и %d дет." % [item.credits, item.parts]
	changed.emit()


func accept_contract(index: int) -> bool:
	if adventure == null or not docked or not adventure.can_accept(index, current_system):
		return false
	adventure.accepted.append(index)
	_sync_freight()
	_save_adventure()
	changed.emit()
	return true


func refit(module: String) -> bool:
	if adventure == null or not docked or not adventure.buy_module(module):
		return false
	_apply_adventure_upgrades()
	_save_adventure()
	changed.emit()
	return true


func purchase_weapon(index: int) -> bool:
	if adventure == null or not docked or not adventure.buy_weapon(index):
		return false
	_save_adventure()
	changed.emit()
	return true


func mount_weapon(slot: int, profile: int) -> bool:
	if adventure == null or not docked or not adventure.equip_weapon(slot, profile):
		return false
	weapon = TEST_WEAPONS[adventure.slots[adventure.equipped]]
	_save_adventure()
	changed.emit()
	return true


func cycle_weapon() -> void:
	if adventure == null or not battle_result.is_empty():
		return
	stop_laser()
	_laser_spent = Input.is_action_pressed("flight_fire")
	adventure.equipped = 1 - adventure.equipped
	weapon = TEST_WEAPONS[adventure.slots[adventure.equipped]]
	if docked:
		_save_adventure()
	changed.emit()


func _apply_adventure_upgrades() -> void:
	body.turn_scale = PLAYER_TURN_SCALE * (1.0 + adventure.levels.thrusters * 0.2)
	deck.reactor_multiplier = 1.0 + adventure.levels.reactor * 0.2
	deck.upgrade_levels = adventure.levels.duplicate()
	body.shield.capacity = Physics.Shield.CAPACITY + adventure.levels.shield * 25.0
	body.shield.reset()


func _begin_defeat() -> void:
	battle_result = "Корабль потерян"
	defeat_hull = deck.hull.integrity <= 0.0
	defeat_elapsed = 0.0
	stop_laser()
	thrusting = false
	turn_input = 0.0
	acceleration = Vector2.ZERO
	body.active.clear()
	_discard_projectiles()
	notice = ""
	defeat_started.emit()


func _discard_projectiles() -> void:
	for projectile in projectiles:
		projectile.queue_free()
	projectiles.clear()


func _advance_defeat(delta: float) -> void:
	if defeat_elapsed >= DEFEAT_SECONDS:
		return
	defeat_elapsed = minf(DEFEAT_SECONDS, defeat_elapsed + delta)
	ship_position += velocity * delta * 0.42
	heading = wrapf(heading + angular_velocity * delta * 0.5, -PI, PI)
	changed.emit()


func _resolve_contact() -> void:
	var hit := Physics.contact(body, station_body)
	if hit != null:
		Physics.resolve(body, station_body, hit, 0.0)
