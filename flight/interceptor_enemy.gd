extends "res://flight/enemy_ship.gd"

const TELEPORT_RANGE := 330.0
const TELEPORT_COOLDOWN := 15.0

enum Tactic { WEAPONS, DISABLE, SUFFOCATE }

var team: Array[DeckSimulation.CrewMember] = []
var tactic: Tactic = Tactic.WEAPONS
var teleport_timer := 2.0
var _next_order := 0.0
var _hacks := 0
var _deployed := false
var _retreating := false


func _configure_deck() -> void:
	deck.layout_path = "res://deck/layouts/interceptor.json"


func _ready() -> void:
	super._ready()
	tactic = randi_range(0, Tactic.size() - 1) as Tactic
	deck.crew.resize(1)
	var hacker := deck.make_member("Хакер · перехватчик", deck.HACKER, deck.reactor_tile + Vector2i.DOWN)
	deck.crew.append(hacker)
	var cells := deck.free_cells_in_room(deck.teleport_tile)
	for index in range(4):
		var member := deck.make_member("Боец · %d" % (index + 1), deck.FIGHTER, cells[index])
		team.append(member)
		deck.crew.append(member)


func _assign_crew() -> void:
	# Keep a pilot and hacker aboard during the operation.
	if not deck.helm_is_manned() and deck.crew[0].health <= 0.0 and not deck.crew.any(func(member: DeckSimulation.CrewMember) -> bool: return member.health > 0.0 and member.target == deck.bridge_tile):
		for index in range(1, deck.crew.size()):
			if deck.crew[index].health > 0.0:
				deck.assign_order(index, deck.bridge_tile, false, true)
				break
	for index in range(1, deck.crew.size()):
		var member := deck.crew[index]
		if member.specialty == deck.HACKER and member.order == deck.Order.IDLE:
			deck.assign_order(index, deck.reactor_tile, false, true)
		elif member.specialty == deck.FIGHTER and member.order == deck.Order.IDLE and deck.hull.condition(deck.teleport_tile) < 1.0:
			deck.assign_order(index, deck.teleport_tile, false, true)
			break


func _steer(delta: float, target_position: Vector2, target_velocity: Vector2) -> void:
	var offset := target_position - position
	var bearing := offset.normalized()
	var radial := clampf((offset.length() - 226.0) * 1.35, -105.0, 120.0)
	var goal := (target_velocity + bearing * radial + bearing.orthogonal() * 22.0).limit_length(142.0)
	var throttle := _recovery_throttle() if _conserve_if_low(20.0) else 0.82
	_fly_towards(delta, goal, throttle)


func advance_boarding(delta: float, target: DeckSimulation, target_position: Vector2) -> void:
	teleport_timer = move_toward(teleport_timer, 0.0, delta)
	_next_order -= delta
	var distance := position.distance_to(target_position)
	var objectives := _objectives(target)
	var objective := target.INVALID_CELL
	for tile: Vector2i in objectives:
		if tile != target.INVALID_CELL and target.hull.condition(tile) > 0.0:
			objective = tile
			break
	var active := team.filter(func(member: DeckSimulation.CrewMember) -> bool: return member.health > 0.0 and member in target.boarders)
	if _deployed and not _retreating:
		_retreating = active.any(func(member: DeckSimulation.CrewMember) -> bool: return member.health <= 35.0)
		_retreating = _retreating or team.any(func(member: DeckSimulation.CrewMember) -> bool: return member.health <= 0.0)
		_retreating = _retreating or (tactic != Tactic.WEAPONS and objective == target.INVALID_CELL)
	if distance <= DeckSimulation.HACK_RANGE and not _retreating:
		_support(target, objective)
	if teleport_timer == 0.0 and distance <= TELEPORT_RANGE and deck.module_online(deck.teleport_tile):
		if not _deployed or (not _retreating and team.any(func(member: DeckSimulation.CrewMember) -> bool: return member.health > 0.0 and member in deck.crew)):
			_transfer(target, deck, team, true)
		elif _retreating and not active.is_empty():
			_transfer(deck, target, active, false)
	if _next_order > 0.0 or active.is_empty():
		return
	_next_order = 0.45
	var extraction := target.free_cells_in_room(target.airlock_tile)
	var attack_crew := tactic == Tactic.WEAPONS and objective == target.INVALID_CELL
	for member: DeckSimulation.CrewMember in active:
		member.aggressive = attack_crew
		if _retreating:
			member.retreating = true
			member.aggressive = false
			if target.hull.room_at.get(member.cell) != target.hull.room_at.get(target.airlock_tile) and not extraction.is_empty():
				target.boarder_move(member, extraction.pop_front())
		elif attack_crew:
			if member.order != target.Order.IDLE:
				member.order = target.Order.IDLE
				member.target = target.INVALID_CELL
				member.route.clear()
		elif objective != target.INVALID_CELL:
			target.boarder_move(member, objective, true)


