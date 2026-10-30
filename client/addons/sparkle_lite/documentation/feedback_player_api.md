# FeedbackPlayerLite API Reference

`FeedbackPlayerLite` is the orchestrator node. It owns an ordered list of `FeedbackBaseLite` resources and fires them in parallel when `play()` is called. Every feedback honours its own `delay_ms` from the `play()` moment — not from the previous feedback — so stacks compose cleanly.

`extends Node`

---

## Exported properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `feedbacks` | `Array[FeedbackBaseLite]` | `[]` | Ordered list of feedbacks this player fires. Authored via the custom inspector or appended in code via `add_feedback`. |
| `auto_play_on_ready` | `bool` | `false` | When true, `play()` is called from `_ready()` at runtime (not in the editor). |
| `loop` | `bool` | `false` | When true, the sequence restarts automatically from `loop_from_index` after `loop_delay_ms`. |
| `loop_delay_ms` | `float` | `0.0` | Pause between loop iterations, in milliseconds. |
| `loop_from_index` | `int` | `0` | Index into `feedbacks` the loop restarts from. Useful when you want an intro feedback to play once. |
| `default_intensity` | `float` | `1.0` | Global multiplier applied on top of every feedback's own `intensity_multiplier` and the per-call intensity argument. |
| `minimum_interval_ms` | `float` | `0.0` | Debounce window. Calls to `play()` that arrive inside this window are silently ignored. |

---

## Methods

### `play(intensity: float = 1.0) -> void`

Fires every enabled feedback in parallel, each respecting its own `delay_ms`. Emits `started` immediately, `feedback_started(i)` as each feedback begins, `feedback_completed(i)` as each finishes, and `completed` once all are done.

`intensity` is multiplied with `default_intensity` and passed to each feedback's `_play(combined, self)`. Individual feedbacks then scale it by their own `intensity_multiplier`.

### `stop() -> void`

Cancels every active sequence instance. Each feedback's `_stop()` is called so state is restored (camera transforms, time scales, scale baselines, ...). No further signals fire for cancelled instances.

### `play_feedback_at_index(index: int, intensity: float = 1.0) -> void`

Fires a single feedback by index — bypasses the rest of the stack. Handy for firing one specific row programmatically, or for testing.

### `add_feedback(feedback: FeedbackBaseLite) -> FeedbackBaseLite`

Appends `feedback` to the list and returns it. Ignored if `feedback` is null.

### `clear_feedbacks() -> void`

Empties the feedbacks list.

### `apply_preset(preset: FeedbackPresetLite) -> void`

Replaces `feedbacks` with a deep copy of `preset.feedbacks`. The source preset is not mutated — safe to share one preset across many players.

### `get_total_duration() -> float`

Returns the time in seconds from a `play()` call until the last enabled feedback completes. Takes each feedback's `delay_ms + duration_ms` and picks the max.

### `is_playing() -> bool`

Returns true if at least one sequence instance is currently running.

---

## Signals

| Signal | Args | When |
|--------|------|------|
| `started` | — | At the start of every `play()` call. |
| `completed` | — | When every feedback in the instance has finished. |
| `feedback_started` | `index: int` | As each feedback begins firing (after its `delay_ms`). |
| `feedback_completed` | `index: int` | As each feedback ends (after its `duration_ms`). |

`play()` calls can overlap. Each call creates an independent "sequence instance" that emits its own `started` / `completed` pair. Per-feedback signals fire once per instance.

---

## Lifecycle notes

- `_ready()` calls `pre_warm(tree)` on every feedback so pool-owning feedbacks (Audio, Screen Flash) can allocate persistent nodes.
- On `NOTIFICATION_EXIT_TREE` the player calls `stop()` and `release_pool(tree)` on every feedback, freeing pooled audio players and restoring any modified engine state.
- `NOTIFICATION_PREDELETE` also calls `stop()` as a safety net.

---

## Minimum setup (no inspector)

```gdscript
var player := FeedbackPlayerLite.new()
add_child(player)

var shake := FeedbackCameraShakeLite.new()
shake.duration_ms = 300
player.add_feedback(shake)

player.play()
```

See **[Runtime API](runtime_api.md)** for full code patterns.
