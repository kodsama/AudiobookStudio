// Command-line interface for Audiobook Studio.
//
// Reuses the app's Flutter-free data layer (EPUB parsing, sherpa-onnx TTS,
// ffmpeg assembly, model downloads) so the converter can be driven from a
// terminal or an LLM. Use --json for machine-readable output.
//
// Examples:
//   dart run audiobook_studio info book.epub
//   dart run audiobook_studio list-models
//   dart run audiobook_studio download piper
//   dart run audiobook_studio convert book.epub --engine local --model piper
//   dart run audiobook_studio convert book.epub --engine openai --json
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:audiobook_studio/data/audio/ffmpeg_service.dart';
import 'package:audiobook_studio/data/deps/sherpa_model_installer.dart';
import 'package:audiobook_studio/data/epub/epub_parser.dart';
import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/data/tts/backend_factory.dart';
import 'package:audiobook_studio/data/tts/sherpa_catalog.dart';
import 'package:audiobook_studio/data/tts/sherpa_tts_backend.dart';
import 'package:audiobook_studio/data/text/text_chunker.dart';
import 'package:audiobook_studio/domain/book.dart';
import 'package:audiobook_studio/domain/conversion_options.dart';

const _usage = '''
Audiobook Studio — convert an EPUB to a chaptered .m4b audiobook.

Usage: dart run audiobook_studio <command> [options]

Commands:
  info <file.epub>              Show metadata + chapters
  list-models                   List local TTS engines and install state
  download <modelId>            Download a local model (e.g. piper, kokoro)
  convert <file.epub>           Convert to .m4b
  schema                        Print a JSON description of this CLI (for agents)

Convert options:
  --engine <local|openai|elevenlabs>  TTS engine (default: local)
  --model <id>                  local model id (default: best for the language)
  --voice <id>                  cloud voice id (default: a sensible one)
  --language <code>             narration language (default: book's language)
  --speed <x>                   narration speed 0.5–2.0 (default: 1.0)
  --bitrate <b>                 AAC bitrate, e.g. 128k (default: 128k)
  --cover <path>                cover image (default: the EPUB's own)
  --chapters <a,b,c>            only these chapter indices (default: all)
  -o, --output <path>           output .m4b (default: <title>.m4b next to epub)
  --models-dir <dir>            models location (default: ~/.audiobook_studio/models)
  --sherpa-lib <dir>            dir with sherpa dylibs (default: auto-detect)
  --api-key <key>               cloud key (or OPENAI_API_KEY / ELEVENLABS_API_KEY)

Global:
  --json                        machine-readable JSON lines (for scripts/LLMs)
  -h, --help                    show this help
''';

late bool _json;

void main(List<String> argv) async {
  final args = _Args(argv);
  _json = args.flag('json');
  if (args.flag('help') || args.flag('h') || args.positionals.isEmpty) {
    stdout.writeln(_usage);
    return;
  }
  final command = args.positionals.first;
  try {
    switch (command) {
      case 'help':
        stdout.writeln(_usage);
      case 'schema':
        _schema();
      case 'info':
        await _info(args);
      case 'list-models':
        _listModels(args);
      case 'download':
        await _download(args);
      case 'convert':
        await _convert(args);
      default:
        _fail('Unknown command: $command');
    }
  } on Object catch (e) {
    _fail('$e');
  }
}

// --- commands ---

