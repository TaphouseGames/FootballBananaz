# startup_cleanup.gd
# Cleans up abandoned temp files on plugin load (once per 24 hours)
@tool
class_name StartupCleanup

# Local change: the timestamp lives in user:// rather than in project.godot,
# so the plugin does not rewrite a version-controlled file once a day.
const CLEANUP_STAMP_FILE: String = "user://tripo_bridge_last_cleanup.txt"
const CLEANUP_INTERVAL_HOURS: float = 24.0
const TEMP_DIR: String = "user://tripo_temp"

static func run() -> void:
	var last_str: String = ""
	if FileAccess.file_exists(CLEANUP_STAMP_FILE):
		last_str = FileAccess.get_file_as_string(CLEANUP_STAMP_FILE).strip_edges()

	if not last_str.is_empty():
		var last := Time.get_unix_time_from_datetime_string(last_str)
		var now := Time.get_unix_time_from_system()
		if (now - last) / 3600.0 < CLEANUP_INTERVAL_HOURS:
			return  # Not yet 24 hours

	_cleanup_temp()

	var now_str := Time.get_datetime_string_from_system(false)
	var f := FileAccess.open(CLEANUP_STAMP_FILE, FileAccess.WRITE)
	if f:
		f.store_string(now_str)

static func _cleanup_temp() -> void:
	var abs_temp := ProjectSettings.globalize_path(TEMP_DIR)
	if not DirAccess.dir_exists_absolute(abs_temp):
		return
	LogHelper.log("StartupCleanup: cleaning old temp files...")
	_delete_dir_recursive(abs_temp)
	LogHelper.log("StartupCleanup: done")

static func _delete_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_delete_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
