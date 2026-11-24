extends SceneTree
## Run with: godot --headless --path . --script res://tests/voyage_regression.gd

const Run = preload("res://flight/run.gd")
const Voyage = preload("res://flight/voyage_state.gd")
const Physics = Voyage.Physics
const SCENE := preload("res://flight/run.tscn")
const TICK := 1.0 / 60.0

var _run: Run
var _voyage: Voyage
var _failures := 0


func _initialize() -> void:
	call_deferred("_test_voyage")


func _test_voyage() -> void:
	_run = SCENE.instantiate()
	root.add_child(_run)
	_voyage = _run.voyage
	_check(_run.mode == Run.Mode.FLIGHT and _voyage.fuel == 5 and _voyage.deck.engine_health == 1.0,
		"Main scene starts in a healthy ship in local flight")
	_test_ship_physics()
	_test_slow_time()
	_run._reset()
	await _test_inertia_and_pause()

	_key(KEY_M)
	_system_click(Voyage.REFUGE)
	_key(KEY_ENTER)
	_check(_run.mode == Run.Mode.MAP and _voyage.current_system == Voyage.HOME and _voyage.fuel == 5,
		"Non-adjacent systems cannot be selected for a jump")
	_system_click(Voyage.DISTRESS)
	_key(KEY_ENTER)
	_check(_run.mode == Run.Mode.FLIGHT and not paused and _voyage.current_system == Voyage.DISTRESS,
		"A valid jump leaves the map and restores the previous pause")
	_check(_voyage.fuel == 3 and _voyage.deck.engine_health == 0.30 and _voyage.velocity.is_zero_approx(),
		"Jump spends fuel once and the scripted incident damages the ship")
	for door in _voyage.deck.doors.values():
		_check(door.automatic, "The incident keeps room doors in automatic mode")
	_check(is_instance_valid(_voyage.enemy), "The drill attacks near Cascade")

	_key(KEY_M)
	_system_click(Voyage.REFUGE)
	_key(KEY_ENTER)
	_check(_voyage.fuel == 3 and _voyage.current_system == Voyage.DISTRESS,
		"An impaired engine blocks a jump without spending fuel")
	_key(KEY_ESCAPE)

	Input.action_press("flight_fire")
	_tick(180)
	Input.action_release("flight_fire")
	_check(not is_instance_valid(_voyage.enemy) and _voyage.battle_result.is_empty(),
		"Destroying Cascade's attacker allows the rescue to continue")
	_key(KEY_E)
	_check(not _voyage.docked and _voyage.dock_blocker().contains("зону стыковки"), "Docking rejects distant ships")
	_approach_station()
	_key(KEY_E)
	_check(not _voyage.docked and _voyage.dock_blocker().contains("шлюз"), "Rescue requires a prepared airlock")

	await _prepare_ship()
	_check(_voyage.deck.engine_health == 1.0 and _voyage.deck.airlock_progress == 1.0,
		"Deck orders complete while the flight view is visible")
	_key(KEY_E)
	_check(_voyage.docking_time > 0.0 and not _voyage.docked and _voyage.survivors_onboard == 0,
		"Manual approach hands off to a timed capture before boarding")
	var capture_start := _voyage.ship_position
	_tick(40)
	_check(_voyage.docking_time > 0.0 and _voyage.ship_position.distance_to(capture_start) > 1.0 and not _voyage.fire(),
		"Capture visibly moves the ship and locks its weapons")
	_tick(80)
	_check(_voyage.docked and _voyage.stage == Voyage.Stage.DELIVER_SURVIVORS
		and _voyage.survivors_onboard == 8, "Docking at Cascade picks up eight survivors")
	_check(_voyage.deck.passengers.size() == 8 and _voyage.deck.passengers.all(
		func(passenger: Voyage.DeckSimulation.Passenger) -> bool: return _voyage.deck.tile_kind(passenger.cell) == "S"),
		"Passengers first come aboard through the airlock")
	var docked_angle := _voyage.station_body.heading
	var docked_position := _voyage.ship_position
	_tick(420)
	_check(docked_angle != _voyage.station_body.heading and docked_position != _voyage.ship_position
		and is_equal_approx(_voyage.distance_to_station(), Voyage.DOCK_RADIUS),
		"The moored ship shares the station's rotation")
	_check(_voyage.deck.passengers.all(func(passenger: Voyage.DeckSimulation.Passenger) -> bool:
		return passenger.cell == passenger.seat and _voyage.deck.tile_kind(passenger.cell) == "G"),
		"Passengers walk through the door and occupy their cargo seats")
	_check(not _voyage.fire(), "A docked ship cannot fire")
	_key(KEY_E)
	_key(KEY_E)
	_tick(110)
	_check(_voyage.survivors_onboard == 8, "Repeated docking does not board the same passengers twice")

	_check(_voyage.jump_blocker(Voyage.HOME).is_empty(), "Home is a valid evacuation destination")
	_key(KEY_M)
	_system_click(Voyage.REFUGE)
	_key(KEY_ENTER)
	_check(_voyage.current_system == Voyage.REFUGE and _voyage.fuel == 0,
		"The alternate haven is reachable using the remaining fuel")
	_key(KEY_M)
	_system_click(Voyage.DISTRESS)
	_key(KEY_ENTER)
	_check(_voyage.current_system == Voyage.REFUGE and _voyage.jump_blocker(Voyage.DISTRESS).contains("топлива"),
		"Insufficient fuel blocks a jump")
	_key(KEY_ESCAPE)
	_approach_station()
	_key(KEY_E)
	_tick(110)
	_check(_voyage.stage == Voyage.Stage.COMPLETE and _voyage.delivered == 8 and _voyage.survivors_onboard == 0,
		"Delivering at the safe station completes the scenario")
	_check(_voyage.deck.passengers.is_empty(), "Evacuees leave the cargo seats upon delivery")
	_check(_voyage.fuel == Voyage.FULL_FUEL, "The safe station refuels the ship")
	_key(KEY_E)
	_check(_voyage.delivered == 8 and _voyage.docked, "The completed report survives another docking input")

	_run._reset()
	_check(_run.mode == Run.Mode.FLIGHT and not paused and _voyage.current_system == Voyage.HOME,
		"Reset returns to the initial flight view")
	_check(_voyage.deck.engine_health == 1.0 and _voyage.deck.airlock_progress == 0.0
		and _voyage.delivered == 0 and not _voyage.incident_seen, "Reset clears all voyage and deck state")
	await _test_unbounded_flight_and_weapon()
	await _test_menu_and_training()
	await _test_adventure()
	if _failures == 0:
		print("Voyage regression checks passed.")
	quit(_failures)


