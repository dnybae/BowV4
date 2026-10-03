# Bow iCloud sync implementation plan

Reviewed October 2, 2026. Planning only; iCloud sync is not enabled by this document.

## Intended experience

A person's budget appears automatically on their other iPhones signed into the same Apple Account with iCloud available. Edits work offline and converge after connectivity returns. A new installation first attempts to retrieve the existing budget. No Bow login or manual backup import is required. Sync is asynchronous, so do not promise immediate delivery or recovery of changes that never finished uploading.

## Findings in the current app

- `App/App.swift`: one shared SwiftData container serves the app, background bank refresh, and Shortcuts. It has no explicit CloudKit configuration.
- `Project.json`: the permanent bundle ID is `app.bitrig.danielbaeza.bow`. No iCloud or APNs entitlements are configured; background modes contain only `fetch`. Current device family is iPhone only.
- `App/Models/BowSchema.swift`: 12 models, with a V1 schema and no migration stages. Stored attributes inspected have defaults or are optional, without unique constraints or SwiftData relationships. This is a promising CloudKit starting point, subject to an actual mirrored-store initialization test. Verify arrays, external image data, and indexes in that test.
- Models link by UUID. Remote records can arrive separately, so referenced accounts, envelopes, and transactions may temporarily be absent.
- `ContentView.swift` shows welcome immediately when profiles are empty. `BudgetCommands.createBudget` guards only against a locally existing profile. Different devices can create unrelated profiles and starter categories; most records have no budget ownership field, so simply selecting the first profile would silently combine budgets.
- `BundledPayeeInstaller`, card payment envelope creation, `ScheduleReviewPlanner`, and bank imports use local existence checks. Those checks cannot prevent simultaneous creation on separate devices.
- `BowDataUpgrade` changes balances and uses a profile-level completion marker. A partial remote import must not trigger a second or incomplete financial migration.
- Budget snapshots and transaction feeds react to `ModelContext.didSave`; remote import invalidation needs explicit verification and support.
- `SimpleFINCredentialStore` uses `AfterFirstUnlockThisDeviceOnly`. Budget restoration will not restore this bank credential. `SimpleFINConnection` also mixes durable settings with request counters and device activity.
- `BowBackup.restore` deletes and reinserts the whole budget. Under sync, these changes would propagate. Current restore messaging does not describe that scope.
- Demo uses an in-memory container. Appearance, intro flags, and collapsed sections are local preferences. Privacy text currently describes primarily device-local storage.

## Recommended architecture and scope

Keep SwiftData and use its built-in private CloudKit mirroring. Do not introduce a second custom sync engine alongside it. Use proposed container `iCloud.app.bitrig.danielbaeza.bow`, verifying ownership and signing before registering it.

Sync profiles, accounts, groups, envelopes, transactions, allocations, payees/rules/custom logos, schedules/occurrences, bank mappings, and import/review history. Preserve identifiers and integer monetary amounts. Keep presentation preferences, demo state, caches, and bank refresh execution state device-local. Separate durable bank connection preferences from operational counters with an explicit migration; do not casually move existing models between stores.

For the initial release, keep bank secrets in device-local Keychain. Existing imported data still appears everywhere, but a replacement phone reconnects SimpleFIN to resume fetching. A separate optional iCloud Keychain design can later eliminate that step. Never store access URLs in budget records or backups. Prefer one designated bank-refresh device with explicit takeover, plus deduplication even during takeover; replicated counters are not an atomic account-wide rate limiter.

## Implementation sequence

### 1. Prove storage compatibility and preserve existing data

- Capture representative V1 store fixtures and round-trip backups, including images, bank history, reconciliation, and schedules.
- Verify the current on-disk store location/configuration and enable mirroring in place. Never silently create an empty replacement store after initialization failure.
- Complete existing balance upgrades before first export. Redesign future upgrade bookkeeping so partially received data cannot be skipped or upgraded twice.
- If model changes are required, freeze the V1 model definitions, introduce V2 and a tested migration stage. Keep backup decoding compatible.
- Explicitly configure the real container with `.private(containerIdentifier)` and demo/test containers with `.none`.
- Add iCloud container/services, `aps-environment`, and `remote-notification` background mode while preserving the existing bank `fetch` setup. Use Bitrig's standard-project and notifications skills for implementation.

