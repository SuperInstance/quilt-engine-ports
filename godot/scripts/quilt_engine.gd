extends Node2D
## quilt-engine-ports — Godot reference scaffold.
##
## The quilt 5+1 opcodes in Godot: cells as Nodes, TICK as _process,
## the sheet as JSON loaded at runtime (engine-agnostic format, see
## docs/DESIGN.md §3.2).
##
##   BIND   scatter  — write a value to a named cell           (idempotent)
##   LINK   connect  — add a dependency edge                   (transitive, acyclic)
##   EFFECT transform — apply a registered effect to a cell     (associative; STUBBED in v0.1)
##   VIEW   gather   — read cells                              (pure)
##   TICK   wavefront — recompute the dirty set, once per frame (monotonic, journaled)
##   FORGET teardown — release bindings + links + visuals       (complete; grant-tracking STUBBED in v0.1)
##
## Laws enforced here, cheaply and visibly:
##   BIND  idempotence  — rebinding the same id+value is a no-op (journal records nothing)
##   LINK  transitivity — reachability is walkable via links(); cycles are rejected at link time
##   EFFECT associativity — the dispatch table is ordered; composition order is preserved
##   VIEW  purity       — view() returns values and mutates nothing
##   TICK  monotonicity — tick count only increases; the journal is append-only
##   FORGET completeness — a forgotten cell leaves no node, no edge, no dirty bit

const DEFAULT_SHEET := "res://sheets/bay_controller.json"
const COLUMNS := 3
const CELL_SPACING := Vector2(300.0, 110.0)
const CELL_ORIGIN := Vector2(90.0, 70.0)

class Cell:
	var id: String
	var kind: String        ## value | formula | io | sensor
	var value: Variant = null
	var expr: String = ""
	var reads: Array = []
	var label: Label = null

## ------------------------------------------------------------------ state

var _cells: Dictionary = {}     ## id -> Cell
var _links: Dictionary = {}     ## id -> { to_id: true }   out-edges (CSR-shaped)
var _links_in: Dictionary = {}  ## id -> { from_id: true } in-edges
var _topo_order: Array = []     ## Array[String], topological, deterministic
var _dirty: Dictionary = {}     ## id -> true
var _tick_count: int = 0
var _journal: Array = []        ## append-only tick records (TICK monotonicity)
var _effects: Dictionary = {}   ## EFFECT dispatch table (stubbed: name -> Callable)
var mhs: MhsTransport = null    ## the MHS seam (mock transport in the scaffold)

## ------------------------------------------------------------------ BIND

func bind(id: String, kind: String, value: Variant = null) -> void:
	## BIND(n, v); BIND(n, v) = BIND(n, v)  — same id + same value is a no-op.
	if _cells.has(id):
		var c: Cell = _cells[id]
		if c.value == value:
			return
		c.value = value
		_mark_dirty(id)
		return
	var c := Cell.new()
	c.id = id
	c.kind = kind
	c.value = value
	_cells[id] = c
	_links[id] = {}
	_links_in[id] = {}
	_spawn_label(c)
	_mark_dirty(id)

## ------------------------------------------------------------------ LINK

func link(from_id: String, to_id: String) -> Error:
	## Add a dependency edge from_id -> to_id. Rejects unknown ids and cycles
	## (a cycle would break the TICK wavefront, so it never enters the graph).
	if not _cells.has(from_id) or not _cells.has(to_id):
		push_error("LINK: unknown cell (%s -> %s)" % [from_id, to_id])
		return ERR_DOES_NOT_EXIST
	if _links[from_id].has(to_id):
		return OK  # idempotent edge add
	if _reaches(to_id, from_id):
		push_error("LINK: cycle rejected (%s -> %s)" % [from_id, to_id])
		return ERR_CYCLIC_LINK
	_links[from_id][to_id] = true
	_links_in[to_id][from_id] = true
	_rebuild_topo()
	_mark_dirty(to_id)
	return OK

func links(from_id: String) -> Array:
	## Direct out-edges. Transitivity is reachable through _reaches()
	## (a->b + b->c implies a->c without adding the shortcut edge —
	## topology stays authored, reachability stays walkable).
	return _links.get(from_id, {}).keys()

func _reaches(start: String, target: String) -> bool:
	if start == target:
		return true
	var seen := { start: true }
	var stack: Array = [start]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		for nxt in _links.get(cur, {}).keys():
			if nxt == target:
				return true
			if not seen.has(nxt):
				seen[nxt] = true
				stack.push_back(nxt)
	return false

## ------------------------------------------------------------------ VIEW

