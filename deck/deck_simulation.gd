extends Node

signal changed
signal damage_alert(tile: Vector2i, breach: bool, message: String)

enum Order { IDLE, MOVE, POST, REPAIR, PREPARE, SEAL, REPAIR_ROOM }

const Hull = preload("res://deck/hull.gd")
const ShipPower = preload("res://deck/ship_power.gd")
enum WorkPose { NONE, HELM, REPAIR, AIRLOCK, WEAPONS, LIFE_SUPPORT, REACTOR }

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


class Door:
	var wants_open: bool
	var automatic := true
	var openness: float

	func _init(open: bool) -> void:
		wants_open = open
		openness = 1.0 if open else 0.0

	func permits_entry() -> bool:
		return wants_open and openness == 1.0


class CrewMember:
	var title: String
	var role: String
	var color: Color
	var cell: Vector2i
	var position: Vector2
	var target := INVALID_CELL
	var route: Array[Vector2i] = []
	var landing := INVALID_CELL
	var squeeze := 0.0
	var squeeze_side := Vector2.ZERO
	var face_left := false
	var order := Order.IDLE
	var blocked := false
	var health := 100.0

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
var power := ShipPower.new()
var simulation_speed := 1.0
var module_cells: Array = MODULE_CELLS
var crew: Array[CrewMember] = []
var doors: Dictionary[Vector4i, Door] = {}
var engine_health := 0.0
var airlock_progress := 0.0
var notice := ""
var training_hint := ""
var _door_edges: Array = []
var _grid := AStar2D.new()
var _bounds := Rect2i()
var _transits: Array[Transit] = []
var hull := Hull.new()
var floor_bounds := Rect2()
var damage_enabled := true
var alerts: Dictionary[int, float] = {}
var emp_timers: Dictionary[int, float] = {}
var emp_recovery_time := 0.0
var _emp_recovery_loss := 0.0
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
	weapons_tile = layout.modules.weapons
	life_support_tile = layout.modules.life_support
	reactor_tile = layout.modules.reactor
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
		assert(_grid.has_point(_id(crew[index].cell)) and tile_kind(crew[index].cell) == ["B", "E", "S", "W"][index],
			"Crew spawn must be on the floor of the assigned compartment")
	crew[0].target = bridge_tile
	crew[0].order = Order.POST
	crew[GUNNER_INDEX].target = weapons_tile
	crew[GUNNER_INDEX].order = Order.POST
	_transits.clear()
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
	return skill * lerpf(0.35, 1.0, hull.condition(bridge_tile))


func module_online(tile: Vector2i) -> bool:
	return hull.condition(tile) > 0.0 and emp_time(tile) == 0.0


func emp_time(tile: Vector2i) -> float:
	return emp_timers.get(hull.room_at.get(tile, -1), 0.0)


func apply_emp(drain: float, duration: float, count: int, side: Vector2, recovery_loss := 0.0) -> void:
	if not damage_enabled or disabled():
		return
	power.spend(minf(power.energy, drain))
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
	for member in crew:
		if member.health > 0.0:
			occupied.append(member.cell)
			occupied.append(member.landing)
	for transit in _transits:
		occupied.append_array(transit.cells)
	var leaks_before := hull.breaches.size()
	hull.strike(tile, damage, clampf(breach_chance, 0.0, 1.0), occupied, _rng)
	var lost := false
	if crew_damage > 0.0:
		var room: int = hull.room_at[tile]
		for member in crew:
			if hull.room_at.get(Vector2i(member.position.round()), -1) == room:
				lost = _hurt_crew(member, crew_damage) or lost
		if lost:
			_replan_waiting_orders()
	var breached := hull.breaches.size() > leaks_before
	if not announce and not breached:
		changed.emit()
		return tile
	var room_name: String = {"B": "мостик", "E": "двигатели", "W": "вооружение",
		"L": "кислородная установка", "S": "шлюз", "C": "коридор", "R": "реактор"}[tile_kind(tile)]
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


