// Runs inside the app the compat workflow generates, not in this package:
// flutter_test and integration_test resolve there. tool/ci/prepare_app.dart
// copies it to the app's integration_test directory.

import 'package:audio_decode/audio_decode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('decodes a bundled Ogg Vorbis fixture', () async {
    final data = await rootBundle.load('assets/sine_44100_stereo_1s.ogg');
    final pcm = decodeAudio(data.buffer.asUint8List());

    expect(pcm.sampleRate, 44100);
    expect(pcm.channels, 2);
    expect(pcm.frameCount, greaterThan(0));
    expect(pcm.samples.length, pcm.frameCount * pcm.channels);
  });

  test('rejects garbage with AudioDecodeException', () {
    // Starts with the Ogg capture pattern. The bytes reach the native decoder
    // before they are rejected.
    final garbage = Uint8List.fromList([
      ...'OggS'.codeUnits,
      ...List<int>.generate(60, (i) => (i * 37) & 0xFF),
    ]);

    expect(() => decodeAudio(garbage), throwsA(isA<AudioDecodeException>()));
  });
}
