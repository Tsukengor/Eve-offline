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
	_game.voyage.deck.auto_crew = false
	_check(_game.voyage.deck.load_layout("res://tests/rescue_corridor_fixture.json").is_empty(), "Load the damage fixture")
	_check_pressure_links()
	_check_damage_and_repairs()
	_check_operators()
	_check_reactor_power()
	_check_enemy()
	_check_drill_pursuit()
	_check_fighter_and_test_controls()
	_game._toggle_arena()
	_check_laser()
	_check_missile()
	_check_emp()
	_check_missile_fighter_tactics()
	_check_railgun()
	_check_fields_and_swarm()
	_check_ship_effects()
	_game._toggle_arena()
	_check(_game.voyage.weapon.kind == 0, "The rescue scenario retains its kinetic weapon")
	if _failures == 0:
		print("Combat regression checks passed.")
	quit(_failures)


func _check_ship_effects() -> void:
	_game._reset()
	var voyage := _game.voyage
	var fighter := voyage.add_test_enemy(Voyage.Opponent.FIGHTER)
	var drill := voyage.add_test_enemy(Voyage.Opponent.DRILL)
	fighter.deck.apply_hit(10.0, 0.0, 0.0, Vector2.LEFT)
	_check(fighter.hit_remaining > 0.0 and fighter.hit_side == Vector2.LEFT,
		"A successful hit starts the flash on the impact side")
	fighter.deck.apply_hit(Hull.HULL_MAX, 0.0)
	for member in drill.deck.crew:
		member.health = 0.0
	drill.velocity = Vector2(8, 0)
	voyage._advance_battle(TICK)
	_check(voyage.enemies.is_empty() and voyage.wrecks.size() == 2, "Both defeat causes leave persistent hulls")
	if voyage.wrecks.size() == 2:
		var derelict := voyage.wrecks[0]
		var wreck := voyage.wrecks[1]
		_check(not derelict.broken_hull and wreck.broken_hull and derelict.texture == drill.crew_derelict
			and wreck.texture == fighter.hull_wreck, "Crew loss and hull failure select different visuals")
		var position := derelict.position
		voyage._advance_wrecks(2.0)
		_check(derelict.position == position + Vector2(16, 0) and derelict.age == 2.0,
			"The derelict drifts after the animation ends")
	voyage.clear_test_enemies()
	_check(voyage.wrecks.is_empty(), "Clearing the test field removes old wrecks")


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
	voyage.body.shield.online = false
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


func _weapon_fixture(kind: int) -> Voyage:
	_game._reset()
	var voyage := _game.voyage
	voyage.set_test_damage(true, true)
	voyage.select_test_weapon(kind)
	voyage.heading = 0.0
	return voyage


func _check_laser() -> void:
	var voyage := _weapon_fixture(1)
	var target := voyage.add_test_enemy(Voyage.Opponent.DRILL)
	target.position = voyage.ship_position + Vector2(1700, 0)
	target.heading = PI
	var initial := target.deck.hull.integrity
	_check(voyage.fire() and voyage.deck.power.energy == 100.0, "Activating the laser does not charge a lump sum")
	var beam := voyage.projectiles[0]
	for frame in range(4):
		voyage._advance_weapons(TICK)
	_check(beam.beam_blocked and target.deck.hull.integrity == initial, "The unbounded beam reaches a distant hull before its first damage tick")
	voyage._advance_weapons(TICK)
	_check(is_equal_approx(initial - target.deck.hull.integrity, 3.0), "The laser applies one twelfth of its DPS after five 60 Hz frames")
	for frame in range(25):
		voyage._advance_weapons(TICK)
	_check(is_equal_approx(initial - target.deck.hull.integrity, 18.0) and is_equal_approx(voyage.deck.power.energy,79.0),
		"Uninterrupted contact deals six discrete ticks and drains energy over half a second")
	initial = target.deck.hull.integrity
	voyage.heading = PI * 0.5
	voyage._advance_weapons(TICK)
	_check(beam.position.is_equal_approx(voyage.muzzle_position()) and not beam.beam_blocked
		and target.deck.hull.integrity == initial, "The beam turns with its ship and damage stops when contact breaks")
	voyage._physics_process(TICK)
	_check(voyage.projectiles.is_empty(), "Releasing fire immediately stops the beam")
	voyage.deck.power.energy = 2.0
	Input.action_press("flight_fire")
	for frame in range(8):
		voyage._physics_process(TICK)
	_check(voyage.projectiles.is_empty() and voyage.deck.power.energy == 0.0, "The beam runs until its power reserve is exhausted")
	voyage.deck.power.energy = 40.0
	voyage._physics_process(TICK)
	_check(voyage.projectiles.is_empty(), "Holding fire after depletion does not flicker the beam as energy returns")
	Input.action_release("flight_fire")
	voyage._physics_process(TICK)
	Input.action_press("flight_fire")
	voyage._physics_process(TICK)
	Input.action_release("flight_fire")
	_check(is_instance_valid(voyage.laser_beam), "Another press re-arms the depleted laser")
	voyage.stop_laser()


