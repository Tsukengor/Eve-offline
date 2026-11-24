extends Node2D

const Voyage = preload("res://flight/voyage_state.gd")
const SpaceDisplay = preload("res://flight/space_display.gd")
const DeckDisplay = preload("res://deck/deck_view.gd")
const Training = preload("res://flight/training.gd")
const SHOT_SOUND := preload("res://assets/audio/shot.wav")
const LASER_SOUND := preload("res://assets/audio/laser.wav")
const SHOT_SOUNDS := {
	Voyage.WeaponProfile.Kind.KINETIC: SHOT_SOUND,
	Voyage.WeaponProfile.Kind.MISSILE: preload("res://assets/audio/missile_launch.wav"),
	Voyage.WeaponProfile.Kind.EMP: preload("res://assets/audio/emp_discharge.wav"),
	Voyage.WeaponProfile.Kind.RAIL: preload("res://assets/audio/rail_discharge.wav"),
	Voyage.WeaponProfile.Kind.FLAK: preload("res://assets/audio/flak_shot.wav"),
	Voyage.WeaponProfile.Kind.PUSH: preload("res://assets/audio/impulse_shot.wav"),
}

enum Mode { FLIGHT, DECK, MAP }
enum Session { CAMPAIGN, TRAINING, ARENA }

@onready var voyage: Voyage = $Voyage
@onready var space: SpaceDisplay = $Space
@onready var deck: DeckDisplay = $Deck

var session := Session.CAMPAIGN
var mode := Mode.FLIGHT
var _training: Training
var _shot_audio: Dictionary[int, AudioStreamPlayer] = {}
var _laser_audio: AudioStreamPlayer
var _mode_before_map := Mode.FLIGHT
var _paused_before_map := false
var _nav: Array[Button] = []
var _space_pause: Button
var _space_reset: Button
var _action: Button
var _menu_button: Button
var _computer_button: Button
var _flak_button: Button
var _spawn_missile_fighter: Button
var _scan_button: Button
var _scan_next: Button
var _test_panel: Control
var _weapon_select: OptionButton
var _test_mass_value: Label
var _test_thrust_value: Label
var _spawn_drill: Button
var _spawn_fighter: Button
var _clear_targets: Button
var _alert: Label
var _alert_time := 0.0


func _ready() -> void:
	var labels := ["Полёт", "Палуба", "Карта"]
	for index in range(labels.size()):
		_nav.append(_button(labels[index], Vector2(496 + index * 97, 46), Vector2(90, 42),
			_navigate.bind(index), true))
	_menu_button = _button("Меню", Vector2(388, 46), Vector2(100, 42), _return_to_menu)
	_space_pause = _button("Пауза", Vector2(796, 46), Vector2(164, 42), _toggle_pause)
	_space_reset = _button("Сброс", Vector2(972, 46), Vector2(116, 42), _reset)
	_action = _button("Стыковка", Vector2(816, 538), Vector2(252, 40), _interact)
	_computer_button = _button("Борткомпьютер", Vector2(32, 651), Vector2(200, 34), _toggle_computer)
	_scan_button = _button("Сканер", Vector2(244, 651), Vector2(165, 34), _toggle_scan)
	_flak_button = _button("ПВО: выкл", Vector2(567, 651), Vector2(144, 34), _toggle_flak)
	_scan_next = _button("Другая цель", Vector2(422, 651), Vector2(135, 34), _cycle_scan)
	_weapon_select = OptionButton.new()
	_weapon_select.position = Vector2(800, 651)
	_weapon_select.size = Vector2(288, 34)
	_weapon_select.focus_mode = Control.FOCUS_NONE
	for profile in Voyage.TEST_WEAPONS:
		_weapon_select.add_item(profile.title)
	_weapon_select.item_selected.connect(voyage.select_test_weapon)
	add_child(_weapon_select)
	_build_test_panel()
	_alert = _label("", Vector2(54, 173), 17, self)
	_alert.add_theme_color_override("font_color", Color("#ffab8c"))
	_alert.add_theme_color_override("font_shadow_color", Color("#090e15"))
	_alert.add_theme_constant_override("shadow_offset_y", 2)
	deck.simulation.damage_alert.connect(_show_alert)
	voyage.in_arena = session == Session.ARENA
	voyage.in_training = session == Session.TRAINING
	for kind in SHOT_SOUNDS:
		var audio := AudioStreamPlayer.new()
		audio.bus = &"Weapons"
		audio.stream = SHOT_SOUNDS[kind]
		audio.max_polyphony = 8
		_shot_audio[kind] = audio
		add_child(audio)
	_laser_audio = AudioStreamPlayer.new()
	_laser_audio.bus = &"Weapons"
	var loop := LASER_SOUND.duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
	_laser_audio.stream = loop
	add_child(_laser_audio)
	voyage.weapon_fired.connect(_play_shot)
	space.voyage = voyage
	space.destination_selected.connect(_select_destination)
	deck.reset_requested.connect(_reset)
	voyage.changed.connect(_refresh)
	voyage.configure(deck.simulation)
	if voyage.in_training:
		_training = Training.new()
		_training.reset(voyage)
	_apply_mode()


