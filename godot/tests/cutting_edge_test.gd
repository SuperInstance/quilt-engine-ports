extends Node

## Conformance tests for the 4 cutting-edge adoptions in GDScript.
## Mirrors the C and Rust polyformalism ports.

const CuttingEdgeCells = preload("res://scripts/cutting_edge_cells.gd")

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	print("=== quilt-engine-ports: 4 cutting-edge adoptions (Phase 227) ===\n")
	test_proof_chain()
	test_route_policy()
	test_crdt_pn_counter()
	test_crdt_mv_register()
	test_crdt_or_set()
	test_world_kind()
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


func test_proof_chain() -> void:
	print("== test_proof_chain ==")
	var chain := CuttingEdgeCells.ProofChain.new(0xDEADBEEF)
	chain.append(100)
	chain.append(200)
	chain.append(300)
	check(chain.entries.size() == 3, "3 entries appended")
	check(chain.verify_full(), "full chain verifies (prev_hash + sig)")
	# Tamper: change the second entry
	chain.entries[1].new_state = 999
	check(not chain.verify_full(), "tampered chain does not verify")


func test_route_policy() -> void:
	print("== test_route_policy ==")
	check(CuttingEdgeCells.route(null) == CuttingEdgeCells.Substrate.TEXT_LOG, "null -> TEXT_LOG")
	check(CuttingEdgeCells.route(true) == CuttingEdgeCells.Substrate.PARAM_UPDATE, "bool -> PARAM_UPDATE")
	check(CuttingEdgeCells.route(42) == CuttingEdgeCells.Substrate.SPARSE_IDX, "int -> SPARSE_IDX")
	check(CuttingEdgeCells.route(3.14) == CuttingEdgeCells.Substrate.DENSE_VEC, "float -> DENSE_VEC")
	check(CuttingEdgeCells.route("short") == CuttingEdgeCells.Substrate.HIER_STORE, "short string -> HIER_STORE")
	check(CuttingEdgeCells.route("a" + "a".repeat(100)) == CuttingEdgeCells.Substrate.DENSE_VEC, "long string -> DENSE_VEC")
	check(CuttingEdgeCells.route([1, 2, 3]) == CuttingEdgeCells.Substrate.DENSE_VEC, "array -> DENSE_VEC")


func test_crdt_pn_counter() -> void:
	print("== test_crdt_pn_counter ==")
	var a := CuttingEdgeCells.PNCounter.new()
	var b := CuttingEdgeCells.PNCounter.new()
	a.inc("alice", 5)
	b.inc("bob", 3)
	a.merge(b)
	check(a.value() == 8, "merged PN-Counter = 8")
	# Convergence: a.merge(b) == b.merge(a)
	var c := CuttingEdgeCells.PNCounter.new()
	var d := CuttingEdgeCells.PNCounter.new()
	c.inc("alice", 5)
	d.inc("bob", 3)
	d.merge(c)
	check(c.value() == d.value(), "PN-Counter converges")


func test_crdt_mv_register() -> void:
	print("== test_crdt_mv_register ==")
	var a := CuttingEdgeCells.MVRegister.new("alice")
	var b := CuttingEdgeCells.MVRegister.new("bob")
	a.write("v1", 1)
	b.write("v2", 2)
	# After merge, the higher clock wins
	a.merge(b)
	check(a.read() == "v2", "merge picks the higher clock")


func test_crdt_or_set() -> void:
	print("== test_crdt_or_set ==")
	var a := CuttingEdgeCells.ORSet.new()
	a.add("x", "alice", 1)
	check(a.contains("x"), "x is in the set after add")
	a.remove("x")
	check(not a.contains("x"), "x is removed")
	# Convergence: a.merge(b) preserves elements
	var b := CuttingEdgeCells.ORSet.new()
	b.add("y", "bob", 1)
	a.merge(b)
	check(a.contains("y"), "merged set contains y")


func test_world_kind() -> void:
	print("== test_world_kind ==")
	check(CuttingEdgeCells.world_kind_name() == "physical.world", "WORLD kind name = physical.world")
	check(CuttingEdgeCells.world_kind_count() == 5, "WORLD kind count = 5")