func _check_missile() -> void:
	var voyage := _weapon_fixture(2)
	var target := voyage.add_test_enemy(Voyage.Opponent.DRILL)
	var off_axis := voyage.add_test_enemy(Voyage.Opponent.FIGHTER)
	target.position = voyage.ship_position + Vector2(195, 64)
	target.heading = PI
	target.body.shield.online = true
	off_axis.position = voyage.ship_position + Vector2(0, 94)
	_check(voyage.fire(), "The launcher fires a missile")
	var missile := voyage.projectiles[0]
	_check(missile.target_body == target.body, "Missiles acquire the nearest eligible target inside the nose sector")
	for frame in range(18):
		voyage._advance_weapons(TICK)
	_check(missile.velocity.y > 10.0 and missile.velocity.length() < 160.0, "Missiles curve toward their lock at low speed")
	for frame in range(140):
		voyage._advance_weapons(TICK)
		if missile.blast_time > 0.0:
			break
	_check(missile.blast_time > 0.0 and target.deck.hull.integrity < 100.0
		and off_axis.deck.hull.integrity == Hull.HULL_MAX and target.body.shield.charge == 100.0,
		"The missile crosses the active field and detonates on the hull without draining it")

	var hull := target.deck.hull.integrity
	var far_side := target.body.position + Vector2(1, 0) * (target.body.shield_radius() + 81.0)
	missile.position = far_side
	Voyage.Weapons._explode(missile, voyage._weapon_targets())
	var distant_drain := 100.0 - target.body.shield.charge
	missile.position = far_side - Vector2(50, 0)
	Voyage.Weapons._explode(missile, voyage._weapon_targets())
	_check(distant_drain > 0.0 and 100.0 - target.body.shield.charge > distant_drain * 2.0
		and target.deck.hull.integrity == hull, "An external blast falls off with distance and only hits the field")

	voyage = _weapon_fixture(2)
	_check(voyage.fire(), "A missile can launch without a target")
	var timed := voyage.projectiles[0]
	timed.remaining = TICK
	voyage._advance_weapons(TICK)
	_check(timed.blast_time > 0.0 and voyage.deck.hull.integrity < Hull.HULL_MAX,
		"The fuse can detonate an unguided missile and its blast can damage the firing ship")


