extends SceneTree
## Run with: godot --headless --path . --script res://tests/deck_regression.gd

const DeckSimulation = preload("res://deck/deck_simulation.gd")
const DECK := preload("res://deck/deck.tscn")
const CORRIDOR_LAYOUT := "res://tests/rescue_corridor_fixture.json"
const BRIDGE_DOOR := Vector4i(3, 3, 3, 4)
const WEAPON_DOOR := Vector4i(2, 8, 2, 9)
const TICK := 1.0 / 60.0

var _sim: DeckSimulation
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var deck := DECK.instantiate()
	root.add_child(deck)
	_sim = deck.get_node("Simulation")
	_check(paused, "The deck starts in tactical pause")
	_test_layout_connectivity()
	_check(_sim.load_layout(CORRIDOR_LAYOUT, false).is_empty(), "Load the corridor traffic fixture")
	await _test_pause()
	_test_unrelated_door()
	_test_closing_before_entry()
	_test_door_safety()
	_test_automatic_door()
	_test_imported_layout()
	_test_wait_for_empty_destination()
	_test_swap()
	_test_pass_stationary()
	_test_route_prefers_clear_path()
	_test_parallel_orders()
	_test_workstation_poses()
	_test_helm_exclusivity()
	_test_pass_workstations()
	_test_local_duties_and_casualties()
	if _failures == 0:
		print("Deck regression checks passed.")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _tick(count: int) -> void:
	for index in range(count):
		_sim._physics_process(TICK)
		var cells: Array[Vector2i] = []
		for member in _sim.crew:
			if member.cell in cells:
				_check(false, "Each logical crew position must remain exclusive")
				break
			cells.append(member.cell)


func _place(index: int, cell: Vector2i) -> void:
	_sim.crew[index].cell = cell
	_sim.crew[index].position = Vector2(cell)


func _test_pause() -> void:
	_sim.toggle_door(BRIDGE_DOOR)
	_sim.assign_order(1, _sim.ENGINE)
	await physics_frame
	await physics_frame
	_check(_sim.doors[BRIDGE_DOOR].openness == 0.0 and _sim.crew[1].landing == _sim.INVALID_CELL,
		"Tactical pause freezes door animation and crew movement together")


func _test_unrelated_door() -> void:
	_sim.reset()
	var engineer := _sim.crew[1]
	_place(1, Vector2i(5, 5))
	_sim.assign_order(1, _sim.ENGINE)
	_tick(5)
	var before := engineer.position
	var landing := engineer.landing
	var route := engineer.route.duplicate()
	_sim.toggle_door(WEAPON_DOOR)
	_check(engineer.position == before and engineer.landing == landing, "A door must not cancel an unrelated step")
	_tick(1)
	_check(engineer.position.distance_to(Vector2(landing)) < before.distance_to(Vector2(landing)),
		"An unrelated door must not reverse motion")
	_tick(10)
	_check(engineer.route == route, "A door that is still opening must not interrupt the route")
	var door := _sim.doors[WEAPON_DOOR]
	_check(door.openness > 0.0 and door.openness < 1.0 and not door.permits_entry(),
		"Opening is animated and only passable after reaching its endpoint")


func _test_closing_before_entry() -> void:
	_sim.reset()
	_sim.toggle_door(BRIDGE_DOOR)
	_tick(22)
	_place(1, Vector2i(3, 5))
	_sim.assign_order(1, Vector2i(3, 3))
	_tick(4)
	var engineer := _sim.crew[1]
	var door := _sim.doors[BRIDGE_DOOR]
	_sim.toggle_door(BRIDGE_DOOR)
	_check(not door.permits_entry() and engineer.blocked, "Closing blocks people who have not entered")
	_tick(9)
	_check(door.openness < 1.0 and door.openness > 0.0, "An empty door closes gradually")
	_tick(35)
	_check(door.openness == 0.0 and engineer.cell == Vector2i(3, 4),
		"The crew stops on the near side of a closing door")
	_sim.toggle_door(BRIDGE_DOOR)
	_tick(10)
	_check(engineer.landing == _sim.INVALID_CELL, "A partly open door does not admit entry")
	_tick(70)
	_check(engineer.cell == Vector2i(3, 3), "The waiting order resumes after opening")


