# Design Guidelines

## iOS (SwiftUI)

### Code Design

- Layering: `Services` (I/O and system integrations), `ViewModels` (workflow/state orchestration), `Models`
  (API and app data), `Formats` (tag-format parsing/mapping), `Views` (rendering and user actions).
- NFC read path: `NFCManager` reads NDEF records, delegates record parsing to `Formats/TagFormatParser`, returns
  the first supported payload, then falls back to `RawNDEFTagPayload` when no parser matches.
- Tag abstraction: `NFCTagPayload` is the unified interface for scan display and spool workflows; concrete
  implementations include `OpenSpoolTagPayload` and `RawNDEFTagPayload`.
- Metadata normalization: `FilamentMetadata` is the shared value type for pre-filling create-spool UI and
  building Spoolman create requests.
- Spoolman integration: `SpoolmanAPI` owns HTTP calls and request/response encoding; `SpoolmanViewModel` owns
  business flow (sync current spool, cleanup duplicates, assignment, create spool, refresh affected spools).
- View composition: scan/history/spools/settings are independent SwiftUI screens bound to one observable view
  model; detail cards consume model data and format-derived fields.

### Colors & Tints

- Scanning active: `.green` (circle fill, stroke, `ProgressView` tint)
- Scanning idle: `.gray` (circle fill, stroke, icon)
- Stop button: `.red` background (custom `RoundedRectangle`)
- Start / primary action: `.blue` background (custom `RoundedRectangle`)
- Unassigned "Create New Spool" button: `.blue` background with `.white` foreground
- Secondary action buttons (Assign, Change Spool, Unlink): `.regularMaterial` background, default foreground
- Unlink from Spool: `.red` foreground
- Destructive / error: `.red`
- Success confirmation: `.green`
- Connection test button: `.blue` tint on `.borderedProminent`
- Save button (post-test): `.green` tint on `.borderedProminent`

### Buttons

- Settings form primary buttons (Test Connection, Save) use `.borderedProminent` with
  `HStack { Spacer(); content; Spacer() }`.
- Scan screen start/stop button: `Button(action:)` with a manual `HStack { Image; Text }`:

  ```swift
  HStack { Image(...); Text(...) }
      .frame(maxWidth: .infinity)
      .padding()
      .background(color, in: RoundedRectangle(cornerRadius: 12))
      .foregroundStyle(.white)
  ```

- Post-scan action buttons (Assign, Change, Unlink, Create):

  ```swift
  Label(...)
      .fontWeight(.medium)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .padding(.horizontal)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
  ```
- Destructive or stop actions use `.red` tint or foreground; confirmations use `.green` tint.

### Spinners

- Inline `ProgressView()` with `.progressViewStyle(.circular)` replaces the button icon while an async
  operation is in progress.
- The button is disabled (`disabled(true)`) during the operation.
- Spinner tint matches the button foreground (`.tint(.white)` on a `.borderedProminent` button).

### Forms (Settings)

- Use `Form` with `Section` blocks; header labels in sentence case.
- Sections: "Spoolman Server" (URL field, Test Connection, Save), "Current Configuration" (saved URL read-only),
  "Spool Creation" (filament name style `Picker`), "Filament Presets" (Brands, Materials, Variants, Weights
  `NavigationLink` rows).
- Destructive or blocking flows (e.g., connection test) gate the next action: show the outcome inline before
  revealing the next button.
- Editing an input field resets any prior test/validation result.
- Toast confirmations (`overlay`) slide in from the bottom, auto-dismiss after 1.5 s.

### Create Spool Sheet

- Used from `ScanView` (after scanning a tag). `tagPayload` and `uidHex` are optional; the sheet works without a tag.
- First row is a full-width tappable row showing "Create New" or the selected filament name + ID
  (e.g., `Bambu PLA (#7)`). Tapping opens `FilamentPickerSheet`.
- `FilamentPickerSheet` lists existing filaments with a "Create New" entry at the top. Selecting an existing
  filament locks the Filament fields and pre-fills them, including `variantDecoded` from the filament's custom
  field. Toolbar has Refresh (leading) and Done (trailing).
- Filament section (`PickableField`): brand, material, variant, color. Each field has a label, trailing text
  input, and a chevron icon that opens a `PresetPickerSheet`. The color row additionally has a `ColorPicker`
  on iOS. Locked fields show a `lock.fill` icon. Variant suggestions prepend an empty entry that clears the field.
- Properties section: diameter (`SpoolField`), weight (`PickableField` with presets), nozzle temp, bed temp.
  Locked when using an existing filament.
- Tag section shows the card UID as read-only monospaced text; hidden when `uidHex` is empty.
- Temperature fields use `.numberPad`; default temperatures are applied when material is entered and the temp
  fields are blank.
- The top-right `Create` toolbar item swaps to a circular spinner and disables while the request is in progress.
- On success: the spool list is refreshed and the caller can open `SpoolDetailSheet` for the new spool.

### Preset Editor (`PresetEditorView`)

- Navigated to from Settings via `NavigationLink` for Brands, Materials, Variants, Weights.
- List with two sections: "Your presets" (reorderable, deletable, add field + `plus.circle.fill` button) and
  "From Spoolman" (unused suggestions fetched from loaded spools, tappable to add).
- Toolbar: `EditButton` for reorder/delete mode.

### Toast / Feedback Overlay

```swift
.overlay {
    if showFeedback {
        VStack {
            Spacer()
            HStack { Image(systemName: ...) ; Text(...) }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 40)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
.animation(.easeInOut, value: showFeedback)
```

### Scan Screen

