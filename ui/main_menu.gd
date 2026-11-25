extends Control

const Settings = preload("res://ui/game_settings.gd")
@onready var _settings: Settings = get_node("/root/GameSettings")

const Run = preload("res://flight/run.gd")
const RUN := preload("res://flight/run.tscn")
const SHIP := preload("res://assets/flight/rescue_ship.png")
const STARS := preload("res://assets/flight/starfield.png")
const INK := Color("#e3edf6")
const MINT := Color("#78ead0")
const DIM := Color("#a1b4c9")

var _panel: VBoxContainer
var _binding_buttons: Dictionary = {}
var _capturing := ""
var _status: Label
var _page := "main"
var settings_only := false
signal settings_closed
signal settings_escaped


func _ready() -> void:
	if settings_only:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_show_settings()
	else:
		get_tree().paused = false
		_show_main()


func _draw() -> void:
	draw_texture_rect(STARS, Rect2(Vector2.ZERO, size), false, Color("#526e8d"))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.06, 0.10, 0.60))
	if _page in ["main", "campaign"]:
		var center := size * Vector2(0.71, 0.53)
		var accent := Color("#344b63")
		draw_circle(center, 148, accent, false, 1, true)
		draw_circle(center, 198, Color(accent, 0.6), false, 1, true)
		draw_line(center - Vector2(216, 0), center + Vector2(216, 0), accent)
		draw_line(center - Vector2(0, 216), center + Vector2(0, 216), accent)
		var texture_size := SHIP.get_size()
		var extent := texture_size / maxf(texture_size.x, texture_size.y) * 282.0
		draw_set_transform(center, PI * 0.28)
		draw_texture_rect(SHIP, Rect2(-extent / 2.0, extent), false)
		draw_set_transform(Vector2.ZERO)
	draw_line(Vector2(66, size.y - 56), Vector2(size.x - 66, size.y - 56), Color("#31465a"))


func _new_panel(page: String, title: String, width := 385.0) -> void:
	_page = page
	_capturing = ""
	_binding_buttons.clear()
	if is_instance_valid(_panel):
		remove_child(_panel)
		_panel.queue_free()
	_panel = VBoxContainer.new()
	_panel.position = Vector2(66, 85)
	_panel.size.x = width
	_panel.add_theme_constant_override("separation", 9)
	add_child(_panel)
	_panel.add_child(_text(title, 44, INK))
	queue_redraw()


func _show_main() -> void:
	_new_panel("main", "Eve Offline")
	_menu_button(_panel, "Кампания", _show_campaign)
	_menu_button(_panel, "Приключение", _show_adventure)
	_menu_button(_panel, "Обучение", _start.bind(Run.Session.TRAINING))
	_menu_button(_panel, "Полигон", _start.bind(Run.Session.ARENA))
	_menu_button(_panel, "Настройки", _show_settings)
	_menu_button(_panel, "Выход", get_tree().quit)


func _show_campaign() -> void:
	_new_panel("campaign", "Кампания", 480.0)
	_menu_button(_panel, "Спасение станции «Каскад»", _start.bind(Run.Session.CAMPAIGN))
	_menu_button(_panel, "Назад", _show_main)


func _show_adventure() -> void:
	_new_panel("adventure", "Приключение", 460.0)
	var saved := FileAccess.file_exists(Run.Voyage.Adventure.SAVE_PATH)
	var resume := _menu_button(_panel, "Продолжить", _start.bind(Run.Session.ADVENTURE, true))
	resume.disabled = not saved
	var begin := _confirm_new_adventure if saved else _start.bind(Run.Session.ADVENTURE)
	_menu_button(_panel, "Новый рейс", begin)
	_menu_button(_panel, "Назад", _show_main)


func _confirm_new_adventure() -> void:
	_new_panel("adventure_reset", "Новый рейс", 490.0)
	_panel.add_child(_text("Новый рейс заменит сохранение приключения.", 17, DIM))
	_menu_button(_panel, "Начать новый рейс", _start.bind(Run.Session.ADVENTURE))
	_menu_button(_panel, "Назад", _show_adventure)


