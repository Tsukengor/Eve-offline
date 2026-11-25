extends RefCounted

const RADIUS := 4600.0
const INNER_LIMIT := 4110.0
const COUNT := 216

class Rock:
	var position: Vector2
	var radius: float
	var rotation: float
	var frame: int


static func generate(center: Vector2, sector: int) -> Array[Rock]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 987137 + sector * 19231
	var rocks: Array[Rock] = []
	for index in COUNT:
		var rock := Rock.new()
		var angle := TAU * index / COUNT + rng.randf_range(-0.011, 0.011)
		rock.position = center + Vector2.from_angle(angle) * (RADIUS + rng.randf_range(-310.0, 375.0))
		rock.radius = rng.randf_range(23.0, 62.0)
		rock.frame = rng.randi_range(0, 3)
		rock.rotation = rng.randf_range(-PI, PI)
		rocks.append(rock)
	return rocks


static func constrain(ship, center: Vector2) -> void:
	var offset: Vector2 = ship.position - center
	if offset.length_squared() < INNER_LIMIT * INNER_LIMIT:
		return
	var outward := offset.normalized()
	ship.position = center + outward * INNER_LIMIT
	ship.velocity -= outward * maxf(0.0, ship.velocity.dot(outward))
