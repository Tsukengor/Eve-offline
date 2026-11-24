extends RefCounted

const Voyage = preload("res://flight/voyage_state.gd")
enum Step { TURN, THRUST, BRAKE, FIRE, SEAL, PREPARE, APPROACH, DOCK, COMPLETE }

var _voyage: Voyage
var _initial_heading := 0.0
var _target: Voyage.EnemyShip
var step := Step.TURN


func reset(voyage: Voyage) -> void:
	_voyage = voyage
	_voyage.training_can_dock = false
	_voyage.deck.damage_enabled = true
	_voyage.flight_computer = true
	_voyage.heading -= 0.35
	_initial_heading = _voyage.heading
	_target = null
	_set_step(Step.TURN)


func advance(in_deck: bool) -> void:
	match step:
		Step.TURN:
			if absf(angle_difference(_initial_heading, _voyage.heading)) >= 0.20:
				_set_step(Step.THRUST)
		Step.THRUST:
			if _voyage.velocity.length() >= 55.0:
				_set_step(Step.BRAKE)
		Step.BRAKE:
			if _voyage.velocity.length() < 12.0 and absf(_voyage.angular_velocity) < 0.18:
				_target = _voyage.spawn_training_target()
				_set_step(Step.FIRE)
		Step.FIRE:
			if not is_instance_valid(_target) or _target.disabled() or _target.deck.hull.integrity < 91.0:
				_voyage.finish_training_target(_target)
				var deck := _voyage.deck
				deck.apply_hit(10.0, 1.0, 0.0, Vector2.ZERO, deck.engine_tile)
				deck.damage_enabled = false
				_set_step(Step.SEAL)
		Step.SEAL:
			if _voyage.deck.hull.breaches.is_empty():
				_set_step(Step.PREPARE)
		Step.PREPARE:
			if _voyage.deck.airlock_progress >= 1.0:
				_voyage.training_can_dock = true
				_set_step(Step.APPROACH)
		Step.APPROACH:
			if not in_deck and _voyage.distance_to_station() <= Voyage.DOCK_RANGE:
				_set_step(Step.DOCK)
		Step.DOCK:
			if _voyage.stage == Voyage.Stage.COMPLETE:
				_set_step(Step.COMPLETE)
			elif _voyage.distance_to_station() > Voyage.DOCK_RANGE:
				_set_step(Step.APPROACH)


func _set_step(next: Step) -> void:
	step = next
	var instructions := [
		"Поверни корабль клавишей %s или %s. %s погасит вращение." % [_key("flight_turn_left"), _key("flight_turn_right"), _key("flight_stabilize")],
		"Удерживай %s, чтобы разогнаться. Бирюзовая стрелка показывает скорость." % _key("flight_thrust"),
		"Удерживай %s для торможения. Борткомпьютер погасит скорость и вращение." % _key("flight_brake"),
		"По курсу учебная цель. Выстрели клавишей %s. Следи за запасом энергии." % _key("flight_fire"),
		"Пробоина в машинном отделении. %s — палуба. Выбери инженера (%s) и нажми ПКМ по пробоине." % [_key("toggle_deck"), _key("crew_2")],
		"Пробоина закрыта. Выбери спасателя (%s) и нажми ПКМ по пульту шлюза." % _key("crew_3"),
		"Шлюз готов. Вернись в полёт (%s) и войди в пунктирное кольцо станции." % _key("toggle_deck"),
		"Удерживай %s, пока скорость не упадёт до 34 ед/с. Затем нажми %s для стыковки." % [_key("flight_brake"), _key("dock_ship")],
		"Учебная эвакуация завершена. В меню можно выбрать кампанию или полигон.",
	]
	_voyage.training_hint = instructions[step]
	_voyage.training_step = mini(step + 1, 8)
	_voyage.deck.training_hint = _voyage.training_hint
	_voyage.changed.emit()


func _key(action: String) -> String:
	return _voyage.get_node("/root/GameSettings").key_label(action)
