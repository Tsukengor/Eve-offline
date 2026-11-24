extends RefCounted

const Projectile = preload("res://flight/projectile.gd")
const Profile = preload("res://flight/weapon_profile.gd")
const Physics = preload("res://flight/ship_physics.gd")
const Deck = preload("res://deck/deck_simulation.gd")
const Drone = preload("res://flight/drone.gd")
const BLAST_SECONDS := 0.34


class Target:
	var body: Physics.Body
	var deck: Deck
	var drone: Drone
	var hostile: bool

	func _init(ship: Physics.Body, interior: Deck, enemy: bool, unmanned: Drone = null) -> void:
		body = ship
		deck = interior
		drone = unmanned
		hostile = enemy

	func disabled() -> bool:
		return deck.disabled() if deck != null else drone.disabled()

	func damage_enabled() -> bool:
		return deck.damage_enabled if deck != null else drone.damage_enabled

	func has_field() -> bool:
		return body.shield != null and body.shield.active()

	func strike(damage: float, breach: float, crew: float, side: Vector2,
			tile := Deck.INVALID_CELL, announce := true) -> void:
		if deck != null:
			deck.apply_hit(damage, breach, crew, side, tile, announce)
		else:
			drone.strike(damage)

	func absorb(damage: float) -> void:
		if damage_enabled():
			body.shield.absorb(damage)


static func begin(shot: Projectile, profile: Profile, shooter: Physics.Body, mount: Vector2, angle: float,
		hostile: bool, targets: Array[Target]) -> void:
	shot.profile = profile
	shot.shooter = shooter
	shot.mount = mount
	shot.angle = angle
	shot.aim_offset = angle_difference(shooter.heading, angle)
	shot.hostile = hostile
	shot.damage = profile.damage
	shot.breach_chance = profile.breach_chance
	shot.crew_damage = profile.crew_damage
	shot.launch(shooter.model.world_point(mount, shooter.position, shooter.heading), Vector2.from_angle(angle))
	shot.end = shot.position
	match profile.kind:
		Profile.Kind.MISSILE:
			shot.remaining = profile.missile_fuse
			shot.velocity = Vector2.from_angle(angle) * profile.missile_speed
			var best := INF
			for target in targets:
				if target.hostile == hostile or target.disabled():
					continue
				var offset := target.body.position - shooter.position
				var distance := offset.length_squared()
				if distance < best and absf(angle_difference(shooter.heading, offset.angle())) <= deg_to_rad(profile.missile_lock_angle * 0.5):
					shot.target_body = target.body
					best = distance
		Profile.Kind.EMP:
			shot.remaining = profile.emp_range / profile.emp_speed
		Profile.Kind.RAIL:
			shot.velocity = Vector2.from_angle(angle) * profile.rail_speed
			shot.penetration_left = profile.rail_penetration


static func tick(shot: Projectile, delta: float, targets: Array[Target], station: Physics.Body) -> bool:
	if shot.blast_time > 0.0:
		shot.blast_time = move_toward(shot.blast_time, 0.0, delta)
		return shot.blast_time > 0.0
	match shot.profile.kind:
		Profile.Kind.LASER:
			return _laser(shot, delta, targets, station)
		Profile.Kind.EMP:
			_emp(shot, delta, targets)
		Profile.Kind.RAIL:
			return _rail(shot, delta, targets, station)
		_:
			return _moving_shot(shot, delta, targets, station)
	return shot.remaining > 0.0


static func _moving_shot(shot: Projectile, delta: float, targets: Array[Target], station: Physics.Body) -> bool:
	var missile := shot.profile.kind == Profile.Kind.MISSILE
	if missile and shot.target_body != null:
		for target in targets:
			if target.body != shot.target_body or target.disabled():
				continue
			var desired := shot.position.angle_to_point(shot.target_body.position)
			shot.angle = rotate_toward(shot.angle, desired, deg_to_rad(shot.profile.missile_turn_rate) * delta)
			shot.velocity = Vector2.from_angle(shot.angle) * shot.profile.missile_speed
			break
	var before := shot.position
	shot.advance(delta)
	var hit := _trace(shot, before, shot.position, targets, station, missile)
	if missile and (not hit.is_empty() or shot.remaining <= 0.0):
		if not hit.is_empty():
			shot.position = hit.point
		_explode(shot, targets)
		return true
	if not hit.is_empty():
		if hit.has("target"):
			var target: Target = hit.target
			if hit.field:
				target.absorb(shot.damage)
			else:
				target.strike(shot.damage, shot.breach_chance, shot.crew_damage, _side(target, hit.point, shot.velocity))
		return false
	return shot.remaining > 0.0


