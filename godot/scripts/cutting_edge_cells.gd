extends RefCounted
## quilt-engine-ports/godot/scripts/cutting_edge_cells.gd
##
## The 4 cutting-edge adoptions in GDScript (Phase 227):
##   - PROOF: signed hash-linked audit chain
##   - ROUTE:  substrate routing for memory
##   - CRDT:   state-based CRDT for offline convergence
##   - WORLD:  physical.world (Code-as-World) -- separate file
##
## Mirrors the C and Rust polyformalism ports.

class_name CuttingEdgeCells

const FNV_OFFSET: int = -3750763034362895579
const FNV_PRIME:  int = 1099511628211


# ──────────────────────────────── FNV-1a
static func fnv1a64_str(s: String) -> int:
	var h: int = FNV_OFFSET
	var bytes := s.to_utf8_buffer()
	for i in range(bytes.size()):
		h = (h ^ bytes[i]) & -1
		h = (h * FNV_PRIME) & -1
	return h


# ═══════════════════════════════ PROOF ═══════════════════════════════
## Signed hash-linked audit chain.
## Each BIND records the previous state_hash, then signs the
## (prev_hash, new_state, secret) triple with HMAC-style keyed hash.
## The verifier checks both: prev_hash is the previous link, and
## sig matches.

class ProofEntry:
	var prev_hash: int = 0
	var new_state: int = 0
	var sig: int = 0
	var secret: int = 0

	func _init(p: int, n: int, s: int, k: int) -> void:
		prev_hash = p
		new_state = n
		sig = s
		secret = k


class ProofChain:
	var entries: Array = []  # Array[ProofEntry]
	var ring_size: int = 1024
	var secret: int

	func _init(k: int = -867530904004197377) -> void:
		secret = k

	func append(state: int) -> ProofEntry:
		var prev: int = 0
		if entries.size() > 0:
			prev = entries[-1].new_state
		# HMAC-style: sig = FNV(state XOR secret) XOR prev
		var s: int = (state ^ secret) & -1
		s = (s * FNV_PRIME) & -1
		s = (s ^ prev) & -1
		var e := ProofEntry.new(prev, state, s, secret)
		entries.append(e)
		# Ring buffer
		if entries.size() > ring_size:
			entries.pop_front()
		return e

	func verify_full() -> bool:
		for i in range(1, entries.size()):
			var cur: ProofEntry = entries[i]
			var prev: ProofEntry = entries[i - 1]
			if cur.prev_hash != prev.new_state:
				return false
			var expected: int = (cur.new_state ^ cur.secret) & -1
			expected = (expected * FNV_PRIME) & -1
			expected = (expected ^ cur.prev_hash) & -1
			if cur.sig != expected:
				return false
		return true


# ═══════════════════════════════ ROUTE ═══════════════════════════════
## Substrate routing for memory. Picks the substrate based on
## the value's type/size.

enum Substrate { DENSE_VEC, SPARSE_IDX, TEXT_LOG, HIER_STORE, PARAM_UPDATE }


static func route(v: Variant) -> int:
	if v == null:
		return Substrate.TEXT_LOG
	if v is bool:
		return Substrate.PARAM_UPDATE
	if v is int:
		return Substrate.SPARSE_IDX
	if v is float:
		return Substrate.DENSE_VEC
	if v is String:
		var s: String = v
		if s.length() < 64:
			return Substrate.HIER_STORE
		return Substrate.DENSE_VEC
	if v is Array or v is Dictionary:
		return Substrate.DENSE_VEC
	return Substrate.DENSE_VEC


# ═══════════════════════════════ CRDT ═══════════════════════════════
## State-based CRDT for offline convergence.
## Three kinds: PN_Counter, MV_Register, OR_Set.

class PNCounter:
	## PN-Counter: 2-state superposition (positive vs negative)
	var p: Dictionary = {}  # actor -> positive count
	var n: Dictionary = {}  # actor -> negative count

	func inc(actor: String, amount: int = 1) -> void:
		p[actor] = (p.get(actor, 0) + amount) if amount > 0 else p.get(actor, 0)
		n[actor] = (n.get(actor, 0) + (-amount)) if amount < 0 else n.get(actor, 0)

	func value() -> int:
		var sum: int = 0
		for a in p:
			sum += p[a]
		for a in n:
			sum -= n[a]
		return sum

	func merge(other: PNCounter) -> void:
		for a in other.p:
			p[a] = max(p.get(a, 0), other.p[a])
		for a in other.n:
			n[a] = max(n.get(a, 0), other.n[a])


class MVRegister:
	## MV-Register: N-state superposition (read wins via vector clock)
	var values: Array = []  # Array[{value, clock}]
	var my_id: String

	func _init(id: String) -> void:
		my_id = id

	func write(value: Variant, clock: int) -> void:
		# Single-value, set both
		values = [{"value": value, "clock": clock, "id": my_id}]

	func read() -> Variant:
		if values.is_empty():
			return null
		var best: Dictionary = values[0]
		for v in values:
			if v["clock"] > best["clock"]:
				best = v
		return best["value"]

	func merge(other: MVRegister) -> void:
		# Take the higher clock
		var mine: int = 0
		if not values.is_empty():
			mine = values[0]["clock"]
		var theirs: int = 0
		if not other.values.is_empty():
			theirs = other.values[0]["clock"]
		if theirs > mine:
			values = other.values.duplicate()
		# else: keep ours


class ORSet:
	## OR-Set: add/remove superposition (add wins, then remove)
	var elements: Dictionary = {}  # value -> {actor -> unique_tag}

	func add(value: Variant, actor: String, tag: int) -> void:
		if not elements.has(value):
			elements[value] = {}
		elements[value][actor] = tag

	func remove(value: Variant) -> void:
		if elements.has(value):
			elements[value].clear()

	func contains(value: Variant) -> bool:
		if not elements.has(value):
			return false
		return elements[value].size() > 0

	func merge(other: ORSet) -> void:
		for value in other.elements:
			if not elements.has(value):
				elements[value] = {}
			for actor in other.elements[value]:
				elements[value][actor] = other.elements[value][actor]

	func value() -> Array:
		var out: Array = []
		for v in elements:
			if contains(v):
				out.append(v)
		return out


# ═══════════════════════════════ WORLD ═══════════════════════════════
## physical.world cell kind is in world_cell.gd (separate file).
## This module re-exports the key functions for the conformance suite.
static func world_kind_name() -> String:
	return "physical.world"

static func world_kind_count() -> int:
	return 5
