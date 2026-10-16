import 'package:flutter/material.dart';

/// Stable, JSON-friendly icon keys. Using named keys instead of raw
/// IconData codePoints avoids Flutter's icon tree-shaking analysis warning
/// ("Argument 'codePoint' must be a constant") when persisting icons.
const Map<String, IconData> kHistoryIcons = {
  'calendar': Icons.calendar_today,
  'event': Icons.event,
  'time': Icons.access_time,
  'cloud': Icons.cloud,
  'location': Icons.location_on,
  'help': Icons.help_outline,
  'error': Icons.error_outline,
};

String iconKeyFor(IconData icon) {
  for (final entry in kHistoryIcons.entries) {
    if (entry.value == icon) return entry.key;
  }
  return 'help';
}

/// Represents one entry in "Riwayat Perintah" (command history).
/// Covers the use case: Mendapatkan informasi (hari/tanggal/cuaca/lokasi)
/// and keeps a record so the user can review what the app told them before.
class CommandHistoryItem {
  final String title; // e.g. "Hari", "Cuaca"
  final String value; // e.g. "Senin", "Berawan, 29°C"
  final DateTime timestamp;
  final String iconKey; // key into kHistoryIcons
  final bool isError; // true when this entry represents an error message

  CommandHistoryItem({
    required this.title,
    required this.value,
    required this.timestamp,
    required IconData icon,
    this.isError = false,
  }) : iconKey = iconKeyFor(icon);

  IconData get icon => kHistoryIcons[iconKey] ?? Icons.help_outline;

  Map<String, dynamic> toJson() => {
        'title': title,
        'value': value,
        'timestamp': timestamp.toIso8601String(),
        'iconKey': iconKey,
        'isError': isError,
      };

  factory CommandHistoryItem.fromJson(Map<String, dynamic> json) {
    return CommandHistoryItem(
      title: json['title'] as String,
      value: json['value'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      icon: kHistoryIcons[json['iconKey'] as String? ?? 'help'] ??
          Icons.help_outline,
      isError: json['isError'] as bool? ?? false,
    );
  }
}
