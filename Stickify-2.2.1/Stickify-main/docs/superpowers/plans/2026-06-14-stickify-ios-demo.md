# Stickify iOS Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native SwiftUI iOS demo for Stickify that turns the PRD into a polished scanner-first product prototype.

**Architecture:** Scaffold a minimal iOS Xcode project, then add focused SwiftUI files for theme, reusable components, data models, and three feature tabs. Use local seeded state so every visible control has believable demo behavior without external services.

**Tech Stack:** Swift 5, SwiftUI, Xcode iOS Simulator, local mock data.

---

## File Structure

- Create `Stickify.xcodeproj`: native iOS project file.
- Create `Stickify/StickifyApp.swift`: app entry point.
- Create `Stickify/ContentView.swift`: owns selected tab and shared demo state.
- Create `Stickify/Models/StickerDemoModels.swift`: data models and sample data.
- Create `Stickify/Design/StickifyTheme.swift`: design tokens and shape helpers.
- Create `Stickify/Components/StickerChip.swift`: sticker rendering component.
- Create `Stickify/Components/CloudShape.swift`: cloud container component.
- Create `Stickify/Components/CloudTabBar.swift`: bottom cloud base navigation.
- Create `Stickify/Features/Capture/CaptureView.swift`: scanner-first capture flow.
- Create `Stickify/Features/Library/LibraryView.swift`: cloud hub and vault/editor flow.
- Create `Stickify/Features/Playground/PlaygroundView.swift`: sticker play modes.

## Task 1: Scaffold Buildable iOS Project

**Files:**
- Create: `Stickify.xcodeproj/project.pbxproj`
- Create: `Stickify/StickifyApp.swift`
- Create: `Stickify/ContentView.swift`

- [ ] **Step 1: Create the project structure**

Create the `Stickify` source folder and initial Swift files.

- [ ] **Step 2: Add a minimal iOS app target**

Create an Xcode project named `Stickify` with bundle identifier `com.sirius.Stickify`, deployment target iOS 17.0, and source files under `Stickify/`.

- [ ] **Step 3: Add temporary app shell**

`StickifyApp.swift`:

```swift
import SwiftUI

@main
struct StickifyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

`ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Stickify")
            .font(.largeTitle.bold())
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project Stickify.xcodeproj -scheme Stickify -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: build succeeds or reports only simulator-name mismatch, in which case select an available iPhone simulator.

## Task 2: Add Theme, Models, and Root Navigation

**Files:**
- Create: `Stickify/Models/StickerDemoModels.swift`
- Create: `Stickify/Design/StickifyTheme.swift`
- Create: `Stickify/Components/CloudTabBar.swift`
- Modify: `Stickify/ContentView.swift`

- [ ] **Step 1: Define demo models**

Add `AppTab`, `StickerItem`, `StickerLibrary`, `PlaygroundMode`, and `StickifyDemoState` with seeded sample stickers and libraries.

- [ ] **Step 2: Define design tokens**

Add static colors for sky blue, classic blue, energetic red, order grey, and carbon black; add reusable rounded shadow helpers.

- [ ] **Step 3: Build custom tab bar**

Create a white cloud-base tab bar with three large rounded tab buttons: Capture, Library, Playground.

- [ ] **Step 4: Wire root navigation**

`ContentView` owns `@State private var selectedTab: AppTab = .capture` and `@State private var demoState = StickifyDemoState.sample`.

- [ ] **Step 5: Build**

Run the same `xcodebuild` command and confirm the tab shell compiles.

## Task 3: Implement Capture Demo

**Files:**
- Create: `Stickify/Components/StickerChip.swift`
- Create: `Stickify/Features/Capture/CaptureView.swift`
- Modify: `Stickify/ContentView.swift`

- [ ] **Step 1: Add reusable sticker chip**

Render stickers as white-bordered rounded chips with emoji/art label, category color, and soft shadow.

- [ ] **Step 2: Build scanner surface**

Create a sky-blue camera mock with blurred scenic background gradients, a central cloud-object sticker, blue glow outline, scan brackets, hint bubble, round shutter, flash/flip buttons, and right-side translucent capsule shelf.

- [ ] **Step 3: Add interactions**

Tapping the highlighted object adds it to shelf state; tapping shutter toggles frozen scan; tapping shelf opens enlarged shelf sheet; cleanup prompt appears after first collect.

- [ ] **Step 4: Build**

Run `xcodebuild` and confirm Capture compiles.

## Task 4: Implement Library Demo

**Files:**
- Create: `Stickify/Components/CloudShape.swift`
- Create: `Stickify/Features/Library/LibraryView.swift`
- Modify: `Stickify/ContentView.swift`

- [ ] **Step 1: Build cloud hub**

Create a pure sky-blue hub with a 2 x 4 cloud grid, library names, counts, and a dashed add cloud.

- [ ] **Step 2: Build vault state**

Selecting a cloud opens a grey vault with type/color segmented controls and a dense sticker grid.

- [ ] **Step 3: Add edit controls**

Long-press a sticker or tap library settings to enter edit mode; show clone, style, filter, and material controls with visible selected-state feedback.

- [ ] **Step 4: Build**

Run `xcodebuild` and confirm Library compiles.

## Task 5: Implement Playground Demo

**Files:**
- Create: `Stickify/Features/Playground/PlaygroundView.swift`
- Modify: `Stickify/ContentView.swift`

- [ ] **Step 1: Build canvas**

Create an order-grey canvas with layered sticker chips and a cloud source tray.

- [ ] **Step 2: Add mode switching**

Add three energetic-red circular mode controls for stack, fusion, and scatter.

- [ ] **Step 3: Add per-mode behavior**

Stack shows layer ordering controls; fusion shows a soft merged overlap area; scatter shows stack/gap/gravity toggles.

- [ ] **Step 4: Add solidify action**

The red solidify button shows a super-sticker success banner and appends a sample super sticker to state.

- [ ] **Step 5: Build**

Run `xcodebuild` and confirm Playground compiles.

## Task 6: Simulator Verification and Polish

**Files:**
- Modify any Swift files that fail visual or compile checks.

- [ ] **Step 1: Run the app on Simulator**

Use XcodeBuildMCP when defaults are configured, otherwise use `xcodebuild` and the available simulator destination.

- [ ] **Step 2: Verify core flows**

Confirm Capture opens first, object collection updates the shelf, Library vault sorting changes presentation, Playground modes switch, and solidify shows feedback.

- [ ] **Step 3: Visual polish pass**

Compare the app against the selected `Sky Pop Capture` reference and fix spacing, radii, colors, hierarchy, and broken layouts.

- [ ] **Step 4: Final build**

Run a final successful build command and record the result.

## Self-Review

- Spec coverage: the plan covers the PRD's three-tab information architecture, capture shelf, cloud hub, vault sorting/editing, playground modes, and visual tokens.
- Placeholder scan: no `TBD`, `TODO`, or unspecified implementation steps remain.
- Type consistency: model and view names are consistent across tasks.
