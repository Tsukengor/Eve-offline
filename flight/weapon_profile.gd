extends Resource

@export var projectile: PackedScene
@export_range(0.01, 10.0, 0.01) var cooldown := 0.32
@export var muzzle_offset := 35.0
@export_range(0.0, 100.0, 0.1) var energy_cost := 12.0
@export var mounts: PackedVector2Array

@export var damage := 27.0
@export_range(0.0, 1.0, 0.01) var breach_chance := 0.25
@export var crew_damage := 14.0
@export_range(0.0, 45.0, 0.5) var damaged_spread_degrees := 18.0

enum Kind { KINETIC, LASER, MISSILE, EMP, RAIL }

@export var kind := Kind.KINETIC
@export var title := "Кинетика"

@export_group("Laser")
@export_range(1, 100, 0.1) var laser_energy_per_second := 42.0
@export_range(10, 15, 1) var laser_ticks_per_second := 12

@export_group("Missile")
@export_range(1, 2500, 1) var missile_speed := 145.0
@export_range(0.05, 20, 0.05) var missile_fuse := 4.2
@export_range(1, 1440, 1) var missile_turn_rate := 135.0
@export_range(1, 360, 1) var missile_lock_angle := 112.0
@export_range(1, 500, 1) var missile_blast_radius := 122.0

@export_group("EMP")
@export_range(1, 2000, 1) var emp_range := 385.0
@export_range(1, 360, 1) var emp_angle := 76.0
@export_range(1, 5000, 1) var emp_speed := 780.0
@export_range(0, 100, 0.1) var emp_energy_drain := 54.0
@export_range(0, 30, 0.1) var emp_disable_duration := 3.2
@export_range(0, 6, 1) var emp_systems := 3
@export_range(0.0, 1.0) var emp_recovery_suppression := 0.65
@export_range(0.0, 1.0) var emp_edge_strength := 0.35

@export_group("Railgun")
@export_range(1, 6000, 1) var rail_speed := 1550.0
@export_range(1, 16, 1) var rail_penetration := 5
@export_range(0.0, 1.0, 0.01) var rail_retention := 0.74
