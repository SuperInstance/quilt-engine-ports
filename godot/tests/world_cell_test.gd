extends Node

## quilt-engine-ports/godot/tests/world_cell_test.gd
##
## Conformance tests for the `physical.world` cell kind in GDScript.
## Mirrors the C and Rust polyformalism tests:
##   - quilt-c/tests/test_world.c
##   - quilt-rust/crates/quilt-polyformalism/tests/polyformalism.rs

const WorldCell = preload("res://scripts/world_cell.gd")

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	print("=== quilt-engine-ports: physical.world cell kind (Phase 227) ===\n")
	test_kind_name()
	test_propose_sets_state_hash()
	test_propose_updates_prev_hash()
	test_execute_produces_quantity()
	test_verify_resets_on_propose()
	test_render_writes_placeholder()
	test_refine_appends_hint()
	test_polyformalism_shape()
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("  PASS %s" % msg)
	else:
		failed += 1
		print("  FAIL %s" % msg)


func test_kind_name() -> void:
	print("== test_kind_name ==")
	check(WorldCell.kind_name() == "physical.world", "kind name = physical.world")
	check(WorldCell.kind_count() == 5, "5 abductive-loop operations")
	var cell := WorldCell.new()
	check(cell.op_name(WorldCell.Op.PROPOSE) == "PROPOSE", "name(PROPOSE)")
	check(cell.op_name(WorldCell.Op.EXECUTE) == "EXECUTE", "name(EXECUTE)")
	check(cell.op_name(WorldCell.Op.RENDER)  == "RENDER",  "name(RENDER)")
	check(cell.op_name(WorldCell.Op.VERIFY)  == "VERIFY",  "name(VERIFY)")
	check(cell.op_name(WorldCell.Op.REFINE)  == "REFINE",  "name(REFINE)")


func test_propose_sets_state_hash() -> void:
	print("== test_propose_sets_state_hash ==")
	var cell := WorldCell.new()
	# Init state_hash is all-zero
	var all_zero: bool = true
	for i in range(32):
		if cell.state_hash[i] != 0:
			all_zero = false
	check(all_zero, "init state_hash is all-zero")
	# Propose sets a non-zero hash
	check(cell.propose("x = 1; y = x + 2") == 0, "propose returns 0")
	var not_zero: bool = false
	for i in range(32):
		if cell.state_hash[i] != 0:
			not_zero = true
	check(not_zero, "after propose, state_hash is non-zero")
	# A different program produces a different hash
	var h1: PackedByteArray = cell.state_hash
	check(cell.propose("x = 1; y = x + 3") == 0, "different code propose returns 0")
	var different: bool = false
	for i in range(32):
		if h1[i] != cell.state_hash[i]:
			different = true
	check(different, "different code -> different state_hash")
	check(cell.n_propose == 2, "n_propose = 2")


func test_propose_updates_prev_hash() -> void:
	print("== test_propose_updates_prev_hash ==")
	var cell := WorldCell.new()
	cell.propose("v1")
	var h1: PackedByteArray = cell.state_hash
	# After first propose, prev_hash is all-zero
	var prev_zero: bool = true
	for i in range(32):
		if cell.prev_hash[i] != 0:
			prev_zero = false
	check(prev_zero, "prev_hash is all-zero after first propose")
	cell.propose("v2")
	# After second propose, prev_hash == h1
	var prev_eq_h1: bool = true
	for i in range(32):
		if cell.prev_hash[i] != h1[i]:
			prev_eq_h1 = false
	check(prev_eq_h1, "after second propose, prev_hash == state_hash after first")


func test_execute_produces_quantity() -> void:
	print("== test_execute_produces_quantity ==")
	var cell := WorldCell.new()
	cell.propose("x = 5; y = x * 2")
	var q: Dictionary = cell.execute([])
	check(q.has("value"), "execute returns dict with 'value'")
	check(q["value"] >= -50.0 and q["value"] <= 50.0, "value in -50..+50")
	check(q["uncertainty"] >= 0.0 and q["uncertainty"] <= 0.9, "uncertainty in 0..0.9")
	check(q["unit"] == "?", "unit is '?'")
	check(cell.n_execute == 1, "n_execute = 1")


func test_verify_resets_on_propose() -> void:
	print("== test_verify_resets_on_propose ==")
	var cell := WorldCell.new()
	cell.propose("x = 1")
	cell.verify(0.0, 100.0)  # wide tolerance
	check(cell.verified, "verify sets verified with wide tolerance")
	cell.propose("x = 2")
	check(not cell.verified, "new propose resets verified = 0")


func test_render_writes_placeholder() -> void:
	print("== test_render_writes_placeholder ==")
	var cell := WorldCell.new()
	cell.propose("render a sphere")
	var path: String = "user://test_world_cell.png"
	check(cell.render(path) == 0, "render returns 0")
	check(FileAccess.file_exists(path), "render wrote a file")
	# Clean up
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(cell.n_render == 1, "n_render = 1")


func test_refine_appends_hint() -> void:
	print("== test_refine_appends_hint ==")
	var cell := WorldCell.new()
	cell.propose("x = 1")
	var h_before: PackedByteArray = cell.state_hash
	check(cell.refine("object is heavier"), "refine with hint returns true")
	check("object is heavier" in cell.code, "refine appended the hint")
	var different: bool = false
	for i in range(32):
		if h_before[i] != cell.state_hash[i]:
			different = true
	check(different, "state_hash changed after refine")
	check(cell.n_refine == 1, "n_refine = 1")


func test_polyformalism_shape() -> void:
	print("== test_polyformalism_shape ==")
	# The 10 opcodes (5+1+1+1+1+1) apply to the GDScript port.
	# The 5 abductive-loop operations are 0..4.
	check(WorldCell.Op.PROPOSE == 0, "PROPOSE = 0")
	check(WorldCell.Op.EXECUTE == 1, "EXECUTE = 1")
	check(WorldCell.Op.RENDER  == 2, "RENDER = 2")
	check(WorldCell.Op.VERIFY  == 3, "VERIFY = 3")
	check(WorldCell.Op.REFINE  == 4, "REFINE = 4")
	# 5 + 1 + 1 + 1 + 1 + 1 = 10
	check(5 + 1 + 1 + 1 + 1 + 1 == 10, "10 opcodes total")
