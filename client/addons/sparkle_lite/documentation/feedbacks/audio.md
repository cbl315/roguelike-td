# Audio

Plays an `AudioStream` via a pooled `AudioStreamPlayer2D` or `AudioStreamPlayer3D`. Pool nodes live under the `SparkleLitePresets` autoload so scene changes never cut audio mid-play. Three allocation strategies cover everything from bullet-spam SFX to rare one-shots.

**Class:** `FeedbackAudioLite` · **Demo:** `samples/scenes/sparklelite_04_audio.tscn`

---

## Properties

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `stream` | `AudioStream` | `null` | The clip to play. Null = silent no-op. |
| `volume_db` | `float` | `0.0` | Playback volume in decibels. |
| `pitch_min` | `float` | `0.9` | Lower bound of randomised pitch scale. |
| `pitch_max` | `float` | `1.1` | Upper bound. Same value on both disables randomisation. |
| `bus` | `String` | `"Master"` | Audio bus name. Invalid bus falls back to `Master` with a warning. |
| `use_3d` | `bool` | `false` | When true, uses `AudioStreamPlayer3D` positioned at the owning player's global origin. When false, uses `AudioStreamPlayer2D`. |
| `loading_mode` | `LoadingMode` | `POOL` | Allocation strategy. See below. |
| `max_simultaneous` | `int` | `4` | **POOL only.** Hard cap on concurrent playbacks. |
| `pool_size` | `int` | `4` | **POOL only.** Number of players pre-warmed at `FeedbackPlayerLite` ready time. |

### Inherited

`label`, `enabled`, `delay_ms`, `duration_ms` *(unused — the clip plays through)*, `intensity_multiplier`.

> `intensity_multiplier` scales audio **linearly** (converted to dB and added to `volume_db`). An intensity of `0.5` is ~−6 dB quieter than intensity `1.0`.

---

## Loading modes

### `POOL` (default)

Pre-allocates `pool_size` players up-front. When a play is requested:

1. Reuse the first idle player in the pool.
2. If none are idle and `_active < max_simultaneous`, grow the pool by one.
3. If at the cap, **evict the oldest active playback** and restart on that player.

Best for frequent SFX (gunshots, footsteps). The eviction prevents runaway polyphony when effects pile up.

### `CACHE`

Grows on demand, never evicts. Pool expands player-by-player as concurrent plays increase, up to a safety cap of **64** players. Once the cap is reached, further plays are silently dropped.

Best for variable-intensity scenes where you don't know the max polyphony up-front but you'd rather drop a sound than interrupt an existing one.

### `ONE_TIME`

Creates a fresh `AudioStreamPlayer2D/3D` per play, frees it when `finished` fires. No reuse.

Best for **rare one-shots**: boss intro stings, level-start fanfares. Keeps the pool empty between plays.

---

## Recipes

### Bullet-spam SFX

```gdscript
audio.stream = preload("res://sfx/gunshot.ogg")
audio.loading_mode = FeedbackAudioLite.LoadingMode.POOL
audio.pool_size = 6
audio.max_simultaneous = 8
audio.pitch_min = 0.92
audio.pitch_max = 1.08
audio.volume_db = -3.0
```

### Positional impact (3D)

```gdscript
audio.stream = preload("res://sfx/impact.ogg")
audio.use_3d = true
audio.loading_mode = FeedbackAudioLite.LoadingMode.CACHE
audio.pitch_min = 0.85
audio.pitch_max = 1.15
audio.bus = "SFX"
```

### Boss sting (one-shot, no interruptions)

```gdscript
audio.stream = preload("res://sfx/boss_roar.ogg")
audio.loading_mode = FeedbackAudioLite.LoadingMode.ONE_TIME
audio.pitch_min = 1.0
audio.pitch_max = 1.0
audio.volume_db = 2.0
audio.bus = "Music"
```

---

## Gotchas

- **`use_3d` positioning is a snapshot.** The 3D player's `global_position` is set to the owning `FeedbackPlayerLite`'s position at the moment `play()` is called. The sound does **not** follow a moving emitter — if you need that, parent a dedicated `AudioStreamPlayer3D` to the emitter and drive it with a `FeedbackCallLite` instead.
- **`intensity` becomes `volume`.** `intensity_multiplier * per_call_intensity` is converted to dB and added on top of `volume_db`. Calling `player.play(0.5)` is ~−6 dB quieter than `player.play(1.0)`. Set `intensity_multiplier = 1.0` if you don't want this coupling.
- **Invalid bus names fall back to Master with a warning.** The warning fires once per feedback instance on first play.
- **POOL's eviction is audible.** When polyphony exceeds `max_simultaneous`, the oldest sound stops abruptly. If you hear cut-offs, raise the cap or switch to `CACHE`.
- **`ONE_TIME` creates garbage.** Every play allocates a node. Fine for rare stings; a bad fit for a machine gun.
