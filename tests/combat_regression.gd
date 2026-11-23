extends SceneTree

const Hull = preload("res://deck/hull.gd")
const Deck = preload("res://deck/deck_simulation.gd")
const Voyage = preload("res://flight/voyage_state.gd")
const Run = preload("res://flight/run.gd")
const GAME := preload("res://flight/run.tscn")
const TICK := 1.0 / 60.0

var _failures := 0
var _game: Run


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	_game = GAME.instantiate()
	root.add_child(_game)
	_check_pressure_links()
	_check_damage_and_repairs()
	_check_operators()
	_check_reactor_power()
	_check_enemy()
	_check_drill_pursuit()
	_check_fighter_and_test_controls()
	if _failures == 0:
		print("Combat regression checks passed.")
	quit(_failures)


func _check_pressure_links() -> void:
	var hull := Hull.new()
	hull.configure(["BBEE"], [Vector4i(1, 0, 2, 0)])
	hull.rooms[hull.room_at[Vector2i.ZERO]].oxygen = 0.1
	hull.advance_air(0.5, [], 0.0)
	_check(is_equal_approx(hull.oxygen_at(Vector2i.ZERO), 0.1)
		and is_equal_approx(hull.oxygen_at(Vector2i(3, 0)), 1.0), "Closed doors block air exchange")
	hull.advance_air(0.5, [Vector4i(1, 0, 2, 0)], 0.0)
	var left := hull.oxygen_at(Vector2i.ZERO)
	var right := hull.oxygen_at(Vector2i(3, 0))
	_check(left > 0.1 and right < 1.0 and is_equal_approx(left + right, 1.1),
		"Open doors share air while conserving the total")


func _check_damage_and_repairs() -> void:
	var deck := _game.voyage.deck
	deck.reset(true)
	deck._rng.seed = 12
	var engineer := deck.crew[1]
	engineer.cell = Vector2i(11, 3)
	engineer.position = Vector2(engineer.cell)
	deck.apply_hit(20.0, 1.0, 9.0, Vector2.ZERO, Deck.ENGINE)
	deck.apply_hit(20.0, 1.0, 9.0, Vector2.ZERO, Deck.ENGINE)
	_check(deck.alerts.has(deck.hull.room_at[Deck.ENGINE]), "Hits raise the affected room alert")
	_check(engineer.health == 82.0 and deck.crew[0].health == 100.0,
		"Projectile crew damage affects the crew in the struck room")
	_check(deck.hull.breaches.size() == 2 and not deck.hull.breaches.has(engineer.cell),
		"Multiple breaches choose distinct unoccupied tiles")
	for tile in deck.hull.breaches:
		_check(tile not in Deck.MODULE_CELLS and deck.hull.room_at[tile] == deck.hull.room_at[Deck.ENGINE],
			"Breaches stay inside the struck room, away from module cells")
	var room := deck.hull.rooms[deck.hull.room_at[Deck.ENGINE]]
	for i in range(110):
		deck._physics_process(TICK)
	_check(room.oxygen < 0.95 and is_equal_approx(deck.hull.condition(Deck.ENGINE), 0.6),
		"Breaches lower oxygen and hits lower room integrity")
	var first: Vector2i = deck.hull.breaches.keys()[0]
	deck.assign_order(1, first)
	for i in range(370):
		deck._physics_process(TICK)
		if not deck.hull.breaches.has(first):
			break
	_check(not deck.hull.breaches.has(first) and deck.hull.breaches.size() == 1,
		"An engineer approaching a breach can seal it")
	var second: Vector2i = deck.hull.breaches.keys()[0]
	deck.assign_order(1, second)
	for i in range(370):
		deck._physics_process(TICK)
		if not deck.hull.breaches.has(second):
			break
	_check(deck.hull.breaches.is_empty(), "The second breach can be sealed independently")
	var low_oxygen := room.oxygen
	deck.toggle_door(Vector4i(13, 3, 13, 4))
	deck.assign_order(1, Deck.ENGINE)
	for i in range(310):
		deck._physics_process(TICK)
	_check(room.oxygen > low_oxygen and deck.hull.condition(Deck.ENGINE) == 1.0,
		"Oxygen recovers and crew repair room damage independently from the outer hull")

	var east := 0
	var west := 0
	deck._rng.seed = 24
	for i in range(500):
		east += deck._impact_cell(Vector2.RIGHT).x
		west += deck._impact_cell(Vector2.LEFT).x
	_check(east > west + 1400, "The side of impact biases the random cell selection")


