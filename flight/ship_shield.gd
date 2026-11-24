extends RefCounted

const CAPACITY := 100.0
const RECHARGE_DELAY := 4.0
const RECHARGE_RATE := 20.0
const EMP_DURATION := 3.0

var charge := CAPACITY
var delay := 0.0
var emp_time := 0.0
var collapsed := false
var pulse := 0.0
var online := true


func active() -> bool:
	return online and not collapsed and emp_time <= 0.0


func reset() -> void:
	charge = CAPACITY
	delay = 0.0
	emp_time = 0.0
	collapsed = false
	pulse = 0.0


func advance(delta: float, staffed := true) -> bool:
	var elapsed := maxf(delay, emp_time)
	var updated := online != staffed or elapsed > 0.0 or pulse > 0.0 or (staffed and charge < CAPACITY)
	online = staffed
	delay = move_toward(delay, 0.0, delta)
	emp_time = move_toward(emp_time, 0.0, delta)
	pulse = move_toward(pulse, 0.0, delta)
	if online:
		charge = minf(CAPACITY, charge + maxf(0.0, delta - elapsed) * RECHARGE_RATE)
	if charge == CAPACITY:
		collapsed = false
	return updated


func absorb(amount: float) -> void:
	charge = maxf(0.0, charge - amount)
	delay = RECHARGE_DELAY
	pulse = 0.28
	collapsed = charge == 0.0


func suppress() -> void:
	absorb(CAPACITY)
	emp_time = EMP_DURATION
