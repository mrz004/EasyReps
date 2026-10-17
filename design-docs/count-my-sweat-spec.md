# Count My Sweat - Build Spec (for GitHub Copilot)

A personal gym + food tracker for Android. Local-first, ad-free, no accounts, no backend.

## 0. How to work with this spec

- Read the whole file before writing code. Build milestone by milestone (section 12), in order.
- This spec is the source of truth. If it is silent, choose the simplest option that works and record the choice in `NOTES.md`. Do not add features that are not listed here; ask first.
- Prefer the Flutter SDK and platform features over new packages. Add a dependency only when it saves real work. Use current stable versions and read each package's README for its current API (for example `google_sign_in` changed across major versions). Do not guess APIs.
- Do not cut corners on: data-loss handling, input validation, security (no secrets in the repo), accessibility.
- Keep files small. One screen per file. Run `flutter analyze` and the tests before finishing each milestone.

## 1. Product

**Principles**
- Local-first and offline-first. The gym often has bad signal; logging must work fully offline.
- Store only raw data (sets, food entries). Compute all stats from it, so analysis can change without migrations.
- Fewest taps possible while logging. Simple UI over feature richness.
- No AI features. No ads. No analytics or crash-reporting SDKs. Android permission: `INTERNET` only.
- User data may leave the phone only through (a) the user's own Google Drive app folder, (b) the share sheet when the user exports.

**Non-goals for v1:** iOS, accounts or a backend, ads, AI, social features, meal grouping (breakfast/lunch/dinner), barcode scanning, notifications, supersets, browsing or editing past sessions (see section 13).

## 2. Tech stack

- Flutter (stable), Dart, Material 3, light/dark following the system. Target: Android only.
- Database: `drift` (SQLite) with migrations. Streams for reactive UI.
- State management: `flutter_riverpod` (keep it minimal; no code generation unless needed).
- Navigation: built-in `Navigator`.
- HTTP: `http`.
- Charts: `fl_chart`.
- Sharing / files: `share_plus`, `path_provider`.
- PDF: `pdf`. CSV: `csv`.
- Google Drive backup: `google_sign_in` + `googleapis` (Drive v3), scope `https://www.googleapis.com/auth/drive.appdata`. Background: `workmanager` (phase 2, see section 8).
- External link: `url_launcher` (Home coffee link).
- Chart-to-image: `RepaintBoundary` + `toImage` (no package).
- Date range picker: built-in `showDateRangePicker`.
- Suggested layout: `lib/data` (drift tables, DAOs, repositories), `lib/features/<home|workout|session|exercise|library|food|analyse|profile|export|backup>`, `lib/core` (theme, utils).

## 3. Data model

All timestamps are epoch milliseconds (UTC). "Day" always means the device's local calendar day. Weights are stored in kg.

