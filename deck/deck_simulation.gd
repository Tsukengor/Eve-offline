extends Node

signal changed
signal damage_alert(tile: Vector2i, breach: bool, message: String)
signal hit_received(side: Vector2)
signal security_alert(kind: String, subject: Variant, message: String)

enum Order { IDLE, MOVE, POST, REPAIR, PREPARE, SEAL, REPAIR_ROOM, ATTACK, FORCE_DOOR, SABOTAGE }

const Hull = preload("res://deck/hull.gd")
const ShipPower = preload("res://deck/ship_power.gd")
enum WorkPose { NONE, HELM, REPAIR, AIRLOCK, WEAPONS, LIFE_SUPPORT, REACTOR, SHIELD }

const ShipLayout = preload("res://deck/ship_layout.gd")
const RESCUE_LAYOUT := "res://deck/layouts/rescue.json"
const DRILL_LAYOUT := "res://deck/layouts/drill.json"
const FIGHTER_LAYOUT := "res://deck/layouts/fighter.json"
const ENGINE := Vector2i(12, 3)
const BRIDGE := Vector2i(2, 2)
const HELM_SEAT := BRIDGE + Vector2i.DOWN
const AIRLOCK := Vector2i(12, 9)
const WEAPONS := Vector2i(3, 9)
const WEAPONS_SEAT := WEAPONS + Vector2i.DOWN
const GUNNER_INDEX := 3
const LIFE_SUPPORT := Vector2i(8, 9)
const LIFE_SUPPORT_SEAT := LIFE_SUPPORT + Vector2i.DOWN
const REACTOR := Vector2i(8, 2)
const MODULE_CELLS := [ENGINE, BRIDGE, AIRLOCK, WEAPONS, LIFE_SUPPORT, REACTOR]
const HYPOXIA_DAMAGE := 12.0
const CARDINAL_STEPS := [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]
const INVALID_CELL := Vector2i(-1, -1)
const WALK_SPEED := 3.5
const SQUEEZE_SPEED := WALK_SPEED * 0.52
const SQUEEZE_OFFSET := 0.24
const WORKSTATION_PASS_OFFSET := 0.42
const DOOR_SECONDS := 0.30
const TRAFFIC_WEIGHT := 2.5

const CREW_LIMIT := 6
const SECURITY_SECONDS := 20.0
const DOOR_FORCE_SECONDS := 5.0
const HACK_RANGE := 575.0
const RESCUER := 2
const FIGHTER := 4
const HACKER := 5
const MEDIC := 6
const SHIELD_TECH := 7
const REACTOR_TECH := 8
const LEGACY_NAVIGATOR := 9
const LEGACY_SAPPER := 10
const WEAPONS_DATA := [
	{"melee": 8.0, "sprite": 0},
	{"melee": 12.0, "sprite": 1},
	{"melee": 15.0, "sprite": 2},
	{"melee": 5.0, "sprite": 3, "shot": 12.0, "range": 4},
	{"melee": 16.0, "sprite": 4, "shot": 17.0, "range": 5},
	{"melee": 7.0, "sprite": 5},
	{"melee": 7.0, "sprite": 4},
	{"melee": 12.0, "sprite": 0},
	{"melee": 11.0, "sprite": 1},
]
const ROOM_NAMES := {"B": "мостик", "E": "двигатели", "W": "вооружение",
	"L": "кислородная установка", "S": "шлюз", "C": "коридор", "R": "реактор",
	"G": "грузовой отсек", "H": "щит", "T": "телепорт"}
class Navigation extends AStar2D:
	var locked: Dictionary[Vector4i, float] = {}
	func _compute_cost(from_id: int, to_id: int) -> float:
		var edge := Hull.edge_between(Vector2i(get_point_position(from_id)), Vector2i(get_point_position(to_id)))
		return 1.0 + locked.get(edge, 0.0)

const SPECIALTIES := [
	{"role": "Пилот", "color": Color("#90c8ff")},
	{"role": "Инженер", "color": Color("#f7bf79")},
	{"role": "Спасатель", "color": Color("#78ead0")},
	{"role": "Наводчик", "color": Color("#d6a4fa")},
	{"role": "Боец", "color": Color("#ff947d")},
	{"role": "Хакер", "color": Color("#aeb1ff")},
	{"role": "Медик", "color": Color("#81dfae")},
	{"role": "Эксперт по щитам", "color": Color("#7ddcfa")},
	{"role": "Энергетик", "color": Color("#f1d083")},
]


class Door:
	var wants_open: bool
	var automatic := true
	var openness: float
	var lock_time := 0.0
	var lock_faction := 0
	var force_progress := 0.0
	var open_before_hack := false

	func _init(open: bool) -> void:
		wants_open = open
		openness = 1.0 if open else 0.0

	func permits_entry() -> bool:
		return wants_open and openness == 1.0


class CrewMember:
	var title: String
	var role: String
	var color: Color

	var specialty := 0
	var cell: Vector2i
	var position: Vector2
	var target := INVALID_CELL
	var route: Array[Vector2i] = []
	var landing := INVALID_CELL
	var squeeze := 0.0
	var squeeze_side := Vector2.ZERO
	var facing := Vector2i.DOWN
	var order := Order.IDLE
	var blocked := false
	var health := 100.0
	var gait := 0.0
	var repair_phase := 0.0
	var resume_post := INVALID_CELL
	var faction := 0
	var _combat_ref: WeakRef
	var combat_target: CrewMember:
		get: return _combat_ref.get_ref() if _combat_ref != null else null
		set(value): _combat_ref = weakref(value) if value != null else null
	var retreating := false
	var aggressive := false
	var immune := false
	var attack_cooldown := 0.0
	var attack_frame := 0.0
	var attack_direction := Vector2.RIGHT
	var attack_sprite := 0
	var down_time := 1.0
	var hack_pose_time := 0.0
	var force_edge := Vector4i.ZERO
	var sabotage_delay := 0.0
	var tactical_clock := 0.0

	func _init(member_name: String, member_role: String, tint: Color, start: Vector2i) -> void:
		title = member_name
		role = member_role
		color = tint
		cell = start
		position = Vector2(start)


class Transit:
	var paths: Dictionary[CrewMember, Array] = {}
	var yielding: Dictionary[CrewMember, Vector2] = {}
	var cells: Array[Vector2i] = []
	var squeezed := false
	var squeeze_offset := SQUEEZE_OFFSET
	var side_sign := 1.0
	var length := 1
	var distance := 0.0


class Passenger:
	var cell: Vector2i
	var seat: Vector2i
	var route: Array[Vector2i] = []
	var crossing := 0.0
	var position: Vector2
	var boarding_delay := 0.0
	var gait := 0.0


var plan: Array = []
@export_file("*.json") var layout_path := RESCUE_LAYOUT
var layout_name := ""
var walls: Array = []
var hatches: Array = []
var _spawns: Array = []
var engine_tile := ENGINE
var bridge_tile := BRIDGE
var airlock_tile := AIRLOCK
var weapons_tile := WEAPONS
var life_support_tile := LIFE_SUPPORT
var reactor_tile := REACTOR
var shield_tile := INVALID_CELL
var teleport_tile := INVALID_CELL
var power := ShipPower.new()
var simulation_speed := 1.0
var module_cells: Array = MODULE_CELLS
var crew: Array[CrewMember] = []
var boarders: Array[CrewMember] = []
var passengers: Array[Passenger] = []
var freight_count := 0
var cargo_seats: Array[Vector2i] = []
var doors: Dictionary[Vector4i, Door] = {}
var engine_health := 0.0
var reactor_multiplier := 1.0
var upgrade_levels := {}
var airlock_progress := 0.0
var notice := ""
var training_hint := ""
var _door_edges: Array = []
var _grid := Navigation.new()
var _bounds := Rect2i()
var _transits: Array[Transit] = []
var hull := Hull.new()
var floor_bounds := Rect2()
var damage_enabled := true
var auto_crew := false
var auto_airlock := true
var _crew_check := 0.0
var alerts: Dictionary[int, float] = {}
var emp_timers: Dictionary[int, float] = {}
var emp_recovery_time := 0.0
var _emp_recovery_loss := 0.0
var computer_outage := 0.0
var firewall := 0.0
var hack_cooldown := 0.0
var teleport_flash := 0.0
var room_hacks: Dictionary[int, float] = {}
var _rng := RandomNumberGenerator.new()


static func edge_between(a: Vector2i, b: Vector2i) -> Vector4i:
	return Hull.edge_between(a, b)


func _ready() -> void:
	var error := load_layout(layout_path, false)
	if not error.is_empty():
		push_error(error)
		if layout_path != RESCUE_LAYOUT:
			load_layout(RESCUE_LAYOUT, false)


