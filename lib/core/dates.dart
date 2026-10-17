/// Local-day helpers. Timestamps are stored as UTC epoch milliseconds;
/// a "day" always means the device's local calendar day.
library;

const List<String> MONTH_NAMES = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const List<String> WEEKDAY_NAMES = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> WEEKDAY_SHORT = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

DateTime fromMillis(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _two(int v) => v.toString().padLeft(2, '0');

/// YYYY-MM-DD of the local day.
String dayKey(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';

DateTime parseDayKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String formatTime(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String formatDate(DateTime t) => '${t.day} ${MONTH_NAMES[t.month - 1]} ${t.year}';

String formatShortDate(DateTime t) => '${t.day} ${MONTH_NAMES[t.month - 1]}';

String formatDateTime(DateTime t) => '${formatShortDate(t)}, ${formatTime(t)}';

/// "Today", "Yesterday" or e.g. "Mon 12 Oct".
String formatDayLabel(DateTime day, {DateTime? now}) {
  final today = startOfDay(now ?? DateTime.now());
  final d = startOfDay(day);
  if (d == today) return 'Today';
  if (d == addDays(today, -1)) return 'Yesterday';
  final label = '${WEEKDAY_NAMES[d.weekday - 1]} ${formatShortDate(d)}';
  return d.year == today.year ? label : '$label ${d.year}';
}

/// "Today 10:42" or "12 Oct, 21:15".
String formatRelativeDateTime(DateTime t, {DateTime? now}) {
  final today = startOfDay(now ?? DateTime.now());
  if (startOfDay(t) == today) return 'today ${formatTime(t)}';
  return formatDateTime(t);
}

/// Bit for a weekday in the preset bitmask (Mon=1 ... Sun=64).
int weekdayBit(int weekday) => 1 << (weekday - 1);

bool maskHasWeekday(int mask, int weekday) => mask & weekdayBit(weekday) != 0;

/// "Mon, Thu" or "" when no day is set.
String formatDaysMask(int mask) => [
  for (var wd = 1; wd <= 7; wd++)
    if (maskHasWeekday(mask, wd)) WEEKDAY_NAMES[wd - 1],
].join(', ');

/// "01:30" or "1:02:03".
String formatElapsed(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(sec)}' : '${_two(m)}:${_two(sec)}';
}

/// Every local day from [first] to [last], inclusive.
List<DateTime> daysBetween(DateTime first, DateTime last) {
  final days = <DateTime>[];
  var d = startOfDay(first);
  final end = startOfDay(last);
  while (!d.isAfter(end)) {
    days.add(d);
    d = addDays(d, 1);
  }
  return days;
}
