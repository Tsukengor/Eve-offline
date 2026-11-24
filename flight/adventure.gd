extends RefCounted

const SAVE_PATH := "user://adventure.cfg"
const VERSION := 1
const SCRAP := 3
const ION := 4
const NEST := 5
const MAP_POINTS := [Vector2(119, 283), Vector2(219, 108), Vector2(392, 230), Vector2(245, 375),
	Vector2(601, 113), Vector2(627, 345)]
const ROUTES := [Vector3i(0, SCRAP, 2), Vector3i(SCRAP, 2, 2), Vector3i(1, ION, 2),
	Vector3i(2, ION, 2), Vector3i(ION, NEST, 3), Vector3i(SCRAP, NEST, 3)]
const PICKUP_DISTANCE := 82.0
const PICKUP_SPEED := 75.0
const MODULE_NAMES := {"thrusters": "Маневровые сопла", "reactor": "Реактор", "shield": "Генератор щита"}
const MODULE_EFFECTS := {"thrusters": "+20% тяги поворота", "reactor": "+20% скорости зарядки",
	"shield": "+25 ед. ёмкости"}
const WEAPON_PRICES := [0, 0, 110, 135, 165]

# Opponent indices follow Voyage.Opponent. Slots are stable across jumps and saves.
const ENCOUNTERS := {
	SCRAP: [0, 1], ION: [2, 1], NEST: [3, 0, 2],
}
const SECTOR_NOTES := {
	SCRAP: "Старые остовы мешают манёврам. Бур и истребитель атакуют с разных направлений.",
	ION: "В ионных облаках реакторы теряют энергию. Ракетчик атакует из-за облаков.",
	NEST: "Роевик и его прикрытие атакуют одновременно. Дроны выходят на орбиту вокруг корабля.",
}
const CONTRACTS := [
	{"title": "Фильтры для «Перевала»", "from": 0, "to": 2, "battle": false, "credits": 72, "parts": 1,
		"brief": "На «Перевале» заканчиваются фильтры. Возьмите пломбированный ящик и сдайте его на причале."},
	{"title": "Архив для «Каскада»", "from": 2, "to": 1, "battle": false, "credits": 85, "parts": 2,
		"brief": "Доставьте журнал ремонтов на «Каскад». Диспетчер примет архив при стыковке."},
	{"title": "Катушки для «Кромки»", "from": 1, "to": ION, "battle": false, "credits": 118, "parts": 2,
		"brief": "Отвезите катушки к «Кромке». Ионные облака на подлёте разряжают реактор."},
	{"title": "Проход через Свалку", "from": 0, "to": SCRAP, "battle": true, "credits": 125, "parts": 3,
		"brief": "Уберите рейдеров из поля старых остовов и пристыкуйтесь к «Сборщику»."},
	{"title": "Ракеты в грозовом фронте", "from": 2, "to": ION, "battle": true, "credits": 150, "parts": 3,
		"brief": "Уничтожьте дозор в Грозе. Вблизи ионных облаков ракеты особенно опасны."},
	{"title": "Разорить Гнездо", "from": 1, "to": NEST, "battle": true, "credits": 220, "parts": 4,
		"brief": "Разбейте роевика и прикрытие, дождитесь отключения дронов и пришвартуйтесь к «Якорю»."},
]

class SalvageCrate:
	var position: Vector2
	var credits: int
	var parts: int

	func _init(at: Vector2, payment: int, components: int) -> void:
		position = at
		credits = payment
		parts = components


var save_path := SAVE_PATH
var credits := 90
var parts := 1
var unlocked: Array[int] = [0, 1]
var slots: Array[int] = [0, 1]
var equipped := 0
var levels := {"thrusters": 0, "reactor": 0, "shield": 0}
var accepted: Array[int] = []
var settled: Array[int] = []
var defeated: Dictionary[int, Array] = {}
var containers: Dictionary[int, Array] = {}
var crew_health: Array[float] = []
var saved_system := 0


func remaining(system: int) -> Array:
	var slots_left: Array[int] = []
	var cleared: Array = defeated.get(system, [])
	for index in ENCOUNTERS.get(system, []).size():
		if index not in cleared:
			slots_left.append(index)
	return slots_left


func record_defeat(system: int, slot: int, at: Vector2, opponent: int) -> void:
	if slot not in remaining(system):
		return
	if not defeated.has(system):
		defeated[system] = []
	defeated[system].append(slot)
	if not containers.has(system):
		containers[system] = []
	containers[system].append(SalvageCrate.new(at, [32, 27, 42, 68][opponent], 2 if opponent == 3 else 1))


func nearest_container(system: int, at: Vector2) -> SalvageCrate:
	var nearest: SalvageCrate
	var distance := PICKUP_DISTANCE ** 2
	for item: SalvageCrate in containers.get(system, []):
		var separation := item.position.distance_squared_to(at)
		if separation <= distance:
			distance = separation
			nearest = item
	return nearest


func collect(system: int, item: SalvageCrate) -> void:
	containers[system].erase(item)
	credits += item.credits
	parts += item.parts