func _check_emp() -> void:
	var voyage := _weapon_fixture(3)
	var near_ship := voyage.add_test_enemy(Voyage.Opponent.DRILL)
	var far_ship := voyage.add_test_enemy(Voyage.Opponent.DRILL)
	var outside := voyage.add_test_enemy(Voyage.Opponent.FIGHTER)
	near_ship.position = voyage.ship_position + Vector2(105, 0)
	far_ship.position = voyage.ship_position + Vector2(305, 0)
	outside.position = voyage.ship_position + Vector2(0, 150)
	near_ship.heading = PI
	far_ship.heading = PI
	_check(voyage.fire(), "The EMP emits a traveling cone")
	voyage._advance_weapons(TICK)
	_check(near_ship.deck.power.energy == 100.0 and far_ship.deck.power.energy == 100.0,
		"Ships beyond the wave front are unaffected")
	var rim := PackedVector2Array([Vector2(100, 35), Vector2(122, 35), Vector2(122, 64), Vector2(100, 64)])
	_check(Voyage.Weapons._sector_front(Vector2.ZERO, 0.0, deg_to_rad(20.0), rim, 100.0, 115.0) != null,
		"An EMP hits the hull where it intersects the cone even if its center is outside")
	for frame in range(35):
		voyage._advance_weapons(TICK)
	_check(near_ship.deck.power.energy < far_ship.deck.power.energy and far_ship.deck.power.energy < 100.0
		and outside.deck.power.energy == 100.0, "The EMP weakens with distance and misses ships outside the cone")
	_check(near_ship.deck.emp_timers.size() == 3 and near_ship.deck.hull.integrity == Hull.HULL_MAX
		and not near_ship.deck.module_online(near_ship.deck.weapons_tile),
		"EMP disables multiple systems toward the near side without damaging their hull")
	for frame in range(210):
		near_ship.deck._physics_process(TICK)
	_check(near_ship.deck.emp_timers.is_empty() and near_ship.deck.module_online(near_ship.deck.weapons_tile),
		"Disabled systems automatically return when the EMP timer ends")

	_check(near_ship.deck.emp_recovery_time > 6.4 and near_ship.deck.energy_recovery_rate() < 10.0,
		"EMP keeps reactor recovery suppressed after its brief system shutdown")
	near_ship.deck._physics_process(6.49)
	_check(near_ship.deck.emp_recovery_time > 0.0, "The recharge debuff lasts a full ten simulation seconds")
	near_ship.deck._physics_process(0.02)
	_check(near_ship.deck.emp_recovery_time == 0.0 and near_ship.deck.energy_recovery_rate() == 10.0,
		"Normal reactor recovery comes back after the ten-second debuff")


func _check_missile_fighter_tactics() -> void:
	var voyage := _weapon_fixture(0)
	voyage.set_test_damage(false, false)
	var fighter := voyage.add_test_enemy(Voyage.Opponent.MISSILE_FIGHTER)
	fighter.deck.power.energy = 9.0
	var recovery := fighter.deck.power.energy
	for frame in range(150):
		voyage._advance_battle(TICK)
		voyage._advance_weapons(TICK)
	_check(fighter.conserving_power and not fighter.shot_requested and fighter.deck.power.energy > recovery,
		"A low-energy missile fighter retreats without shooting and gains energy")
	var closest := INF
	var shots := 0
	for frame in range(1700):
		voyage._advance_battle(TICK)
		voyage._advance_weapons(TICK)
		closest = minf(closest, fighter.position.distance_to(voyage.ship_position))
		if fighter.flash_remaining == Voyage.FLASH_SECONDS:
			shots += 1
	_check(closest > 155.0 and shots >= 4, "Missile fighters keep their distance across repeated attack and recharge cycles")


func _check_railgun() -> void:
	var voyage := _weapon_fixture(4)
	var first := voyage.add_test_enemy(Voyage.Opponent.DRILL)
	var second := voyage.add_test_enemy(Voyage.Opponent.DRILL)
	first.position = voyage.ship_position + Vector2(145, 0)
	second.position = voyage.ship_position + Vector2(285, 0)
	first.heading = PI
	second.heading = PI
	_check(voyage.fire(), "Railgun launches")
	for frame in range(20):
		voyage._advance_weapons(TICK)
	var damaged_rooms := 0
	for room in first.deck.hull.rooms:
		if room.integrity < Hull.ROOM_MAX:
			damaged_rooms += 1
	_check(damaged_rooms >= 2 and second.deck.hull.integrity < Hull.HULL_MAX,
		"The rail bolt damages multiple compartments in order and exits to hit another ship")


