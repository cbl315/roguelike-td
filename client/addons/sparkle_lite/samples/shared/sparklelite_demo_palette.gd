# sparklelite_demo_palette.gd
# Shared color palette for the Sparkle Lite sample scenes. The values
# mirror the plugin icon gradient so every sample feels part of one set.
#
# Tutorial note: nothing here is Sparkle Lite specific — this is just
# a convenience constants file so sample scenes don't sprinkle magic
# hex codes everywhere.

class_name SparkleLiteDemoPalette
extends RefCounted

## Deep purple/black page background.
const BG: Color = Color("#140A1F")

## Card background — one step up from the page bg.
const CARD_BG: Color = Color("#1E1028")

## Panel fill for inline info boxes and code blocks.
const PANEL_BG: Color = Color("#271838")

## Subtle stroke for card outlines.
const STROKE: Color = Color("#3A2450")

## Primary text color.
const TEXT: Color = Color("#F4EEFF")

## Muted / secondary text.
const TEXT_MUTED: Color = Color("#B8A8D0")

## Code-block monospace tint.
const CODE_TEXT: Color = Color("#D8C7F0")

## Icon gradient stops (yellow → pink → purple → blue), same as the
## plugin icon's grad_main.
const GRADIENT_YELLOW: Color = Color("#FFE17A")
const GRADIENT_PINK: Color = Color("#FF6FA8")
const GRADIENT_PURPLE: Color = Color("#A24AE2")
const GRADIENT_BLUE: Color = Color("#4A90E2")

## Cyan / warm accents from the plugin icon highlights.
const ACCENT_CYAN: Color = Color("#8AF0E8")
const ACCENT_WARM: Color = Color("#FF8A4A")

## Per-feedback accent colors — mirror FeedbackTypeRegistryLite.
const ACCENT_CAMERA_SHAKE: Color = Color("#4A90E2")
const ACCENT_HIT_PAUSE: Color = Color("#E24A4A")
const ACCENT_SCREEN_FLASH: Color = Color("#FFFFFF")
const ACCENT_AUDIO: Color = Color("#E2C64A")
const ACCENT_SCALE_PUNCH: Color = Color("#FF8C42")
const ACCENT_CALL: Color = Color("#9EB24A")

## itch.io promo accent (brand pink).
const ITCH_PINK: Color = Color("#FA5C5C")
