# Camera Shake 2D

2D sibling of [Camera Shake](camera_shake.md). Targets `Camera2D` instead of `Camera3D`, uses `Vector2` position amplitude in **pixels** and a single rotation axis in **degrees**. Same layered-noise engine, same additive stacking, same distance-falloff system — just in pixel space.

**Class:** `FeedbackCameraShake2DLite` · **Demo:** `samples/scenes/sparklelite_09_camera_shake_2d.tscn`

---

## Properties

### Positional shake

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `shake_position_x` | `bool` | `true` | Enables horizontal shake. |
| `shake_position_y` | `bool` | `true` | Enables vertical shake. |
| `position_amplitude` | `Vector2` | `(12, 12)` | Peak offset in **pixels**. |
| `position_randomness` | `Vector2` | `(0.5, 0.5)` | Smooth (0) vs chaotic (1) noise blend per-axis. |
| `position_curve` | `Curve` | `null` | Envelope over `[0, 1]`. |

### Rotational shake

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `shake_rotation` | `bool` | `true` | Enables camera roll. |
| `rotation_amplitude` | `float` | `2.0` | Peak rotation in **degrees**. |
| `rotation_randomness` | `float` | `0.5` | Smooth/chaotic blend. |
| `rotation_curve` | `Curve` | `null` | Envelope. |

### Camera target

Same four modes as the 3D variant, targeting `Camera2D`:

| Mode | Behaviour |
|------|-----------|
| `AUTO` | `viewport.get_camera_2d()` then scene walk for `.enabled` Camera2D. |
| `ACTIVE` | Alias for AUTO. |
| `BY_PATH` | Camera at `camera_path`. |
| `BY_GROUP` | Every Camera2D in `camera_group_name`. |

### Distance falloff

Identical shape to the 3D version but distances are **pixels**:

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `use_distance_falloff` | `bool` | `false` | |
| `shake_source_path` | `NodePath` | `NodePath()` | Source `Node2D`. |
| `falloff_start_distance` | `float` | `200.0` | Full intensity ≤ this, in pixels. |
| `falloff_end_distance` | `float` | `800.0` | Zero intensity ≥ this. |
| `falloff_curve` | `Curve` | `null` | Optional. |

### Timing

`use_unscaled_time` (default `true`) — same semantics.

### Inherited

`label`, `enabled`, `delay_ms`, `duration_ms`, `intensity_multiplier`.

---

## Stacking

Same as 3D: additive composition, combined output capped at 2× the strongest contributor, baseline `offset` and `rotation` captured on first register and restored on last unregister.

---

## Recipes

### Candy-crunch pop

```gdscript
shake.duration_ms = 420
shake.position_amplitude = Vector2(14, 14)
shake.rotation_amplitude = 2.5
shake.position_randomness = Vector2(0.55, 0.55)
```

### Heavy boss-hit screen jolt

```gdscript
shake.duration_ms = 650
shake.position_amplitude = Vector2(36, 36)
shake.rotation_amplitude = 6
shake.position_randomness = Vector2(0.75, 0.75)
```

### Ambient environmental tremor

```gdscript
shake.duration_ms = 2400
shake.position_amplitude = Vector2(3, 3)
shake.shake_rotation = false
shake.position_randomness = Vector2(0.1, 0.1)  # very smooth
```

---

## Gotchas

- **`Camera2D.enabled` is what we watch for**, not `.current` (which only exists on `Camera3D`). If your `Camera2D` isn't `enabled`, the scene-walk fallback skips it.
- **Pixels, not world units.** Set `position_amplitude` based on your game's pixel density — 14 pixels feels loud at 1080p and jarring at 240p.
- **Editor preview works even if `make_current()` hasn't been called** — the fallback scans the tree.
