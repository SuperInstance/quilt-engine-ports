extends RefCounted
## jev_receipts.gd — JEV receipts (fnv1a-64 + hash-chained WAL) in GDScript.
##
## No class_name: headless runs have no global class cache, so consumers
## preload this file (same discipline as quilt_engine.gd).
##
## Port of SuperInstance/jev-quilt's bookkeeper.py per docs/JEV-SPEC.md
## (jev-quilt PR #4). The contract pinned cross-language:
##   1. fnv1a-64 over raw UTF-8 BYTES (never characters — non-ASCII safe)
##   2. payload_hash = fnv1a-64 of the residue's UTF-8 bytes
##   3. Receipt.sha() binds the residue TEXT: a non-empty payload re-derives
##      payload_hash from the retained payload at sha() time, so editing
##      payload alone breaks replay; empty payload keeps the stored hash
##      (the historical formula, back-compat pinned)
##   4. replay = sha256 over the concatenated per-receipt shas — divergence
##      is the tamper referee
## Pinned vector (Python, Rust, WASM ports all agree):
##   fnv1a("café Δ 日本語") = 0x024a555471370b18d
##
## GDScript ints are signed 64-bit; hash state is carried as two's-complement
## and rendered unsigned via 32-bit halves (Hash.hex64), so values above 2^63
## are exact. The 64x64 multiply is limb-based (16-bit limbs) so it cannot
## trip a debug build's signed-overflow error.
##
## Residue serialization (JSON) is engine-local and NOT pinned cross-language;
## the pinned contract is the hash law above, not the byte layout.


class Hash:
	## fnv1a-64 + sha256 helpers. Hash state is int64 two's-complement.

	# 0xcbf29ce484222325 does not fit int64 as a literal; its two's-complement
	# decimal is the same constant every other port starts from.
	const FNV_OFFSET := -3750763034362895579  # == 0xcbf29ce484222325 unsigned
	const FNV_PRIME := 0x100000001b3          # 1099511628211
	const RESIDUE_CAP := 200

	static func mul64(a: int, b: int) -> int:
		## Low 64 bits of a*b via 16-bit limbs — no signed overflow possible.
		const M := 0xFFFF
		var al := [a & M, (a >> 16) & M, (a >> 32) & M, (a >> 48) & M]
		var bl := [b & M, (b >> 16) & M, (b >> 32) & M, (b >> 48) & M]
		var p := [0, 0, 0, 0, 0, 0, 0]
		for i in 4:
			for j in 4:
				p[i + j] += al[i] * bl[j]
		for i in 6:
			p[i + 1] += p[i] >> 16
			p[i] &= M
		return p[0] | (p[1] << 16) | (p[2] << 32) | (p[3] << 48)

	static func fnv1a_64(data: PackedByteArray) -> int:
		## fnv1a-64 over raw bytes; result as int64 two's-complement.
		var h := FNV_OFFSET
		for b in data:
			h = h ^ b
			h = mul64(h, FNV_PRIME)
		return h

	static func hex64(h: int) -> String:
		## Unsigned 16-digit hex of a 64-bit two's-complement int.
		# GDScript's "%08x" does not zero-pad hex — pad manually.
		var hi := "%x" % ((h >> 32) & 0xFFFFFFFF)
		var lo := "%x" % (h & 0xFFFFFFFF)
		while hi.length() < 8:
			hi = "0" + hi
		while lo.length() < 8:
			lo = "0" + lo
		return hi + lo

	static func fnv1a_hex(s: String) -> String:
		return hex64(fnv1a_64(s.to_utf8_buffer()))

	static func sha256_hex(s: String) -> String:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(s.to_utf8_buffer())
		return ctx.finish().hex_encode()


