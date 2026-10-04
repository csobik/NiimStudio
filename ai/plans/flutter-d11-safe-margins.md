# Flutter D11 Safe Margins

**Status:** In progress

## Feature References

- Primary: `Label Layout and Preview` / `Text Formatting` / content safe-margin
  preset
- Supporting: `Label Layout and Preview` / `Text Formatting` / automatic font
  sizing
- Supporting: `Label Layout and Preview` / `Rendering and Preview` / shared
  layout and clipping bounds
- Supporting: `App Quick Printing` / `Quick Print` / visible common settings

## Goal

Let a user keep automatically fitted D11 text visibly away from label edges by
choosing one of three physical safe-margin presets. The default balanced margin
and every user selection must affect fitting, preview, and printed raster
identically in portrait and landscape.

## Acceptance Criteria

- The composer exposes exactly these symmetric content-margin presets:
  `Tight` at 1 mm, `Normal` at 1.5 mm, and `Wide` at 2.5 mm.
- A new composer session starts with `Normal` selected.
- Presets are represented by a typed value rather than UI strings or arbitrary
  pixel values.
- A preset's millimetres are converted independently on each logical axis using
  the selected canvas's approved physical and pixel dimensions, rounded to the
  nearest whole pixel. For the current 203 DPI D11 12 x 40 mm contract, `Normal`
  resolves to 12 pixels on every edge.
- Automatic font sizing continues to choose the largest integer font whose
  measured ink bounds fit inside the selected safe area.
- Ink remains centered on the full physical label; no glyph is cropped,
  stretched, wrapped, or silently shrunk below the existing minimum font size.
- Content that cannot fit inside the selected safe area reports the existing
  overflow state and cannot be printed.
- Changing the preset immediately invalidates the previous printable raster,
  starts a new render, and enables Print only after the latest render succeeds.
- The on-screen preview and the immutable native raster captured for printing
  come from the same render with the same selected preset.
- The three controls and their selected state are usable with touch, keyboard,
  pointer, and screen-reader semantics at current phone and desktop breakpoints.
- Hardware-independent tests cover conversion, boundaries, fitting, default
  selection, rerendering, stale-raster prevention, and print eligibility.
- A manual D11 smoke test confirms that the default `Normal` preset prints
  `3,5x016` in landscape with visible space on all sides.

## Out of Scope

- Free-form margin entry, independent margins per edge, negative margins,
  printer calibration offsets, or automatic compensation for media-feed skew.
- Explicit or per-line font-size controls, font family/weight selection,
  multiple lines, line spacing, alignment controls, templates, and icons.
- Persisting the selected preset between app launches or changing the selected
  printer, label stock, density, quantity, or BLE protocol.
- Models and media other than the current D11 12 x 40 mm composer.

## Current State

- `app/lib/src/rendering/label_text_renderer.dart` owns auto-fit and currently
  receives one fixed `paddingPx`, defaulting to 8 pixels (approximately 1 mm on
  the D11). The setting is not expressed in physical units and cannot be changed
  from the composer.
- `_fitsInk` subtracts the same fixed pixel padding from both dimensions, while
  `_placeInk` centers fitted ink on the full logical canvas. The preview and
  native raster already share this rendered result.
- `D11PreviewCapability` in
  `app/lib/src/adapters/d11_capability_loader.dart` exposes 203 DPI and the
  approved 12 x 40 mm, 96 x 320 pixel contract. `D11LabelGeometry` exposes each
  orientation's logical physical and pixel dimensions.
- `app/lib/src/ui/label_composer_screen.dart` invalidates its printable raster
  for text and orientation changes using a monotonically increasing render
  revision, but has no formatting state or margin controls.
- Renderer tests currently assert the fixed 8-pixel boundary. Widget tests cover
  orientation, stale renders, responsive layout, and print eligibility, and can
  be extended without Bluetooth hardware.
- The current BLE-printing worktree must be reconciled before this plan starts;
  this plan changes only composition and consumes the existing immutable raster
  printing boundary.

## Contracts and Decisions

### Margin Value

- Add an immutable typed preset value in the composition/domain boundary with a
  stable identity, display label, and millimetre value. Do not store a raw
  localized UI label as renderer input.
