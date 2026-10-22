/// [name] as a file name: the characters Windows and Android don't allow
/// (`/ \ : * ? " < > |`) become `_`. A pet called "Rocky/Max" would otherwise
/// ask for a folder that doesn't exist.
String safeFileName(String name) {
  final clean = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return clean.isEmpty ? '_' : clean;
}
