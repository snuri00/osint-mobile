import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

enum LlmProvider { anthropic, deepseek, openai }

extension LlmProviderX on LlmProvider {
  String get id => switch (this) {
        LlmProvider.anthropic => 'anthropic',
        LlmProvider.deepseek => 'deepseek',
        LlmProvider.openai => 'openai',
      };

  String get label => switch (this) {
        LlmProvider.anthropic => 'Anthropic',
        LlmProvider.deepseek => 'DeepSeek',
        LlmProvider.openai => 'OpenAI',
      };

  String get defaultModel => switch (this) {
        LlmProvider.anthropic => 'claude-sonnet-5',
        LlmProvider.deepseek => 'deepseek-chat',
        LlmProvider.openai => 'gpt-5.4',
      };

  String get keyHint => switch (this) {
        LlmProvider.anthropic => 'sk-ant-…',
        LlmProvider.deepseek => 'sk-…',
        LlmProvider.openai => 'sk-…',
      };

  String get consoleUrl => switch (this) {
        LlmProvider.anthropic => 'console.anthropic.com',
        LlmProvider.deepseek => 'platform.deepseek.com',
        LlmProvider.openai => 'platform.openai.com',
      };

  static LlmProvider fromId(String id) => LlmProvider.values.firstWhere(
        (p) => p.id == id,
        orElse: () => LlmProvider.anthropic,
      );
}

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  LlmProvider _provider = LlmProvider.anthropic;
  final Map<LlmProvider, String> _keys = {};
  final Map<LlmProvider, String> _models = {};
  OsintThemeMode _theme = OsintThemeMode.dark;

  LlmProvider get provider => _provider;
  OsintThemeMode get theme => _theme;
  String get apiKey => _keys[_provider] ?? '';
  bool get hasKey => apiKey.trim().isNotEmpty;

  String get model =>
      (_models[_provider]?.trim().isNotEmpty ?? false)
          ? _models[_provider]!.trim()
          : _provider.defaultModel;

  static Future<AppSettings> load() async {
    final s = AppSettings._();
    final prefs = await SharedPreferences.getInstance();
    s._provider = LlmProviderX.fromId(prefs.getString('provider') ?? 'anthropic');
    s._theme = (prefs.getString('theme') ?? 'dark') == 'light'
        ? OsintThemeMode.light
        : OsintThemeMode.dark;
    for (final p in LlmProvider.values) {
      final m = prefs.getString('model_${p.id}');
      if (m != null) s._models[p] = m;
      final k = await _secure.read(key: 'apikey_${p.id}');
      if (k != null) s._keys[p] = k;
    }
    return s;
  }

  Future<void> setProvider(LlmProvider p) async {
    _provider = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider', p.id);
    notifyListeners();
  }

  Future<void> setTheme(OsintThemeMode t) async {
    _theme = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', t == OsintThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    _keys[_provider] = key;
    await _secure.write(key: 'apikey_${_provider.id}', value: key);
    notifyListeners();
  }

  Future<void> setModel(String model) async {
    _models[_provider] = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('model_${_provider.id}', model);
    notifyListeners();
  }
}