static func _laser(shot: Projectile, delta: float, targets: Array[Target], station: Physics.Body) -> bool:
	var source: Deck
	for target in targets:
		if target.body == shot.shooter:
			source = target.deck
			break
	if source == null or source.disabled() or not source.weapons_are_manned():
		return false
	var cost := minf(source.power.energy, shot.profile.laser_energy_per_second * delta)
	if cost <= 0.0:
		return false
	source.power.spend(cost)
	var step := cost / shot.profile.laser_energy_per_second
	shot.position = shot.shooter.model.world_point(shot.mount, shot.shooter.position, shot.shooter.heading)
	shot.angle = shot.shooter.heading + shot.aim_offset
	var forward := Vector2.from_angle(shot.angle)
	var extent := 1.0
	if station != null:
		extent = _beam_extent(shot.position, forward, station.outline(), extent)
	for target in targets:
		if target.hostile != shot.hostile:
			extent = _beam_extent(shot.position, forward, target.body.outline(), extent)
			if target.has_field():
				extent = maxf(extent, (target.body.position - shot.position).dot(forward) + target.body.shield_radius() + 1.0)
	var hit := _trace(shot, shot.position, shot.position + forward * extent, targets, station)
	shot.beam_blocked = not hit.is_empty()
	if shot.beam_blocked:
		shot.end = hit.point
	var interval := 1.0 / shot.profile.laser_ticks_per_second
	shot.beam_tick_elapsed += step
	var ticks := floori((shot.beam_tick_elapsed + 0.000001) / interval)
	shot.beam_tick_elapsed = maxf(0.0, shot.beam_tick_elapsed - ticks * interval)
	if not hit.has("target"):
		shot.contact_body = null
		return source.power.energy > 0.0
	var target: Target = hit.target
	var side := _side(target, hit.point, forward)
	if ticks == 0:
		return source.power.energy > 0.0
	var new_contact: bool = target.body != shot.contact_body or shot.contact_field != hit.field
	if new_contact:
		shot.contact_body = target.body
		shot.contact_field = hit.field
		shot.contact_tile = target.deck._impact_cell(side) if target.deck != null and not hit.field else Deck.INVALID_CELL
	var chance := 1.0 - pow(1.0 - shot.breach_chance, interval)
	for tick_index in range(ticks):
		if hit.field:
			if target.body.shield.active():
				target.absorb(shot.damage * interval * 0.25)
		else:
			target.strike(shot.damage * interval, chance, shot.crew_damage * interval, side, shot.contact_tile,
				new_contact and tick_index == 0)
	return source.power.energy > 0.0


static func _beam_extent(start: Vector2, direction: Vector2, polygon: PackedVector2Array, extent: float) -> float:
	for vertex in polygon:
		extent = maxf(extent, (vertex - start).dot(direction) + 1.0)
	return extent


static func _explode(shot: Projectile, targets: Array[Target]) -> void:
	shot.blast_time = BLAST_SECONDS
	for target in targets:
		if target.disabled():
			continue
		if target.has_field():
			var edge_distance := shot.position.distance_to(target.body.position) - target.body.shield_radius()
			if edge_distance >= 0.0:
				if edge_distance < shot.profile.missile_blast_radius:
					target.absorb(shot.damage * (1.0 - edge_distance / shot.profile.missile_blast_radius))
				continue
		var nearest := _closest_on_outline(shot.position, target.body.outline())
		var distance := shot.position.distance_to(nearest)
		if distance >= shot.profile.missile_blast_radius:
			continue
		var strength := 1.0 - distance / shot.profile.missile_blast_radius
		var side := _side(target, nearest, shot.velocity)
		target.strike(shot.damage * strength, shot.breach_chance * strength, shot.crew_damage * strength, side)


