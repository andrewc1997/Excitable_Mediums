extends Node

# ============================================================
# EXCITABLE MEDIUMS - CAMPAIGN MANAGER (Godot 4.3)
#
# Central source for the campaign sequence, unlocks and progress.
# PlayerMode creates this under /root/CampaignManager automatically.
# No Autoload registration or replacement scene is necessary.
#
# To add another campaign level, edit only campaign_manifest.json.
# This script never modifies Builder files or custom level JSON.
# ============================================================

signal progress_changed

const MANIFEST_PATH: String = "res://levels/campaign_manifest.json"
const PROGRESS_PATH: String = "user://excitable_mediums_campaign_progress.json"

var levels: Array[Dictionary] = []
var completed_ids: Dictionary = {}
var best_ticks: Dictionary = {}
var _initialised: bool = false
var _loading: bool = false


func _ready() -> void:
	ensure_ready()


func ensure_ready() -> void:
	# Safe to call when PlayerMode opens the menu or requests its next level.
	# This also supports a manager that was instanced before it received _ready().
	if _initialised or _loading:
		return
	_loading = true
	_load_manifest()
	if levels.is_empty():
		_load_fallback_campaign()
	_load_progress()
	_initialised = true
	_loading = false
	print("CampaignManager: %d campaign levels available." % levels.size())


func _load_fallback_campaign() -> void:
	# Recovery ONLY when the manifest cannot be loaded. Normally the
	# campaign order is controlled entirely by campaign_manifest.json.
	push_warning("CampaignManager: Could not read campaign levels from res://levels/campaign_manifest.json; using the installed first three levels as a recovery list.")
	var defaults: Array[Dictionary] = [
		{"id": "level_001", "title": "First Connection", "description": "Introduce Begin nodes and targets.", "path": "res://levels/level_001.json"},
		{"id": "level_002", "title": "The Second Lap", "description": "Learn splitters and loops.", "path": "res://levels/level_002_loop.json"},
		{"id": "level_003", "title": "Point of No Return", "description": "Time a bridge blocker.", "path": "res://levels/level_003_point_of_no_return.json"}
	]
	for entry in defaults:
		if FileAccess.file_exists(str(entry["path"])):
			levels.append(entry.duplicate(true))
	if levels.is_empty():
		push_error("CampaignManager: No playable campaign JSON files were found under res://levels/.")