func _test_menu_and_training() -> void:
	_run.free()
	var settings = root.get_node("GameSettings")
	var test_config := "user://settings-regression.cfg"
	_check(settings.rebind("flight_fire", KEY_R).is_empty()
		and not settings.rebind("flight_fire", KEY_W).is_empty()
		and settings.key_label("flight_fire") == "R", "A conflicting binding preserves both shortcuts")
	settings.set_volume("Weapons", 0.35)
	_check(settings.save_settings(test_config) == OK, "Settings are written to disk")
	settings.reset_keyboard()
	settings.load_settings(test_config)
	var fire_key: InputEventKey = InputMap.action_get_events("flight_fire")[0]
	_check(fire_key.physical_keycode == KEY_R and is_equal_approx(settings.volumes["Weapons"], 0.35)
		and is_equal_approx(settings.volumes["Alerts"], 1.0), "The assigned shortcut and individual channel volume reload")
	settings.load_settings()
	DirAccess.remove_absolute(test_config)

	var menu = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(menu)
	current_scene = menu
	_check(menu._panel.get_child_count() == 7, "The entry scene offers six menu actions")
	menu._show_campaign()
	_check(menu._panel.get_child(1).text.contains("Каскад"), "The campaign lists the existing rescue mission")
	menu._show_settings()
	_check(menu._binding_buttons.has("flight_fire"), "The settings page exposes the fire binding")
	menu._start(Run.Session.TRAINING)
	await process_frame
	_run = current_scene
	_voyage = _run.voyage
	var training := _run._training
	_check(_voyage.in_training and training.step == Run.Training.Step.TURN,
		"The training button launches the first objective")

	_train_until_next("flight_turn_right", 180)
	_train_until_next("flight_thrust", 240)
	_train_until_next("flight_brake", 300)
	_train_until_next("flight_fire", 240)
	_check(training.step == Run.Training.Step.SEAL and _voyage.deck.hull.breaches.size() == 1,
		"Real steering, thrust, braking and shooting create the training breach")
	if not _voyage.deck.hull.breaches.is_empty():
		_key(KEY_TAB)
		_key(KEY_2)
		_click(_run.deck._cell_center(_voyage.deck.hull.breaches.keys()[0]), MOUSE_BUTTON_RIGHT)
		_train_until_next("", 420)
		_check(training.step == Run.Training.Step.PREPARE, "Repairing the training breach advances the objective")
		_key(KEY_3)
		_click(_run.deck._cell_center(_voyage.deck.airlock_tile), MOUSE_BUTTON_RIGHT)
		_train_until_next("", 420)
		_check(training.step == Run.Training.Step.APPROACH, "Preparing the airlock enables the approach")
		_key(KEY_TAB)
		_voyage.ship_position = _voyage.station_position() + Vector2(-(Voyage.DOCK_RANGE - 7.0), 0)
		_voyage.velocity = Vector2.ZERO
		training.advance(false)
		_key(KEY_E)
		_tick(110)
		training.advance(false)
		_check(training.step == Run.Training.Step.COMPLETE and _voyage.delivered == 8,
			"Docking after the training objectives completes evacuation")
	_run._return_to_menu()
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.scene_file_path == "res://ui/main_menu.tscn",
		"Returning from a run restores the main menu")