func _show_settings() -> void:
	_new_panel("settings", "Настройки", 970.0)
	var rows := HBoxContainer.new()
	rows.add_theme_constant_override("separation", 30)
	_panel.add_child(rows)
	var keyboard := VBoxContainer.new()
	keyboard.custom_minimum_size.x = 490
	rows.add_child(keyboard)
	keyboard.add_child(_text("Клавиатура и мышь", 24, MINT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(490, 335)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	keyboard.add_child(scroll)
	var bindings := VBoxContainer.new()
	bindings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(bindings)
	for action in Settings.LABELS:
		var row := HBoxContainer.new()
		bindings.add_child(row)
		var label := _text(Settings.LABELS[action], 16, INK)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_binding_buttons[action] = _menu_button(row, _settings.key_label(action), _capture.bind(action), Vector2(118, 36))
	_menu_button(keyboard, "Сбросить клавиши", _reset_keys, Vector2(100, 38))
	var sound := VBoxContainer.new()
	sound.custom_minimum_size.x = 340
	sound.add_theme_constant_override("separation", 11)
	rows.add_child(sound)
	sound.add_child(_text("Звук", 24, MINT))
	for bus in Settings.BUSES:
		var label := _text("", 17, INK)
		label.text = "%s   %d%%" % [Settings.BUSES[bus], roundi(_settings.volumes[bus] * 100)]
		sound.add_child(label)
		var slider := HSlider.new()
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = _settings.volumes[bus]
		slider.value_changed.connect(_volume_changed.bind(bus, label))
		sound.add_child(slider)
	_status = _text("Выбери действие, затем нажми клавишу или кнопку мыши.", 15, DIM)
	_panel.add_child(_status)
	_menu_button(_panel, "Назад", _close_settings, Vector2(130, 42)).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _close_settings() -> void:
	if settings_only:
		settings_closed.emit()
	else:
		_show_main()


func _volume_changed(value: float, bus: String, label: Label) -> void:
	_settings.set_volume(bus, value)
	_settings.save_settings()
	label.text = "%s   %d%%" % [Settings.BUSES[bus], roundi(value * 100)]


func _capture(action: String) -> void:
	_capturing = action
	_status.text = "Назначить «%s». Нажми клавишу или кнопку мыши. Esc отменяет." % Settings.LABELS[action]


func _reset_keys() -> void:
	_capturing = ""
	_settings.reset_keyboard()
	_settings.save_settings()
	_show_settings()
	_status.text = "Клавиши восстановлены."


func is_binding_key() -> bool:
	return not _capturing.is_empty()


func _input(event: InputEvent) -> void:
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	var mouse: bool = event is InputEventMouseButton and event.pressed
	if not key and not mouse:
		return
	if not _capturing.is_empty():
		get_viewport().set_input_as_handled()
		var code: int = event.physical_keycode if key else -event.button_index
		if code == KEY_ESCAPE:
			_capturing = ""
			_status.text = "Назначение отменено."
			return
		var error := _settings.rebind(_capturing, code)
		if not error.is_empty():
			_status.text = error + " Выбери другую клавишу."
			return
		_binding_buttons[_capturing].text = _settings.key_label(_capturing)
		_capturing = ""
		_status.text = "Назначение сохранено."
		_settings.save_settings()
	elif key and event.physical_keycode == KEY_ESCAPE and _page != "main":
		get_viewport().set_input_as_handled()
		if settings_only:
			settings_escaped.emit()
		else:
			_close_settings()


func _start(session: Run.Session, resume := false) -> void:
	var game: Run = RUN.instantiate()
	game.session = session
	game.continue_adventure = resume
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	queue_free()


func _text(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _menu_button(parent: Container, title: String, action: Callable, extent := Vector2(200, 54)) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = extent
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#122438") if state == "normal" else Color("#203c52")
		style.border_color = Color("#365570") if state == "normal" else MINT
		style.set_border_width_all(1)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