## Loads a scenario deck atomically. Call before starting the scenario.
func load_layout(path: String, for_flight := true) -> String:
	var layout := ShipLayout.read(path)
	if layout.has("error"):
		return layout.error
	layout_path = path
	layout_name = layout.name
	plan = layout.plan
	walls = layout.walls
	hatches = layout.hatches
	_spawns = layout.spawns
	_door_edges = layout.doors
	bridge_tile = layout.modules.bridge
	engine_tile = layout.modules.engine
	airlock_tile = layout.modules.airlock
	weapons_tile = layout.modules.get("weapons", INVALID_CELL)
	life_support_tile = layout.modules.life_support
	reactor_tile = layout.modules.reactor
	shield_tile = layout.modules.get("shield", INVALID_CELL)
	teleport_tile = layout.modules.get("teleport", INVALID_CELL)
	module_cells = layout.modules.values()
	_bounds = Rect2i(0, 0, plan[0].length(), plan.size())
	doors.clear()
	for edge: Vector4i in _door_edges:
		doors[edge] = Door.new(false)
	for edge: Vector4i in hatches:
		doors[edge] = Door.new(false)
	_build_navigation()
	reset(for_flight)
	return ""


func _id(tile: Vector2i) -> int:
	return tile.y * _bounds.size.x + tile.x


func _build_navigation() -> Array[Vector2i]:
	_grid.clear()
	var walkable: Array[Vector2i] = []
	for y in range(_bounds.size.y):
		for x in range(_bounds.size.x):
			var tile := Vector2i(x, y)
			if tile_kind(tile) != "." and tile not in module_cells:
				walkable.append(tile)
				_grid.add_point(_id(tile), Vector2(tile))
	for tile in walkable:
		for step in [Vector2i.RIGHT, Vector2i.DOWN]:
			var other: Vector2i = tile + step
			if other in walkable and joined(tile, other):
				_grid.connect_points(_id(tile), _id(other))
	var unreachable: Array[Vector2i] = []
	if walkable.is_empty():
		unreachable.assign(module_cells)
		return unreachable
	var start := _id(walkable.front())
	for tile in walkable:
		if _grid.get_id_path(start, _id(tile)).is_empty():
			unreachable.append(tile)
	for module: Vector2i in module_cells:
		var accessible := false
		for step: Vector2i in CARDINAL_STEPS:
			if module + step in walkable and module + step not in unreachable and tile_kind(module + step) == tile_kind(module):
				accessible = true
				break
		if not accessible:
			unreachable.append(module)
	return unreachable


func joined(a: Vector2i, b: Vector2i) -> bool:
	var kind := tile_kind(a)
	return a.distance_squared_to(b) == 1 and kind != "." and tile_kind(b) != "." \
		and (kind == tile_kind(b) or doors.has(edge_between(a, b))) and edge_between(a, b) not in walls


func reset(for_flight := false) -> void:
	crew.assign([
		CrewMember.new("Мира", "Пилот", Color("#90c8ff"), _spawns[0]),
		CrewMember.new("Лев", "Инженер", Color("#f7bf79"), _spawns[1]),
		CrewMember.new("Ника", "Спасатель", Color("#78ead0"), _spawns[2]),
		CrewMember.new("Ива", "Наводчик", Color("#d6a4fa"), _spawns[3]),
	])
	for index in range(crew.size()):
		crew[index].specialty = index
		assert(_grid.has_point(_id(crew[index].cell)) and (index == GUNNER_INDEX and weapons_tile == INVALID_CELL or tile_kind(crew[index].cell) == ["B", "E", "S", "W"][index]),
			"Crew spawn must be on the floor of the assigned compartment")
	crew[0].target = bridge_tile
	crew[0].order = Order.POST
	if weapons_tile != INVALID_CELL:
		crew[GUNNER_INDEX].target = weapons_tile
		crew[GUNNER_INDEX].order = Order.POST
	boarders.clear()
	_reset_security()
	_transits.clear()
	passengers.clear()
	freight_count = 0
	upgrade_levels.clear()
	_find_cargo_seats()
	for edge in doors:
		_update_edge(edge, true)
		doors[edge] = Door.new(false)
		doors[edge].automatic = edge not in hatches
	alerts.clear()
	emp_timers.clear()
	emp_recovery_time = 0.0
	_emp_recovery_loss = 0.0
	power.energy = ShipPower.CAPACITY
	hull.configure(plan, _door_edges, walls, hatches)
	var first: Vector2i = hull.room_at.keys()[0]
	floor_bounds = Rect2(Vector2(first), Vector2.ONE)
	for tile: Vector2i in hull.room_at:
		floor_bounds = floor_bounds.expand(Vector2(tile)).expand(Vector2(tile + Vector2i.ONE))
	engine_health = 1.0 if for_flight else 0.0
	airlock_progress = 0.0
	notice = "" if for_flight else "Двигатель отключён. Назначьте ремонт."
	changed.emit()


func available_berth() -> bool:
	return crew.size() < CREW_LIMIT or crew.any(func(member: CrewMember) -> bool: return member.health <= 0.0)


func hire_member(title: String, specialty: int) -> bool:
	if not available_berth() or specialty < 0 or specialty >= SPECIALTIES.size():
		return false
	var spawn := _free_berth()
	if spawn == INVALID_CELL:
		return false
	var profile: Dictionary = SPECIALTIES[specialty]
	var recruit := CrewMember.new(title, profile.role, profile.color, spawn)
	recruit.specialty = specialty
	for index in crew.size():
		if crew[index].health <= 0.0:
			crew[index] = recruit
			changed.emit()
			return true
	crew.append(recruit)
	changed.emit()
	return true


func _free_berth() -> Vector2i:
	var nearest := INVALID_CELL
	var distance := INF
	for tile: Vector2i in hull.room_at:
		if tile in module_cells or _occupant(tile) != null or _reserved(tile):
			continue
		var separation := float(tile.distance_squared_to(airlock_tile))
		if separation < distance:
			distance = separation
			nearest = tile
	return nearest


func crew_checkpoint() -> Array:
	var roster: Array = []
	for member in crew:
		roster.append({"title": member.title, "specialty": member.specialty, "cell": member.cell, "position": member.position,
			"health": member.health, "target": member.target, "order": member.order})
	return roster


func restore_roster(roster: Array) -> void:
	if roster.size() < 4:
		return
	var restored: Array[CrewMember] = []
	var occupied := {}
	for data in roster.slice(0, CREW_LIMIT):
		if not data is Dictionary or not data.get("cell") is Vector2i or not data.get("title") is String:
			return
		var specialty: Variant = data.get("specialty", 0)
		if specialty == LEGACY_NAVIGATOR:
			specialty = 0
		elif specialty == LEGACY_SAPPER:
			specialty = RESCUER
		if not specialty is int or specialty < 0 or specialty >= SPECIALTIES.size():
			return
		var health := clampf(float(data.get("health", 100.0)), 0.0, 100.0)
		var tile: Vector2i = data.cell
		if health > 0.0 and (not hull.room_at.has(tile) or tile in module_cells or occupied.has(tile)):
			return
		var profile: Dictionary = SPECIALTIES[specialty]
		var member := CrewMember.new(data.title.substr(0, 22), profile.role, profile.color, tile)
		member.specialty = specialty
		member.health = health
		if health <= 0.0 and data.get("position") is Vector2 and data.position.is_finite():
			member.position = data.position
		elif health > 0.0:
			occupied[tile] = true
			if data.get("target") is Vector2i and hull.room_at.has(data.target) and data.get("order") in [Order.IDLE, Order.MOVE, Order.POST, Order.REPAIR, Order.PREPARE, Order.SEAL, Order.REPAIR_ROOM]:
				member.target = data.target
				member.order = data.order
		restored.append(member)
	crew = restored
	for member in crew:
		if member.target != INVALID_CELL:
			_replan(member)
	changed.emit()


func service_at_station() -> void:
	_reset_security()
	hull.integrity = Hull.HULL_MAX
	hull.breaches.clear()
	for room in hull.rooms:
		room.integrity = Hull.ROOM_MAX
		room.oxygen = 1.0
	engine_health = 1.0
	power.energy = ShipPower.CAPACITY
	emp_timers.clear()
	emp_recovery_time = 0.0
	_emp_recovery_loss = 0.0
	for member in crew:
		if member.health > 0.0:
			member.health = 100.0
		if member.order in [Order.SEAL, Order.REPAIR, Order.REPAIR_ROOM]:
			member.order = Order.IDLE
			member.target = INVALID_CELL
			member.route.clear()
			member.blocked = false
	changed.emit()


