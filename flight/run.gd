extends Node2D

const Voyage = preload("res://flight/voyage_state.gd")
const SpaceDisplay = preload("res://flight/space_display.gd")
const DeckDisplay = preload("res://deck/deck_view.gd")
const ComputerPanel = preload("res://ui/computer_panel.gd")
const AdventurePanel = preload("res://ui/adventure_panel.gd")
const Training = preload("res://flight/training.gd")
const SHOT_SOUND := preload("res://assets/audio/shot.wav")
const LASER_SOUND := preload("res://assets/audio/laser.wav")
const SHOT_SOUNDS := {
	Voyage.WeaponProfile.Kind.KINETIC: SHOT_SOUND,
	Voyage.WeaponProfile.Kind.MISSILE: preload("res://assets/audio/missile_launch.wav"),
	Voyage.WeaponProfile.Kind.EMP: preload("res://assets/audio/emp_discharge.wav"),
	Voyage.WeaponProfile.Kind.RAIL: preload("res://assets/audio/rail_discharge.wav"),
}

enum Mode { FLIGHT, DECK, MAP }
enum Session { CAMPAIGN, TRAINING, ARENA, ADVENTURE }

@onready var voyage: Voyage = $Voyage
@onready var space: SpaceDisplay = $Space
@onready var deck: DeckDisplay = $Deck

var session := Session.CAMPAIGN
var continue_adventure := false
var adventure_save_path := Voyage.Adventure.SAVE_PATH
var _adventure_panel: AdventurePanel
var _journal_button: Button
var _slot_button: Button
var _adventure_was_paused := false
var _defeat_panel: PanelContainer
var _defeat_title: Label
var _defeat_retry: Button
var mode := Mode.FLIGHT
var _training: Training
var _shot_audio: Dictionary[int, AudioStreamPlayer] = {}
var _laser_audio: AudioStreamPlayer
var _paused_before_map := false
var _nav: Dictionary[int, Button] = {}
var _space_pause: Button
var _slow_button: Button
var _action: Button
var _pause_overlay: ColorRect
var _computer_panel: ComputerPanel
var _computer_was_paused := false
var _pause_was_paused := false
var _settings_overlay: Control
var _computer_button: Button
var _spawn_missile_fighter: Button
var _spawn_swarm: Button
var _spawn_interceptor: Button
var _scan_button: Button
var _scan_next: Button
var _test_panel: Control
var _weapon_select: OptionButton
var _test_mass_value: Label
var _test_thrust_value: Label
var _spawn_drill: Button
var _spawn_fighter: Button
var _clear_targets: Button
var _alert_scroll: ScrollContainer
var _alert_stack: VBoxContainer
var _alerts: Array[Dictionary] = []
var _dismissed_alerts := {}
var _recruit_role: OptionButton
var _hire_test_crew: Button
var _hack_actions: OptionButton
var _hack_execute: Button
var _hack_target: Button
var _hack_ship := -1
var _slow_motion := false
var _threat_announced := false
var _threat_system := -1
@onready var _bindings = get_node("/root/GameSettings")


