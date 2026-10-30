# Sparkle Lite Documentation

Welcome to the Sparkle Lite docs. This folder is the reference for everything the plugin ships with — authoring, runtime, each feedback type, and the preset system.

## Start here

- **[Getting Started](getting_started.md)** — your first `FeedbackPlayerLite`, start to finish.
- **[Authoring in the inspector](authoring_in_inspector.md)** — the custom UI: preview, copy/paste, drag-reorder, presets.
- **[Runtime API](runtime_api.md)** — building players and feedbacks from pure code.

## Reference

- **[FeedbackPlayerLite API](feedback_player_api.md)** — the orchestrator node. Every exported property, method, and signal.
- **[Presets & the autoload](presets_and_autoload.md)** — saving named feedback stacks and playing them from anywhere.

## Feedbacks

Every feedback type, one page each:

| Feedback | Page |
|----------|------|
| Camera Shake (3D) | [feedbacks/camera_shake.md](feedbacks/camera_shake.md) |
| Camera Shake 2D | [feedbacks/camera_shake_2d.md](feedbacks/camera_shake_2d.md) |
| Hit Pause | [feedbacks/hit_pause.md](feedbacks/hit_pause.md) |
| Screen Flash 2D | [feedbacks/screen_flash_2d.md](feedbacks/screen_flash_2d.md) |
| Audio | [feedbacks/audio.md](feedbacks/audio.md) |
| Scale Punch | [feedbacks/scale_punch.md](feedbacks/scale_punch.md) |
| Call | [feedbacks/call.md](feedbacks/call.md) |

## Quick links by task

- **Fire a shake when I shoot** → [Getting Started](getting_started.md) + [Camera Shake](feedbacks/camera_shake.md).
- **Hit-stop when I land a hit** → [Hit Pause](feedbacks/hit_pause.md).
- **A full juicy hit reaction (shake + pause + flash + audio + punch)** → Demo 08 + [Runtime API](runtime_api.md).
- **Play the same sequence on different nodes** → [Presets & the autoload](presets_and_autoload.md).
- **Swap feedback lists at runtime (per weapon / per skill)** → [Runtime API](runtime_api.md).
