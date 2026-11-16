import 'package:intl/intl.dart';

final _gbp = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);

/// Formats pence. Money out shows with a proper minus sign, like the design.
String money(num pence, {bool signed = false}) {
  final s = _gbp.format(pence.abs() / 100);
  if (pence < 0) return '−$s';
  if (signed && pence > 0) return '+$s';
  return s;
}

String moneyWhole(num pence) => NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 0).format(pence / 100);

/// "1,234.56" or "£1,234.56" → pence. Returns null when it can't be read.
int? parseMoney(String text) {
  var t = text.trim().replaceAll('£', '').replaceAll(',', '').replaceAll('−', '-');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  return v == null ? null : (v * 100).round();
}

DateTime day(String iso) => DateTime.parse(iso);
String dShort(String iso) => DateFormat('d MMM', 'en_GB').format(day(iso));
String dDay(String iso) => DateFormat('EEE d MMM', 'en_GB').format(day(iso));
String dLong(String iso) => DateFormat('EEEE d MMMM yyyy', 'en_GB').format(day(iso));
String dMonth(String ym) => DateFormat('MMM', 'en_GB').format(DateTime.parse('$ym-01'));
String dMonthLong(String ym) => DateFormat('MMMM yyyy', 'en_GB').format(DateTime.parse('$ym-01'));
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