func _ready() -> void:
	_nav[Mode.DECK] = _button("Палуба", Vector2(500, 46), Vector2(128, 42), _navigate.bind(Mode.DECK), true)
	_nav[Mode.MAP] = _button("Карта", Vector2(640, 46), Vector2(118, 42), _navigate.bind(Mode.MAP), true)
	_space_pause = _button("Пауза", Vector2(768, 46), Vector2(174, 42), _toggle_pause)
	_slow_button = _button("0,25×", Vector2(954, 46), Vector2(134, 42), _toggle_slow, true)
	_action = _button("Стыковка", Vector2(816, 538), Vector2(252, 40), _interact)
	_computer_button = _button("Бортовой компьютер", Vector2(32, 651), Vector2(226, 34), _open_computer)
	_scan_button = _button("Сканер", Vector2(266, 651), Vector2(156, 34), _toggle_scan)
	_scan_next = _button("Другая цель", Vector2(430, 651), Vector2(136, 34), _cycle_scan)
	_weapon_select = OptionButton.new()
	_weapon_select.position = Vector2(800, 651)
	_weapon_select.size = Vector2(288, 34)
	_weapon_select.focus_mode = Control.FOCUS_NONE
	for profile in Voyage.TEST_WEAPONS:
		_weapon_select.add_item(profile.title)
	_weapon_select.item_selected.connect(voyage.select_test_weapon)
	add_child(_weapon_select)
	_build_test_panel()
	_build_run_overlays()
	_alert_scroll = ScrollContainer.new()
	_alert_scroll.position = Vector2(32, 94)
	_alert_scroll.size.x = 181.0
	_alert_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_alert_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_alert_scroll.z_index = 11
	_alert_scroll.hide()
	add_child(_alert_scroll)
	_alert_stack = VBoxContainer.new()
	_alert_stack.custom_minimum_size.x = 163.0
	_alert_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_scroll.add_child(_alert_stack)
	_alert_stack.minimum_size_changed.connect(_size_alerts)
	deck.simulation.damage_alert.connect(_show_alert)
	deck.simulation.security_alert.connect(_show_security_alert)
	_build_security_controls()
	voyage.in_arena = session == Session.ARENA
	voyage.in_training = session == Session.TRAINING
	deck.simulation.auto_crew = not voyage.in_training
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
	voyage.defeat_started.connect(_show_defeat)
	voyage.configure(deck.simulation)
	if session == Session.ADVENTURE:
		voyage.adventure_save_path = adventure_save_path
		voyage.start_adventure(continue_adventure)
	if voyage.in_training:
		_training = Training.new()
		_training.reset(voyage)
	_apply_mode()


func _navigate(destination: Mode) -> void:
	if not voyage.battle_result.is_empty() or (destination == Mode.MAP and (voyage.in_arena or voyage.in_training)):
		return
	_close_modes()
	voyage.scan_enemy = false
	if mode == destination:
		destination = Mode.FLIGHT
	if mode == Mode.MAP:
		_leave_map(destination)
		return
	if destination == Mode.MAP:
		_paused_before_map = get_tree().paused
		space.selected = -1
		get_tree().paused = true
	mode = destination
	_apply_mode()


func _leave_map(destination: Mode) -> void:
	mode = destination
	get_tree().paused = _paused_before_map
	_apply_mode()


func _close_modes() -> void:
	if is_instance_valid(_settings_overlay):
		_close_settings()
	if _pause_overlay.visible:
		_close_pause()
	_close_journal()
	_close_computer()


func _return_to_flight() -> void:
	_close_modes()
	voyage.scan_enemy = false
	if mode == Mode.MAP:
		_leave_map(Mode.FLIGHT)
	else:
		mode = Mode.FLIGHT
		_apply_mode()


func _apply_mode() -> void:
	deck.visible = mode == Mode.DECK
	space.visible = mode != Mode.DECK
	space.map_open = mode == Mode.MAP
	voyage.manual_control = mode == Mode.FLIGHT
	for index in _nav:
		_nav[index].set_pressed_no_signal(index == mode)
	_action.visible = mode != Mode.DECK and not voyage.in_arena
	_nav[Mode.MAP].disabled = voyage.in_arena or voyage.in_training
	if not voyage.manual_control:
		voyage.stop_laser()
	deck._refresh()
	_refresh()