func damage_engine(health: float) -> void:
	if health >= engine_health:
		return
	engine_health = maxf(health, 0.0)
	notice = "Двигатель повреждён."
	_report_damage(engine_tile, false, notice)
	changed.emit()


func helm_is_manned() -> bool:
	return operator_at(WorkPose.HELM) != null


func weapons_are_manned() -> bool:
	return operator_at(WorkPose.WEAPONS) != null


func operator_at(pose: WorkPose) -> CrewMember:
	for member in crew:
		if workstation_pose(member) == pose and module_online(member.target):
			return member
	return null


func pilot_efficiency() -> float:
	var pilot := operator_at(WorkPose.HELM)
	if pilot == null:
		return 0.0
	var skill := 1.0 if pilot.role == "Пилот" else 0.76
	return skill * lerpf(0.35, 1.0, hull.condition(bridge_tile)) * (0.32 if hacked(bridge_tile) else 1.0)


func module_online(tile: Vector2i) -> bool:
	return tile != INVALID_CELL and hull.condition(tile) > 0.0 and emp_time(tile) == 0.0 and not (tile in [weapons_tile, airlock_tile, shield_tile, teleport_tile] and hacked(tile))


func emp_time(tile: Vector2i) -> float:
	return emp_timers.get(hull.room_at.get(tile, -1), 0.0)


func apply_emp(drain: float, duration: float, count: int, side: Vector2, recovery_loss := 0.0) -> void:
	if not damage_enabled or disabled():
		return
	power.spend(minf(power.energy, drain))
	hit_received.emit(side)
	if recovery_loss > 0.0:
		emp_recovery_time = 10.0
		_emp_recovery_loss = maxf(_emp_recovery_loss, recovery_loss)
	var modules := module_cells.duplicate()
	var area := Vector2(_bounds.size)
	var normal := side.normalized()
	modules.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) / area).dot(normal) > (Vector2(b) / area).dot(normal))
	var affected := 0
	for tile: Vector2i in modules:
		var room: int = hull.room_at[tile]
		if affected >= count:
			break
		if hull.condition(tile) <= 0.0 or duration <= 0.0:
			continue
		emp_timers[room] = maxf(emp_time(tile), duration)
		affected += 1
	if affected > 0:
		notice = "ЭМИ. Отключено систем: %d." % affected
		damage_alert.emit(modules.front(), false, notice)
	changed.emit()


func crew_alive() -> int:
	var count := 0
	for member in crew:
		if member.health > 0.0:
			count += 1
	return count


func disabled() -> bool:
	return hull.integrity <= 0.0 or crew_alive() == 0


func apply_hit(damage: float, breach_chance: float, crew_damage := 0.0,
		impact_side := Vector2.ZERO, tile := INVALID_CELL, announce := true) -> Vector2i:
	if not damage_enabled or hull.room_at.is_empty() or damage <= 0.0:
		return INVALID_CELL
	if tile == INVALID_CELL:
		tile = _impact_cell(impact_side)
	if not hull.room_at.has(tile):
		return INVALID_CELL
	var occupied: Array[Vector2i] = []
	occupied.assign(module_cells)
	for member in occupants():
		if member.health > 0.0:
			occupied.append(member.cell)
			occupied.append(member.landing)
	for transit in _transits:
		occupied.append_array(transit.cells)
	for passenger in passengers:
		occupied.append(Vector2i(passenger.position.round()))
	var leaks_before := hull.breaches.size()
	hull.strike(tile, damage, clampf(breach_chance, 0.0, 1.0), occupied, _rng)
	var lost := false
	if crew_damage > 0.0:
		var room: int = hull.room_at[tile]
		for member in occupants():
			if hull.room_at.get(Vector2i(member.position.round()), -1) == room:
				if not member.immune:
					lost = _hurt_crew(member, crew_damage) or lost
		if lost:
			_replan_waiting_orders()
	hit_received.emit(impact_side)
	var breached := hull.breaches.size() > leaks_before
	if not announce and not breached:
		changed.emit()
		return tile
	var room_name: String = ROOM_NAMES[tile_kind(tile)]
	notice = ("%s — %s" % ["Пробоина" if breached else "Повреждение", room_name.capitalize()])
	_report_damage(tile, breached, notice)
	changed.emit()
	return tile


func _report_damage(tile: Vector2i, breach: bool, message: String) -> void:
	alerts[hull.room_at[tile]] = 2.0
	damage_alert.emit(tile, breach, message)


func _impact_cell(side: Vector2) -> Vector2i:
	var candidates := hull.room_at.keys()
	if side.is_zero_approx():
		return candidates[_rng.randi_range(0, candidates.size() - 1)]
	var area := Vector2(_bounds.size)
	var normal := side.normalized()
	var weights := PackedFloat32Array()
	var total := 0.0
	for cell: Vector2i in candidates:
		var relative := (Vector2(cell) + Vector2(0.5, 0.5)) / area * 2.0 - Vector2.ONE
		total += exp(relative.dot(normal) * 2.6)
		weights.append(total)
	var pick := _rng.randf_range(0.0, total)
	for index in range(weights.size()):
		if pick <= weights[index]:
			return candidates[index]
	return candidates.back()


func tile_kind(tile: Vector2i) -> String:
	if not _bounds.has_point(tile):
		return "."
	return plan[tile.y][tile.x]


func assign_order(index: int, target: Vector2i, move_only := false, automatic := false) -> void:
	if tile_kind(target) == "." or index < 0 or index >= crew.size():
		return
	var member := crew[index]
	if member.health <= 0.0:
		return
	if not automatic:
		member.resume_post = INVALID_CELL
	member.combat_target = null
	member.target = target
	if move_only:
		member.order = Order.MOVE
	elif hull.breaches.has(target):
		member.order = Order.SEAL
	elif hull.condition(target) < 1.0:
		member.order = Order.REPAIR_ROOM
	else:
		if target == engine_tile:
			member.order = Order.REPAIR if engine_health < 1.0 else Order.MOVE
		elif target == airlock_tile:
			member.order = Order.PREPARE if airlock_progress < 1.0 else Order.POST
		elif target in [bridge_tile, weapons_tile, life_support_tile, reactor_tile, shield_tile]:
			member.order = Order.POST
		else:
			member.order = Order.MOVE
	_replan(member)
	if member.target == member.cell and member.landing == INVALID_CELL:
		for other in crew:
			if other != member and not other.route.is_empty() and other.route.back() == member.cell:
				_replan(other)
	_replan_waiting_orders()
	if automatic:
		return
	notice = "Цель недоступна или занята." if member.blocked else ""
	if member.blocked and member.target == bridge_tile:
		notice = "Кресло пилота занято."
	elif member.blocked and member.target == weapons_tile:
		notice = "Пост вооружения занят."
	changed.emit()


func toggle_door(edge: Vector4i) -> void:
	if not doors.has(edge) or doors[edge].lock_time > 0.0:
		return
	var door := doors[edge]
	if edge in hatches:
		_set_manual_door(edge, not door.wants_open)
	elif door.automatic:
		_set_manual_door(edge, true)
	elif door.wants_open:
		_set_manual_door(edge, false)
	else:
		set_automatic(edge)


func set_automatic(edge: Vector4i) -> void:
	if not doors.has(edge) or edge in hatches or doors[edge].lock_time > 0.0:
		return
	doors[edge].automatic = true
	_update_edge(edge, true)
	_replan_waiting_orders()
	notice = "Дверь переведена в автоматический режим."
	changed.emit()


func _update_edge(edge: Vector4i, connected: bool) -> void:
	if edge in hatches:
		return
	var a := _id(Vector2i(edge.x, edge.y))
	var b := _id(Vector2i(edge.z, edge.w))
	if connected and not _grid.are_points_connected(a, b):
		_grid.connect_points(a, b)
	elif not connected and _grid.are_points_connected(a, b):
		_grid.disconnect_points(a, b)


func _set_manual_door(edge: Vector4i, open: bool) -> void:
	var door := doors[edge]
	door.automatic = false
	door.wants_open = open
	_update_edge(edge, open)
	if open:
		_replan_waiting_orders()
		notice = "Дверь открывается."
	else:
		for member in occupants():
			var start := member.landing if member.landing != INVALID_CELL else member.cell
			if _crosses_edge(start, member.route, edge):
				_replan(member)
		notice = "Дверь закроется после освобождения прохода." if _edge_reserved(edge) else ("Дверь закрывается." if edge in hatches else "Дверь запирается. ЛКМ возвращает автоматику.")
	changed.emit()