func _check_operators() -> void:
	var voyage := _game.voyage
	var deck := voyage.deck
	voyage.reset()
	var speed := Vector2(40, 10)
	voyage.velocity = speed
	var direction := voyage.heading
	deck.assign_order(0, Vector2i(1, 3))
	voyage.advance_flight(TICK, 1.0, true, true)
	_check(voyage.heading == direction and voyage.velocity == speed and not voyage.thrusting,
		"Without a pilot only inertia remains")
	_check(deck.pilot_efficiency() == 0.0, "A pilot with a pending movement order leaves the post")
	deck.reset(true)
	deck.apply_hit(100.0, 0.0, 0.0, Vector2.ZERO, Deck.WEAPONS)
	_check(not voyage.fire(), "A destroyed weapons room prevents firing")
	deck.reset(true)
	deck.apply_hit(30.0, 0.0, 0.0, Vector2.ZERO, Deck.WEAPONS)
	seed(6)
	_check(voyage.fire(), "A damaged weapons room can still fire")
	var shot := voyage.projectiles[0]
	_check(shot.crew_damage == voyage.weapon.crew_damage and shot.breach_chance == voyage.weapon.breach_chance
		and not shot.velocity.normalized().is_equal_approx(Vector2.from_angle(voyage.heading)),
		"The shot carries its supplied crew damage, breach chance and increased spread")

	deck.reset(true)
	for room in deck.hull.rooms:
		room.oxygen = 0.0
	deck.crew[0].health = 1.0
	deck._physics_process(0.1)
	_check(deck.crew[0].health == 0.0 and not deck.helm_is_manned(), "Hypoxia can kill and vacate the helm")

	deck.reset(true)
	var oxygen_room := deck.hull.rooms[deck.hull.room_at[Deck.LIFE_SUPPORT]]
	for room in deck.hull.rooms:
		room.oxygen = 0.5
	deck._advance_atmosphere(0.2)
	var automatic := oxygen_room.oxygen - 0.5
	for room in deck.hull.rooms:
		room.oxygen = 0.5
	var operator := deck.crew[2]
	operator.cell = Deck.LIFE_SUPPORT_SEAT
	operator.position = Vector2(operator.cell)
	deck.assign_order(2, Deck.LIFE_SUPPORT)
	deck._advance_atmosphere(0.2)
	_check(oxygen_room.oxygen - 0.5 > automatic, "An operator improves automatic oxygen production")


func _check_reactor_power() -> void:
	var voyage := _game.voyage
	var deck := voyage.deck
	voyage.reset()
	var full_rate := deck.energy_recovery_rate()
	deck.apply_hit(50.0, 0.0, 0.0, Vector2.ZERO, deck.reactor_tile)
	_check(is_equal_approx(deck.energy_recovery_rate(), full_rate * 0.5), "A damaged reactor recharges more slowly")

	var engineer := deck.crew[1]
	engineer.cell = deck.reactor_tile + Vector2i.DOWN
	engineer.position = Vector2(engineer.cell)
	deck.assign_order(1, deck.reactor_tile)
	for frame in range(180):
		deck._physics_process(TICK)
	_check(deck.operator_at(Deck.WorkPose.REACTOR) == engineer
		and is_equal_approx(deck.energy_recovery_rate(), full_rate * 1.5), "The engineer repairs the reactor and then boosts recharge")

	deck.power.energy = 6.0
	_check(not voyage.fire() and voyage.weapon_status() == "Зарядка" and voyage.projectiles.is_empty(),
		"The weapon waits for enough energy before firing")
	var baseline := voyage.velocity
	voyage.advance_flight(TICK, 0.0, true, false)
	var low_thrust := baseline.distance_to(voyage.velocity)
	voyage.velocity = baseline
	deck.power.energy = 100.0
	voyage.advance_flight(TICK, 0.0, true, false)
	var full_thrust := baseline.distance_to(voyage.velocity)
	_check(is_equal_approx(low_thrust * 2.0, full_thrust) and deck.power.energy < 100.0,
		"At half the low-energy threshold the nozzles produce half thrust and consume energy")
	deck.power.energy = 0.0
	voyage.velocity = baseline
	voyage.advance_flight(TICK, 1.0, true, false)
	_check(voyage.velocity == baseline and not voyage.thrusting and voyage.body.active.is_empty(),
		"An empty reserve leaves only inertia")
	Input.action_press("flight_fire")
	for frame in range(90):
		deck._physics_process(TICK)
		voyage._physics_process(TICK)
		if not voyage.projectiles.is_empty():
			break
	Input.action_release("flight_fire")
	_check(voyage.projectiles.size() == 1 and deck.power.energy < 1.0,
		"Holding fire launches a shot as soon as recharge covers the cost")


