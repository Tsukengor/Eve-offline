extends Node

const FILE := "user://settings.cfg"
const DEFAULTS := {
	"flight_turn_left": KEY_A, "flight_turn_right": KEY_D, "flight_thrust": KEY_W,
	"flight_brake": KEY_SHIFT, "flight_stabilize": KEY_Q, "flight_fire": KEY_F, "cycle_weapon": KEY_X,
	"slow_time": KEY_T, "toggle_deck": KEY_TAB, "toggle_map": KEY_M, "tactical_pause": KEY_SPACE, "toggle_computer": KEY_B, "toggle_journal": KEY_J, "toggle_scanner": KEY_C,
	"dock_ship": KEY_E, "confirm_jump": KEY_ENTER, "crew_1": KEY_1, "crew_2": KEY_2,
	"crew_3": KEY_3, "crew_4": KEY_4, "crew_5": KEY_5, "crew_6": KEY_6, "order_modifier": KEY_SHIFT,
}
const LABELS := {
	"flight_turn_left": "Поворот влево", "flight_turn_right": "Поворот вправо", "flight_thrust": "Маршевая тяга",
	"flight_brake": "Торможение", "flight_stabilize": "Стабилизация", "flight_fire": "Огонь", "cycle_weapon": "Смена орудия",
	"slow_time": "Замедлить время", "toggle_deck": "Полёт / палуба", "toggle_map": "Карта",
	"tactical_pause": "Тактическая пауза", "toggle_computer": "Бортовой компьютер",
	"toggle_journal": "Журнал / верфь", "toggle_scanner": "Сканер", "dock_ship": "Стыковка", "confirm_jump": "Подтвердить прыжок",
	"crew_1": "Выбрать пилота", "crew_2": "Выбрать инженера", "crew_3": "Выбрать спасателя", "crew_4": "Выбрать наводчика",
	"crew_5": "Выбрать пятого члена экипажа", "crew_6": "Выбрать шестого члена экипажа",
	"order_modifier": "Модификатор приказов",
}
const BUSES := {"Master": "Общая громкость", "Music": "Музыка", "Weapons": "Выстрелы",
	"Alerts": "Оповещения", "Interior": "Работа экипажа"}

var bindings := DEFAULTS.duplicate()
var volumes := {"Master": 1.0, "Music": 0.75, "Weapons": 1.0, "Alerts": 1.0, "Interior": 1.0}


func _ready() -> void:
	load_settings()


func load_settings(path := FILE) -> void:
	bindings = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	config.load(path)
	var candidate := DEFAULTS.duplicate()
	for action in candidate:
		var value: Variant = config.get_value("keyboard", action, candidate[action])
		if value is int and _valid_binding(value):
			candidate[action] = value
	for added in ["cycle_weapon", "crew_5", "crew_6", "toggle_computer", "toggle_journal", "toggle_scanner"]:
		if config.has_section_key("keyboard", added):
			continue
		for key in [DEFAULTS[added], KEY_C, KEY_V, KEY_B, KEY_G, KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P,
				KEY_H, KEY_J, KEY_K, KEY_L, KEY_Z, KEY_N, KEY_7, KEY_8, KEY_9, KEY_0, KEY_F2, KEY_F3]:
			if _conflict(candidate, added, key).is_empty():
				candidate[added] = key
				break
	var valid := true
	for action in candidate:
		if not _conflict(candidate, action, candidate[action]).is_empty():
			valid = false
			break
	if valid:
		bindings = candidate
	for action in bindings:
		_apply_binding(action)
	for bus in BUSES:
		var default_volume := 0.75 if bus == "Music" else 1.0
		var value: Variant = config.get_value("audio", bus, default_volume)
		set_volume(bus, float(value) if value is float or value is int else default_volume)


func save_settings(path := FILE) -> Error:
	var config := ConfigFile.new()
	for action in bindings:
		config.set_value("keyboard", action, bindings[action])
	for bus in volumes:
		config.set_value("audio", bus, volumes[bus])
	return config.save(path)


func key_label(action: String) -> String:
	var code: int = bindings[action]
	if code >= 0:
		return OS.get_keycode_string(code)
	match -code:
		1: return "ЛКМ"
		2: return "ПКМ"
		3: return "СКМ"
		4: return "Колесо ↑"
		5: return "Колесо ↓"
		6: return "Колесо ←"
		7: return "Колесо →"
		_: return "Мышь %d" % (-code - 4)


func rebind(action: String, code: int) -> String:
	if not bindings.has(action) or not _valid_binding(code):
		return "Эта клавиша недоступна."
	var conflict := _conflict(bindings, action, code)
	if not conflict.is_empty():
		return "Клавиша уже назначена действию «%s»." % LABELS[conflict]
	var old: int = bindings[action]
	if old != code:
		Input.action_release(action)
		bindings[action] = code
		_apply_binding(action)
	return ""


func _conflict(keys: Dictionary, action: String, code: int) -> String:
	for other in keys:
		if other == action or keys[other] != code:
			continue
		if code == KEY_SHIFT and action in ["flight_brake", "order_modifier"] and other in ["flight_brake", "order_modifier"]:
			continue
		return other
	return ""


func _apply_binding(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var code: int = bindings[action]
	if code < 0:
		var button := InputEventMouseButton.new()
		button.button_index = -code
		InputMap.action_add_event(action, button)
	else:
		var key := InputEventKey.new()
		key.physical_keycode = code
		InputMap.action_add_event(action, key)


func _valid_binding(code: int) -> bool:
	if code < 0:
		return code >= -32
	return code != KEY_ESCAPE and code != KEY_NONE and not OS.get_keycode_string(code).is_empty()


func order_modifier(event: InputEventMouse) -> bool:
	return event.shift_pressed if bindings["order_modifier"] == KEY_SHIFT else Input.is_action_pressed("order_modifier")


func reset_keyboard() -> void:
	bindings = DEFAULTS.duplicate()
	for action in bindings:
		Input.action_release(action)
		_apply_binding(action)


func set_volume(bus: String, level: float) -> void:
	if not BUSES.has(bus):
		return
	var safe := clampf(level, 0.0, 1.0) if is_finite(level) else 1.0
	volumes[bus] = safe
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_mute(index, safe <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(safe, 0.0001)))