func _door_allows_step(from: Vector2i, to: Vector2i, faction := 0) -> bool:
	var edge := edge_between(from, to)
	if not doors.has(edge):
		return true
	var door := doors[edge]
	return door.permits_entry() and (door.lock_time == 0.0 or door.lock_faction == faction)


func _crosses_edge(start: Vector2i, route: Array, edge: Vector4i) -> bool:
	for tile: Vector2i in route:
		if edge_between(start, tile) == edge:
			return true
		start = tile
	return false


func _edge_reserved(edge: Vector4i) -> bool:
	for transit in _transits:
		for path: Array in transit.paths.values():
			if _crosses_edge(path[0], path.slice(1), edge):
				return true
	for passenger in passengers:
		if passenger.crossing > 0.0 and not passenger.route.is_empty() and edge_between(passenger.cell, passenger.route[0]) == edge:
			return true
	return false


func _door_needed(edge: Vector4i) -> bool:
	if _edge_reserved(edge):
		return true
	var center := (Vector2(edge.x, edge.y) + Vector2(edge.z, edge.w)) * 0.5
	for member in occupants():
		if member.health > 0.0 and (doors[edge].lock_time == 0.0 or member.faction == doors[edge].lock_faction) and member.position.distance_squared_to(center) <= 9.1:
			var start := member.landing if member.landing != INVALID_CELL else member.cell
			if _crosses_edge(start, member.route, edge):
				return true
		if member.health > 0.0 and (doors[edge].lock_time == 0.0 or member.faction == doors[edge].lock_faction) and member.cell.distance_squared_to(Vector2i(center.round())) <= 1:
			var opponent := member.combat_target
			if member.order in [Order.ATTACK, Order.IDLE, Order.SABOTAGE] and opponent != null and opponent.health > 0.0 and edge_between(member.cell, opponent.cell) == edge:
				return true
	for passenger in passengers:
		if doors[edge].lock_time == 0.0 and passenger.boarding_delay <= 0.0 and not passenger.route.is_empty() and edge_between(passenger.cell, passenger.route[0]) == edge:
			return true
	return false


func _replan_waiting_orders() -> void:
	for member in occupants():
		if member.health > 0.0 and member.target != INVALID_CELL and member.blocked:
			_replan(member)


func _replan(member: CrewMember) -> void:
	# An admitted transit owns its entire crossing. Only change the route after it.
	var start := member.landing if member.landing != INVALID_CELL else member.cell
	var weighted: Array[Vector2i] = []
	for other in occupants():
		if other != member and other.health > 0.0 and _grid.has_point(_id(other.cell)):
			weighted.append(other.cell)
			if other.landing != INVALID_CELL:
				weighted.append(other.landing)
	for tile in weighted:
		_grid.set_point_weight_scale(_id(tile), TRAFFIC_WEIGHT)
	_prepare_navigation(member)
	var path := _path_to_order(member, start)
	_grid.locked.clear()
	for tile in weighted:
		_grid.set_point_weight_scale(_id(tile), 1.0)

	member.blocked = path.is_empty()
	member.route.assign(path.slice(1))


func _prepare_navigation(member: CrewMember) -> void:
	_grid.locked.clear()
	for edge in doors:
		if doors[edge].lock_time > 0.0 and doors[edge].lock_faction != member.faction:
			_grid.locked[edge] = WALK_SPEED * (DOOR_FORCE_SECONDS - doors[edge].force_progress) / (1.4 if member.specialty == RESCUER else 1.0)


func _route_cost(path: Array[Vector2i]) -> float:
	var cost := 0.0
	for index in range(1, path.size()):
		var step := _id(path[index])
		cost += _grid._compute_cost(_id(path[index - 1]), step) * _grid.get_point_weight_scale(step)
	return cost


func _path_to_order(member: CrewMember, start: Vector2i) -> Array[Vector2i]:
	if (member.order == Order.POST and member.target in [bridge_tile, weapons_tile, life_support_tile, reactor_tile, shield_tile]) \
		or (member.order == Order.REPAIR_ROOM and member.target in [reactor_tile, shield_tile]):
		var seat := member.target + Vector2i.DOWN
		if not _goal_available(seat, member, true):
			return []
		return _path(start, seat)
	if member.target not in module_cells and member.order not in [Order.SEAL, Order.REPAIR_ROOM, Order.SABOTAGE]:
		if not _goal_available(member.target, member, true, member.retreating):
			return []
		return _path(start, member.target)
	var best_path: Array[Vector2i] = []
	var best_cost := INF
	for direction in CARDINAL_STEPS:
		var tile: Vector2i = member.target + direction
		if edge_between(member.target, tile) in walls or tile_kind(member.target) != tile_kind(tile) or not _goal_available(tile, member, false):
			continue
		var path := _path(start, tile)
		if path.is_empty():
			continue
		var cost := _route_cost(path)
		if cost < best_cost:
			best_path = path
			best_cost = cost
	return best_path


func _path(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not _bounds.has_point(start) or not _grid.has_point(_id(start)):
		return path
	if not _bounds.has_point(end) or not _grid.has_point(_id(end)):
		return path
	for point in _grid.get_point_path(_id(start), _id(end)):
		path.append(Vector2i(point))
	return path


func _find_cargo_seats() -> void:
	cargo_seats.clear()
	for x in range(_bounds.size.x):
		for y in range(_bounds.size.y):
			var tile := Vector2i(x, y)
			if tile_kind(tile) == "G":
				cargo_seats.append(tile)
	# Keep the middle of the bay available as an aisle.
	cargo_seats.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var left_distance := absi(a.x - airlock_tile.x)
		var right_distance := absi(b.x - airlock_tile.x)
		if left_distance != right_distance:
			return left_distance > right_distance
		return a.y < b.y if a.y != b.y else a.x < b.x)
	cargo_seats.resize(mini(8, cargo_seats.size()))


func board_passengers(count: int) -> void:
	var staging: Array[Vector2i] = []
	for y in range(_bounds.size.y):
		for x in range(_bounds.size.x):
			var tile := Vector2i(x, y)
			if tile_kind(tile) == "S" and tile != airlock_tile and _occupant(tile) == null:
				staging.append(tile)
	if staging.is_empty():
		staging.append(_spawns[2])
	passengers.clear()
	for index in range(count):
		var passenger := Passenger.new()
		passenger.cell = staging[index % staging.size()]
		passenger.position = Vector2(passenger.cell)
		passenger.seat = cargo_seats[index] if index < cargo_seats.size() else passenger.cell
		passenger.boarding_delay = 0.18 * index + 0.25
		passengers.append(passenger)
	changed.emit()


func unload_passengers() -> void:
	passengers.clear()
	changed.emit()


func _advance_passengers(delta: float) -> bool:
	var updated := false
	for index in range(passengers.size()):
		var passenger := passengers[index]
		if passenger.boarding_delay > 0.0:
			passenger.boarding_delay = maxf(0.0, passenger.boarding_delay - delta)
			if passenger.boarding_delay == 0.0:
				for earlier in range(index):
					if passengers[earlier].position.distance_squared_to(passenger.position) < 0.35:
						passenger.boarding_delay = 0.08
						break
			updated = true
			continue
		if passenger.cell == passenger.seat:
			continue
		if passenger.route.is_empty():
			passenger.route = _path(passenger.cell, passenger.seat).slice(1)
		if passenger.route.is_empty():
			continue
		var destination := passenger.route[0]
		if passenger.crossing == 0.0 and not _door_allows_step(passenger.cell, destination):
			var door := doors[edge_between(passenger.cell, destination)]
			if not door.automatic and not door.wants_open:
				passenger.route.clear()
			continue
		var previous := passenger.position
		passenger.crossing = minf(1.0, passenger.crossing + delta * 2.4)
		passenger.position = Vector2(passenger.cell).lerp(Vector2(destination), passenger.crossing)
		passenger.gait += previous.distance_to(passenger.position)
		if passenger.crossing == 1.0:
			passenger.cell = destination
			passenger.route.pop_front()
			passenger.crossing = 0.0
		updated = true
	return updated


func _goal_available(tile: Vector2i, member: CrewMember, allow_departure: bool, share_with_opponent := false) -> bool:
	if tile == member.cell and member.landing == INVALID_CELL:
		return true
	for other in occupants():
		if other == member or other.health <= 0.0 or (share_with_opponent and other.faction != member.faction):
			continue
		if not other.route.is_empty() and other.route.back() == tile:
			return false
		if other.route.is_empty() and other.landing == tile:
			return false
		if other.cell == tile:
			var leaving := other.landing != INVALID_CELL or (
				other.target != INVALID_CELL and other.target != tile and other.target not in module_cells)
			if not allow_departure or not leaving:
				return false
	return true