func _check_enemy() -> void:
	_game._toggle_arena()
	var voyage := _game.voyage
	var enemy := voyage.add_test_enemy(voyage.Opponent.DRILL)
	_check(is_instance_valid(enemy) and enemy.deck != voyage.deck and not enemy.deck.hull.room_at.is_empty(),
		"The drill is composed with an independent crew and hull")
	enemy.deck.apply_hit(20.0, 1.0, 0.0, Vector2.ZERO, enemy.deck.engine_tile)
	enemy.advance(TICK, voyage.ship_position, voyage.velocity)
	_check(enemy.deck.crew[1].order == Deck.Order.SEAL and enemy.deck.helm_is_manned(),
		"The drill assigns free crew to its breach while keeping the pilot")
	enemy.deck.reset(true)
	var hostile_hull := enemy.deck.hull.integrity
	var local_hull := voyage.deck.hull.integrity
	enemy.heading = PI
	enemy.position = voyage.ship_position + Vector2(55, 0)
	enemy.velocity = Vector2(-120, 0)
	voyage._advance_battle(TICK)
	_check(voyage.deck.hull.integrity < local_hull and enemy.deck.hull.integrity < hostile_hull
		and not enemy.can_ram(), "Ramming damages both ships and starts a retreat")
	_check(local_hull - voyage.deck.hull.integrity > hostile_hull - enemy.deck.hull.integrity,
		"Ramming damages the target more than the drill")
	_check(enemy.deck.hull.condition(enemy.deck.weapons_tile) < 1.0, "The ram damages the drill weapons room")
	_game._toggle_scan()
	_check(voyage.scan_enemy, "The flight scanner can show the drill deck")
	for frame in range(480):
		enemy.advance(TICK, voyage.ship_position, voyage.velocity)
	_check(enemy.deck.hull.condition(enemy.deck.weapons_tile) == 1.0 and enemy.deck.helm_is_manned(),
		"The spare crew repair the ram damage while the pilot holds the helm")
	enemy.deck.apply_hit(Hull.HULL_MAX, 0.0)
	voyage._advance_battle(TICK)
	_check(not is_instance_valid(voyage.enemy) and voyage.battle_result.is_empty(),
		"Destroying a target leaves the sandbox running")
	_game._reset()
	voyage.deck.apply_hit(Hull.HULL_MAX, 0.0)
	voyage._advance_battle(TICK)
	_check(voyage.battle_result == "Корабль потерян", "Losing the player hull ends the battle")
	_game._reset()
	for member in voyage.deck.crew:
		voyage.deck._hurt_crew(member, 100.0)
	voyage._advance_battle(TICK)
	_check(voyage.battle_result == "Корабль потерян" and voyage.deck.hull.integrity == Hull.HULL_MAX,
		"Losing the entire crew also ends the battle")


func _check_drill_pursuit() -> void:
	_game._reset()
	var voyage := _game.voyage
	voyage.set_test_damage(false, false)
	var drill := voyage.add_test_enemy(Voyage.Opponent.DRILL)
	var origin := voyage.ship_position
	drill.heading += 1.1
	drill.velocity = Vector2(12, 95)
	drill.body.spin = 1.40
	var rams := 0
	var ready := true
	for frame in range(1900):
		var angle := frame / 170.0
		voyage.ship_position = origin + Vector2(cos(angle) - 1.0, sin(angle)) * 114.0
		voyage.velocity = Vector2(-sin(angle), cos(angle)) * (114.0 * 60.0 / 170.0)
		voyage._advance_battle(TICK)
		if ready and not drill.can_ram():
			rams += 1
		ready = drill.can_ram()
	_check(rams >= 3, "The drill recovers from spin and lateral drift, then rams a turning target repeatedly")