func _test_adventure() -> void:
	var menu := current_scene
	var save_path := "user://adventure-regression.cfg"
	var run := SCENE.instantiate() as Run
	run.session = Run.Session.ADVENTURE
	run.adventure_save_path = save_path
	root.add_child(run)
	current_scene = run
	menu.queue_free()
	_run = run
	_voyage = run.voyage
	var voyage := _voyage
	_check(voyage.adventure != null and voyage.docked and voyage.system_count() == 6
		and FileAccess.file_exists(save_path), "Adventure has its own sector and initial station checkpoint")
	_run._open_journal()
	_check(paused and _run._adventure_panel.visible, "The station workshop opens and preserves the tactical view")
	_run._close_journal()
	_check(not paused and not _run._adventure_panel.visible, "Closing the workshop restores time")
	_check(voyage.accept_contract(0) and voyage.accept_contract(3) and voyage.deck.freight_count == 1,
		"The starter station offers a delivery and a combat contract")
	_check(not voyage.accept_contract(0), "The same contract cannot be accepted twice")
	_key(KEY_X)
	_check(voyage.weapon.kind == Voyage.WeaponProfile.Kind.LASER, "The remappable action selects the second installed weapon")
	_check(voyage.jump(Voyage.DISTRESS) and voyage.enemies.is_empty() and voyage.deck.engine_health == 1.0,
		"Adventure traffic does not trigger the scripted campaign incident")
	_check(voyage.jump(Voyage.REFUGE), "The delivery destination is reachable along the existing lanes")
	voyage._moor_at_checkpoint()
	voyage._arrive_at_adventure_station()
	_check(0 in voyage.adventure.settled and voyage.adventure.credits == 162 and voyage.deck.freight_count == 0,
		"Docking hands over freight and pays the delivery once")
	voyage._arrive_at_adventure_station()
	_check(voyage.adventure.credits == 162, "Docking again does not pay twice")
	_check(voyage.purchase_weapon(2) and voyage.mount_weapon(1, 2) and voyage.adventure.slots == [0, 2],
		"New equipment can be purchased and installed at a station")
	_check(voyage.jump(Voyage.Adventure.SCRAP) and voyage.enemies.size() == 2 and voyage.wrecks.size() == 4,
		"The wreck field contains the ambush and physical debris")
	for hostile in voyage.enemies:
		hostile.deck.apply_hit(Voyage.DeckSimulation.Hull.HULL_MAX, 0.0)
	voyage._advance_battle(TICK)
	var loot: Array = voyage.adventure.containers[Voyage.Adventure.SCRAP]
	_check(voyage.enemies.is_empty() and loot.size() == 2 and voyage.adventure.credits == 52,
		"Victory drops containers instead of immediately paying salvage")
	if not loot.is_empty():
		voyage.ship_position = loot[0].position
		voyage.velocity = Vector2(95, 0)
		_key(KEY_E)
		_check(loot.size() == 2, "Too much speed blocks salvage pickup")
		voyage.velocity = Vector2.ZERO
		_key(KEY_E)
		_check(loot.size() == 1 and voyage.adventure.credits > 52,
			"Interaction collects exactly one nearby container")
	voyage._moor_at_checkpoint()
	voyage._arrive_at_adventure_station()
	_check(3 in voyage.adventure.settled and voyage.refit("shield") and voyage.body.shield.capacity == 125.0,
		"The combat payout funds a shield capacity upgrade")
	_check(voyage.refit("thrusters") and voyage.body.turn_scale > Voyage.PLAYER_TURN_SCALE,
		"Thruster upgrades affect the player's angular acceleration")
	_check(voyage.jump(Voyage.REFUGE) and voyage.jump(Voyage.Adventure.ION),
		"The ion sector is reachable by jumping")
	var cloud: Vector3 = Voyage.ION_CLOUDS[0]
	voyage.ship_position = voyage.station_position() + Vector2(cloud.x, cloud.y)
	var reserve := voyage.deck.power.energy
	voyage._apply_ion_hazards(1.0)
	_check(is_equal_approx(reserve - voyage.deck.power.energy, 13.0),
		"Flying into an ion cloud drains the ship's energy")
	voyage.deck.apply_hit(Voyage.DeckSimulation.Hull.HULL_MAX, 0.0)
	_tick(1)
	_check(voyage.defeat_hull and not _run._defeat_panel.visible, "Hull loss starts the defeat animation before showing the dialog")
	_tick(150)
	_check(_run._defeat_panel.visible and _run._defeat_retry.text == "С сохранения",
		"Defeat finishes with a checkpoint recovery action")
	_run._reset()
	_check(voyage.current_system == Voyage.Adventure.SCRAP and voyage.docked and voyage.enemies.is_empty()
		and voyage.adventure.slots == [0, 2] and voyage.body.shield.capacity == 125.0
		and voyage.adventure.containers[Voyage.Adventure.SCRAP].size() == 1 and voyage.battle_result.is_empty(),
		"Recovery restores location, upgrades, contracts, loot and the defeated encounter set")
	DirAccess.remove_absolute(save_path)
	_run._return_to_menu()
	await process_frame
	await process_frame


