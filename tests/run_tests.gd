extends SceneTree
## Headless test runner. Discovers tests/test_*.gd, instantiates each (RefCounted),
## and awaits every method whose name starts with "test_", passing a TestContext.
##
## Run:  $GODOT --headless --path . --fixed-fps 60 --script tests/run_tests.gd
## Exit code is 1 when any check fails.

const TEST_DIR := "res://tests/"
## Hard cap on a whole run; a hung await must never hang CI.
const WATCHDOG_SECONDS := 120.0

var _total_passes: int = 0
var _total_failures: int = 0

var _elapsed_seconds: float = 0.0


func _initialize() -> void:
	_run_all()


## Frame-counted watchdog (a SceneTreeTimer would leak at exit when the run finishes first).
func _process(delta: float) -> bool:
	_elapsed_seconds += delta
	if _elapsed_seconds > WATCHDOG_SECONDS:
		push_error("Test run exceeded %.0f s; aborting" % WATCHDOG_SECONDS)
		print("\n==== WATCHDOG TIMEOUT ====")
		quit(1)
		return true
	return false


func _run_all() -> void:
	var files := _find_test_files()
	# Optional substring filter on the suite file name, e.g. TEST_FILTER=test_bot.
	var filter_text := OS.get_environment("TEST_FILTER")
	if filter_text != "":
		files = files.filter(
			func(path: String) -> bool: return path.get_file().contains(filter_text)
		)
	if files.is_empty():
		push_error("No tests/test_*.gd files found")
		quit(1)
		return
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("\n%s\n  FAIL  script failed to load (parse error above)" % path.get_file())
			_total_failures += 1
			continue
		var suite: RefCounted = script.new()
		for method in suite.get_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var ctx := TestContext.new(self, "%s::%s" % [path.get_file(), method_name])
			print("\n%s" % ctx.test_name)
			await suite.call(method_name, ctx)
			await ctx.teardown()
			if ctx.passes + ctx.failures == 0:
				# A test that records no check almost always died on a runtime error
				# (the coroutine aborts silently); count it as a failure.
				print("  FAIL  test recorded no checks (runtime error above?)")
				ctx.failures += 1
			_total_passes += ctx.passes
			_total_failures += ctx.failures
	print("\n==== %d passed, %d failed ====" % [_total_passes, _total_failures])
	quit(1 if _total_failures > 0 else 0)


func _find_test_files() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("test_") and entry.ends_with(".gd"):
			found.append(TEST_DIR + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
