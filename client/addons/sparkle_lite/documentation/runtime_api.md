# Runtime API

Everything you can author in the inspector, you can build from code. This page covers the idioms for runtime-driven feedback stacks: per-weapon recipes, data-driven effects, and dynamically spawned players.

For a runnable example, see **Demo 09 — Full Runtime API** (`samples/scenes/sparklelite_08_full_api.gd`).

---

## Creating a player in code

```gdscript
var player := FeedbackPlayerLite.new()
player.name = &"RuntimePlayer"
add_child(player)
```

That's a complete, usable `FeedbackPlayerLite`. No `.tscn` required.

---

## Adding feedbacks

Every feedback is a `Resource` subclass of `FeedbackBaseLite`. Instantiate it, set properties, and append:

```gdscript
var shake := FeedbackCameraShakeLite.new()
shake.duration_ms = 350.0
shake.position_amplitude = Vector3(0.25, 0.25, 0)
shake.rotation_amplitude = Vector3(0, 0, 4)

player.add_feedback(shake)
```

`add_feedback` returns the feedback you passed in — handy for chained config or storing a reference.

---

## Swapping feedback lists

Two patterns for runtime stack changes:

### Clear + rebuild

```gdscript
player.clear_feedbacks()

var audio := FeedbackAudioLite.new()
audio.stream = preload("res://sfx/pop.ogg")
player.add_feedback(audio)

var punch := FeedbackScalePunchLite.new()
punch.target = NodePath("../Candy")
punch.punch_scale = Vector3(1.35, 1.35, 1.35)
player.add_feedback(punch)

player.play()
```

Ideal when the stack changes infrequently (weapon pickup, power-up activation).

### Preset-based swap

```gdscript
player.apply_preset(my_preset)
```

`apply_preset` deep-duplicates the preset's feedbacks onto the player, so the preset resource itself is never mutated. Use this for named reusable stacks — see **[Presets & the autoload](presets_and_autoload.md)**.

---

## Firing, stopping, inspecting

```gdscript
player.play()                # fire at authored intensity
player.play(1.8)             # 1.8x multiplier
player.play_feedback_at_index(0)  # fire just one feedback

player.stop()                # cancel every active sequence instance
player.is_playing()          # true if any instance is running
player.get_total_duration()  # seconds from play-call to last feedback end
```

---

## Signals

```gdscript
player.started.connect(func(): print("sequence began"))
player.completed.connect(func(): print("sequence ended"))
player.feedback_started.connect(func(i): print("fb ", i, " began"))
player.feedback_completed.connect(func(i): print("fb ", i, " ended"))
```

`started` / `completed` fire once per `play()` instance. If you overlap plays (call `play()` again before the first one ends), each instance fires its own pair independently.

`feedback_started(index)` / `feedback_completed(index)` fire once per feedback in the stack, with the index into `player.feedbacks`.

---

## Looping

```gdscript
player.loop = true
player.loop_delay_ms = 200
player.loop_from_index = 0
player.play()
```

The player restarts the sequence when it finishes, waiting `loop_delay_ms` between iterations. `loop_from_index` lets you loop only the tail — for example, play an intro feedback once and loop the rest forever.

---

## Debounce / rate-limit

`minimum_interval_ms` ignores `play()` calls that arrive faster than the specified window:

```gdscript
player.minimum_interval_ms = 80  # ignore plays <80 ms apart
```

Useful for rapid-fire scenarios where you don't want 60 overlapping shakes per second.

---

## Building full sequences

A practical "juicy shot" built entirely in code:

```gdscript
func build_juicy_shot() -> FeedbackPlayerLite:
    var player := FeedbackPlayerLite.new()

    var audio := FeedbackAudioLite.new()
    audio.stream = preload("res://sfx/shoot.ogg")
    audio.pitch_min = 0.92
    audio.pitch_max = 1.08
    player.add_feedback(audio)

    var shake := FeedbackCameraShakeLite.new()
    shake.duration_ms = 300
    shake.position_amplitude = Vector3(0.15, 0.15, 0)
    player.add_feedback(shake)

    var flash := FeedbackScreenFlash2DLite.new()
    flash.delay_ms = 20
    flash.flash_color = Color(1, 0.95, 0.7)
    flash.flash_intensity = 0.35
    flash.fade_out_duration_ms = 120
    player.add_feedback(flash)

    var impact_pause := FeedbackHitPauseLite.new()
    impact_pause.delay_ms = 120
    impact_pause.duration_ms = 80
    impact_pause.time_scale_during_pause = 0.06
    player.add_feedback(impact_pause)

    return player
```

Spawn one per actor, cache it, call `play()` from gameplay code.

---

## Per-weapon recipe pattern

Common use case: each weapon has its own feel, swap the full stack on weapon pickup.

```gdscript
const WEAPONS := {
    "pistol": preload("res://presets/weapon_pistol.tres"),
    "shotgun": preload("res://presets/weapon_shotgun.tres"),
    "rocket": preload("res://presets/weapon_rocket.tres"),
}

func equip_weapon(name: String) -> void:
    var preset: FeedbackPresetLite = WEAPONS[name]
    _feedback_player.apply_preset(preset)
```

Now `_feedback_player.play()` from your fire code plays whatever the current weapon sounds/feels like.

---

## Stopping feedbacks on actor death

`FeedbackPlayerLite` stops cleanly when removed from the tree — but if your actor is long-lived and you want to kill an in-flight sequence mid-play:

```gdscript
player.stop()
```

That cancels every active instance, runs each feedback's `_stop()` hook (restores camera transforms, scale baselines, time-scale, etc.), and emits no further signals.

---

## `@tool` and editor behaviour

All feedback resources and the player are `@tool` scripts. This lets the inspector build live previews. **Call feedbacks do nothing in the editor** — their `_play` returns early when `Engine.is_editor_hint()` is true, so no accidental gameplay method calls during authoring.