func _navigate(destination: Mode) -> void:
	if destination == Mode.MAP:
		if voyage.in_arena or voyage.in_training:
			return
		if mode == Mode.MAP:
			_leave_map(_mode_before_map)
			return
		_mode_before_map = mode
		_paused_before_map = get_tree().paused
		mode = Mode.MAP
		space.selected = -1
		get_tree().paused = true
	elif mode == Mode.MAP:
		_leave_map(destination)
		return
	else:
		mode = destination
	_apply_mode()


func _leave_map(destination: Mode) -> void:
	mode = destination
	get_tree().paused = _paused_before_map
	_apply_mode()


func _apply_mode() -> void:
	deck.visible = mode == Mode.DECK
	space.visible = mode != Mode.DECK
	space.map_open = mode == Mode.MAP
	voyage.manual_control = mode == Mode.FLIGHT
	for index in range(_nav.size()):
		_nav[index].set_pressed_no_signal(index == mode)
	_space_pause.visible = mode == Mode.FLIGHT
	_space_reset.visible = mode != Mode.DECK
	_action.visible = mode != Mode.DECK and not voyage.in_arena
	_menu_button.position = Vector2(972, 651) if mode == Mode.DECK else Vector2(388, 46)
	_nav[Mode.MAP].disabled = voyage.in_arena or voyage.in_training
	if not voyage.manual_control:
		voyage.stop_laser()
	deck._refresh()
	_refresh()


func _refresh() -> void:
	space.refresh()
	_computer_button.visible = mode == Mode.FLIGHT
	_computer_button.text = "БК: включён" if voyage.flight_computer else "БК: выключен"
	_flak_button.visible = mode == Mode.FLIGHT
	_flak_button.text = "ПВО: авто" if voyage.flak_enabled else "ПВО: выкл"
	if voyage.flak_enabled and not voyage.flight_computer:
		_flak_button.text = "ПВО: ждёт БК"
	_scan_button.visible = mode == Mode.FLIGHT and is_instance_valid(voyage.enemy)
	_scan_button.text = "Скрыть сканер" if voyage.scan_enemy else "Сканер"
	_scan_next.visible = _scan_button.visible and voyage.scan_enemy and voyage.enemies.size() > 1
	_test_panel.visible = mode == Mode.FLIGHT and voyage.in_arena
	_weapon_select.visible = _test_panel.visible
	_weapon_select.select(voyage.test_weapon)
	_spawn_drill.disabled = voyage.enemies.size() >= Voyage.MAX_TEST_ENEMIES
	_spawn_fighter.disabled = _spawn_drill.disabled
	_spawn_missile_fighter.disabled = _spawn_drill.disabled
	_clear_targets.disabled = voyage.enemies.is_empty() and voyage.projectiles.is_empty() and voyage.wrecks.is_empty()
	_alert.visible = mode == Mode.FLIGHT and _alert_time > 0.0
	if mode == Mode.DECK:
		return
	if mode == Mode.MAP:
		_action.text = "Прыжок"
		_action.disabled = not voyage.jump_blocker(space.selected).is_empty()
	else:
		_space_pause.text = "Продолжить" if get_tree().paused else "Пауза"
		if voyage.docking_time > 0.0:
			_action.text = "Идёт стыковка"
		else:
			_action.text = "Отстыковка" if voyage.docked else "Стыковка"
		_action.disabled = get_tree().paused or not voyage.dock_blocker().is_empty()


