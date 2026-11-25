extends Node2D

const Voyage = preload("res://flight/voyage_state.gd")
const Model = preload("res://flight/ship_model.gd")
const Physics = preload("res://flight/ship_physics.gd")
const SHIP := preload("res://assets/flight/rescue_ship.png")
const PLAYER_WRECK := preload("res://assets/flight/rescue_wreck.png")
const CREW_LOSS_FRAMES := preload("res://assets/flight/rescue_crew_loss.png")
const ASTEROIDS := preload("res://assets/flight/asteroid_belt.png")
const CONTAINER := preload("res://assets/flight/salvage_container.png")
const ION_CLOUD := preload("res://assets/flight/ion_cloud.png")
const STATION := preload("res://assets/flight/orbital_station.png")
const DISTRESS_STATION := preload("res://assets/flight/orbital_station_distress.png")
const DOCK_CLAMPS := preload("res://assets/flight/docking_clamps.png")
const HIT_FRAMES := preload("res://assets/flight/impact_frames.png")
const WRECK_FRAMES := preload("res://assets/flight/ship_explosion_frames.png")
const BLACKOUT_FRAMES := preload("res://assets/flight/crew_blackout_frames.png")
const EXHAUST := preload("res://assets/flight/thruster.png")
const MANEUVER_EXHAUST := preload("res://assets/flight/maneuver_thruster.png")
const MUZZLE_FLASH := preload("res://assets/flight/muzzle_flash.png")
const LASER_BEAM := preload("res://assets/flight/laser_beam.png")
const MISSILE := preload("res://assets/flight/guided_missile.png")
const EXPLOSION := preload("res://assets/flight/missile_blast.png")
const EMP_SPARK := preload("res://assets/flight/emp_spark.png")
const RAIL_BOLT := preload("res://assets/flight/rail_bolt.png")
const DRONE := preload("res://assets/flight/swarm_drone.png")
const SHIELD := preload("res://assets/flight/shield_field.png")
const SHIELD_HIT := preload("res://assets/flight/shield_hit.png")
const Profile = preload("res://flight/weapon_profile.gd")
const REACTOR := preload("res://assets/deck/reactor.png")
const ROOM_DAMAGE := preload("res://assets/deck/room_damage.png")
const TELEPORT_FLASH := preload("res://assets/deck/teleport_flash.png")
const STARFIELD := preload("res://assets/flight/starfield.png")

const SCAN_FLOORS := {
	"B": Color("#36526b"), "E": Color("#3c4a5d"), "S": Color("#365450"),
	"C": Color("#243447"), "W": Color("#583c51"), "L": Color("#34566a"), "R": Color("#554b3c"),
	"G": Color("#505244"), "H": Color("#325363"), "T": Color("#544477"),
}

const GRID_PITCH := 84.0
const GRID := Color(0.47, 0.62, 0.78, 0.14)
const VELOCITY_COLOR := Color("#78ead0")
const ACCELERATION_COLOR := Color("#f7bf79")

@onready var frame: Control = get_parent()
var voyage: Voyage
var _font := ThemeDB.fallback_font


func world_to_screen(point: Vector2) -> Vector2:
	return frame.size * 0.5 + (point - voyage.ship_position) * voyage.computer.zoom()


func _world_point(point: Vector2) -> Vector2:
	return world_to_screen(point) / voyage.computer.zoom()


