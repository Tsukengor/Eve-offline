extends RefCounted

const Projectile = preload("res://flight/projectile.gd")
const Profile = preload("res://flight/weapon_profile.gd")
const Physics = preload("res://flight/ship_physics.gd")
const Deck = preload("res://deck/deck_simulation.gd")
const BLAST_SECONDS := 0.34


class Target:
	var body: Physics.Body
	var deck: Deck
	var hostile: bool

	func _init(ship: Physics.Body, interior: Deck, enemy: bool) -> void:
		body = ship
		deck = interior
		hostile = enemy


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
		Profile.Kind.LASER:
			shot.remaining = profile.laser_duration
		Profile.Kind.MISSILE:
			shot.remaining = profile.missile_fuse
			shot.velocity = Vector2.from_angle(angle) * profile.missile_speed
			var best := INF
			for target in targets:
				if target.hostile == hostile or target.deck.disabled():
					continue
				var offset := target.body.position - shooter.position
				var distance := offset.length_squared()
				if distance < best and absf(angle_difference(shooter.heading, offset.angle())) <= deg_to_rad(profile.missile_lock_angle * 0.5):
					shot.target_body = target.body
					shot.target_deck = target.deck
					best = distance
		Profile.Kind.EMP:
			shot.remaining = profile.emp_range / profile.emp_speed


static func tick(shot: Projectile, delta: float, targets: Array[Target], station: Physics.Body) -> bool:
	if shot.blast_time > 0.0:
		shot.blast_time = move_toward(shot.blast_time, 0.0, delta)
		return shot.blast_time > 0.0
	match shot.profile.kind:
		Profile.Kind.LASER:
			_laser(shot, delta, targets, station)
		Profile.Kind.EMP:
			_emp(shot, delta, targets)
		_:
			return _moving_shot(shot, delta, targets, station)
	return shot.remaining > 0.0


static func _moving_shot(shot: Projectile, delta: float, targets: Array[Target], station: Physics.Body) -> bool:
	var missile := shot.profile.kind == Profile.Kind.MISSILE
	if missile and is_instance_valid(shot.target_deck) and not shot.target_deck.disabled():
		var desired := shot.position.angle_to_point(shot.target_body.position)
		shot.angle = rotate_toward(shot.angle, desired, deg_to_rad(shot.profile.missile_turn_rate) * delta)
		shot.velocity = Vector2.from_angle(shot.angle) * shot.profile.missile_speed
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
			target.deck.apply_hit(shot.damage, shot.breach_chance, shot.crew_damage, _side(target, hit.point, shot.velocity))
		return false
	return shot.remaining > 0.0


static func _laser(shot: Projectile, delta: float, targets: Array[Target], station: Physics.Body) -> void:
	var powered := false
	for target in targets:
		if target.body == shot.shooter:
			powered = not target.deck.disabled() and target.deck.weapons_are_manned()
			break
	if not powered:
		shot.remaining = 0.0
		return
	var step := minf(delta, shot.remaining)
	shot.remaining -= step
	shot.position = shot.shooter.model.world_point(shot.mount, shot.shooter.position, shot.shooter.heading)
	shot.angle = shot.shooter.heading + shot.aim_offset
	var forward := Vector2.from_angle(shot.angle)
	shot.reach = minf(shot.profile.laser_range, shot.reach + shot.profile.laser_speed * step)
	shot.end = shot.position + forward * shot.reach
	var hit := _trace(shot, shot.position, shot.end, targets, station)
	if not hit.is_empty():
		shot.end = hit.point
	if not hit.has("target"):
		shot.contact_body = null
		return
	var target: Target = hit.target
	var side := _side(target, hit.point, forward)
	var new_contact := target.body != shot.contact_body
	if new_contact:
		shot.contact_body = target.body
		shot.contact_tile = target.deck._impact_cell(side)
	var chance := 1.0 - pow(1.0 - shot.breach_chance, step)
	target.deck.apply_hit(shot.damage * step, chance, shot.crew_damage * step, side, shot.contact_tile, new_contact)


static func _explode(shot: Projectile, targets: Array[Target]) -> void:
	shot.blast_time = BLAST_SECONDS
	for target in targets:
		if target.deck.disabled():
			continue
		var nearest := _closest_on_outline(shot.position, target.body.outline())
		var distance := shot.position.distance_to(nearest)
		if distance >= shot.profile.missile_blast_radius:
			continue
		var strength := 1.0 - distance / shot.profile.missile_blast_radius
		var side := _side(target, nearest, shot.velocity)
		target.deck.apply_hit(shot.damage * strength, shot.breach_chance * strength, shot.crew_damage * strength, side)


static func _emp(shot: Projectile, delta: float, targets: Array[Target]) -> void:
	var step := minf(delta, shot.remaining)
	shot.remaining -= step
	var previous := shot.reach
	shot.reach = minf(shot.profile.emp_range, previous + shot.profile.emp_speed * step)
	var half_angle := deg_to_rad(shot.profile.emp_angle * 0.5)
	for target in targets:
		if target.hostile == shot.hostile or target.deck.disabled() or shot.affected.has(target.body):
			continue
		var offset := target.body.position - shot.position
		if absf(angle_difference(shot.angle, offset.angle())) > half_angle:
			continue
		var closest := _closest_on_outline(shot.position, target.body.outline())
		var distance := closest.distance_to(shot.position)
		if distance < previous or distance > shot.reach:
			continue
		shot.affected[target.body] = true
		var strength := lerpf(1.0, shot.profile.emp_edge_strength, distance / shot.profile.emp_range)
		target.deck.apply_emp(shot.profile.emp_energy_drain * strength, shot.profile.emp_disable_duration * strength,
			ceili(shot.profile.emp_systems * strength), _side(target, closest, Vector2.from_angle(shot.angle)))


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
		if target.body == shot.shooter or target.deck.disabled() or (not friendly and target.hostile == shot.hostile):
			continue
		var point: Variant = Physics.segment_hit(start, finish, target.body.outline())
		if point != null and start.distance_squared_to(point) < best:
			best = start.distance_squared_to(point)
			result = {"point": point, "target": target}
	return result


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