```
exercises
  id TEXT PK                  -- dataset id (e.g. "Barbell_Bench_Press_-_Medium") or "custom-<uuid>"
  name TEXT NOT NULL
  primary_muscle TEXT NOT NULL
  secondary_muscles TEXT NULL -- comma separated
  equipment TEXT NULL
  description TEXT NULL       -- max 2 short lines
  image_asset TEXT NULL       -- "assets/exercises/img/<id>.webp"; NULL for custom
  is_custom BOOL NOT NULL DEFAULT 0

presets
  id INT PK AUTOINCREMENT
  name TEXT NOT NULL
  preferred_days INT NOT NULL DEFAULT 0   -- bitmask Mon=1 Tue=2 Wed=4 Thu=8 Fri=16 Sat=32 Sun=64; 0 = none
  created_at INT NOT NULL

preset_exercises
  preset_id INT FK presets ON DELETE CASCADE
  exercise_id TEXT FK exercises
  position INT NOT NULL
  PRIMARY KEY (preset_id, exercise_id)

sessions
  id INT PK AUTOINCREMENT
  preset_id INT NULL FK presets ON DELETE SET NULL   -- NULL means Mix
  preset_name TEXT NOT NULL                          -- snapshot; "Mix" for Mix
  started_at INT NOT NULL
  ended_at INT NULL                                  -- NULL = active; at most ONE active session

session_exercises                                    -- the exercise list of one session
  session_id INT FK sessions ON DELETE CASCADE
  exercise_id TEXT FK exercises
  position INT NOT NULL
  PRIMARY KEY (session_id, exercise_id)

sets
  id INT PK AUTOINCREMENT
  session_id INT FK sessions ON DELETE CASCADE
  exercise_id TEXT FK exercises
  weight_kg REAL NOT NULL
  reps INT NOT NULL
  logged_at INT NOT NULL

foods                          -- cache of looked-up foods + user-created foods
  id INT PK AUTOINCREMENT
  source TEXT NOT NULL         -- 'off' | 'custom'
  source_id TEXT NULL          -- Open Food Facts barcode
  name TEXT NOT NULL
  brand TEXT NULL
  serving_g REAL NULL
  -- per 100 g, all REAL NULL except kcal:
  kcal REAL NOT NULL, protein_g, carbs_g, sugar_g, fiber_g, fat_g, sat_fat_g, sodium_mg
  last_used_at INT NULL
  UNIQUE (source, source_id)

food_entries                   -- self-contained: amounts actually eaten, copied at save time
  id INT PK AUTOINCREMENT
  eaten_at INT NOT NULL
  name TEXT NOT NULL
  food_id INT NULL FK foods ON DELETE SET NULL
  quantity_g REAL NULL
  kcal REAL NOT NULL
  protein_g, carbs_g, sugar_g, fiber_g, fat_g, sat_fat_g, sodium_mg REAL NULL

nutrition_targets              -- optional; one row per nutrient the user chose to target
  nutrient TEXT PK             -- kcal|protein_g|carbs_g|fat_g|sat_fat_g|sugar_g|fiber_g|sodium_mg
  value REAL NOT NULL
  kind TEXT NOT NULL           -- 'min' (at least) | 'max' (at most)

body_weights
  id INT PK AUTOINCREMENT
  measured_on TEXT NOT NULL UNIQUE   -- YYYY-MM-DD; saving the same day replaces
  weight_kg REAL NOT NULL

settings                       -- key/value: weight_unit ('kg'|'lb'), height_cm, last_backup_at, drive_connected
  key TEXT PK, value TEXT
```

Derived values (never stored):
- **Volume** of a set = `weight_kg * reps`. Training volume per day = sum over sets, grouped by the local day of `logged_at`.
- **Non-saturated fat** = `fat_g - sat_fat_g` when both are known and `fat_g >= sat_fat_g`.
- Day totals of nutrients treat unknown (null) values as 0.

## 4. Core rules

**Units.** Display weights in the chosen unit (kg default; lb = kg * 2.20462). Convert input to kg and store the full-precision value; round only for display (0.1).

**Validation.** Weight: number >= 0 (0 allowed for bodyweight). Reps: integer >= 1. Nutrient values and quantity: number >= 0 (quantity > 0). Names: non-empty after trimming. Reject NaN and negatives with an inline error.

**Session lifecycle**
- Only one active session at a time. If one is active, starting another is blocked and the UI offers Resume.
- `start(presetId | null)` creates the session (`preset_name` = preset name or "Mix") and copies the preset's exercises into `session_exercises` in order. Mix starts with an empty list.
- Mix only: picking an exercise from the library adds it to `session_exercises` (no duplicates). Nothing is saved to any preset.
- Logging a set inserts into `sets`. Sets can be edited or deleted while their session is active.
- `end()` sets `ended_at`. If the session has zero sets, delete the session instead. If it was Mix and has at least one set, offer "Save as preset" (opens the Preset editor prefilled with the exercises done, in order of first set).
- ASSUMED, pending confirmation: if the app opens and an active session started on an earlier day, auto-end it at its last set's `logged_at` (delete it if it has no sets).
- Deleting or editing a preset never changes past sessions or sets.

**Preset ranking** (Workout screen; Mix is excluded)
1. Group A: presets whose `preferred_days` includes today's weekday (device local). Group B: all others.
2. Within each group sort by number of finished sessions in the last 60 days (descending), then most recent `started_at` (never-used last), then name.
3. Group A is listed before Group B.

**Prefill.** Weight and reps boxes on the Exercise screen prefill from the most recent earlier set of that exercise (excluding the current session). After tapping Add, the boxes keep the values just added. If there is no history, they are empty.