func _test_door_safety() -> void:
	_sim.reset()
	_sim.toggle_door(BRIDGE_DOOR)
	_tick(22)
	_place(1, Vector2i(3, 4))
	_sim.assign_order(1, Vector2i(3, 3))
	_tick(5)
	var engineer := _sim.crew[1]
	var door := _sim.doors[BRIDGE_DOOR]
	var before := engineer.position.y
	_sim.toggle_door(BRIDGE_DOOR)
	_tick(8)
	_check(door.openness == 1.0 and engineer.position.y < before,
		"An admitted crossing keeps the door open and continues forward")
	_tick(14)
	_check(engineer.cell == Vector2i(3, 3) and door.openness < 1.0,
		"The door starts closing when the edge is clear")
	_tick(20)
	_check(door.openness == 0.0, "A stationary occupant on an adjacent tile does not hold the door open")


func _test_automatic_door() -> void:
	_sim.reset()
	var door := _sim.doors[BRIDGE_DOOR]
	_check(door.automatic and door.openness == 0.0, "Room doors start shut and in automatic mode")
	_place(1, Vector2i(3, 5))
	_sim.assign_order(1, Vector2i(3, 3))
	_tick(90)
	_check(_sim.crew[1].cell == Vector2i(3, 3) and door.openness == 0.0,
		"The approaching crew opens the door, then the room seals again")
	_sim.toggle_door(BRIDGE_DOOR)
	_tick(22)
	_sim.toggle_door(BRIDGE_DOOR)
	_sim.assign_order(1, Vector2i(3, 5))
	_tick(45)
	_check(_sim.crew[1].blocked and door.openness == 0.0, "Manual closure overrides automatic access")
	_sim.toggle_door(BRIDGE_DOOR)
	_check(door.automatic, "Third click returns the locked door to automatic mode")
	_tick(90)
	_check(_sim.crew[1].cell == Vector2i(3, 5), "Restoring automatic access resumes the waiting order")


func _test_layout_connectivity() -> void:
	_sim.reset()
	_check(_sim._build_navigation().is_empty(), "Every player floor tile and module is reachable through open doors")
	for index in range(_sim.crew.size()):
		_check(_sim.tile_kind(_sim.crew[index].cell) == ["B", "E", "S", "W"][index],
			"Each crew member initially occupies their specialty compartment")
	for edge in _sim.doors:
		var a := Vector2i(edge.x, edge.y)
		var b := Vector2i(edge.z, edge.w)
		_check(a.distance_squared_to(b) == 1 and _sim.hull.room_at.has(a) and _sim.hull.room_at.has(b),
			"Doors sit between floor tiles and do not occupy a cell")


func _test_imported_layout() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CORRIDOR_LAYOUT))
	data.name = "Испытательная палуба"
	data.edges.append({"kind": "hatch", "a": [1, 1], "b": [0, 1]})
	data.edges.append({"kind": "wall", "a": [1, 1], "b": [2, 1]})
	var path := "user://deck_import_regression.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	_check(_sim.load_layout(path).is_empty() and _sim.layout_name == data.name,
		"The game can load the deck editor's versioned JSON")
	var hatch := Vector4i(0, 1, 1, 1)
	var inside := Vector2i(1, 1)
	_check(not _sim.doors[hatch].automatic and _sim._path(inside, Vector2i(2, 1)).size() > 2,
		"Exterior doors default to manual and interior walls block their direct edge")
	_sim.set_automatic(hatch)
	_check(not _sim.doors[hatch].automatic, "Exterior doors cannot be made automatic")
	_sim.toggle_door(hatch)
	_tick(90)
	_check(_sim.hull.oxygen_at(inside) < 0.6 and _sim.hull.oxygen_at(_sim.engine_tile) == 1.0,
		"An open exterior door leaks only its compartment while internal doors are shut")
	_check(_sim._path(inside, Vector2i(0, 1)).is_empty(), "An exterior door never leads to a walkable tile")
	_sim.toggle_door(hatch)
	var oxygen := _sim.hull.oxygen_at(inside)
	_tick(35)
	_check(_sim.hull.oxygen_at(inside) > oxygen, "Closing the exterior door stops the leak")

	data.edges.pop_front()
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	_check(not _sim.load_layout(path).is_empty() and _sim.layout_name == "Испытательная палуба",
		"Rejecting an isolated compartment preserves the active deck")
	_check(_sim.load_layout(CORRIDOR_LAYOUT, false).is_empty(), "Restore the default deck after importing")


