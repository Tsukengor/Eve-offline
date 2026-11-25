extends Node2D

signal destination_selected(system: int)

const Voyage = preload("res://flight/voyage_state.gd")
const STARFIELD := preload("res://assets/flight/starfield.png")
const STARS := [
	preload("res://assets/flight/star_home.png"),
	preload("res://assets/flight/star_distress.png"),
	preload("res://assets/flight/star_refuge.png"),
]
const FIELD := Rect2(32.0, 124.0, 738.0, 472.0)
const SIDEBAR := Rect2(796.0, 124.0, 292.0, 472.0)
const TEXT := Color("#e3edf6")
const MUTED := Color("#9fb4c8")
const PANEL := Color("#101e2e")
const LINE := Color("#30465c")
const GRID := Color(0.47, 0.62, 0.78, 0.10)
const ACCENT := Color("#78ead0")
const AMBER := Color("#f7bf79")
const DANGER := Color("#ff8c85")

@onready var flight_view: Control = $FlightViewport
@onready var flight_field: Node2D = $FlightViewport/FlightField

var voyage: Voyage
var map_open := false
var selected := -1
var _font := ThemeDB.fallback_font


func refresh() -> void:
	flight_view.visible = not map_open
	flight_field.voyage = voyage
	flight_field.scale = Vector2.ONE * voyage.computer.zoom() if voyage != null else Vector2.ONE
	flight_field.queue_redraw()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not map_open or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		for index in range(voyage.system_count()):
			var star := _map_point(index)
			if Rect2(star - Vector2(57, 25), Vector2(114, 70)).has_point(point):
				destination_selected.emit(index)
				get_viewport().set_input_as_handled()
				return


func _draw() -> void:
	if voyage == null:
		return
	var title: String = "Карта сектора" if map_open else "Система «%s»" % Voyage.SYSTEMS[voyage.current_system].name
	if voyage.in_arena:
		title = "Полигон"
	_text(title, Vector2(32, 76), 28)
	if map_open:
		draw_texture_rect(STARFIELD, FIELD, false, Color("#8999b3"))
		_draw_grid()
	draw_rect(FIELD, LINE, false)
	draw_rect(SIDEBAR, PANEL)
	draw_rect(SIDEBAR, LINE, false)
	if map_open:
		_draw_map()
		_draw_map_sidebar()
	else:
		_draw_flight_sidebar()
	_text(voyage.training_hint if voyage.in_training else voyage.notice, Vector2(32, 630), 15, ACCENT if voyage.in_training else MUTED)


func _draw_grid() -> void:
	for x in range(72, int(FIELD.size.x), 84):
		draw_line(FIELD.position + Vector2(x, 0), FIELD.position + Vector2(x, FIELD.size.y), GRID)
	for y in range(54, int(FIELD.size.y), 84):
		draw_line(FIELD.position + Vector2(0, y), FIELD.position + Vector2(FIELD.size.x, y), GRID)


func _draw_flight_sidebar() -> void:
	var system: Dictionary = Voyage.SYSTEMS[voyage.current_system]
	if voyage.in_arena:
		_section("ПРОТИВНИКИ  %d/%d   ДРОНЫ  %d" % [voyage.enemies.size(), Voyage.MAX_TEST_ENEMIES, voyage.drones.size()], 155)
		var durability := floori(voyage.deck.hull.integrity / Voyage.DeckSimulation.Hull.HULL_MAX * 100.0)
		_draw_shield(478)
		_metric("Скорость", "%d ед/с" % ceili(voyage.velocity.length()), 499, ACCENT)
		_metric("Корпус", "%d%%" % durability, 528, DANGER if durability < 40 else TEXT)
		_metric("Орудие", voyage.weapon_status(), 557, MUTED)
		_draw_energy(582)
		return
	_section("СТАНЦИЯ", 153)
	_text("«%s»" % system.station, Vector2(816, 184), 26)
	var docked_text := "%d ед. до станции" % roundi(voyage.distance_to_station())
	if voyage.docked:
		docked_text = "Пристыкован"
	elif voyage.docking_time > 0.0:
		docked_text = "Захват причалом"
	_text(docked_text, Vector2(816, 213), 16, MUTED)
	var speed := "%d ед/с" % ceili(voyage.velocity.length())
	_metric("Скорость", speed, 255, ACCENT if voyage.velocity.length() <= Voyage.DOCK_SPEED else TEXT)
	_draw_ship_metrics(277)
	_metric("Орудие", voyage.weapon_status(), 367, MUTED)
	var hull := voyage.deck.hull.integrity / Voyage.DeckSimulation.Hull.HULL_MAX
	_metric("Корпус", "%d%%" % floori(hull * 100.0), 395, TEXT if hull > 0.4 else DANGER)
	_draw_energy(417)
	_draw_shield(436)
	_draw_objective(466)
	if voyage.battle_result.is_empty() and voyage.adventure != null and voyage.current_system == Voyage.Adventure.ION and voyage._inside_ion(voyage.ship_position) and not voyage.docked:
		_text("Ионная область: потеря энергии", Vector2(816, 527), 14, AMBER)
	elif voyage.docking_time <= 0.0 and voyage.battle_result.is_empty() and not voyage.dock_blocker().is_empty() and voyage.stage != Voyage.Stage.COMPLETE:
		_text(voyage.dock_blocker(), Vector2(816, 527), 15, AMBER)


