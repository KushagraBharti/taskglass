# Development notes

## Local environment

Built on macOS 27.0.1, Apple Silicon, with Apple Swift 6.4 and the command line macOS SDK. Minimum deployment target is macOS 26. No software was installed for this project. Build scripts use existing `swift`, `clang`, and `xcrun`; measurement uses Python's standard library.

## Performance decisions

- Direct Mach and libproc calls replace a child `ps` process on every sample.
- A sampler actor performs collection off the main thread and retains only the previous counters. Executable names and paths are cached until a PID's start identity changes.
- A bounded 90-point graph uses simple vector paths rather than a full chart framework or Canvas drawing context.
- AppKit's NSTableView creates reusable cells for visible rows. SwiftUI does not construct hundreds of process row hierarchies.
- Sorting and filtering happen once per snapshot or user change, rather than in every body evaluation. The Apps filter obtains running application IDs once per arrangement.
- Manual pause and hidden/minimized state cancel the sampling task and its periodic wakeups. Resume resets counters before calculating rates.
- The interface uses system typography and materials. There are no continuous animations, external fonts, image downloads, or web views.
- A hostname lookup unexpectedly triggered synchronous name resolution during UI inspection. It was removed; the app uses “This Mac.”

## Next work

- App grouping with aggregate child-process accounting and a tree view. Process identity must remain correct across exit and PID reuse.
- Disk capacity and per-volume throughput, battery details, and richer per-interface networking.
- User-configurable columns, persistent window preferences, and process-specific history with a strict memory bound.
- Broader tests under process churn, interface changes, sleep/wake, memory pressure, and multiple macOS versions.
- VoiceOver, increased contrast, reduced transparency, light appearance, and keyboard-only review.
- App icon, license, contribution guidelines, signed releases and notarization.

These are follow-up items, not advertised capabilities. GPU or sensor collection should be added only with documented permissions, measurement semantics, and measured overhead.

## Repository hygiene

The project has its own Git repository inside `taskglass/`. No files from the parent workspace belong to it. Generated screenshots and build output are ignored. Timing reports in `measurements/` contain only aggregate resource numbers and can be committed. Nothing has been pushed to GitHub.

## Native utility refinement

The second design pass removes the dashboard sidebar and tinted metric cards. Navigation, filtering, search, pause, and the optional inspector use native macOS controls. The primary process view keeps a compact CPU/memory/network summary beneath the table. Extra resource columns are optional. Performance uses a single system accent color, plain section grouping and aligned data instead of card backgrounds.

Design references:

- [Apple materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials), which distinguishes the controls/navigation layer from content.
- [Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/), particularly native toolbar behavior.

Table updates now write changed text into existing visible cells instead of reloading row views. Process enumeration uses a smaller C record and reserves the next counter dictionary before filling it. The Performance view avoids process enumeration entirely. Sampling restarts immediately when the selected view or refresh interval changes. UI, monitoring, sampling, table integration and graph drawing are in separate source files.

For appearance QA, launch the app with `open dist/Taskglass.app --args --preview-light`. This sets only the running app's appearance and does not change macOS settings. Relaunch without the argument to follow the system appearance again. The resource strip omits its mini graphs when the content pane narrows for the inspector.

The Mach sampler reuses one host send right initialized with `pthread_once`. Build packaging replaces the executable atomically, so rebuilding does not truncate the executable used by a running app.
