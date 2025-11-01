import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kThemeModeKey = 'prefs.themeMode'; // 'system' | 'light' | 'dark'

ThemeMode _parseTheme(String? raw) {
  switch (raw) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

String _themeToString(ThemeMode mode) {
  // Returns 'system' | 'light' | 'dark'
  return mode.name;
}

/// Riverpod v3 Notifier-based controller (no StateNotifier).
class ThemeModeController extends Notifier<ThemeMode> {
  // If you later want DI for storage, extract this into a Provider and read via ref.
  late final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  ThemeMode build() {
    // Default immediately, then hydrate asynchronously.
    Future.microtask(() async {
      final saved = await _storage.read(key: _kThemeModeKey);
      if (saved != null) {
        final hydrated = _parseTheme(saved);
        if (hydrated != state) state = hydrated;
      }
    });
    return ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _storage.write(key: _kThemeModeKey, value: _themeToString(mode));
  }
}

/// Provider: NotifierProvider<Controller, State> (Riverpod v3).
final themeModeControllerProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