func _check_fighter_and_test_controls() -> void:
	_game._reset()
	var voyage := _game.voyage
	var fighter := voyage.add_test_enemy(Voyage.Opponent.FIGHTER)
	var drill := voyage.add_test_enemy(Voyage.Opponent.DRILL)
	_check(voyage.enemies.size() == 2 and fighter.deck != drill.deck, "The range supports independent concurrent enemies")
	_game._toggle_scan()
	_game._cycle_scan()
	_check(voyage.enemy == drill, "The scanner can select the next hostile deck")
	for ship in [fighter, drill]:
		_check(ship.deck._build_navigation().is_empty(), "Every hostile floor tile and module is reachable")
		_check(ship.deck.tile_kind(ship.deck.crew[1].cell) == "E" and ship.deck.tile_kind(ship.deck.crew[3].cell) == "W",
			"Hostile crews spawn in their assigned compartments")
	_check(drill.deck.weapons_tile.y < drill.deck.bridge_tile.y and drill.deck.weapons_tile.y < drill.deck.engine_tile.y,
		"The drill mechanism sits ahead of the helm and engines")
	voyage.set_test_physics(2.0, 0.5)
	_check(voyage.body.mass_scale == 2.0 and voyage.body.thrust_scale == 0.5 and drill.body.mass_scale == 1.0,
		"Range tuning applies to the player's body only")
	voyage.set_test_damage(false, true)
	voyage.deck.apply_hit(30.0, 1.0)
	drill.deck.apply_hit(10.0, 0.0)
	_check(voyage.deck.hull.integrity == Hull.HULL_MAX and voyage.deck.alerts.is_empty()
		and drill.deck.hull.integrity < Hull.HULL_MAX, "Damage toggles are independent and suppressed hits do not raise alarms")

	voyage.clear_test_enemies()
	voyage.set_test_damage(false, false)
	fighter = voyage.add_test_enemy(Voyage.Opponent.FIGHTER)
	fighter.deck.power.energy = 0.0
	voyage._physics_process(TICK)
	_check(voyage.projectiles.is_empty() and fighter.deck.power.energy < 1.0,
		"Hostile weapons also need energy before they can fire")
	fighter.deck.power.energy = 100.0
	voyage._physics_process(TICK)
	_check(fighter.deck.power.energy < 92.0, "The fighter pays for its volley from its own reserve")
	_check(voyage.projectiles.size() == 2 and voyage.projectiles[0].hostile and voyage.projectiles[1].hostile,
		"The fighter fires a volley from both nose mounts")
	if voyage.projectiles.size() == 2:
		_check(voyage.projectiles[0].velocity.normalized().is_equal_approx(Vector2.from_angle(fighter.heading))
			and voyage.projectiles[0].position.distance_to(voyage.projectiles[1].position) > 10.0,
			"Both shells follow the hull from separate physical mounts")
	var volleys := 1
	var closest := INF
	var farthest_after_break := 0.0
	for frame in range(750):
		voyage._physics_process(TICK)
		if fighter.flash_remaining == Voyage.FLASH_SECONDS:
			volleys += 1
		var distance := fighter.position.distance_to(voyage.ship_position)
		closest = minf(closest, distance)
		if closest < 150.0:
			farthest_after_break = maxf(farthest_after_break, distance)
	_check(farthest_after_break > 390.0 and volleys >= 4, "The fighter breaks away and returns for another firing pass")
	voyage.clear_test_enemies()
	_check(voyage.enemies.is_empty() and voyage.projectiles.is_empty() and not voyage.scan_enemy,
		"Clearing the range also clears in-flight ammunition and the selected target")
	_game._toggle_arena()
	_check(voyage.body.mass_scale == 1.0 and voyage.body.thrust_scale == 1.0 and voyage.deck.damage_enabled,
		"Range settings do not affect the rescue campaign")


func _check(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error(message)