func _refresh() -> void:
	space.refresh()
	if voyage.deck != null:
		_check_low_health()
		_check_threats()
		_refresh_security_controls()
	_nav[Mode.DECK].text = _shortcut("Палуба", "toggle_deck")
	_nav[Mode.MAP].text = _shortcut("Карта", "toggle_map")
	_space_pause.text = _shortcut("Продолжить" if get_tree().paused and mode != Mode.MAP else "Пауза", "tactical_pause")
	_slow_button.text = _shortcut("0,25×", "slow_time")
	_slow_button.set_pressed_no_signal(_slow_motion)
	_computer_button.text = _shortcut("Бортовой компьютер", "toggle_computer")
	_space_pause.disabled = mode == Mode.MAP
	var lost := not voyage.battle_result.is_empty()
	_defeat_panel.visible = lost and voyage.defeat_elapsed >= Voyage.DEFEAT_SECONDS
	if _defeat_panel.visible:
		_defeat_title.text = "Корпус разрушен" if voyage.defeat_hull else "Экипаж погиб"
		_defeat_retry.text = "С сохранения" if voyage.adventure != null else "Заново"
	_space_pause.disabled = lost or mode == Mode.MAP
	_slow_button.disabled = lost
	for index in _nav:
		_nav[index].disabled = lost or (index == Mode.MAP and (voyage.in_arena or voyage.in_training))
	_journal_button.visible = voyage.adventure != null and mode != Mode.DECK and not lost
	_journal_button.text = _shortcut("Верфь" if voyage.docked and mode == Mode.FLIGHT else "Журнал", "toggle_journal")
	_slot_button.visible = voyage.adventure != null and mode == Mode.FLIGHT and not lost
	if _slot_button.visible:
		_slot_button.text = _shortcut("%d · %s" % [voyage.adventure.equipped + 1, voyage.weapon.title], "cycle_weapon")
	_computer_button.visible = mode == Mode.FLIGHT and not lost
	_scan_button.visible = mode == Mode.FLIGHT and not lost and voyage.scanner_available() and is_instance_valid(voyage.enemy)
	_scan_button.text = _shortcut("Скрыть сканер" if voyage.scan_enemy else "Сканер", "toggle_scanner")
	_scan_next.visible = _scan_button.visible and voyage.scan_enemy and voyage.enemies.size() > 1
	_test_panel.visible = mode == Mode.FLIGHT and voyage.in_arena and not lost
	_weapon_select.visible = _test_panel.visible
	_weapon_select.select(voyage.test_weapon)
	_spawn_drill.disabled = voyage.enemies.size() >= Voyage.MAX_TEST_ENEMIES
	_spawn_fighter.disabled = _spawn_drill.disabled
	_spawn_missile_fighter.disabled = _spawn_drill.disabled
	_spawn_swarm.disabled = _spawn_drill.disabled
	_spawn_interceptor.disabled = _spawn_drill.disabled
	_clear_targets.disabled = voyage.enemies.is_empty() and voyage.drones.is_empty() and voyage.projectiles.is_empty() and voyage.wrecks.is_empty()
	_action.visible = mode != Mode.DECK and not voyage.in_arena and not lost
	if mode == Mode.DECK or lost:
		return
	if mode == Mode.MAP:
		_action.text = _shortcut("Прыжок", "confirm_jump")
		_action.disabled = not voyage.jump_blocker(space.selected).is_empty()
	else:
		if voyage.docking_time > 0.0:
			_action.text = "Идёт стыковка"
		else:
			_action.text = _shortcut("Отстыковка" if voyage.docked else "Стыковка", "dock_ship")
		var item := voyage.salvage_contact()
		if item != null:
			_action.text = _shortcut("Подобрать", "dock_ship")
			_action.disabled = get_tree().paused or voyage.velocity.length() > Voyage.Adventure.PICKUP_SPEED
		else:
			_action.disabled = get_tree().paused or not voyage.dock_blocker().is_empty()


func _select_destination(destination: int) -> void:
	if mode == Mode.MAP:
		space.selected = destination
		_refresh()


func _interact() -> void:
	if _adventure_panel.visible or _computer_panel.visible or _pause_overlay.visible:
		return
	if mode == Mode.MAP:
		if voyage.jump(space.selected):
			_leave_map(Mode.FLIGHT)
	elif mode == Mode.FLIGHT and not get_tree().paused:
		voyage.interact()


func _toggle_pause() -> void:
	if mode != Mode.MAP and voyage.battle_result.is_empty() and not _adventure_panel.visible and not _computer_panel.visible and not _pause_overlay.visible:
		get_tree().paused = not get_tree().paused
		if get_tree().paused:
			voyage.stop_laser()
		deck._refresh()
		_refresh()


