extends RefCounted

const RADIUS := 4600.0
const INNER_LIMIT := 4110.0
const COUNT := 384
const CHUNK := 320.0
const DEEP_START := 4790.0

class Rock:
	var position: Vector2
	var origin: Vector2
	var radius: float
	var rotation: float
	var frame: int
	var phase: float
	var drift: Vector2
	var id: Vector3i

	func advance(time: float) -> void:
		position = origin + drift * sin(time * 0.13 + phase)
		rotation = phase + time * 0.09


static func generate(center: Vector2, sector: int) -> Array[Rock]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 987137 + sector * 19231
	var rocks: Array[Rock] = []
	for index in COUNT:
		var angle := TAU * index / COUNT + rng.randf_range(-0.011, 0.011)
		var point := center + Vector2.from_angle(angle) * (RADIUS + rng.randf_range(-310.0, 375.0))
		rocks.append(_rock(point, Vector3i(0, 0, index), rng))
	return rocks


static func deep_field(center: Vector2, sector: int, chunk: Vector2i, destroyed: Dictionary) -> Array[Rock]:
	var rocks: Array[Rock] = []
	var rng := RandomNumberGenerator.new()
	for y in range(chunk.y - 3, chunk.y + 4):
		for x in range(chunk.x - 3, chunk.x + 4):
			rng.seed = hash(Vector3i(x, y, sector + 675))
			for index in range(12):
				var point := Vector2(x + rng.randf(), y + rng.randf()) * CHUNK
				var id := Vector3i(x, y, COUNT + index)
				var rock := _rock(center + point, id, rng)
				if point.length_squared() >= DEEP_START * DEEP_START and not destroyed.has(id):
					rocks.append(rock)
	return rocks


static func _rock(at: Vector2, id: Vector3i, rng: RandomNumberGenerator) -> Rock:
	var rock := Rock.new()
	rock.id = id
	rock.origin = at
	rock.radius = rng.randf_range(23.0, 62.0)
	rock.frame = rng.randi_range(0, 3)
	rock.phase = rng.randf_range(-PI, PI)
	rock.drift = Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(30.0, 78.0)
	rock.advance(0.0)
	return rock


static func constrain(ship, center: Vector2) -> void:
	var offset: Vector2 = ship.position - center
	if offset.length_squared() < INNER_LIMIT * INNER_LIMIT:
		return
	var outward := offset.normalized()
	ship.position = center + outward * INNER_LIMIT
	ship.velocity -= outward * maxf(0.0, ship.velocity.dot(outward))