/// Emits a JSON description of the whole CLI so an agent can discover commands,
/// options, available engines/models, output events and exit codes in one call.
void _schema() {
  _emit({
    'name': 'audiobook_studio',
    'description':
        'Convert a DRM-free EPUB into a chaptered .m4b audiobook with local '
            '(offline, free) or cloud text-to-speech.',
    'invocation':
        'dart run audiobook_studio <command> [options]  (or the compiled binary)',
    'globalOptions': [
      {'name': '--json', 'type': 'flag', 'description': 'Emit JSON lines (one object per line) on stdout for machine parsing.'},
      {'name': '--help', 'aliases': ['-h', 'help'], 'type': 'flag', 'description': 'Show usage.'},
    ],
    'commands': [
      {
        'name': 'info',
        'summary': 'Show book metadata and chapters.',
        'args': [{'name': 'file', 'type': 'path', 'required': true, 'description': '.epub file'}],
        'outputJson': {'title': 'string', 'author': 'string', 'language': 'string', 'hasCover': 'bool', 'totalChars': 'int', 'chapters': '[{index:int,title:string,chars:int}]'},
      },
      {
        'name': 'list-models',
        'summary': 'List local TTS engines, sizes, and install state.',
        'args': [],
        'outputJson': {'models': '[{id,label,languages,sizeMb,recommended,installed,blurb}]'},
      },
      {
        'name': 'download',
        'summary': 'Download a local model (all its languages).',
        'args': [{'name': 'modelId', 'type': 'string', 'required': true, 'enum': [for (final m in kSherpaModels) m.id]}],
      },
      {
        'name': 'convert',
        'summary': 'Convert an EPUB to a .m4b audiobook.',
        'args': [{'name': 'file', 'type': 'path', 'required': true, 'description': '.epub file'}],
        'options': [
          {'name': '--engine', 'type': 'enum', 'enum': ['local', 'openai', 'elevenlabs'], 'default': 'local', 'description': 'TTS engine.'},
          {'name': '--model', 'type': 'string', 'enum': [for (final m in kSherpaModels) m.id], 'description': 'Local model id (default: best for the language).'},
          {'name': '--voice', 'type': 'string', 'description': 'Cloud voice id.'},
          {'name': '--language', 'type': 'string', 'description': 'ISO 639-1 code (default: the book\'s language).'},
          {'name': '--speed', 'type': 'number', 'default': 1.0, 'description': '0.5–2.0.'},
          {'name': '--bitrate', 'type': 'string', 'default': '128k', 'description': 'AAC bitrate, e.g. 96k/128k/192k.'},
          {'name': '--cover', 'type': 'path', 'description': 'Cover image override (else the EPUB\'s own).'},
          {'name': '--chapters', 'type': 'string', 'description': 'Comma-separated chapter indices (default: all).'},
          {'name': '--output', 'aliases': ['-o'], 'type': 'path', 'description': 'Output .m4b (default: <title>.m4b next to the epub).'},
          {'name': '--models-dir', 'type': 'path', 'description': 'Where models live (default: ~/.audiobook_studio/models).'},
          {'name': '--sherpa-lib', 'type': 'path', 'description': 'Dir with sherpa native libs (default: auto-detect from a flutter macOS build).'},
          {'name': '--api-key', 'type': 'string', 'description': 'Cloud key (else OPENAI_API_KEY / ELEVENLABS_API_KEY).'},
        ],
      },
    ],
    'jsonEvents': [
      {'event': 'log', 'fields': {'message': 'string'}},
      {'event': 'progress', 'fields': {'phase': 'download|synthesize', 'fraction': 'number 0..1'}},
      {'event': 'done', 'fields': {'output': 'string (path)', 'chapters': 'int'}},
      {'event': 'error', 'fields': {'message': 'string'}, 'stream': 'stderr'},
    ],
    'models': [
      for (final m in kSherpaModels)
        {'id': m.id, 'languages': m.languages, 'sizeMb': m.sizeMb, 'recommended': m.recommended},
    ],
    'exitCodes': {'0': 'success', '1': 'error (see error event / stderr)'},
    'notes': [
      'Local engine is free and offline (sherpa-onnx); cloud engines need an API key.',
      'For clean stdout in scripts, compile a standalone binary with `dart build cli`.',
      'Recommended agent flow: `schema` -> `info <epub>` -> `list-models` -> `download <id>` (if needed) -> `convert <epub> --json`.',
    ],
  });
}