func _build_run_overlays() -> void:
	_computer_panel = ComputerPanel.new()
	_computer_panel.position = Vector2(218, 125)
	_computer_panel.z_index = 10
	_computer_panel.size = Vector2(684, 415)
	_computer_panel.add_theme_stylebox_override("panel", _overlay_style())
	_computer_panel.assigned.connect(voyage.set_computer)
	_computer_panel.dismissed.connect(_close_computer)
	_computer_panel.hide()
	add_child(_computer_panel)
	_journal_button = _button("Журнал", Vector2(594, 651), Vector2(162, 34), _open_journal)
	_slot_button = _button("", Vector2(770, 651), Vector2(318, 34), voyage.cycle_weapon)
	_slot_button.tooltip_text = "Сменить активное орудие"
	_adventure_panel = AdventurePanel.new()
	_adventure_panel.position = Vector2(54, 111)
	_adventure_panel.size = Vector2(1012, 500)
	_adventure_panel.add_theme_stylebox_override("panel", _overlay_style())
	_adventure_panel.dismissed.connect(_close_journal)
	_adventure_panel.hide()
	add_child(_adventure_panel)

	_defeat_panel = PanelContainer.new()
	_defeat_panel.position = Vector2(253, 414)
	_defeat_panel.size = Vector2(298, 170)
	_defeat_panel.add_theme_stylebox_override("panel", _overlay_style())
	add_child(_defeat_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_defeat_panel.add_child(content)
	_defeat_title = Label.new()
	_defeat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_defeat_title.add_theme_font_size_override("font_size", 26)
	content.add_child(_defeat_title)
	_defeat_retry = _button("Заново", Vector2.ZERO, Vector2.ZERO, _reset)
	_defeat_retry.reparent(content, false)
	_defeat_retry.custom_minimum_size.y = 34
	var menu := _button("В меню", Vector2.ZERO, Vector2.ZERO, _return_to_menu)
	menu.reparent(content, false)
	menu.custom_minimum_size.y = 34
	_defeat_panel.hide()
	_build_pause()


func _build_pause() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.color = Color(0.025, 0.045, 0.07, 0.78)
	_pause_overlay.z_index = 20
	add_child(_pause_overlay)
	_resize_pause()
	get_viewport().size_changed.connect(_resize_pause)
	var center := CenterContainer.new()
	_pause_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
	panel.add_theme_stylebox_override("panel", _overlay_style())
	center.add_child(panel)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	panel.add_child(buttons)
	var title := Label.new()
	title.text = "Пауза"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	buttons.add_child(title)
	for item in [
		["Продолжить [Esc]", _close_pause],
		["Загрузить" if session == Session.ADVENTURE else "Сброс", _reset],
		["Настройки", _open_settings],
		["Главное меню", _return_to_menu],
		["Выйти из игры", get_tree().quit],
	]:
		var button := _button(item[0], Vector2.ZERO, Vector2.ZERO, item[1])
		button.custom_minimum_size.y = 42
		button.reparent(buttons, false)
	_pause_overlay.hide()


func _resize_pause() -> void:
	_pause_overlay.size = get_viewport_rect().size
	if is_instance_valid(_settings_overlay):
		_settings_overlay.size = _pause_overlay.size


func _open_pause() -> void:
	_pause_was_paused = get_tree().paused
	get_tree().paused = true
	voyage.stop_laser()
	_pause_overlay.show()
	_refresh()


func _close_pause() -> void:
	_pause_overlay.hide()
	get_tree().paused = _pause_was_paused
	_refresh()


func _open_settings() -> void:
	if is_instance_valid(_settings_overlay):
		return
	_settings_overlay = load("res://ui/main_menu.tscn").instantiate()
	_settings_overlay.set("settings_only", true)
	_settings_overlay.z_index = 21
	_settings_overlay.connect("settings_closed", _close_settings)
	_settings_overlay.connect("settings_escaped", _return_to_flight)
	add_child(_settings_overlay)
	_settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_resize_pause()
	_pause_overlay.hide()


func _close_settings() -> void:
	remove_child(_settings_overlay)
	_settings_overlay.queue_free()
	_settings_overlay = null
	_pause_overlay.show()


func _overlay_style() -> StyleBoxFlat:
	var style := _style(Color("#101b29"), Color("#46637b"))
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 18.0)
	return style


