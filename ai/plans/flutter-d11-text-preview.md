# Flutter D11 Text Preview

**Status:** Completed

## Feature References

- Primary: `App Quick Printing` / `Quick Print`
- Primary: `Label Layout and Preview` / `Physical Label Canvas`
- Primary: `Label Layout and Preview` / `Text Formatting`
- Supporting: `Label Layout and Preview` / `Rendering and Preview`
- Supporting: `Label Layout and Preview` / `Reusable Label Description`

## Goal

Introduce an Android and Linux Flutter application that composes one centered
line of text for the approved D11 12 x 40 mm label, previews it in portrait or
landscape reading orientation, and deterministically produces the native
96 x 320 pixel label raster without using ImageMagick or Bluetooth.

## Acceptance Criteria

- The repository contains one Flutter application under `app/` with Android and
  Linux hosts and no third-party runtime packages.
- The first screen provides a text field, portrait/landscape control, physical
  label dimensions, and a live label preview at phone and desktop viewport
  sizes.
- D11 physical media stays fixed at 12 x 40 mm and 96 x 320 native pixels.
- Portrait content uses a 96 x 320 logical canvas. Landscape content uses a
  320 x 96 logical canvas and is transformed clockwise into the unchanged
  96 x 320 native raster without mirroring or clipping.
- Text is horizontally and vertically centered, remains on one line, and uses
  the largest integer font size that fits within explicit padding.
- Empty text produces a valid blank preview. Content that cannot fit at the
  minimum size reports overflow rather than cropping, wrapping, or stretching.
- Label output uses a bundled, offline font with its license recorded in the
  repository.
- Automated tests cover geometry, orientation transforms, fitting, responsive
  UI behavior, and the exact final native raster dimensions without Bluetooth
  or printer hardware.
- The approved D11 facts in the app have an automated parity check against the
  authoritative backend capability registry.

## Out of Scope

- Bluetooth discovery, permissions, connection, transport, and printing.
- Porting the Niimbot packet protocol or printer command state machine to Dart.
- Models or label stocks other than D11 with `d-12x40` media.
- Multiple lines, explicit font controls, templates, icons, persistence, AI,
  image import, or arbitrary rotations.
- iOS and macOS host projects; the application boundaries must not prevent
  adding their native Bluetooth transports later.

## Current State

- The Python CLI prints a prepared raster image but has no text composer or
  graphical preview.
- `backend/src/niimstudio/domain/printers.toml` records D11 at 203 DPI with
  `d-12x40` media, while domain tests establish normal printable bounds of
  96 x 320 pixels.
- Existing CLI validation uses the D11 protocol-width ceiling of 240 pixels and
  does not constrain an input image to the selected physical label dimensions.
- The repository has no Flutter or Dart project, and the workstation initially
  has no Flutter SDK on `PATH`.

## Contracts and Decisions

### Project Boundary

- Add one Flutter package at `app/`; keep the existing Python package at
  `backend/` unchanged except for a parity test if needed.
- Keep domain geometry independent of Flutter widgets. Rendering may depend on
  `dart:ui`; screen composition stays in the UI layer.
- Do not add a BLE package in this slice. A later application-owned transport
  interface will separate protocol behavior from Android, BlueZ, and future
  CoreBluetooth adapters.

### Geometry

- `LabelContentOrientation` means how a person reads the composed content. It is
  separate from the capability registry's physical `PrintOrientation`.
- Native D11 coordinates are cross-feed width 96 and feed length 320.
- Portrait maps logical coordinates directly to native coordinates.
- Landscape maps a 320 x 96 logical canvas clockwise into 96 x 320 native
  coordinates. Corner-marker tests define the exact transform.
- Geometry uses integer pixels after the backend-approved millimetre-to-pixel
  conversion. This slice consumes the approved 96 x 320 result rather than
  introducing another rounding policy.

### Rendering

- Bundle the static Barlow Condensed Bold font under SIL Open Font License 1.1
  and reference it by an app-specific family name.
- Measure actual glyph bounds, binary-search the largest fitting integer font
  size, and center the measured ink rectangle rather than only its baseline.
- Composite onto white, convert to luminance, and apply an explicit fixed
  threshold with dithering disabled.
- The preview and native raster consume the same composed label result.

### Capability Parity

- Store only the D11 preview contract needed by this slice in a versioned JSON
  asset.
- Add an automated backend parity test that compares that contract with
  `printers.toml`; the TOML registry remains authoritative until a later shared
  capability format is approved.

## Implementation Steps

- [x] Bootstrap the Flutter Android/Linux package without third-party runtime
  dependencies and record SDK constraints.
- [x] Red: add a backend parity test for the D11 app contract and confirm it
  fails because the contract asset is absent.
- [x] Green: add the smallest versioned D11 capability asset and make parity
  pass.
- [x] Red: add pure geometry tests for portrait/landscape logical dimensions,
  fixed native dimensions, and clockwise corner mapping; confirm failure.
- [x] Green: implement immutable label geometry and content orientation values.
- [x] Red: add renderer tests for blank output, centered text, largest fitting
  size, no wrapping, overflow, monochrome conversion, and 96 x 320 output;
  confirm failure.
- [x] Green: add the bundled font and implement the smallest deterministic text
  composer and native-raster renderer.
- [x] Red: add widget tests for live text updates, orientation changes, visible
  physical dimensions, and phone/desktop layouts; confirm failure.
- [x] Green: implement the focused composer screen and preview.
- [x] Refactor boundaries and names while keeping backend, Dart, and Flutter
  tests green.

## Verification

- [x] `git diff --check`
- [x] `poetry --directory backend run python -m compileall -q src/niimstudio`
- [x] `poetry --directory backend check`
- [x] `poetry --directory backend run pytest -c pyproject.toml`
- [x] `poetry --directory backend run ruff check src/niimstudio tests`
- [x] `poetry --directory backend run ruff format --check src/niimstudio tests`
- [x] From `app/`: `flutter analyze`
- [x] From `app/`: `flutter test`
- [x] From `app/`: `flutter build apk --debug`
- [x] From `app/`: `flutter build linux --debug`
- [x] Verify feature references, paths, font license, commands, and platform
  claims against the resulting tree.

Verification notes:

- Python 3.14 support was added to the backend project contract so the Poetry
  verification environment uses the installed system interpreter. All 162
  backend tests pass with 89.86% coverage.
- Android assembly passed with Platform 36, Build Tools 36.0.0, and NDK
  `28.2.13676358` in a temporary user-owned SDK.
- Linux assembly passed with the installed CMake, Clang, Ninja, and GTK
  development packages.

## Completion

- [x] Update the referenced feature checklists only for behavior completed by
  this slice; keep Bluetooth printing and other platforms unchecked.
- [x] Record any unavailable Android or Linux build check with its exact missing
  host dependency.
- [x] Include no generated caches, local labels, build output, or unrelated
  files.