func _draw_map() -> void:
	for route: Vector3i in voyage.routes():
		var a := _map_point(route.x)
		var b := _map_point(route.y)
		var active := (route.x == voyage.current_system and route.y == selected
			or route.y == voyage.current_system and route.x == selected)
		draw_line(a, b, ACCENT if active else LINE.lightened(0.15), 2.0 if active else 1.0, true)
		var label_at := (a + b) * 0.5
		draw_rect(Rect2(label_at - Vector2(31, 12), Vector2(62, 24)), PANEL)
		_centered("%d топл." % route.z, label_at + Vector2(0, 5), 13, ACCENT if active else MUTED)
	for index in range(voyage.system_count()):
		var at := _map_point(index)
		var active := index == voyage.current_system
		if index == selected or active:
			draw_circle(at, 24.0, Color(PANEL, 0.94), true, -1.0, true)
			draw_arc(at, 24.0, 0.0, TAU, 40, ACCENT if active else TEXT, 1.5, true)
		var sprite_index := index % STARS.size()
		if voyage.adventure != null and index in Voyage.Adventure.SECTOR_NOTES:
			sprite_index = [1, 0, 2][index - Voyage.Adventure.SCRAP]
			if not voyage.adventure.remaining(index).is_empty():
				draw_arc(at, 22.0, 0.0, TAU, 32, Color(AMBER, 0.70), 1.0, true)
		if voyage.adventure != null and voyage.adventure.has_destination(index):
			draw_arc(at, 29.0, 0.0, TAU, 32, ACCENT, 1.0, true)
		_draw_sprite(STARS[sprite_index], at, 37)
		_centered(Voyage.SYSTEMS[index].name, at + Vector2(0, 42), 20, ACCENT if active else TEXT)
		if active and voyage.adventure == null:
			_centered("Текущая система", at + Vector2(0, 61), 13, MUTED)
		elif voyage.adventure == null and index == Voyage.DISTRESS and voyage.stage == Voyage.Stage.ANSWER_DISTRESS:
			_centered("Сигнал бедствия", at + Vector2(0, 61), 13, AMBER)


func _draw_map_sidebar() -> void:
	_section("МЕЖСИСТЕМНЫЙ ПРЫЖОК", 153)
	if selected >= 0:
		_text(Voyage.SYSTEMS[selected].name, Vector2(816, 188), 26)
		var cost := voyage.route_cost(selected)
		_text("Стоимость прыжка  %d" % cost if cost > 0 else "Прямого маршрута нет",
			Vector2(816, 220), 16, MUTED)
	else:
		_text("Выберите систему", Vector2(816, 188), 22, MUTED)
	_draw_ship_metrics(267)
	if voyage.adventure != null and selected in Voyage.Adventure.SECTOR_NOTES:
		_section("ОПАСНОСТЬ СЕКТОРА", 374, AMBER)
		_wrapped(Voyage.Adventure.SECTOR_NOTES[selected], Vector2(816, 400), 248, 15)
	else:
		_draw_objective(410)
	var blocker := voyage.jump_blocker(selected)
	if selected >= 0 and voyage.route_cost(selected) > 0 and not blocker.is_empty():
		_text(blocker, Vector2(816, 518), 15, AMBER)


func _draw_ship_metrics(baseline: float) -> void:
	var engine := minf(voyage.deck.engine_health, voyage.deck.hull.condition(voyage.deck.engine_tile))
	var airlock := voyage.deck.airlock_progress
	_metric("Топливо", "%d / %d" % [voyage.fuel, voyage.fuel_capacity()], baseline, TEXT)
	_metric("Двигатель", "ЭМИ" if voyage.deck.emp_time(voyage.deck.engine_tile) > 0.0 else "%d%%" % floori(engine * 100), baseline + 31,
		ACCENT if engine >= 1.0 else DANGER)
	_metric("Шлюз", "Готов" if airlock >= 1.0 else "%d%%" % floori(airlock * 100),
		baseline + 62, ACCENT if airlock >= 1.0 else MUTED)