func _open_journal() -> void:
	if voyage.adventure == null or _adventure_panel.visible or not voyage.battle_result.is_empty():
		return
	_adventure_was_paused = get_tree().paused
	get_tree().paused = true
	voyage.stop_laser()
	_adventure_panel.present(voyage, voyage.docked and mode == Mode.FLIGHT)


func _close_journal() -> void:
	if not _adventure_panel.visible:
		return
	_adventure_panel.hide()
	get_tree().paused = _adventure_was_paused
	_refresh()


func _show_defeat() -> void:
	_close_journal()
	get_tree().paused = false
	mode = Mode.FLIGHT
	_apply_mode()


func _open_computer() -> void:
	if _computer_panel.visible or _adventure_panel.visible or _pause_overlay.visible:
		return
	_computer_was_paused = get_tree().paused
	get_tree().paused = true
	voyage.stop_laser()
	_computer_panel.present(voyage.computer)
	_refresh()


func _close_computer() -> void:
	if not _computer_panel.visible:
		return
	_computer_panel.hide()
	get_tree().paused = _computer_was_paused
	_refresh()


func _toggle_scan() -> void:
	if not voyage.scanner_available() or _computer_panel.visible:
		return
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
	_spawn_missile_fighter = _test_button("+ Ракетный", Vector2(816, 216), Vector2(163, 30),
		voyage.add_test_enemy.bind(Voyage.Opponent.MISSILE_FIGHTER))
	_spawn_swarm = _test_button("+ Роевик", Vector2(986, 216), Vector2(82, 30),
		voyage.add_test_enemy.bind(Voyage.Opponent.SWARM))
	_spawn_interceptor = _test_button("+ Перехватчик", Vector2(816, 251), Vector2(136, 30),
		voyage.add_test_enemy.bind(Voyage.Opponent.INTERCEPTOR))
	_clear_targets = _test_button("Убрать всех", Vector2(958, 251), Vector2(110, 30), voyage.clear_test_enemies)
	_damage_check("Урон игроку", 282, true)
	_damage_check("Урон противникам", 310, false)
	_test_mass_value = _label("", Vector2(816, 348), 15, _test_panel)
	_test_slider(373, 0.5, 3.0, true)
	_test_thrust_value = _label("Тяга  1.00×", Vector2(816, 410), 15, _test_panel)
	_test_slider(440, 0.25, 2.0, false)
	_update_test_physics_labels()


func _build_security_controls() -> void:
	_recruit_role = _choices(Vector2(32, 683), 202.0)
	for profile in Voyage.DeckSimulation.SPECIALTIES:
		_recruit_role.add_item(profile.role)
	_recruit_role.select(Voyage.DeckSimulation.FIGHTER)
	_hire_test_crew = _button("Нанять", Vector2(242, 683), Vector2(100, 28), _hire_on_range)
	_hack_actions = _choices(Vector2(540, 683), 344.0)
	_hack_execute = _button("Применить", Vector2(890, 683), Vector2(104, 28), _execute_hack)
	_hack_target = _button("Цель", Vector2(1000, 683), Vector2(88, 28), _cycle_scan)


func _choices(at: Vector2, width: float) -> OptionButton:
	var choices := OptionButton.new()
	choices.position = at
	choices.custom_minimum_size.x = width
	choices.size = Vector2(width, 28)
	choices.fit_to_longest_item = false
	choices.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	choices.focus_mode = Control.FOCUS_NONE
	add_child(choices)
	return choices


func _hire_on_range() -> void:
	if voyage.in_arena:
		var specialty := _recruit_role.selected
		voyage.deck.hire_member(Voyage.DeckSimulation.SPECIALTIES[specialty].role, specialty)


