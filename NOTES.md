# Implementation notes

Choices made where `design-docs/count-my-sweat-spec.md` is silent (spec section 0 asks for them to be recorded here).

## Data and rules
- **Mix detection.** A session is Mix when `preset_id IS NULL` *and* `preset_name = 'Mix'`. A preset session whose preset was deleted also gets `preset_id = NULL`; the name check keeps it from turning into a Mix (no "+ Add exercise", no "Save as preset").
- **One active session** is enforced twice: in `SessionRepository.start()` and by a partial unique index `sessions_one_active` created in the migration.
- **Auto-end** of a forgotten session runs at startup *and* whenever the app returns to the foreground.
- **Seed import** runs when the number of exercises in the bundled JSON differs from the last import (`settings.seed_count`). Seeded rows are upserted; `custom-…` rows are never touched. If the asset is missing the app still boots with an empty library.
- **Exercise description** = first two instruction steps joined; the UI clamps it to 2 lines.
- **Dataset as built on 2026-10-18**: 876 exercises (the spec said 873). Three newer kettlebell exercises have no image upstream; the script writes `has_image: false` for them and the seeder stores `image_asset = NULL`, so the app shows a placeholder icon. Assets total 8.4 MB.
- **Recent foods** = last 15 entries, distinct by (name, quantity, kcal).
- **Adding food on a past day** logs it on that day at the current time of day. Entry time is editable.
- **Editing an entry's amount** rescales all its nutrients proportionally (works without the source food).
- **Prefill in lb.** If the prefilled weight text is left untouched, the exact stored kg value is reused, so kg → lb → kg rounding never drifts.
- **Change tracking for backup.** Writes to any user table set `settings.data_changed_at` (via drift `tableUpdates`). Writes to `settings` itself do not count.

## Open Food Facts
- The legacy `/cgi/search.pl` endpoint was unavailable when checked, and the v2 API has no full-text search. The app uses **Search-a-licious**: `GET https://search.openfoodfacts.org/search?q=…&page_size=20&fields=code,product_name,brands,serving_quantity,nutriments` (field names verified against a live response on 2026-10-18).
- kcal fallback order: `energy-kcal_100g` → `energy-kj_100g / 4.184` → `energy_100g / 4.184`. Hits without a name or energy are skipped.
- Client-side rate limit: at most 10 searches per rolling minute (the documented limit). Above it, the app shows a message and keeps saved foods, quick add and custom foods working.

## Screens
- **Home chart**: bar chart (the spec says bar; the wireframe shows a line). Values shown in the chosen unit.
- **Analyse**: the volume chart is a line (as in the wireframe), intake is bars with a dashed target line. Nutrient chips offer all 8 nutrients.
- **"Save chart as image"** captures both charts together, with their captions, as one PNG.
- **Workout cards**: the 1:5 and 3:2 ratios are *minimum* heights, so large text scaling never clips content.
- **Preset editor**: leaving with unsaved changes asks for confirmation. Saving needs at least one exercise.
- **Library**: items already in the list are shown as "Added" and can't be picked again.

## Exports
- CSV uses RFC 4180 line endings (`\r\n`). Weights have up to 3 decimals and nutrients up to 2, with trailing zeros trimmed.
- PDF: averages are per **logged** day (days with at least one entry), and target results count logged days. A **personal record** needs earlier history to beat; an exercise's first-ever period is not a PR, so the "All" range never shows PRs.
- PDF weights use the chosen unit. Non-ASCII characters are transliterated or replaced with `?` (built-in fonts).

## Google Drive backup
- Backup JSON keys per row are drift's default JSON keys (camelCase column getters), tagged with `schema_version`.
- **Restore** replaces all foods (the Open Food Facts cache is only a cache), so entries pointing to cached foods get `food_id = NULL`, as the spec requires. If the backup references an exercise missing from this install's dataset, a custom placeholder exercise is created so no sets are lost.
- **"Start fresh"** marks Drive connected and backs up right away. If local data is empty, nothing uploads until there is data. Either way the old `backup.json` is copied to `backup.prev.json` first.
- **Automatic retry**: when the app goes to the background, it backs up if data changed since `last_backup_at` *or* the last attempt failed.
- **Daily task (phase 2)**: a unique (`drive-daily-backup`), network-constrained (`NetworkType.connected`) `workmanager` periodic task with a 24 h frequency, Android only. It is registered (policy `update`, so the schedule is kept) when Drive becomes connected (fresh connect, Restore, Start fresh) and again at every app start while connected; it is cancelled on Disconnect. The task runs `BackupService.backupIfNeeded()`, the same check as going to the background, so it skips when Drive isn't connected, nothing changed and the last try didn't fail, or local data is empty (no pointless uploads that would also overwrite `backup.prev.json`). Failures go to `settings.backup_error`; the task always reports success and tries again the next day.
- **Background isolate database**: `AppDatabase` uses drift_flutter's `shareAcrossIsolates: true`. The workmanager engine runs in the same process, so when the app is open it connects to the UI's drift server (writes stay serialised and Profile sees `backup_error` / `last_backup_at` live). When the app is closed it starts its own.
- **Silent sign-in without an Activity**: `attemptLightweightAuthentication` uses Credential Manager, which fails with `uiUnavailable` in the workmanager isolate. `DriveGateway.signInSilently` then falls back to the account-less `GoogleSignIn.instance.authorizationClient.authorizationForScopes`, which returns a token for already-granted scopes without UI. If Google needs the user to choose an account (for example, several accounts on the phone), it returns nothing and Profile shows "sign-in expired". **Not yet verified on a device** (no Android SDK on the dev machine).
- The web OAuth client id comes from `--dart-define=GOOGLE_SERVER_CLIENT_ID=…`. Without it, Profile says Drive isn't set up.

## Naming
- Organisation convention: constants are `UPPER_CASE` (lint `constant_identifier_names` is disabled for this).

## Open items (owner)
- `applicationId` / namespace is still `com.example.cms`. Pick the final id **before** registering the OAuth client.
- `COFFEE_URL` and `APP_CONTACT` in `lib/core/constants.dart` are placeholders.
- Repository licence, final Mix tagline, app icon.
