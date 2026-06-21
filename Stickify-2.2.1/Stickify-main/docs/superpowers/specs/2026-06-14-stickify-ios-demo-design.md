# Stickify iOS Demo Design

## Goal

Build a native SwiftUI demo for Stickify from `Stickify_PRD_V001.md`, using the selected `Sky Pop Capture` visual direction as the north star. The demo should feel like a polished product prototype, not a generic sample app.

## Selected Direction

`Sky Pop Capture` is scanner-first and PRD-faithful. The first screen makes the core loop obvious: scan a real-world object, see an AI highlight, tap to collect it into a temporary shelf, then continue into cloud storage and playful sticker creation.

Reference image:

`/Users/sirius/.codex/generated_images/019ec6a8-0e39-7241-b0a7-068d5e5ef10b/ig_05b20e2088f64469016a2ec44c29248191ad7d867368567031.png`

## Product Scope

The demo implements the full PRD information architecture at prototype depth:

- `Capture`: a camera-like scanner mock with frozen scan state, blue AI outline, right-side temporary shelf, collection animation state, and save-space cleanup prompt.
- `Library`: sky-blue cloud hub with a 2 x 4 cloud grid, new-library entry, and a vault view with type/color sorting, rainbow ordering, long-press multi-select, and editing controls.
- `Playground`: grey canvas with red mode controls for stacking, fusion, and scatter, plus a red solidify action that creates a super sticker.

The demo uses seeded mock sticker data and local state only. It does not require camera access, AI services, photo deletion, physics engines, or persistence beyond the running app session.

## Visual System

Colors:

- Sky blue: `#7FD7FF` for the capture atmosphere and library hub.
- Classic blue: `#0056B8` for scan highlights, primary actions, and active capture/library controls.
- Energetic red: `#E52B1E` for playground mode controls and super-sticker actions.
- Order grey: `#EBEBEB` for shelves, vault backgrounds, inactive tabs, and structured surfaces.
- Carbon black: `#2D2926` for text and icon strokes.

Shape language:

- Use circles, pills, and cloud-like rounded forms.
- Avoid sharp corners.
- Bottom navigation should read as a white cloud base.
- Sticker cards use white borders, soft shadows, and slight rotation/offset.

Typography:

- Use system fonts.
- Keep UI copy short and readable.
- Mix English tab labels with light Chinese UI labels from the PRD where they add personality: `万物皆可贴纸`, `识别到贴纸`, `类型`, `颜色`, `固化`, `超级贴纸`.

## Interaction Design

Capture:

- Default state shows the camera-like scanner with an object outlined in blue.
- Tapping the highlighted object adds a sticker to the right shelf and changes the hint copy.
- Tapping the shutter toggles a frozen-scan presentation with dimmed blur treatment.
- Tapping the shelf opens a lightweight enlarged shelf sheet with no editing controls.
- After collection, a cleanup prompt can appear with a "do not ask again" toggle.

Library:

- Cloud hub shows eight slots in a 2 x 4 layout; the final slot creates a new cloud in demo state.
- Selecting a cloud opens the vault.
- Type and color segmented controls change grouping emphasis.
- Long-press or edit settings enables multi-select.
- Editing toolbar exposes clone, style, filter, and material controls with visible demo feedback.

Playground:

- Mode dial switches between stacking, fusion, and scatter.
- Stack mode shows layered stickers with depth.
- Fusion mode shows two stickers overlapping with a soft merged region.
- Scatter mode shows parameter toggles for stack, gap, and gravity.
- Solidify creates a super-sticker result banner and adds a new item to mock state.

## Architecture

Create a small native SwiftUI app with simple local models and focused view files:

- `StickifyApp.swift`: app entry.
- `Models/StickerDemoModels.swift`: tabs, stickers, library clouds, playground modes, demo state helpers.
- `Design/StickifyTheme.swift`: colors, reusable shapes, and visual helpers.
- `Components/StickerChip.swift`: reusable sticker display.
- `Components/CloudShape.swift`: reusable cloud-like container.
- `Components/CloudTabBar.swift`: custom bottom tab base.
- `Features/Capture/CaptureView.swift`: scanner demo.
- `Features/Library/LibraryView.swift`: cloud hub and vault.
- `Features/Playground/PlaygroundView.swift`: play modes.
- `ContentView.swift`: root state and tab switching.

State stays in `ContentView` and is passed down with bindings where child views mutate shared demo data. Feature-local state stays local.

## Build Target

Use a minimal Xcode iOS project that can build and run on Simulator. Deployment target should be iOS 17 or newer so SwiftUI APIs remain simple and modern.

## Validation

The demo is complete when:

- `xcodebuild` or XcodeBuildMCP builds the iOS target successfully.
- Simulator launch shows the Capture tab first.
- Capture, Library, and Playground tabs are reachable.
- The highlighted object can be collected into the shelf.
- The library can enter a vault and change sorting mode.
- Playground mode switching and solidify feedback work.
- Screens visually follow the selected `Sky Pop Capture` direction.