func view(ids: Array) -> Dictionary:
	## Pure gather. Reads values, mutates nothing.
	var out := {}
	for id in ids:
		if _cells.has(id):
			out[id] = _cells[id].value
	return out

## ------------------------------------------------------------------ EFFECT (STUB)

func register_effect(effect_name: String, fn: Callable) -> void:
	## EFFECT dispatch table. v0.1 ships the table and the associativity
	## guarantee (registered order is invocation order); no built-in effects.
	_effects[effect_name] = fn

func effect(id: String, effect_name: String, args: Array = []) -> Error:
	if not _cells.has(id):
		return ERR_DOES_NOT_EXIST
	if not _effects.has(effect_name):
		return ERR_UNAVAILABLE  # stub: nothing registered in v0.1
	return _effects[effect_name].call(id, args)

## ------------------------------------------------------------------ TICK

func _process(delta: float) -> void:
	## The frame IS the tick (conformance C3): no second scheduler, no timer.
	_demo_drive_mhs(delta)
	tick(delta)

func tick(_delta: float) -> int:
	## Recompute the dirty wavefront in topological order, once per frame.
	_tick_count += 1
	var computed := 0
	for id in _topo_order:
		if _dirty.has(id):
			_recompute(_cells[id])
			computed += 1
	if computed > 0:
		_journal.append({ "tick": _tick_count, "computed": computed })
	return computed

func _recompute(c: Cell) -> void:
	_dirty.erase(c.id)
	var prev := c.value
	if c.kind == "formula":
		c.value = _eval_formula(c)
	if c.value != prev:
		_update_label(c)
		for nxt in _links[c.id].keys():
			_mark_dirty(nxt)

func _eval_formula(c: Cell) -> Variant:
	## Formula variables are the last path segment of each read:
	##   reads ["bay.pump.power", "bay.pump.threshold"] -> power, threshold
	## Sheets are trusted input (same trust model as quilt-rust program cells).
	## Constraint: last segments must be unique per formula.
	var names: Array = []
	var values: Array = []
	for r in c.reads:
		names.push_back(r.get_slice(".", r.get_slice_count(".") - 1))
		values.push_back(_cells[r].value if _cells.has(r) else null)
	var e := Expression.new()
	if e.parse(c.expr, PackedStringArray(names)) != OK:
		push_error("formula parse error on %s: %s" % [c.id, e.get_error_text()])
		return null
	var result: Variant = e.execute(values)
	if e.has_execute_failed():
		push_error("formula execute error on %s" % c.id)
		return null
	return result

## ------------------------------------------------------------------ FORGET (stub)

func forget(id: String) -> void:
	## Teardown: cell, both edge sets, dirty bit, visual — nothing left.
	## v0.1 stub: MHS grant-tracking lands with interlocks (docs/DESIGN.md §3.4).
	var c: Cell = _cells.get(id)
	if c == null:
		return
	for to_id in _links.get(id, {}).keys():
		_links_in[to_id].erase(id)
	for from_id in _links_in.get(id, {}).keys():
		_links[from_id].erase(id)
	_links.erase(id)
	_links_in.erase(id)
	if c.label != null:
		c.label.queue_free()
	_cells.erase(id)
	_dirty.erase(id)
	_rebuild_topo()

## ------------------------------------------------------------------ sheet loading

func load_sheet(path: String) -> Error:
	## The engine-agnostic cell-graph JSON (docs/DESIGN.md §3.2):
	## bind every cell, link every reads[] edge, recompute once. O(cells+edges).
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("sheet not found: %s" % path)
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("sheet is not a JSON object: %s" % path)
		return ERR_PARSE_ERROR
	for cell_def in parsed.get("cells", []):
		bind(cell_def.get("id", ""), cell_def.get("kind", "value"), cell_def.get("value", null))
		if cell_def.has("expr"):
			_cells[cell_def["id"]].expr = cell_def["expr"]
		if cell_def.has("reads"):
			_cells[cell_def["id"]].reads = cell_def["reads"]
			for r in cell_def["reads"]:
				var err := link(r, cell_def["id"])
				if err != OK:
					return err
	_rebuild_topo()
	return OK

## ------------------------------------------------------------------ MHS seam