func assign_order(index: int, target: Vector2i, move_only := false) -> void:
	if tile_kind(target) == ".":
		return
	var member := crew[index]
	if member.health <= 0.0:
		return
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
		elif target in [bridge_tile, weapons_tile, life_support_tile, reactor_tile]:
			member.order = Order.POST
		else:
			member.order = Order.MOVE
	_replan(member)
	if member.target == member.cell and member.landing == INVALID_CELL:
		for other in crew:
			if other != member and not other.route.is_empty() and other.route.back() == member.cell:
				_replan(other)
	_replan_waiting_orders()
	notice = "Цель недоступна или занята." if member.blocked else ""
	if member.blocked and member.target == bridge_tile:
		notice = "Кресло пилота занято."
	elif member.blocked and member.target == weapons_tile:
		notice = "Пост вооружения занят."
	changed.emit()


func toggle_door(edge: Vector4i) -> void:
	if doors.has(edge):
		_set_manual_door(edge, not doors[edge].wants_open)


func set_automatic(edge: Vector4i) -> void:
	if not doors.has(edge) or edge in hatches:
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
		for member in crew:
			var start := member.landing if member.landing != INVALID_CELL else member.cell
			if _crosses_edge(start, member.route, edge):
				_replan(member)
		notice = "Дверь закроется после освобождения прохода." if _edge_reserved(edge) else "Дверь закрывается."
	changed.emit()


func _door_allows_step(from: Vector2i, to: Vector2i) -> bool:
	var edge := edge_between(from, to)
	return not doors.has(edge) or doors[edge].permits_entry()


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
	return false


func _door_needed(edge: Vector4i) -> bool:
	if _edge_reserved(edge):
		return true
	var center := (Vector2(edge.x, edge.y) + Vector2(edge.z, edge.w)) * 0.5
	for member in crew:
		if member.health > 0.0 and member.position.distance_squared_to(center) <= 9.1:
			var start := member.landing if member.landing != INVALID_CELL else member.cell
			if _crosses_edge(start, member.route, edge):
				return true
	return false


func _replan_waiting_orders() -> void:
	for member in crew:
		if member.health > 0.0 and member.target != INVALID_CELL and member.blocked:
			_replan(member)


func _replan(member: CrewMember) -> void:
	# An admitted transit owns its entire crossing. Only change the route after it.
	var start := member.landing if member.landing != INVALID_CELL else member.cell
	var weighted: Array[Vector2i] = []
	for other in crew:
		if other != member and other.health > 0.0:
			weighted.append(other.cell)
			if other.landing != INVALID_CELL:
				weighted.append(other.landing)
	for tile in weighted:
		_grid.set_point_weight_scale(_id(tile), TRAFFIC_WEIGHT)
	var path := _path_to_order(member, start)
	for tile in weighted:
		_grid.set_point_weight_scale(_id(tile), 1.0)

	member.blocked = path.is_empty()
	member.route.assign(path.slice(1))


func _path_to_order(member: CrewMember, start: Vector2i) -> Array[Vector2i]:
	if (member.order == Order.POST and member.target in [bridge_tile, weapons_tile, life_support_tile, reactor_tile]) \
		or (member.order == Order.REPAIR_ROOM and member.target == reactor_tile):
		var seat := member.target + Vector2i.DOWN
		if not _goal_available(seat, member, true):
			return []
		return _path(start, seat)
	if member.target not in module_cells and member.order not in [Order.SEAL, Order.REPAIR_ROOM]:
		if not _goal_available(member.target, member, true):
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
		var cost := 0.0
		for step in path.slice(1):
			cost += _grid.get_point_weight_scale(_id(step))
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


func _goal_available(tile: Vector2i, member: CrewMember, allow_departure: bool) -> bool:
	if tile == member.cell and member.landing == INVALID_CELL:
		return true
	for other in crew:
		if other == member or other.health <= 0.0:
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