func _draw() -> void:
	if voyage == null:
		return
	var zoom := voyage.computer.zoom()
	var size := frame.size / zoom
	var center := size * 0.5
	draw_texture_rect(STARFIELD, Rect2(Vector2.ZERO, size), false)
	_draw_grid(size)
	_draw_environment(size)
	_draw_asteroids(size)
	if not voyage.in_arena:
		_draw_station(size)
	_draw_wrecks(size)
	for hostile in voyage.enemies:
		_draw_enemy(hostile, size)
	for drone in voyage.drones:
		_draw_drone(drone, size)
	_draw_projectiles(size)
	_draw_ship()
	if voyage.deck.teleport_flash > 0.0:
		_sprite(TELEPORT_FLASH, center, 94.0, Color(1.0, 1.0, 1.0, voyage.deck.teleport_flash))
	if not voyage.battle_result.is_empty():
		var dim := smoothstep(0.45, Voyage.DEFEAT_SECONDS, voyage.defeat_elapsed)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.028, 0.045, dim * 0.62))
		return
	_draw_vector(center, voyage.velocity * 0.48, VELOCITY_COLOR, "v", false)
	_draw_vector(center, voyage.acceleration * 0.35, ACCELERATION_COLOR, "a", true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / zoom)
	size = frame.size
	_draw_computer(size)
	if voyage.scan_enemy and voyage.scanner_available() and is_instance_valid(voyage.enemy):
		_draw_scan(size)
	_text("v  Скорость", Vector2(18, size.y - 18), 13, VELOCITY_COLOR)
	_text("a  Ускорение", Vector2(122, size.y - 18), 13, ACCELERATION_COLOR)
	if get_tree().paused:
		_text("На паузе", Vector2(size.x - 116.0, 28), 15, ACCELERATION_COLOR)
	elif voyage.simulation_speed < 1.0:
		_text("Время 0,25×", Vector2(size.x - 116.0, 28), 15, ACCELERATION_COLOR)


func _draw_grid(size: Vector2) -> void:
	var origin := voyage.ship_position - size * 0.5
	var start := Vector2(fposmod(-origin.x, GRID_PITCH), fposmod(-origin.y, GRID_PITCH))
	var x := start.x
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID)
		x += GRID_PITCH
	var y := start.y
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID)
		y += GRID_PITCH


func _draw_environment(size: Vector2) -> void:
	if voyage.adventure == null:
		return
	var available := Rect2(Vector2.ZERO, size)
	if voyage.current_system == Voyage.Adventure.ION:
		for cloud: Vector3 in Voyage.ION_CLOUDS:
			var center := _world_point(voyage.station_position() + Vector2(cloud.x, cloud.y))
			if available.grow(cloud.z).has_point(center):
				_sprite(ION_CLOUD, center, cloud.z * 2.0)
				for segment in range(18):
					var start := TAU * segment / 18.0
					draw_arc(center, cloud.z, start, start + 0.20, 6, Color("#4c758e"), 1.0, true)
	for item: Voyage.Adventure.SalvageCrate in voyage.adventure.containers.get(voyage.current_system, []):
		var point := _world_point(item.position)
		if not available.grow(15.0).has_point(point):
			continue
		draw_set_transform(point, item.body.heading)
		_sprite(CONTAINER, Vector2.ZERO, 27.0)
		draw_set_transform(Vector2.ZERO)
		if voyage.salvage_contact() == item:
			draw_arc(point, 17.0, 0.0, TAU, 24, VELOCITY_COLOR, 1.0, true)


func _draw_station(size: Vector2) -> void:
	var station := _world_point(voyage.station_position())
	var label: String = "«%s»" % Voyage.SYSTEMS[voyage.current_system].station
	var distress := voyage.adventure == null and voyage.current_system == Voyage.DISTRESS
	var active_distress := distress and voyage.stage == Voyage.Stage.ANSWER_DISTRESS
	var color := ACCELERATION_COLOR if active_distress else VELOCITY_COLOR
	var visible_area := Rect2(Vector2.ZERO, size)
	if visible_area.grow(Voyage.DOCK_RANGE).has_point(station):
		var ring := Color(color, 0.56 if voyage.distance_to_station() < 255.0 else 0.24)
		for segment in range(16):
			var start := TAU * segment / 16.0
			draw_arc(station, Voyage.DOCK_RANGE, start, start + TAU * 0.57 / 16.0, 6, ring, 1.0, true)
		var rotation := voyage.station_body.heading + PI * 0.5
		draw_set_transform(station, rotation)
		_sprite(DISTRESS_STATION if distress else STATION, Vector2.ZERO, Voyage.STATION_SIZE)
		draw_set_transform(Vector2.ZERO)
		if voyage.docking_time > 0.0 or voyage.docked:
			var angle := voyage.dock_angle + rotation
			var clamp_position := station + Vector2.from_angle(angle) * (Voyage.STATION_SIZE * 0.5 + 2.0)
			draw_set_transform(clamp_position, angle)
			var sprite_frame := 1 if voyage.docked else 0
			var glow := 1.0 if voyage.docked else 0.7 + 0.3 * sin(voyage.docking_time * 15.0)
			draw_texture_rect_region(DOCK_CLAMPS, Rect2(-12, -12, 24, 24), Rect2(sprite_frame * 24, 0, 24, 24),
				Color(1.0, 1.0, 1.0, glow))
			draw_set_transform(Vector2.ZERO)
		var label_position := station + Vector2(0, Voyage.STATION_SIZE * 0.5 + 23.0)
		if visible_area.has_point(station) and visible_area.grow(-34.0).has_point(label_position):
			_centered(label, label_position, color)
	if not visible_area.has_point(station) and (active_distress or voyage.computer.enabled("objects")):
		_draw_station_bearing(size, station, label, color if active_distress else _scanner_color(color))


