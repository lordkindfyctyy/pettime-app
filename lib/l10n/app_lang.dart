import 'en.dart';

/// The language the app is showing right now: `es` or `en`. [LanguageState]
/// sets it from the user's choice or from the phone's language.
class AppLang {
  AppLang._();

  static const supported = ['es', 'en'];

  static String code = 'es';

  static bool get isEnglish => code == 'en';

  /// `es` when the phone is in Spanish, `en` for any other language.
  static String fromSystem(String languageCode) =>
      languageCode == 'es' ? 'es' : 'en';
}

//// A number written with a point ("2.5") as it is read in the language of the
/// app: with a decimal comma in Spanish.
String localizedDecimal(String number) =>
    AppLang.isEnglish ? number : number.replaceAll('.', ',');

/// Translates a text written in Spanish. The Spanish text is the key: in
/// English it is looked up in [enStrings], and a text without translation is
/// shown in Spanish. `{name}` marks are replaced with the values in [args]:
///
///     tr('Toma de {name} registrada', {'name': med.name})
String tr(String es, [Map<String, Object?>? args]) {
  final text = AppLang.isEnglish ? (enStrings[es] ?? es) : es;
  if (args == null) return text;
  // One pass over the text: a value that looks like a mark (a pet called
  // "{n}") is not replaced again.
  return text.replaceAllMapped(
    RegExp(r'\{(\w+)\}'),
    (m) => args.containsKey(m[1]) ? '${args[m[1]]}' : m[0]!,
  );
}
