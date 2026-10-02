# App Quick Printing

**Status:** Proposed

NiimStudio should make the common task possible from an Android phone at the
location where the label is needed or from a Linux computer. The primary
workflow is opening the app, entering text, checking the preview, and printing
without a cloud account.

## Quick Print

- [ ] Provide one focused app screen with a text field, label preview, and print
  action.
- [ ] Keep common settings such as printer, label stock, orientation, and copy
  count available without requiring the user to understand raster dimensions.
- [ ] Restore the most recently confirmed printer and label settings while
  making the active selections visible before printing.
- [ ] Complete a previously configured one-line label without navigating a
  general-purpose graphic editor.
- [ ] Report connection, printing, completion, and actionable failure states in
  the app.

## Local Bluetooth Operation

- [ ] Discover, select, connect to, print on, and disconnect from one nearby
  supported printer directly from the device over Bluetooth Low Energy.
- [ ] Explain and request only the Bluetooth permissions required by the mobile
  or desktop platform.
- [ ] Handle permission denial, Bluetooth being disabled, the app moving to the
  background, connection loss, cancellation, and operation timeouts.
- [ ] Keep text composition, preview, and printing available without a server,
  cloud account, or Internet connection.
- [ ] Never send label contents or printer identifiers to a remote service as
  part of the basic print workflow.

## Device Support

- [ ] Support Android and Linux as the initial application platforms with the
  same label composition, preview, and printing behavior.
- [ ] Keep platform Bluetooth integration behind an explicit transport boundary
  so Android can use its system BLE APIs and Linux can use BlueZ without
  changing label or printer-protocol behavior.
- [ ] Keep iOS and macOS as planned follow-up platforms using their native
  Bluetooth integration; do not claim support before their complete workflows
  are tested on real devices.
- [ ] Make the app usable with touch on Android and keyboard and pointer input on
  Linux.
- [ ] Use the same approved printer, label, density, and protocol facts as the
  existing capability registry, with automated parity tests where source code
  cannot be shared directly.
- [ ] Preserve the existing command-line image-printing workflow while the
  mobile workflow is introduced.
