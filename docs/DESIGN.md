# The 5+1 Opcodes Across Game Engines

> **Design document for quilt-engine-ports.** One opcode set, three engines.
> Cells as game objects. TICK as the engine frame. The cell graph as the scene.

The quilt engine has five opcodes and a sixth that makes it safe to walk away
from. Everything a quilt runtime does — evaluate a sheet, drive hardware,
federate with another quilt — reduces to `BIND / LINK / EFFECT / VIEW / TICK`
plus `FORGET` ([quilt-cellular-arch], [quilt-mhs]).

This document maps those six opcodes onto the three dominant game engines —
**Godot**, **Unity**, **Unreal** — and specifies what a port must implement to
be a quilt engine, not a quilt-flavored demo. The porting ladder runs
Godot → Unity → Unreal: Godot first because its scene system is the closest
structural match to a cell graph, Unity second because its ECS variant makes
the cell-graph-in-disguise claim concrete, Unreal last because its object
model is the furthest from JSON and the most work to bridge honestly.

Why game engines at all? Because a game engine is already a reactive runtime
with a scheduler (the frame loop), a graph (the scene tree), an inspector
(the editor), and a renderer. Quilt says your whole system is a reactive
graph of cells; a game engine says your whole system is a reactive graph of
nodes. Those are the same sentence with different accents. The port makes
the equivalence executable: a quilt sheet loads as a scene, ticks as the
frame, and renders as a live cell-graph visualizer — and through the MHS
seam, the same scene can drive real hardware.

---

## 1. The 5+1 opcodes (canonical)

Source of truth: [quilt-cellular-arch] (`FRAMEWORK.md`, `laws/`), proven
in [quilt-rust] (reference runtime), on metal in [quilt-esp32] (`qm_opcodes`),
and against MHS devices in [quilt-mhs].

| # | Opcode | Shape | Semantics | Law |
|---|--------|-------|-----------|-----|
| 1 | `BIND` | scatter | Write a value to N named cells. Parallel, name-addressed. | **idempotence**: `BIND(n,v); BIND(n,v) = BIND(n,v)` |
| 2 | `LINK` | connect | Construct the dependency graph. Edges are first-class; topology is data. | **transitivity**: `a→b ∧ b→c ⟹ a→c` (for transitive R) |
| 3 | `EFFECT` | transform | Apply a function across cells in parallel. The only opcode that *acts*. | **associativity**: `(f∘g)∘h = f∘(g∘h)` |
| 4 | `VIEW` | gather | Read N cells. The only opcode guaranteed never to modify state. | **purity**: `VIEW` leaves state untouched |
| 5 | `TICK` | wavefront | Advance time one step: evaluate the dirty wavefront in dependency order. | **monotonicity**: time advances; the journal is append-only |
| 6 | `FORGET` | teardown | The +1. Release bindings, links, grants. Park machines. Latch. | **forget-completeness**: grants released, machine parked and latched |

Two properties every port inherits for free:

- **Everything is SIMD-able.** BIND is scatter, LINK is CSR graph
  construction, EFFECT is parallel map, VIEW is gather, TICK is a wavefront
  schedule. A GPU runs all five at once; a game engine runs them sixty times
  a second.
- **The journal is the ground truth.** TICK appends; nothing rewrites
  history. This is what makes replay, debug, and federation tractable —
  and what makes `FORGET` a *safety* opcode rather than a destructor.

---

## 2. The porting contract

An engine port is a **quilt engine** when it satisfies this contract. Anything
less is a demo. (Pattern follows [quilt-mhs]' conformance suite: one contract,
conformance checks, many substrates.)

| C# | Requirement | Check |
|----|-------------|-------|
| C1 | All 5+1 opcodes are present, named, and semantically honest (no clamping — reject out-of-envelope like a real device would). | opcode smoke test |
| C2 | A cell-graph JSON (the sheet) loads from disk at runtime and becomes engine objects. No editor-only path. | load a sheet the editor never saw |
| C3 | The graph ticks from the engine's own frame loop — not a thread, not a timer the engine can't see. | frame-count test: N frames = N ticks |
| C4 | The 5 laws hold on the port: BIND idempotence, LINK transitivity, EFFECT associativity, VIEW purity, TICK monotonicity. | port the laws test from [quilt-cellular-arch] `laws/laws.py` |
| C5 | FORGET is complete: bindings, links, grants, timers — all torn down; the cell graph reverts to bindable-but-inert. | forget a bound sheet, assert no residue |
| C6 | The MHS seam is isolated behind one port/interface, so the real MHS SDK drops in without touching engine code. | compile against a mock; swap transports |
| C7 | A cell-graph visualizer exists in-engine: nodes render, links render, values update live during TICK. | eyeball test, 60fps with ≥100 cells |

