import 'package:audiobook_studio/data/deps/dependency_checker.dart';
import 'package:audiobook_studio/data/deps/dependency_installer.dart';
import 'package:audiobook_studio/data/process_runner.dart';
import 'package:audiobook_studio/domain/conversion_options.dart';
import 'package:audiobook_studio/domain/dependency.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripts canned responses keyed by `exe firstArg`.
class ScriptedRunner extends ProcessRunner {
  final Map<String, ProcessRunResult> responses;
  String? streamedExe;
  List<String>? streamedArgs;

  ScriptedRunner(this.responses);

  @override
  Future<ProcessRunResult> run(String e, List<String> a, {String? stdinText}) async {
    final key = '$e ${a.isNotEmpty ? a.first : ''}'.trim();
    return responses[key] ?? responses[e] ?? const ProcessRunResult(1, '', '');
  }

  @override
  Stream<String> stream(String e, List<String> a, {String? stdinText}) {
    streamedExe = e;
    streamedArgs = a;
    return Stream.fromIterable(['installing...', 'done']);
  }
}

void main() {
  group('DependencyChecker', () {
    test('every engine requires ffmpeg + ffprobe only', () {
      final checker = DependencyChecker(ScriptedRunner({}));
      for (final b in TtsBackendKind.values) {
        expect(checker.requiredFor(b),
            [DependencyKind.ffmpeg, DependencyKind.ffprobe]);
      }
    });

    test('reports missing with an install hint when which fails', () async {
      final checker = DependencyChecker(ScriptedRunner({
        'which ffmpeg': const ProcessRunResult(1, '', 'not found'),
      }));
      final statuses = await checker.checkAll(os: HostOs.macos);
      final ffmpeg = statuses.firstWhere((s) => s.kind == DependencyKind.ffmpeg);
      expect(ffmpeg.found, isFalse);
      expect(ffmpeg.installHint, 'brew install ffmpeg');
    });

    test('reports present with location + version when found', () async {
      final checker = DependencyChecker(ScriptedRunner({
        'which ffmpeg': const ProcessRunResult(0, '/opt/homebrew/bin/ffmpeg\n', ''),
        'ffmpeg -version': const ProcessRunResult(0, 'ffmpeg version 7.1\n...', ''),
        'which ffprobe': const ProcessRunResult(0, '/opt/homebrew/bin/ffprobe\n', ''),
        'ffprobe -version': const ProcessRunResult(0, 'ffprobe version 7.1\n', ''),
      }));
      final statuses = await checker.checkAll(os: HostOs.macos);
      final ffmpeg = statuses.firstWhere((s) => s.kind == DependencyKind.ffmpeg);
      expect(ffmpeg.found, isTrue);
      expect(ffmpeg.location, '/opt/homebrew/bin/ffmpeg');
      expect(ffmpeg.version, 'ffmpeg version 7.1');
    });
  });

  group('DependencyInstaller', () {
    test('Mac builds a brew install command and streams output', () async {
      final runner = ScriptedRunner({});
      final installer = DependencyInstaller.forOs(HostOs.macos, runner);
      final lines =
          await installer.install([DependencyKind.ffmpeg]).toList();
      expect(runner.streamedExe, 'brew');
      expect(runner.streamedArgs, ['install', 'ffmpeg']);
      expect(lines, contains('installing...'));
    });

    test('Linux builds an apt-get command', () {
      final (exe, args) =
          LinuxInstaller(ScriptedRunner({})).installCommand(['ffmpeg']);
      expect(exe, 'sudo');
      expect(args, ['apt-get', 'install', '-y', 'ffmpeg']);
    });

    test('Windows maps ffmpeg to its winget id', () {
      final (exe, args) =
          WindowsInstaller(ScriptedRunner({})).installCommand(['ffmpeg']);
      expect(exe, 'winget');
      expect(args, contains('Gyan.FFmpeg'));
    });
  });
}
