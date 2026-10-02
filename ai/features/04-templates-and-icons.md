# Templates and Icons

**Status:** Proposed

NiimStudio should cover repeated label types without becoming a general-purpose
graphic editor. Templates provide a small number of understandable layouts and
accept only the data needed by that layout.

## Built-In Templates

- [ ] Provide initial templates for centered text, title and subtitle, and icon
  with caption.
- [ ] Let each template declare its required values, optional values, supported
  formatting, and layout constraints.
- [ ] Validate substituted values and show the completed preview before printing.
- [ ] Keep template geometry in physical label coordinates and pass the result
  through the same fitting and native-raster validation as manually composed
  labels.
- [ ] Allow a configured label to be saved locally as a named favorite without
  requiring an account.

## Icon Catalog

- [ ] Include a curated, locally available catalog of simple monochrome icons,
  starting with common symbols such as a light bulb.
- [ ] Record the license and attribution requirements for every bundled icon.
- [ ] Let the user search or browse icons and configure supported position, size,
  and spacing choices.
- [ ] Scale and rasterize icons deterministically while preserving aspect ratio
  and rejecting content outside the printable area.
- [ ] Keep icon selection and printing fully functional offline.

## Safe Extensibility

- [ ] Store templates and favorites as bounded, versioned, validated data rather
  than executable code.
- [ ] Treat import, export, sharing, and arbitrary user-supplied vector graphics
  as separate capabilities requiring explicit validation and resource limits.
