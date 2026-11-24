extends Node2D

@onready var _settings = get_node("/root/GameSettings")

signal reset_requested

const DeckSimulation = preload("res://deck/deck_simulation.gd")
const CREW_SPRITES := [
	preload("res://assets/deck/pilot.png"),
	preload("res://assets/deck/engineer.png"),
	preload("res://assets/deck/rescuer.png"),
	preload("res://assets/deck/gunner.png"),
]
const WALK_FRAMES := preload("res://assets/deck/crew_walk.png")
const REPAIR_FRAMES := preload("res://assets/deck/crew_repair.png")
const CARGO_SEAT := preload("res://assets/deck/cargo_seat.png")
const PASSENGER := preload("res://assets/deck/passenger.png")
const REPAIR_SOUND := preload("res://assets/audio/repair_tools.wav")
const HELM_SPRITES := [
	preload("res://assets/deck/pilot_helm.png"),
	preload("res://assets/deck/engineer_helm.png"),
	preload("res://assets/deck/rescuer_helm.png"),
	preload("res://assets/deck/gunner_seated.png"),
]
const WORK_FRAME := 128.0
const GUNNER_WORK := preload("res://assets/deck/work/gunner_work.png")
const WORK_DIRECTIONS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const WORK_ATLASES := {
	DeckSimulation.WorkPose.AIRLOCK: {
		Vector2i.UP: preload("res://assets/deck/work/airlock_north.png"),
		Vector2i.DOWN: preload("res://assets/deck/work/airlock_south.png"),
		Vector2i.LEFT: preload("res://assets/deck/work/airlock_west.png"),
		Vector2i.RIGHT: preload("res://assets/deck/work/airlock_east.png"),
	},
}
const WALL_TRIM := preload("res://assets/deck/floor_wall_trim.png")
const FLOOR_THRESHOLD := preload("res://assets/deck/floor_threshold.png")
const FLOOR_SPRITES := {
	"B": preload("res://assets/deck/bridge_floor_v2.png"),
	"E": preload("res://assets/deck/engineering_floor_v2.png"),
	"R": preload("res://assets/deck/engineering_floor_v2.png"),
	"S": preload("res://assets/deck/rescue_floor_v2.png"),
	"C": preload("res://assets/deck/corridor_floor_v2.png"),
	"W": preload("res://assets/deck/weapons_floor.png"),
	"L": preload("res://assets/deck/rescue_floor_v2.png"),
	"G": preload("res://assets/deck/cargo_floor.png"),
	"H": preload("res://assets/deck/shield_floor.png"),
}
const BRIDGE_SPRITE := preload("res://assets/deck/bridge_console_v2.png")
const ENGINE_SPRITE := preload("res://assets/deck/engine.png")
const SHIELD_CONSOLE := preload("res://assets/deck/shield_console.png")
const AIRLOCK_SPRITE := preload("res://assets/deck/airlock.png")
const REACTOR_SPRITE := preload("res://assets/deck/reactor.png")
const WEAPONS_SPRITE := preload("res://assets/deck/weapons_console.png")
const LIFE_SUPPORT_SPRITE := preload("res://assets/deck/life_support.png")
const BREACH_SPRITE := preload("res://assets/deck/breach.png")
const AIR_LEAK := preload("res://assets/deck/air_leak.png")
const EMP_SPARK := preload("res://assets/flight/emp_spark.png")
const DAMAGE_SPRITE := preload("res://assets/deck/room_damage.png")
const DAMAGE_TONE := preload("res://assets/audio/system_damage.wav")
const BREACH_TONE := preload("res://assets/audio/hull_breach.wav")
const DOOR_SPRITE := preload("res://assets/deck/bulkhead_door.png")
const ORIGIN := Vector2(100, 175)
const CELL := 33.0
const TEXT := Color("#e3edf6")
const MUTED := Color("#a1b4c9")
const LINE := Color("#30465c")
const PANEL := Color("#101e2e")
const ACCENT := Color("#78ead0")
const AMBER := Color("#f7bf79")
const DANGER := Color("#ff8c85")
const WEAPONS_COLOR := Color("#d6a4fa")

