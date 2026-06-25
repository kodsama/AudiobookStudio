/// Filesystem-safe file-stem derivation, shared by the app and the CLI.
library;

/// Turns a book title into a safe file stem, preserving accents, apostrophes and
/// spaces and stripping only characters that are illegal in file names on common
/// filesystems (`\ / : * ? " < > |` and control chars). Collapses whitespace.
String safeFileStem(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'\s+'), ' ') // tabs/newlines -> space (don't glue words)
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '') // illegal/control chars
      .replaceAll(RegExp(r' +'), ' ') // re-collapse after removals
      .trim();
  return cleaned.isEmpty ? 'audiobook' : cleaned;
}
