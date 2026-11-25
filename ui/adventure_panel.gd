extends PanelContainer

const Voyage = preload("res://flight/voyage_state.gd")
const Adventure = Voyage.Adventure

signal dismissed

var voyage: Voyage
var _body: VBoxContainer
var _docked_at_open := false
var _tab := 0
var _show_completed := false
var _sort := 0
var _type := 0
var _status := 0


func present(game: Voyage, workshop: bool) -> void:
	voyage = game
	_docked_at_open = voyage.docked
	_tab = 1 if workshop and _docked_at_open else 0
	_rebuild()
	show()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	add_child(content)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	content.add_child(top)
	var tabs := [
		_button(top, "Контракты", _open_tab.bind(0)),
		_button(top, "Верфь", _open_tab.bind(1), _docked_at_open),
		_button(top, "Экипаж", _open_tab.bind(2), _docked_at_open),
	]
	tabs[_tab].add_theme_stylebox_override("normal", _button_style(Color("#203c4e"), Color("#78ead0")))
	var wallet := _line("Кредиты %d   ·   Детали %d" % [voyage.adventure.credits, voyage.adventure.parts], 18)
	wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(wallet)
	_button(top, "Закрыть", dismissed.emit)
	content.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)
	match _tab:
		1: _build_workshop()
		2: _build_recruitment()
		_: _build_contracts()


func _open_tab(tab: int) -> void:
	if tab != _tab:
		_tab = tab
		_rebuild()


