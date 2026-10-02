# AI-Assisted Composition

**Status:** Proposed, Post-MVP

AI may shorten uncommon composition tasks, but it is not part of label geometry,
Bluetooth control, or the reliable basic print path. Text entry, formatting,
templates, icons, preview, and printing remain usable without AI.

## Natural-Language Drafts

- [ ] Accept an optional request such as "print a label with a light-bulb icon
  and the caption Led ABC" and turn it into a structured label draft.
- [ ] Prefer a matching built-in template and curated icon over generating new
  graphical content.
- [ ] Show the interpreted text, template, icon, orientation, and formatting in
  the normal editor and preview before printing.
- [ ] Require explicit user confirmation; AI cannot connect to a printer or start
  a print job directly.
- [ ] Pass every AI-produced draft through the same schema, physical-layout,
  overflow, and raster validation as a manually created label.

## Optional Network Use

- [ ] Clearly identify when an AI provider requires Internet access and obtain
  confirmation before sending label content to it.
- [ ] Do not send printer identifiers, Bluetooth addresses, saved labels, or
  unrelated local data to an AI provider.
- [ ] Return to the normal editor when AI is unavailable, times out, or produces
  an invalid draft; basic printing must remain available.

## Generated Graphics

- [ ] Treat custom AI-generated icons as a later capability than selecting from
  the curated icon catalog.
- [ ] Convert generated graphics into a bounded, validated local asset and show
  the exact monochrome preview before it can be printed.
- [ ] Never execute generated code, template expressions, scripts, or untrusted
  active document content.