func _occupant(tile: Vector2i, faction := -1) -> CrewMember:
	for member in occupants():
		if member.health > 0.0 and member.cell == tile and (faction == -1 or member.faction == faction):
			return member
	return null


func opponent_in_cell(member: CrewMember, tile: Vector2i) -> CrewMember:
	return _occupant(tile, 1 - member.faction)


func _reserved(tile: Vector2i) -> bool:
	for transit in _transits:
		if tile in transit.cells:
			return true
	return false


func _waiting_to_walk(member: CrewMember) -> bool:
	return member.health > 0.0 and not member.route.is_empty() and not _reserved(member.cell)


func _start_transits() -> bool:
	var started := false
	# Let people who can leave normally clear the way first.
	for member in occupants():
		if not _waiting_to_walk(member):
			continue
		var next := member.route[0]
		if not _door_allows_step(member.cell, next, member.faction) or _reserved(next) or _occupant(next, member.faction) != null:
			continue
		var enemy := opponent_in_cell(member, next)
		if enemy != null and (member.route.size() != 1 or not (enemy == member.combat_target or member.retreating)):
			continue
		var transit := Transit.new()
		_add_path(transit, member, 1)
		_transits.append(transit)
		started = true
	for member in occupants():
		if _waiting_to_walk(member) and _start_squeeze(member):
			started = true
	return started


func _add_path(transit: Transit, member: CrewMember, steps: int) -> void:
	var path: Array[Vector2i] = [member.cell]
	for index in range(steps):
		path.append(member.route.pop_front())
	member.landing = path.back()
	transit.paths[member] = path
	for tile in path:
		if tile not in transit.cells:
			transit.cells.append(tile)


func _start_squeeze(member: CrewMember) -> bool:
	var transit := Transit.new()
	transit.squeezed = true
	var previous := member.cell
	for index in range(member.route.size()):
		var tile := member.route[index]
		if not _door_allows_step(previous, tile, member.faction) or _reserved(tile):
			return false
		var other := _occupant(tile)
		if opponent_in_cell(member, tile) != null:
			return false
		if other == null:
			if index == 0:
				return false
			transit.length = index + 1
			_add_path(transit, member, transit.length)
			_transits.append(transit)
			return true
		if other.faction != member.faction:
			return false
		if index == 0 and not other.route.is_empty() and other.route[0] == member.cell:
			_add_path(transit, member, 1)
			_add_path(transit, other, 1)
			_transits.append(transit)
			return true
		var side := Vector2(tile - previous).orthogonal()
		if index + 1 < member.route.size():
			side += Vector2(member.route[index + 1] - tile).orthogonal()
		if workstation_pose(other) == WorkPose.NONE:
			transit.yielding[other] = -side.normalized()
		elif transit.squeeze_offset == SQUEEZE_OFFSET:
			# The operator stays still. Give the passer more room away from the equipment.
			transit.squeeze_offset = WORKSTATION_PASS_OFFSET
			if side.dot(Vector2(other.target - other.cell)) > 0.0:
				transit.side_sign = -1.0
		previous = tile
	return false


func _advance_transits(delta: float) -> bool:
	var arrived := false
	for index in range(_transits.size() - 1, -1, -1):
		var transit := _transits[index]
		var speed := SQUEEZE_SPEED if transit.squeezed else WALK_SPEED
		transit.distance = minf(float(transit.length), transit.distance + delta * speed)
		for member in transit.paths:
			var previous := member.position
			var path: Array = transit.paths[member]
			var edge := mini(floori(transit.distance), transit.length - 1)
			var direction := Vector2(path[edge + 1] - path[edge])
			member.position = Vector2(path[edge]) + direction * (transit.distance - edge)
			member.facing = Vector2i(direction)
			if transit.squeezed:
				member.squeeze = sin(PI * transit.distance / transit.length)
				# Blend the normals at a turn so the sidestep stays continuous.
				var side := direction.orthogonal()
				var next_side := side
				if edge + 2 < path.size():
					var outgoing := Vector2(path[edge + 2] - path[edge + 1]).orthogonal()
					next_side = side.lerp(outgoing, 0.5)
				if edge > 0:
					var previous_side := Vector2(path[edge] - path[edge - 1]).orthogonal()
					side = previous_side.lerp(side, 0.5)
				member.squeeze_side = side.lerp(next_side, transit.distance - edge).normalized()
				member.squeeze_side *= transit.side_sign
				member.position += member.squeeze_side * (transit.squeeze_offset * member.squeeze)
			member.gait += previous.distance_to(member.position) * 1.4
		for member in transit.yielding:
			if workstation_pose(member) != WorkPose.NONE:
				member.position = Vector2(member.cell)
				member.squeeze = 0.0
				continue
			var mover: CrewMember = transit.paths.keys()[0]
			var path: Array = transit.paths[mover]
			var proximity := clampf(1.0 - absf(transit.distance - path.find(member.cell)), 0.0, 1.0)
			member.squeeze = smoothstep(0.0, 1.0, proximity)
			member.squeeze_side = transit.yielding[member] * transit.side_sign
			var previous := member.position
			member.position = Vector2(member.cell) + member.squeeze_side * (SQUEEZE_OFFSET * member.squeeze)
			member.gait += previous.distance_to(member.position) * 1.4
		if transit.distance >= transit.length:
			# Both sides of a swap commit on the same tick.
			for member in transit.paths:
				member.cell = member.landing
				member.landing = INVALID_CELL
				member.position = Vector2(member.cell)
				member.squeeze = 0.0
			for member in transit.yielding:
				member.position = Vector2(member.cell)
				member.squeeze = 0.0
			_transits.remove_at(index)
			arrived = true
	return arrived


func _advance_doors(delta: float) -> bool:
	var updated := false
	var opened := false
	for edge in doors:
		var door := doors[edge]
		if door.automatic or door.lock_time > 0.0:
			door.wants_open = _door_needed(edge)
		if not door.wants_open and _edge_reserved(edge):
			continue
		var goal := 1.0 if door.wants_open else 0.0
		if door.openness == goal:
			continue
		door.openness = move_toward(door.openness, goal, delta / DOOR_SECONDS)
		updated = true
		if door.openness == goal and not door.automatic:
			notice = "Наружная дверь открыта. Утечка кислорода." if edge in hatches and door.wants_open else ("Дверь открыта." if door.wants_open else ("Дверь закрыта." if edge in hatches else "Дверь заперта. ЛКМ возвращает автоматику."))
			if door.wants_open:
				opened = true
	if opened:
		_replan_waiting_orders()
	return updated


func _physics_process(delta: float) -> void:
	delta *= simulation_speed
	var falling := false
	for member in occupants():
		member.hack_pose_time = move_toward(member.hack_pose_time, 0.0, delta)
		if member.health <= 0.0 and member.down_time < 1.0:
			member.down_time = minf(1.0, member.down_time + delta)
			falling = true
	var updated := falling or not _transits.is_empty() or not alerts.is_empty() or not emp_timers.is_empty() or emp_recovery_time > 0.0
	for room in emp_timers.keys():
		emp_timers[room] -= delta
		if emp_timers[room] <= 0.0:
			emp_timers.erase(room)
	for room in alerts.keys():
		alerts[room] -= delta
		if alerts[room] <= 0.0:
			alerts.erase(room)
	var suppressed := minf(emp_recovery_time, delta)
	if suppressed > 0.0:
		updated = power.recharge(suppressed, energy_recovery_rate()) or updated
		emp_recovery_time = move_toward(emp_recovery_time, 0.0, suppressed)
		if emp_recovery_time == 0.0:
			_emp_recovery_loss = 0.0
	updated = power.recharge(delta - suppressed, energy_recovery_rate()) or updated
	updated = _advance_atmosphere(delta) or updated
	if _advance_transits(delta):
		_replan_waiting_orders()
	updated = _advance_security(delta) or updated
	updated = _advance_doors(delta) or updated
	updated = _advance_combat(delta) or updated
	updated = _advance_passengers(delta) or updated
	if auto_crew:
		_crew_check -= delta
		if _crew_check <= 0.0:
			_crew_check = 0.25
			updated = _assign_local_jobs() or updated
	updated = _start_transits() or updated
	var repair_rate := 0.0
	var prepare_rate := 0.0
	for member in crew:
		if member.health <= 0.0 or member.blocked or member.landing != INVALID_CELL or not member.route.is_empty():
			continue
		if member.order in [Order.REPAIR, Order.SEAL, Order.REPAIR_ROOM]:
			member.repair_phase += delta
		match member.order:
			Order.MOVE:
				member.order = Order.IDLE
				member.target = INVALID_CELL
				updated = true
			Order.REPAIR:
				repair_rate = maxf(repair_rate, 0.23 if member.role == "Инженер" else 0.12)
			Order.PREPARE:
				if module_online(airlock_tile):
					prepare_rate = maxf(prepare_rate, 0.23 if member.role == "Спасатель" else 0.12)
			Order.SEAL, Order.REPAIR_ROOM:
				_service_hull(member, delta)
				updated = true
	if repair_rate > 0.0:
		engine_health = minf(1.0, engine_health + repair_rate * delta)
		if engine_health == 1.0:
			_finish(Order.REPAIR, Order.IDLE, "Двигатель восстановлен.")
		updated = true
	if prepare_rate > 0.0:
		airlock_progress = minf(1.0, airlock_progress + prepare_rate * hull.condition(airlock_tile) * delta)
		if airlock_progress == 1.0:
			_finish(Order.PREPARE, Order.POST, "Шлюз готов к приёму выживших.")
		updated = true
	if updated:
		changed.emit()