**Rest timer.** Shows elapsed time since the last set was logged in this session (computed from `logged_at`, so it survives the app being backgrounded). No setting in v1.

## 5. Screens

Navigation: Home -> Food / Workout / Analyse / Profile. Workout -> Session -> Exercise screen. Workout (+) / View / Save as preset -> Preset editor. Library opens from the Preset editor and from a Mix session. Food -> Add food. Export dialog opens from Analyse and Profile. Drive connect/restore opens from Profile.

**5.1 Home**
- Top: bar chart "Your progress this week" = training volume per day for the last 7 days (ASSUMED metric).
- Button "Start workout": starts a Mix session. If a session is active it reads "Resume workout" and returns to it.
- Four tiles in a 2x2 grid: Food, Workout, Analyse, Profile.
- Bottom: "Buy me a coffee" text link (opens a URL constant via `url_launcher`; URL is a placeholder to fill in).

**5.2 Workout**
- Single-column list. Top: a slim Mix card (about 1:5 aspect ratio), pinned as the first item, not sticky, tagline "let's go by mood", no other description.
- Below: preset cards (about 3:2 aspect ratio), ranked per section 4. Each shows name, preferred days, exercise count.
- Tapping a card expands it to reveal two buttons: **View** (opens the Preset editor to see or edit it) and **Start** (starts the session). Tapping Mix reveals only Start.
- `+` button (top right) opens the Preset editor to create a preset.
- Empty state (no presets): faint hint "Tap + to create your first preset" under the Mix card.

**5.3 Preset editor** (create / view / edit)
- Fields: name (required), preferred days (optional Mon-Sun chips, multi-select), exercise list (reorderable, swipe or button to remove), "+ Add from library" (library in multi-select mode).
- Save, and Delete (with confirmation, only for existing presets).
- Also used by "Save as preset" after a Mix session (prefilled).

**5.4 Session** (preset or Mix)
- Header: preset name. List of the session's exercises, each with the number of sets logged so far. Tap one -> Exercise screen.
- Mix only: "+ Add exercise" opens the library in single-select mode.
- A sticky **End session** button at the bottom (always visible). It asks for confirmation, then follows the `end()` rule in section 4.

**5.5 Exercise screen**
- Posture image (from assets), target muscle, two-line description.
- Two inputs only: weight and reps (numeric keyboards), prefilled per section 4. One **Add set** button.
- List of this exercise's sets in the current session; tap to edit or delete.
- Rest timer (see section 4), shown near the Add button.

**5.6 Exercise library** (picker)
- Search box (case-insensitive substring on name), muscle filter chips (from `primary_muscle`), rows with thumbnail, name, primary muscle.
- "+ Custom exercise": name (required), primary muscle (choose from existing list), optional description. No image. No delete in v1.
- Single-select returns one exercise; multi-select shows checkboxes and a Done button.

**5.7 Food log**
- Date header with previous/next day arrows (ASSUMED), default today.
- Headline card: calories, protein, carbs, fat for the day. If a target exists for a nutrient show a progress bar (`min`: fills toward the target, shows met state; `max`: turns red when exceeded). Without a target show the number only.
- "Show details" expands: sugar, fiber, saturated fat, non-saturated fat (derived), sodium, with their targets if set.
- A small "! limit" badge appears on the card whenever any `max` target is exceeded, even if collapsed.
- Time-ordered list of entries (name, time, kcal); tap to edit or delete. "+ Add food" button.

**5.8 Add food**
- Search box (debounced) against Open Food Facts (section 6). Local `foods` cache is searched first and used when offline.
- "Recent": the last 15 distinct entries. Tapping one re-adds it as a new entry with the same values (editable before saving).
- Choosing a result opens a sheet: amount in grams (default `serving_g` or 100), live preview of nutrients, Save. Save copies the computed nutrients into a new `food_entries` row.
- "Quick add": kcal (required), protein (optional), optional name (default "Quick add").
- "Custom food": name, per-100 g values (kcal required); saved in `foods` with `source = 'custom'`.