Future<void> _info(_Args args) async {
  final path = _requireEpub(args);
  final book = EpubParser().parse(File(path).readAsBytesSync(),
      fallbackTitle: p.basenameWithoutExtension(path));
  if (_json) {
    _emit({
      'title': book.title,
      'author': book.author,
      'language': book.languageCode,
      'hasCover': book.hasCover,
      'totalChars': book.totalChars,
      'chapters': [
        for (final c in book.chapters)
          {'index': c.index, 'title': c.title, 'chars': c.charCount},
      ],
    });
  } else {
    stdout.writeln('Title    : ${book.title}');
    stdout.writeln('Author   : ${book.author}');
    stdout.writeln('Language : ${book.languageCode}');
    stdout.writeln('Cover    : ${book.hasCover ? 'yes' : 'no'}');
    stdout.writeln('Chapters : ${book.chapters.length} '
        '(${book.totalChars} chars)');
    for (final c in book.chapters) {
      stdout.writeln('  [${c.index}] ${c.charCount.toString().padLeft(7)}  ${c.title}');
    }
  }
}

void _listModels(_Args args) {
  final installer = _installer(args, http.Client());
  if (_json) {
    _emit({
      'models': [
        for (final m in kSherpaModels)
          {
            'id': m.id,
            'label': m.label,
            'languages': m.languages,
            'sizeMb': m.sizeMb,
            'recommended': m.recommended,
            'installed': installer.isInstalled(m),
            'blurb': m.blurb,
          },
      ],
    });
  } else {
    for (final m in kSherpaModels) {
      final mark = installer.isInstalled(m) ? '✓' : ' ';
      final rec = m.recommended ? ' (recommended)' : '';
      stdout.writeln('[$mark] ${m.id.padRight(8)} ${m.languages.join('/').padRight(12)} '
          '~${m.sizeMb}MB$rec');
      stdout.writeln('      ${m.blurb}');
    }
  }
}

Future<void> _download(_Args args) async {
  if (args.positionals.length < 2) _fail('Usage: download <modelId>');
  final id = args.positionals[1];
  final model = sherpaModelById(id) ?? _fail('Unknown model: $id');
  final installer = _installer(args, http.Client());
  await for (final line in installer.ensureInstalled(model,
      onProgress: (f) => _progress('download', f))) {
    _log(line);
  }
}

Future<void> _convert(_Args args) async {
  final path = _requireEpub(args);
  final runner = SystemProcessRunner();
  final httpClient = http.Client();
  final installer = _installer(args, httpClient);

  final book = EpubParser().parse(File(path).readAsBytesSync(),
      fallbackTitle: p.basenameWithoutExtension(path));

  final engine = switch (args.opt('engine') ?? 'local') {
    'local' => TtsBackendKind.local,
    'openai' => TtsBackendKind.openai,
    'elevenlabs' => TtsBackendKind.elevenlabs,
    final e => _fail('Unknown engine: $e'),
  };
  final language = args.opt('language') ?? book.languageCode;

  // Resolve the voice/model id.
  String voiceId;
  if (engine == TtsBackendKind.local) {
    voiceId = args.opt('model') ?? defaultSherpaModelId(language);
    final model = sherpaModelById(voiceId) ?? _fail('Unknown model: $voiceId');
    if (!installer.isInstalled(model)) {
      _log('Model "$voiceId" not installed; downloading…');
      await for (final line in installer.ensureInstalled(model,
          onProgress: (f) => _progress('download', f))) {
        _log(line);
      }
    }
    _initSherpa(args);
  } else {
    voiceId = args.opt('voice') ?? (engine == TtsBackendKind.openai ? 'alloy' : 'EXAVITQu4vr4xnSDxMaL');
  }

  final dir = p.dirname(p.absolute(path));
  final safe = book.title.replaceAll(RegExp(r'[^\w\- ]+'), '').trim();
  final output = args.opt('output') ?? args.opt('o') ?? p.join(dir, '${safe.isEmpty ? 'audiobook' : safe}.m4b');
  final selected = args.opt('chapters') != null
      ? args.opt('chapters')!.split(',').map((s) => int.parse(s.trim())).toSet()
      : book.chapters.map((c) => c.index).toSet();

  final apiKey = args.opt('api-key') ??
      Platform.environment[engine == TtsBackendKind.openai ? 'OPENAI_API_KEY' : 'ELEVENLABS_API_KEY'] ??
      '';

  final options = ConversionOptions(
    backend: engine,
    languageCode: language,
    voiceId: voiceId,
    speed: double.tryParse(args.opt('speed') ?? '') ?? 1.0,
    bitrate: args.opt('bitrate') ?? '128k',
    outputPath: output,
    workDir: '$output.work',
    coverOverridePath: args.opt('cover'),
    selectedChapterIndices: selected,
    apiKeys: {if (engine.isCloud) engine.name: apiKey},
  );

  final backend = makeBackend(options,
      runner: runner, httpClient: httpClient, sherpa: installer);
  await _runConversion(book, options, backend, FfmpegService(runner));
}