func _train_until_next(action: String, limit: int) -> void:
	var step := _run._training.step
	if not action.is_empty():
		Input.action_press(action)
	for frame in limit:
		_tick(1)
		_run._training.advance(_run.mode == Run.Mode.DECK)
		if _run._training.step != step:
			break
	if not action.is_empty():
		Input.action_release(action)


func _test_ship_physics() -> void:
	var ship := Physics.Body.new()
	ship.model = _voyage.body.model
	var turn_group := Voyage.Physics.Model.Group.TURN_RIGHT
	_check(is_equal_approx(_voyage.body._group_torque(turn_group), ship._group_torque(turn_group) * 1.5)
		and is_equal_approx(_voyage.body.passive_angular_deceleration, 0.24),
		"The player's turn and stabilization nozzles and passive damping are strengthened")
	ship.advance(TICK, 0.0, 1.0, 0.0, false)
	var spin := ship.spin
	var heading := ship.heading
	ship.advance(TICK, 0.0, 0.0, 0.0, false)
	_check(spin > 0.0 and ship.spin == spin and ship.heading > heading and ship.velocity.is_zero_approx(),
		"Paired nozzles rotate the ship in place and preserve angular inertia")
	ship.advance(TICK, 0.0, 0.0, 0.0, true)
	_check(is_zero_approx(ship.spin), "Stabilization fires the opposite pair to arrest rotation")

	ship.heading = 0.0
	ship.velocity = Vector2(80, 50)
	ship.advance(TICK, 0.0, 0.0, 1.0, false, false)
	_check(ship.velocity.x < 80.0 and is_equal_approx(ship.velocity.y, 50.0),
		"Manual braking applies only axial counter-thrust")
	var side_drift := ship.velocity.y
	ship.advance(TICK, 0.0, 0.0, 1.0, true)
	_check(ship.velocity.y < side_drift and is_zero_approx(ship.spin),
		"The flight computer can brake sideways without introducing spin")

	var station := Physics.Body.new()
	station.model = _voyage.station_body.model
	station.fixed = true
	ship.position = Vector2(-197, 29)
	ship.velocity = Vector2(120, 0)
	var hit := Physics.contact(ship, station)
	_check(hit != null, "A hull corner overlaps the station")
	if hit != null:
		Physics.resolve(ship, station, hit, 0.15)
		_check(not is_zero_approx(ship.spin) and hit.closing_speed > 0.0 and station.position == Vector2.ZERO,
			"An off-center impact spins the hull around its mass center")
		_check(Physics.contact(ship, station) == null, "The contact solver separates the two polygons")

	var charge := _voyage.deck.power.energy
	_voyage.deck.power.energy = 0.0
	_voyage.angular_velocity = -0.08
	_voyage.advance_flight(0.6, 0.0, false, false)
	_check(is_zero_approx(_voyage.angular_velocity) and is_zero_approx(_voyage.deck.power.energy),
		"The player hull passively stops spinning without power or overshoot")
	_voyage.deck.power.energy = charge