**5.9 Analyse**
- Range chips: 7d, 30d, 90d, All (default 30d).
- Chart 1: training volume per day.
- Chart 2: daily intake of one nutrient (selector chips; default calories) with the target drawn as a line when a target exists.
- Buttons: "Save chart as image" (captures the chart currently shown as PNG and opens the share sheet) and "Export data (CSV)" (opens the Export dialog).

**5.10 Profile**
- Nutrition targets: list of nutrients with optional value and an "at least / at most" choice. Suggested defaults when first set: kcal, protein, carbs, fiber = at least; sat fat, sugar, sodium = at most; fat = at most. Editable.
- Units: kg / lb.
- Body: height (cm) and body weight. Body weight is a list of dated entries; the latest is shown; "Add weight" saves for a date (default today).
- Google Drive: Connect / Disconnect, last backup time, a visible error line if the last backup failed (for example sign-in expired), "Back up now".
- "Export PDF summary" (opens the Export dialog).
- About / Licences: credits for Open Food Facts and free-exercise-db (section 10), app version.

**5.11 Export dialog** (shared by CSV and PDF)
- Date range: presets 7d, 30d, 90d, All, and Custom (`showDateRangePicker`). Default: last 30 days.
- Include: Workout and Food checkboxes, both ticked by default. Export is disabled when neither is ticked.
- If nothing exists in the chosen range for the ticked sections, show a message and create no file.

**5.12 Drive connect / restore** - see section 8.

## 6. Food data (Open Food Facts)