func _draw_enemy(enemy: Voyage.EnemyShip, size: Vector2) -> void:
	if not is_instance_valid(enemy) or enemy.disabled():
		return
	var point := _world_point(enemy.position)
	var danger := Color("#ff8c85")
	var visible := Rect2(Vector2.ZERO, size)
	if visible.grow(48.0).has_point(point):
		_draw_thrusters(enemy.body)
		draw_set_transform(_world_point(enemy.model.world_point(Vector2.ZERO, enemy.position, enemy.heading)), enemy.heading + PI * 0.5)
		var condition := enemy.deck.hull.integrity / Voyage.DeckSimulation.Hull.HULL_MAX
		var damaged := Color.WHITE.lerp(danger, (1.0 - condition) * 0.55)
		var flash := enemy.hit_remaining / Voyage.EnemyShip.HIT_SECONDS
		_sprite(enemy.sprite, Vector2.ZERO, enemy.sprite_size, damaged.lerp(Color("#fff4d5"), flash * 0.65))
		if enemy.hit_remaining > 0.0:
			var index := mini(4, int((1.0 - flash) * 5.0))
			_effect_frame(HIT_FRAMES, index, enemy.hit_side * enemy.sprite_size * 0.35, 34.0)
		if enemy.flash_remaining > 0.0 and enemy.weapon != null:
			for mount in enemy.weapon.mounts:
				_sprite(MUZZLE_FLASH, mount, 19.0, Color(1, 0.7, 0.5, enemy.flash_remaining / Voyage.FLASH_SECONDS))
		draw_set_transform(Vector2.ZERO)
		_draw_shield(enemy.body)
		if enemy.deck.teleport_flash > 0.0:
			_sprite(TELEPORT_FLASH, point, 105.0, Color(1.0, 1.0, 1.0, enemy.deck.teleport_flash))
		if not visible.has_point(point):
			_draw_threat(size, enemy)
			return
		draw_rect(Rect2(point + Vector2(-24, 43), Vector2(48, 3)), Color("#30465c"))
		draw_rect(Rect2(point + Vector2(-24, 43), Vector2(48 * condition, 3)), danger)
		if enemy.body.shield != null:
			draw_rect(Rect2(point + Vector2(-24, 49), Vector2(48, 2)), Color("#233b4f"))
			var field := enemy.body.shield
			var ratio := field.charge / field.capacity
			draw_rect(Rect2(point + Vector2(-24, 49), Vector2(48 * ratio, 2)), Color("#76ccf0") if field.active() else Color("#677d95"))
		_centered(enemy.call_sign, point + Vector2(0, 65), danger)
	if not Rect2(Vector2.ZERO, size).has_point(point):
		_draw_threat(size, enemy)


func _draw_asteroids(size: Vector2) -> void:
	var view := Rect2(Vector2.ZERO, size)
	for rock in voyage.asteroids + voyage.deep_asteroids:
		var point := _world_point(rock.position)
		if not view.grow(rock.radius).has_point(point):
			continue
		draw_set_transform(point, rock.rotation)
		_effect_frame(ASTEROIDS, rock.frame, Vector2.ZERO, rock.radius * 2.2)
		draw_set_transform(Vector2.ZERO)