func can_accept(index: int, system: int) -> bool:
	return index >= 0 and index < CONTRACTS.size() and CONTRACTS[index].from == system and index not in accepted


func has_destination(system: int) -> bool:
	for index in accepted:
		if index not in settled and CONTRACTS[index].to == system:
			return true
	return false


func settle(system: int) -> Array[String]:
	var completed: Array[String] = []
	for index in accepted:
		var job: Dictionary = CONTRACTS[index]
		if index in settled or job.to != system or (job.battle and not remaining(system).is_empty()):
			continue
		settled.append(index)
		credits += job.credits
		parts += job.parts
		completed.append(job.title)
	return completed


func module_cost(key: String) -> Vector2i:
	var level: int = levels[key]
	return Vector2i(55 + level * 40, 2 + level)


func buy_module(key: String) -> bool:
	if not levels.has(key) or levels[key] >= 2:
		return false
	var cost := module_cost(key)
	if credits < cost.x or parts < cost.y:
		return false
	credits -= cost.x
	parts -= cost.y
	levels[key] += 1
	return true


func buy_weapon(index: int) -> bool:
	if index < 0 or index >= WEAPON_PRICES.size() or index in unlocked or credits < WEAPON_PRICES[index]:
		return false
	credits -= WEAPON_PRICES[index]
	unlocked.append(index)
	return true


func equip_weapon(slot: int, weapon: int) -> bool:
	if slot not in [0, 1] or weapon not in unlocked or slots[slot] == weapon:
		return false
	if slots[1 - slot] == weapon:
		slots[1 - slot] = slots[slot]
	slots[slot] = weapon
	return true


func save(system: int, health: Array[float]) -> Error:
	var cargo := {}
	for sector in containers:
		var items: Array = []
		for item: SalvageCrate in containers[sector]:
			items.append([item.position, item.credits, item.parts])
		cargo[sector] = items
	var config := ConfigFile.new()
	config.set_value("checkpoint", "version", VERSION)
	config.set_value("checkpoint", "state", {
		"system": system, "credits": credits, "parts": parts, "unlocked": unlocked, "slots": slots,
		"equipped": equipped, "levels": levels, "accepted": accepted, "settled": settled,
		"defeated": defeated, "containers": cargo, "crew_health": health,
	})
	var temporary := save_path + ".tmp"
	var result := config.save(temporary)
	if result == OK:
		result = DirAccess.rename_absolute(temporary, save_path)
	if result == OK:
		saved_system = system
	return result


func load_checkpoint(system_count: int) -> bool:
	var config := ConfigFile.new()
	if config.load(save_path) != OK or config.get_value("checkpoint", "version", 0) != VERSION:
		return false
	var state: Variant = config.get_value("checkpoint", "state", {})
	if not state is Dictionary or typeof(state.get("system")) != TYPE_INT or state.system < 0 or state.system >= system_count:
		return false
	saved_system = state.system
	credits = _number(state.get("credits"), 0)
	parts = _number(state.get("parts"), 0)
	unlocked = _indices(state.get("unlocked"), WEAPON_PRICES.size())
	if 0 not in unlocked:
		unlocked.append(0)
	if 1 not in unlocked:
		unlocked.append(1)
	var saved_slots := _indices(state.get("slots"), WEAPON_PRICES.size())
	if saved_slots.size() == 2 and saved_slots[0] in unlocked and saved_slots[1] in unlocked:
		slots = saved_slots
	equipped = mini(1, _number(state.get("equipped"), 0))
	accepted = _indices(state.get("accepted"), CONTRACTS.size())
	settled = _indices(state.get("settled"), CONTRACTS.size())
	var saved_levels: Variant = state.get("levels")
	if saved_levels is Dictionary:
		for module in levels:
			levels[module] = mini(2, _number(saved_levels.get(module), 0))
	var cleared: Variant = state.get("defeated")
	if cleared is Dictionary:
		for sector in ENCOUNTERS:
			defeated[sector] = _indices(cleared.get(sector), ENCOUNTERS[sector].size())
	var cargo: Variant = state.get("containers")
	if cargo is Dictionary:
		for sector in ENCOUNTERS:
			var items: Variant = cargo.get(sector)
			if not items is Array:
				continue
			containers[sector] = []
			for item in items:
				if item is Array and item.size() == 3 and item[0] is Vector2 and item[0].is_finite():
					containers[sector].append(SalvageCrate.new(item[0], _number(item[1], 0), _number(item[2], 0)))
	var health: Variant = state.get("crew_health")
	if health is Array:
		for value in health.slice(0, 4):
			if value is float or value is int:
				crew_health.append(clampf(value, 0.0, 100.0))
	return true


static func _number(value: Variant, fallback: int) -> int:
	return clampi(value, 0, 10000000) if value is int else fallback


static func _indices(values: Variant, upper_bound: int) -> Array[int]:
	var result: Array[int] = []
	if values is Array:
		for value in values:
			if value is int and value >= 0 and value < upper_bound and value not in result:
				result.append(value)
	return result