func _refresh_security_controls() -> void:
	var on_deck := mode == Mode.DECK and voyage.battle_result.is_empty()
	_recruit_role.visible = on_deck and voyage.in_arena
	_hire_test_crew.visible = _recruit_role.visible
	_hire_test_crew.disabled = not voyage.deck.available_berth()
	_hack_actions.visible = on_deck and voyage.deck.has_hacker()
	_hack_execute.visible = _hack_actions.visible
	_hack_target.visible = _hack_actions.visible and voyage.enemies.size() > 1
	if not _hack_actions.visible:
		return
	var hostile := voyage.enemy
	var id := hostile.get_instance_id() if is_instance_valid(hostile) else 0
	if id != _hack_ship:
		_hack_ship = id
		_hack_actions.clear()
		_add_hack_choice("Фаерволл · свой корабль", "firewall")
		if id != 0:
			_add_hack_choice("%s · компьютер" % hostile.call_sign, "computer")
			for room in hostile.deck.hull.rooms:
				var cell: Vector2i = room.tiles.front()
				_add_hack_choice("%s · %s" % [hostile.call_sign, hostile.deck.ROOM_NAMES[hostile.deck.tile_kind(cell)]], "room", cell)
			for edge: Vector4i in hostile.deck.doors:
				if edge not in hostile.deck.hatches:
					var a := Vector2i(edge.x, edge.y)
					var b := Vector2i(edge.z, edge.w)
					_add_hack_choice("Дверь %s / %s (%d, %d)" % [hostile.deck.ROOM_NAMES[hostile.deck.tile_kind(a)], hostile.deck.ROOM_NAMES[hostile.deck.tile_kind(b)], a.x, a.y], "door", edge)
		_hack_actions.select(0)
	var cooldown := voyage.deck.hack_cooldown
	_hack_actions.tooltip_text = "Фаерволл активен ещё %d с" % ceili(voyage.deck.firewall) if voyage.deck.firewall > 0.0 else "Команды хакера"
	_hack_execute.disabled = cooldown > 0.0 or not voyage.deck.hacker_available()
	_hack_execute.text = "%d с" % ceili(cooldown) if cooldown > 0.0 else "Применить"


func _add_hack_choice(title: String, kind: String, subject: Variant = null) -> void:
	_hack_actions.add_item(title)
	_hack_actions.set_item_metadata(_hack_actions.item_count - 1, [kind, subject])


func _execute_hack() -> void:
	var action: Array = _hack_actions.get_item_metadata(_hack_actions.selected)
	var success := voyage.deck.establish_firewall() if action[0] == "firewall" else voyage.hack_enemy(action[0], action[1])
	if action[0] == "firewall":
		voyage.deck.notice = "Фаерволл активен на 20 с." if success else "Хакер недоступен."
	else:
		voyage.deck.notice = "Взлом выполнен." if success else "Взлом отклонён. Проверьте дальность, энергию и защиту цели."
	deck.queue_redraw()


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


func _shortcut(title: String, action: String) -> String:
	return "%s [%s]" % [title, _bindings.key_label(action)]


func _show_alert(tile: Vector2i, breach: bool, message: String) -> void:
	var interior := voyage.deck
	var room: int = interior.hull.room_at.get(tile, -1)
	if message.begins_with("ЭМИ"):
		_notify(message, "emp", func() -> bool: return not interior.emp_timers.is_empty() or interior.emp_recovery_time > 0.0)
	elif breach:
		_notify(message, "breach:%d" % room, func() -> bool:
			for cell in interior.hull.breaches:
				if interior.hull.room_at.get(cell, -1) == room:
					return true
			return false)
		_notify("Повреждение — " + interior.ROOM_NAMES[interior.tile_kind(tile)].capitalize(), "damage:%d" % room,
			func() -> bool: return interior.hull.condition(tile) < 1.0)
	else:
		_notify(message, "damage:%d" % room, func() -> bool: return interior.hull.condition(tile) < 1.0)


