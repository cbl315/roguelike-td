# Screen Flash 2D

Full-viewport colour flash driven by a fade-in → hold → fade-out envelope. One shared `ColorRect` per canvas layer lives under the `SparkleLitePresets` autoload, so a flash triggered just before a scene change survives the transition, and multiple flashes on the same layer composite onto a single rect instead of stacking `CanvasLayer`s.

**Class:** `FeedbackScreenFlash2DLite` · **Demo:** `samples/scenes/sparklelite_03_screen_flash.tscn`

---

## Properties

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `flash_color` | `Color` | `Color.WHITE` | Peak-intensity colour. |
| `fade_in_duration_ms` | `float` | `40.0` | Transparent → peak. Keep small for impacts. |
| `hold_duration_ms` | `float` | `0.0` | Time at peak before fade-out starts. |
| `fade_out_duration_ms` | `float` | `120.0` | Peak → transparent. This is where the "bloom" lives. |
| `flash_intensity` | `float` | `0.3` | Peak alpha in `[0, 1]`. `0.3` is a noticeable-but-readable flash; `1.0` is a full whiteout. |
| `canvas_layer` | `int` | `100` | `CanvasLayer.layer` index. Different values create independent overlays — useful for separating gameplay flashes from UI flashes. |
| `blend_mode` | `BlendMode` | `ADD` | `ADD` brightens the image; `MODULATE` tints it. |

### Inherited

`label`, `enabled`, `delay_ms`, `duration_ms` *(unused — total length is driven by fade-in + hold + fade-out)*, `intensity_multiplier`.

---

## Stacking

Multiple flashes on the same `canvas_layer` composite onto one shared `ColorRect`. The coordinator:

- uses the **maximum** current alpha among active flashes as the rect's alpha (so two overlapping 0.3 flashes don't blow out to 0.6)
- **weighted-averages** each flash's colour by its current alpha (so a red flash fading out while a blue one peaks slides the tint correctly)
- switches the rect's material to `BLEND_MODE_ADD` if **any** active flash uses `ADD`

When the last flash ends the rect alpha is forced back to `0`.

---

## Blend modes

- **`ADD`** — adds the flash colour to the image. Best for hits, explosions, and bright impacts. White flashes with `ADD` look like physical light.
- **`MODULATE`** — multiplies the flash colour over the image. Best for damage-taken (red tint), freeze (blue tint), or any state-driven colour wash where you want the underlying image to stay readable.

---

## Recipes

### Hit flash (white pop)

```gdscript
flash.flash_color = Color.WHITE
flash.flash_intensity = 0.25
flash.fade_in_duration_ms = 20
flash.hold_duration_ms = 0
flash.fade_out_duration_ms = 120
flash.blend_mode = FeedbackScreenFlash2DLite.BlendMode.ADD
```

### Damage-taken (red wash)

```gdscript
flash.flash_color = Color(1.0, 0.1, 0.1)
flash.flash_intensity = 0.4
flash.fade_in_duration_ms = 60
flash.hold_duration_ms = 30
flash.fade_out_duration_ms = 300
flash.blend_mode = FeedbackScreenFlash2DLite.BlendMode.MODULATE
```

### Critical hit (held whiteout)

```gdscript
flash.flash_color = Color.WHITE
flash.flash_intensity = 0.9
flash.fade_in_duration_ms = 10
flash.hold_duration_ms = 50
flash.fade_out_duration_ms = 200
flash.blend_mode = FeedbackScreenFlash2DLite.BlendMode.ADD
```

---

## Gotchas

- **The overlay survives scene changes.** It lives under the `SparkleLitePresets` autoload — a flash fired just before `change_scene_to_file` still completes on the new scene. Usually that's desirable; if not, set a shorter total duration.
- **Timing runs on unscaled time.** Flash tweens use `set_ignore_time_scale(true)` so they still play during `FeedbackHitPauseLite`. That's almost always what you want for feedback.
- **The flash ignores `duration_ms`.** Total length is `fade_in + hold + fade_out`. `FeedbackPlayerLite.get_total_duration()` does not account for this yet — add the three values yourself if you need the real total.
- **`canvas_layer = 0` sits under most UI.** The default `100` puts the flash above typical HUD elements; drop it if you want the flash to appear behind an overlay.
