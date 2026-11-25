extends PanelContainer

const Computer = preload("res://flight/flight_computer.gd")

signal dismissed
signal assigned(module: String, level: int)

var _model: Computer
var _usage: Label


func present(model: Computer) -> void:
	_model = model
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 7)
	add_child(rows)
	var heading := Label.new()
	heading.text = "Бортовой компьютер"
	heading.add_theme_font_size_override("font_size", 25)
	rows.add_child(heading)
	_usage = Label.new()
	_usage.add_theme_font_size_override("font_size", 17)
	rows.add_child(_usage)
	rows.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 340.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(scroll)
	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("separation", 6)
	scroll.add_child(options)
	for module: String in Computer.MODULES:
		var spec: Dictionary = Computer.MODULES[module]
		var row := HBoxContainer.new()
		options.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var title := Label.new()
		title.text = spec.title
		info.add_child(title)
		var hint := Label.new()
		hint.text = spec.hint
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", Color("#9fb4c8"))
		info.add_child(hint)
		var picker := OptionButton.new()
		picker.custom_minimum_size.x = 215.0
		row.add_child(picker)
		for index in spec.cost.size():
			picker.add_item(_option(module, index, spec.cost[index]))
		picker.select(model.levels[module])
		picker.item_selected.connect(_allocate.bind(module))
	var close := Button.new()
	close.text = "Закрыть"
	close.custom_minimum_size.y = 34
	close.pressed.connect(dismissed.emit)
	rows.add_child(close)
	_refresh()
	show()


func _allocate(level: int, module: String) -> void:
	assigned.emit(module, level)
	_refresh()


func _refresh() -> void:
	var drain := _model.overload_draw()
	_usage.text = "Память %d / %d" % [_model.memory_used(), Computer.MEMORY]
	if drain > 0.0:
		_usage.text += "   ·   Перегрузка −%.2f ед/с" % drain
	_usage.add_theme_color_override("font_color", Color("#ffae87") if drain > 0.0 else Color("#78ead0"))


func _option(module: String, level: int, cost: int) -> String:
	var status := "Выкл."
	if module == "zoom":
		status = ["Базовый", "Средний", "Дальний"][level]
	elif level > 0:
		status = "Вкл." if module in ["assist", "scanner", "objects", "threat", "aim"] else "%d%%" % roundi(Computer.PERFORMANCE[level] * 100.0)
	return "%s  ·  %d ед." % [status, cost]
