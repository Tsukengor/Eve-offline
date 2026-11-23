extends RefCounted

const CAPACITY := 100.0
const RECHARGE := 10.0
const OPERATOR_BONUS := 1.5
const LOW_ENERGY := 12.0

var energy := CAPACITY


func recharge(delta: float, rate: float) -> bool:
	var next := minf(CAPACITY, energy + delta * rate)
	if next == energy:
		return false
	energy = next
	return true


func can_spend(cost: float) -> bool:
	return energy >= cost


func spend(cost: float) -> bool:
	if not can_spend(cost):
		return false
	energy -= cost
	return true


func supply_thrusters(request: float) -> float:
	if request <= 0.0:
		return 1.0
	var fraction := minf(1.0, minf(energy / LOW_ENERGY, energy / request))
	energy = maxf(0.0, energy - request * fraction)
	return fraction
