# Call

Bridge feedback — calls a method **or** emits a signal on a target node at its place in the timeline. Lets designers hook gameplay code into a feel sequence without scripting around the `FeedbackPlayerLite`.

**Class:** `FeedbackCallLite` · **Demo:** `samples/scenes/sparklelite_06_call.tscn`

---

## Properties

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `mode` | `CallMode` | `CALL_METHOD` | `CALL_METHOD` invokes a method; `EMIT_SIGNAL` emits a signal. |
| `target` | `NodePath` | `NodePath()` | Destination node. **Empty means the call is dispatched on the owning `FeedbackPlayerLite`** — useful for driving the player itself from within its own stack. |
| `method_or_signal` | `StringName` | `&""` | Method or signal name (depending on `mode`). |
| `arguments` | `Array` | `[]` | Positional arguments. For `EMIT_SIGNAL`, these become the signal's arguments. |

### Inherited

- `delay_ms` — when inside the timeline the call fires.
- `label`, `enabled`, `intensity_multiplier`.
- `duration_ms` is **ignored** — the call is instantaneous.

> `intensity_multiplier` is **not** passed through. If you want intensity-aware behaviour, read `intensity_multiplier` from the feedback in your called method via a direct reference — or (simpler) drive intensity via the arguments you pass.

---

## When to use Call

- **Spawning a particle** at the right moment of a juicy sequence:
  ```gdscript
  call.method_or_signal = &"emit"
  call.target = NodePath("../ImpactParticles")
  ```
- **Telling the game logic a visual moment happened** (score popup, combo increment):
  ```gdscript
  call.mode = FeedbackCallLite.CallMode.EMIT_SIGNAL
  call.method_or_signal = &"feedback_peak"
  ```
- **Chaining two players without scripting:** give player A a Call feedback with `method_or_signal = &"play"` and `target = NodePath("../PlayerB")`.

---

## Recipes

### Spawn an impact at hit-stop resume

```gdscript
# Assumes a HitPause at delay 0 (80 ms), Call fires right as time resumes.
call.mode = FeedbackCallLite.CallMode.CALL_METHOD
call.target = NodePath("../ImpactParticles")
call.method_or_signal = &"restart"
call.delay_ms = 80
call.arguments = []
```

### Emit a gameplay signal mid-sequence

```gdscript
call.mode = FeedbackCallLite.CallMode.EMIT_SIGNAL
call.target = NodePath()                      # emit on the player itself
call.method_or_signal = &"juicy_hit_peak"
call.delay_ms = 120
# In your gameplay code: player.juicy_hit_peak.connect(_on_peak)
```

### Chain a second player

```gdscript
call.mode = FeedbackCallLite.CallMode.CALL_METHOD
call.target = NodePath("../SecondaryPlayer")
call.method_or_signal = &"play"
call.arguments = [1.0]                        # intensity
call.delay_ms = 200
```

---

## Gotchas

- **Skipped during editor preview.** The feedback's `get_preview_diagnostic` reports this: calls and signals are never fired when you hit the preview button, only at runtime. Prevents side effects from accidentally firing while you're authoring.
- **Missing method/signal produces a one-shot warning.** If `method_or_signal` doesn't exist on the resolved target, a `push_warning` fires **once per (instance id, name)** combination — repeat calls stay silent. Check the editor output if a Call seems to do nothing.
- **Empty `method_or_signal` silently no-ops** (with a one-shot warning).
- **Target resolution falls back to the current scene.** The path is resolved relative to the `FeedbackPlayerLite` first, then relative to `current_scene`. Absolute paths work via `current_scene` lookup.
- **`arguments` must match the method/signal signature.** A mismatch raises a runtime error from Godot, not from this feedback.