func _objectives(target: DeckSimulation) -> Array[Vector2i]:
	match tactic:
		Tactic.DISABLE: return [target.shield_tile, target.bridge_tile]
		Tactic.SUFFOCATE: return [target.life_support_tile]
	return [target.weapons_tile]


func _transfer(destination: DeckSimulation, source: DeckSimulation, candidates: Array, deploying: bool) -> void:
	if not deck.power.can_spend(18.0):
		return
	var slots := destination.free_cells_in_room(destination.airlock_tile if deploying else destination.teleport_tile)
	var room: int = source.hull.room_at.get(source.teleport_tile if deploying else source.airlock_tile)
	var moved := 0
	for member: DeckSimulation.CrewMember in candidates:
		if slots.is_empty():
			break
		if member.health <= 0.0 or member.landing != source.INVALID_CELL or source._reserved(member.cell):
			continue
		if source.hull.room_at.get(member.cell) != room:
			if deploying and member in deck.crew and member.order == deck.Order.IDLE:
				deck.boarder_move(member, deck.teleport_tile)
			continue
		source.teleport_out(member)
		destination.teleport_in(member, slots.pop_front(), deploying)
		member.immune = deploying and not deck.damage_enabled
		member.retreating = false
		moved += 1
	if moved > 0:
		_deployed = true
		teleport_timer = TELEPORT_COOLDOWN
		deck.power.spend(18.0)
		source.teleport_flash = 0.65
		destination.teleport_flash = 0.65
		var player := destination if deploying else source
		player.security_alert.emit("boarding", null, "Абордаж · противники в шлюзе" if deploying else "Перехватчик эвакуирует бойцов")
		player.changed.emit()


func _support(target: DeckSimulation, objective: Vector2i) -> void:
	if deck.hack_cooldown > 0.0 or not deck.hacker_available() or target.firewall > 0.0:
		return
	if not _deployed:
		if deck.send_hack(target, "computer"):
			_hacks += 1
		return
	if objective != target.INVALID_CELL and _hacks % 3 == 2 and deck.send_hack(target, "room", objective):
		_hacks += 1
		return
	var anchor := objective if objective != target.INVALID_CELL else target.bridge_tile
	var area: int = target.hull.room_at.get(anchor, -1)
	for edge: Vector4i in target.doors:
		if edge in target.hatches:
			continue
		var a := Vector2i(edge.x, edge.y)
		var b := Vector2i(edge.z, edge.w)
		var by_objective: bool = target.hull.room_at.get(a) == area or target.hull.room_at.get(b) == area
		var on_route := false
		for member in team:
			if member in target.boarders and target._crosses_edge(member.cell, member.route, edge):
				on_route = true
				break
		if (by_objective or on_route) and deck.send_hack(target, "door", edge):
			_hacks += 1
			return
	if deck.send_hack(target, "computer"):
		_hacks += 1