func energy_recovery_rate() -> float:
	if not module_online(reactor_tile):
		return 0.0
	var rate := ShipPower.RECHARGE * reactor_multiplier * hull.condition(reactor_tile) * (1.0 - _emp_recovery_loss)
	var operator := operator_at(WorkPose.REACTOR)
	if hacked(reactor_tile):
		rate *= 0.20
	if operator != null:
		rate *= 1.85 if operator.specialty == REACTOR_TECH else ShipPower.OPERATOR_BONUS
	return rate


func _advance_atmosphere(delta: float) -> bool:
	var open_doors: Array[Vector4i] = []
	for tile in doors:
		if doors[tile].openness >= 1.0:
			open_doors.append(tile)
	var support := hull.condition(life_support_tile) if module_online(life_support_tile) else 0.0
	if operator_at(WorkPose.LIFE_SUPPORT) != null:
		support *= 1.5
	if hacked(life_support_tile):
		support = 0.0
		var room: Hull.Room = hull.rooms[hull.room_at[life_support_tile]]
		room.oxygen = maxf(0.0, room.oxygen - 0.15 * delta)
	var updated := hull.advance_air(delta, open_doors, support)
	var lost_crew := false
	for member in occupants():
		if member.immune or (not damage_enabled and member.faction == 0) or member.health <= 0.0 or hull.oxygen_at(Vector2i(member.position.round())) >= Hull.LOW_OXYGEN:
			continue
		if _hurt_crew(member, HYPOXIA_DAMAGE * delta):
			notice = "%s: критическая гипоксия." % member.title
			lost_crew = true
		updated = true
	if lost_crew:
		_replan_waiting_orders()
	return updated


func _hurt_crew(member: CrewMember, damage: float) -> bool:
	if member.health <= 0.0:
		return false
	member.health = maxf(0.0, member.health - damage)
	if member.health > 0.0:
		return false
	member.down_time = 0.0
	member.order = Order.IDLE
	member.target = INVALID_CELL
	member.resume_post = INVALID_CELL
	member.route.clear()
	member.blocked = false
	member.cell = Vector2i(member.position.round())
	member.landing = INVALID_CELL
	member.squeeze = 0.0
	for index in range(_transits.size() - 1, -1, -1):
		var transit := _transits[index]
		transit.yielding.erase(member)
		transit.paths.erase(member)
		if transit.paths.is_empty():
			for other in transit.yielding:
				other.position = Vector2(other.cell)
				other.squeeze = 0.0
			_transits.remove_at(index)
	return true


func _assign_local_jobs() -> bool:
	var changed_orders := false
	for index in crew.size():
		var member := crew[index]
		if member.health <= 0.0 or member.landing != INVALID_CELL or not member.route.is_empty() or member.blocked:
			continue
		if member.order not in [Order.IDLE, Order.POST, Order.PREPARE] or (member.order == Order.IDLE and member.combat_target != null and member.combat_target.health > 0.0):
			continue
		var room: int = hull.room_at.get(member.cell, -1)
		if room < 0:
			continue
		var breach := _local_breach(member, room)
		if breach != INVALID_CELL:
			if member.order in [Order.POST, Order.PREPARE]:
				member.resume_post = member.target
			assign_order(index, breach, false, true)
			changed_orders = true
			continue
		if member.order != Order.IDLE:
			continue
		var preferred := member.resume_post
		member.resume_post = INVALID_CELL
		for target: Vector2i in [preferred] + module_cells:
			if target == airlock_tile and not auto_airlock:
				continue
			if hull.room_at.get(target, -1) != room or (target == engine_tile and engine_health == 1.0 and hull.condition(target) == 1.0):
				continue
			if crew.any(func(other: CrewMember) -> bool:
				return (other != member and other.health > 0.0 and other.target == target
					and other.order in [Order.POST, Order.PREPARE, Order.REPAIR, Order.REPAIR_ROOM])):
				continue
			assign_order(index, target, false, true)
			if not member.blocked and member.order != Order.MOVE:
				changed_orders = true
				break
			member.order = Order.IDLE
			member.target = INVALID_CELL
			member.route.clear()
			member.blocked = false
	return changed_orders


func _local_breach(member: CrewMember, room: int) -> Vector2i:
	var nearest := INVALID_CELL
	var best := INF
	for tile in hull.breaches:
		if hull.room_at.get(tile, -1) != room or crew.any(func(other: CrewMember) -> bool:
			return other.health > 0.0 and other.order == Order.SEAL and other.target == tile):
			continue
		var reachable := false
		for step in CARDINAL_STEPS:
			var stand: Vector2i = tile + step
			if hull.room_at.get(stand, -1) == room and edge_between(tile, stand) not in walls and _goal_available(stand, member, false) and not _path(member.cell, stand).is_empty():
				reachable = true
				break
		var distance := float(member.cell.distance_squared_to(tile))
		if reachable and distance < best:
			nearest = tile
			best = distance
	return nearest


func _service_hull(member: CrewMember, delta: float) -> void:
	if member.order == Order.SEAL:
		var rate := 0.45 if member.role == "Инженер" else 0.30
		if not hull.seal(member.target, rate * delta):
			return
		notice = "Пробоина заделана."
	else:
		var rate := 0.24 if member.role == "Инженер" else 0.14
		if not hull.repair(member.target, rate * Hull.ROOM_MAX * delta):
			return
		notice = "Отсек восстановлен."
		if member.target in [reactor_tile, shield_tile]:
			member.order = Order.POST
			return
		if member.target == engine_tile and engine_health < 1.0:
			member.order = Order.REPAIR
			return
	member.order = Order.IDLE
	member.target = INVALID_CELL


func _finish(completed_order: Order, next_order: Order, message: String) -> void:
	for member in crew:
		if member.order != completed_order:
			continue
		member.order = next_order
		if next_order == Order.IDLE and (member.blocked or member.landing != INVALID_CELL
				or not member.route.is_empty()):
			member.order = Order.MOVE
		if member.order == Order.IDLE:
			member.target = INVALID_CELL
	notice = message


func workstation_pose(member: CrewMember) -> WorkPose:
	if member.health <= 0.0 or member.blocked or member.landing != INVALID_CELL or not member.route.is_empty():
		return WorkPose.NONE
	if member.cell.distance_squared_to(member.target) != 1 or (not boarders.is_empty() and opponent_in_cell(member, member.cell) != null):
		return WorkPose.NONE
	match member.order:
		Order.REPAIR, Order.SEAL, Order.REPAIR_ROOM:
			return WorkPose.REPAIR
		Order.PREPARE:
			return WorkPose.AIRLOCK
		Order.POST:
			if member.target == bridge_tile and member.cell == (bridge_tile + Vector2i.DOWN):
				return WorkPose.HELM
			if member.target == airlock_tile:
				return WorkPose.AIRLOCK
			if member.target == weapons_tile and member.cell == (weapons_tile + Vector2i.DOWN):
				return WorkPose.WEAPONS
			if member.target == life_support_tile and member.cell == (life_support_tile + Vector2i.DOWN):
				return WorkPose.LIFE_SUPPORT
			if member.target == reactor_tile and member.cell == reactor_tile + Vector2i.DOWN:
				return WorkPose.REACTOR
			if member.target == shield_tile and member.cell == shield_tile + Vector2i.DOWN:
				return WorkPose.SHIELD
	return WorkPose.NONE


