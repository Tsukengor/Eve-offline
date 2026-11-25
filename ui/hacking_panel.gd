extends Control

const Voyage = preload("res://flight/voyage_state.gd")
const Deck = Voyage.DeckSimulation

signal dismissed

class DeckMap extends Control:
	signal targeted(kind: String, target: Variant)
	var interior: Deck
	var pitch := 32.0
	var origin := Vector2.ZERO
	var hover := {}
	const ROOM_COLORS := {
		"B": Color("#345878"), "E": Color("#63463d"), "S": Color("#2e625c"),
		"W": Color("#5b4872"), "L": Color("#347385"), "R": Color("#675237"),
		"C": Color("#24374d"), "G": Color("#525442"), "H": Color("#385778"),
		"T": Color("#514676"),
	}

	func set_deck(value: Deck) -> void:
		interior = value
		hover.clear()
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0c1624"))
		if interior == null or interior.plan.is_empty():
			return
		var bounds := interior.floor_bounds
		pitch = minf(43.0, minf((size.x - 48.0) / bounds.size.x, (size.y - 34.0) / bounds.size.y))
		origin = (size - bounds.size * pitch) * 0.5 - bounds.position * pitch
		var hover_room := -1
		if hover.get("kind") == "room":
			hover_room = interior.hull.room_at.get(hover.subject, -1)
		for tile: Vector2i in interior.hull.room_at:
			var room: int = interior.hull.room_at[tile]
			var tint: Color = ROOM_COLORS[interior.tile_kind(tile)]
			if interior.hacked(tile):
				tint = tint.lerp(Color("#b67be6"), 0.6)
			if room == hover_room:
				tint = tint.lightened(0.26)
			draw_rect(Rect2(origin + Vector2(tile) * pitch, Vector2.ONE * (pitch - 1.0)), tint)
		for room in interior.hull.rooms:
			var center := Vector2.ZERO
			for tile in room.tiles:
				center += _tile_center(tile)
			center /= room.tiles.size()
			var kind := interior.tile_kind(room.tiles.front())
			var label: String = "Кислород" if kind == "L" else Deck.ROOM_NAMES[kind].capitalize()
			var font_size := clampi(roundi(pitch * 0.30), 9, 13)
			var font := ThemeDB.fallback_font
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if room.tiles.size() >= 3 and label != "Коридор":
				draw_string(font, center + Vector2(-width * 0.5, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#e5eff5"))
		for edge in interior.walls:
			_draw_edge(edge, Color("#8294a6"), 2.0)
		for edge in interior.doors:
			var color := Color("#d4a86c")
			if edge in interior.hatches:
				color = Color("#768da4")
			elif interior.doors[edge].lock_time > 0.0:
				color = Color("#e3a2fa")
			if hover.get("kind") == "door" and hover.subject == edge:
				color = Color("#fff0bd")
			_draw_edge(edge, color, 5.0)

	func _tile_center(tile: Vector2i) -> Vector2:
		return origin + (Vector2(tile) + Vector2.ONE * 0.5) * pitch

	func _edge_center(edge: Vector4i) -> Vector2:
		return (_tile_center(Vector2i(edge.x, edge.y)) + _tile_center(Vector2i(edge.z, edge.w))) * 0.5

	func _draw_edge(edge: Vector4i, color: Color, width: float) -> void:
		var center := _edge_center(edge)
		var side := Vector2(edge.z - edge.x, edge.w - edge.y).orthogonal() * pitch * 0.31
		draw_line(center - side, center + side, color, width)

	func pick(point: Vector2) -> Dictionary:
		if interior == null:
			return {}
		for edge in interior.doors:
			var distance := point - _edge_center(edge)
			var normal := Vector2(edge.z - edge.x, edge.w - edge.y)
			if absf(distance.dot(normal)) <= 6.0 and absf(distance.dot(normal.orthogonal())) <= pitch * 0.33:
				if edge in interior.hatches:
					return {}
				return {"kind": "door", "subject": edge}
		var tile := Vector2i(((point - origin) / pitch).floor())
		return {"kind": "room", "subject": tile} if interior.hull.room_at.has(tile) else {}

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			hover = pick(event.position)
			tooltip_text = ""
			match hover.get("kind"):
				"door": tooltip_text = "Взломать дверь"
				"room": tooltip_text = "Взломать отсек · " + Deck.ROOM_NAMES[interior.tile_kind(hover.subject)]
			queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var target := pick(event.position)
			if not target.is_empty():
				targeted.emit(target.kind, target.subject)
			accept_event()

var voyage: Voyage
var _hostiles: Array[Voyage.EnemyShip] = []
var _ships: OptionButton
var _map: DeckMap
var _status: Label
var _console: Button
var _firewall: Button
var _selection: Voyage.EnemyShip


func build(frame_style: StyleBoxFlat) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.027, 0.042, 0.067, 0.76)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var middle := CenterContainer.new()
	middle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(middle)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 800
	panel.add_theme_stylebox_override("panel", frame_style)
	middle.add_child(panel)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 10)
	panel.add_child(lines)
	var heading := Label.new()
	heading.text = "Взлом систем"
	heading.add_theme_font_size_override("font_size", 24)
	lines.add_child(heading)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	lines.add_child(controls)
	_ships = OptionButton.new()
	_ships.custom_minimum_size.x = 300
	_ships.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ships.item_selected.connect(_select)
	controls.add_child(_ships)
	_console = _make_button(controls, "Взломать компьютер", _target.bind("computer", null))
	_firewall = _make_button(controls, "Фаерволл", _raise_firewall)
	_make_button(controls, "Закрыть", dismissed.emit)
	_map = DeckMap.new()
	_map.custom_minimum_size.y = 337
	_map.mouse_exited.connect(func() -> void:
		_map.hover.clear()
		_map.queue_redraw())
	_map.targeted.connect(_target)
	lines.add_child(_map)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(_status)