// --- conversion loop (Flutter-free) ---

Future<void> _runConversion(
    Book book, ConversionOptions o, backend, FfmpegService ffmpeg) async {
  final chunker = TextChunker();
  Directory(o.workDir).createSync(recursive: true);
  final selected =
      book.chapters.where((c) => o.selectedChapterIndices.contains(c.index)).toList();
  final totalChars = selected.fold<int>(0, (s, c) => s + c.charCount);
  var doneChars = 0;
  final renderedChapters = <Chapter>[];
  final renderedWavs = <String>[];

  for (var pos = 0; pos < selected.length; pos++) {
    final ch = selected[pos];
    final chWav = p.join(o.workDir, 'chapter_${ch.index.toString().padLeft(4, '0')}.wav');
    if (File(chWav).existsSync()) {
      _log('[${pos + 1}/${selected.length}] ${ch.title} — cached');
    } else {
      final chunks = chunker.chunk(ch.text, maxChars: backend.maxChars, languageCode: o.languageCode);
      _log('[${pos + 1}/${selected.length}] ${ch.title} (${chunks.length} chunks)');
      final chunkWavs = <String>[];
      for (var i = 0; i < chunks.length; i++) {
        final cw = p.join(o.workDir, 'chapter_${ch.index.toString().padLeft(4, '0')}_chunk_${i.toString().padLeft(4, '0')}.wav');
        if (!File(cw).existsSync()) await backend.synth(chunks[i], cw);
        chunkWavs.add(cw);
      }
      await ffmpeg.concatToChapterWav(chunkWavs, chWav, backend.sampleRate as int);
      for (final cw in chunkWavs) {
        try {
          File(cw).deleteSync();
        } on FileSystemException {/* ignore */}
      }
    }
    doneChars += ch.charCount;
    renderedChapters.add(ch);
    renderedWavs.add(chWav);
    _progress('synthesize', totalChars == 0 ? 1 : doneChars / totalChars);
  }

  // Cover: explicit override, else the EPUB's own.
  String? coverPath = o.coverOverridePath;
  if (coverPath == null && book.hasCover) {
    final ext = (book.coverContentType ?? '').contains('png') ? 'png' : 'jpg';
    coverPath = p.join(o.workDir, 'cover.$ext');
    File(coverPath).writeAsBytesSync(book.coverBytes!);
  }

  _log('Assembling ${o.outputPath} …');
  await ffmpeg.assembleM4b(book, renderedChapters, renderedWavs, o,
      coverPath: coverPath, sampleRate: backend.sampleRate as int);
  await backend.dispose();
  if (_json) {
    _emit({'event': 'done', 'output': o.outputPath, 'chapters': renderedChapters.length});
  } else {
    _log('Done → ${o.outputPath}');
  }
}