func _show_security_alert(kind: String, subject: Variant, message: String) -> void:
	_notify(message, "%s:%s" % [kind, str(subject)], _security_alert_active.bind(kind, subject))


func _security_alert_active(kind: String, subject: Variant) -> bool:
	match kind:
		"boarding": return voyage._boarded()
		"computer": return voyage.deck.computer_interrupted()
		"room": return voyage.deck.hacked(subject)
		"door": return voyage.deck.doors.has(subject) and voyage.deck.doors[subject].lock_time > 0.0
	return false


func _notify(message: String, key := "", active := Callable()) -> void:
	if key.is_empty():
		key = message
	if _dismissed_alerts.has(key):
		return
	for entry in _alerts:
		if entry.key == key:
			if entry.text != message:
				entry.text = message
				entry.label.text = message
			return
	var line := Label.new()
	line.text = message
	line.custom_minimum_size.x = 147.0
	line.add_theme_font_size_override("font_size", 14)
	line.add_theme_color_override("font_color", Color("#ffbb91"))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.tooltip_text = "Щёлкните, чтобы скрыть оповещение"
	panel.add_to_group("alert_panels")
	panel.gui_input.connect(_dismiss_alert.bind(key))
	var outline := _style(Color("#142334"), Color("#6a5053"))
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		outline.set_content_margin(side, 8.0)
	for side in [SIDE_TOP, SIDE_BOTTOM]:
		outline.set_content_margin(side, 4.0)
	panel.add_theme_stylebox_override("panel", outline)
	panel.add_child(line)
	_alert_stack.add_child(panel)
	_alerts.append({"key": key, "text": message, "node": panel, "label": line, "active": active})
	_size_alerts()


func _size_alerts() -> void:
	_alert_scroll.visible = not _alerts.is_empty()
	_alert_scroll.size.y = minf(384.0, _alert_stack.get_combined_minimum_size().y)


func _dismiss_alert(event: InputEvent, key: String) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	for index in _alerts.size():
		if _alerts[index].key == key:
			var active: Callable = _alerts[index].active
			if active.is_valid():
				_dismissed_alerts[key] = active
			_remove_alert(index)
			get_viewport().set_input_as_handled()
			return


func _remove_alert(index: int) -> void:
	var node: Control = _alerts[index].node
	_alert_stack.remove_child(node)
	node.queue_free()
	_alerts.remove_at(index)
	_size_alerts()


func _check_low_health() -> void:
	for member in voyage.deck.crew:
		if member.health > 0.0 and member.health <= 30.0:
			_notify("%s · мало здоровья (%d HP)" % [member.title, ceili(member.health)], "crew:%d" % member.get_instance_id(),
				func() -> bool: return member in voyage.deck.crew and member.health > 0.0 and member.health <= 30.0)


func _check_threats() -> void:
	if _threat_system != voyage.current_system:
		_threat_system = voyage.current_system
		_threat_announced = false
	var threat := _threat_active(_threat_system)
	if threat and not _threat_announced and voyage.battle_result.is_empty():
		_threat_announced = true
		get_tree().paused = true
		if mode == Mode.MAP:
			_paused_before_map = true
		_notify("Противники обнаружены", "threat:%d" % _threat_system, _threat_active.bind(_threat_system))


func _threat_active(system: int) -> bool:
	return system == voyage.current_system and (not voyage.enemies.is_empty() or not voyage.drones.is_empty())


func _toggle_slow() -> void:
	_slow_motion = not _slow_motion
	_physics_process(0.0)


func _physics_process(_delta: float) -> void:
	var speed := 0.25 if _slow_motion else 1.0
	if voyage.simulation_speed != speed:
		voyage.simulation_speed = speed
		deck.simulation.simulation_speed = speed
		deck.queue_redraw()
		_refresh()


