/// Models describing external dependencies the app needs and their state.
library;

/// Host operating systems the installer logic branches on. Kept separate from
/// `dart:io.Platform` so tests can drive each branch deterministically.
enum HostOs { macos, linux, windows }

/// The system tools the app relies on. Local TTS models are downloaded in-app
/// (sherpa-onnx bundles its own runtime + espeak data), so the only system
/// packages are ffmpeg/ffprobe for assembly.
enum DependencyKind {
  /// Audio encoder / muxer.
  ffmpeg,

  /// Media probe used for chapter durations.
  ffprobe,
}

/// Metadata about a [DependencyKind].
extension DependencyKindInfo on DependencyKind {
  /// Short human label.
  String get label => switch (this) {
        DependencyKind.ffmpeg => 'ffmpeg',
        DependencyKind.ffprobe => 'ffprobe',
      };

  /// All current dependencies are required system packages.
  bool get isRequired => true;

  /// Installed by the OS package manager.
  bool get isSystemPackage => true;

  /// The executable name probed on `PATH`.
  String get binaryName => switch (this) {
        DependencyKind.ffmpeg => 'ffmpeg',
        DependencyKind.ffprobe => 'ffprobe',
      };

  /// Which engine(s) this dependency serves, for the UI label.
  String get neededFor => 'all engines';
}

/// The resolved state of one dependency on this machine.
class DependencyStatus {
  /// Which dependency this describes.
  final DependencyKind kind;

  /// Whether it was found.
  final bool found;

  /// Detected version string, when available.
  final String? version;

  /// Resolved path/location, when found.
  final String? location;

  /// A short hint shown when missing (e.g. the install command).
  final String? installHint;

  const DependencyStatus({
    required this.kind,
    required this.found,
    this.version,
    this.location,
    this.installHint,
  });

  @override
  String toString() =>
      'DependencyStatus(${kind.label}, found=$found, ${version ?? '-'})';
}