func _scanner_color(color: Color) -> Color:
	return Color(color, 0.70 + 0.30 * sin(Time.get_ticks_msec() * 0.005))


func _draw_threat(size: Vector2, enemy: Voyage.EnemyShip) -> void:
	if not voyage.computer.enabled("threat"):
		return
	var approach := (enemy.velocity - voyage.velocity).dot(enemy.position.direction_to(voyage.ship_position))
	var color := _scanner_color(Color("#ff8c85")) if approach > 20.0 else Color("#ca9c95")
	_draw_station_bearing(size, _world_point(enemy.position), enemy.call_sign, color)


func _draw_computer(size: Vector2) -> void:
	var view := Rect2(Vector2.ZERO, size)
	if voyage.computer.enabled("objects"):
		var objects: Array[Vector2] = []
		var captions: Array[String] = []
		if voyage.adventure != null:
			for item in voyage.adventure.containers.get(voyage.current_system, []):
				objects.append(item.position)
				captions.append("Контейнер")
		for wreck in voyage.wrecks:
			if wreck.collider != null:
				objects.append(wreck.position)
				captions.append("Остов")
		var nearest := -1
		var distance := INF
		for index in objects.size():
			var point := world_to_screen(objects[index])
			var offset := size * 0.5 - point
			if not view.has_point(point) and offset.length_squared() < distance:
				nearest = index
				distance = offset.length_squared()
		if nearest >= 0:
			_draw_station_bearing(size, world_to_screen(objects[nearest]), captions[nearest], _scanner_color(VELOCITY_COLOR))
	var assist := voyage.assisted_target()
	if assist.is_empty():
		return
	var lead := world_to_screen(assist.point)
	if not view.grow(-10.0).has_point(lead):
		return
	var origin := world_to_screen(voyage.muzzle_position())
	draw_dashed_line(origin, lead, Color(0.47, 0.92, 0.82, 0.38), 1.0, 7.0, true, true)
	draw_arc(lead, 10.0, 0.0, TAU, 24, VELOCITY_COLOR, 1.0, true)
	for axis in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(lead + axis * 6.0, lead + axis * 13.0, VELOCITY_COLOR, 1.0, true)


func _draw_drone(drone: Voyage.Drone, size: Vector2) -> void:
	var point := _world_point(drone.body.position)
	if not Rect2(Vector2.ZERO, size).grow(20.0).has_point(point):
		return
	var tint := Color("#7a9cab") if drone.disabled_time > 0.0 else Color.WHITE
	if drone.shutdown_time >= 0.0:
		tint = tint.lerp(Color("#d68563"), 0.5 + sin(drone.shutdown_time * 17.0) * 0.4)
	_draw_shell(DRONE, point, drone.body.heading, 25.0, tint)
	if drone.hit_time > 0.0:
		_effect_frame(HIT_FRAMES, mini(4, int((1.0 - drone.hit_time / 0.18) * 5.0)), point, 24.0)


func _draw_shield(body: Physics.Body) -> void:
	var field := body.shield
	if field == null:
		return
	var point := _world_point(body.position)
	var diameter := body.shield_radius() * 2.0
	if field.active():
		var strength := field.charge / field.capacity
		_sprite(SHIELD, point, diameter, Color(1.0, 1.0, 1.0, 0.40 + strength * 0.40))
	if field.pulse > 0.0:
		_sprite(SHIELD_HIT, point, diameter, Color(1.0, 1.0, 1.0, field.pulse / 0.28))


func _draw_wrecks(size: Vector2) -> void:
	var visible := Rect2(Vector2.ZERO, size).grow(105.0)
	for wreck in voyage.wrecks:
		var at := _world_point(wreck.position)
		if not visible.has_point(at):
			continue
		draw_set_transform(at, wreck.rotation)
		_sprite(wreck.texture, Vector2.ZERO, wreck.size)
		draw_set_transform(Vector2.ZERO)
		if wreck.broken_hull and wreck.age < 0.84:
			_effect_frame(WRECK_FRAMES, int(wreck.age * 8.0 / 0.84), at, wreck.size * 2.1)
		elif not wreck.broken_hull and wreck.age < 0.62:
			_effect_frame(BLACKOUT_FRAMES, int(wreck.age * 4.0 / 0.62), at, wreck.size)