func _occupant(tile: Vector2i) -> CrewMember:
	for member in crew:
		if member.health > 0.0 and member.cell == tile:
			return member
	return null


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
	for member in crew:
		if not _waiting_to_walk(member):
			continue
		var next := member.route[0]
		if not _door_allows_step(member.cell, next) or _reserved(next) or _occupant(next) != null:
			continue
		var transit := Transit.new()
		_add_path(transit, member, 1)
		_transits.append(transit)
		started = true
	for member in crew:
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
		if not _door_allows_step(previous, tile) or _reserved(tile):
			return false
		var other := _occupant(tile)
		if other == null:
			if index == 0:
				return false
			transit.length = index + 1
			_add_path(transit, member, transit.length)
			_transits.append(transit)
			return true
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
			var path: Array = transit.paths[member]
			var edge := mini(floori(transit.distance), transit.length - 1)
			var direction := Vector2(path[edge + 1] - path[edge])
			member.position = Vector2(path[edge]) + direction * (transit.distance - edge)
			if direction.x != 0.0:
				member.face_left = direction.x < 0.0
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
			member.position = Vector2(member.cell) + member.squeeze_side * (SQUEEZE_OFFSET * member.squeeze)
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
		if door.automatic:
			door.wants_open = _door_needed(edge)
		if not door.wants_open and _edge_reserved(edge):
			continue
		var goal := 1.0 if door.wants_open else 0.0
		if door.openness == goal:
			continue
		door.openness = move_toward(door.openness, goal, delta / DOOR_SECONDS)
		updated = true
		if door.openness == goal and not door.automatic:
			notice = "Наружная дверь открыта. Утечка кислорода." if edge in hatches and door.wants_open else ("Дверь открыта." if door.wants_open else "Дверь закрыта.")
			if door.wants_open:
				opened = true
	if opened:
		_replan_waiting_orders()
	return updated


func _physics_process(delta: float) -> void:
	delta *= simulation_speed
	var updated := not _transits.is_empty() or not alerts.is_empty() or not emp_timers.is_empty() or emp_recovery_time > 0.0
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
	updated = _advance_doors(delta) or updated
	updated = _start_transits() or updated
	var repair_rate := 0.0
	var prepare_rate := 0.0
	for member in crew:
		if member.health <= 0.0 or member.blocked or member.landing != INVALID_CELL or not member.route.is_empty():
			continue
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
	var rate := ShipPower.RECHARGE * hull.condition(reactor_tile) * (1.0 - _emp_recovery_loss)
	return rate * ShipPower.OPERATOR_BONUS if operator_at(WorkPose.REACTOR) != null else rate


func _advance_atmosphere(delta: float) -> bool:
	var open_doors: Array[Vector4i] = []
	for tile in doors:
		if doors[tile].openness >= 1.0:
			open_doors.append(tile)
	var support := hull.condition(life_support_tile) if module_online(life_support_tile) else 0.0
	if operator_at(WorkPose.LIFE_SUPPORT) != null:
		support *= 1.5
	var updated := hull.advance_air(delta, open_doors, support)
	var lost_crew := false
	for member in crew:
		if not damage_enabled or member.health <= 0.0 or hull.oxygen_at(Vector2i(member.position.round())) >= Hull.LOW_OXYGEN:
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
	member.order = Order.IDLE
	member.target = INVALID_CELL
	member.route.clear()
	member.blocked = false
	return true


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
		if member.target == reactor_tile:
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
	if member.cell.distance_squared_to(member.target) != 1:
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
	return WorkPose.NONE


func crew_status(member: CrewMember) -> String:
	if member.health <= 0.0:
		return "Выведен из строя"
	if member.squeeze > 0.12 and workstation_pose(member) == WorkPose.NONE:
		return "Пропускает" if member.landing == INVALID_CELL else "Протискивается"
	if member.landing != INVALID_CELL:
		return "В пути"
	if member.blocked:
		return "Ожидает пульт" if member.target in [bridge_tile, weapons_tile, life_support_tile, reactor_tile] else "Ждёт прохода"
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
	return "Свободен"