class Receipt:
	## One booked state change (jev-quilt bookkeeper.py, frozen dataclass).
	var tick: int
	var state_hash: String
	var delta_hash: String
	var decision_kind: String
	var payload_hash: String   # 16-digit hex, fnv1a-64 of residue bytes
	var payload: String = ""   # capped readable residue (Hash.RESIDUE_CAP chars)

	func _init(p_tick: int, p_state_hash: String, p_delta_hash: String,
			p_decision_kind: String, p_payload_hash: String, p_payload: String = "") -> void:
		tick = p_tick
		state_hash = p_state_hash
		delta_hash = p_delta_hash
		decision_kind = p_decision_kind
		payload_hash = p_payload_hash
		payload = p_payload

	func sha() -> String:
		## Binds the residue TEXT, not merely its hash field (JEV-SPEC law 3).
		var ph := payload_hash
		if payload != "":
			ph = Hash.fnv1a_hex(payload)
		return Hash.sha256_hex("%d|%s|%s|%s|%s" % [
			tick, state_hash, delta_hash, decision_kind, ph])


class Bookkeeper:
	## Per-cell append-only WAL. Law 4: every state change is booked;
	## replay ≡ live. A cell woken by a delta replays its book to catch up.
	var cell_name: String
	var entries: Array = []   # Array[Receipt]
	var _tick := 0

	func _init(p_cell_name: String) -> void:
		cell_name = p_cell_name

	static func canon(v: Variant) -> String:
		## Engine-local residue/state serialization (sort_keys for
		## determinism). NOT pinned cross-language — the hash law is.
		return JSON.stringify(v, "", true)

	func book(state: Variant, delta: Variant, decision_kind: String, payload: Variant) -> Receipt:
		_tick += 1
		var residue := canon(payload).left(Hash.RESIDUE_CAP)
		var r := Receipt.new(
			_tick,
			Hash.sha256_hex(canon(state)),
			Hash.sha256_hex(canon(delta)),
			decision_kind,
			Hash.fnv1a_hex(residue),
			residue)
		entries.append(r)
		return r

	func replay() -> String:
		## Recompute the chain hash from the book. Divergence vs a stored
		## chain = tampering; replay is the referee.
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		for e in entries:
			ctx.update(e.sha().to_utf8_buffer())
		return ctx.finish().hex_encode()

	func verify() -> bool:
		## Structural check: ticks strictly increasing from 1, no empty tail.
		for i in entries.size():
			if entries[i].tick != i + 1:
				return false
		return true


class JevCell:
	## Minimal cell surface (law 1 + law 2 + the book): integer (k, s)
	## identity, a mean-window reading, and a surprise floor below which
	## deltas are silence. Float identity is refused loudly (refused flag) —
	## headless release builds ignore assert(), so refusal is a flag, not
	## a crash.
	var name: String
	var refused := false
	var k: int
	var s: int
	var window_size := 4
	var surprise_floor := 0      # integer magnitude; 0 = record everything
	var book := Bookkeeper.new("")
	var _window: Array = []      # ints

	func _init(p_name: String, coord_k: Variant, coord_s: Variant) -> void:
		name = p_name
		if typeof(coord_k) != TYPE_INT or typeof(coord_s) != TYPE_INT:
			push_error("cell %s: coord must be integer (k, s) — identity never floats" % p_name)
			refused = true
			return
		k = coord_k
		s = coord_s
		book = Bookkeeper.new(p_name)

	func observe(value: int) -> Variant:
		## Feed a reading. Returns the booked Receipt when |value − mean|
		## reaches the floor, or null when below it (law 2: silence).
		var mean := 0
		for v in _window:
			mean += v
		if not _window.is_empty():
			mean = int(mean / _window.size())
		_window.append(value)
		while _window.size() > window_size:
			_window.pop_front()
		var surprise: int = absi(value - mean)
		if surprise < surprise_floor:
			return null
		return book.book({"k": k, "s": s, "value": value}, {"surprise": surprise},
			"observe", {"surprise": surprise, "mean": mean, "n": _window.size()})
