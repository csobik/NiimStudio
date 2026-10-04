# Label Layout and Preview

**Status:** Proposed

NiimStudio should turn text and simple formatting into a printer-ready label.
Users work in physical label terms; the application owns pixel dimensions,
content rotation, monochrome conversion, and device raster orientation.

## Physical Label Canvas

- [x] Build the canvas from the selected printer, label stock, printable bounds,
  and DPI in the capability registry rather than from a protocol-wide raster
  limit.
- [x] Define `portrait` as the short physical edge being horizontal and
  `landscape` as the long physical edge being horizontal in the user-facing
  preview.
- [x] Transform the logical portrait or landscape canvas into the printer's
  native cross-feed and feed raster without asking the user to rotate a raw
  image.
- [x] Show the selected physical dimensions and orientation in the preview.
- [ ] Validate the final native raster against the selected physical label before
  connecting to a printer.

## Text Formatting

- [ ] Support one or more text lines with font family, size, weight, horizontal
  alignment, vertical alignment, and line spacing.
- [ ] Let users select a small content safe-margin preset expressed in physical
  units, apply it identically to automatic fitting, preview, and the final
  printer raster, and start new labels with a balanced non-edge default.
- [ ] Allow different font sizes for individual lines, including a deterministic
  ratio such as a subtitle at half the title size.
- [x] Bundle approved fonts so the same label does not depend on fonts installed
  on the phone or desktop host.
- [x] Offer automatic font sizing that finds the largest size fitting the
  content area.
- [ ] Keep an explicitly requested font size unchanged and report overflow
  before printing unless the user explicitly enables proportional shrinking.
- [x] Never silently crop, stretch, wrap, or rotate text to make it fit.

## Rendering and Preview

- [x] Render labels inside the application without ImageMagick, shell commands,
  or another externally installed executable.
- [x] Use an explicit alpha-compositing, grayscale, threshold, and dithering
  policy to produce a deterministic one-bit printer raster.
- [x] Make the on-screen preview represent the same layout and clipping bounds
  used to create the printer raster.
- [x] Allow previewing and correcting a label without connecting to the printer
  or consuming label stock.
- [x] Cover physical geometry, orientation transforms, fitting, overflow, and
  final raster bytes with hardware-independent automated tests.

## Reusable Label Description

- [ ] Represent label content and formatting as a validated, versioned,
  non-executable label description independent of Bluetooth and UI state.
- [ ] Ensure mobile UI, future templates, and an optional text-oriented CLI all
  use the same layout semantics even when their platform renderers are separate.
