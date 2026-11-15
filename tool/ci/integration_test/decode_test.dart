// Runs inside the app the compat workflow generates, not in this package:
// flutter_test and integration_test resolve there. tool/ci/prepare_app.dart
// copies it to the app's integration_test directory. The same file runs on
// Linux, an Android emulator and an iOS simulator. The fixtures come from the
// asset bundle and nothing here depends on the host platform.

import 'dart:math' as math;

import 'package:audio_decode/audio_decode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('decodes the bundled Ogg Vorbis fixture', () async {
    final bytes = await _asset('sine_44100_stereo_1s.ogg');
    final pcm = decodeAudio(bytes);
    _report('ogg', pcm);

    expect(pcm.sampleRate, 44100);
    expect(pcm.channels, 2);
    // The granule position of the last Ogg page is 44100. stb_vorbis trims
    // the decode to it, and audioInfo reads the same granule.
    expect(pcm.frameCount, 44100);
    expect(pcm.samples.length, pcm.frameCount * pcm.channels);
    expect(audioInfo(bytes).frameCount, pcm.frameCount);
    _expectTone(pcm);
  });

  test('decodes the bundled MP3 fixture', () async {
    final bytes = await _asset('sine_44100_stereo_1s.mp3');
    final pcm = decodeAudio(bytes);
    _report('mp3', pcm);

    expect(pcm.sampleRate, 44100);
    expect(pcm.channels, 2);
    // MP3 adds decoder delay. These are the bounds test/audio_decode_test.dart
    // uses on the Dart VM.
    expect(pcm.frameCount, greaterThan((0.8 * 44100).round()));
    expect(pcm.frameCount, lessThan(44100 + 4096));
    expect(pcm.samples.length, pcm.frameCount * pcm.channels);
    _expectTone(pcm);
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

/// Reads a fixture that tool/ci/prepare_app.dart declared as an asset.
///
/// The bundle may hand back a view into a larger buffer. Only the asset's own
/// bytes are copied out.
Future<Uint8List> _asset(String name) async {
  final data = await rootBundle.load('assets/$name');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// Both fixtures hold a 440 Hz sine in each channel at an RMS of about 2050.
/// Silence, noise or a wrong channel layout fails here.
void _expectTone(PcmAudio pcm) {
  for (var channel = 0; channel < pcm.channels; channel++) {
    expect(
      _rms(pcm, channel),
      greaterThan(500),
      reason: 'channel $channel must not be silent',
    );
    expect(
      _magnitudeAt(pcm, channel, 440),
      greaterThan(_magnitudeAt(pcm, channel, 1000) * 20),
      reason: 'channel $channel: 440 Hz should dominate 1000 Hz',
    );
  }
}

/// Prints the geometry and level of a decode to the test log.
void _report(String label, PcmAudio pcm) {
  final levels = [
    for (var channel = 0; channel < pcm.channels; channel++)
      _rms(pcm, channel).toStringAsFixed(1),
  ];
  debugPrint(
    'decoded $label: ${pcm.sampleRate} Hz, ${pcm.channels} channels, '
    '${pcm.frameCount} frames, RMS per channel ${levels.join(' ')}',
  );
}

double _rms(PcmAudio pcm, int channel) {
  final frames = pcm.frameCount;
  if (frames == 0) return 0;
  var sum = 0.0;
  for (var i = 0; i < frames; i++) {
    final v = pcm.samples[i * pcm.channels + channel].toDouble();
    sum += v * v;
  }
  return math.sqrt(sum / frames);
}

/// Magnitude of one frequency in one channel, as a single-bin DFT.
double _magnitudeAt(PcmAudio pcm, int channel, double frequency) {
  var re = 0.0;
  var im = 0.0;
  for (var i = 0; i < pcm.frameCount; i++) {
    final v = pcm.samples[i * pcm.channels + channel].toDouble();
    final phase = 2 * math.pi * frequency * i / pcm.sampleRate;
    re += v * math.cos(phase);
    im += v * math.sin(phase);
  }
  return math.sqrt(re * re + im * im);
}
