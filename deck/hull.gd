extends RefCounted

const STEPS := [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]
const HULL_MAX := 140.0
const ROOM_MAX := 100.0
const LOW_OXYGEN := 0.20
const LEAK_RATE := 0.23
const HATCH_LEAK_RATE := 0.48
const REFILL_RATE := 0.065
const EXCHANGE_RATE := 0.52


class Room:
	var tiles: Array[Vector2i] = []
	var integrity := ROOM_MAX
	var oxygen := 1.0


var rooms: Array[Room] = []
var room_at: Dictionary[Vector2i, int] = {}
var breaches: Dictionary[Vector2i, float] = {}
var integrity := HULL_MAX
var _vacuum_connections: Dictionary[Vector4i, int] = {}
var _door_connections: Dictionary[Vector4i, Vector2i] = {}


func configure(plan: Array, door_edges: Array, walls: Array = [], hatches: Array = []) -> void:
	rooms.clear()
	room_at.clear()
	breaches.clear()
	_door_connections.clear()
	_vacuum_connections.clear()
	var closed := door_edges + walls
	integrity = HULL_MAX
	var kinds: Dictionary[Vector2i, String] = {}
	for y in range(plan.size()):
		for x in range(plan[y].length()):
			var cell := Vector2i(x, y)
			if plan[y][x] != ".":
				kinds[cell] = plan[y][x]
	for cell in kinds:
		if room_at.has(cell):
			continue
		var room := Room.new()
		var index := rooms.size()
		rooms.append(room)
		room_at[cell] = index
		var pending: Array[Vector2i] = [cell]
		while not pending.is_empty():
			var tile: Vector2i = pending.pop_back()
			room.tiles.append(tile)
			for step: Vector2i in STEPS:
				var other := tile + step
				if kinds.get(other, "") == kinds[cell] and not room_at.has(other) and edge_between(tile, other) not in closed:
					room_at[other] = index
					pending.append(other)
	for edge: Vector4i in door_edges:
		var a: int = room_at[Vector2i(edge.x, edge.y)]
		var b: int = room_at[Vector2i(edge.z, edge.w)]
		if a != b:
			_door_connections[edge] = Vector2i(mini(a, b), maxi(a, b))

	for edge: Vector4i in hatches:
		var a := Vector2i(edge.x, edge.y)
		var b := Vector2i(edge.z, edge.w)
		_vacuum_connections[edge] = room_at[a] if room_at.has(a) else room_at[b]


static func edge_between(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.y > b.y or (a.y == b.y and a.x > b.x):
		return Vector4i(b.x, b.y, a.x, a.y)
	return Vector4i(a.x, a.y, b.x, b.y)


func condition(tile: Vector2i) -> float:
	if not room_at.has(tile):
		return 1.0
	return rooms[room_at[tile]].integrity / ROOM_MAX


func oxygen_at(tile: Vector2i) -> float:
	return rooms[room_at[tile]].oxygen if room_at.has(tile) else 1.0


func strike(tile: Vector2i, damage: float, breach_chance: float, occupied: Array[Vector2i],
		rng: RandomNumberGenerator) -> void:
	if not room_at.has(tile):
		return
	var room := rooms[room_at[tile]]
	integrity = maxf(0.0, integrity - damage)
	room.integrity = maxf(0.0, room.integrity - damage)
	if breach_chance <= 0.0 or rng.randf() >= breach_chance:
		return
	var free: Array[Vector2i] = []
	for cell in room.tiles:
		if cell not in occupied and not breaches.has(cell):
			free.append(cell)
	if not free.is_empty():
		breaches[free[rng.randi_range(0, free.size() - 1)]] = 1.0


func repair(tile: Vector2i, amount: float) -> bool:
	var room := rooms[room_at[tile]]
	room.integrity = minf(ROOM_MAX, room.integrity + amount)
	return room.integrity == ROOM_MAX


func seal(tile: Vector2i, amount: float) -> bool:
	if not breaches.has(tile):
		return true
	breaches[tile] -= amount
	if breaches[tile] > 0.0:
		return false
	breaches.erase(tile)
	return true


func advance_air(delta: float, open_doors: Array[Vector4i], life_support: float) -> bool:
	var links: Dictionary[Vector2i, bool] = {}
	for edge in open_doors:
		if _door_connections.has(edge):
			links[_door_connections[edge]] = true
	var changes := PackedFloat64Array()
	changes.resize(rooms.size())
	for pair: Vector2i in links:
		var a := rooms[pair.x]
		var b := rooms[pair.y]
		var exchange := (a.oxygen - b.oxygen) * EXCHANGE_RATE * delta * mini(a.tiles.size(), b.tiles.size())
		changes[pair.x] -= exchange / a.tiles.size()
		changes[pair.y] += exchange / b.tiles.size()
	for edge in open_doors:
		if _vacuum_connections.has(edge):
			changes[_vacuum_connections[edge]] -= HATCH_LEAK_RATE * delta
	for tile in breaches:
		changes[room_at[tile]] -= LEAK_RATE * delta
	var updated := false
	for index in range(rooms.size()):
		var room := rooms[index]
		var next := clampf(room.oxygen + changes[index] + REFILL_RATE * delta * life_support,
			0.0, 1.0)
		updated = updated or not is_equal_approx(next, room.oxygen)
		room.oxygen = next
	return updated
