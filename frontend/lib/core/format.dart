import 'package:intl/intl.dart';

String fmtTime(String? iso) {
  if (iso == null) return '-';
  final t = DateTime.tryParse(iso)?.toLocal();
  return t == null ? '-' : DateFormat('HH:mm:ss').format(t);
}

String fmtDateTime(String? iso) {
  if (iso == null) return '-';
  final t = DateTime.tryParse(iso)?.toLocal();
  return t == null ? '-' : DateFormat('d MMM, HH:mm:ss').format(t);
}

String ago(String? iso) {
  if (iso == null) return 'never';
  final t = DateTime.tryParse(iso);
  if (t == null) return '-';
  final d = DateTime.now().toUtc().difference(t.toUtc());
  if (d.inSeconds < 0) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  return '${d.inHours}h ${d.inMinutes % 60}m ago';
}

String fmtNum(dynamic v, {int digits = 1, String suffix = ''}) {
  if (v == null) return '-';
  final n = (v as num).toDouble();
  return '${n.toStringAsFixed(digits)}$suffix';
}

String fmtDuration(num? seconds) {
  if (seconds == null) return '-';
  final s = seconds.round();
  if (s < 60) return '${s}s';
  return '${s ~/ 60}m ${s % 60}s';
}

String pct(dynamic v) => v == null ? '-' : '${((v as num) * 100).toStringAsFixed(1)}%';

String humanize(String? id) {
  if (id == null || id.isEmpty) return '-';
  final s = id.replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

const regimeLabels = {
  'continuous': 'Continuous (60/0)',
  '45_15': '45 work / 15 rest',
  '30_30': '30 work / 30 rest',
  '15_45': '15 work / 45 rest',
};

/// Site-local time label for Abu Dhabi sites (Gulf Standard Time, UTC+4).
String siteTime(String? clock, {String? date}) {
  if (clock == null) return '-';
  if (date == null) return '$clock GST';
  final d = DateTime.tryParse(date);
  return d == null ? '$clock GST' : '${DateFormat('d MMM').format(d)}, $clock GST';
}