static func _emp(shot: Projectile, delta: float, targets: Array[Target]) -> void:
	var step := minf(delta, shot.remaining)
	shot.remaining -= step
	var previous := shot.reach
	shot.reach = minf(shot.profile.emp_range, previous + shot.profile.emp_speed * step)
	var half_angle := deg_to_rad(shot.profile.emp_angle * 0.5)
	for target in targets:
		if target.hostile == shot.hostile or target.disabled() or shot.affected.has(target.body):
			continue
		var shielded := target.has_field()
		var outline := _field_outline(target.body) if shielded else target.body.outline()
		var contact: Variant = _sector_front(shot.position, shot.angle, half_angle, outline, previous, shot.reach)
		if contact == null:
			continue
		var closest: Vector2 = contact
		var distance := closest.distance_to(shot.position)
		shot.affected[target.body] = true
		var strength := lerpf(1.0, shot.profile.emp_edge_strength, distance / shot.profile.emp_range)
		if not target.damage_enabled():
			continue
		if shielded:
			target.body.shield.suppress()
		elif target.deck != null:
			target.deck.apply_emp(shot.profile.emp_energy_drain * strength, shot.profile.emp_disable_duration * strength,
				ceili(shot.profile.emp_systems * strength), _side(target, closest, Vector2.from_angle(shot.angle)),
				shot.profile.emp_recovery_suppression * strength)
		else:
			target.drone.disabled_time = shot.profile.emp_disable_duration * strength


# Test the moving front against the part of the hull inside the wedge, including its two radial edges.
static func _sector_front(origin: Vector2, angle: float, half: float, polygon: PackedVector2Array,
		previous: float, reach: float) -> Variant:
	var nearest := Vector2.ZERO
	var min_distance := INF
	var max_distance := 0.0
	var inside := Geometry2D.is_point_in_polygon(origin, polygon)
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		var points: Array[Vector2] = [a, Geometry2D.get_closest_point_to_segment(origin, a, b)]
		var length := maxf(a.distance_to(origin), b.distance_to(origin)) + 1.0
		for boundary in [angle - half, angle + half]:
			var intersection: Variant = Geometry2D.segment_intersects_segment(origin, origin + Vector2.from_angle(boundary) * length, a, b)
			if intersection != null:
				points.append(intersection)
		for point in points:
			var offset := point - origin
			if absf(angle_difference(angle, offset.angle())) > half + 0.0001:
				continue
			var distance := offset.length()
			max_distance = maxf(max_distance, distance)
			if distance < min_distance:
				nearest = point
				min_distance = distance
	if inside and previous == 0.0:
		return origin
	if min_distance > reach or max_distance < previous:
		return null
	return origin + origin.direction_to(nearest) * previous if min_distance < previous else nearest


static func _rail(shot: Projectile, delta: float, targets: Array[Target], station: Physics.Body) -> bool:
	var start := shot.position
	shot.advance(delta)
	var finish := shot.position
	var station_hit: Variant = Physics.segment_hit(start, finish, station.outline()) if station != null else null
	if station_hit != null:
		finish = station_hit
	var crossings: Array[Dictionary] = []
	for target in targets:
		if target.hostile == shot.hostile or target.disabled():
			continue
		if target.has_field():
			var contact: Variant = _field_entry(start, finish, target.body)
			if contact != null:
				crossings.append({"target": target, "field": true, "distance": start.distance_squared_to(contact)})
		var outline := target.body.outline()
		var entry: Variant = Physics.segment_hit(start, finish, outline)
		if entry == null:
			continue
		var exit_point: Vector2 = Physics.segment_hit(finish, start, outline)
		var visited: Dictionary = shot.penetrated.get(target.body, {})
		shot.penetrated[target.body] = visited
		if target.deck == null:
			crossings.append({"target": target, "distance": start.distance_squared_to(entry), "tile": Deck.INVALID_CELL})
		else:
			_rail_cells(target, entry, exit_point, start, visited, crossings)
	crossings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	for crossing in crossings:
		var target: Target = crossing.target
		if crossing.get("field", false):
			if target.body.shield.charge >= target.body.shield.capacity * 0.5:
				target.absorb(shot.damage)
				return false
			target.absorb(target.body.shield.capacity)
			continue
		var visited := shot.penetrated[target.body]
		var room: int = target.deck.hull.room_at[crossing.tile] if target.deck != null else 0
		if visited.has(room):
			continue
		visited[room] = true
		var side := _side(target, start, shot.velocity)
		target.strike(shot.damage, shot.breach_chance, shot.crew_damage, side, crossing.tile)
		shot.penetration_left -= 1
		if shot.penetration_left <= 0:
			return false
		shot.damage *= shot.profile.rail_retention
		shot.crew_damage *= shot.profile.rail_retention
	return station_hit == null and shot.remaining > 0.0


