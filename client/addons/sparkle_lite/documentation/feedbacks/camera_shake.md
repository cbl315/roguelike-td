# Camera Shake (3D)

Layered-noise positional + rotational shake on one or more `Camera3D` nodes. Two frequencies of Simplex noise are blended per-axis (smooth coherent + high-frequency chaotic), then envelope-scaled by an optional `Curve`, then summed across overlapping shakes.

**Class:** `FeedbackCameraShakeLite` · **Demo:** `samples/scenes/sparklelite_01_camera_shake.tscn`

---

## Properties

### Positional shake

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `shake_position_x` | `bool` | `true` | Enables X-axis position shake. |
| `shake_position_y` | `bool` | `true` | Enables Y-axis position shake. |
| `shake_position_z` | `bool` | `false` | Enables Z-axis (into-screen) position shake. |
| `position_amplitude` | `Vector3` | `(0.3, 0.3, 0.0)` | Peak offset in metres. |
| `position_randomness` | `Vector3` | `(0.5, 0.5, 0.0)` | Per-axis blend between smooth noise (0) and high-frequency chaotic noise (1). |
| `position_curve` | `Curve` | `null` | Envelope over `[0, 1]`. Null uses a built-in `1 − t` linear fade. |

### Rotational shake

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `shake_rotation_x` | `bool` | `false` | Enables pitch shake. |
| `shake_rotation_y` | `bool` | `false` | Enables yaw shake. |
| `shake_rotation_z` | `bool` | `true` | Enables roll shake — the most useful axis for shoot feedback. |
| `rotation_amplitude` | `Vector3` | `(0, 0, 2)` | Peak rotation, **in degrees**. |
| `rotation_randomness` | `Vector3` | `(0.5, 0.5, 0.5)` | Same smooth/chaotic blend as positional. |
| `rotation_curve` | `Curve` | `null` | Envelope over `[0, 1]`. |

### Camera target

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `camera_selection_mode` | `enum` | `AUTO` | How to locate the camera(s). See below. |
| `camera_path` | `NodePath` | `NodePath()` | Only used in `BY_PATH` mode. Relative to the player or to the current scene. |
| `camera_group_name` | `String` | `""` | Only used in `BY_GROUP` mode. Shakes every `Camera3D` in this group. |

**Camera selection modes:**
- `AUTO` — uses `viewport.get_camera_3d()`; falls back to scene tree walk.
- `ACTIVE` — same as AUTO in practice (looks for the currently active camera).
- `BY_PATH` — targets the camera at `camera_path`.
- `BY_GROUP` — shakes every `Camera3D` in `camera_group_name`. Good for split-screen.

### Distance falloff

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `use_distance_falloff` | `bool` | `false` | Scale shake by distance from a source point. |
| `shake_source_path` | `NodePath` | `NodePath()` | Source node (must be `Node3D`). Falls back to the player's position. |
| `falloff_start_distance` | `float` | `5.0` | Full intensity at or below this distance (metres). |
| `falloff_end_distance` | `float` | `20.0` | Zero intensity at or beyond this distance. Must be > start. |
| `falloff_curve` | `Curve` | `null` | Optional curve over the `[start, end]` range. Null is linear. |

### Timing

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `use_unscaled_time` | `bool` | `true` | Ignores `Engine.time_scale`. Keep true so the shake reads during hit pauses. |

### Inherited from `FeedbackBaseLite`

`label`, `enabled`, `delay_ms`, `duration_ms` (in ms — shake length), `intensity_multiplier`.

---

## Stacking

Multiple shakes on the same camera compose additively. The coordinator caps combined output at **2× the strongest single contributor**, so a pile-up of small shakes can't become a runaway jitter. Baseline (original) camera transform is captured on the first active shake and restored when the last one ends.

---

## Recipes

### Rifle shot (sharp, short)

```gdscript
shake.duration_ms = 300
shake.position_amplitude = Vector3(0.15, 0.15, 0)
shake.rotation_amplitude = Vector3(0, 0, 3)  # roll
shake.position_randomness = Vector3(0.3, 0.3, 0)  # mostly smooth
```

### Explosion (heavier, longer)

```gdscript
shake.duration_ms = 600
shake.position_amplitude = Vector3(0.5, 0.5, 0.25)
shake.shake_position_z = true
shake.rotation_amplitude = Vector3(2, 2, 4)
shake.shake_rotation_x = true
shake.shake_rotation_y = true
shake.position_randomness = Vector3(0.7, 0.7, 0.7)  # chaotic
```

### Global explosion with falloff

```gdscript
shake.use_distance_falloff = true
shake.falloff_start_distance = 3.0
shake.falloff_end_distance = 30.0
shake.shake_source_path = NodePath("../Explosion")
```

A player 30 m from the blast feels nothing; one 3 m away gets full intensity.

---

## Gotchas

- **`AUTO` requires the camera to be reachable from the player's viewport.** If the player lives inside a `SubViewport`, AUTO finds the subviewport's camera, not the main one. Use `BY_PATH` when nested.
- **Rotation axis conventions match Godot's `rotation` property** — X is pitch, Y is yaw, Z is roll.
- **Preview uses your current scene's active camera.** If no camera is set as current, preview can't run and the row shows a diagnostic.
