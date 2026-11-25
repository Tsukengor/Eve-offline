extends RefCounted

const MEMORY := 10
const MODULES := {
	"assist": {"title": "Помощь пилоту", "cost": [0, 2], "hint": "Торможение по вектору скорости с гашением вращения"},
	"pilot": {"title": "Автопилот", "cost": [0, 2, 3, 4], "hint": "Выполняет команды полёта при пустом кресле"},
	"shield": {"title": "Автоматика щита", "cost": [0, 2, 3, 4], "hint": "Поддерживает поле и заряжает его медленнее оператора"},
	"weapons": {"title": "Автоматика орудий", "cost": [0, 2, 3, 4], "hint": "Ведёт огонь по команде с меньшей точностью и темпом"},
	"scanner": {"title": "Сканер противников", "cost": [0, 2], "hint": "Открывает палубы противников в полёте"},
	"objects": {"title": "Поиск объектов", "cost": [0, 2], "hint": "Метки станций, контейнеров и остовов"},
	"threat": {"title": "Указатель угроз", "cost": [0, 2], "hint": "Направление на противников и подсветка сближения"},
	"aim": {"title": "Помощь в прицеливании", "cost": [0, 2], "hint": "Упреждение и доводка выстрела до 4°"},
	"zoom": {"title": "Дальность обзора", "cost": [0, 1, 3], "hint": "Средний и дальний масштаб используют память"},
}
const PERFORMANCE := [0.0, 0.40, 0.65, 0.85]
const SCALES := [1.0, 0.8, 0.62]

var outage: Callable
var levels := {"assist": 1, "pilot": 0, "shield": 0, "weapons": 0, "scanner": 1, "zoom": 0, "objects": 0, "threat": 1, "aim": 0}


func configure(module: String, level: int) -> bool:
	if not MODULES.has(module) or level < 0 or level >= MODULES[module].cost.size() or levels[module] == level:
		return false
	levels[module] = level
	return true


func restore(saved: Dictionary) -> void:
	if not saved.is_empty() and not saved.has("threat"):
		levels.threat = 0
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
	if offline():
		return 0.0
	var over := maxi(0, memory_used() - MEMORY)
	return over * (2.0 + over * 0.75)


func efficiency(module: String) -> float:
	return 0.0 if offline() else PERFORMANCE[levels[module]]


func zoom() -> float:
	return 1.0 if offline() else SCALES[levels.zoom]


func offline() -> bool:
	return outage.is_valid() and outage.call()


func enabled(module: String) -> bool:
	return not offline() and levels[module] > 0
