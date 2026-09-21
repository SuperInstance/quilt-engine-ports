extends Node
## jev_receipts_test.gd — headless conformance for the JEV receipts port.
##
## Pins the cross-language contract from docs/JEV-SPEC.md (jev-quilt PR #4)
## against jev_receipts.gd:
##   J1 — fnv1a-64 over UTF-8 BYTES: "café Δ 日本語" → 0x024a555471370b18d
##        (the vector Python, Rust, and the duke-lab WASM port all pin)
##   J2 — a residue-carrying receipt re-derives payload_hash from the
##        retained payload: editing payload alone breaks replay
##   J3 — empty payload keeps the stored hash (historical formula,
##        back-compat pinned)
##   J4 — verify(): ticks strictly increasing from 1; replay() is the
##        tamper referee (one edited receipt diverges the chain)
##   J5 — JevCell: integer (k, s) identity law; below-floor deltas are
##        silence (law 2); above-floor deltas are booked
##
## Prints "J<n> PASS <detail>" / "J<n> FAIL <detail>", exits 0/1 —
## same shape as laws_test.gd, run by scripts/ci.sh.

const JR = preload("res://scripts/jev_receipts.gd")

var failures: int = 0

func _ready() -> void:
	print("=== jev receipts headless conformance ===")
	j1_fnv1a_bytes_pinned_vector()
	j2_payload_tamper_breaks_replay()
	j3_empty_payload_back_compat()
	j4_verify_and_replay_referee()
	j5_cell_identity_and_floor()
	print()
	if failures == 0:
		print("=== ALL J1-J5 PASS ===")
		get_tree().quit(0)
	else:
		print("=== ", failures, " JEV CONFORMANCE FAILURES ===")
		get_tree().quit(1)


func check(ok: bool, label: String, detail: String) -> void:
	if ok:
		print(label, " PASS ", detail)
	else:
		print(label, " FAIL ", detail)
		failures += 1


func j1_fnv1a_bytes_pinned_vector() -> void:
	var got: String = JR.Hash.fnv1a_hex("café Δ 日本語")
	check(got == "24a555471370b18d", "J1",
		"fnv1a-64('café Δ 日本語') = %s (want 24a555471370b18d = 0x024a555471370b18d)" % got)
	var ascii: String = JR.Hash.fnv1a_hex("hello")
	check(ascii == "a430d84680aabd0b", "J1",
		"fnv1a-64('hello') = %s (want a430d84680aabd0b)" % ascii)


func j2_payload_tamper_breaks_replay() -> void:
	var bk: JR.Bookkeeper = JR.Bookkeeper.new("c")
	bk.book({"v": 1}, {"d": 1}, "observe", {"surprise": 3, "note": "café Δ"})
	var chain: String = bk.replay()
	# tamper with the retained residue TEXT only (hash field untouched)
	bk.entries[0].payload = '{"surprise": 3, "note": "café Δ — edited"}'
	check(bk.replay() != chain, "J2",
		"payload-text edit diverges the chain (hash field never touched)")


func j3_empty_payload_back_compat() -> void:
	var r: JR.Receipt = JR.Receipt.new(1, "aa", "bb", "observe", "0123456789abcdef", "")
	var direct: String = r.sha()
	# stored hash is used verbatim when payload is empty, even if it is
	# NOT the fnv1a of anything — the historical formula, pinned
	var implied: String = JR.Hash.sha256_hex("1|aa|bb|observe|0123456789abcdef")
	check(direct == implied, "J3", "empty payload keeps stored payload_hash")


func j4_verify_and_replay_referee() -> void:
	var bk: JR.Bookkeeper = JR.Bookkeeper.new("c")
	for i in 3:
		bk.book({"v": i}, {"d": i}, "observe", {"surprise": i})
	check(bk.verify(), "J4", "ticks 1..3 strictly increasing")
	bk.entries[2].tick = 7
	check(not bk.verify(), "J4", "gapped ticks fail verify()")


func j5_cell_identity_and_floor() -> void:
	var c: JR.JevCell = JR.JevCell.new("probe", 3, 5)
	c.surprise_floor = 4
	c.observe(10)                     # window empty → mean 0, surprise 10 ≥ floor: booked
	var r2: Variant = c.observe(10)   # mean 10, surprise 0 < floor: silence
	check(r2 == null, "J5", "below-floor delta is silence (law 2)")
	var r3: Variant = c.observe(20)   # mean 10, surprise 10 ≥ floor: booked
	check(r3 != null and r3.tick == 2, "J5",
		"above-floor delta booked (tick %d)" % (r3.tick if r3 != null else -1))
	check(c.book.verify(), "J5", "cell book verifies")
	# float identity: typed int params refuse at the binding level; an
	# untyped Variant float reaching the runtime guard is refused loudly
	var k: Variant = 1.5
	var c2: JR.JevCell = JR.JevCell.new("bad", k, 2)
	check(c2.refused, "J5", "float (k, s) identity refused")
