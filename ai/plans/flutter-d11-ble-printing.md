# Flutter D11 BLE Printing

**Status:** In progress

## Feature References

- Primary: `App Quick Printing` / `Quick Print`
- Primary: `App Quick Printing` / `Local Bluetooth Operation`
- Supporting: `App Quick Printing` / `Device Support`
- Supporting: `Label Layout and Preview` / `Physical Label Canvas`

## Goal

Let an Android or Linux user explicitly find one nearby D11, select it, and
print the latest valid 96 x 320 raster from the Flutter composer. The app waits
for protocol completion, reports actionable progress or failure, and always
cleans up notifications and the BLE connection.

## Acceptance Criteria

- The app uses exactly `universal_ble` 2.3.0 under its BSD-3-Clause license.
- Scanning starts only after a user action, is time-bounded, and distinguishes
  D11 from D110 and D11_H advertised names.
- The user explicitly selects one discovered D11 for the current app session.
- Print is enabled only for a selected device and the latest completed,
  non-empty, non-overflowing raster.
- The first slice prints one copy at density 3 and label type 1.
- Packet framing, checksum validation, fragmented notifications, unrelated
  responses, unsupported/error responses, command timeouts, row encoding, and
  the complete print sequence match the Python reference implementation.
- The app connects, discovers exactly one characteristic with read,
  write-without-response, and notify properties, subscribes, serializes writes,
  prints, unsubscribes, and disconnects on success, error, or cancellation.
- A successful message appears only after page completion, reported page count,
  and acknowledged end-print commands.
- Visible states distinguish scanning, connecting, printing rows, waiting for
  the printer, success, permission/adapter failures, protocol failures, timeout,
  and disconnection.
- Automated tests use fake transports and require no Bluetooth hardware.
- Manual Android and Linux smoke tests print the centered `3,5x016` landscape
  label on the available D11.

## Out of Scope

- Models other than D11, multiple simultaneous printers, automatic selection,
  saved devices, reconnect in the background, density/copy controls, printer
  information, heartbeat, RFID, and firmware-specific capability inference.
- iOS and macOS host projects.
- Templates, icons, multiple text lines, print history, and AI composition.

## Current State

- The Flutter app creates a validated D11 native raster but has no discovery,
  transport, packet protocol, print use case, or print UI.
- The Python implementation in `backend/src/niimstudio/nimmy/` is the reference
  for discovery identity, characteristic matching, packet framing, command
  response offsets, raster rows, polling, deadlines, and cleanup.
- The Python transport discovers characteristics by properties rather than
  fixed service or characteristic UUIDs.
- The D11 hardware is available for an opt-in smoke test after automated tests
  pass.

## Contracts and Decisions

### Pure Protocol

- `NiimbotPacket` owns byte framing and checksum validation.
- `NiimbotPacketDecoder` incrementally buffers fragmented notifications,
  discards noise before a header, preserves a trailing single header byte, and
  reports malformed complete packets.
- `D11PrinterTransport` exposes connected notification bytes and serialized raw
  writes without importing Flutter or `universal_ble`.
- `D11Printer` owns one in-flight command, expected response types, protocol
  errors, deadlines, row encoding, print polling, and interrupted-job cleanup.

### BLE Adapter

- Pin `universal_ble: 2.3.0`; do not use an open-ended compatible range.
- Keep static plugin APIs behind `UniversalBleD11Gateway` so application and
  widget tests depend on small ports.
- Match advertised names using the existing normalized longest-prefix model
  semantics; this slice exposes only exact D11-family matches excluding D110 and
  D11_H.
- Discover all services and require exactly one characteristic containing read,
  notify, and write-without-response.
- Subscribe before the first command, write without response, and serialize all
  rows. MTU optimization is optional; correctness must not depend on it.

### UI State

- A completed render is tagged with a monotonically increasing composition
  revision. Print captures the current immutable raster and cannot switch to a
  later or earlier render mid-job.
- Printer and print state live in a focused controller injected into the widget;
  widgets do not call the BLE plugin directly.
- Discovery and print status are persistent accessible text, not only snackbars.

## Implementation Steps

- [x] Add the exact BLE dependency, platform declarations, and license notice.
- [x] Red: add shared packet vectors and Dart packet/decoder tests; confirm the
  missing implementation fails.
- [x] Green: implement packet framing and incremental response decoding.
- [x] Red: add raster-row and complete print-sequence tests over a fake transport,
  including timeout, rejected acknowledgement, protocol error, and cleanup.
- [x] Green: implement the transport port and D11 print state machine.
- [x] Red: add discovery identity, characteristic selection, lifecycle, and
  exception-translation tests around a fake BLE platform boundary.
- [x] Green: implement the `universal_ble` Android/Linux adapter and required
  Android permissions.
- [x] Red: add controller and widget tests for scan, selection, disabled print,
  progress, success, retry, stale render, and failure states.
- [x] Green: connect discovery and printing to the focused composer UI.
- [x] Refactor while all backend, Dart, Flutter, and fake-transport tests remain
  green.
- [ ] Run Android and Linux D11 hardware smoke tests and record the result.

## Verification

- [x] `git diff --check`
- [x] `poetry --directory backend run python -m compileall -q src/niimstudio`
- [x] `poetry --directory backend check`
- [x] `poetry --directory backend run pytest -c pyproject.toml`
- [x] `poetry --directory backend run ruff check src/niimstudio tests`
- [x] `poetry --directory backend run ruff format --check src/niimstudio tests`
- [x] From `app/`: `dart format --output=none --set-exit-if-changed lib test`
- [x] From `app/`: `flutter analyze`
- [x] From `app/`: `flutter test`
- [x] From `app/`: `flutter build apk --debug`
- [x] From `app/`: `flutter build linux --debug`
- [x] Android D11 manual print smoke test.
- [ ] Linux D11 manual print smoke test.

## Completion

- [ ] Update only feature checklist items fully completed by this slice.
- [ ] Record package version, license, hardware, firmware if available, native
  raster dimensions, and observed print outcome.
- [ ] Include no generated caches, local labels, build output, hardware IDs, or
  unrelated files.

## Verification Notes

- Automated result: 73 Flutter tests and 162 backend tests pass; backend coverage
  is 89.86%. Flutter analyze, Dart format, Ruff, Poetry check, compileall, and
  diff whitespace checks pass.
- Linux debug bundle builds successfully after clearing a stale CMake cache.
- Android SDK Platform 36 and Build Tools 36.0.0 were installed system-wide; the
  debug APK was installed on a phone successfully.
- The implementation uses `universal_ble` 2.3.0 (BSD-3-Clause), density 3,
  quantity 1, and the D11 native raster size of 96 x 320 pixels.
- The user confirmed successful Android-to-D11 printing. The exact firmware and
  edge spacing were not recorded; Linux hardware printing remains unverified.
