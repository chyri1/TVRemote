import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppShortcutConfig {
  final String id;
  final String label;
  final String link;
  final int color;
  final bool enabled;
  final bool isCustom;

  const AppShortcutConfig({
    required this.id,
    required this.label,
    required this.link,
    required this.color,
    this.enabled = true,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'link': link,
        'color': color,
        'enabled': enabled,
        'isCustom': isCustom,
      };

  factory AppShortcutConfig.fromJson(Map<String, dynamic> json) =>
      AppShortcutConfig(
        id: json['id'] as String,
        label: json['label'] as String,
        link: json['link'] as String,
        color: json['color'] as int? ?? 0xFF4A90E2,
        enabled: json['enabled'] as bool? ?? true,
        isCustom: json['isCustom'] as bool? ?? false,
      );

  AppShortcutConfig copyWith({
    String? id,
    String? label,
    String? link,
    int? color,
    bool? enabled,
    bool? isCustom,
  }) =>
      AppShortcutConfig(
        id: id ?? this.id,
        label: label ?? this.label,
        link: link ?? this.link,
        color: color ?? this.color,
        enabled: enabled ?? this.enabled,
        isCustom: isCustom ?? this.isCustom,
      );
}

enum ScreenMirrorOption {
  no,
  sessionOnly,
  yes,
}

class AppSettings extends ChangeNotifier {
  static const _themeKey = 'app.theme';
  static const _localeKey = 'app.locale';
  static const _animationDurationKey = 'app.animation_duration_ms';
  static const _volumeStepKey = 'app.volume_step';
  static const _featuredAppsKey = 'app.featured_apps';
  static const _screenMirrorKey = 'app.screen_mirror_mode';
  static const _useMinimalAdbKey = 'app.use_minimal_adb';
  static const _manualCommandKey = 'app.manual_command_enabled';
  static const _showRawPackageNameKey = 'app.show_raw_package_name';

  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;
  int _animationDurationMs = 100;
  int _volumeStep = 1;
  static void Function()? onSettingsSaved;

  ScreenMirrorOption _screenMirrorOption = ScreenMirrorOption.yes;
  bool _useMinimalAdb = true;
  bool _manualCommandEnabled = false;
  bool _showRawPackageName = false;
  List<AppShortcutConfig> _featuredApps = [];

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;
  Locale get effectiveLocale {
    if (_locale != null) return _locale!;
    final sys = WidgetsBinding.instance.platformDispatcher.locale;
    if (sys.languageCode == 'pt' || sys.languageCode == 'es') {
      return Locale(sys.languageCode);
    }
    return const Locale('en');
  }
  int get animationDurationMs => _animationDurationMs;
  Duration get animationDuration =>
      Duration(milliseconds: _animationDurationMs);
  int get volumeStep => _volumeStep;
  ScreenMirrorOption get screenMirrorOption => _screenMirrorOption;
  bool get screenMirrorEnabled =>
      _screenMirrorOption == ScreenMirrorOption.yes ||
      _screenMirrorOption == ScreenMirrorOption.sessionOnly;
  bool get useMinimalAdb => _useMinimalAdb;
  bool get manualCommandEnabled => _manualCommandEnabled;
  bool get showRawPackageName => _showRawPackageName;
  String get screenSaverTitle => getScreenSaverTitle();
  List<AppShortcutConfig> get featuredApps =>
      List.unmodifiable(_featuredApps);
  List<AppShortcutConfig> get enabledApps =>
      _featuredApps.where((a) => a.enabled).toList();

  static final AppSettings instance = AppSettings._();
  AppSettings._();

  static List<AppShortcutConfig> get _defaultApps => const [
        AppShortcutConfig(
          id: 'youtube',
          label: 'YouTube',
          link: 'https://www.youtube.com',
          color: 0xFFFF0033,
          enabled: true,
        ),
        AppShortcutConfig(
          id: 'netflix',
          label: 'Netflix',
          link: 'https://www.netflix.com/title',
          color: 0xFFE50914,
          enabled: true,
        ),
        AppShortcutConfig(
          id: 'disney',
          label: 'Disney+',
          link: 'https://www.disneyplus.com',
          color: 0xFF113CCF,
          enabled: true,
        ),
        AppShortcutConfig(
          id: 'max',
          label: 'Max',
          link: 'https://play.max.com',
          color: 0xFF002BE7,
          enabled: true,
        ),
        AppShortcutConfig(
          id: 'settings',
          label: 'Configurações',
          link: 'settings',
          color: 0xFF546E7A,
          enabled: true,
        ),
        AppShortcutConfig(
          id: 'prime',
          label: 'Prime Video',
          link: 'https://app.primevideo.com',
          color: 0xFF00A8E1,
          enabled: false,
        ),
        AppShortcutConfig(
          id: 'spotify',
          label: 'Spotify',
          link: 'spotify:',
          color: 0xFF1DB954,
          enabled: false,
        ),
        AppShortcutConfig(
          id: 'globoplay',
          label: 'Globoplay',
          link: 'globoplay:',
          color: 0xFFFB3B11,
          enabled: false,
        ),
        AppShortcutConfig(
          id: 'twitch',
          label: 'Twitch',
          link: 'twitch://',
          color: 0xFF9146FF,
          enabled: false,
        ),
      ];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeStr = prefs.getString(_themeKey);
    if (themeStr == 'light') {
      _themeMode = ThemeMode.light;
    } else if (themeStr == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }

    final localeStr = prefs.getString(_localeKey);
    if (localeStr != null && localeStr.isNotEmpty && localeStr != 'system') {
      _locale = Locale(localeStr);
    } else {
      _locale = null;
    }

    _animationDurationMs = prefs.getInt(_animationDurationKey) ?? 100;
    _volumeStep = prefs.getInt(_volumeStepKey) ?? 1;
    _useMinimalAdb = prefs.getBool(_useMinimalAdbKey) ?? true;
    _manualCommandEnabled = prefs.getBool(_manualCommandKey) ?? false;
    _showRawPackageName = prefs.getBool(_showRawPackageNameKey) ?? false;

    // Se ainda não configurado (primeiro uso), o espelhamento de tela inicia como SIM (yes) por padrão.
    final mirrorPref = prefs.getString(_screenMirrorKey);
    if (mirrorPref == null) {
      _screenMirrorOption = ScreenMirrorOption.yes;
    } else if (mirrorPref == 'yes' || prefs.getBool('app.screen_mirror_enabled') == true) {
      _screenMirrorOption = ScreenMirrorOption.yes;
    } else {
      _screenMirrorOption = ScreenMirrorOption.no;
    }

    final appsJson = prefs.getString(_featuredAppsKey);
    if (appsJson != null && appsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(appsJson) as List;
        _featuredApps = decoded
            .map((e) => AppShortcutConfig.fromJson(e as Map<String, dynamic>))
            .toList();
        if (!_featuredApps.any((a) => a.id == 'settings')) {
          _featuredApps.add(const AppShortcutConfig(
            id: 'settings',
            label: 'Configurações',
            link: 'settings',
            color: 0xFF546E7A,
            enabled: true,
          ));
        }
      } catch (_) {
        _featuredApps = List.from(_defaultApps);
      }
    } else {
      _featuredApps = List.from(_defaultApps);
    }

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (mode == ThemeMode.system) {
      await prefs.remove(_themeKey);
    } else {
      await prefs.setString(
          _themeKey, mode == ThemeMode.light ? 'light' : 'dark');
    }
  }

  Future<void> setLocale(Locale? loc) async {
    _locale = loc;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (loc == null) {
      await prefs.remove(_localeKey);
    } else {
      await prefs.setString(_localeKey, loc.languageCode);
    }
  }

  Future<void> setAnimationDuration(int ms) async {
    _animationDurationMs = ms.clamp(0, 1000);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_animationDurationKey, _animationDurationMs);
  }

  Future<void> setVolumeStep(int step) async {
    _volumeStep = step.clamp(1, 100);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_volumeStepKey, _volumeStep);
  }

  Future<void> setScreenMirrorOption(ScreenMirrorOption opt) async {
    final wasEnabled = screenMirrorEnabled;
    _screenMirrorOption = opt;
    final nowEnabled = screenMirrorEnabled;
    if (wasEnabled != nowEnabled && _manualWindowHeight != null) {
      if (!nowEnabled) {
        _manualWindowHeight = (_manualWindowHeight! - 230.0).clamp(280.0, 960.0);
      } else {
        _manualWindowHeight = (_manualWindowHeight! + 230.0).clamp(280.0, 960.0);
      }
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (opt == ScreenMirrorOption.yes) {
      await prefs.setString(_screenMirrorKey, 'yes');
    } else {
      await prefs.setString(_screenMirrorKey, 'no');
    }
  }

  void setScreenMirrorEnabled(bool enabled) {
    setScreenMirrorOption(enabled ? ScreenMirrorOption.sessionOnly : ScreenMirrorOption.no);
  }

  // Redimensionamento manual de janela (apenas durante a sessão em memória)
  double? _manualWindowHeight;
  double? get manualWindowHeight => _manualWindowHeight;
  bool get hasManualWindowHeight => _manualWindowHeight != null;

  void setManualWindowHeight(double height) {
    if (_manualWindowHeight != height) {
      _manualWindowHeight = height;
      notifyListeners();
    }
  }

  void resetManualWindowHeight() {
    if (_manualWindowHeight != null) {
      _manualWindowHeight = null;
      notifyListeners();
    }
  }

  Future<void> setManualCommandEnabled(bool enabled) async {
    final wasEnabled = _manualCommandEnabled;
    _manualCommandEnabled = enabled;
    if (wasEnabled != enabled && _manualWindowHeight != null) {
      if (!enabled) {
        _manualWindowHeight = (_manualWindowHeight! - 70.0).clamp(280.0, 960.0);
      } else {
        _manualWindowHeight = (_manualWindowHeight! + 70.0).clamp(280.0, 960.0);
      }
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_manualCommandKey, enabled);
  }

  Future<void> toggleApp(String id, bool enabled) async {
    final idx = _featuredApps.indexWhere((a) => a.id == id);
    if (idx != -1) {
      _featuredApps[idx] = _featuredApps[idx].copyWith(enabled: enabled);
      notifyListeners();
      await _saveApps();
    }
  }

  Future<void> reorderApps(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _featuredApps.length) return;
    if (newIndex < 0 || newIndex >= _featuredApps.length) return;
    final item = _featuredApps.removeAt(oldIndex);
    _featuredApps.insert(newIndex, item);
    notifyListeners();
    await _saveApps();
  }

  Future<void> moveApp(int fromIndex, int toIndex) async {
    if (fromIndex < 0 || fromIndex >= _featuredApps.length) return;
    if (toIndex < 0 || toIndex >= _featuredApps.length) return;
    if (fromIndex == toIndex) return;
    final item = _featuredApps.removeAt(fromIndex);
    _featuredApps.insert(toIndex, item);
    notifyListeners();
    await _saveApps();
  }

  Future<void> addCustomApp(String label, String link, [int? color]) async {
    final newApp = AppShortcutConfig(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      label: label.trim(),
      link: link.trim(),
      color: color ?? 0xFF00B4D8,
      enabled: true,
      isCustom: true,
    );
    _featuredApps.add(newApp);
    notifyListeners();
    await _saveApps();
  }

  Future<void> removeCustomApp(String id) async {
    _featuredApps.removeWhere((a) => a.id == id && a.isCustom);
    notifyListeners();
    await _saveApps();
  }

  Future<void> setUseMinimalAdb(bool value) async {
    _useMinimalAdb = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useMinimalAdbKey, value);
    notifyListeners();
  }

  Future<void> setShowRawPackageName(bool value) async {
    _showRawPackageName = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showRawPackageNameKey, value);
    notifyListeners();
  }

  Future<void> _saveApps() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_featuredApps.map((a) => a.toJson()).toList());
    await prefs.setString(_featuredAppsKey, encoded);
    onSettingsSaved?.call();
  }
}

/// Função universal de internacionalização para os idiomas suportados (PT, EN, ES).
String appTr({required String pt, required String en, required String es}) {
  final code = AppSettings.instance.effectiveLocale.languageCode.toLowerCase();
  if (code.startsWith('es')) return es;
  if (code.startsWith('en')) return en;
  return pt;
}

/// Retorna o nome amigável para o protetor de tela / backdrop nos idiomas suportados (PT, EN, ES).
String getScreenSaverTitle() {
  return appTr(
    pt: 'Protetor de tela',
    en: 'Screen saver',
    es: 'Salvapantallas',
  );
}
