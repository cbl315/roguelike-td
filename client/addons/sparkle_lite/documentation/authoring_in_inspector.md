# Authoring in the Inspector

The `FeedbackPlayerLite` inspector is where most of your work happens. It's a custom UI — the default "array editor" Godot ships with is replaced by a dedicated list editor with per-row tools.

---

## Anatomy of a row

Each feedback in the list is shown as a row with:

1. **Type icon** — cues what kind of feedback this is at a glance.
2. **Label field** — the display name. Leave blank to show the default type name.
3. **Enable toggle** — skip this feedback without deleting it.
4. **Preview button (eye)** — fires this single feedback in the editor against the current scene.
5. **Menu button (⋮)** — copy, paste-over, duplicate, delete.
6. **Drag handle** — drag the row up or down to reorder.
7. **Expand arrow** — collapses the parameter block.

Below the rows, a big **+ Add Feedback** dropdown lists the seven types.

---

## Previewing

The preview button runs the feedback against your currently open scene — no play-mode required. Most feedbacks have simple requirements:

- **Camera Shake / Camera Shake 2D** — needs at least one active camera in the scene.
- **Screen Flash 2D** — always works.
- **Hit Pause** — needs the editor to be running (preview triggers the real time-scale drop).
- **Audio** — needs an `AudioStream` assigned.
- **Scale Punch** — needs a valid target path.
- **Call** — does nothing in preview (to avoid triggering gameplay methods by mistake).

If preview can't run, the row shows a short diagnostic (for example: *"camera_path did not resolve to a Camera3D"*). Fix the input and try again.

---

## Copy / paste

The **⋮** menu on each row has:

- **Copy** — snapshot this feedback onto the Sparkle Lite clipboard.
- **Paste over** — replaces this feedback's parameters with the clipboard's.
- **Duplicate** — insert a clone right below this row.
- **Delete** — remove this feedback.

Clipboard survives across scene switches inside the same editor session. Useful for tuning one shake on a boss and dropping it into the normal enemy stack.

---

## Drag-reorder

Hold the drag handle on any row and drop it between others to reorder. The order in the list is the order they fire — but note that feedbacks don't *wait* for each other. Each one honours its own `delay_ms` from the `play()` call, regardless of list order.

Order still matters for one thing: readability. Put the 0 ms feedbacks at the top, the delayed ones at the bottom. Your future self will thank you.

---

## Presets

Save a full feedback list as a `.tres` file and reuse it on any player.

### Saving a preset

1. Configure a `FeedbackPlayerLite` exactly how you want it.
2. In the **FileSystem** dock, right-click your preset folder → **New Resource** → search for `FeedbackPresetLite`.
3. Open the new `.tres`, paste the player's feedbacks into its `feedbacks` array (or use the per-feedback copy/paste to rebuild the list).

Alternatively, from code:

```gdscript
var preset := FeedbackPresetLite.new()
preset.feedbacks = my_player.feedbacks.duplicate(true)
ResourceSaver.save(preset, "res://presets/shoot_hit.tres")
```

### Applying a preset

```gdscript
my_player.apply_preset(preset)
```

See **[Presets & the autoload](presets_and_autoload.md)** for the global registry and scene-wide `SparkleLitePresets.play(name)` pattern.

---

## The "You're using Sparkle Lite" banner

Below the feedbacks list you'll see a soft purple banner. That's the nudge toward the full Sparkle plugin — 33 feedback types vs the 7 here. The banner is cosmetic only; it does not affect runtime.

---

## Gotchas

- **Custom inspector only appears on `FeedbackPlayerLite` nodes.** Other node types show the default Godot inspector.
- **Tool scripts.** Every feedback and the player are `@tool` scripts. Editing feedback source code requires a scene reload on rare occasions — close and reopen the scene.
- **The preview button uses a dedicated controller** that reverts any state it mutated (camera transform, time scale, node scale) when the preview ends or you click preview on a different row.