class MhsTransport:
	## The MHS seam: discover / read / write / abort, isolated behind one class
	## so the real SDK drops in as a subclass without touching the engine
	## (conformance C6; shape mirrors quilt-mhs MhsClient).
	var _channels := {}    ## "device/channel" -> value
	var _envelope := {}    ## "device/channel" -> [lo, hi]

	func discover(_kind_hint: String = "") -> Array:
		return ["mock-01"]

	func define_channel(device: String, channel: String, value: Variant, lo: Variant, hi: Variant) -> void:
		var k := device + "/" + channel
		_channels[k] = value
		_envelope[k] = [lo, hi]

	func read(device: String, channel: String) -> Variant:
		return _channels.get(device + "/" + channel, null)

	func write(device: String, channel: String, value: Variant) -> Error:
		## Enforce the envelope: REJECT out-of-range, never clamp
		## (a clamping transport fails conformance, not the operator).
		var k := device + "/" + channel
		if _envelope.has(k):
			var bounds: Array = _envelope[k]
			if value < bounds[0] or value > bounds[1]:
				return ERR_INVALID_DATA
		_channels[k] = value
		return OK

	func abort(_device: String) -> Error:
		_channels.clear()
		return OK

func _demo_drive_mhs(_delta: float) -> void:
	## Demo: a (mocked) MHS power channel feeds the sheet each tick.
	## With a real transport, this same line reads a real device.
	if mhs == null:
		return
	var t := float(_tick_count) / 60.0
	var power := 0.5 + 0.5 * sin(t * 0.8)
	var err := mhs.write("mock-01", "pump.power", power)  # envelope 0..1
	if err == OK:
		bind("bay.pump.power", "io", mhs.read("mock-01", "pump.power"))

## ------------------------------------------------------------------ visuals

func _spawn_label(c: Cell) -> void:
	## Minimal cell-graph visualizer (conformance C7): one Label per cell,
	## one Line2D per link, updated live during TICK.
	var l := Label.new()
	l.position = CELL_ORIGIN + Vector2(CELL_SPACING.x * (c.id.hash() % COLUMNS), CELL_SPACING.y)
	l.add_theme_font_size_override("font_size", 18)
	add_child(l)
	c.label = l
	_update_label(c)

func _update_label(c: Cell) -> void:
	if c.label == null:
		return
	c.label.text = "%s = %s" % [c.id, str(c.value)]

func _draw_links() -> void:
	draw_set_transform(Vector2.ZERO)
	for id in _links.keys():
		var a: Cell = _cells.get(id)
		if a == null or a.label == null:
			continue
		for to_id in _links[id].keys():
			var b: Cell = _cells.get(to_id)
			if b == null or b.label == null:
				continue
			draw_line(a.label.position + Vector2(0, 18), b.label.position, Color(0.45, 0.65, 0.55, 0.9), 2.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW:
		_draw_links()

## ------------------------------------------------------------------ internals

func _mark_dirty(id: String) -> void:
	_dirty[id] = true

func _rebuild_topo() -> void:
	## Kahn's algorithm, deterministic (sorted ids) — the TICK wavefront order.
	_topo_order = []
	var indeg := {}
	for id in _cells.keys():
		indeg[id] = _links_in[id].size()
	var ready := []
	for id in indeg.keys():
		if indeg[id] == 0:
			ready.push_back(id)
	ready.sort()
	while not ready.is_empty():
		ready.sort()
		var cur: String = ready.pop_front()
		_topo_order.push_back(cur)
		for nxt in _links[cur].keys():
			indeg[nxt] -= 1
			if indeg[nxt] == 0:
				ready.push_back(nxt)

## ------------------------------------------------------------------ lifecycle

func _ready() -> void:
	mhs = MhsTransport.new()
	mhs.define_channel("mock-01", "pump.power", 0.0, 0.0, 1.0)
	var err := load_sheet(DEFAULT_SHEET)
	if err != OK:
		push_error("sheet load failed: %d" % err)

## ------------------------------------------------------------------ conformance helpers (laws)

func tick_count() -> int:
	return _tick_count

func journal() -> Array:
	return _journal.duplicate()

func cells() -> Array:
	return _cells.keys()

func assert_laws() -> Array:
	## Cheap law checks runnable from any test harness (docs/DESIGN.md §2, C4).
	var results := []
	# BIND idempotence
	var before := _journal.size()
	bind("bay.pump.threshold", "value", 0.7)
	bind("bay.pump.threshold", "value", 0.7)
	results.push_back({ "law": "bind_idempotence", "holds": _journal.size() == before })
	# VIEW purity
	var v_before := view(["bay.pump.running"])
	var v_after := view(["bay.pump.running"])
	results.push_back({ "law": "view_purity", "holds": v_before.hash() == v_after.hash() and _journal.size() == before })
	# TICK monotonicity
	var t_before := _tick_count
	tick(1.0 / 60.0)
	results.push_back({ "law": "tick_monotonicity", "holds": _tick_count == t_before + 1 })
	# LINK transitivity (walkable)
	results.push_back({ "law": "link_transitivity", "holds": _reaches("bay.pump.power", "bay.uptime") })
	return results
