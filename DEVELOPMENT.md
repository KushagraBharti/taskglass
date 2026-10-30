# Development notes

## Toolchain and scope

Taskglass targets macOS 14+ on ARM64 with Swift 6.0 or newer. Development used macOS 27.0.1, Swift 6.4 and Command Line Tools on an M5 Pro. No software was installed for this project. Swift/Clang, iconutil, codesign, ditto and hdiutil are Apple tools already on the build machine. Optional measurement scripts use Python's standard library.

The app has no package dependencies, web view, privileged helper, daemon, login item or updater service. It does not collect analytics or make monitoring network requests. Help-menu links open the user's browser only when clicked.

## Performance choices

- Direct Mach, libproc and IOKit calls avoid launching monitoring subprocesses.
- A sampler actor collects off the main thread. Paths and app identities are cached until PID/start identity changes. Directory account-name lookups use a bounded utility queue.
- Histories retain at most 601 system points and 181 selected-process points. Icon/account caches are bounded. The list cache holds at most 256 icons at 32×32 pixels; the inspector holds 16 at 80×80 pixels. Together their pixel storage is about 1.4 MiB, excluding AppKit caches. No monitoring history is written to disk.
- One AppKit drawing view renders each chart, including its grid and traces. Core maps also use AppKit. There is no charting runtime, continuous animation, Canvas, drawingGroup or external font.
- Native tables reuse visible cells. Resource outlines use positional slots, with expansion and selection following content identity across re-ranking. Full reloads are reserved for initial display and grouping changes.
- Group aggregates are calculated once; helpers use their outer app bundle. Overview selects five leaders without sorting a second full array. Resource views sort their shared unsorted source once.
- Overview and resource contexts without an active process-counter source collect process data every third tick. CPU, memory, storage, GPU and Neural Engine views collect on each tick. Process deltas have their own elapsed clock.
- CPU/GPU temperature summaries, fans, battery and capacity refresh every 10 seconds. Full IOHID sensor polling runs on the Temperatures page or as an SMC fallback. Handles and sensor metadata are reused.
- CLPC setup constructs only three recognized descriptors instead of enumerating the entire IOReport legend.
- Covered windows keep bounded history without publishing invisible UI updates. Pause, hide and minimize cancel periodic sampling. Resume/wake reset rate baselines.
- Release builds use the explicit native SwiftPM engine and safe `-Osize` optimization and full link-time optimization, strip distribution-only symbols, and retain the unstripped build and dSYM in `.build`. There is no `-Ounchecked`.

See [measurements](measurements/README.md) for measured costs and limitations. Sampler timings exclude UI work and are not whole-app CPU claims.

## Accuracy and safety

Process CPU Mach ticks are converted using mach_timebase_info before elapsed-time deltas. A real busy single-thread fixture must measure 30–130%; 100% represents one core. System CPU is normalized across logical cores and handles 32-bit tick wraps.

Process quit actions require a current record, the same PID/start identity, and the current user's ownership. Root, PID 1 and Taskglass itself are excluded. No privilege escalation is attempted.

SMC is read only. Optional SMC/IOReport ABI handling and CLPC descriptors reference MIT-licensed macmon; revision and license are in [third-party notices](THIRD_PARTY_NOTICES.md). No macmon or powermetrics executable is invoked. Power is experimental and is not ANE utilization or wall power. Unsupported values leave graph gaps.

The optional six-second Metal and Core ML fixtures validated real GPU PID attribution, ANE resource-group time and Neural Engine memory on the M5 Pro. Fixtures are not linked into the app and install nothing. Shared ANE counters are never presented as separate per-PID execution totals. Recognized macOS 27 layouts enable ANE accounting; older/unknown layouts remain unavailable. See [accelerator attribution](docs/accelerator-attribution.md). Additional physical M-series/OS coverage, deeper process trees, per-device storage, media engines and per-process network attribution remain future work.

## Design and verification

The interface shares typography, colors, bands, chart rendering and native table cells. Historical design reviews and superseded measurements remain in Git history; current behavior and limitations belong in this document and the measurement summary.

The final native-engine pass visited all resource pages, checked full grouped browsing and search, process trends and self-quit protection, and verified reopening after close. It also fixed paused navigation to use the retained process sample rather than a system-only snapshot. A regression test covers that case.

The first preview is intentionally dark. Native toolbar/sidebar controls follow macOS. Full VoiceOver and all accessibility preference combinations still need broader user testing; tooltips, keyboard actions and accessibility labels are included.

## Distribution

`VERSION` drives the bundle and archive names. `scripts/build-app.sh` makes the app; `package-release.sh` makes ZIP/DMG/checksums; `validate-release.sh` verifies architecture, minimum OS, licenses, signatures, mounted DMG and extracted ZIP contents. The public release workflow runs tests and packaging, attests its artifacts, and publishes an unsigned prerelease from a matching version tag. CI uses standard public ARM64 runners.

The free preview is ad-hoc signed for integrity, without Apple Developer ID or notarization. Users follow normal Gatekeeper approval. No security-disabling installer or quarantine-removal command is supplied.

For diagnostics only, launch with `--profile-events` and redirect stderr under `.build`. Events contain uptime, pane and exposure state, not readings or process names. `scripts/measure.py --events PATH` records the window exposure during a run so covered and visible measurements are not confused.

## Hygiene

`.build/`, `dist/`, local screenshots and Python bytecode are ignored. Only reviewed aggregate measurements and a reviewed overview screenshot with generic process names and no executable paths are published. View settings use normal macOS preferences in `dev.taskglass.app`; tests use memory-only preferences. `rm -rf .build dist` removes generated project output. macOS manages its own launch/driver/compiler caches and diagnostics.

## Build-engine verification

On the development Swift 6.4 Command Line Tools, the default swiftbuild engine compiled with SDK 27 but recorded SDK 14 in LC_BUILD_VERSION. An identical native-engine build recorded minimum OS 14 and SDK 27 correctly. The build script selects `--build-system native` for the preview. Swift 6.4 warns that this engine is deprecated, so this workaround needs revisiting when the upstream engine is corrected or native support is removed. CI uses Swift toolchains supplied by its standard macOS runners.

The first CI pass found that the macOS 15 runner has Swift 6.1. Core tests passed, but an unnecessary tools-version 6.2 manifest requirement blocked the app build. The manifest now requires Swift 6.0; no 6.2-only manifest API is used. Release validation still requires SDK 26+ metadata.