func _select_destination(destination: int) -> void:
	if mode == Mode.MAP:
		space.selected = destination
		_refresh()


func _interact() -> void:
	if mode == Mode.MAP:
		if voyage.jump(space.selected):
			_leave_map(Mode.FLIGHT)
	elif mode == Mode.FLIGHT and not get_tree().paused:
		voyage.toggle_docking()


func _toggle_pause() -> void:
	if mode != Mode.MAP:
		get_tree().paused = not get_tree().paused
		if get_tree().paused:
			voyage.stop_laser()
		deck._refresh()
		_refresh()


func _toggle_computer() -> void:
	voyage.flight_computer = not voyage.flight_computer
	_refresh()


func _toggle_flak() -> void:
	voyage.flak_enabled = not voyage.flak_enabled
	_refresh()


func _toggle_scan() -> void:
	voyage.scan_enemy = not voyage.scan_enemy
	_refresh()


func _cycle_scan() -> void:
	if not voyage.enemies.is_empty():
		voyage.scan_index = (voyage.scan_index + 1) % voyage.enemies.size()
		_refresh()


func _build_test_panel() -> void:
	_test_panel = Control.new()
	_test_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_test_panel)
	_spawn_drill = _test_button("+ Бур", Vector2(816, 177), Vector2(120, 33),
		voyage.add_test_enemy.bind(Voyage.Opponent.DRILL))
	_spawn_fighter = _test_button("+ Истребитель", Vector2(946, 177), Vector2(122, 33),
		voyage.add_test_enemy.bind(Voyage.Opponent.FIGHTER))
	_spawn_missile_fighter = _test_button("+ Ракетный истребитель", Vector2(816, 216), Vector2(252, 30),
		voyage.add_test_enemy.bind(Voyage.Opponent.MISSILE_FIGHTER))
	_clear_targets = _test_button("Убрать противников", Vector2(816, 251), Vector2(252, 30), voyage.clear_test_enemies)
	_damage_check("Урон игроку", 282, true)
	_damage_check("Урон противникам", 310, false)
	_test_mass_value = _label("", Vector2(816, 348), 15, _test_panel)
	_test_slider(373, 0.5, 3.0, true)
	_test_thrust_value = _label("Тяга  1.00×", Vector2(816, 410), 15, _test_panel)
	_test_slider(440, 0.25, 2.0, false)
	_update_test_physics_labels()


func _test_button(title: String, at: Vector2, size: Vector2, action: Callable) -> Button:
	var button := _button(title, at, size, action)
	button.reparent(_test_panel)
	button.add_theme_font_size_override("font_size", 14)
	return button


func _damage_check(title: String, y: float, player: bool) -> void:
	var box := CheckButton.new()
	box.position = Vector2(816, y)
	box.size = Vector2(252, 28)
	box.text = title
	box.button_pressed = true
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(func(enabled: bool) -> void:
		if player:
			voyage.set_test_damage(enabled, voyage.enemy_damage)
		else:
			voyage.set_test_damage(voyage.player_damage, enabled))
	_test_panel.add_child(box)