func _effect_frame(atlas: Texture2D, index: int, point: Vector2, extent: float) -> void:
	var side := Vector2.ONE * extent
	draw_texture_rect_region(atlas, Rect2(point - side * 0.5, side), Rect2(index * 64, 0, 64, 64))


func _draw_station_bearing(size: Vector2, station: Vector2, label: String, color: Color) -> void:
	var center := size * 0.5
	var direction := center.direction_to(station)
	var inset := center - Vector2(83, 48)
	var scale := minf(inset.x / maxf(absf(direction.x), 0.0001), inset.y / maxf(absf(direction.y), 0.0001))
	var tip := center + direction * scale
	_arrow_tip(tip, direction, color, 10.0)
	_centered(label, tip - direction * 34.0 + Vector2(0, -10), color)


func _draw_projectiles(size: Vector2) -> void:
	var visible_area := Rect2(Vector2.ZERO, size).grow(24)
	for projectile in voyage.projectiles:
		var point := _world_point(projectile.position)
		match projectile.profile.kind:
			Profile.Kind.LASER:
				var direction := Vector2.from_angle(projectile.angle)
				var viewport_length := point.distance_to(size * 0.5) + size.length() * 0.5 + 8.0
				var finish := point + direction * viewport_length
				if projectile.beam_blocked:
					var impact := _world_point(projectile.end)
					if point.distance_to(impact) <= viewport_length:
						finish = impact
						_sprite(LASER_BEAM, impact, 8.0)
				draw_line(point, finish, Color("#b266ed"), 3.0, true)
				draw_line(point, finish, Color("#f8dfff"), 1.0, true)
			Profile.Kind.EMP:
				_draw_emp_wave(projectile, point)
			Profile.Kind.RAIL:
				if visible_area.has_point(point):
					_draw_shell(RAIL_BOLT, point, projectile.angle, 35.0)
			Profile.Kind.MISSILE:
				if projectile.blast_time > 0.0:
					var fraction: float = projectile.blast_time / Voyage.Weapons.BLAST_SECONDS
					var diameter := projectile.profile.missile_blast_radius * 2.0
					_sprite(EXPLOSION, point, diameter * lerpf(0.25, 0.92, 1.0 - fraction), Color(1, 1, 1, sqrt(fraction)))
					draw_arc(point, diameter * 0.5 * lerpf(0.35, 1.0, 1.0 - fraction), 0, TAU, 48, Color(1, 0.62, 0.30, fraction * 0.7), 2.0, true)
				elif visible_area.has_point(point):
					_draw_shell(MISSILE, point, projectile.angle, 26.0)
			_:
				if visible_area.has_point(point):
					_draw_shell(projectile.sprite, point, projectile.velocity.angle(), projectile.sprite_size,
						Color("#ff995e") if projectile.hostile else Color.WHITE)
	if voyage.flash_remaining > 0.0:
		var flash_position := _world_point(voyage.muzzle_position())
		draw_set_transform(flash_position, voyage.flash_direction.angle() + PI * 0.5)
		_sprite(MUZZLE_FLASH, Vector2.ZERO, 29.0, Color(1, 1, 1, voyage.flash_remaining / Voyage.FLASH_SECONDS))
	draw_set_transform(Vector2.ZERO)


func _draw_shell(sprite: Texture2D, point: Vector2, angle: float, extent: float, tint := Color.WHITE) -> void:
	draw_set_transform(point, angle + PI * 0.5)
	_sprite(sprite, Vector2.ZERO, extent, tint)
	draw_set_transform(Vector2.ZERO)