- Keep the preset symmetric. Convert horizontal and vertical insets separately
  from `logicalSizePx / displaySizeMm`; this preserves the authoritative rounded
  raster dimensions and supports unequal axis density without introducing a
  second media-size calculation.
- Use nearest-integer rounding and validate that twice each inset leaves a
  positive content area. Invalid geometry is a programming/configuration error,
  not an overflow result.

### Rendering

- Pass the selected preset through `LabelComposer.render`; do not recreate or
  mutate a renderer when the selection changes.
- Replace the renderer's constructor-level pixel padding with per-render safe
  area insets. `fitsAtFontSize` must use the same preset so tests and future
  diagnostics cannot diverge from normal rendering.
- Keep the existing minimum font size, measured-glyph fitting, centering,
  thresholding, orientation transform, and `RenderedLabel` failure contract.

### UI State

- Own the selected preset alongside text and orientation in
  `LabelComposerScreen`. A preset change increments the same render revision and
  clears `_printableRaster` before requesting the replacement render.
- Use the existing visual language and a compact three-choice control. Show both
  the preset name and millimetre value without adding a settings screen.
- Do not persist the choice in this slice; `Normal` is restored when a new screen
  instance is created.

## Implementation Steps

- [x] Red: add pure geometry/domain tests for all preset values, axis-aware
  millimetre-to-pixel conversion, nearest-pixel rounding, and rejection of a
  non-positive content area; run them and confirm the contract is missing.
- [x] Green: add the typed presets and smallest safe-area conversion needed to
  satisfy those tests.
- [x] Refactor the value and conversion names while keeping geometry tests green.
- [x] Red: update renderer tests to pass a preset and add boundaries proving
  `Normal` stays at least 12 pixels from every D11 edge in both orientations,
  wider margins cannot increase the selected font size, and impossible content
  still reports overflow; confirm failure against fixed `paddingPx` behavior.
- [x] Green: pass the preset through `LabelComposer`, replace fixed pixel padding
  with per-render insets, and keep auto-fit and centering behavior unchanged.
- [x] Refactor renderer helpers while keeping exact orientation and raster-byte
  tests green.
- [x] Red: add widget tests for the default `Normal 1.5 mm` selection, all three
  accessible choices, immediate rerender on change, disabled Print while that
  render is pending, and printing only the raster produced for the latest
  selection; confirm the focused failures.
- [x] Green: add the compact margin control and composition state to the existing
  phone/desktop screen without changing BLE ownership or print orchestration.
- [x] Refactor test fakes and screen parameters while all focused and existing
  Flutter tests remain green.
- [ ] Run the automated verification matrix, then print one landscape
  `3,5x016` label with `Normal` on D11 and record the observed edge spacing.

## Verification

- [x] `git diff --check`
- [x] From `app/`: `dart format --output=none --set-exit-if-changed lib test`
- [x] From `app/`: `flutter analyze`
- [x] From `app/`: `flutter test`
- [x] From `app/`: `flutter build apk --debug`
- [x] From `app/`: `flutter build linux --debug`
- [ ] On Android or Linux, print landscape `3,5x016` with `Normal`; verify one
  96 x 320 D11 raster prints without clipping and with visible margins on all
  physical edges.
- [x] Verify feature wording, plan paths, values, and commands against the final
  tree.

## Completion

- [ ] Mark the referenced content safe-margin feature item complete only after
  controls, rendering, printing, and hardware smoke verification are complete.
- [ ] Record the tested platform, D11 model/firmware when available, label stock,
  selected preset, resolved pixel insets, and observed physical result.
- [ ] Reconcile the preceding BLE-printing plan without changing unrelated
  incomplete feature items.
- [ ] Include no generated caches, local labels, build output, hardware IDs, or
  unrelated files.

## Verification Notes

- Automated result: all 73 Flutter tests pass. Flutter analysis, Dart formatting,
  Android and Linux debug builds, IDE inspections, and diff whitespace checks
  pass.
- The D11 12 x 40 mm contract resolves `Normal` to 12 logical pixels on every
  edge in portrait and landscape.
- The physical D11 print smoke test remains unverified; no hardware result or
  model/firmware observation was recorded.
