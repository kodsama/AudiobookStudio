/// Locates and parses an EPUB's OPF package document.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Structured result of reading the OPF: metadata, reading order, and the
/// information needed to locate the cover image.
class OpfData {
  /// `dc:title`, or empty if absent.
  final String title;

  /// `dc:creator`, or empty if absent.
  final String author;

  /// `dc:language` (ISO 639-1), defaulting to `en`.
  final String languageCode;

  /// Archive paths of spine documents, in reading order.
  final List<String> spineHrefs;

  /// Map of manifest archive path → media type (e.g. `image/jpeg`).
  final Map<String, String> mediaTypes;

  /// Archive path of the declared cover image, if the OPF identified one.
  final String? coverHref;

  /// Map of spine archive path (fragment stripped) → its table-of-contents
  /// title, from the EPUB3 nav document or EPUB2 NCX. Used to title chapters
  /// that have no in-document heading.
  final Map<String, String> tocTitles;

  const OpfData({
    required this.title,
    required this.author,
    required this.languageCode,
    required this.spineHrefs,
    required this.mediaTypes,
    this.coverHref,
    this.tocTitles = const {},
  });
}

/// Reads the OPF package document from an in-memory EPUB [Archive].
class OpfReader {
  /// Parses the OPF and returns structured [OpfData].
  ///
  /// Throws [FormatException] if the archive is not a valid EPUB (missing
  /// container or package document).
  OpfData read(Archive archive) {
    final opfPath = _findOpfPath(archive);
    final opfDir = p.url.dirname(opfPath);
    final opfXml = _readString(archive, opfPath);
    final doc = XmlDocument.parse(opfXml);
    final pkg = doc.rootElement;

    String dc(String name) {
      final el = pkg
          .findAllElements(name, namespaceUri: '*')
          .where((e) => e.qualifiedName.endsWith(name))
          .firstOrNull;
      return el?.innerText.trim() ?? '';
    }

    // Resolve a manifest href (relative to the OPF dir) to an archive path.
    String resolve(String href) =>
        p.url.normalize(p.url.join(opfDir, href));

    // Manifest: id -> archive path, and archive path -> media type.
    final idToHref = <String, String>{};
    final mediaTypes = <String, String>{};
    String? coverIdHref;
    String? navHref; // EPUB3 nav document
    String? ncxHref; // EPUB2 NCX
    for (final item in pkg.findAllElements('item', namespaceUri: '*')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      final media = item.getAttribute('media-type') ?? '';
      if (id == null || href == null) continue;
      final path = resolve(href);
      idToHref[id] = path;
      mediaTypes[path] = media;
      final props = item.getAttribute('properties') ?? '';
      // EPUB3 cover marker.
      if (props.contains('cover-image')) coverIdHref = path;
      if (props.split(RegExp(r'\s+')).contains('nav')) navHref = path;
      if (media == 'application/x-dtbncx+xml') ncxHref = path;
    }

    // EPUB2 cover marker: <meta name="cover" content="cover-id"/>.
    if (coverIdHref == null) {
      for (final meta in pkg.findAllElements('meta', namespaceUri: '*')) {
        if (meta.getAttribute('name') == 'cover') {
          final id = meta.getAttribute('content');
          coverIdHref = id == null ? null : idToHref[id];
          break;
        }
      }
    }

    // Spine: ordered itemref -> manifest id -> archive path.
    final spine = <String>[];
    for (final ref in pkg.findAllElements('itemref', namespaceUri: '*')) {
      final idref = ref.getAttribute('idref');
      final path = idref == null ? null : idToHref[idref];
      if (path != null) spine.add(path);
    }

    final lang = dc('language');
    return OpfData(
      title: dc('title'),
      author: dc('creator'),
      languageCode: lang.isEmpty ? 'en' : lang.split('-').first.toLowerCase(),
      spineHrefs: spine,
      mediaTypes: mediaTypes,
      coverHref: coverIdHref,
      tocTitles: _readToc(archive, navHref, ncxHref),
    );
  }

  /// Builds a map of spine archive path → table-of-contents title from the
  /// EPUB3 nav document (preferred) or EPUB2 NCX. Fragments are stripped so the
  /// first entry pointing into a file titles that whole spine document. Failures
  /// are swallowed — the TOC is an enhancement, not required.
  Map<String, String> _readToc(Archive archive, String? navHref, String? ncxHref) {
    final out = <String, String>{};
    final path = navHref ?? ncxHref;
    if (path == null) return out;
    try {
      final dir = p.url.dirname(path);
      final doc = XmlDocument.parse(_readString(archive, path));
      String target(String href) =>
          p.url.normalize(p.url.join(dir, href.split('#').first));
      String clean(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

      if (navHref != null) {
        // EPUB3: <nav><ol><li><a href="file#frag">Title</a>…
        for (final a in doc.findAllElements('a', namespaceUri: '*')) {
          final href = a.getAttribute('href');
          final text = clean(a.innerText);
          if (href == null || text.isEmpty) continue;
          out.putIfAbsent(target(href), () => text);
        }
      } else {
        // EPUB2 NCX: <navPoint><navLabel><text>Title</text></navLabel>
        //            <content src="file#frag"/></navPoint>
        for (final np in doc.findAllElements('navPoint', namespaceUri: '*')) {
          final text = clean(
              np.findAllElements('text', namespaceUri: '*').firstOrNull?.innerText ?? '');
          final src = np
              .findAllElements('content', namespaceUri: '*')
              .firstOrNull
              ?.getAttribute('src');
          if (text.isEmpty || src == null) continue;
          out.putIfAbsent(target(src), () => text);
        }
      }
    } on Object {
      // Malformed TOC — ignore and fall back to in-document headings.
    }
    return out;
  }

  /// Finds the OPF path via `META-INF/container.xml`.
  String _findOpfPath(Archive archive) {
    final container = _readString(archive, 'META-INF/container.xml');
    final doc = XmlDocument.parse(container);
    final rootfile = doc.findAllElements('rootfile', namespaceUri: '*').firstOrNull;
    final fullPath = rootfile?.getAttribute('full-path');
    if (fullPath == null) {
      throw const FormatException('EPUB container.xml has no rootfile');
    }
    return fullPath;
  }

  /// Reads an archive entry as UTF-8 text, throwing if it is missing.
  String _readString(Archive archive, String path) {
    final file = archive.files.firstWhere(
      (f) => f.name == path,
      orElse: () => throw FormatException('EPUB missing entry: $path'),
    );
    return utf8.decode(file.content as List<int>, allowMalformed: true);
  }
}
