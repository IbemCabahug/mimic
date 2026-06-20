import 'package:shared_preferences/shared_preferences.dart';

/// Global word-language selection ('en', 'fil', 'ceb'). Read at round start by
/// assignMimics so the host's choice drives the dealt (and LAN-synced) words.
class LanguageStore {
  static const String _prefsKey = 'word_language';
  static const String defaultLanguage = 'en';
  static String _current = defaultLanguage;

  static String get current => _current;

  /// Call once at startup (after WidgetsFlutterBinding.ensureInitialized()).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.isNotEmpty) {
      _current = saved;
    }
  }

  static Future<void> setLanguage(String code) async {
    _current = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
  }
}
