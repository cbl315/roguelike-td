# Getting Started

This walkthrough builds a juicy shoot reaction in four steps: a camera shake at the moment of the shot, a screen flash a frame later, and one `play()` call that fires both.

Time: **~5 minutes**. You'll end with a player you can drop into any scene.

---

## 1. Install

Copy the `addons/sparkle_lite/` folder into your project's `addons/` directory and enable **Sparkle Lite** under **Project → Project Settings → Plugins**.

That's it. No native code, no autoload wiring — `plugin.gd` registers the `SparkleLitePresets` autoload automatically.

---

## 2. Add a FeedbackPlayerLite

In a scene with a `Camera3D` (the built-in **Node → 3D Scene** template works), add a child node of type **FeedbackPlayerLite**.

You can find it two ways:
- In the **Add Node** dialog, search for `FeedbackPlayerLite`.
- Or add a generic `Node`, then attach `res://addons/sparkle_lite/players/feedback_player_lite.gd` to it.

Select the new node. The inspector now shows the Sparkle Lite custom UI — an empty feedbacks list plus a big **+ Add Feedback** button at the bottom.

---

## 3. Author the feedback stack

### Camera Shake (at 0 ms)

Click **+ Add Feedback**, choose **Camera Shake**. A new row appears with:

- A preview button (the eye icon).
- An enable toggle.
- A collapsible parameter block.

Expand the row. Leave everything at defaults — the out-of-the-box values are tuned for a light shoot feel — but click **Preview** (the eye). Your camera shakes. 

Optional tweaks:
- **duration_ms** → `350`
- **position_amplitude** → `Vector3(0.2, 0.2, 0)`
- **rotation_amplitude** → `Vector3(0, 0, 3)` (degrees)

### Screen Flash 2D (at 40 ms)

Click **+ Add Feedback** again, choose **Screen Flash 2D**.

- **delay_ms** → `40` (so the flash lands just after the shake starts)
- **flash_color** → `Color(1, 1, 0.8)` (warm muzzle tint)
- **flash_intensity** → `0.4`
- **fade_out_duration_ms** → `150`

Click the flash's **Preview** button. A quick warm flash covers the viewport and fades.

---

## 4. Fire it from code

On the node that handles shooting (often the player controller), grab the `FeedbackPlayerLite` and call `play()`:

```gdscript
@onready var feedback: FeedbackPlayerLite = $FeedbackPlayer

func shoot() -> void:
    # ... spawn projectile, deduct ammo, etc ...
    feedback.play()
```

That's the whole integration. Both the shake and the flash are scheduled in parallel (the flash waits 40 ms on its own), and both stop cleanly if you free the player or call `stop()`.

### Per-call intensity

`play()` accepts an optional intensity multiplier:

```gdscript
feedback.play()        # 1.0x — authored level
feedback.play(0.4)     # soft shot
feedback.play(1.8)     # critical / heavy
```

The multiplier scales every feedback in the list. A soft shot gets a small shake *and* a small flash; a crit gets both dialed up.

---

## Where to go next

- **[Authoring in the inspector](authoring_in_inspector.md)** — learn the preview button, drag-reorder, copy/paste, and saving presets.
- **[Feedback reference](README.md#feedbacks)** — every exported property on every feedback.
- **[Runtime API](runtime_api.md)** — doing this without the inspector, for runtime-generated players, skills, or data-driven feedback stacks.
- **[Demo project](../samples/)** — nine scenes, each the minimum code needed to showcase one feedback.
