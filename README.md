# quilt-engine-ports — the 5+1 opcodes in Godot, Unity, Unreal

> **A quilt cell graph walks into three game engines.** Cells as nodes, TICK
> as the frame, sheets as JSON — and one MHS seam so the same scene can drive
> real hardware. Godot scaffold runs (text-only, editor-optional); Unity and
> Unreal are specified to the conformance check.

<p align="center">
  <img src="assets/banner.jpg" alt="A glowing hexagonal patchwork quilt with threads leading to three miniature worlds" width="860">
</p>

The quilt engine reduces everything to six opcodes — `BIND / LINK / EFFECT /
VIEW / TICK` + `FORGET` — with five proved laws and a completeness guarantee
([quilt-cellular-arch]). This repo takes those opcodes to the three dominant
game engines, on the thesis that a game engine is already a reactive runtime:
the scene tree is a cell graph, the frame loop is TICK, the editor is a VIEW
UI that ships with the engine.

**What's here, honestly:**

- **[docs/DESIGN.md](docs/DESIGN.md)** — the full opcode→engine mapping for
  all three engines: opcode tables, cell-graph JSON loading, the MHS seam,
  rendering/routing tie-ins, and the porting ladder
  (Godot → Unity → Unreal). Every claim is marked *runs* or *specified*.
- **Godot reference scaffold** (`godot/`) — `project.godot`, one scene, one
  GDScript engine (~330 lines): loads a cell-graph JSON at runtime, builds
  the graph, ticks it from `_process`, and renders it live. BIND / LINK /
  VIEW / TICK are implemented; EFFECT and FORGET are law-shaped stubs (the
  dispatch table and teardown are real; the effect library and grant-tracking
  are the next milestone). **Text files only — written for Godot 4.3, not yet
  run against a Godot binary in CI.** Open it in the editor and press F5.
- **Unity and Unreal** — specified in DESIGN.md (§4, §5), including the
  claim that Unity DOTS/ECS *is* a cell graph re-expressed, and the registry
  discipline Unreal needs for FORGET. Not scaffolded. That's the ladder.

## The 30 seconds

Drop `godot/` into the Godot editor (4.3+), run the scene. What you'll see:

1. `sheets/bay_controller.json` loads cold — the editor never saw it (conformance C2).
2. Five cells bind as nodes: a mocked MHS power channel feeds `bay.pump.power`,
   formulas recompute in dependency order every frame (the wavefront).
3. When power dips below threshold, `bay.alarm` flips — on screen, in real time.
4. The MHS transport is a mock with a **real envelope** (0..1): out-of-range
   writes are *rejected*, never clamped — a clamping transport fails
   conformance, same rule as [quilt-mhs].

The same sheet is meant to run unchanged in Unity (fixed tick) and Unreal
(registry-backed Tick) — that's the porting ladder, rung by rung, each rung
gated by the same conformance checks (DESIGN.md §2, C1–C7).

## Why this is the right shape

- **Cells as game objects is the honest mapping.** Not a metaphor that
  leaks — BIND is scatter, VIEW is gather, TICK is the wavefront, and the
  engines already schedule all three sixty times a second.
- **Sheets stay engine-neutral.** The JSON is the contract; engine assets are
  caches, never the source of truth. Port the laws, not the vibes.
- **The MHS seam is one interface per engine, mock-first** — when the real
  Model Hardware Standard SDK lands ([quilt-mhs] is tracking it), it drops in
  as a transport swap, not an engine rewrite.

## Layout

```
docs/DESIGN.md         the opcode→engine mapping, all three engines + ladder
godot/project.godot    Godot 4.3 project (reference scaffold)
godot/scenes/          one scene: the live cell-graph viewer
godot/scripts/         the engine: 5+1 opcodes, laws helpers, MHS mock
godot/sheets/          the engine-agnostic cell-graph JSON format
assets/banner.jpg      banner (sdxl-turbo, see scripts/banner.sh)
scripts/banner.sh      reproducible banner generation (DeepInfra, not mmx)
```

## Status (v0.1)

| Piece | State |
|---|---|
| DESIGN.md, all three engines | ✅ written, claims marked runs/specified |
| Godot: BIND/LINK/VIEW/TICK | ✅ implemented in scaffold |
| Godot: EFFECT/FORGET | 🔶 law-shaped stubs (documented in code) |
| Godot: MHS seam | ✅ typed transport + enforcing mock (real SDK = subclass) |
| Godot: run in editor | ⚠️ written for 4.3, **not yet run** — no binary in this lane; F5 and report |
| Unity / Unreal scaffolds | ❌ specified only (that's the next rungs) |

Roadmap: run the scaffold headless in CI → law tests as a conformance suite
(`assert_laws()` is already in the script) → EFFECT library → MHS grant
tracking in FORGET → Unity rung → Unreal rung.

## Related

Part of the [quilt] ecosystem: [quilt-cellular-arch] (the opcodes and laws) ·
[quilt-rust] (reference runtime) · [quilt-mhs] (the MHS bridge) ·
[quilt-esp32] (the opcodes on metal).

Apache-2.0.

[quilt-cellular-arch]: https://github.com/SuperInstance/quilt-cellular-arch
[quilt-rust]: https://github.com/SuperInstance/quilt-rust
[quilt-mhs]: https://github.com/SuperInstance/quilt-mhs
[quilt-esp32]: https://github.com/SuperInstance/quilt-esp32
[quilt]: https://github.com/SuperInstance/quilt