func _draw_shield(y: float) -> void:
	var field := voyage.body.shield
	var charge := "%d / %d" % [roundi(field.charge), roundi(field.capacity)]
	var title := "Щит"
	if field.emp_time > 0.0:
		title = "Щит · ЭМИ"
	elif not field.online:
		title = "Щит · пост свободен" if voyage.deck.emp_time(voyage.deck.shield_tile) == 0.0 else "Щит · пост отключён"
	elif field.collapsed:
		title = "Щит · зарядка"
	_metric(title, charge, y, ACCENT if field.active() else MUTED)


func _draw_energy(y: float) -> void:
	var energy := voyage.deck.power.energy
	var power := Voyage.DeckSimulation.ShipPower
	_metric("Энергия · ЭМИ" if voyage.deck.emp_recovery_time > 0.0 else "Энергия", "%d / %d" % [floori(energy), power.CAPACITY], y, AMBER if energy >= power.LOW_ENERGY else DANGER)


func _draw_objective(baseline: float) -> void:
	draw_line(Vector2(816, baseline - 23), Vector2(1068, baseline - 23), LINE)
	if not voyage.battle_result.is_empty():
		_section("ИСХОД БОЯ", baseline, ACCENT)
		_text(voyage.battle_result, Vector2(816, baseline + 30), 18, TEXT)
		return

	if voyage.adventure != null:
		_section("ПРИКЛЮЧЕНИЕ", baseline, ACCENT)
		var tickets := voyage.adventure.accepted.size() - voyage.adventure.settled.size()
		_text("Контракты  %d в работе" % tickets, Vector2(816, baseline + 27), 17)
		_text("%d кр.  ·  %d деталей" % [voyage.adventure.credits, voyage.adventure.parts], Vector2(816, baseline + 44), 15, MUTED)
		return

	if voyage.in_training:
		_section("ОБУЧЕНИЕ  %d / 8" % voyage.training_step, baseline, ACCENT)
		_text("Эвакуация завершена" if voyage.stage == Voyage.Stage.COMPLETE else "Учебный рейс", Vector2(816, baseline + 28), 17)
		return

	match voyage.stage:
		Voyage.Stage.ANSWER_DISTRESS:
			_section("СПАСАТЕЛЬНАЯ ОПЕРАЦИЯ", baseline)
			_text("Эвакуируйте экипаж", Vector2(816, baseline + 28), 17)
			_text("станции «Каскад» в Искре.", Vector2(816, baseline + 50), 17)
		Voyage.Stage.DELIVER_SURVIVORS:
			_section("НА БОРТУ  %d ЧЕЛ." % voyage.survivors_onboard, baseline)
			_text("Доставьте выживших", Vector2(816, baseline + 28), 17)
			_text("в Гавань или на Рубеж.", Vector2(816, baseline + 50), 17)
		Voyage.Stage.COMPLETE:
			_section("РЕЙС ЗАВЕРШЁН", baseline, ACCENT)
			_text("Спасено %d человек" % voyage.delivered, Vector2(816, baseline + 32), 21, ACCENT)


func _wrapped(value: String, at: Vector2, width: int, size: int) -> void:
	draw_multiline_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, MUTED)


func _metric(label: String, value: String, y: float, tint: Color) -> void:
	_text(label, Vector2(816, y), 16, MUTED)
	var width := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	_text(value, Vector2(1068 - width, y), 17, tint)


func _section(label: String, y: float, tint: Color = MUTED) -> void:
	_text(label, Vector2(816, y), 13, tint)


func _map_point(index: int) -> Vector2:
	var point: Vector2 = Voyage.Adventure.MAP_POINTS[index] if voyage.adventure != null else Voyage.SYSTEMS[index].map
	return FIELD.position + point


func _draw_sprite(sprite: Texture2D, center: Vector2, longest: float, tint := Color.WHITE) -> void:
	var size := sprite.get_size()
	var extent := size * (longest / maxf(size.x, size.y))
	draw_texture_rect(sprite, Rect2(center - extent * 0.5, extent), false, tint)


func _centered(value: String, at: Vector2, size: int, color: Color) -> void:
	var width := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(value, at - Vector2(width * 0.5, 0), size, color)


func _text(value: String, at: Vector2, size: int, color: Color = TEXT) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