func _process(_delta: float) -> void:
	if _training != null and not get_tree().paused:
		_training.advance(mode == Mode.DECK)
	if DisplayServer.get_name() != "headless":
		var playing_laser := is_instance_valid(voyage.laser_beam) and not get_tree().paused
		if playing_laser and not _laser_audio.playing:
			_laser_audio.play()
		elif not playing_laser and _laser_audio.playing:
			_laser_audio.stop()
	for index in range(_alerts.size() - 1, -1, -1):
		var active: Callable = _alerts[index].active
		if active.is_valid() and not active.call():
			_remove_alert(index)
	for key in _dismissed_alerts.keys():
		if not _dismissed_alerts[key].call():
			_dismissed_alerts.erase(key)


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
	_paused_before_map = false
	space.selected = -1
	while not _alerts.is_empty():
		_remove_alert(0)
	_dismissed_alerts.clear()
	_threat_announced = false
	_threat_system = -1
	_slow_motion = false
	_physics_process(0.0)
	_adventure_panel.hide()
	_computer_panel.hide()
	_pause_overlay.hide()
	if session == Session.ADVENTURE:
		voyage.start_adventure(true)
	else:
		voyage.reset()
	if _training != null:
		_training.reset(voyage)
	deck._select(1)
	_apply_mode()


func _input(event: InputEvent) -> void:
	if is_instance_valid(_settings_overlay) and _settings_overlay.is_binding_key():
		return
	var is_key: bool = event is InputEventKey and event.pressed and not event.echo
	if is_key and event.physical_keycode == KEY_ESCAPE:
		if is_instance_valid(_settings_overlay):
			_return_to_flight()
			get_viewport().set_input_as_handled()
			return
		if mode != Mode.FLIGHT or _adventure_panel.visible or _computer_panel.visible or _pause_overlay.visible or voyage.scan_enemy:
			_return_to_flight()
		elif voyage.battle_result.is_empty():
			_open_pause()
		get_viewport().set_input_as_handled()
		return
	var unobstructed_mouse: bool = event is InputEventMouseButton and event.pressed and (event.button_index > MOUSE_BUTTON_MIDDLE or not _over_interface())
	if not is_key and not unobstructed_mouse:
		return
	for action in ["toggle_deck", "toggle_map", "toggle_computer", "toggle_journal", "toggle_scanner", "slow_time", "tactical_pause"]:
		if event.is_action_pressed(action, false, true):
			_unhandled_input(event)
			return


func _over_interface() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	while is_instance_valid(hovered):
		if hovered is BaseButton or hovered is Range or hovered is ScrollContainer or hovered is LineEdit or hovered.is_in_group("alert_panels"):
			return true
		hovered = hovered.get_parent_control()
	return false


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)
	if not pressed or not voyage.battle_result.is_empty():
		return
	if event.is_action_pressed("toggle_deck", false, true):
		_navigate(Mode.DECK)
	elif event.is_action_pressed("toggle_map", false, true):
		_navigate(Mode.MAP)
	elif event.is_action_pressed("toggle_journal", false, true):
		if _adventure_panel.visible:
			_close_journal()
		else:
			_close_modes()
			_open_journal()
	elif event.is_action_pressed("toggle_computer", false, true):
		if _computer_panel.visible:
			_close_computer()
		else:
			_close_modes()
			_open_computer()
	elif event.is_action_pressed("toggle_scanner", false, true):
		_close_modes()
		if mode != Mode.FLIGHT:
			_return_to_flight()
		_toggle_scan()
	elif event.is_action_pressed("slow_time", false, true):
		_toggle_slow()
	elif event.is_action_pressed("tactical_pause", false, true):
		_toggle_pause()
	elif event.is_action_pressed("cycle_weapon", false, true):
		voyage.cycle_weapon()
	elif event.is_action_pressed("dock_ship", false, true) and mode == Mode.FLIGHT:
		_interact()
	elif event.is_action_pressed("confirm_jump", false, true) and mode == Mode.MAP:
		_interact()
	elif event is InputEventMouseButton and mode == Mode.FLIGHT and not get_tree().paused and SpaceDisplay.FIELD.has_point(event.position) \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
		voyage.set_computer("zoom", clampi(voyage.computer.levels.zoom + step, 0, 2))
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