func _build_contracts() -> void:
	var save := voyage.adventure
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 10)
	_body.add_child(filters)
	var check := CheckBox.new()
	check.text = "Показывать выполненные"
	check.set_pressed_no_signal(_show_completed)
	check.toggled.connect(func(value: bool) -> void:
		_show_completed = value
		_rebuild())
	filters.add_child(check)
	_filter(filters, ["Сначала новые", "Сначала ценные", "Ближайшие"], _sort, func(value: int) -> void: _sort = value)
	_filter(filters, ["Все типы", "Доставка", "Бой"], _type, func(value: int) -> void: _type = value)
	_filter(filters, ["Все статусы", "Доступные", "В работе"], _status, func(value: int) -> void: _status = value)
	_body.add_child(HSeparator.new())
	var matches := _filtered_contracts()
	for index in matches:
		var job: Dictionary = Adventure.CONTRACTS[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		_body.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		text.add_child(_line(job.title, 19))
		text.add_child(_line("%s → %s, «%s»   ·   %d кр. / %d дет." % [
			Voyage.SYSTEMS[job.from].station, Voyage.SYSTEMS[job.to].name,
			Voyage.SYSTEMS[job.to].station, job.credits, job.parts], 15))
		text.add_child(_line(job.brief, 15))
		if index in save.settled:
			_button(row, "Выполнен", Callable(), false)
		elif index in save.accepted:
			var action := "Сдать на станции" if not job.battle or save.remaining(job.to).is_empty() else "Устранить угрозу"
			_button(row, action, Callable(), false)
		else:
			_button(row, "Принять", _perform.bind(voyage.accept_contract.bind(index)), voyage.docked)
		_body.add_child(HSeparator.new())
	if matches.is_empty():
		_body.add_child(_line("Нет контрактов, подходящих под фильтры.", 18))


func _filter(parent: Container, values: Array, selected: int, update: Callable) -> void:
	var picker := OptionButton.new()
	for value in values:
		picker.add_item(value)
	picker.select(selected)
	picker.item_selected.connect(func(index: int) -> void:
		update.call(index)
		_rebuild())
	parent.add_child(picker)


func _filtered_contracts() -> Array[int]:
	var save := voyage.adventure
	var matches: Array[int] = []
	var distance := {}
	for index in Adventure.CONTRACTS.size():
		var job: Dictionary = Adventure.CONTRACTS[index]
		var active := index in save.accepted
		var done := index in save.settled
		if (job.from != voyage.current_system and not active) or (done and not _show_completed):
			continue
		if (_type == 1 and job.battle) or (_type == 2 and not job.battle):
			continue
		if (_status == 1 and active) or (_status == 2 and (not active or done)):
			continue
		matches.append(index)
		distance[index] = voyage.route_distance(job.to)
	matches.sort_custom(func(a: int, b: int) -> bool:
		if _sort == 1 and Adventure.CONTRACTS[a].credits != Adventure.CONTRACTS[b].credits:
			return Adventure.CONTRACTS[a].credits > Adventure.CONTRACTS[b].credits
		if _sort == 2 and distance[a] != distance[b]:
			return distance[a] < distance[b]
		if _sort == 0:
			var a_new := a not in save.accepted
			var b_new := b not in save.accepted
			if a_new != b_new:
				return a_new
			if not a_new:
				return save.accepted.find(a) > save.accepted.find(b)
		return a > b)
	return matches


func _build_recruitment() -> void:
	var crew := voyage.deck
	_body.add_child(_line("Экипаж   %d / %d" % [crew.crew_alive(), crew.CREW_LIMIT], 22))
	var candidates := voyage.adventure.candidates(voyage.current_system, crew.SPECIALTIES.size())
	if candidates.is_empty():
		_body.add_child(_line("На этой станции сейчас нет кандидатов.", 17))
	for candidate in candidates:
		var row := HBoxContainer.new()
		_body.add_child(row)
		var profile: Dictionary = crew.SPECIALTIES[candidate.specialty]
		var title := _line("%s   ·   %s" % [candidate.name, profile.role], 17)
		title.add_theme_color_override("font_color", profile.color)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		_button(row, "Нанять за %d кр." % Adventure.HIRE_COST, _perform.bind(voyage.hire_recruit.bind(candidate.id)),
			crew.available_berth() and voyage.adventure.credits >= Adventure.HIRE_COST)


func _build_workshop() -> void:
	var save := voyage.adventure
	_body.add_child(_line("Улучшения отсеков", 22))
	for module: String in Adventure.MODULE_NAMES:
		var row := HBoxContainer.new()
		_body.add_child(row)
		var level: int = save.levels[module]
		var label := _line("%s   ·   %d / 2   ·   %s за уровень" % [
			Adventure.MODULE_NAMES[module], level, Adventure.MODULE_EFFECTS[module]], 17)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var cost := save.module_cost(module)
		var price := "%d кр. / %d дет." % [cost.x, cost.y] if level < 2 else "Максимум"
		_button(row, price, _perform.bind(voyage.refit.bind(module)),
			level < 2 and save.credits >= cost.x and save.parts >= cost.y)
	_body.add_child(HSeparator.new())
	_body.add_child(_line("Орудия", 22))
	for slot in range(2):
		var row := HBoxContainer.new()
		_body.add_child(row)
		var label := _line("Слот %d%s" % [slot + 1, "   ·   активен" if slot == save.equipped else ""], 17)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(250, 34)
		for index in Voyage.TEST_WEAPONS.size():
			if index in save.unlocked:
				picker.add_item(Voyage.TEST_WEAPONS[index].title, index)
				if index == save.slots[slot]:
					picker.select(picker.item_count - 1)
		picker.item_selected.connect(func(item: int) -> void:
			_perform(voyage.mount_weapon.bind(slot, picker.get_item_id(item))))
		row.add_child(picker)
	for index in Adventure.WEAPON_PRICES.size():
		if index in save.unlocked:
			continue
		var row := HBoxContainer.new()
		_body.add_child(row)
		var label := _line(Voyage.TEST_WEAPONS[index].title, 17)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var price: int = Adventure.WEAPON_PRICES[index]
		_button(row, "Купить за %d кр." % price, _perform.bind(voyage.purchase_weapon.bind(index)), save.credits >= price)


func _perform(action: Callable) -> void:
	if action.call():
		_rebuild()


func _button(parent: Container, title: String, action: Callable, enabled := true) -> Button:
	var button := Button.new()
	button.text = title
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(154, 32)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_stylebox_override("normal", _button_style(Color("#142638"), Color("#385367")))
	button.add_theme_stylebox_override("hover", _button_style(Color("#20374a"), Color("#78ead0")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("#244054"), Color("#78ead0")))
	button.add_theme_stylebox_override("disabled", _button_style(Color("#131f2b"), Color("#2a3947")))
	if action.is_valid():
		button.pressed.connect(action)
	parent.add_child(button)
	return button


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style


func _line(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#dbe8f2"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