func _test_wait_for_empty_destination() -> void:
	_sim.reset()
	_place(1, Vector2i(3, 3))
	var occupied := _sim.crew[1].cell
	_sim.assign_order(0, occupied)
	_tick(25)
	_check(_sim.crew[0].cell != occupied and _sim.crew[0].blocked,
		"A MOVE order cannot end in an occupied tile")
	_sim.assign_order(1, Vector2i(4, 3))
	_tick(65)
	_check(_sim.crew[0].cell == occupied, "A blocked order resumes when its destination is vacated")


func _test_swap() -> void:
	_sim.reset()
	_place(0, Vector2i(5, 5))
	_place(1, Vector2i(6, 5))
	_sim.assign_order(0, Vector2i(6, 5))
	_sim.assign_order(1, Vector2i(5, 5))
	_tick(19)
	var a := _sim.crew[0]
	var b := _sim.crew[1]
	_check(a.squeeze > 0.5 and b.squeeze > 0.5, "A head-on encounter uses both squeeze poses")
	_check((a.position.y - 5.0) * (b.position.y - 5.0) < 0.0, "The crew sidesteps in opposite directions")
	_check(a.cell == Vector2i(5, 5) and b.cell == Vector2i(6, 5),
		"A squeeze lasts longer than a normal one-cell walk")
	_tick(40)
	_check(a.cell == Vector2i(6, 5) and b.cell == Vector2i(5, 5),
		"A head-on encounter swaps the two cells without creating duplicates")


func _test_pass_stationary() -> void:
	_sim.reset()
	_place(0, Vector2i(5, 5))
	_place(1, Vector2i(6, 5))
	_sim.assign_order(0, Vector2i(8, 5))
	_tick(30)
	var a := _sim.crew[0]
	var b := _sim.crew[1]
	_check(a.squeeze > 0.0 and b.squeeze > 0.0, "A stationary crew member yields to passing traffic")
	_check(a.gait > 0.0 and b.gait > 0.0, "Moving and yielding both advance their gait frames")
	_tick(100)
	_check(a.cell == Vector2i(8, 5) and b.cell == Vector2i(6, 5),
		"Passing never displaces the stationary crew member")


func _test_route_prefers_clear_path() -> void:
	_sim.reset()
	_place(0, Vector2i(2, 6))
	_place(1, Vector2i(5, 5))
	_place(2, Vector2i(6, 5))
	_sim.assign_order(0, Vector2i(14, 6))
	_check(Vector2i(7, 7) in _sim.crew[0].route, "Congestion can make the clear detour cheaper")
	_tick(320)
	_check(_sim.crew[0].cell == Vector2i(14, 6), "The lower corridor reaches the same junction")


func _test_parallel_orders() -> void:
	_sim.reset()
	_sim.assign_order(1, _sim.ENGINE)
	_sim.assign_order(2, _sim.AIRLOCK)
	_tick(520)
	_check(_sim.engine_health > 0.0 and _sim.airlock_progress > 0.0, "Both jobs run concurrently")
	_tick(500)
	_check(_sim.engine_health == 1.0 and _sim.airlock_progress == 1.0, "Both jobs complete")
	_check(_sim.crew[1].cell.distance_squared_to(_sim.ENGINE) == 1,
		"Repairs are done beside the module")


func _test_workstation_poses() -> void:
	var poses := DeckSimulation.WorkPose
	_sim.reset()
	_check(_sim.workstation_pose(_sim.crew[0]) == poses.HELM, "The pilot starts seated at the helm")
	_sim.assign_order(0, Vector2i(1, 2))
	_check(_sim.workstation_pose(_sim.crew[0]) == poses.NONE, "Leaving the helm restores the standing pose")
	_sim.assign_order(1, _sim.ENGINE)
	_sim.assign_order(2, _sim.AIRLOCK)
	_tick(60)
	_check(_sim.workstation_pose(_sim.crew[1]) == poses.REPAIR, "The engineer starts the voyage at the repair station")
	_check(_sim.crew[0].gait > 0.0 and _sim.crew[1].repair_phase > 0.0,
		"Walking and repairing advance separate animation clocks")
	for frame in range(520):
		if _sim.workstation_pose(_sim.crew[1]) == poses.REPAIR and _sim.workstation_pose(_sim.crew[2]) == poses.AIRLOCK:
			break
		_tick(1)
	_check(_sim.workstation_pose(_sim.crew[1]) == poses.REPAIR, "The engineer uses the repair pose")
	_check(_sim.workstation_pose(_sim.crew[2]) == poses.AIRLOCK, "The rescue specialist uses the airlock pose")
	_tick(360)
	_check(_sim.workstation_pose(_sim.crew[1]) == poses.NONE, "Finishing repairs restores the standing pose")
	_check(_sim.workstation_pose(_sim.crew[2]) == poses.AIRLOCK, "The airlock operator stays on post")
	_sim.assign_order(2, Vector2i(14, 10))
	_check(_sim.workstation_pose(_sim.crew[2]) == poses.NONE, "Leaving the airlock restores the standing pose")


