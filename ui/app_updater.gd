extends Node

const REPOSITORY := "Tsukengor/Eve-offline"
const RELEASES := "https://github.com/" + REPOSITORY + "/releases/download/"
const LATEST := "https://api.github.com/repos/" + REPOSITORY + "/releases/latest"
const DIRECTORY := "user://updates"
const POINTER := DIRECTORY + "/current.cfg"
const PACK := "Eve-Offline.pck"
const MAX_ARCHIVE := 120 * 1024 * 1024
const HEADERS := ["User-Agent: Eve-Offline-Updater", "Accept: application/vnd.github+json"]

var _current: String
var _binary: String
var _asset: String
var _request: HTTPRequest


func _ready() -> void:
	if OS.has_feature("editor") or DisplayServer.get_name() == "headless":
		return
	match OS.get_name():
		"Linux":
			_binary = "Eve-Offline.x86_64"
			_asset = "Eve-Offline-linux-x86_64.zip"
		"Windows":
			_binary = "Eve-Offline.exe"
			_asset = "Eve-Offline-windows-x86_64.zip"
		_: return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_current = "v" + str(ProjectSettings.get_setting("application/config/version"))
	_check.call_deferred()


func _check() -> void:
	var pointer := ConfigFile.new()
	if pointer.load(POINTER) == OK:
		var installed := str(pointer.get_value("application", "tag", ""))
		if newer(installed, _current) and _start_build(installed):
			return
	_request = HTTPRequest.new()
	_request.timeout = 60.0
	add_child(_request)
	var response := await _request_bytes(LATEST, 512 * 1024)
	var release: Variant = JSON.parse_string(response.get_string_from_utf8())
	if not release is Dictionary or release.get("draft", true) or release.get("prerelease", true):
		return
	var tag := str(release.get("tag_name", ""))
	if not newer(tag, _current):
		return
	var assets: Array = release.get("assets", [])
	var names := []
	for asset in assets:
		if asset is Dictionary:
			names.append(asset.get("name", ""))
	if _asset not in names or "SHA256SUMS.txt" not in names:
		return
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://ui/main_menu.tscn":
		await get_tree().scene_changed
	_offer(tag)


func _offer(tag: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Обновление игры"
	dialog.dialog_text = "Обнаружено обновление %s. Установить?\nПосле установки игра перезапустится." % tag
	dialog.ok_button_text = "Да"
	dialog.cancel_button_text = "Нет"
	add_child(dialog)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(_install.bind(tag, dialog), CONNECT_ONE_SHOT)
	dialog.popup_centered()


func _install(tag: String, dialog: ConfirmationDialog) -> void:
	dialog.hide()
	dialog.queue_free()
	var status := AcceptDialog.new()
	status.title = "Обновление игры"
	status.dialog_text = "Скачивание и проверка обновления %s…" % tag
	status.get_ok_button().disabled = true
	status.unresizable = true
	add_child(status)
	status.popup_centered()
	var error := await _download_build(tag)
	if error.is_empty():
		var pointer := ConfigFile.new()
		pointer.set_value("application", "tag", tag)
		if _start_build(tag):
			pointer.save(POINTER)
			return
		error = "Не удалось запустить новую версию."
	status.dialog_text = error
	status.get_ok_button().disabled = false
	status.confirmed.connect(status.queue_free)


func _download_build(tag: String) -> String:
	var base := RELEASES + tag + "/"
	var hashes := await _request_bytes(base + "SHA256SUMS.txt", 8192)
	var expected := checksum(hashes.get_string_from_utf8(), _asset)
	if expected.is_empty():
		return "Не удалось получить контрольную сумму обновления."
	var target := ProjectSettings.globalize_path(DIRECTORY.path_join(tag))
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		return "Не удалось создать папку для обновления."
	var archive := target.path_join("download.zip")
	_request.download_file = archive
	await _request_bytes(base + _asset, MAX_ARCHIVE)
	_request.download_file = ""
	if FileAccess.get_sha256(archive) != expected:
		DirAccess.remove_absolute(archive)
		return "Скачивание прервалось или контрольная сумма не совпала."
	var extracted := unpack(archive, target, _binary)
	DirAccess.remove_absolute(archive)
	if not extracted:
		return "Не удалось распаковать обновление."
	return ""


func _request_bytes(url: String, limit: int) -> PackedByteArray:
	_request.body_size_limit = limit
	if _request.request(url, HEADERS) != OK:
		return PackedByteArray()
	var reply: Array = await _request.request_completed
	if reply[0] != HTTPRequest.RESULT_SUCCESS or reply[1] != 200:
		return PackedByteArray()
	return reply[3]


func _start_build(tag: String) -> bool:
	var folder := ProjectSettings.globalize_path(DIRECTORY.path_join(tag))
	var binary := folder.path_join(_binary)
	if not FileAccess.file_exists(binary) or not FileAccess.file_exists(folder.path_join(PACK)):
		return false
	if OS.get_name() == "Linux" and FileAccess.set_unix_permissions(binary, 493) != OK:
		return false
	if OS.create_process(binary, PackedStringArray()) < 0:
		return false
	get_tree().quit.call_deferred()
	return true


static func unpack(archive: String, target: String, binary: String) -> bool:
	var zip := ZIPReader.new()
	if zip.open(archive) != OK:
		return false
	for name in [PACK, binary]:
		var contents := zip.read_file(name)
		if contents.is_empty():
			return false
		var file := FileAccess.open(target.path_join(name), FileAccess.WRITE)
		if file == null or not file.store_buffer(contents):
			return false
	zip.close()
	return true


static func checksum(manifest: String, asset: String) -> String:
	for line in manifest.split("\n", false):
		var columns := line.strip_edges().split(" ", false, 1)
		if columns.size() != 2 or columns[1].strip_edges() != asset:
			continue
		var hash := columns[0].to_lower()
		if hash.length() != 64:
			return ""
		for character in hash:
			if character not in "0123456789abcdef":
				return ""
		return hash
	return ""


static func newer(candidate: String, baseline: String) -> bool:
	var left := _version(candidate)
	var right := _version(baseline)
	if left.size() != 3 or right.size() != 3:
		return false
	for index in range(3):
		if left[index] != right[index]:
			return left[index] > right[index]
	return false


static func _version(tag: String) -> PackedInt32Array:
	var version := PackedInt32Array()
	if not tag.begins_with("v"):
		return version
	for part in tag.substr(1).split("."):
		if part.is_empty() or part.length() > 8 or not part.is_valid_int() or str(part.to_int()) != part or part.to_int() < 0:
			return PackedInt32Array()
		version.append(part.to_int())
	return version
