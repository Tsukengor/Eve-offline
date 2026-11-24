extends RefCounted

const Model = preload("res://flight/ship_model.gd")
const ShipPower = preload("res://deck/ship_power.gd")


class Body:
	# Full power cost per active nozzle in each group (energy per second).
	const NOZZLE_COST := [9.0, 4.0, 4.0, 10.0]

	var power: ShipPower
	var model: Model
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var heading := 0.0
	var spin := 0.0
	var passive_angular_deceleration := 0.0
	var fixed := false
	var mass_scale := 1.0
	var thrust_scale := 1.0
	var active: Dictionary[int, float] = {}

	func advance(delta: float, main: float, turn: float, brake: float, damp_spin: bool, assisted_brake := true, velocity_goal := Vector2.ZERO) -> float:
		active.clear()
		var forces := Vector2.ZERO
		var torque := 0.0
		var power_draw := 0.0
		var frame := heading + PI * 0.5
		var brake_force := Vector2.ZERO
		if brake > 0.0 and assisted_brake:
			# Each nozzle clamps its share of the opposing force requested by the controller.
			brake_force = (velocity_goal - velocity).rotated(-frame) * model.mass * mass_scale / delta
			for index in range(model.nozzle_groups.size()):
				if model.nozzle_groups[index] == Model.Group.MAIN:
					brake_force -= model.local_force(index) * main * thrust_scale
		var requested := turn
		if damp_spin and is_zero_approx(turn):
			var opposing := Model.Group.TURN_LEFT if spin > 0.0 else Model.Group.TURN_RIGHT
			var capacity := absf(_group_torque(opposing))
			if capacity > 0.0:
				requested = clampf(-spin * model.moment * mass_scale / (delta * capacity), -1.0, 1.0)
		for i in range(model.nozzle_points.size()):
			var local := model.local_force(i) * thrust_scale
			var throttle := 0.0
			var group := model.nozzle_groups[i]
			match group:
				Model.Group.MAIN:
					throttle = main
				Model.Group.TURN_LEFT:
					throttle = maxf(-requested, 0.0)
				Model.Group.TURN_RIGHT:
					throttle = maxf(requested, 0.0)
				Model.Group.BRAKE:
					if assisted_brake:
						throttle = clampf(brake_force.dot(local.normalized()) / local.length(), 0.0, brake)
					elif local.y > 0.0:
						throttle = brake
			if throttle <= 0.0:
				continue
			active[i] = throttle
			power_draw += NOZZLE_COST[group] * throttle * thrust_scale
			var force := local * throttle
			forces += force
			torque += (model.nozzle_points[i] - model.center_of_mass).cross(force)
		var supply := power.supply_thrusters(power_draw * delta) if power != null else 1.0
		if supply == 0.0:
			active.clear()
		elif supply < 1.0:
			for index in active:
				active[index] *= supply
		velocity += forces.rotated(frame) * delta * inverse_mass() * supply
		spin = move_toward(spin + torque * delta * inverse_moment() * supply, 0.0,
			passive_angular_deceleration * delta)
		heading = wrapf(heading + spin * delta, -PI, PI)
		return supply

	func _group_torque(group: int) -> float:
		var torque := 0.0
		for i in range(model.nozzle_points.size()):
			if model.nozzle_groups[i] == group:
				torque += (model.nozzle_points[i] - model.center_of_mass).cross(model.local_force(i) * thrust_scale)
		return torque

	func turn_toward(course: float, efficiency: float) -> float:
		var error := angle_difference(heading, course)
		var group := Model.Group.TURN_LEFT if spin > 0.0 else Model.Group.TURN_RIGHT
		var damping := absf(_group_torque(group)) * inverse_moment() * efficiency
		var stopping_spin := sqrt(2.0 * damping * absf(error))
		var desired_spin := signf(error) * minf(stopping_spin, minf(absf(error) * 3.0, 2.6))
		return clampf((desired_spin - spin) / maxf(damping * 0.20, 0.01), -1.0, 1.0) * efficiency

	func inverse_mass() -> float:
		return 0.0 if fixed else 1.0 / (model.mass * mass_scale)

	func inverse_moment() -> float:
		return 0.0 if fixed else 1.0 / (model.moment * mass_scale)

	func apply_impulse(impulse: Vector2, point: Vector2) -> void:
		velocity += impulse * inverse_mass()
		spin += (point - position).cross(impulse) * inverse_moment()

	func outline() -> PackedVector2Array:
		return model.outline(position, heading)


class Contact:
	var normal := Vector2.ZERO
	var point := Vector2.ZERO
	var depth := 0.0
	var closing_speed := 0.0


static func contact(a: Body, b: Body) -> Contact:
	var first := a.outline()
	var second := b.outline()
	var result := Contact.new()
	result.depth = INF
	for polygon in [first, second]:
		for index in range(polygon.size()):
			var edge: Vector2 = polygon[(index + 1) % polygon.size()] - polygon[index]
			var axis := edge.orthogonal().normalized()
			var p := _project(first, axis)
			var q := _project(second, axis)
			var positive := p.y - q.x
			var negative := q.y - p.x
			if positive <= 0.0 or negative <= 0.0:
				return null
			if minf(positive, negative) < result.depth:
				result.depth = minf(positive, negative)
				result.normal = axis if positive < negative else -axis
	var overlap := Geometry2D.intersect_polygons(first, second)
	if overlap.is_empty():
		result.point = (a.position + b.position) * 0.5
	else:
		for vertex in overlap[0]:
			result.point += vertex
		result.point /= overlap[0].size()
	return result


static func resolve(a: Body, b: Body, hit: Contact, bounce: float) -> void:
	var n := hit.normal
	var ra := hit.point - a.position
	var rb := hit.point - b.position
	var a_cross := ra.cross(n)
	var b_cross := rb.cross(n)
	var relative := b.velocity - a.velocity
	var approach := relative.dot(n) + b.spin * b_cross - a.spin * a_cross
	hit.closing_speed = maxf(0.0, -approach)
	var inverse_total := a.inverse_mass() + b.inverse_mass()
	if inverse_total <= 0.0:
		return
	var correction := n * (hit.depth + 0.02) / inverse_total
	a.position -= correction * a.inverse_mass()
	b.position += correction * b.inverse_mass()
	if approach >= 0.0:
		return
	var effective := inverse_total + a_cross * a_cross * a.inverse_moment() + b_cross * b_cross * b.inverse_moment()
	var impulse := n * (-(1.0 + bounce) * approach / effective)
	a.apply_impulse(-impulse, a.position + ra)
	b.apply_impulse(impulse, b.position + rb)


static func _project(points: PackedVector2Array, direction: Vector2) -> Vector2:
	var extent := Vector2(INF, -INF)
	for point in points:
		var projected := point.dot(direction)
		extent.x = minf(extent.x, projected)
		extent.y = maxf(extent.y, projected)
	return extent


static func segment_hit(start: Vector2, end: Vector2, outline: PackedVector2Array) -> Variant:
	if Geometry2D.is_point_in_polygon(start, outline):
		return start
	var nearest: Variant = null
	var shortest := INF
	for index in range(outline.size()):
		var point: Variant = Geometry2D.segment_intersects_segment(
			start, end, outline[index], outline[(index + 1) % outline.size()])
		if point == null:
			continue
		var distance := start.distance_squared_to(point)
		if distance < shortest:
			nearest = point
			shortest = distance
	return nearest
