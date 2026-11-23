extends Resource

@export var projectile: PackedScene
@export_range(0.01, 10.0, 0.01) var cooldown := 0.32
@export var muzzle_offset := 35.0
@export_range(0.0, 100.0, 0.1) var energy_cost := 12.0
@export var mounts: PackedVector2Array

@export var damage := 27.0
@export_range(0.0, 1.0, 0.01) var breach_chance := 0.25
@export var crew_damage := 9.0
@export_range(0.0, 45.0, 0.5) var damaged_spread_degrees := 18.0
