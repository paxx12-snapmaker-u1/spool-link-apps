# SpoolLink for iOS — User Guide

## Scan — Idle

The default view on launch. Tap **Start Scanning** to activate NFC scanning via CoreNFC.

<a href="images/ios/01-scan-idle.png"><img src="images/ios/01-scan-idle.png" alt="Scan idle" height="520" /></a>

## Scan — Tag Read (No OpenSpool Data)

Any NFC tag is supported. When no OpenSpool record is present, the tag is still detected
and the card UID is shown. Both Spoolman actions remain available — OpenSpool data is
only used to pre-fill fields when creating a new spool.

<a href="images/ios/02-scan-result-empty-tag.png"><img src="images/ios/02-scan-result-empty-tag.png" alt="Scan result empty tag" height="520" /></a>

## Scan — Tag Read (OpenSpool)

When an OpenSpool 1.0 tag is scanned, the full filament data (format, type, material,
brand, color, temperatures, card UID) is displayed and used to pre-fill the Create Spool
form.

<a href="images/ios/03-scan-result-openspool.png"><img src="images/ios/03-scan-result-openspool.png" alt="Scan result OpenSpool" height="520" /></a>

## Scan — Tag Already Assigned

When a scanned tag is already linked to a spool, the spool is shown with two actions:
**Change Spool** (reassign to a different spool) or **Unlink from Spool** (remove the
tag UID from the current spool).

<a href="images/ios/04-scan-result-assigned.png"><img src="images/ios/04-scan-result-assigned.png" alt="Scan result assigned" height="520" /></a>

## Assign to Existing Spool

Searchable list of all spools on the Spoolman server. Selecting one links the scanned
tag UID to that spool. A tag can only belong to one spool at a time — if it was
previously assigned elsewhere, it is automatically removed from that spool.

> **Tip:** Spools typically have two tags, one attached to each side. Assign both tags
> to the same spool so it is detected no matter which side faces the reader.

<a href="images/ios/05-assign-spool-sheet.png"><img src="images/ios/05-assign-spool-sheet.png" alt="Assign spool sheet" height="520" /></a>

## Create New Spool — Manual

Form to create a new Spoolman spool. Fields are pre-filled from the OpenSpool tag data
but remain editable. The scanned card UID is attached automatically.

<a href="images/ios/06-create-spool-sheet.png"><img src="images/ios/06-create-spool-sheet.png" alt="Create spool sheet" height="520" /></a>

## Create New Spool — Existing Filament

When an existing Spoolman filament is selected from the picker, all filament fields lock
to that filament's values (shown with lock icons).

<a href="images/ios/07-create-spool-with-filament.png"><img src="images/ios/07-create-spool-with-filament.png" alt="Create spool with filament" height="520" /></a>

## Spools

Full spool list fetched from Spoolman, ordered by the active filter. Each row shows the
color swatch, filament name, material, remaining weight, and tag count.

<a href="images/ios/08-spools-list.png"><img src="images/ios/08-spools-list.png" alt="Spools list" height="520" /></a>

## Spool Detail

Sheet with complete spool metadata: remaining weight, color, diameter, print
temperatures, dates, and all assigned NFC tag UIDs. Actions: assign another tag or
open the spool directly in Spoolman.

<a href="images/ios/09-spool-detail-sheet.png"><img src="images/ios/09-spool-detail-sheet.png" alt="Spool detail sheet" height="520" /></a>

## Spool Detail — Assign NFC Tag

Tapping **Assign NFC Tag** opens the system NFC reader sheet. Hold the device near a
tag to link it to the spool.

<a href="images/ios/10-spool-detail-assign-tag.png"><img src="images/ios/10-spool-detail-assign-tag.png" alt="Spool detail assign tag" height="520" /></a>

## Spool Detail — Remove All Tags

Tapping **Remove All** shows a confirmation popover before detaching all NFC tag UIDs
from the spool.

<a href="images/ios/11-spool-detail-remove-all.png"><img src="images/ios/11-spool-detail-remove-all.png" alt="Spool detail remove all" height="520" /></a>

## History

Log of every NFC scan in this session. Each entry shows the tag format, card UID,
matched spool (if any), and timestamp.

<a href="images/ios/12-history.png"><img src="images/ios/12-history.png" alt="History" height="520" /></a>

## Settings

Spoolman server URL with a connection test, tag storage, filament name pattern for new spools, and
editable presets for brands, materials, variants, and weights.

**Tag Storage** selects where tag links are kept: **Card UIDs** (the default) or **Spoolman native
tags** (Spoolman v0.27.0 or newer). Use the same setting as **Spoolman Tag Storage** on the printer.
Picking a store does not move links; switching the printer's setting does, or use **Move existing
links here**, which moves every link on the server to the selected store and lists any it left in place.

<a href="images/ios/13-settings.png"><img src="images/ios/13-settings.png" alt="Settings" height="520" /></a>

## Settings — Connection Test

Tapping **Test Connection** validates the server URL by running a sequence of API checks
(info endpoint, `card_uids` field or native tag support, filament field). On success a **Save** button appears
to persist the URL.

<a href="images/ios/14-settings-connection-ok.png"><img src="images/ios/14-settings-connection-ok.png" alt="Settings connection test" height="520" /></a>