func _test_slider(y: float, lower: float, upper: float, mass: bool) -> void:
	var slider := HSlider.new()
	slider.position = Vector2(818, y)
	slider.size = Vector2(247, 24)
	slider.min_value = lower
	slider.max_value = upper
	slider.step = 0.05
	slider.value = 1.0
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float) -> void:
		if mass:
			voyage.set_test_physics(value, voyage.test_thrust)
		else:
			voyage.set_test_physics(voyage.test_mass, value)
		_update_test_physics_labels())
	_test_panel.add_child(slider)


func _update_test_physics_labels() -> void:
	_test_mass_value.text = "Масса  %.2f×  (%.1f)" % [voyage.test_mass, Voyage.RESCUE_MODEL.mass * voyage.test_mass]
	_test_thrust_value.text = "Тяга  %.2f×" % voyage.test_thrust


func _label(value: String, at: Vector2, font_size: int, parent: Node) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _show_alert(_tile: Vector2i, _breach: bool, message: String) -> void:
	_alert.text = message
	_alert_time = 2.7
	_alert.visible = mode == Mode.FLIGHT


func _physics_process(_delta: float) -> void:
	var speed := 0.25 if Input.is_action_pressed("slow_time") else 1.0
	if voyage.simulation_speed != speed:
		voyage.simulation_speed = speed
		deck.simulation.simulation_speed = speed
		deck.queue_redraw()
		_refresh()


func _process(delta: float) -> void:
	if _training != null and not get_tree().paused:
		_training.advance(mode == Mode.DECK)
	if DisplayServer.get_name() != "headless":
		var playing_laser := is_instance_valid(voyage.laser_beam) and not get_tree().paused
		if playing_laser and not _laser_audio.playing:
			_laser_audio.play()
		elif not playing_laser and _laser_audio.playing:
			_laser_audio.stop()
	if _alert_time > 0.0:
		_alert_time = maxf(_alert_time - delta, 0.0)
		if _alert_time == 0.0:
			_alert.hide()


func _play_shot(kind: int) -> void:
	if DisplayServer.get_name() != "headless" and _shot_audio.has(kind):
		_shot_audio[kind].play()


func _return_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _toggle_arena() -> void:
	voyage.in_arena = not voyage.in_arena
	_reset()


func _reset() -> void:
	get_tree().paused = false
	mode = Mode.FLIGHT
	_mode_before_map = Mode.FLIGHT
	_paused_before_map = false
	space.selected = -1
	_alert_time = 0.0
	voyage.reset()
	if _training != null:
		_training.reset(voyage)
	deck._select(1)
	_apply_mode()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.is_action_pressed("toggle_deck", false, true):
		_navigate(Mode.FLIGHT if mode == Mode.DECK else Mode.DECK)
	elif event.is_action_pressed("toggle_map", false, true):
		_navigate(Mode.MAP)
	elif event.physical_keycode == KEY_ESCAPE and mode == Mode.MAP:
		_leave_map(_mode_before_map)
	elif event.is_action_pressed("tactical_pause", false, true):
		_toggle_pause()
	elif event.is_action_pressed("dock_ship", false, true) and mode == Mode.FLIGHT:
		_interact()
	elif event.is_action_pressed("confirm_jump", false, true) and mode == Mode.MAP:
		_interact()
	else:
		return
	get_viewport().set_input_as_handled()



func _button(title: String, at: Vector2, size: Vector2, callback: Callable, toggle := false) -> Button:
	var button := Button.new()
	button.text = title
	button.position = at
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.toggle_mode = toggle
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal", _style(Color("#101e2e"), Color("#30465c")))
	button.add_theme_stylebox_override("hover", _style(Color("#20374c"), Color("#78ead0")))
	button.add_theme_stylebox_override("pressed", _style(Color("#213c50"), Color("#78ead0")))
	button.add_theme_stylebox_override("disabled", _style(Color("#141e2a"), Color("#263446")))
	button.pressed.connect(callback)
	add_child(button)
	return button


func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	return style