static func _rail_cells(target: Target, entry: Vector2, end: Vector2, start: Vector2,
		visited: Dictionary, crossings: Array[Dictionary]) -> void:
	var hull_bounds := Rect2(target.body.model.hull[0], Vector2.ZERO)
	for point in target.body.model.hull:
		hull_bounds = hull_bounds.expand(point)
	var local_rotation := -target.body.heading - PI * 0.5
	var model_center := target.body.model.center_of_mass
	var deck_bounds := target.deck.floor_bounds
	var a := deck_bounds.position + ((entry - target.body.position).rotated(local_rotation) + model_center - hull_bounds.position) / hull_bounds.size * deck_bounds.size
	var b := deck_bounds.position + ((end - target.body.position).rotated(local_rotation) + model_center - hull_bounds.position) / hull_bounds.size * deck_bounds.size
	for tile: Vector2i in target.deck.hull.room_at:
		if visited.has(target.deck.hull.room_at[tile]):
			continue
		var ratio := _cell_entry(a, b, Rect2(Vector2(tile), Vector2.ONE))
		if ratio <= 1.0:
			crossings.append({"target": target, "tile": tile, "distance": start.distance_squared_to(entry.lerp(end, ratio))})


static func _cell_entry(from: Vector2, to: Vector2, cell: Rect2) -> float:
	var lo := 0.0
	var hi := 1.0
	for axis in [0, 1]:
		var motion := to[axis] - from[axis]
		if is_zero_approx(motion):
			if from[axis] < cell.position[axis] or from[axis] >= cell.end[axis]:
				return INF
			continue
		var a := (cell.position[axis] - from[axis]) / motion
		var b := (cell.end[axis] - from[axis]) / motion
		lo = maxf(lo, minf(a, b))
		hi = minf(hi, maxf(a, b))
		if lo >= hi:
			return INF
	return lo


static func _trace(shot: Projectile, start: Vector2, finish: Vector2, targets: Array[Target],
		station: Physics.Body, friendly := false) -> Dictionary:
	var result := {}
	var best := INF
	if station != null:
		var point: Variant = Physics.segment_hit(start, finish, station.outline())
		if point != null:
			best = start.distance_squared_to(point)
			result = {"point": point}
	for target in targets:
		if target.body == shot.shooter or target.disabled() or (not friendly and target.hostile == shot.hostile):
			continue
		var shield: Variant = _field_entry(start, finish, target.body) if not friendly and target.has_field() else null
		var point: Variant = shield if shield != null else Physics.segment_hit(start, finish, target.body.outline())
		if point != null and start.distance_squared_to(point) < best:
			best = start.distance_squared_to(point)
			result = {"point": point, "target": target, "field": shield != null}
	return result


static func _field_entry(start: Vector2, finish: Vector2, body: Physics.Body) -> Variant:
	var radius := body.shield_radius()
	if start.distance_squared_to(body.position) < radius * radius:
		return null
	var fraction := Geometry2D.segment_intersects_circle(start, finish, body.position, radius)
	return start.lerp(finish, fraction) if fraction >= 0.0 else null


static func _field_outline(body: Physics.Body) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius := body.shield_radius()
	for index in range(24):
		points.append(body.position + Vector2.from_angle(TAU * index / 24.0) * radius)
	return points


static func _closest_on_outline(point: Vector2, polygon: PackedVector2Array) -> Vector2:
	if Geometry2D.is_point_in_polygon(point, polygon):
		return point
	var nearest := polygon[0]
	for index in range(polygon.size()):
		var candidate := Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])
		if point.distance_squared_to(candidate) < point.distance_squared_to(nearest):
			nearest = candidate
	return nearest


static func _side(target: Target, point: Vector2, incoming: Vector2) -> Vector2:
	var side := point - target.body.position
	if side.is_zero_approx():
		side = -incoming
	return side.rotated(-target.body.heading - PI * 0.5)