// --- sherpa native lib bootstrap ---

void _initSherpa(_Args args) {
  // The TTS worker isolate loads the native lib; tell it where to find it.
  // Prefer an explicit dir, then a flutter-build output, else null (default
  // resolution via native assets / rpath).
  SherpaTtsBackend.libraryDir = args.opt('sherpa-lib') ?? _autoSherpaLibDir();
}

String? _autoSherpaLibDir() {
  bool hasLib(String dir) => File(p.join(dir, _sherpaLibName)).existsSync() ||
      File(p.join(dir, 'libsherpa-onnx-c-api.dylib')).existsSync() ||
      File(p.join(dir, 'libsherpa-onnx-c-api.so')).existsSync();

  // 1) Next to a distributed binary (release layout): exe dir, ../lib, ../Frameworks.
  final exeDir = p.dirname(Platform.resolvedExecutable);
  for (final d in [exeDir, p.join(exeDir, '..', 'lib'), p.join(exeDir, '..', 'Frameworks')]) {
    if (hasLib(d)) return p.normalize(d);
  }
  // 2) A local flutter desktop build (dev).
  final root = Directory.current.path;
  for (final cfg in ['Release', 'Debug']) {
    final fw = p.join(root, 'build', 'macos', 'Build', 'Products', cfg,
        'audiobook_studio.app', 'Contents', 'Frameworks');
    if (hasLib(fw)) return fw;
  }
  return null;
}

String get _sherpaLibName => Platform.isWindows
    ? 'sherpa-onnx-c-api.dll'
    : Platform.isMacOS
        ? 'libsherpa-onnx-c-api.dylib'
        : 'libsherpa-onnx-c-api.so';

// --- helpers ---

SherpaModelInstaller _installer(_Args args, http.Client client) {
  final home = Platform.environment['HOME'] ?? '.';
  final dir = args.opt('models-dir') ?? p.join(home, '.audiobook_studio', 'models');
  return SherpaModelInstaller(modelsDir: dir, client: client);
}

String _requireEpub(_Args args) {
  if (args.positionals.length < 2) _fail('Provide a .epub file path.');
  final path = args.positionals[1];
  if (!File(path).existsSync()) _fail('File not found: $path');
  return path;
}

void _log(String msg) {
  if (_json) {
    _emit({'event': 'log', 'message': msg});
  } else {
    stdout.writeln(msg);
  }
}

int _lastPct = -1;
String _lastPhase = '';

void _progress(String phase, double fraction) {
  final pct = (fraction.clamp(0, 1) * 100).round();
  if (_json) {
    _emit({'event': 'progress', 'phase': phase, 'fraction': double.parse(fraction.clamp(0, 1).toStringAsFixed(4))});
  } else if (pct != _lastPct || phase != _lastPhase) {
    _lastPct = pct;
    _lastPhase = phase;
    stdout.writeln('  $phase: $pct%');
  }
}

void _emit(Object o) => stdout.writeln(jsonEncode(o));

Never _fail(String message) {
  if (_json) {
    stderr.writeln(jsonEncode({'event': 'error', 'message': message}));
  } else {
    stderr.writeln('Error: $message');
  }
  exit(1);
}

/// Tiny flag/option parser: `--key value`, `--flag`, and positionals.
class _Args {
  final List<String> positionals = [];
  final Map<String, String> _opts = {};
  final Set<String> _flags = {};

  _Args(List<String> argv) {
    for (var i = 0; i < argv.length; i++) {
      final a = argv[i];
      if (a.startsWith('-')) {
        final key = a.replaceFirst(RegExp(r'^-+'), '');
        if (i + 1 < argv.length && !argv[i + 1].startsWith('-')) {
          _opts[key] = argv[++i];
        } else {
          _flags.add(key);
        }
      } else {
        positionals.add(a);
      }
    }
  }

  String? opt(String k) => _opts[k];
  bool flag(String k) => _flags.contains(k);
}
