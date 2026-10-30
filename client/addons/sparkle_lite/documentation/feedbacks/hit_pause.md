# Hit Pause

Briefly drops `Engine.time_scale` for hit-stop impact. Multiple overlapping hit pauses compose via a lowest-wins coordinator (the pause that slows the most wins while it's active). Hard-capped at **500 ms** regardless of the authored value — pauses longer than half a second feel like bugs.

**Class:** `FeedbackHitPauseLite` · **Demo:** `samples/scenes/sparklelite_02_hit_pause.tscn`

---

## Properties

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `time_scale_during_pause` | `float` | `0.05` | Engine time scale applied while the pause is active. 0.05 is a heavy hit-stop; 0.3 is a light one; 1.0 disables the effect. |
| `affect_audio` | `bool` | `false` | When true, `AudioServer.playback_speed_scale` is also dropped. Leave false if you want audio to continue at normal speed during the pause. |

### Inherited

- `duration_ms` — pause length. **Clamped to 500 ms.**
- `label`, `enabled`, `delay_ms`, `intensity_multiplier`.

---

## Stacking

Multiple hit pauses fire simultaneously correctly. The coordinator keeps the **lowest** active `time_scale_during_pause` until the last pause ends, then restores the original time scale. They do not stack multiplicatively.

Example:

- Pause A: 0.1 × for 120 ms
- Pause B: 0.05 × for 60 ms, starts 30 ms into A

Timeline:
- t = 0 → 30ms: time scale = 0.1
- t = 30 → 90ms: time scale = 0.05 (B wins)
- t = 90 → 120ms: time scale = 0.1 (A wins again, B ended)
- t = 120ms: restore

---

## What actually needs to be visible

Hit pause is **invisible** without something on-screen moving at scaled time. If everything in your scene uses `use_unscaled_time`, nothing appears to pause. Make sure at least the gameplay (enemies, projectiles, etc.) runs on scaled time.

The demo uses a spinning cube ring that rotates on scaled delta for exactly this reason.

---

## Recipes

### Combat hit-stop

```gdscript
pause.duration_ms = 80
pause.time_scale_during_pause = 0.05
```

Snappy and impactful. Pair with a camera shake (`use_unscaled_time = true` so the shake keeps animating) and you've got a satisfying landing.

### Heavy boss hit

```gdscript
pause.duration_ms = 180
pause.time_scale_during_pause = 0.02
pause.affect_audio = true
```

Near-freeze that includes audio — reserve for rare big hits.

### Chain combo flair

```gdscript
pause.duration_ms = 40
pause.time_scale_during_pause = 0.3
```

Light pause you can fire on every combo hit without the game feeling stuttery.

---

## Gotchas

- **500 ms cap.** Higher values are clamped and push a warning. If you need a "freeze" longer than half a second, use `get_tree().paused = true` / `false` with a timer instead — that's a different concept.
- **Feedbacks that need to keep running during the pause must set `use_unscaled_time = true`** (Camera Shake, Camera Shake 2D, Scale Punch, Screen Flash 2D all do by default).
- **Hit pause runs in the editor preview too** — the editor briefly slows down when you click the preview button. This is intentional; it's the only way to feel-test the duration without entering play mode.
