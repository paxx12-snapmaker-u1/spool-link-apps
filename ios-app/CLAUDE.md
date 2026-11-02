# iOS App — Agent Guidelines

## Build & Test

```
xcodebuild -project ios-app/NFCSpoolReader.xcodeproj \
           -scheme NFCSpoolReader \
           -destination 'id=810CDEC4-F845-485B-B384-2AB00B1B3FD6' \
           build
```

SourceKit reports spurious "Cannot find type" errors for types defined in sibling files — ignore them.
Trust `xcodebuild` output only.

## Layer Map

| Folder | Responsibility |
|---|---|
| `Formats/` | NDEF record parsing → `NFCTagPayload` concrete types; `FilamentMetadata` normalisation |
| `Models/` | API response types, app-level value types (`ScanResult`, `FilamentPresets`, `TagPayload` protocol) |
| `Services/` | I/O only — `NFCManager` (CoreNFC session), `SpoolmanAPI` (HTTP actor) |
| `ViewModels/` | `SpoolmanViewModel` — business flow, state, NFC delegate |
| `Views/` | SwiftUI screens and sheets; no business logic |

## NFC Parse Path

1. `NFCManager.tagReaderSession(_:didDetect:)` reads NDEF records.
2. `TagFormatParser.parse(record:)` is called per record; returns the first matched `NFCTagPayload`.
3. Falls back to `RawNDEFTagPayload` when no parser matches.

To add a new tag format: implement `NFCTagPayload`, add a matching branch in `TagFormatParser.parse(record:)`.

## JSON Decoding Rules

- **`SpoolmanAPI`** uses `keyDecodingStrategy = .convertFromSnakeCase` and **no explicit `CodingKeys`** on response
  models. The decoder converts `"spool_id"` → `"spoolId"` before matching Swift property names. This works correctly.
- **`OpenSpoolPayload`** (and any future NDEF JSON model) uses **explicit `CodingKeys` with snake_case raw values and
  NO `convertFromSnakeCase`**. Mixing explicit `CodingKeys` with `convertFromSnakeCase` causes all snake_case keys to
  silently decode as `nil` because the strategy transforms the JSON key before matching against the `rawValue`.

## card_uids Format

Tag UIDs are stored in `spool.extra.cardUids` (decoded from `extra.card_uids`) as a comma-separated string
of uppercase hex UIDs:

```
"AABBCCDD,11223344"
```

`SpoolResponse.tagUIDs` splits on `,` and filters empty strings. `tagCount` is `tagUIDs.count`. The field
value itself is JSON-encoded (double-serialized string) as required by Spoolman's custom field API —
`SpoolmanAPI` handles this encoding/decoding transparently.

## `SpoolmanViewModel` State

| Property | Type | Purpose |
|----------|------|---------|
| `spools` | `[SpoolResponse]` | Loaded spool list |
| `isFetchingSpools` | `Bool` | Spool fetch in progress |
| `hasMoreSpools` | `Bool` | Pagination — more pages available |
| `spoolsErrorMessage` | `String?` | Last spool fetch error |
| `scanHistory` | `[ScanResult]` | All scan results this session |
| `lastResult` | `ScanResult?` | Most recent scan |
| `isScanning` | `Bool` | NFC foreground scan active |
| `statusMessage` | `String` | Scan screen status text |
| `pendingAssignSpool` | `SpoolResponse?` | Spool awaiting NFC tag assignment |
| `isCreatingSpool` | `Bool` | Spool creation in progress |
| `availableFilaments` | `[SpoolmanAPI.FilamentResponse]` | Loaded filament list for picker |
| `isLoadingFilaments` | `Bool` | Filament fetch in progress |
| `filamentsErrorMessage` | `String?` | Last filament fetch error |

Key methods: `ensureSpoolsLoaded()`, `fetchSpools(reset:)`, `loadMoreSpools()`, `processTag()`,
`processAssignment()`, `startTagAssignment(for:)`, `cancelTagAssignment()`, `removeTag(uidHex:from:)`,
`removeAllTags(from:)`, `createSpoolFromTag(tagPayload:uidHex:overrideMeta:selectedFilamentId:)`,
`loadFilaments()`, `loadFilamentsIfNeeded()`, `updateBaseURL(_:)`.

- `ensureSpoolsLoaded()` — call from any view that needs `viewModel.spools` populated. Fetches only when
  the list is currently empty.
- `processTag` and `processAssignment` own the "add to current spool, remove from others" sync logic.
  Do not duplicate this in views.
- `processAssignment` returns a `TagAssignmentOutcome`. If the tag is on another spool it sets
  `pendingTagMove` and writes nothing (unless called with `confirmMove: false`, as `AssignSpoolSheet` does,
  which moves it directly); the view confirms with `confirmTagMove(_:)` or calls
  `declineTagMove()`. Errors (including "already assigned") set `assignmentError`. Views that start an
  assignment apply the `TagAssignmentPrompts` modifier (in `SpoolsView.swift`) to present both, and show
  `lastAssignmentResult` inline.

## `FilamentMetadata`

Shared normalised value type produced by `NFCTagPayload.filamentMetadata`. Used for:

- Pre-filling `CreateSpoolSheet` fields.
- Building the Spoolman `createSpoolFromTag` call.
- `filamentName(style:)` — applies the user-selected `FilamentNameStyle`.
- `colorName` — derives a human-readable color name from `colorHex` via HSL.

Read the naming style in `SpoolmanViewModel` via:

```swift
let styleRaw = UserDefaults.standard.string(forKey: "filamentNameStyle") ?? ""
let nameStyle = FilamentNameStyle(rawValue: styleRaw) ?? .brandAndSubtype
meta.filamentName(style: nameStyle)
```

## `SpoolmanAPI`

- `actor` — all mutations are safe; call with `await`.
- Uses `convertToSnakeCase` encoder and `convertFromSnakeCase` decoder consistently for server I/O.
- `findOrCreateVendor(name:)` — use before `createSpoolFromInfo` when brand is non-nil.
- Do not add view logic or `UserDefaults` reads here; those belong in the ViewModel.

## Sheets and State in `ScanView`

- `selectedSpool: SpoolResponse?` drives `SpoolDetailSheet` via `.sheet(item:)`.
- `showCreateSheet`, `showAssignSheet`, `showChangeSpoolSheet` are `@State` on `ScanView`; their
  `.sheet(isPresented:)` modifiers are attached inside the `if let result` block so `result` is in scope.
- After `CreateSpoolSheet` dismisses, `.onChange(of: showCreateSheet)` opens `SpoolDetailSheet` for the
  newly created spool.
- "Change Spool" button is shown only when `!viewModel.spools.isEmpty`.

## Settings Persistence

Use `@AppStorage` in views for user preferences. Current keys:

- `"spoolmanBaseURL"` — server URL
- `"filamentNameStyle"` — raw value of `FilamentNameStyle`
- `"spoolsSortBy"` — raw value of `SpoolSort` (persisted in `SpoolsView`)
- `"spoolsSortAscending"` — `Bool` sort direction (persisted in `SpoolsView`)

`FilamentPresets` are persisted via `FilamentPresets.load()` / `.save()` using `UserDefaults` directly
(not `@AppStorage`).

Read `@AppStorage`-backed preferences in the ViewModel via `UserDefaults.standard` directly (the ViewModel
is not a SwiftUI view).

## Code Style

- No comments unless the why is non-obvious.
- No trailing whitespace on empty lines.
- Empty line at end of every source file.
- Retain existing indentation and brace style.
