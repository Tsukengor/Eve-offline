extends RefCounted

const MEMORY := 10
const MODULES := {
	"assist": {"title": "Помощь пилоту", "cost": [0, 2], "hint": "Торможение по вектору скорости с гашением вращения"},
	"pilot": {"title": "Автопилот", "cost": [0, 2, 3, 4], "hint": "Выполняет команды полёта при пустом кресле"},
	"shield": {"title": "Автоматика щита", "cost": [0, 2, 3, 4], "hint": "Поддерживает поле и заряжает его медленнее оператора"},
	"weapons": {"title": "Автоматика орудий", "cost": [0, 2, 3, 4], "hint": "Ведёт огонь по команде с меньшей точностью и темпом"},
	"scanner": {"title": "Сканер противников", "cost": [0, 2], "hint": "Открывает палубы противников в полёте"},
	"zoom": {"title": "Дальность обзора", "cost": [0, 1, 3], "hint": "Средний и дальний масштаб используют память"},
}
const PERFORMANCE := [0.0, 0.40, 0.65, 0.85]
const SCALES := [1.0, 0.8, 0.62]

var levels := {"assist": 1, "pilot": 0, "shield": 0, "weapons": 0, "scanner": 1, "zoom": 0}


func configure(module: String, level: int) -> bool:
	if not MODULES.has(module) or level < 0 or level >= MODULES[module].cost.size() or levels[module] == level:
		return false
	levels[module] = level
	return true


func restore(saved: Dictionary) -> void:
	for module in MODULES:
		var level: Variant = saved.get(module)
		if level is int:
			configure(module, level)


func memory_used() -> int:
	var total := 0
	for module in MODULES:
		total += MODULES[module].cost[levels[module]]
	return total


func overload_draw() -> float:
	var over := maxi(0, memory_used() - MEMORY)
	return over * (2.0 + over * 0.75)


func efficiency(module: String) -> float:
	return PERFORMANCE[levels[module]]


func zoom() -> float:
	return SCALES[levels.zoom]