func crew_status(member: CrewMember) -> String:
	if member.health <= 0.0:
		return "Выведен из строя"
	if member.order == Order.ATTACK or member.attack_frame > 0.0:
		return "Ведёт бой"
	if member.order == Order.FORCE_DOOR or _needs_to_force(member) != Vector4i.ZERO:
		return "Выламывает дверь"
	if member.squeeze > 0.12 and workstation_pose(member) == WorkPose.NONE:
		return "Пропускает" if member.landing == INVALID_CELL else "Протискивается"
	if member.landing != INVALID_CELL:
		return "В пути"
	if member.blocked:
		return "Ожидает пульт" if member.target in [bridge_tile, weapons_tile, life_support_tile, reactor_tile, shield_tile] else "Ждёт прохода"
	if not member.route.is_empty():
		var next := member.route[0]
		return "Ждёт прохода" if _reserved(next) or _occupant(next) != null else "Готов идти"
	match member.order:
		Order.REPAIR, Order.REPAIR_ROOM:
			return "Ремонтирует"
		Order.SEAL:
			return "Заделывает пробоину"
		Order.PREPARE:
			return "Готовит шлюз"
		Order.POST:
			if not module_online(member.target):
				return "Пост отключён"
			if member.target == bridge_tile:
				return "За штурвалом"
			if member.target == weapons_tile:
				return "За орудием"
			if member.target == airlock_tile:
				return "На посту у шлюза"
			if member.target == life_support_tile:
				return "У кислородной установки"
			if member.target == reactor_tile:
				return "У реактора"
			if member.target == shield_tile:
				return "За пультом щита"
	return "Свободен"


func occupants() -> Array[CrewMember]:
	return crew + boarders if not boarders.is_empty() else crew


func make_member(title: String, specialty: int, tile: Vector2i) -> CrewMember:
	var profile: Dictionary = SPECIALTIES[specialty]
	var member := CrewMember.new(title, profile.role, profile.color, tile)
	member.specialty = specialty
	return member


func free_cells_in_room(module: Vector2i, arriving_faction := -1) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not hull.room_at.has(module):
		return cells
	var occupied: Array[Vector2i] = []
	for tile in hull.rooms[hull.room_at[module]].tiles:
		if not _grid.has_point(_id(tile)) or _occupant(tile, arriving_faction) != null:
			continue
		if arriving_faction < 0 and _reserved(tile):
			continue
		if occupants().any(func(member: CrewMember) -> bool:
			var relevant := arriving_faction < 0 or member.faction == arriving_faction
			return member.health > 0.0 and relevant and (member.landing == tile or not member.route.is_empty() and member.route.back() == tile)):
			continue
		if _occupant(tile) != null or _reserved(tile):
			occupied.append(tile)
		else:
			cells.append(tile)
	cells.append_array(occupied)
	return cells


func teleport_in(member: CrewMember, tile: Vector2i, hostile: bool) -> void:
	member.cell = tile
	member.position = Vector2(tile)
	member.faction = int(hostile)
	member.landing = INVALID_CELL
	member.order = Order.IDLE
	member.target = INVALID_CELL
	member.resume_post = INVALID_CELL
	member.force_edge = Vector4i.ZERO
	member.combat_target = null
	member.blocked = false
	member.route.clear()
	if hostile:
		boarders.append(member)
	else:
		crew.append(member)
	changed.emit()


func teleport_out(member: CrewMember) -> void:
	if member.landing != INVALID_CELL or _reserved(member.cell):
		return
	crew.erase(member)
	boarders.erase(member)
	_replan_waiting_orders()


func attack_order(index: int, target: CrewMember) -> void:
	var member := crew[index]
	if member.health <= 0.0 or target.health <= 0.0 or target not in boarders:
		return
	member.order = Order.ATTACK
	member.combat_target = target
	member.route.clear()
	member.resume_post = INVALID_CELL
	member.target = INVALID_CELL
	member.tactical_clock = 0.0
	changed.emit()


func boarder_move(member: CrewMember, cell: Vector2i, sabotage := false) -> void:
	if cell == INVALID_CELL or (member.target == cell and member.order == (Order.SABOTAGE if sabotage else Order.MOVE) and not member.blocked):
		return
	member.combat_target = null
	member.target = cell
	member.order = Order.SABOTAGE if sabotage else Order.MOVE
	member.sabotage_delay = 1.5
	_replan(member)


func _advance_combat(delta: float) -> bool:
	var updated := false
	if boarders.is_empty() and not crew.any(func(member: CrewMember) -> bool: return member.specialty == MEDIC or member.order == Order.ATTACK or member.attack_frame > 0):
		return false
	var actors := occupants()
	var enemy_present := boarders.any(func(member: CrewMember) -> bool: return member.health > 0.0)
	for member in actors:
		if member.health <= 0.0:
			continue
		member.attack_frame = move_toward(member.attack_frame, 0.0, delta)
		member.attack_cooldown = move_toward(member.attack_cooldown, 0.0, delta)
		member.tactical_clock -= delta
		if member.attack_frame > 0.0:
			updated = true
		if member.landing != INVALID_CELL or _reserved(member.cell):
			continue
		if member.order == Order.ATTACK and (member.combat_target == null or member.combat_target not in actors or member.combat_target.health <= 0.0):
			member.combat_target = null
			member.route.clear()
			member.order = Order.IDLE
			member.target = INVALID_CELL
			member.blocked = false
			updated = true
		if not enemy_present:
			member.combat_target = null
			if member.specialty == MEDIC and member.order == Order.IDLE:
				for patient in crew:
					if patient != member and patient.health > 0.0 and patient.health < 100.0 and hull.room_at[patient.cell] == hull.room_at[member.cell]:
						patient.health = minf(100.0, patient.health + 5.0 * delta)
						updated = true
			continue
		var contact := opponent_in_cell(member, member.cell)
		if member.retreating and contact == null:
			continue
		var victim := contact if contact != null else member.combat_target
		if member.order != Order.ATTACK and contact == null:
			# Operators hold their posts until an attacker reaches their tile.
			if member.order not in [Order.IDLE, Order.SABOTAGE]:
				continue
			victim = _closest_opponent(member, actors, 4.5 if member.faction > 0 and not member.aggressive else INF)
			member.combat_target = victim
			if victim == null:
				if member.order == Order.SABOTAGE:
					updated = _sabotage(member, delta) or updated
				continue
		var weapon: Dictionary = WEAPONS_DATA[member.specialty]
		var reach: float = float(weapon.get("range", 1))
		if tile_kind(member.cell) == "C" and hacked(member.cell):
			reach = 1.0
		var distance := Vector2(member.cell).distance_to(Vector2(victim.cell))
		if contact == null and reach == 1.0 and member.order != Order.SABOTAGE and member.tactical_clock <= 0.0:
			if _try_close_combat(member, victim):
				continue
		if distance > reach or not _line_of_fire(member.cell, victim.cell):
			if member.order == Order.SABOTAGE:
				updated = _sabotage(member, delta) or updated
			elif member.tactical_clock <= 0.0:
				member.tactical_clock = 0.35
				_approach_enemy(member, victim, reach)
			continue
		if contact == null or member.order in [Order.IDLE, Order.ATTACK, Order.SABOTAGE]:
			member.route.clear()
			member.target = INVALID_CELL
			member.blocked = false
		if member.attack_cooldown > 0.0:
			continue
		var melee := distance <= 1.0
		member.attack_direction = Vector2.RIGHT * (1.0 if member.faction != 0 else -1.0) if contact != null else Vector2(victim.cell - member.cell).normalized()
		member.attack_sprite = weapon.sprite if melee else (7 if member.specialty == FIGHTER else 6)
		member.attack_frame = 0.28
		member.attack_cooldown = 0.92 if melee else 1.15
		if not victim.immune and (victim.faction != 0 or damage_enabled):
			_hurt_crew(victim, weapon.melee if melee else weapon.shot)
		updated = true
	return updated


func _try_close_combat(member: CrewMember, victim: CrewMember) -> bool:
	if member.cell.distance_squared_to(victim.cell) != 1 or not joined(member.cell, victim.cell):
		return false
	if not _goal_available(victim.cell, member, false, true):
		return false
	var edge := edge_between(member.cell, victim.cell)
	if doors.has(edge) and not (doors[edge].automatic or doors[edge].wants_open):
		return false
	member.route.assign([victim.cell])
	return true


func _closest_opponent(member: CrewMember, actors: Array[CrewMember], maximum: float) -> CrewMember:
	var nearest: CrewMember
	var distance := maximum * maximum
	for candidate in actors:
		if candidate.faction == member.faction or candidate.health <= 0.0:
			continue
		var separation := float(member.cell.distance_squared_to(candidate.cell))
		if separation < distance:
			distance = separation
			nearest = candidate
	return nearest