func _test_helm_exclusivity() -> void:
	var helm := DeckSimulation.WorkPose.HELM
	_sim.reset()
	_place(1, Vector2i(3, 3))
	_place(2, Vector2i(4, 2))
	_sim.assign_order(1, _sim.BRIDGE)
	_sim.assign_order(2, _sim.BRIDGE)
	_tick(45)
	_check(_sim.workstation_pose(_sim.crew[0]) == helm and _sim.crew[1].blocked and _sim.crew[2].blocked,
		"An occupied helm only has one operator")
	_sim.assign_order(0, Vector2i(1, 2))
	_tick(100)
	_check(_sim.workstation_pose(_sim.crew[1]) == helm and _sim.crew[2].blocked,
		"Only one queued crew member can claim the vacated seat")
	_check(_sim.crew[1].cell == _sim.HELM_SEAT, "The helm uses one fixed seat")
	_sim.assign_order(1, Vector2i(4, 3))
	_tick(100)
	_check(_sim.workstation_pose(_sim.crew[2]) == helm, "Another crew member can subsequently take the helm")


func _test_pass_workstations() -> void:
	var poses := DeckSimulation.WorkPose
	_sim.reset()
	_place(1, Vector2i(1, 3))
	_sim.assign_order(1, Vector2i(3, 3))
	_tick(34)
	_check(_sim.crew[1].squeeze > 0.8 and _sim.crew[1].position.y > 3.0,
		"The passing crew member sidesteps away from the helm")
	_check(_sim.crew[0].squeeze == 0.0 and _sim.crew[0].position == Vector2(_sim.HELM_SEAT)
		and _sim.workstation_pose(_sim.crew[0]) == poses.HELM, "The seated operator keeps working")

	_sim.reset()
	_place(1, Vector2i(12, 2))
	_place(2, Vector2i(13, 2))
	_sim.assign_order(1, _sim.ENGINE)
	_sim.assign_order(2, Vector2i(11, 2))
	_tick(34)
	_check(_sim.crew[2].squeeze > 0.8 and _sim.crew[2].position.y < 2.0,
		"The passing crew member sidesteps away from the engine")
	_check(_sim.crew[1].squeeze == 0.0 and _sim.crew[1].position == Vector2(12, 2)
		and _sim.workstation_pose(_sim.crew[1]) == poses.REPAIR and _sim.engine_health > 0.0,
		"The engineer stays in the repair pose and keeps repairing")

func _test_local_duties_and_casualties() -> void:
	_sim.reset(true)
	_sim.auto_crew = true
	var engineer := _sim.crew[1]
	var first := _sim.engine_tile + Vector2i.RIGHT
	var second := _sim.engine_tile + Vector2i.LEFT
	_sim.hull.breaches[first] = 0.6
	_sim.hull.breaches[second] = 0.6
	_tick(330)
	_check(_sim.hull.breaches.is_empty(), "An idle engineer seals every reachable leak in their own room")

	_sim.reset(true)
	_sim.auto_crew = true
	var pilot := _sim.crew[0]
	_sim.assign_order(0, Vector2i(1, 2), true)
	_tick(110)
	_check(pilot.target == _sim.bridge_tile or _sim.helm_is_manned(), "A crew member in the bridge takes an empty helm")
	_sim.reset(true)
	_sim.auto_crew = false
	_place(1, Vector2i(6, 5))
	engineer = _sim.crew[1]
	_sim.assign_order(1, Vector2i(9, 5), true)
	_tick(7)
	var impact_position := engineer.position
	_check(engineer.landing != _sim.INVALID_CELL and impact_position != Vector2(engineer.cell), "The casualty is hit in transit")
	_sim._hurt_crew(engineer, 100.0)
	_tick(70)
	_check(engineer.position == impact_position and engineer.landing == _sim.INVALID_CELL,
		"A casualty remains at the exact impact position and releases the transit")