func _draw_emp_wave(projectile: Voyage.Projectile, point: Vector2) -> void:
	if projectile.reach <= 0.0:
		return
	var half := deg_to_rad(projectile.profile.emp_angle * 0.5)
	var first := projectile.angle - half
	var last := projectile.angle + half
	var fade := 1.0 - 0.7 * projectile.reach / projectile.profile.emp_range
	var outline := Color(0.42, 0.91, 1.0, fade)
	draw_arc(point, projectile.reach, first, last, 32, outline, 3.0, true)
	draw_arc(point, maxf(0.0, projectile.reach - 6.0), first, last, 32, Color(outline, fade * 0.42), 1.0, true)
	for factor in [-0.82, -0.41, 0.0, 0.41, 0.82]:
		var spark := point + Vector2.from_angle(projectile.angle + half * factor) * projectile.reach
		_sprite(EMP_SPARK, spark, 17.0, Color(1, 1, 1, fade))


func _draw_ship() -> void:
	var body := voyage.body
	if not voyage.battle_result.is_empty():
		_draw_player_defeat(body)
		return
	_draw_thrusters(body)
	var healthy := voyage.deck.engine_health >= 1.0 and voyage.deck.hull.condition(voyage.deck.engine_tile) >= 1.0
	var hull_center := _world_point(body.model.world_point(Vector2.ZERO, body.position, body.heading))
	draw_set_transform(hull_center, body.heading + PI * 0.5)
	_sprite(SHIP, Vector2.ZERO, 60, Color.WHITE if healthy else Color("#f8c599"))
	draw_set_transform(Vector2.ZERO)
	_draw_shield(body)


func _draw_player_defeat(body: Physics.Body) -> void:
	var elapsed := voyage.defeat_elapsed
	var at := _world_point(body.model.world_point(Vector2.ZERO, body.position, body.heading))
	var broken := voyage.defeat_hull
	draw_set_transform(at, body.heading + PI * 0.5)
	if broken:
		_sprite(PLAYER_WRECK, Vector2.ZERO, 60.0)
		_sprite(SHIP, Vector2.ZERO, 60.0, Color(1.0, 1.0, 1.0, 1.0 - smoothstep(0.0, 0.62, elapsed)))
	else:
		var frame_size := Vector2(CREW_LOSS_FRAMES.get_width() / 12.0, CREW_LOSS_FRAMES.get_height())
		var extent := frame_size * 60.0 / frame_size.y
		var index := mini(11, int(elapsed * 5.9))
		draw_texture_rect_region(CREW_LOSS_FRAMES, Rect2(-extent * 0.5, extent), Rect2(Vector2(index * frame_size.x, 0), frame_size))
	draw_set_transform(Vector2.ZERO)
	if broken:
		for index in range(3):
			var time := elapsed - 0.13 - index * 0.20
			if time >= 0.0 and time < 0.84:
				var offset := Vector2(-9.0 + index * 8.0, 15.0 - index * 14.0).rotated(body.heading)
				_effect_frame(WRECK_FRAMES, int(time / 0.84 * 8.0), at + offset, 95.0 + 20.0 * index)
	elif elapsed < 1.72:
		var time := fposmod(elapsed, 0.86)
		_effect_frame(BLACKOUT_FRAMES, mini(3, int(time / 0.86 * 4.0)), at, 72.0 + elapsed * 18.0)


func _draw_thrusters(body: Physics.Body) -> void:
	var model := body.model
	for index in body.active:
		var exhaust := -model.nozzle_forces[index].normalized().rotated(body.heading + PI * 0.5)
		var at := _world_point(model.world_point(model.nozzle_points[index], body.position, body.heading))
		var level := body.active[index]
		var main := model.nozzle_groups[index] == Model.Group.MAIN
		var length := lerpf(3.0, 23.0 if main else 13.0, level)
		draw_set_transform(at + exhaust * length * 0.38, exhaust.angle() - (PI * 0.5 if main else 0.0))
		_sprite(EXHAUST if main else MANEUVER_EXHAUST, Vector2.ZERO, length, Color(1, 1, 1, 0.85 * sqrt(level)))
	draw_set_transform(Vector2.ZERO)