func _test_slow_time() -> void:
	var test_speed := Vector2(80.0, -40.0)
	_voyage.velocity = test_speed
	_voyage.deck.power.energy = 30.0
	_check(_voyage.fire(), "The ship can fire before slowing time")
	var projectile := _voyage.projectiles[0]
	var start := projectile.position
	var ship_start := _voyage.ship_position
	var energy := _voyage.deck.power.energy
	Input.action_press("slow_time")
	_run._physics_process(TICK)
	_tick(6)
	_check(_voyage.simulation_speed == 0.25 and _voyage.deck.simulation_speed == 0.25,
		"Holding the action slows both the local field and the deck")
	_check(projectile.position.is_equal_approx(start + projectile.velocity * TICK * 1.5)
		and _voyage.ship_position.is_equal_approx(ship_start + test_speed * TICK * 1.5)
		and is_equal_approx(_voyage.deck.power.energy, energy + _voyage.deck.energy_recovery_rate() * TICK * 1.5),
		"Projectiles, ship motion and reactor recovery all advance at quarter speed")
	_key(KEY_TAB)
	_check(_voyage.deck.simulation_speed == 0.25, "Changing views while holding slow time preserves the speed")
	Input.action_release("slow_time")
	_run._physics_process(TICK)
	_check(_voyage.simulation_speed == 1.0 and _voyage.deck.simulation_speed == 1.0,
		"Releasing slow time restores normal play")
	_key(KEY_TAB)