- Free, no API key. Terms: attribution, share-alike (ODbL), a custom `User-Agent` such as `CountMySweat/<version> (<repo URL or contact>)`, and enforced rate limits (search is limited more strictly than product reads).
- Find the current search endpoint and field names in the official docs (https://openfoodfacts.github.io/openfoodfacts-server/api/) before coding; do not rely on memory.
- Per-100 g nutriment keys expected (verify): `energy-kcal_100g`, `proteins_100g`, `carbohydrates_100g`, `sugars_100g`, `fiber_100g`, `fat_100g`, `saturated-fat_100g`, `sodium_100g` (grams; convert to mg). If kcal is missing, fall back to `energy_100g` (kJ) / 4.184.
- Search only after at least 3 characters and a 500 ms pause. Cache every result you show into `foods`. Handle offline and errors without blocking quick add or custom foods.
- Show Open Food Facts attribution on the Add food screen (and in About / Licences).

## 7. Exports

**CSV** (UTF-8, header row, proper escaping via `csv`, ISO dates in local time). Files are shared together through `share_plus`.
- `workouts.csv` - one row per set: `date,time,session,exercise,target_muscle,set_number,weight_kg,reps`. `set_number` = order of the set within that exercise in that session.
- `food.csv` - one row per entry: `date,time,food,quantity_g,kcal,protein_g,carbs_g,sugar_g,fiber_g,fat_g,saturated_fat_g,sodium_mg`. Blank where unknown. All nutrients are included even though the UI hides some by default.
- Only the ticked sections, only rows inside the date range. Real names, never internal ids.

**PDF summary** (`pdf` package, built-in fonts, ASCII text, 1-2 pages) - only the ticked sections:
- Header: period and generation date.
- Workout: number of sessions, total volume, volume trend (first vs second half of the period), personal records (an exercise whose maximum weight in the period beats all of its earlier history; list exercise, new weight, date).
- Food: average per day of calories, protein, carbs, fat; versus targets where set (number of days the target was met or kept).

## 8. Google Drive backup

- Storage: the hidden app data folder (`drive.appdata` scope). One file `backup.json` plus `backup.prev.json`.
- Backup content (JSON with `schema_version` and `exported_at`): custom exercises, presets, preset_exercises, sessions, session_exercises, sets, food_entries, custom foods, nutrition_targets, body_weights, and settings `weight_unit` and `height_cm`. Exclude the Open Food Facts cache and the seeded exercises. On restore, `food_id` values that point to missing rows become NULL.
- Upload flow: before overwriting, copy the current `backup.json` to `backup.prev.json`, then write the new file.
- **Safety rules (important):**
  1. Never upload while local data is empty.
  2. On first connect, if a remote backup exists: show the Drive connect/restore screen with the backup date and two choices: **Restore (recommended)** or **Start fresh** (asks to confirm; overwrites the remote file only after the previous one is kept as `backup.prev.json`). Nothing uploads until the user chooses.
  3. Restore replaces local data inside a single database transaction, after a confirmation.
  4. Failures must be visible in Profile (last backup time + error), never silent. Retry later automatically.
- Triggers: (phase 1) when the app goes to the background and data changed since `last_backup_at`, plus the "Back up now" button. (phase 2) a unique, network-constrained `workmanager` periodic task (daily). The background isolate must open its own database connection.
- Setup: the Android OAuth client needs the package name and the signing SHA-1 (register both debug and release). Document this in the README, because forks need their own Google Cloud project. Never commit secrets.

## 9. Exercise dataset

- Source: GitHub `yuhonas/free-exercise-db` - 873 exercises, `dist/exercises.json` (about 1 MB), images at `exercises/<id>/0.jpg` and `1.jpg` (about 750x500 JPEG). Inspect the JSON to confirm field names.
- Write a one-off script `tools/prepare_exercises.py` (Python + Pillow) that outputs `assets/exercises/exercises.json` (trimmed to: id, name, primary muscle, secondary muscles, equipment, instructions) and `assets/exercises/img/<id>.webp`.
- Use only the first image (`0.jpg`), resized to a maximum width of 400 px, WebP quality 60. Measured result: about 8 MB for all 873 images. Total asset budget (images + JSON): under 10 MB. Look at a sample of converted images before committing.
- The two-line description is built from the first one or two instruction steps (truncate to fit).
- On first launch, import the JSON into `exercises` (`is_custom = 0`). Never overwrite custom exercises. Image assets are declared in `pubspec.yaml`.

## 10. Licences and attribution

- Open Food Facts data: ODbL. Show attribution wherever its data appears, and in About / Licences.
- free-exercise-db: published under the Unlicense (public domain). Its images came from an upstream dataset and their original provenance is unverified. Fine for personal use; before a Play Store release, review the repo's licence and open issues.
- Repository licence: TBD by the owner (MIT or GPL candidates). Do not add one without asking.

## 11. Quality bar

- Tests (keep them focused): preset ranking, session lifecycle (start, end, discard-empty, auto-end), unit conversion, derived non-saturated fat, CSV output format, backup export -> wipe -> restore round trip.
- Accessibility: tap targets at least 48 dp, labels on icon buttons, support system text scaling, sufficient contrast in both themes.
- Never lose data silently: use transactions for multi-row writes and restore; confirm destructive actions.

## 12. Milestones (build in order)

1. **Setup:** Flutter project, lint, drift database with migrations, asset preparation script, first-launch seed import, theme, navigation shell. *Done when:* app boots and 873 exercises are in the database.
2. **Core logging:** library, preset editor, Workout screen with ranking, session, Exercise screen, Mix flow, Save as preset. *Done when:* a user can create a preset, start, log sets, end, and an in-progress session survives killing the app.
3. **Home and volume chart:** Home screen, Analyse range chips and volume chart.
4. **Food and Profile:** food log, Add food (Open Food Facts, custom, quick add), Profile (targets, units, height, body weight).
5. **Analyse intake and chart image:** nutrient intake chart with target line, save chart as image.
6. **Exports:** Export dialog, CSV, PDF summary.
7. **Drive backup:** connect, backup, restore with the safety rules, Profile status.
8. **Polish:** About / Licences, accessibility pass, app icon, README (including OAuth setup), Play Store checklist (check Google Play's current payments policy before keeping the coffee link in a store build).

## 13. Assumed defaults and open items

Assumed (change if wrong):
- Auto-end of forgotten sessions (section 4).
- Home chart metric is weekly training volume per day.
- Images: first image only, 400 px, quality 60 (total about 8 MB).
- Food log has previous/next day navigation; Analyse intake chart defaults to calories.
- Library multi-select when opened from the Preset editor; custom exercises cannot be deleted in v1.
- Android Auto Backup is left at its default as an extra safety net.

Open or not yet designed:
- No screen to browse or edit past sessions or per-exercise history yet (data is stored, only prefill uses it).
- "Recently used exercises" in the library picker: optional idea, not decided.
- Final Mix tagline wording, coffee link URL, repository licence.
