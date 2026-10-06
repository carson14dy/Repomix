class_name TestContext
extends RefCounted
## Per-test helper (class_name TestContext) handed to every test_* method by tests/run_tests.gd.
##
## Tests drive players only through InputMap actions and observe public state
## (velocity, global_position, is_on_floor(), node tree). Nodes added through
## add()/make_floor()/spawn_player() are freed in teardown().

const PLAYER_SCENE_PATH := "res://prefabs/Player.tscn"

var tree: SceneTree
var test_name: String
var passes: int = 0
var failures: int = 0

var _nodes: Array[Node] = []
var _pressed: Array[String] = []


func _init(scene_tree: SceneTree, name: String) -> void:
	tree = scene_tree
	test_name = name


## Record a boolean assertion.
func check(condition: bool, label: String) -> void:
	if condition:
		passes += 1
		print("  PASS  %s" % label)
	else:
		failures += 1
		print("  FAIL  %s" % label)


## Record a numeric assertion with an absolute tolerance.
func check_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	var ok := absf(actual - expected) <= tolerance
	check(ok, "%s (actual %.2f, expected %.2f ± %.2f)" % [label, actual, expected, tolerance])


## Add a node to the scene root and track it for cleanup.
func add(node: Node) -> Node:
	tree.root.add_child(node)
	_nodes.append(node)
	return node


## A static floor on physics layer 1 ("world"), centered at `center`.
func make_floor(center: Vector2, size: Vector2 = Vector2(1200, 40)) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	body.position = center
	add(body)
	return body


## Instantiate prefabs/Player.tscn for the given player index at `pos`.
func spawn_player(player_index: int, pos: Vector2) -> CharacterBody2D:
	var scene: PackedScene = load(PLAYER_SCENE_PATH)
	var player := scene.instantiate() as CharacterBody2D
	player.set("player_index", player_index)
	player.position = pos
	add(player)
	return player


## Simulate an InputMap action being held down.
func press(action: String) -> void:
	Input.action_press(action)
	if not _pressed.has(action):
		_pressed.append(action)


## Simulate an InputMap action being released.
func release(action: String) -> void:
	Input.action_release(action)
	_pressed.erase(action)


## Advance the simulation by `frames` physics frames.
func step(frames: int = 1) -> void:
	for _i in range(frames):
		await tree.physics_frame


## Release all held actions and free every tracked node.
func teardown() -> void:
	for action in _pressed.duplicate():
		Input.action_release(action)
	_pressed.clear()
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await tree.physics_frame
	await tree.physics_frame