func _check_fields_and_swarm() -> void:
	var voyage := _weapon_fixture(4)
	var target := voyage.add_test_enemy(Voyage.Opponent.DRILL)
	target.position = voyage.ship_position + Vector2(180, 0)
	target.heading = PI
	var field := target.body.shield
	field.online = true
	_check(voyage.fire(), "Rail launches into a strong shield")
	for tick in range(14):
		voyage._advance_weapons(TICK)
	_check(field.charge == 62.0 and target.deck.hull.integrity == Hull.HULL_MAX, "A strong shield stops a rail shot")
	field.charge = 49.0
	voyage.weapon_cooldown = 0.0
	voyage.deck.power.energy = 100.0
	_check(voyage.fire(), "Rail launches into a weak shield")
	for tick in range(14):
		voyage._advance_weapons(TICK)
	_check(field.collapsed and field.charge == 0.0 and target.deck.hull.integrity <= Hull.HULL_MAX - 38.0,
		"A weak shield collapses and rail damage reaches the hull without reduction")
	field.advance(6.0)
	_check(field.collapsed and field.charge == 40.0, "A collapsed shield charges under hull fire and remains offline")
	field.advance(3.0)
	_check(field.active() and field.charge == 100.0, "A collapsed shield only returns at full charge")

	voyage.select_test_weapon(3)
	voyage.weapon_cooldown = 0.0
	voyage.deck.power.energy = 100.0
	var energy := target.deck.power.energy
	_check(voyage.fire(), "EMP launches into an active field")
	for tick in range(25):
		voyage._advance_weapons(TICK)
	_check(field.collapsed and field.charge == 0.0 and field.emp_time > 0.0 and target.deck.power.energy == energy,
		"An active field absorbs EMP and loses its charge instead of exposing the modules")
	field.advance(2.0)
	_check(field.charge == 0.0, "EMP pauses recharge during suppression")

	_game._reset()
	_check(voyage.deck.load_layout(Deck.RESCUE_LAYOUT).is_empty(), "Load the compact player deck")
	voyage.set_test_damage(false, true)
	_check(not voyage.body.shield.active(), "An unstaffed field cannot absorb fire")
	voyage.deck.assign_order(1, voyage.deck.shield_tile)
	for tick in range(420):
		voyage.deck._physics_process(TICK)
		voyage._physics_process(TICK)
	_check(voyage.body.shield.active(), "Posting an operator brings the field online")

	var carrier := voyage.add_test_enemy(Voyage.Opponent.SWARM)
	var drone_shots := 0
	for tick in range(1150):
		voyage._physics_process(TICK)
		drone_shots += voyage.drones.filter(func(drone: Voyage.Drone) -> bool: return drone.shot_requested).size()
	_check(voyage.drones.size() == 6 and drone_shots > 8, "A carrier maintains a six-drone firing orbit")
	_check(carrier.position.distance_to(voyage.ship_position) > 310.0 and voyage.drones.all(
		func(drone: Voyage.Drone) -> bool: return absf(drone.body.position.distance_to(voyage.ship_position)
			- Voyage.Drone.ORBIT_RADIUS) < 40.0), "Drones settle into orbit while their carrier keeps its distance")
	if not voyage.drones.is_empty():
		voyage.drones[0].strike(100.0)
	for tick in range(120):
		voyage._physics_process(TICK)
	_check(voyage.drones.size() == 6, "The carrier replaces a destroyed drone")
	carrier.deck.apply_hit(Hull.HULL_MAX, 0.0)
	for tick in range(245):
		voyage._physics_process(TICK)
	_check(voyage.drones.is_empty() and voyage.wrecks.size() == 1 and voyage.wrecks[0].collider != null,
		"Orphan drones detonate, and only the large carrier leaves a persistent collider")
	if voyage.wrecks.size() == 1:
		var obstacle := voyage.wrecks[0].collider
		obstacle.position = voyage.ship_position + Vector2(43, 0)
		obstacle.velocity = Vector2.ZERO
		voyage.heading = 0.0
		voyage.velocity = Vector2(65, 0)
		voyage._advance_wrecks(TICK)
		_check(voyage.velocity.x < 65.0 and obstacle.velocity.x > 0.0,
			"An impact transfers momentum between the player and a large wreck")
		var fighter := voyage.add_test_enemy(Voyage.Opponent.FIGHTER)
		fighter.position = obstacle.position - Vector2(170, 13)
		fighter.obstacles = voyage._wreck_colliders()
		_check(fighter._avoid_wrecks(Vector2(160, 0)).y < 0.0,
			"A fighter plans a detour on the clear side of a wreck")


func _check(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error(message)
