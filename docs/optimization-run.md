# Optimization and cleanup record

Baseline: v0.1.1, `c743e4f`. Implementation checkpoint: `5e83375`. No dependencies or global installations were added.

The user requested six hours of continuous optimization and rejected scheduled continuation. The recurring automation was deleted. Work began at 05:53:30 UTC on 2026-10-30, paused for 51 seconds at 10:14:39, and resumed at 10:15:30. At 11:45:30 the user explicitly paused optimization for cleanup and packaging. Approximately **5 hours 51 minutes** of active work accumulated in this continuous run. Six hours was not completed. An earlier 14-minute pass is separate and does not shorten that timer. No scheduled waiting is counted.

## Retained changes

- Property-scoped Observation replaces broad monitor notifications. Private staging buffers do not invalidate visible views, and stable navigation/count values publish only when changed.
- Process rows share immutable metadata. Family members share the source sample through integer indices. Compact numeric keys and cached localized name order reduce sorting work without changing exact UInt64 memory ordering.
- Native tables reuse visible cells and positional outline items. Expansion and selection follow process/app identity. Small bounded pools release retired data, and unchanged labels and numeric readings avoid repeated formatting.
- List and inspector icon caches use separate pixel sizes and bounded eviction. User-name lookups stay off the main thread.
- Hardware handles and sensor metadata are reused. Slow hardware fields keep their ten-second cadence; supported CPU/GPU/ANE counter semantics and availability remain unchanged.
- Each chart draws grid, baseline, fill and traces in one native Core Graphics view. Chart scales and unchanged inputs avoid redundant work. Core maps reuse label measurements and drawing geometry.
- Rounded bands draw their backgrounds directly; process tables cover only their outside corners instead of compositing the entire table through a mask. Layout, colors, data and scrolling remain intact.
- Safe `-Osize` plus full LTO reduces the executable. Reflection, unwinding and crash symbols remain available in the local unstripped build and dSYM.

See [current measurements](../measurements/README.md) for whole-app CPU, memory, size and limitations. Component benchmarks are not whole-app speedups. Detailed historical passes remain in Git history.

## Rejected experiments

A Canvas renderer lowered CPU but substantially increased graphics memory, so native drawing replaced it. Collinear path simplification, custom process text drawing and altered outline clipping did not justify their complexity or visual differences. Lazy page construction, forced chart layers, explicit drawing bounds, hidden scroll effects and a replacement native scroll container did not improve CPU-page memory. Diagnostic removal of tables or heatmaps was never adopted. All resource views and processes remain available.

## Verification

The existing ABI, sampling, accelerator, sorting and lifecycle checks passed after the final code changes. A busy single-thread fixture measured about 100% CPU. Real six-second Metal and Core ML workloads verified GPU PID attribution and shared ANE group time on the M5 Pro. Release build, ARM64/macOS 14 metadata, ad-hoc signature, ZIP/DMG integrity and extracted executable equality passed locally.

Native inspection confirmed the dashboard and CPU navigation; deterministic rendering checked the table's rounded edges. The accessibility tool timed out when traversing the long live process list, so that attempt is not counted as a successful end-to-end scrolling check. Earlier native outline fixtures covered selection, expansion and re-ranking. Broader physical Mac and accessibility coverage remains outstanding.

## Cleanup

Removed obsolete plot implementations, unused theme/history declarations and superseded design audits. Consolidated measurements into the matched before/after aggregates and one methodology document. Source-reference and C warning checks found no further safe unused-code removals; framework callbacks and older-OS fallbacks remain necessary. Generated experiments and old local release archives are removed after preserving the reviewed aggregates. Build caches, the current app, archives and symbols stay scoped to `.build` and `dist`.

The native SwiftPM engine is still selected because the installed Swift 6.4 default engine recorded incorrect SDK metadata. Its deprecation warning is a documented compatibility issue, not unused code. The packaging commands remain compatible with the supported CI macOS versions.
