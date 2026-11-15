@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';

/// An [UnsupportedError] whose message names [format] and the web.
Matcher _unsupported(String format) => throwsA(
  isA<UnsupportedError>().having(
    (e) => e.message,
    'message',
    allOf(contains(format), contains('not available on the web')),
  ),
);

void main() {
  final fixtures = <String, Uint8List>{};
  setUpAll(() async {
    for (final name in fixtureNames) {
      fixtures[name] = await loadFixture(name);
    }
  });

  String formatOf(String name) => name.endsWith('.ogg') ? 'Ogg Vorbis' : 'MP3';

  group('native-only entry points throw', () {
    for (final name in fixtureNames) {
      test('for $name', () {
        final bytes = fixtures[name]!;
        final format = formatOf(name);
        if (format == 'MP3') {
          expect(() => decodeMp3(bytes), _unsupported('MP3'));
          expect(() => mp3Info(bytes), _unsupported('MP3'));
        } else {
          expect(() => decodeOgg(bytes), _unsupported('Ogg Vorbis'));
          expect(() => oggInfo(bytes), _unsupported('Ogg Vorbis'));
        }
        expect(() => decodeAudio(bytes), _unsupported(format));
        expect(() => audioInfo(bytes), _unsupported(format));
      });
    }

    test('whatever the input', () {
      // The function is missing on the web, which outranks a bad argument.
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9]),
        encodeWav(
          PcmAudio(sampleRate: 8000, channels: 1, samples: Int16List(8)),
        ),
      ]) {
        expect(() => decodeOgg(bytes), _unsupported('Ogg Vorbis'));
        expect(() => oggInfo(bytes), _unsupported('Ogg Vorbis'));
        expect(() => decodeMp3(bytes), _unsupported('MP3'));
        expect(() => mp3Info(bytes), _unsupported('MP3'));
      }
    });
  });

  test('a WAV still decodes and reads back', () {
    final original = PcmAudio(
      sampleRate: 22050,
      channels: 2,
      samples: Int16List.fromList(
        List.generate(882, (i) => (i * 211) % 65536 - 32768),
      ),
    );
    final wav = encodeWav(original);
    expect(decodeAudio(wav).samples, original.samples);
    expect(
      audioInfo(wav),
      const AudioInfo(sampleRate: 22050, channels: 2, frameCount: 441),
    );
  });
}
