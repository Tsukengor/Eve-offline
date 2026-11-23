extends Resource

enum Group { MAIN, TURN_LEFT, TURN_RIGHT, BRAKE }

@export var mass := 12.0
@export var moment := 3600.0
@export var center_of_mass := Vector2.ZERO
@export var muzzle := Vector2(0, -35)
@export var hull: PackedVector2Array
@export var nozzle_points: PackedVector2Array
@export var nozzle_forces: PackedVector2Array
@export var nozzle_groups: PackedInt32Array


func local_force(index: int) -> Vector2:
	return nozzle_forces[index]


func world_point(point: Vector2, center: Vector2, heading: float) -> Vector2:
	return center + (point - center_of_mass).rotated(heading + PI * 0.5)


func outline(center: Vector2, heading: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in hull:
		points.append(world_point(point, center, heading))
	return points
