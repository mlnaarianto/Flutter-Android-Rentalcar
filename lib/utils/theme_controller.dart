import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  ThemeController._();

  /// Satu-satunya sumber kebenaran untuk tema saat ini.
  static final ValueNotifier<ThemeMode> notifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static const _prefsKey = 'theme_mode';

  /// Panggil sekali di main() sebelum runApp untuk memuat pilihan terakhir user.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null) {
      notifier.value = ThemeMode.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => ThemeMode.system,
      );
    }
  }

  /// Ubah tema sekaligus simpan ke storage.
  static Future<void> set(ThemeMode mode) async {
    notifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  /// Helper untuk toggle cepat (light <-> dark), abaikan system.
  static void toggle() {
    set(notifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}