@onready var simulation: DeckSimulation = $Simulation
@export var standalone := true

var _font := ThemeDB.fallback_font
var _selected := 1
var _hovered_cell := DeckSimulation.INVALID_CELL
var _deck_origin := ORIGIN
var _deck_cell := CELL
var _pause_button: Button
var _crew_buttons: Array[Button] = []
var _crew_selected_styles: Array[StyleBoxFlat] = []
var _normal_style: StyleBoxFlat
var _audio: AudioStreamPlayer
var _repair_audio: AudioStreamPlayer



func _ready() -> void:
	_normal_style = _button_style(PANEL, LINE)
	_pause_button = _make_button(Vector2(796, 46), Vector2(164, 42), _toggle_pause)
	_make_button(Vector2(972, 46), Vector2(116, 42), _reset).text = "Сброс"
	for index in range(simulation.crew.size()):
		var button := _make_button(Vector2(792, 174 + index * 66), Vector2(276, 64),
			_select.bind(index))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 15)
		button.icon = CREW_SPRITES[index]
		button.add_theme_constant_override("icon_max_width", 24)
		button.add_theme_constant_override("h_separation", 12)
		_crew_buttons.append(button)
		var selected_style := _button_style(Color("#1b2d3f"), simulation.crew[index].color)
		selected_style.set_border_width_all(0)
		selected_style.border_width_left = 3
		_crew_selected_styles.append(selected_style)
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"Alerts"
	_audio.volume_db = -8.0
	add_child(_audio)
	_repair_audio = AudioStreamPlayer.new()
	_repair_audio.bus = &"Interior"
	_repair_audio.stream = REPAIR_SOUND
	_repair_audio.volume_db = -5.0
	add_child(_repair_audio)
	simulation.damage_alert.connect(_play_alert)
	simulation.changed.connect(_refresh)
	if standalone:
		get_tree().paused = true
	_refresh()


func _physics_process(_delta: float) -> void:
	if standalone:
		var speed := 0.25 if Input.is_action_pressed("slow_time") else 1.0
		if simulation.simulation_speed != speed:
			simulation.simulation_speed = speed
			queue_redraw()


func _process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var repairing := (is_visible_in_tree() and not get_tree().paused
		and simulation.crew.any(func(member: DeckSimulation.CrewMember) -> bool:
			return simulation.workstation_pose(member) == DeckSimulation.WorkPose.REPAIR))
	if repairing and not _repair_audio.playing:
		_repair_audio.pitch_scale = 0.72 if simulation.simulation_speed < 1.0 else 1.0
		_repair_audio.play()
	elif not repairing and _repair_audio.playing:
		_repair_audio.stop()


func _play_alert(_tile: Vector2i, breach: bool, _message: String) -> void:
	if DisplayServer.get_name() == "headless" or (not breach and _audio.playing):
		return
	_audio.stream = BREACH_TONE if breach else DAMAGE_TONE
	_audio.play()