**Honest floor for v0.1 (this repo):** Godot implements C1–C5 fully in the
reference scaffold (EFFECT/FORGET are law-shaped stubs — see §3.4); C6 is a
typed seam with a mock transport; C7 ships as a minimal visualizer scene.
Unity and Unreal are specified (§4, §5), not scaffolded. That's the ladder,
and we say so plainly.

---

## 3. Godot — the reference port

**Claim:** a Godot scene tree *is* a cell graph with a frame scheduler.
Cells map to `Node`s; `TICK` maps to `_process(delta)`; the sheet loads as
JSON at runtime. Godot is the reference port because the mapping is nearly
identity — no ECS detour, no reflection wall, no build step. GDScript reads
JSON natively and the scene tree is already a DAG with named nodes.

### 3.1 Opcode table

| Opcode | Godot construct | Notes |
|--------|-----------------|-------|
| `BIND` | `Node.set_meta("value", v)` + `add_child` | Writing a cell value is setting node metadata; binding a new cell is instantiating a `QuiltCell` node. Idempotence: binding the same name/value twice leaves one cell with one value. |
| `LINK` | `NodePath` references, held in an adjacency `Dictionary` | Edges live in one place (`_links: Dictionary` → CSR-shaped `{from: {to: true}}`), *not* scattered as scene-tree parentage. Transitivity is walkable without touching the tree. |
| `EFFECT` | a call on the cell node (`apply_effect(fn_name, args)`) | Effect functions are registered in a dispatch table (GDScript `Callable`s). Stubbed in v0.1 — the law (associativity) is testable; the library of effects is the next milestone. |
| `VIEW` | `get_meta("value")` across a name list | A pure gather — the scaffold's `view()` returns values and touches nothing. Godot's inspector can even be the VIEW UI when the editor is attached. |
| `TICK` | `_process(delta)` on the engine root | The dirty-set wavefront: cells whose inputs changed recompute in topological order, once per frame. The frame *is* the tick — no second scheduler. |
| `FORGET` | `queue_free()` + link-grant teardown | Bindings erased, links removed, the node leaves the tree inertly. Stubbed to the required *shape* in v0.1; full grant-tracking lands with the MHS interlocks. |

### 3.2 Cell-graph JSON loading

