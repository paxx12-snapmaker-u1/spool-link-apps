# Agent Instructions

This document provides guidance for agents working on this repository to ensure consistency and adherence
to the project's technical standards.

## Core Responsibility

Your goal is to implement, test, and refine three applications (Android/Kotlin, iOS/SwiftUI, Web) that interact with a
Spoolman server via NFC tags.

## Reference Documents

- [docs/DESIGN.md](./docs/DESIGN.md): UI/UX design guidelines — colors, button styles, spinner patterns,
  form conventions — for both iOS and Android.
- [docs/SPOOLMAN.md](./docs/SPOOLMAN.md): Spoolman API protocol reference — all endpoints, field formats, `card_uids`
  wire encoding, OpenSpool NFC tag schema, and the sync logic.
- [docs/ANDROID.md](./docs/ANDROID.md): Android UI walkthrough — screenshots and descriptions of every screen.

## Technical Standards

### 1. Android (Kotlin)

- **Architecture**: MVVM with Jetpack Compose; single `SpoolmanViewModel` (extends `AndroidViewModel`).
- **Networking**: Retrofit with Gson for API interactions; all calls via `withContext(Dispatchers.IO)`.
- **Concurrency**: Kotlin Coroutines (`viewModelScope`).
- **UI**: Jetpack Compose; 4-tab `NavigationBar`; `ScanScreen` uses a plain `Scaffold` (no `TopAppBar`);
  all other screens own a `Scaffold(TopAppBar)`; sheets use `ModalBottomSheet`.
- **NFC**: `NfcAdapter` using Foreground Dispatch for real-time scanning.

### 2. iOS (SwiftUI)

- **Architecture**: MVVM using `@Observable`.
- **Networking**: `URLSession` with modern `async/await` syntax.
- **NFC**: `CoreNFC` framework utilizing `NFCTagReaderSessionDelegate`.
- **Persistence**: Use `@AppStorage` for lightweight configuration (e.g., Spoolman URL).

### 3. Web

- **No framework** — vanilla ES modules, no build step.
- **State** lives in the top-level `state` object; rendering is imperative via `render*` functions.
- **NFC**: Web NFC API (`NDEFReader`), Chrome on Android only.

### 4. Business Logic (Universal)

All implementations must strictly adhere to this synchronization logic:

1. **Parse**: Read an NDEF JSON record from the NFC tag containing a `spool_id`.
2. **Retrieve**: Fetch the spool object from the Spoolman API using that ID.
3. **Update Current**: Append the hex-formatted UID to the current spool's `extra.card_uids` custom field
   (comma-separated list of hex UIDs).
4. **Cleanup Others**: Search the Spoolman server for any other spools containing this UID in their
   `extra.card_uids` and remove only that UID from them.

For manual assignment, moving a UID off another spool requires the user's confirmation when they chose the
spool before scanning (Assign NFC Tag); picking a spool for an already-scanned tag moves it directly. Assigning
a UID the spool already has is reported as an error. See
[docs/SPOOLMAN.md](./docs/SPOOLMAN.md#sync-logic-add-to-current-remove-from-others).

The `card_uids` custom field must exist before writing; call `ensureCardUidsField()` (or equivalent) on first use.

## Agent Workflow

1. **Context**: Examine existing codebases (Android/iOS/Web) to understand established patterns.
2. **Implement**: Write clean, type-safe code.
3. **Verify**: Ensure any new logic does not break the "Add to current, remove from others" requirement.

## Scripts

- `scripts/capture-screenshot.sh <ios|android> <name>` — captures a screenshot from a connected device
  and saves it to `docs/images/<platform>/NN-<name>.png`.
