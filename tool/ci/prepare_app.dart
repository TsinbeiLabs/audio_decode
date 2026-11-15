/// Turns an app made by `flutter create` into the consumer the compat
/// workflow builds. It copies the on-device decode test and its fixtures into
/// the app and declares the fixtures as assets.
///
/// Usage: `dart tool/ci/prepare_app.dart <app directory>`
///
/// The dependency on audio_decode is added separately with `flutter pub add`.
library;

import 'dart:io';

/// The fixtures `integration_test/decode_test.dart` loads, under `assets/`.
const fixtures = ['sine_44100_stereo_1s.ogg', 'sine_44100_stereo_1s.mp3'];

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart tool/ci/prepare_app.dart <app directory>');
    exit(64);
  }
  final app = Directory(args.single);
  final ci = File.fromUri(Platform.script).parent;
  final repo = ci.parent.parent;

  _copy(
    File('${ci.path}/integration_test/decode_test.dart'),
    File('${app.path}/integration_test/decode_test.dart'),
  );
  for (final fixture in fixtures) {
    _copy(
      File('${repo.path}/test/fixtures/$fixture'),
      File('${app.path}/assets/$fixture'),
    );
  }

  // The generated pubspec has a top-level `flutter:` section with no asset
  // list. Inserting one right below the key keeps the rest of the template.
  final pubspec = File('${app.path}/pubspec.yaml');
  final lines = pubspec.readAsLinesSync();
  final section = lines.indexOf('flutter:');
  if (section < 0 || lines.any((line) => line.startsWith('  assets:'))) {
    stderr.writeln('unexpected pubspec layout in ${pubspec.path}');
    exit(1);
  }
  lines.insertAll(section + 1, [
    '  assets:',
    for (final fixture in fixtures) '    - assets/$fixture',
  ]);
  pubspec.writeAsStringSync('${lines.join('\n')}\n');
  print('prepared ${app.path}');
}

void _copy(File from, File to) {
  to.parent.createSync(recursive: true);
  from.copySync(to.path);
}