func _test_inertia_and_pause() -> void:
	var initial_heading := _voyage.heading
	Input.action_press("flight_turn_right")
	_tick(29)
	Input.action_release("flight_turn_right")
	_check(absf(angle_difference(initial_heading, _voyage.heading)) > 0.1
		and _voyage.velocity.is_zero_approx(), "Maneuver thrusters turn the hull without translation")
	_tick(20)

	Input.action_press("flight_thrust")
	_tick(35)
	Input.action_release("flight_thrust")
	_check(_voyage.velocity.length() > 40.0 and _voyage.acceleration.dot(Vector2.from_angle(_voyage.heading)) > 80.0,
		"Main thrust accelerates along the hull")
	var speed := _voyage.velocity
	var position := _voyage.ship_position
	_key(KEY_TAB)
	_check(_run.mode == Run.Mode.DECK and not _voyage.manual_control, "Tab opens the persistent deck")
	Input.action_press("flight_turn_left")
	_tick(8)
	Input.action_release("flight_turn_left")
	_check(_voyage.velocity.is_equal_approx(speed) and _voyage.ship_position.distance_to(position) > 1.0
		and _voyage.acceleration.is_zero_approx(), "Deck view retains inertial motion without applying flight input")
	_key(KEY_SPACE)
	_key(KEY_M)
	position = _voyage.ship_position
	await physics_frame
	await physics_frame
	_check(_run.mode == Run.Mode.MAP and paused and _voyage.ship_position == position,
		"Sector map freezes the voyage")
	_key(KEY_ESCAPE)
	_check(_run.mode == Run.Mode.DECK and paused, "Closing the map restores the previous screen and pause")
	_key(KEY_SPACE)
	_key(KEY_TAB)
	_brake()


func _test_unbounded_flight_and_weapon() -> void:
	Input.action_press("flight_turn_left")
	_tick(64)
	Input.action_release("flight_turn_left")
	Input.action_press("flight_stabilize")
	_tick(120)
	Input.action_release("flight_stabilize")
	Input.action_press("flight_thrust")
	_tick(420)
	Input.action_release("flight_thrust")
	_check(_voyage.ship_position.x < -300.0 or _voyage.ship_position.y < -300.0,
		"The ship can leave all original screen boundaries")
	var center: Vector2 = _run.space.flight_view.size * 0.5
	var ship_on_screen: Vector2 = _run.space.flight_field.world_to_screen(_voyage.ship_position)
	_check(ship_on_screen.is_equal_approx(center), "The local viewport follows the ship in world space")

	var drift := _voyage.velocity
	Input.action_press("flight_turn_right")
	_tick(34)
	Input.action_release("flight_turn_right")
	_check(_voyage.velocity.is_equal_approx(drift), "Turning while coasting does not redirect velocity")
	_check(absf(_voyage.velocity.normalized().cross(Vector2.from_angle(_voyage.heading))) > 0.1,
		"The hull heading and drift can differ")
	Input.action_press("flight_fire")
	_tick(1)
	Input.action_release("flight_fire")
	_check(_voyage.projectiles.size() == 1, "Holding F with a manned weapon fires")
	if _voyage.projectiles.size() != 1:
		return
	var projectile := _voyage.projectiles[0]
	var start := projectile.position
	var initial_velocity := projectile.velocity
	_check(initial_velocity.normalized().is_equal_approx(Vector2.from_angle(_voyage.heading))
		and is_equal_approx(initial_velocity.length(), projectile.travel_speed),
		"The shot follows the hull even while the ship drifts in another direction")
	_check(not _voyage.fire(), "The mount enforces its cooldown")
	_key(KEY_M)
	await physics_frame
	await physics_frame
	_check(projectile.position == start, "Opening the map freezes live projectiles")
	_key(KEY_ESCAPE)
	_tick(30)
	_check(projectile.velocity == initial_velocity
		and projectile.position.is_equal_approx(start + initial_velocity * (30 * TICK)),
		"The projectile travels in a straight line at constant speed")

	_key(KEY_TAB)
	_key(KEY_4)
	_click(_run.deck._cell_center(_voyage.deck.weapons_tile + Vector2i(1, 1)), MOUSE_BUTTON_RIGHT)
	_key(KEY_TAB)
	_tick(200)
	_check(_voyage.projectiles.is_empty() and not _voyage.fire(),
		"Expired projectiles are removed and the empty station blocks firing")
	_key(KEY_TAB)
	_click(_run.deck._cell_center(_voyage.deck.weapons_tile), MOUSE_BUTTON_RIGHT)
	_key(KEY_TAB)
	_tick(45)
	_brake()
	_check(_voyage.fire() and _voyage.projectiles[0].velocity.normalized().is_equal_approx(Vector2.from_angle(_voyage.heading)),
		"At rest the gun fires along the hull and can fire again when the gunner returns")
	_run._reset()
	_check(_voyage.projectiles.is_empty(), "Reset clears local projectiles")
	_check(_voyage.fire() and _voyage.jump(Voyage.DISTRESS) and _voyage.projectiles.is_empty(),
		"Projectiles stay in the system they were fired in")


