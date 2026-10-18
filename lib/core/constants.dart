/// App-wide constants. Values marked "placeholder" must be filled in by the owner.
library;

const String APP_NAME = 'Easy Reps';

/// Keep in sync with `version:` in pubspec.yaml.
const String APP_VERSION = '0.2.0';

/// Placeholder: the owner's "Buy me a coffee" page.
const String COFFEE_URL = 'https://www.buymeacoffee.com/';

/// Placeholder: repository URL or contact used in the Open Food Facts User-Agent.
const String APP_CONTACT = 'https://github.com/mrz004';

const String OFF_USER_AGENT = 'EasyReps/$APP_VERSION ($APP_CONTACT)';
const String OFF_SEARCH_URL = 'https://search.openfoodfacts.org/search';

/// Open Food Facts allows 10 search requests per minute per IP.
const int OFF_SEARCH_LIMIT_PER_MINUTE = 10;
const int OFF_MIN_QUERY_LENGTH = 3;
const Duration OFF_DEBOUNCE = Duration(milliseconds: 500);

const double LB_PER_KG = 2.20462;

const String MIX_NAME = 'Mix';
const String MIX_TAGLINE = "let's go by mood";

/// "Most used" counts finished sessions in this many days.
const int RANKING_WINDOW_DAYS = 60;

const int RECENT_FOODS_LIMIT = 15;

const String EXERCISES_JSON_ASSET = 'assets/exercises/exercises.json';
const String EXERCISE_IMAGE_DIR = 'assets/exercises/img';

const String DRIVE_APPDATA_SCOPE =
    'https://www.googleapis.com/auth/drive.appdata';
const String BACKUP_FILE_NAME = 'backup.json';
const String BACKUP_PREV_FILE_NAME = 'backup.prev.json';
const int BACKUP_SCHEMA_VERSION = 1;

/// Daily `workmanager` backup (phase 2).
const String BACKUP_TASK_UNIQUE_NAME = 'drive-daily-backup';
const String BACKUP_TASK_NAME = 'driveBackup';

/// Web OAuth client id, passed at build time:
/// `flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com`
const String GOOGLE_SERVER_CLIENT_ID = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
);

// Settings keys.
const String SETTING_WEIGHT_UNIT = 'weight_unit';
const String SETTING_HEIGHT_CM = 'height_cm';
const String SETTING_LAST_BACKUP_AT = 'last_backup_at';
const String SETTING_DRIVE_CONNECTED = 'drive_connected';
const String SETTING_BACKUP_ERROR = 'backup_error';
const String SETTING_DATA_CHANGED_AT = 'data_changed_at';
const String SETTING_SEED_COUNT = 'seed_count';
