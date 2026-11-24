extends RefCounted

const Hull = preload("res://deck/hull.gd")
const MODULES := {"bridge": "B", "engine": "E", "airlock": "S", "weapons": "W", "life_support": "L", "reactor": "R"}
const MAX_WIDTH := 24
const MAX_HEIGHT := 18
const MAX_BYTES := 65536


static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {"error": "Файл планировки отсутствует или слишком большой."}
	return decode(JSON.parse_string(file.get_as_text()))


static func decode(data: Variant) -> Dictionary:
	if not data is Dictionary or data.get("type") != "eve.ship-layout" or data.get("version") != 1:
		return {"error": "Нужен JSON планировки Eve Offline версии 1."}
	var rows: Variant = data.get("plan")
	if not rows is Array or rows.is_empty() or rows.size() > MAX_HEIGHT or not rows[0] is String:
		return {"error": "Неподдерживаемая высота палубы."}
	var width: int = rows[0].length()
	if width < 1 or width > MAX_WIDTH:
		return {"error": "Неподдерживаемая ширина палубы."}
	var floors: Dictionary[Vector2i, String] = {}
	for y in range(rows.size()):
		if not rows[y] is String or rows[y].length() != width:
			return {"error": "Строки палубы должны быть одной длины."}
		for x in range(width):
			var kind: String = rows[y][x]
			if not ".CBESWLRGH".contains(kind):
				return {"error": "Неизвестный тип клетки."}
			if kind != ".":
				floors[Vector2i(x, y)] = kind
	var modules: Variant = data.get("modules")
	if not modules is Dictionary:
		return {"error": "Отсутствует размещение модулей."}
	var equipment := {}
	for key: String in MODULES:
		var tile := _point(modules.get(key))
		if floors.get(tile) != MODULES[key]:
			return {"error": "Установите модуль в подходящий отсек: " + key}
		equipment[key] = tile

	if modules.has("shield"):
		var tile := _point(modules.shield)
		if floors.get(tile) != "H":
			return {"error": "Установите пост щита в отсек щита."}
		equipment["shield"] = tile

	var edges: Variant = data.get("edges")
	if not edges is Array or edges.size() > 4 * floors.size():
		return {"error": "Некорректный список границ."}
	var doors: Array[Vector4i] = []
	var hatches: Array[Vector4i] = []
	var walls: Array[Vector4i] = []
	var used := {}
	for entry in edges:
		if not entry is Dictionary:
			return {"error": "Укажите клетки по обе стороны границы."}
		var a := _point(entry.get("a"))
		var b := _point(entry.get("b"))
		var kind: Variant = entry.get("kind")
		var edge := Hull.edge_between(a, b)
		if a.distance_squared_to(b) != 1 or used.has(edge):
			return {"error": "Граница должна соединять две соседние клетки и не повторяться."}
		used[edge] = true
		var inside := int(floors.has(a)) + int(floors.has(b))
		if kind == "wall" and inside == 2:
			walls.append(edge)
		elif kind == "door" and inside == 2 and a not in equipment.values() and b not in equipment.values():
			doors.append(edge)
		elif kind == "hatch" and inside == 1 and a not in equipment.values() and b not in equipment.values():
			hatches.append(edge)
		else:
			return {"error": "Дверь требует свободного пола с обеих сторон, наружная дверь — с одной."}

	var walkable := floors.duplicate()
	for tile: Vector2i in equipment.values():
		walkable.erase(tile)
	var spawns: Array[Vector2i] = []
	for key in ["bridge", "engine", "airlock", "weapons", "life_support", "reactor"]:
		var tile: Vector2i = equipment[key]
		var directions := [Vector2i.DOWN]
		if key == "engine":
			directions = Hull.STEPS
		elif key == "airlock":
			directions = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]
		var found := false
		for step: Vector2i in directions:
			var seat := tile + step
			var edge := Hull.edge_between(tile, seat)
			if walkable.get(seat) == floors[tile] and edge not in walls:
				spawns.append(seat)
				found = true
				break
		if not found:
			return {"error": "Оставьте свободное рабочее место у модуля: " + key}

	if equipment.has("shield"):
		var tile: Vector2i = equipment.shield
		var seat := tile + Vector2i.DOWN
		if walkable.get(seat) != "H" or Hull.edge_between(tile, seat) in walls:
			return {"error": "Оставьте рабочее место у поста щита."}

	var pending: Array[Vector2i] = [spawns[0]]
	var reached := {spawns[0]: true}
	while not pending.is_empty():
		var a: Vector2i = pending.pop_back()
		for step: Vector2i in Hull.STEPS:
			var b: Vector2i = a + step
			if not walkable.has(b) or reached.has(b):
				continue
			var edge := Hull.edge_between(a, b)
			if edge in doors or (edge not in walls and floors[a] == floors[b]):
				reached[b] = true
				pending.append(b)
	if reached.size() != walkable.size():
		return {"error": "Соедините все клетки пола с мостиком через проходы или двери."}
	var name_value: Variant = data.get("name")
	var title: String = name_value.strip_edges().substr(0, 40) if name_value is String else ""
	return {"plan": rows, "name": title if not title.is_empty() else "Палуба",
		"modules": equipment, "doors": doors, "hatches": hatches, "walls": walls, "spawns": spawns.slice(0, 4)}


static func _point(value: Variant) -> Vector2i:
	if value is Array and value.size() == 2:
		for axis in value:
			if not (axis is int or axis is float) or axis < -1 or axis > MAX_WIDTH or floorf(axis) != axis:
				return Vector2i(-100, -100)
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-100, -100)
