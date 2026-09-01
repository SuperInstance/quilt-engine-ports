extends RefCounted
## quilt-engine-ports/godot/scripts/world_cell.gd
##
## The `physical.world` cell kind in GDScript (Phase 227, 5th polyformalism).
##
## Mirrors the C and Rust polyformalism ports:
##   - quilt-c/include/quilt/world.h
##   - quilt-rust/crates/quilt-polyformalism/src/lib.rs (WorldCell)
##
## The 5 abductive-loop operations from the Code-as-World paper
## (MirroS-Lab, arXiv 2608.27549):
##   PROPOSE  -> BIND       (set the program text)
##   EXECUTE  -> EFFECT     (run the program, get a Quantity)
##   RENDER   -> side-eff   (write a placeholder file)
##   VERIFY   -> predicate  (compare to observed value)
##   REFINE   -> BIND+tag   (append a hint, re-propose)
##
## The state_hash is the FNV-1a 64-bit of the program text,
## spread over 4 slices for bit-exact compatibility with the
## C and Rust ports.

class_name WorldCell
extends RefCounted

const FNV_OFFSET: int = 0xcbf29ce484222325
const FNV_PRIME:  int = 0x100000001b3
const FNV_SLICE_MUL: int = 0x9e3779b97f4a7c15  # golden ratio

enum Op { PROPOSE = 0, EXECUTE = 1, RENDER = 2, VERIFY = 3, REFINE = 4 }

# The cell's program (text)
var code: String = ""
var code_len: int = 0
var state_hash: PackedByteArray = PackedByteArray()  # 32 bytes
var prev_hash: PackedByteArray = PackedByteArray()   # 32 bytes (PROOF chain)
var verified: bool = false

# Counters for each of the 5 operations
var n_propose: int = 0
var n_execute: int = 0
var n_render: int = 0
var n_verify: int = 0
var n_refine: int = 0


func _init() -> void:
	state_hash = PackedByteArray()
	state_hash.resize(32)  # all-zero
	prev_hash = PackedByteArray()
	prev_hash.resize(32)  # all-zero


# FNV-1a 64-bit (matches the C and Rust ports)
static func fnv1a64(data: PackedByteArray) -> int:
	var h: int = FNV_OFFSET
	for i in range(data.size()):
		h = (h ^ data[i]) & 0xFFFFFFFFFFFFFFFF
		h = (h * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
	return h


static func fnv1a64_str(s: String) -> int:
	return fnv1a64(s.to_utf8_buffer())


# Spread a 64-bit hash over 4 slices to make 32 bytes
static func hash_to_32(h: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(32)
	for i in range(4):
		var slice: int = (h + (i * FNV_SLICE_MUL)) & 0xFFFFFFFFFFFFFFFF
		# Little-endian
		for j in range(8):
			out[i * 8 + j] = (slice >> (j * 8)) & 0xFF
	return out


# BIND with PROOF chain: save prev_hash before overwriting
func _set_code(new_code: String) -> void:
	prev_hash = state_hash
	state_hash = hash_to_32(fnv1a64_str(new_code))
	code = new_code
	code_len = new_code.length()
	verified = false  # any BIND invalidates verification


func op_name(op: int) -> String:
	match op:
		Op.PROPOSE: return "PROPOSE"
		Op.EXECUTE: return "EXECUTE"
		Op.RENDER:  return "RENDER"
		Op.VERIFY:  return "VERIFY"
		Op.REFINE:  return "REFINE"
		_: return "?"


static func kind_name() -> String:
	return "physical.world"


static func kind_count() -> int:
	return 5


# The 5 abductive-loop operations ----------------------------------

func propose(p_code: String) -> int:
	if p_code.is_empty():
		return -1
	_set_code(p_code)
	n_propose += 1
	return 0


# Synthetic execute: hash of code + reads, mapped to (-50..+50, 0..0.9)
func execute(reads: Array) -> Dictionary:
	if code.is_empty():
		return {}
	var h: int = fnv1a64_str(code)
	for r in reads:
		var bytes := PackedByteArray()
		if r is float:
			bytes.resize(8)
			bytes.encode_float(0, r)
		elif r is int:
			bytes.resize(8)
			bytes.encode_s64(0, r)
		h = h ^ fnv1a64(bytes)
		h = (h * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
	var value: float = float(h % 100) - 50.0
	var uncertainty: float = float(h % 10) * 0.1
	n_execute += 1
	return {"value": value, "uncertainty": uncertainty, "unit": "?", "verified": verified}


# Stub render: write a placeholder file
func render(image_path: String) -> int:
	var f := FileAccess.open(image_path, FileAccess.WRITE)
	if f == null:
		return -1
	f.store_string("PNG placeholder for program of length %d\n" % code_len)
	f.close()
	n_render += 1
	return 0


# Verify: compare execute's value to observed within tolerance
func verify(observed: float, tolerance: float) -> bool:
	var q: Dictionary = execute([])
	var diff: float = q["value"] - observed
	var ok: bool = abs(diff) <= tolerance
	verified = ok
	n_verify += 1
	return ok


# Refine: append a hint to the program
func refine(hint: String) -> bool:
	if code.is_empty():
		return false
	var new_code: String = code + "\n# refine: " + hint + "\n"
	_set_code(new_code)
	n_refine += 1
	return true
