# Presets & the Autoload

Named feedback stacks, saved as `.tres`, triggered from anywhere. This is how you give gameplay code a flat API — `SparkleLitePresets.play(&"explosion")` — without each caller knowing which player exists in the current scene.

---

## What is a preset?

`FeedbackPresetLite` is a `Resource` with a single exported property:

```gdscript
@export var feedbacks: Array[FeedbackBaseLite] = []
```

It's a pure data container — no runtime behaviour, no signals. Save one as a `.tres` and it becomes a shareable, diff-friendly feedback stack.

### Creating a preset in the editor

1. In the **FileSystem** dock, right-click the folder where you want to save → **New Resource** → `FeedbackPresetLite`.
2. Name the file, then open it.
3. Add feedbacks to the `feedbacks` array just like on a `FeedbackPlayerLite`.

### Creating a preset from code

```gdscript
var preset := FeedbackPresetLite.new()
preset.feedbacks = my_player.feedbacks.duplicate(true)
ResourceSaver.save(preset, "res://presets/explosion.tres")
```

---

## Applying a preset to a player

```gdscript
my_player.apply_preset(preset)
my_player.play()
```

`apply_preset` deep-copies the preset's feedbacks onto the player, so later tweaks to the player don't mutate the source resource.

---

## The `SparkleLitePresets` autoload

`plugin.gd` registers an autoload singleton called `SparkleLitePresets` when the plugin is enabled. It's a `FeedbackPresetsAutoloadLite` and acts as the global preset registry.

### Registering presets

```gdscript
SparkleLitePresets.register_preset(&"pop", preload("res://presets/pop.tres"))
SparkleLitePresets.register_preset(&"boom", preload("res://presets/boom.tres"))
```

Or bulk-load a folder:

```gdscript
SparkleLitePresets.load_preset_folder("res://presets/")
# Every .tres in the folder becomes a preset named after its filename.
```

### Playing by name

```gdscript
SparkleLitePresets.play(&"pop")            # finds a player in the current scene
SparkleLitePresets.play(&"boom", 1.5)      # with intensity
```

`play()` walks the current scene for the first `FeedbackPlayerLite` it finds, swaps its feedbacks for the preset (snapshotted + restored on completion), and fires. Use this when you have one "effects" player per scene and many callers want to trigger different effects on it.

### Playing on a specific player

```gdscript
SparkleLitePresets.play_on(&"pop", $DedicatedPlayer, 1.0)
```

Useful when you have multiple `FeedbackPlayerLite` nodes and want to target a specific one.

### Querying the registry

```gdscript
SparkleLitePresets.has_preset(&"pop")       # bool
SparkleLitePresets.get_preset(&"pop")       # FeedbackPresetLite or null
SparkleLitePresets.list_presets()           # Array[StringName]
```

---

## Patterns

### One shared player, many named effects

Give your "world" scene a single `FeedbackPlayerLite` (maybe on the main camera), register every preset under `res://presets/`, and call `SparkleLitePresets.play(&"name")` from anywhere in the codebase. Callers don't need a reference to the player; they just name the effect they want.

### Per-actor player, shared preset library

Each actor has its own `FeedbackPlayerLite`. To fire a specific effect on a specific actor:

```gdscript
SparkleLitePresets.play_on(&"hit_reaction", enemy.feedback_player, 1.0)
```

The preset's feedbacks get swapped onto that player for one play, then restored.

### Data-driven effects

Presets are plain resources — serialise them to JSON on your server, send to client, load and register:

```gdscript
var preset := FeedbackPresetLite.new()
preset.feedbacks = _build_feedbacks_from_json(payload)
SparkleLitePresets.register_preset(payload.name, preset)
```

(You'd implement `_build_feedbacks_from_json` to `.new()` the right feedback types and set their properties.)

---

## Notes

- **Plugin autoload name is `SparkleLitePresets`.** If you need a different name, edit `plugin.gd`'s `_AUTOLOAD_NAME` constant — but be aware every feedback that looks for the audio pool (`SparkleLitePresets/SparkleLiteAudioPool`) uses the default path.
- **Presets never mutate.** Every `apply_preset` / `play` / `play_on` uses `duplicate(true)`. You can share one preset across every `FeedbackPlayerLite` in your game without worrying about state leaks.
