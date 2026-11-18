# Web App — Agent Guidelines

## Purpose

Single-page web application mirroring the iOS/Android NFC SpoolLink apps. No build step — vanilla ES modules
served directly from the filesystem or any static host.

## File Layout

```
web-app/
  public/
    index.html   — full DOM skeleton: tabs, modals, forms, toast
    style.css    — all styles, CSS custom properties, dark-mode via @media
    app.js       — all logic as a single ES module (no imports)
```

## Architecture

- **No framework.** Plain DOM APIs throughout.
- **State** lives in the `state` object (top-level, not exported).
- **API** calls go through the `SpoolmanAPI` class; mirrors `SpoolmanAPI.swift` exactly.
- **Settings** are read/written via the `Settings` object backed by `localStorage`.
- **NFC** uses the [Web NFC API](https://developer.mozilla.org/en-US/docs/Web/API/Web_NFC_API) (`NDEFReader`). Only
  available in Chrome on Android; all other features work everywhere. Check `'NDEFReader' in window` before using.
- **Rendering** is imperative: each tab/modal has a dedicated `render*` function that clears and rebuilds its DOM.
  No virtual DOM or diffing.
- **Modals** are fixed-position bottom sheets. `showModal(id)` / `hideModal(id)` toggle the `.hidden` class and
  manage the shared `#modal-overlay`.

## Key Functions

| Function | What it does |
|---|---|
| `processTag(payload, uidHex)` | Core sync: link tag to current spool, clean others — mirrors `SpoolmanViewModel.processTag` |
| `processAssignment(spool, uidHex, payload)` | Assign tag to specific spool — mirrors `processAssignment` |
| `createSpoolFromTag(uidHex, payload, meta)` | Vendor find-or-create → filament create → spool create |
| `removeTag(spool, uidHex)` | Unlink one UID from the selected store |
| `removeAllTags(spool)` | Unlink all UIDs from the selected store |
| `SpoolmanAPI.migrateTags(target)` | Move every link between stores, following the firmware's `spoollink_migrate.py` |
| `fetchSpools(reset)` | Paginated spool list (page size 20) |
| `tagFields(payload)` | Extract `{ label, value, colorHex? }` fields from a tag payload for display |
| `renderTagDetailTable(payload, uidHex)` | Build the tag detail DOM table using `tagFields()` |
| `renderSpools()` | Rebuild spools tab |
| `renderHistory()` | Rebuild history tab |
| `showSpoolDetail(spool)` | Populate and open `#modal-spool` |
| `showAssignModal(payload, uidHex)` | Open `#modal-assign` with live search |
| `showCreateModal(payload, uidHex)` | Open `#modal-create` pre-filled from tag metadata |
| `showPresetEditor(title, key)` | Open preset editor for `brands`/`materials`/`variants` |

## Data Model

Spoolman API returns snake_case JSON. Key fields:

- `spool.extra.card_uids` — JSON-encoded comma-separated string of uppercase hex UIDs (e.g., `"\"AABBCCDD,11223344\""`)
- `spool.filament.color_hex` — 6-char hex without `#`
- `spool.filament.vendor.name` — brand name
- `spool.remaining_weight` — grams, may be null
- `spool.registered`, `spool.last_used` — ISO 8601 strings

Helper `spoolTagUIDs(spool)` returns `string[]` of UID hex strings from the selected store (`Settings.tagStore`):
`extra.card_uids` or, for `native`, `spool.tags[].uid`.

## card_uids Field

In the `card_uids` store, UIDs are stored in `spool.extra.card_uids` as a Spoolman custom field. The value is
JSON-encoded (double-serialized) as required by the custom field API:

```js
body: JSON.stringify({ extra: { card_uids: JSON.stringify(uids.join(',')) } })
```

Call `SpoolmanAPI.ensureCardUidsField()` before the first write to guarantee the custom field exists on the server.

## NFC Card UID Normalisation

Web NFC `serialNumber` is `"04:ab:cd:ef"` (colon-separated, lowercase).
Normalise with: `serialNumber.replace(/:/g, '').toUpperCase()` → `"04ABCDEF"`.

## OpenSpool NDEF Format

Record type: `mime`, media type: `application/json`.
Root object must have `protocol === "openspool"`.
Parsed by `parseOpenSpoolRecord(record)` → returns structured object or `null`.

## Styling Rules

- Use CSS custom properties (`--blue`, `--green`, `--red`, etc.) for all colours.
- Dark mode via `@media (prefers-color-scheme: dark)` overriding the same variables.
- No inline styles except for dynamic values (swatch colours, flex widths). Use class names.
- Mobile-first; `max-width: 600px` centered on desktop.

## Do / Don't

- **Do** keep all logic in `app.js` — no splitting into modules unless the file becomes unmanageable (>2000 lines).
- **Do** use the `el(tag, attrs, ...children)` helper for DOM construction; avoid `innerHTML` except for
  trusted SVG strings via `parseHTML()`.
- **Don't** add a build step, bundler, or npm dependencies.
- **Don't** persist scan history across page reloads — session only.
- **Don't** add features the iOS/Android apps don't have without noting it here.