### 2. Make budget operations converge safely

- Introduce a stable budget identity/ownership strategy before supporting independently created budgets. Initially offer an explicit choose/replace flow if both cloud and local budgets exist; do not silently merge unrelated budgets or currencies. Preserve an export before replacement.
- Define logical identities for bundled payees, system groups, card payment envelopes, bank items, and schedule occurrences. Use a stable calendar-day key that does not depend on the current device's time zone.
- Add deterministic duplicate reconciliation after imports, remapping UUID references before removing redundant records. Deterministic UUIDs alone do not force SwiftData's mirrored records to upsert into one record.
- Deduplicate scheduled transactions and bank imports before presenting financial totals. Preserve user edits and skipped/deleted occurrence intent, so automation cannot resurrect deleted bills. Do not deduplicate unrelated manual transactions merely because amounts/dates match.
- Specify and test same-record edit/edit and edit/delete conflict behavior. Financially coupled fields must remain consistent; recover conflicting financial edits rather than assume framework conflict resolution preserves all intent.
- Tolerate temporarily missing UUID references; do not perform destructive orphan cleanup during download. Replace crash-prone unique-key dictionary construction where duplicate logical IDs can occur.
- Revisit persisted derived targets and migration markers to prevent competing recomputation or sync loops.

### 3. Deliver a safe new-phone experience

- Add a model-layer sync coordinator for account availability, import/export activity, failures, and remote-change notifications using supported APIs.
- Show an initial retrieval state before offering a new budget. Account availability or an empty local query does not prove that the cloud budget is empty. Handle offline/timeouts without indefinite blocking or automatically seeding duplicates.
- Invalidate snapshot and paged-feed caches after remote imports, refresh views, and revalidate open editors when their objects change remotely. Verify foreground/background and Shortcuts behavior.
- Add concise iCloud status in Settings with actionable sign-in, storage, and retry guidance. Display only timestamps/states actually supported by observed events; do not label a local save as successfully uploaded.
- Define Apple Account sign-out/switch behavior: prevent a previous account's local budget from being automatically uploaded into another account. Preserve recoverability and require an explicit data choice when necessary.
- Apply native-app-design guidance when implementing these UI changes.

### 4. Make backup and bank operations sync-aware

- Retain independent manual backups. Redesign restore as a deliberate budget replacement with cloud-wide messaging, recovery export, and a generation/identity policy so concurrent or offline edits cannot silently resurrect the replaced budget. A local single save is not a cross-device atomic restore.
- Separate disconnect-on-this-device from removing shared bank mappings. Reconnection must reuse existing mappings/import identities and preserve review decisions.
- Update privacy/data-management text to describe private iCloud storage, asynchronous sync, deletion propagation, and bank reconnection accurately.

### 5. Validate and release

- Run existing checks and migration tests; build through Bitrig and run the simulator. Use two physical devices signed into the same test Apple Account for actual sync verification; simulator-only results do not prove push delivery.
- Verify old local budget → cloud → clean installation, matching record identities, balances, categories, reconciliation, images, and bank review state.
- Test offline edits, simultaneous scheduling/imports, partial downloads, cold launches, time-zone differences, conflicting edits/deletes, app termination during migration, and restore while another device is offline.
- Test no iCloud account, account switching, disabled iCloud, full storage, and reconnecting bank access. Confirm demo records and secrets never enter the cloud budget.
- Acceptance: both devices converge to the same correct ledger without duplicated financial events; remote changes refresh visible totals; failures retain locally saved work; a clean installation retrieves the budget without manual import.
- Initialize every mirrored record type in development, export and commit `CloudKitSchema.ckdb`, and validate it. Deploy the schema to production through CloudKit Console before TestFlight, then repeat new-install recovery using TestFlight. Development success alone is insufficient.

## Delivery recommendation

Implement in three reviewable milestones: storage/migration proof; convergence and recovery safeguards; onboarding/status plus production validation. Do not ship capability-only activation before the duplicate-transaction and new-install tests pass. No app code, project settings, or cloud resources were changed in this review.

Reference: [Apple — Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices). SDK/API details and notification behavior must be verified during implementation on the installed iOS 27 SDK; the project still supports iOS 26.