The sheet is the same shape the rest of the ecosystem speaks — flat cells,
`id`/`kind`/`value` or `formula`, links derivable from `reads` (explicit,
auditable — we don't parse expressions to guess edges in a scaffold):

```json
{
  "name": "bay-controller",
  "tick_hz_hint": 60,
  "cells": [
    { "id": "bay.pump.power",   "kind": "value",   "value": 0.0 },
    { "id": "bay.pump.threshold","kind": "value",  "value": 0.7 },
    { "id": "bay.pump.running", "kind": "formula", "reads": ["bay.pump.power", "bay.pump.threshold"],
      "expr": "power >= threshold" },
    { "id": "bay.alarm",        "kind": "formula", "reads": ["bay.pump.running"],
      "expr": "not running" },
    { "id": "bay.led",          "kind": "io",      "value": 0 }
  ]
}
```

Load path: `FileAccess.get_file_as_string` → `JSON.parse_string` → for each
cell, `BIND` a `QuiltCell` node; for each `reads` entry, `LINK` an edge.
Total time is O(cells + edges). A 10k-cell sheet loads in well under a frame
on anything Godot runs on. (Target verified: the scaffold ticks 5 cells;
scale testing is a conformance TODO, stated as such.)

### 3.3 Rendering / routing tie-in

The scene (`scenes/quilt_viewer.tscn`) renders the loaded graph natively:
each cell is a `Label`-carrying node drawn by a simple force-ish layout,
each link a `Line2D`. During `_process`, values update on screen as the
wavefront recomputes — the visualizer *is* the engine, not a mirror of it.
Routing (who may read/write which cell) is a cell contract checked at
BIND/VIEW time in the scaffold's `contract` dictionary — the same shape
[quilt-rust] routers use, minus the caller-awareness until it's needed.

### 3.4 The MHS seam in Godot

[MHS (Model Hardware Standard)][quilt-mhs] is the announced standard for AI
agents operating physical devices. The seam is one GDScript interface:

```gdscript
# MhsTransport — implement over serial, WebSocket, or the real SDK when it lands
func discover(kind_hint: String) -> Array: ...
func read(device: String, channel: String) -> Variant: ...
func write(device: String, channel: String, value: Variant) -> Error: ...
func abort(device: String) -> Error: ...
```

Engine sim → hardware: a formula cell whose `reads` include an MHS-bound
sensor cell recomputes when `read()` polls in; an `io` cell `write()`s on
EFFECT. The in-engine pump/bay demo can drive a real thermal bath the day a
transport exists — same sheet, same tick, one adapter swap. All guesses
about the real spec stay inside the transport, exactly as [quilt-mhs]
isolates them (A-tagged types, conformance suite, mock first).

### 3.5 What the scaffold proves (and doesn't)

**Proves:** the frame loop ticks a JSON-loaded cell graph; BIND/LINK/VIEW/TICK
are real and law-shaped; a sheet the editor never saw becomes a live scene.
**Doesn't yet:** EFFECT dispatch table is a stub (law-testable, not useful);
FORGET frees nodes but doesn't track grants; no conformance harness in CI
(no Godot headless in CI yet — see README roadmap).

---

## 4. Unity — ECS is a cell graph in disguise

**Claim:** Unity's GameObject/MonoBehaviour world maps exactly like Godot's
(cells as `MonoBehaviour`s on child GameObjects, `Update()` as TICK), and
Unity's DOTS/ECS stack is *the same graph, re-expressed*: cells become
components (pure data), LINKs become entity references / blob arrays, EFFECT
becomes a parallel `IJobEntity`, TICK becomes the `SimulationSystemGroup`
fixed-step. The cell graph was there all along; ECS just flattened it.

### 4.1 Opcode table (both flavors)

| Opcode | MonoBehaviour flavor | DOTS/ECS flavor |
|--------|---------------------|-----------------|
| `BIND` | `ScriptableObject` cell def → instantiate + `Init()` on a child GO | `EntityManager.CreateEntity` + `SetComponentData` (scatter by archetype) |
| `LINK` | a `ScriptableObject` graph asset (the sheet) baked into an adjacency `NativeArray` | entity refs / `BlobArray<int>` CSR adjacency — literally the quilt LINK shape |
| `EFFECT` | method call on the behaviour | `IJobEntity` / `IJobChunk`, scheduled parallel by default |
| `VIEW` | read fields / `TryGetValue` on a registry | `GetComponentLookup<T>` gather |
| `TICK` | `Update()` (variable) or `FixedUpdate()` (deterministic — prefer for conformance) | `SimulationSystemGroup` fixed tick; ordering = topological via system ordering constraints |
| `FORGET` | `Destroy(gameObject)` + unsubscribe | `DestroyEntity` (archetype teardown is structural; grants still need bookkeeping) |

The sheet asset story: `ScriptableObject` is Unity's native "JSON-ish typed
data" — write an importer that turns the same cell-graph JSON from §3.2 into
a `.asset`, or skip the editor entirely and parse at runtime (the conformance
requirement C2 forces the runtime path anyway).

### 4.2 MHS seam + rendering

MHS: same four-method transport interface as Godot, implemented as a C#
interface + `ScriptableObject`-configured transport (WebSocket first, real
SDK later). Rendering/routing: a single `DebugDraw`-style renderer (Gizmos
for dev, a UI Toolkit overlay for play mode) plus one GraphView window in
the editor for inspecting the live cell graph — Unity's GraphView is the
best cell-graph inspector of the three engines for free. Conformance notes:
Unity's variable-rate `Update` violates TICK monotonicity testing — use
`FixedUpdate` / fixed-step simulation for the port.

### 4.3 What Unity adds

Jobs/Burst make EFFECT genuinely parallel (BIND/EFFECT/VIEW map to the
burst-compiler's favorite shapes: scatter/map/gather), and DOTS makes the
SIMD claim of §1 literal. Port milestone: run the Godot demo sheet unchanged
in a Unity scene at deterministic fixed tick, 10k+ cells, law tests green.

---

## 5. Unreal — UObjects, Actors, Tick, UPROPERTY

**Claim:** the mapping survives Unreal, but nothing is free. Cells are
`UObject`-derived `UQuiltCell` (data + contract) living under one `AQuiltEngine`
`Actor`; `Tick(DeltaTime)` is the wavefront driver; `UPROPERTY` reflection is
the bridge that lets the editor inspect cell state without a custom
Visualizer (a `Details` panel shows `UPROPERTY` fields of the selected cell
for zero work). The engine's Blueprint graph is *not* the cell graph — it's
the wrong layer; the port ignores it deliberately.

### 5.1 Opcode table

| Opcode | Unreal construct | Notes |
|--------|------------------|-------|
| `BIND` | `NewObject<UQuiltCell>()` registered with the engine actor; value via `UPROPERTY` field | Idempotence enforced by the registry (`Add` on existing id = value overwrite, one object). |
| `LINK` | `TArray<FQuiltEdge>` on the engine actor (CSR-sorted at load) | Edges as plain data — never as editor-created pins/actors. The graph must load from JSON cold. |
| `EFFECT` | registered `TFunction` dispatch (C++/Blueprint-implementable) | Stubbed in spec; the dispatch shape matches Godot's so sheets port byte-for-byte. |
| `VIEW` | `UQuiltCell::GetValue(id)` registry gather | Pure by convention; enforce with a const registry view. |
| `TICK` | `AQuiltEngine::Tick(DeltaTime)` (PrimaryActorTick, default tick group) | Wavefront in topological order once per frame. Fixed-tick conformance: set tick interval or use `SetTickFunctionEnable` with a fixed accumulator. |
| `FORGET` | `DestroyComponent`/`MarkAsGarbage` + link grant teardown | GC timing is the trap: FORGET must be *synchronous* at the quilt level (registry entries die now; UObject reclamation can lag) or forget-completeness is untestable. |

JSON loading: the scaffold spec uses RapidJSON (engine-bundled) —
`FString::ReadFileToString` → parse → BIND/LINK loop, same as §3.2. Cells
deserialize into `UPROPERTY` fields so the editor's Details panel becomes a
free VIEW UI on any selected cell.

### 5.2 MHS seam + rendering

MHS: the four-method `IQuiltMhsTransport` C++ interface, first impl over
HTTP (Europa's `FHttpModule`) — same isolation rule as everywhere else.
Rendering/routing: a `UQuiltGraphRendererComponent` using `ULineBatchComponent`
for links + `UTextRenderComponent` per cell is enough for the C7 eyeball
test at 100+ cells; graduated: one Slate/UMG overlay drawing the graph from
the registry each frame. The visualizer reads the registry (VIEW only), so
rendering can never perturb the tick — purity where it counts.

### 5.3 Honest difficulty

Unreal is the far end of the ladder for a reason: build system friction,
editor-centric culture (the JSON-must-load-cold requirement fights the
`.uasset` default every day), and GC semantics that require the synchronous-
registry discipline above. None of it is hard; all of it is *work*. Port
milestone: same demo sheet, same law tests, one frame-graph capture showing
the wavefront in Unreal Insights.

---

## 6. The porting ladder — Godot → Unity → Unreal

The ladder is ordered by mapping distance, not by engine quality:

```
   cell graph (JSON)  ———— one format, three runtimes ————+
                                                          |
   1. GODOT  (reference)   scene tree ≈ cell graph        |  ✓ scaffold in this repo
        TICK = _process        BIND = node+meta           |    laws testable, MHS seam typed
        |                                                 |
   2. UNITY  (two flavors)  GO/MonoBehaviour ≈ Godot path |  ✗ specified, not scaffolded
        DOTS/ECS = the flattened cell graph               |    jobs make EFFECT parallel
        |                                                 |
   3. UNREAL (far end)      UObjects under one Actor      |  ✗ specified, not scaffolded
        Tick = wavefront, UPROPERTY = free VIEW panel     |    registry discipline for FORGET
```

Rules of the ladder:

1. **Sheets are engine-neutral.** The JSON of §3.2 is the contract. Any
   engine-specific asset (`.tscn` variants, `ScriptableObject` imports,
   `.uasset` bakes) is a *cache* of the JSON, never a source of truth.
2. **Port the laws, not the vibes.** Each rung ships the same C1–C7
   conformance checks (§2). A port that can't run the laws test isn't a
   rung; it's a decoration.
3. **The MHS seam is one interface per engine**, mock-first, exactly as
   [quilt-mhs] does it — so the real SDK lands as a transport swap, never
   an engine rewrite.
4. **Each rung teaches the next.** Godot proves the tick and the laws;
   Unity proves parallel EFFECT and scale; Unreal proves the model survives
   the most opinionated engine. A finding on any rung (e.g., fixed-tick
   for TICK monotonicity) becomes a ladder-wide requirement.

---

## 7. References

- [quilt-cellular-arch](https://github.com/SuperInstance/quilt-cellular-arch) — the 5+1 opcodes, the laws, the framework
- [quilt-rust](https://github.com/SuperInstance/quilt-rust) — the reference engine (single binary, sync core)
- [quilt-mhs](https://github.com/SuperInstance/quilt-mhs) — quilt × MHS: controller adapter, device profile, conformance suite
- [quilt-esp32](https://github.com/SuperInstance/quilt-esp32) — `qm_opcodes` on metal (ESP32-S3, verified 2026-08-26)
- [quilt](https://github.com/SuperInstance/quilt) — the TypeScript canonical runtime

*Everything in this document describes running code where it says so, and
specified intent where it doesn't. The distinction is marked every time.*
