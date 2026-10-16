import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/command_history_item.dart';

/// Keeps the "Riwayat Perintah" (command history) list, persisted locally
/// so it survives app restarts.
class HistoryProvider extends ChangeNotifier {
  final List<CommandHistoryItem> _items = [];

  List<CommandHistoryItem> get items => List.unmodifiable(_items.reversed);

  HistoryProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('history') ?? [];
    _items
      ..clear()
      ..addAll(raw.map((s) => CommandHistoryItem.fromJson(jsonDecode(s))));
    notifyListeners();
  }

  Future<void> add(CommandHistoryItem item) async {
    _items.add(item);
    // Keep history from growing unbounded.
    if (_items.length > 100) {
      _items.removeAt(0);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'history',
      _items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('history');
  }
}