func _load_manifest() -> void:
	levels.clear()
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("CampaignManager: Missing manifest: " + MANIFEST_PATH)
		return

	var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("CampaignManager: Cannot open campaign manifest.")
		return
	var source_text: String = file.get_as_text().strip_edges()
	file.close()
	# Allow UTF-8 BOM accidentally inserted by Windows text editors.
	source_text = source_text.trim_prefix("\uFEFF")
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(source_text)
	if error != OK:
		push_error("CampaignManager: Invalid campaign_manifest.json at line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
		return
	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		push_error("CampaignManager: Campaign manifest must be a JSON object with a 'levels' array.")
		return

	var raw: Variant = parsed.get("levels", [])
	if not (raw is Array):
		push_error("CampaignManager: Manifest 'levels' must be an array.")
		return

	var used_ids: Dictionary = {}
	var used_paths: Dictionary = {}
	for item in raw:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var id: String = str(entry.get("id", "")).strip_edges()
		var path: String = str(entry.get("path", "")).strip_edges()
		if id.is_empty() or path.is_empty():
			push_warning("CampaignManager: Skipped a level with a missing ID or path.")
			continue
		if used_ids.has(id) or used_paths.has(path):
			push_warning("CampaignManager: Duplicate campaign level: " + id)
			continue
		if not path.begins_with("res://"):
			push_warning("CampaignManager: Campaign path must be res://: " + path)
			continue
		used_ids[id] = true
		used_paths[path] = true
		levels.append({
			"id": id,
			"path": path,
			"title": str(entry.get("title", id)),
			"description": str(entry.get("description", ""))
		})
	print("CampaignManager: Manifest parsed: %d levels." % levels.size())


func _load_progress() -> void:
	completed_ids.clear()
	best_ticks.clear()
	if not FileAccess.file_exists(PROGRESS_PATH):
		return
	var file: FileAccess = FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if file == null:
		push_warning("CampaignManager: Could not read saved progress.")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_warning("CampaignManager: Ignored invalid progress data.")
		return

	var ids: Variant = parsed.get("completed_ids", [])
	if ids is Array:
		for id_value in ids:
			var id: String = str(id_value)
			if _index_for_id(id) >= 0:
				completed_ids[id] = true

	var ticks: Variant = parsed.get("best_ticks", {})
	if ticks is Dictionary:
		for id_value in ticks.keys():
			var id: String = str(id_value)
			if _index_for_id(id) >= 0:
				var tick: int = int(ticks[id_value])
				if tick >= 0:
					best_ticks[id] = tick


func _save_progress() -> void:
	var ids: Array[String] = []
	for entry in levels:
		var id: String = str(entry["id"])
		if completed_ids.has(id):
			ids.append(id)
	var file: FileAccess = FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("CampaignManager: Could not save progress: " + PROGRESS_PATH)
		return
	var payload: Dictionary = {
		"version": 1,
		"completed_ids": ids,
		"best_ticks": best_ticks.duplicate(true)
	}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	progress_changed.emit()


func _index_for_id(id: String) -> int:
	for i in range(levels.size()):
		if str(levels[i]["id"]) == id:
			return i
	return -1


func _index_for_path(path: String) -> int:
	for i in range(levels.size()):
		if str(levels[i]["path"]) == path:
			return i
	return -1


func get_all_levels() -> Array[Dictionary]:
	ensure_ready()
	return levels.duplicate(true)


func get_entry_by_path(path: String) -> Dictionary:
	ensure_ready()
	var index: int = _index_for_path(path)
	if index < 0:
		return {}
	return levels[index].duplicate(true)


func is_campaign_path(path: String) -> bool:
	ensure_ready()
	return _index_for_path(path) >= 0


func is_level_unlocked(path: String) -> bool:
	ensure_ready()
	var index: int = _index_for_path(path)
	if index < 0:
		return false
	if index == 0:
		return true
	var previous_id: String = str(levels[index - 1]["id"])
	return completed_ids.has(previous_id)


func is_level_completed(path: String) -> bool:
	ensure_ready()
	var index: int = _index_for_path(path)
	if index < 0:
		return false
	return completed_ids.has(str(levels[index]["id"]))


func get_best_ticks(path: String) -> int:
	ensure_ready()
	var index: int = _index_for_path(path)
	if index < 0:
		return -1
	return int(best_ticks.get(str(levels[index]["id"]), -1))


func mark_level_completed(path: String, tick: int) -> void:
	ensure_ready()
	var index: int = _index_for_path(path)
	if index < 0:
		# Sandbox/Builder levels are intentionally excluded.
		return
	var id: String = str(levels[index]["id"])
	completed_ids[id] = true
	if tick >= 0:
		var existing: int = int(best_ticks.get(id, -1))
		if existing < 0 or tick < existing:
			best_ticks[id] = tick
	_save_progress()


func get_next_level_path(path: String) -> String:
	ensure_ready()
	var index: int = _index_for_path(path)
	if index < 0 or index + 1 >= levels.size():
		return ""
	var next_path: String = str(levels[index + 1]["path"])
	return next_path if is_level_unlocked(next_path) else ""


func get_resume_path() -> String:
	ensure_ready()
	if levels.is_empty():
		return ""
	# Resume at the first unlocked level not yet completed.
	for entry in levels:
		var path: String = str(entry["path"])
		if is_level_unlocked(path) and not is_level_completed(path):
			return path
	# All finished: resume at the last campaign puzzle.
	return str(levels[levels.size() - 1]["path"])


func get_completed_count() -> int:
	ensure_ready()
	var count: int = 0
	for entry in levels:
		if completed_ids.has(str(entry["id"])):
			count += 1
	return count
