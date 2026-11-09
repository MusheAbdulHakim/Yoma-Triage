/// Times and ages as a CHO reads them: the phone's own clock format and time zone,
/// "Today" / "Yesterday" rather than dates, and correct plurals. Never a raw ISO string.
library;

import 'package:flutter/material.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

/// The clock time in the phone's format (12- or 24-hour, as set on the phone).
String clockTime(BuildContext context, DateTime at) {
  final local = at.toLocal();
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

/// "17:43" today, "Yesterday, 09:12", otherwise "5 Nov, 09:12".
String shortWhen(BuildContext context, DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final today = _day(now ?? DateTime.now());
  final day = _day(local);
  final time = clockTime(context, local);
  if (day == today) return time;
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $time';
  return '${local.day} ${_months[local.month - 1]}, $time';
}

/// "Today, 17:43", "Yesterday, 09:12", otherwise "5 Nov, 09:12".
String friendlyWhen(BuildContext context, DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final short = shortWhen(context, local, now: now);
  return _day(local) == _day(now ?? DateTime.now()) ? 'Today, $short' : short;
}

/// "just now", "1 minute ago", "5 minutes ago", "1 hour ago", "2 days ago".
String ago(Duration age) {
  if (age.isNegative || age.inSeconds < 45) return 'just now';
  if (age.inMinutes < 60) return '${_count(age.inMinutes < 1 ? 1 : age.inMinutes, 'minute')} ago';
  if (age.inHours < 24) return '${_count(age.inHours, 'hour')} ago';
  return '${_count(age.inDays, 'day')} ago';
}

/// "1 minute", "2 minutes".
String countOf(int n, String unit) => _count(n, unit);

String _count(int n, String unit) => '$n ${n == 1 ? unit : '${unit}s'}';

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
