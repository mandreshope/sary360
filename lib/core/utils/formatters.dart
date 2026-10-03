/// Mise en forme des dates et tailles pour l'interface (français, sans
/// dépendance à intl).
abstract final class Formatters {
  static const _months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', //
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];

  /// « 3 oct. 2026 »
  static String date(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// « 02:53 »
  static String time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// « 3 oct. 2026 · 02:53 »
  static String dateTime(DateTime d) => '${date(d)} · ${time(d)}';

  /// « 642 Ko », « 3,4 Mo »
  static String bytes(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }
}
