import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A paired (or being paired) Android TV with metadata.
class TvDevice {
  final String id;
  final String name;
  final String host;
  final String? manufacturer;
  final String? model;

  const TvDevice({
    required this.id,
    required this.name,
    required this.host,
    this.manufacturer,
    this.model,
  });

  TvDevice copyWith({
    String? name,
    String? host,
    String? manufacturer,
    String? model,
  }) =>
      TvDevice(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        manufacturer: manufacturer ?? this.manufacturer,
        model: model ?? this.model,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        if (manufacturer != null) 'manufacturer': manufacturer,
        if (model != null) 'model': model,
      };

  factory TvDevice.fromJson(Map<String, dynamic> j) => TvDevice(
        id: j['id'] as String,
        name: j['name'] as String,
        host: j['host'] as String,
        manufacturer: j['manufacturer'] as String?,
        model: j['model'] as String?,
      );
}

/// Persists the list of TVs and the currently selected one.
class TvStore {
  static const _tvsKey = 'tvs';
  static const _selectedKey = 'tvs.selected';
  static const _savedPairingsKey = 'tvs.saved_pairings';

  Future<(List<TvDevice>, String?)> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tvsKey);
    final list = raw == null
        ? <TvDevice>[]
        : (jsonDecode(raw) as List)
            .map((e) => TvDevice.fromJson(e as Map<String, dynamic>))
            .toList();
    return (list, prefs.getString(_selectedKey));
  }

  Future<void> save(List<TvDevice> tvs, String? selectedId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _tvsKey, jsonEncode(tvs.map((e) => e.toJson()).toList()));
    if (selectedId == null) {
      await prefs.remove(_selectedKey);
    } else {
      await prefs.setString(_selectedKey, selectedId);
    }
  }

  Future<List<TvDevice>> loadSavedPairings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedPairingsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => TvDevice.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSavedPairings(List<TvDevice> pairings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedPairingsKey,
      jsonEncode(pairings.map((e) => e.toJson()).toList()),
    );
  }
}
