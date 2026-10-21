import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_lang.dart';

/// The language of the app: follows the phone (default) or the one the user
/// picked in the menu.
class LanguageState extends ChangeNotifier with WidgetsBindingObserver {
  static const storageKey = 'language_v1';

  /// `es`, `en`, or null to follow the phone.
  String? _choice;
  String? get choice => _choice;

  Locale get locale => Locale(AppLang.code);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);
    _choice = AppLang.supported.contains(saved) ? saved : null;
    _apply();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The phone's language changed: follow it unless the user picked one.
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_choice == null) _change();
  }

  Future<void> setChoice(String? choice) async {
    if (choice == _choice) return;
    _choice = choice;
    final prefs = await SharedPreferences.getInstance();
    if (choice == null) {
      await prefs.remove(storageKey);
    } else {
      await prefs.setString(storageKey, choice);
    }
    _change();
  }

  void _apply() {
    AppLang.code = _choice ??
        AppLang.fromSystem(PlatformDispatcher.instance.locale.languageCode);
  }

  void _change() {
    final before = AppLang.code;
    _apply();
    if (AppLang.code == before) {
      notifyListeners();
      return;
    }
    notifyListeners();
    // The texts come from tr() and not from the widget tree, so widgets that
    // did not change would keep the old language: rebuild everything.
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
    onLanguageChanged?.call();
  }

  /// Called after the language changed (to redo the alarms with the new text).
  VoidCallback? onLanguageChanged;
}