func _draw_scan(size: Vector2) -> void:
	var deck := voyage.enemy.deck
	var panel := Rect2(15.0, size.y - 183.0, 204.0, 145.0)
	var cell_size := minf(10.0, (panel.size.y - 30.0) / deck.plan.size())
	var origin := panel.position + Vector2((panel.size.x - deck.plan[0].length() * cell_size) * 0.5, 25)
	draw_rect(panel, Color("#101e2e"))
	draw_rect(panel, Color("#30465c"), false)
	_text("%s  ·  %d/%d" % [voyage.enemy.call_sign.to_upper(), voyage.scan_index % voyage.enemies.size() + 1, voyage.enemies.size()], panel.position + Vector2(12, 18), 12, Color("#bfd1e4"))
	_text("%d%%" % floori(deck.power.energy), panel.position + Vector2(161, 18), 12, ACCELERATION_COLOR)
	for y in range(deck.plan.size()):
		for x in range(deck.plan[y].length()):
			var tile := Vector2i(x, y)
			var kind := deck.tile_kind(tile)
			if kind == ".":
				continue
			var at := origin + Vector2(tile) * cell_size
			var air := deck.hull.oxygen_at(tile)
			var fill: Color = SCAN_FLOORS[kind].lerp(Color("#307da2"), 1.0 - air)
			var damage := 1.0 - deck.hull.condition(tile)
			fill = fill.lerp(Color("#a25956"), damage * 0.72)
			draw_rect(Rect2(at, Vector2.ONE * (cell_size - 1.0)), fill)
			if deck.hull.breaches.has(tile):
				draw_circle(at + Vector2.ONE * 4.5, 2.4, Color("#ffb297"))
	for edge: Vector4i in deck.doors:
		var a := Vector2(edge.x, edge.y)
		var b := Vector2(edge.z, edge.w)
		var center := origin + ((a + b) * 0.5 + Vector2.ONE * 0.45) * cell_size
		var tangent := (b - a).orthogonal() * 3.5
		var door: Voyage.DeckSimulation.Door = deck.doors[edge]
		draw_line(center - tangent, center + tangent, Color("#547883") if door.openness > 0.95 else Color("#cd9c6b"), 2.0)
	for tile: Vector2i in deck.module_cells:
		var at := origin + (Vector2(tile) + Vector2.ONE * 0.45) * cell_size
		if deck.emp_time(tile) > 0.0 or deck.hacked(tile):
			_sprite(EMP_SPARK, at, 9.0)
		elif deck.hull.condition(tile) < 1.0:
			_sprite(ROOM_DAMAGE, at, 9.0)
		elif tile == deck.reactor_tile:
			_sprite(REACTOR, at, 7.0)
		else:
			draw_rect(Rect2(at - Vector2.ONE * 2.5, Vector2.ONE * 5.0), Color("#7291a6"), false)
	for member in deck.crew:
		if member.health <= 0.0:
			continue
		var color := member.color.lerp(Color("#ff766f"), 1.0 - member.health_ratio())
		draw_circle(origin + (member.position + Vector2.ONE * 0.45) * cell_size, 2.8, color)


func _draw_vector(center: Vector2, vector: Vector2, color: Color, label: String, dashed: bool) -> void:
	if vector.length_squared() < 1.0:
		return
	var direction := vector.normalized()
	var normal := direction.orthogonal()
	var tip := center + vector.limit_length(131.0)
	if dashed:
		draw_dashed_line(center, tip, color, 2.0, 6.0)
	else:
		draw_line(center, tip, color, 2.0, true)
	_arrow_tip(tip, direction, color, 8.0)
	_text(label, tip + normal * (10.0 if dashed else -10.0) + Vector2(-3, 4), 13, color)


func _arrow_tip(tip: Vector2, direction: Vector2, color: Color, length: float) -> void:
	var base := tip - direction * length
	var edge := direction.orthogonal() * length * 0.45
	draw_colored_polygon(PackedVector2Array([tip, base + edge, base - edge]), color)


func _sprite(texture: Texture2D, center: Vector2, longest: float, tint := Color.WHITE) -> void:
	if texture == null:
		return
	var size := texture.get_size()
	var extent := size * (longest / maxf(size.x, size.y))
	draw_texture_rect(texture, Rect2(center - extent * 0.5, extent), false, tint)


func _centered(value: String, at: Vector2, tint: Color) -> void:
	var width := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_text(value, at - Vector2(width * 0.5, 0), 15, tint)


func _text(value: String, at: Vector2, size: int, tint: Color) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, tint)