func _prepare_ship() -> void:
	_key(KEY_TAB)
	_key(KEY_SPACE)
	_key(KEY_2)
	_click(_run.deck._cell_center(_voyage.deck.engine_tile), MOUSE_BUTTON_RIGHT)
	_key(KEY_3)
	_click(_run.deck._cell_center(_voyage.deck.airlock_tile), MOUSE_BUTTON_RIGHT)
	var before := _voyage.deck.crew[1].cell
	await physics_frame
	await physics_frame
	_check(_voyage.deck.crew[1].cell == before and _voyage.deck.engine_health == 0.30,
		"Orders issued during pause do not execute yet")
	_key(KEY_SPACE)
	_key(KEY_TAB)
	_tick(720)


func _approach_station() -> void:
	# Start the piloting check on a clear final approach. Wreck collisions are tested separately.
	var bearing := _voyage.station_position().direction_to(_voyage.ship_position)
	_voyage.ship_position = _voyage.station_position() + bearing * (Voyage.DOCK_RANGE + 105.0)
	_voyage.heading = (-bearing).angle()
	_voyage.angular_velocity = 0.0
	_voyage.velocity = Vector2.ZERO
	Input.action_press("flight_thrust")
	for tick in range(420):
		if _voyage.distance_to_station() < Voyage.DOCK_RANGE:
			break
		if _voyage.velocity.length() > 53.0:
			Input.action_release("flight_thrust")
		_tick(1)
	Input.action_release("flight_thrust")
	_check(_voyage.distance_to_station() < Voyage.DOCK_RANGE, "The ship reaches the docking zone under thrust")
	_key(KEY_E)
	_check(not _voyage.docked and _voyage.dock_blocker().contains("скорость"), "Docking rejects a fast approach")
	_brake(5.0)
	_check(_voyage.velocity.length() <= Voyage.DOCK_SPEED
		and Voyage.Physics.contact(_voyage.body, _voyage.station_body) == null,
		"Braking before contact stops the ship inside the docking zone")


func _brake(tolerance := 0.001) -> void:
	Input.action_press("flight_brake")
	_tick(300)
	Input.action_release("flight_brake")
	_check(_voyage.velocity.length() < tolerance, "Active braking stops the ship within tolerance")


func _tick(count: int) -> void:
	for tick in range(count):
		_voyage._physics_process(TICK)
		_voyage.deck._physics_process(TICK)


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	root.push_input(event, true)


func _system_click(system: int) -> void:
	_click(_run.space._map_point(system), MOUSE_BUTTON_LEFT)


func _click(point: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)


func _check(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error(message)