func _approach_enemy(member: CrewMember, victim: CrewMember, reach: float) -> void:
	var best: Array[Vector2i] = []
	var best_cost := INF
	_prepare_navigation(member)
	for tile: Vector2i in hull.room_at:
		if not _grid.has_point(_id(tile)) or tile == victim.cell or tile.distance_squared_to(victim.cell) > reach * reach:
			continue
		if not _goal_available(tile, member, false) or (tile.distance_squared_to(victim.cell) != 1 and not _line_of_fire(tile, victim.cell)):
			continue
		var path := _path(member.cell, tile)
		if not path.is_empty():
			var cost := _route_cost(path)
			if cost < best_cost:
				best = path
				best_cost = cost
	_grid.locked.clear()
	if not best.is_empty():
		member.route.assign(best.slice(1))


func _line_of_fire(from: Vector2i, to: Vector2i) -> bool:
	var count := maxi(absi(to.x - from.x), absi(to.y - from.y))
	var previous := from
	for step in range(1, count + 1):
		var next := Vector2i(Vector2(from).lerp(Vector2(to), float(step) / count).round())
		if previous.distance_squared_to(next) == 2:
			var a := Vector2i(next.x, previous.y)
			var b := Vector2i(previous.x, next.y)
			if not (_clear_shot_edge(previous, a) and _clear_shot_edge(a, next) 					or _clear_shot_edge(previous, b) and _clear_shot_edge(b, next)):
				return false
		elif not _clear_shot_edge(previous, next):
			return false
		previous = next
	return true


func _clear_shot_edge(a: Vector2i, b: Vector2i) -> bool:
	if not joined(a, b):
		return false
	var edge := edge_between(a, b)
	return not doors.has(edge) or doors[edge].openness == 1.0


func _sabotage(member: CrewMember, delta: float) -> bool:
	if member.blocked or not member.route.is_empty() or member.target == INVALID_CELL:
		return false
	member.sabotage_delay -= delta
	member.attack_direction = Vector2(member.target - member.cell).normalized()
	member.attack_frame = 0.16
	member.attack_sprite = 4
	if member.sabotage_delay <= 0.0 and hull.condition(member.target) > 0.0:
		member.sabotage_delay = 1.5
		if damage_enabled:
			var room: Hull.Room = hull.rooms[hull.room_at[member.target]]
			room.integrity = maxf(0.0, room.integrity - 28.0)
			_report_damage(member.target, false, "Саботаж — " + ROOM_NAMES[tile_kind(member.target)].capitalize())
	return true


func _reset_security() -> void:
	computer_outage = 0.0
	firewall = 0.0
	hack_cooldown = 0.0
	teleport_flash = 0.0
	room_hacks.clear()
	for edge in doors:
		if doors[edge].lock_time > 0.0:
			_unlock_door(edge)


func has_hacker() -> bool:
	return crew.any(func(member: CrewMember) -> bool: return member.specialty == HACKER and member.health > 0.0)


func hacker_available() -> bool:
	return crew.any(func(member: CrewMember) -> bool:
		return member.specialty == HACKER and member.health > 0.0 and member.attack_frame <= 0.0)


func establish_firewall() -> bool:
	if not hacker_available() or hack_cooldown > 0.0:
		return false
	firewall = SECURITY_SECONDS
	hack_cooldown = 24.0
	_animate_hacker()
	changed.emit()
	return true


func send_hack(destination, kind: String, target: Variant = null) -> bool:
	if not hacker_available() or hack_cooldown > 0.0 or not power.can_spend(12.0) or not destination.damage_enabled:
		return false
	if not destination.receive_hack(kind, target):
		return false
	power.spend(12.0)
	hack_cooldown = 7.0
	_animate_hacker()
	changed.emit()
	return true


func _animate_hacker() -> void:
	for member in crew:
		if member.health > 0.0 and member.specialty == HACKER:
			member.hack_pose_time = 1.1
			return


func receive_hack(kind: String, target: Variant) -> bool:
	if firewall > 0.0:
		return false
	match kind:
		"computer":
			if computer_outage > 0.0:
				return false
			computer_outage = SECURITY_SECONDS
			security_alert.emit(kind, null, "Бортовой компьютер взломан")
		"door":
			if not target is Vector4i or target not in doors or target in hatches or doors[target].lock_time > 0.0:
				return false
			var door := doors[target]
			door.open_before_hack = door.wants_open
			door.lock_time = SECURITY_SECONDS
			door.lock_faction = 1
			door.force_progress = 0.0
			_update_edge(target, true)
			_replan_all()
			security_alert.emit(kind, target, "Дверь заблокирована взломом")
		"room":
			if not target is Vector2i or not hull.room_at.has(target) or hacked(target):
				return false
			room_hacks[hull.room_at[target]] = SECURITY_SECONDS
			security_alert.emit(kind, target, "Взлом — " + ROOM_NAMES[tile_kind(target)].capitalize())
		_:
			return false
	changed.emit()
	return true


func hacked(tile: Vector2i) -> bool:
	return room_hacks.has(hull.room_at.get(tile, -1))


func force_door(index: int, edge: Vector4i) -> bool:
	if not doors.has(edge) or doors[edge].lock_time <= 0.0 or crew[index].health <= 0.0:
		return false
	var member := crew[index]
	var a := Vector2i(edge.x, edge.y)
	var b := Vector2i(edge.z, edge.w)
	var start := member.landing if member.landing != INVALID_CELL else member.cell
	_prepare_navigation(member)
	var to_a := _path(start, a)
	var to_b := _path(start, b)
	var cost_a := _route_cost(to_a)
	var cost_b := _route_cost(to_b)
	_grid.locked.clear()
	if to_a.is_empty() and to_b.is_empty():
		return false
	member.target = b if to_a.is_empty() or (not to_b.is_empty() and cost_b < cost_a) else a
	member.force_edge = edge
	member.combat_target = null
	member.order = Order.FORCE_DOOR
	_replan(member)
	changed.emit()
	return true


func _needs_to_force(member: CrewMember) -> Vector4i:
	if member.health <= 0.0 or member.landing != INVALID_CELL or _reserved(member.cell):
		return Vector4i.ZERO
	var edge := Vector4i.ZERO
	if member.order == Order.FORCE_DOOR and member.target == member.cell:
		edge = member.force_edge
	elif not member.route.is_empty():
		edge = edge_between(member.cell, member.route[0])
	if doors.has(edge) and doors[edge].lock_time > 0.0 and doors[edge].lock_faction != member.faction:
		return edge
	return Vector4i.ZERO


func _unlock_door(edge: Vector4i, forced := false) -> void:
	var door := doors[edge]
	door.lock_time = 0.0
	door.force_progress = 0.0
	door.wants_open = door.open_before_hack
	if forced:
		door.automatic = false
		door.wants_open = true
	_update_edge(edge, door.automatic or door.wants_open)
	for member in occupants():
		if member.order == Order.FORCE_DOOR and member.force_edge == edge:
			member.order = Order.IDLE
			member.target = INVALID_CELL
			member.route.clear()
			member.blocked = false
	_replan_all()


func _replan_all() -> void:
	for member in occupants():
		if member.target != INVALID_CELL and member.health > 0.0:
			_replan(member)


func _advance_security(delta: float) -> bool:
	var updated := computer_outage > 0.0 or firewall > 0.0 or hack_cooldown > 0.0 or not room_hacks.is_empty() or teleport_flash > 0.0
	teleport_flash = move_toward(teleport_flash, 0.0, delta)
	computer_outage = move_toward(computer_outage, 0.0, delta)
	firewall = move_toward(firewall, 0.0, delta)
	hack_cooldown = move_toward(hack_cooldown, 0.0, delta)
	for room in room_hacks.keys():
		room_hacks[room] -= delta
		if room_hacks[room] <= 0.0:
			room_hacks.erase(room)
	var force := {}
	for member in occupants():
		var edge := _needs_to_force(member)
		if edge == Vector4i.ZERO:
			continue
		member.repair_phase += delta
		force[edge] = maxf(force.get(edge, 0.0), 1.4 if member.specialty == RESCUER else 1.0)
	for edge in doors:
		var door := doors[edge]
		if door.lock_time <= 0.0:
			continue
		updated = true
		door.lock_time -= delta
		door.force_progress += delta * force.get(edge, 0.0)
		var forced := door.force_progress >= DOOR_FORCE_SECONDS
		if forced or door.lock_time <= 0.0:
			_unlock_door(edge, forced)
	return updated


func drive_modifier() -> float:
	return 0.42 if hacked(engine_tile) else 1.0


func cargo_controls_online() -> bool:
	for seat in cargo_seats:
		if hacked(seat):
			return false
	return true


func computer_interrupted() -> bool:
	return computer_outage > 0.0


func clear_boarders() -> void:
	for member in boarders:
		_hurt_crew(member, 100.0)
	boarders.clear()
	_replan_waiting_orders()