func open(state: Voyage) -> void:
	voyage = state
	_ships.clear()
	_hostiles.clear()
	for hostile in voyage.enemies:
		if not is_instance_valid(hostile) or hostile.disabled():
			continue
		_hostiles.append(hostile)
		var distance := voyage.ship_position.distance_to(hostile.position)
		_ships.add_item("%s · %d · %d ед." % [hostile.call_sign, _hostiles.size(), roundi(distance)])
	if _hostiles.is_empty():
		_ships.add_item("Нет доступных кораблей")
	_ships.disabled = _hostiles.is_empty()
	_ships.select(0)
	_select(0)
	show()


func _select(index: int) -> void:
	_selection = _hostiles[index] if index >= 0 and index < _hostiles.size() else null
	_map.set_deck(_selection.deck if is_instance_valid(_selection) else null)
	_refresh()


func _target(kind: String, subject: Variant) -> void:
	if not is_instance_valid(_selection):
		return
	var message := "Взлом выполнен"
	if not voyage.hack_target_available(_selection):
		message = "Корабль вне досягаемости"
	elif not voyage.deck.hacker_available():
		message = "Хакер занят"
	elif voyage.deck.hack_cooldown > 0.0:
		message = "Следующий взлом через %d с" % ceili(voyage.deck.hack_cooldown)
	elif voyage.deck.power.energy < 12.0:
		message = "Для взлома нужно 12 ед. энергии"
	elif _selection.deck.firewall > 0.0:
		message = "Взлом заблокирован фаерволлом цели"
	elif not voyage.hack_enemy(_selection, kind, subject):
		message = "Система уже взломана или защищена от урона"
	_refresh(message)


func _raise_firewall() -> void:
	var success := voyage.deck.establish_firewall()
	_refresh("Фаерволл активен на 20 с" if success else "Фаерволл сейчас недоступен")


func _refresh(message := "") -> void:
	var ready := voyage.deck.hack_cooldown <= 0.0 and voyage.deck.hacker_available()
	_firewall.disabled = not ready
	_console.disabled = not ready or not voyage.hack_target_available(_selection) or voyage.deck.power.energy < 12.0
	if message.is_empty():
		if voyage.deck.firewall > 0.0:
			message = "Фаерволл активен ещё %d с" % ceili(voyage.deck.firewall)
		elif not is_instance_valid(_selection):
			message = "Фаерволл можно установить без выбранной цели"
		elif not voyage.hack_target_available(_selection):
			message = "Для взлома подлетите ближе чем на %d ед." % int(Deck.HACK_RANGE)
		elif voyage.deck.hack_cooldown > 0.0:
			message = "Следующий взлом через %d с" % ceili(voyage.deck.hack_cooldown)
		else:
			message = "Щёлкните по отсеку или внутренней двери · 12 ед. энергии"
	_status.text = message
	_map.queue_redraw()


func _make_button(parent: Control, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 36
	button.pressed.connect(action)
	parent.add_child(button)
	return button