- `ScrollView` containing a `VStack(spacing: 28)`.
- Centered circle indicator (160 pt outer fill, 140 pt stroke): scanning shows
  `ProgressView().scaleEffect(2.2).tint(.green)`, idle shows `wave.3.right.slash` icon in `.gray`.
- Status message (`headline`) below the circle.
- Single full-width start/stop button with icon (`stop.circle.fill` / `play.circle.fill`) and label swap.
- Result section appears via `.transition(.move(edge: .bottom).combined(with: .opacity))`.
- "Tag read" / "Error" header row with icon, then `TagDetailView`, then a `spoolmanSection`.
- `spoolmanSection` label: `Label("Spoolman", systemImage: "server.rack")` in `.caption` / `.secondary`.
- When a spool is associated:
  - `SpoolInfoRow` is tappable (opens `SpoolDetailSheet`).
  - "Change Spool" button shown when `viewModel.spools` is non-empty. Opens `AssignSpoolSheet`.
  - "Unlink from Spool" button always shown in red. Tapping shows a `.confirmationDialog` naming the UID and spool.
- When no spool is associated: "Assign to Existing Spool" and "Create New Spool" buttons shown.
- `ScanView` calls `ensureSpoolsLoaded()` on appear.

### History List

- `List` of `ScanResult` rows: success/failure icon (`.title2`) left, spool name headline + format name capsule
  badge, spool ID + card UID in `.caption`/monospaced, timestamp in body.
- Tapping a row opens a `NavigationStack` sheet with `TagDetailView` and an error banner if failed.
- Empty state uses `ContentUnavailableView`.
- Toolbar: destructive "Clear" button (trash icon) when history is non-empty.
- Tab badge shows `scanHistory.count` (all scans, not just unread).

### Tag Detail Table (`TagDetailView`)

Dynamic table, always shown after a scan:

- **Format** — `payload.formatName` (e.g., "OpenSpool v1.0", "NDEF")
- **Dynamic fields** — each `payload.fields` entry as a `TagRow`; if `field.colorHex` is set, shows a 20×20
  rounded swatch + monospaced `field.value`
- **Card UID** — monospaced hex string, `minimumScaleFactor(0.7)`

Each row: 72 pt label column, `.regularMaterial` background `RoundedCornerShape(12)`.

### Spool Info Row (`SpoolInfoRow`)

Shown below the tag table when a Spoolman spool is associated:

- 36×36 color swatch (`ColorSwatch`, `cornerRadius: 8`)
- Spool name (`.subheadline`/`.medium`), material capsule, remaining weight, `TagCountBadge`
- Uses `.regularMaterial` background with `RoundedRectangle(cornerRadius: 12)`

### Spools List (`SpoolsView`)

- 44×44 `ColorSwatch` per row (`cornerRadius: 10`)
- Name (headline), material capsule, `#id`, remaining weight, `TagCountBadge`
- Conflict indicator: `exclamationmark.triangle.fill` in orange if a UID is on multiple spools
- Grouped by `SpoolSort` with section headers; sort persisted in `@AppStorage("spoolsSortBy")` /
  `@AppStorage("spoolsSortAscending")`
- Sort options: Date Added, Last Used, Name, Material, Remaining, Tags
- Loads up to 1000 spools per request; auto-triggered "Load More" row only beyond that
- Refreshes on appear and on returning to the foreground (skipped within 15 s of the last load);
  pull-to-refresh; a failed refresh shows an inline "Couldn't refresh" banner above the list
- Toolbar: refresh (leading, `arrow.clockwise`), sort menu (trailing, `arrow.up.arrow.down`)

### Spool Detail Sheet (`SpoolDetailSheet`)

- Header card: 64×64 swatch, title, material capsule + `TagCountBadge`; `.regularMaterial` background.
- Stats table: Spool ID, Remaining, Color (18×18 swatch + `#HEX` monospaced), Diameter, Filament weight,
  Nozzle, Bed, Added, Last Used — each row only shown when non-nil.
- Assigned Tags section: UID list with `wave.3.right` icon + monospaced text; conflict warning per UID;
  "Remove All" destructive button in header; confirmation dialog before removal.
- Tip: "Tip: assign a tag from each side of the spool." in `.caption`/`.secondary`.
- Action buttons: "Assign NFC Tag" (`.borderedProminent`, swaps to spinner while `pendingAssignSpool` matches),
  "Open in Spoolman" (`.bordered` link).

### Assign Spool Sheet (`AssignSpoolSheet`)

- `ModalBottomSheet`-style `NavigationStack` with search field.
- List rows: 40×40 swatch, spool name, ID + material + remaining weight + `TagCountBadge`, chevron.
- Full-screen `ProgressView("Assigning…")` overlay while assignment is in progress.
- Empty/error states via `ContentUnavailableView`.

### Shared Components

- `ColorSwatch(hex:size:cornerRadius:)`: filled `RoundedRectangle`; shows `circle.dashed` placeholder when
  `hex` is nil or unparseable.
- `TagCountBadge(count:)`: capsule showing "Tags N"; blue when `count > 0`, secondary otherwise.
- `SpoolmanLoadErrorView`: `ContentUnavailableView` with "Retry" `.borderedProminent` button.

### Connection Test Logs

Monospaced `caption` text, shown inline in the form below the Test button:

- Default color: `.secondary`
- Lines starting with `✓`: `.green`
- Lines starting with `✗`: `.red`

Format: `GET <url>`, `<status> <reason> (<ms>ms)`, `✓ Spoolman v<version>`

### Navigation

- Four-tab `TabView`: Scan (`wave.3.right`), Spools (`list.bullet.rectangle`), History (`clock.arrow.circlepath`),
  Settings (`gearshape`).
- History tab badge: `viewModel.scanHistory.count` (0 suppresses badge).

---