func _make_button(at: Vector2, extent: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.position = at
	button.size = extent
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_stylebox_override("normal", _normal_style)
	button.add_theme_stylebox_override("hover", _button_style(Color("#1c3246"), ACCENT))
	button.add_theme_stylebox_override("pressed", _button_style(Color("#234356"), ACCENT))
	button.pressed.connect(action)
	add_child(button)
	return button


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	return style


func _select(index: int) -> void:
	_selected = index
	_refresh()


func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	_refresh()


func _reset() -> void:
	_selected = 1
	_hovered_cell = DeckSimulation.INVALID_CELL
	if standalone:
		get_tree().paused = true
		simulation.reset()
	else:
		reset_requested.emit()


func _refresh() -> void:
	if not simulation.plan.is_empty():
		var size := Vector2(simulation.plan[0].length(), simulation.plan.size())
		var preferred_cell := 42.0 if simulation.layout_path == DeckSimulation.RESCUE_LAYOUT else CELL
		_deck_cell = minf(preferred_cell, minf(636.0 / size.x, 454.0 / size.y))
		_deck_origin = Vector2(389, 381) - size * _deck_cell * 0.5
	if simulation.tile_kind(_hovered_cell) == ".":
		_hovered_cell = DeckSimulation.INVALID_CELL
	var pause_title := "Продолжить" if get_tree().paused else "Пауза"
	if _pause_button.text != pause_title:
		_pause_button.text = pause_title
	for index in range(_crew_buttons.size()):
		var member := simulation.crew[index]
		var button := _crew_buttons[index]
		var title := "%s · %s\n%s\n%d / 100 HP" % [member.title, member.role, simulation.crew_status(member), ceili(member.health)]
		if button.text != title:
			button.text = title
		var selected := index == _selected
		var style := _crew_selected_styles[index] if selected else _normal_style
		if button.get_theme_stylebox("normal") != style:
			button.add_theme_color_override("font_color", member.color if selected else TEXT)
			button.add_theme_stylebox_override("normal", style)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if standalone and event.is_action_pressed("tactical_pause", false, true):
			_toggle_pause()
			get_viewport().set_input_as_handled()
		else:
			for index in range(simulation.crew.size()):
				if event.is_action_pressed("crew_%d" % (index + 1), false, true):
					_select(index)
					get_viewport().set_input_as_handled()
					break
	if event is InputEventMouse:
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var tile := Vector2i(((point - _deck_origin) / _deck_cell).floor())
		if event is InputEventMouseMotion:
			var hovered := tile if simulation.tile_kind(tile) != "." else DeckSimulation.INVALID_CELL
			if hovered != _hovered_cell:
				_hovered_cell = hovered
				queue_redraw()
			return
		if not (event is InputEventMouseButton and event.pressed):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_select_or_toggle(point, _settings.order_modifier(event))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			simulation.assign_order(_selected, tile, _settings.order_modifier(event))


func _select_or_toggle(point: Vector2, automatic: bool) -> void:
	for edge in simulation.doors:
		var start := _cell_center(Vector2i(edge.x, edge.y))
		var normal := Vector2(edge.z - edge.x, edge.w - edge.y)
		var offset := point - (start + normal * _deck_cell * 0.5)
		if absf(offset.dot(normal)) <= 6.0 and absf(offset.dot(normal.orthogonal())) <= _deck_cell * 0.5:
			if automatic:
				simulation.set_automatic(edge)
			else:
				simulation.toggle_door(edge)
			return
	var closest := -1
	var distance := _deck_cell * 0.45
	for index in range(simulation.crew.size()):
		var member := simulation.crew[index]
		if member.health <= 0.0:
			continue
		var separation := point.distance_to(_crew_point(member))
		if separation < distance:
			closest = index
			distance = separation
	if closest >= 0:
		_select(closest)


func _draw() -> void:
	_text("Палуба спасательного корабля", Vector2(32, 76), 28)
	_panel(Rect2(32, 126, 714, 504))
	_panel(Rect2(772, 126, 316, 504))
	if get_tree().paused:
		_text("На паузе", Vector2(54, 160), 15, AMBER)
	elif simulation.simulation_speed < 1.0:
		_text("Время 0,25×", Vector2(54, 160), 15, AMBER)
	if simulation.layout_path != DeckSimulation.RESCUE_LAYOUT:
		_text(simulation.layout_name, Vector2(54, 190), 15, MUTED)
	_text("Экипаж", Vector2(792, 164), 21)
	_draw_deck()

	_draw_meter("Двигатель · ЭМИ" if simulation.emp_time(simulation.engine_tile) > 0.0 else "Двигатель", minf(simulation.engine_health, simulation.hull.condition(simulation.engine_tile)), 458, AMBER)
	_draw_meter("Спасательный шлюз", simulation.airlock_progress, 499, ACCENT)
	var member := simulation.crew[_selected]
	var readout := _hovered_cell if _hovered_cell != DeckSimulation.INVALID_CELL else Vector2i(member.position.round())
	var air := simulation.hull.oxygen_at(readout)
	_draw_meter("Кислород в отсеке", air, 540, ACCENT if air >= DeckSimulation.Hull.LOW_OXYGEN else DANGER)
	var charge := simulation.power.energy / DeckSimulation.ShipPower.CAPACITY
	_draw_meter("Энергия", charge, 581, AMBER if charge >= 0.12 else DANGER)
	_text("Реактор  +%.1f ед/с%s" % [simulation.energy_recovery_rate(), " · ЭМИ" if simulation.emp_recovery_time > 0.0 else ""], Vector2(792, 618), 14, MUTED)
	_text("Отсек  %d%%" % floori(simulation.hull.condition(readout) * 100.0), Vector2(970, 618), 15, MUTED)
	if standalone:
		if simulation.engine_health >= 1.0 and simulation.airlock_progress >= 1.0:
			_text("Корабль готов к спасательной операции", Vector2(54, 608), 17, ACCENT)
		else:
			_text("Восстановите двигатель и подготовьте шлюз", Vector2(54, 608), 17)
	if not simulation.training_hint.is_empty():
		_text(simulation.training_hint, Vector2(54, 664), 15, ACCENT)
	elif not simulation.notice.is_empty():
		_text(simulation.notice, Vector2(54, 663), 15, MUTED)


func _draw_floor() -> void:
	for y in range(simulation.plan.size()):
		for x in range(simulation.plan[y].length()):
			var tile := Vector2i(x, y)
			var kind := simulation.tile_kind(tile)
			if kind == ".":
				continue
			var bounds := Rect2(_deck_origin + Vector2(tile) * _deck_cell, Vector2.ONE * _deck_cell)
			var tint := Color.WHITE
			if kind == "L":
				tint = Color("#839ab0")
			elif kind == "R":
				tint = Color("#a18b75")
			draw_texture_rect(FLOOR_SPRITES[kind], bounds, false, tint)
			var condition := simulation.hull.condition(tile)
			var air := simulation.hull.oxygen_at(tile)
			if condition < 1.0:
				draw_rect(bounds, Color(0.58, 0.22, 0.14, (1.0 - condition) * 0.36))
			var flash: float = simulation.alerts.get(simulation.hull.room_at[tile], 0.0)
			if flash > 0.0:
				var pulse := (0.16 + 0.23 * sin(flash * TAU * 2.0) ** 2) * minf(flash, 1.0)
				draw_rect(bounds, Color(1.0, 0.28, 0.14, pulse))
			if simulation.emp_time(tile) > 0.0:
				draw_rect(bounds, Color(0.18, 0.50, 0.72, 0.32))
			if air < 0.999:
				draw_rect(bounds, Color(0.25, 0.62, 0.91, (1.0 - air) * 0.57))
	# Thresholds span two tiles, so the entire floor must be drawn first.
	for y in range(simulation.plan.size()):
		for x in range(simulation.plan[y].length()):
			var tile := Vector2i(x, y)
			var kind := simulation.tile_kind(tile)
			if kind == ".":
				continue
			for direction: Vector2i in simulation.CARDINAL_STEPS:
				var neighbour := simulation.tile_kind(tile + direction)
				if neighbour == ".":
					_draw_floor_edge(tile, direction, WALL_TRIM, 5.0, 2.5)
				elif direction == Vector2i.RIGHT or direction == Vector2i.DOWN:
					var edge := simulation.edge_between(tile, tile + direction)
					var has_door := simulation.doors.has(edge)
					if neighbour != kind or edge in simulation.walls or has_door:
						_draw_floor_edge(tile, direction, FLOOR_THRESHOLD if has_door else WALL_TRIM, 5.0, 0.0)


func _draw_floor_edge(tile: Vector2i, direction: Vector2i, sprite: Texture2D,
		width: float, inset: float) -> void:
	var normal := Vector2(direction)
	var center := _cell_center(tile) + normal * (_deck_cell * 0.5 - inset)
	draw_set_transform(center, normal.angle() + PI * 0.5)
	draw_texture_rect(sprite, Rect2(-_deck_cell * 0.5, -width * 0.5, _deck_cell, width), false)
	draw_set_transform(Vector2.ZERO)


func _draw_deck() -> void:
	_draw_floor()
	for edge: Vector4i in simulation.doors:
		_draw_door(edge, simulation.doors[edge])

	_draw_module(simulation.bridge_tile, BRIDGE_SPRITE, Color("#90c8ff"))
	_draw_module(simulation.engine_tile, ENGINE_SPRITE, DANGER if simulation.engine_health < 1.0 else ACCENT)
	_draw_module(simulation.airlock_tile, AIRLOCK_SPRITE, ACCENT if simulation.airlock_progress >= 1.0 else AMBER)
	_draw_module(simulation.weapons_tile, WEAPONS_SPRITE, WEAPONS_COLOR if simulation.weapons_are_manned() else MUTED)
	if simulation.layout_path == DeckSimulation.RESCUE_LAYOUT:
		_room_label("МОСТИК", Vector2i(1, 1))
		_room_label("РЕАКТОР", Vector2i(4, 1))
		_room_label("ДВИГАТЕЛИ", Vector2i(7, 1))
		_room_label("ВООРУЖЕНИЕ", Vector2i(1, 4))
		_room_label("КИСЛОРОД", Vector2i(4, 4))
		_room_label("ШЛЮЗ", Vector2i(7, 4))
		_text("ГРУЗОВОЙ ОТСЕК", _cell_center(Vector2i(6, 8)) + Vector2(-14, 29), 12, MUTED)
	_draw_module(simulation.life_support_tile, LIFE_SUPPORT_SPRITE, ACCENT)
	_draw_module(simulation.reactor_tile, REACTOR_SPRITE, AMBER if simulation.operator_at(DeckSimulation.WorkPose.REACTOR) == null else ACCENT)
	if simulation.shield_tile != simulation.INVALID_CELL:
		var manned := simulation.operator_at(DeckSimulation.WorkPose.SHIELD) != null
		_draw_module(simulation.shield_tile, SHIELD_CONSOLE, ACCENT if manned else MUTED)
		if simulation.layout_path == DeckSimulation.RESCUE_LAYOUT:
			_room_label("ЩИТ", Vector2i(1, 6))
	for tile in simulation.hull.breaches:
		_draw_sprite(BREACH_SPRITE, _cell_center(tile), 27.0)
		_draw_sprite(AIR_LEAK, _cell_center(tile) + Vector2(3, -9) * _deck_cell / CELL, 21.0, Color(1, 1, 1, 0.65))

	for tile in simulation.cargo_seats:
		_draw_sprite(CARGO_SEAT, _cell_center(tile), 23.0)
	for passenger in simulation.passengers:
		_draw_passenger(passenger)

	var selected := simulation.crew[_selected]
	var path := PackedVector2Array([_crew_point(selected)])
	if selected.landing != simulation.INVALID_CELL:
		path.append(_cell_center(selected.landing))
	for tile in selected.route:
		path.append(_cell_center(tile))
	if path.size() > 1:
		draw_polyline(path, selected.color, 2.0, true)
		draw_circle(path[-1], 4.0 * _deck_cell / CELL, selected.color, true, -1.0, true)
	if selected.health > 0.0 and selected.blocked:
		draw_arc(_cell_center(selected.target), 16.0 * _deck_cell / CELL, 0.0, TAU, 28, DANGER, 2.0, true)

	var selected_point := _crew_point(selected)
	if selected.health > 0.0:
		draw_circle(selected_point, 11.0 * _deck_cell / CELL, Color("#142535"), true, -1.0, true)
		draw_arc(selected_point, 11.0 * _deck_cell / CELL, 0.0, TAU, 30, selected.color, 2.0, true)
	for index in range(simulation.crew.size()):
		_draw_crew_member(index)


func _draw_crew_member(index: int) -> void:
	var member := simulation.crew[index]
	if member.health <= 0.0:
		return
	var point := _crew_point(member)
	var pose := simulation.workstation_pose(member)
	if pose == DeckSimulation.WorkPose.HELM or pose == DeckSimulation.WorkPose.WEAPONS:
		_draw_sprite(HELM_SPRITES[index], point, 26.0)
		return
	var direction := member.target - member.cell
	if pose == DeckSimulation.WorkPose.REPAIR:
		var frame := int(member.repair_phase * 9.0) % 4
		var row := WORK_DIRECTIONS.find(direction) * 4 + index
		_draw_atlas_frame(REPAIR_FRAMES, point, 27.0, Vector2(frame, row))
		return
	if pose != DeckSimulation.WorkPose.NONE:
		var atlas: Texture2D = WORK_ATLASES[DeckSimulation.WorkPose.AIRLOCK][direction]
		var frame := Vector2(index, 0)
		if index == DeckSimulation.GUNNER_INDEX:
			atlas = GUNNER_WORK
			frame = Vector2(WORK_DIRECTIONS.find(direction), 1)
		_draw_atlas_frame(atlas, point, 27.0, frame)
		return
	var squeezing := member.squeeze > 0.12
	draw_set_transform(point, 0.0, Vector2(-1.0 if member.face_left else 1.0, 1.0))
	if member.landing != simulation.INVALID_CELL or squeezing:
		var frame := int(member.gait * 4.0) % 4
		_draw_atlas_frame(WALK_FRAMES, Vector2.ZERO, lerpf(21.5, 17.0, member.squeeze),
			Vector2(frame, index + 4 if squeezing else index))
	else:
		_draw_sprite(CREW_SPRITES[index], Vector2.ZERO, 21.5)
	draw_set_transform(Vector2.ZERO)


func _room_label(title: String, anchor: Vector2i) -> void:
	_text(title, _cell_center(anchor) - Vector2(_deck_cell * 0.48, _deck_cell * 0.66), 11, MUTED)


func _draw_atlas_frame(atlas: Texture2D, at: Vector2, size: float, frame: Vector2) -> void:
	var extent := Vector2.ONE * size * _deck_cell / CELL
	draw_texture_rect_region(atlas, Rect2(at - extent * 0.5, extent),
		Rect2(frame * WORK_FRAME, Vector2.ONE * WORK_FRAME))


func _draw_passenger(passenger: DeckSimulation.Passenger) -> void:
	if passenger.boarding_delay > 0.0:
		return
	var point := _deck_origin + (passenger.position + Vector2.ONE * 0.5) * _deck_cell
	var size := Vector2.ONE * 19.0 * _deck_cell / CELL
	var frame := 3 if passenger.cell == passenger.seat else int(passenger.gait * 8.0) % 3
	draw_texture_rect_region(PASSENGER, Rect2(point - size * 0.5, size), Rect2(frame * 32, 0, 32, 32))


func _draw_door(edge: Vector4i, door: DeckSimulation.Door) -> void:
	var center_a := _cell_center(Vector2i(edge.x, edge.y))
	var center_b := _cell_center(Vector2i(edge.z, edge.w))
	draw_set_transform((center_a + center_b) * 0.5, (center_b - center_a).angle(), Vector2.ONE * _deck_cell / 44.0)
	var center := Vector2.ZERO
	var openness := door.openness
	var sprite_size := DOOR_SPRITE.get_size()
	var leaf_height := lerpf(21.0, 4.0, smoothstep(0.0, 1.0, openness))
	var pixels := sprite_size.y * leaf_height / 42.0
	var half_height := sprite_size.y * 0.5
	var width := sprite_size.x * 42.0 / sprite_size.y
	var exterior := edge in simulation.hatches
	var tint := Color.WHITE.lerp(Color("#a4e3d4"), openness)
	if exterior:
		tint = AMBER if openness < 1.0 else DANGER
	elif not door.automatic and not door.wants_open:
		tint = Color("#f28b79")
	var left := center.x - width * 0.5
	draw_texture_rect_region(DOOR_SPRITE, Rect2(left, center.y - 21.0, width, leaf_height),
		Rect2(0.0, half_height - pixels, sprite_size.x, pixels), tint)
	draw_texture_rect_region(DOOR_SPRITE, Rect2(left, center.y + 21.0 - leaf_height, width, leaf_height),
		Rect2(0.0, half_height, sprite_size.x, pixels), tint)
	draw_set_transform(Vector2.ZERO)
	if exterior and openness >= 1.0:
		var interior := Vector2i(edge.x, edge.y)
		var outside := center_b
		if simulation.tile_kind(interior) == ".":
			outside = center_a
		_draw_sprite(AIR_LEAK, outside, 18.0, Color(1, 1, 1, 0.7))


func _draw_module(tile: Vector2i, sprite: Texture2D, tint: Color) -> void:
	var center := _cell_center(tile)
	var scale := _deck_cell / CELL
	var box := Rect2(center - Vector2(15, 15) * scale, Vector2(30, 30) * scale)
	var condition := simulation.hull.condition(tile)
	var rim := tint.lerp(DANGER, 1.0 - condition)
	draw_rect(box, rim.darkened(0.78))
	_draw_sprite(sprite, center, 28.0, Color.WHITE.darkened((1.0 - condition) * 0.45))
	draw_rect(box, rim, false, 1)
	if simulation.emp_time(tile) > 0.0:
		_draw_sprite(EMP_SPARK, center, 25.0, Color(1, 1, 1, 0.78))
	if condition < 0.9:
		_draw_sprite(DAMAGE_SPRITE, center + Vector2(12, -12) * scale, 12.0)
		draw_line(box.end - Vector2(28, 2) * scale, box.end - Vector2(28 - 26 * condition, 2) * scale, rim, 2.0)


func _draw_sprite(sprite: Texture2D, center: Vector2, longest_side: float, tint := Color.WHITE) -> void:
	var size := sprite.get_size()
	var extent := size * (longest_side * _deck_cell / CELL / maxf(size.x, size.y))
	draw_texture_rect(sprite, Rect2(center - extent * 0.5, extent), false, tint)


func _draw_meter(title: String, progress: float, y: float, tint: Color) -> void:
	_text(title, Vector2(792, y), 16)
	_text("%d%%" % roundi(progress * 100), Vector2(1020, y), 15, tint)
	draw_rect(Rect2(792, y + 11, 276, 6), LINE)
	if progress > 0.0:
		draw_rect(Rect2(792, y + 11, 276 * progress, 6), tint)


func _cell_center(tile: Vector2i) -> Vector2:
	return _deck_origin + (Vector2(tile) + Vector2(0.5, 0.5)) * _deck_cell


func _crew_point(member: DeckSimulation.CrewMember) -> Vector2:
	var point := _deck_origin + (member.position + Vector2(0.5, 0.5)) * _deck_cell
	if simulation.workstation_pose(member) != DeckSimulation.WorkPose.NONE:
		point += Vector2(member.target - member.cell) * 5.0 * _deck_cell / CELL
	return point


func _panel(rect: Rect2) -> void:
	draw_rect(rect, PANEL)
	draw_rect(rect, LINE, false)


func _text(value: String, at: Vector2, size: int, color: Color = TEXT) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
