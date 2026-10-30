# Scale Punch

Elastic scale pop — briefly scales a target from its baseline to `punch_scale` and back with an elastic return. Works on `Node2D`, `Node3D`, and `Control`. Baseline scale is cached per target on first play; new punches on the same target **override** the running one (last-starts-wins).

**Class:** `FeedbackScalePunchLite` · **Demo:** `samples/scenes/sparklelite_05_scale_punch.tscn`

---

## Properties

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `target` | `NodePath` | `NodePath()` | Path to the node to punch. **Empty means the punch is applied to the owning `FeedbackPlayerLite` itself.** |
| `punch_scale` | `Vector3` | `(1.2, 1.2, 1.2)` | Peak scale multiplier over baseline. `(1.2, 1.2, 1.2)` = 20 % bigger at peak. For `Control`/`Node2D` only `.x`/`.y` are used. |
| `elasticity` | `float` | `0.4` | Overshoot on the return. `0` = no wobble; `1` = heavy bounce. |
| `use_unscaled_time` | `bool` | `true` | Keep `true` so the punch reads during hit pauses. |

### Inherited

- `duration_ms` — total length including the return. `120–220 ms` covers most cases.
- `label`, `enabled`, `delay_ms`, `intensity_multiplier`.

---

## Timing curve

The punch has a fixed shape split at `t = 0.4`:

- **`0 → 0.4`** (rise): smoothstep from baseline to peak.
- **`0.4 → 1.0`** (return): linear return from peak to baseline, plus `sin(3π·fall) · (1 − fall) · elasticity` overshoot.

`intensity_multiplier` lerps `punch_scale` toward `Vector3.ONE` — intensity `0` = no visible punch, intensity `1` = full authored peak.

---

## Stacking (same target)

A new punch on a target with an active punch **cancels and replaces** the running one — you don't get layered wobble. The replacement starts fresh from baseline, not from the current (mid-punch) scale. For an actor being hit twice quickly, the second punch reads as one clean pop, not two fighting animations.

The first punch ever to touch a target caches its baseline. Subsequent punches read the cache. If the target changes (rare — instance id reuse), the cache is refreshed.

---

## Recipes

### UI button press

```gdscript
punch.target = NodePath("BuyButton")
punch.duration_ms = 150
punch.punch_scale = Vector3(1.1, 0.95, 1.0)   # slight squash
punch.elasticity = 0.5
```

### Enemy hit reaction

```gdscript
punch.duration_ms = 180
punch.punch_scale = Vector3(1.25, 1.25, 1.25)
punch.elasticity = 0.6
```

### Coin pickup pop

```gdscript
punch.target = NodePath("CoinIcon")
punch.duration_ms = 220
punch.punch_scale = Vector3(1.4, 1.4, 1.4)
punch.elasticity = 0.8    # juicy bounce
```

---

## Gotchas

- **Target resolution falls back to the current scene.** `target` is resolved first relative to the `FeedbackPlayerLite`, then relative to `current_scene`. An empty `NodePath` punches the player itself, which is usually what you want when the player sits on the node you're animating.
- **Only `Node2D`, `Node3D`, and `Control` are supported.** Other node types silently no-op.
- **Baselines are static across instances.** The baseline cache is a `static Dictionary` keyed by `instance_id`. If your scene replaces a node under the same instance id (shouldn't happen under normal flow), the cache detects and refreshes it.
- **`stop()` restores the baseline.** Cancelling mid-punch snaps the target back to its original scale — there's no "freeze at current" option.
- **Interrupting from a very deformed state is fine.** The replacement punch reads baseline from the cache, not the live transform, so chained hits don't accumulate scale drift.
