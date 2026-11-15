import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';

// This file runs on the Dart VM and in a browser. The expected checksums were
// recorded on the VM, and the browser has to reproduce them exactly.

/// A seeded integer sequence with no floating point in it. Every product stays
/// below 2^53, which keeps the values exact when compiled to JavaScript.
List<int> _sequence(int count, int seed, int modulus) {
  var state = seed;
  return List.generate(count, (_) {
    state = (state * 48271) % 2147483647;
    return state % modulus;
  });
}

/// A checksum that stays exact in JavaScript numbers.
int _checksum(List<int> values) {
  var hash = values.length;
  for (final value in values) {
    hash = (hash * 65537 + (value & 0xFFFFFFFF)) % 2147483647;
  }
  return hash;
}

/// Builds a RIFF/WAVE file. An odd-sized LIST chunk before the data chunk
/// exercises the chunk walk and its pad byte. A non-null [extensibleTag]
/// writes WAVE_FORMAT_EXTENSIBLE with that sub-format.
Uint8List _wav({
  required int formatTag,
  required int channels,
  required int sampleRate,
  required int bitsPerSample,
  required Uint8List payload,
  bool listChunk = false,
  int? extensibleTag,
}) {
  final blockAlign = (bitsPerSample ~/ 8) * channels;
  final fmtSize = extensibleTag == null ? 16 : 40;
  final fmt = ByteData(8 + fmtSize)
    ..setUint32(0, 0x20746d66, Endian.little) // 'fmt '
    ..setUint32(4, fmtSize, Endian.little)
    ..setUint16(8, extensibleTag == null ? formatTag : 0xFFFE, Endian.little)
    ..setUint16(10, channels, Endian.little)
    ..setUint32(12, sampleRate, Endian.little)
    ..setUint32(16, sampleRate * blockAlign, Endian.little)
    ..setUint16(20, blockAlign, Endian.little)
    ..setUint16(22, bitsPerSample, Endian.little);
  if (extensibleTag != null) {
    fmt
      ..setUint16(24, 22, Endian.little)
      ..setUint16(26, bitsPerSample, Endian.little)
      ..setUint16(32, extensibleTag, Endian.little);
  }
  final list = ByteData(8 + 5)
    ..setUint32(0, 0x5453494c, Endian.little) // 'LIST'
    ..setUint32(4, 5, Endian.little);
  final data = ByteData(8)
    ..setUint32(0, 0x61746164, Endian.little) // 'data'
    ..setUint32(4, payload.length, Endian.little);
  final body = BytesBuilder()
    ..add(fmt.buffer.asUint8List())
    ..add(listChunk ? list.buffer.asUint8List() : const <int>[])
    ..add(listChunk ? const [0] : const <int>[])
    ..add(data.buffer.asUint8List())
    ..add(payload);
  final riff = ByteData(12)
    ..setUint32(0, 0x46464952, Endian.little) // 'RIFF'
    ..setUint32(4, 4 + body.length, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little); // 'WAVE'
  return (BytesBuilder()
        ..add(riff.buffer.asUint8List())
        ..add(body.toBytes()))
      .toBytes();
}

/// Float samples from -1.25 to 1.25 with NaN and both infinities mixed in.
ByteData _floats(int count, int seed, {required bool wide}) {
  final width = wide ? 8 : 4;
  final out = ByteData(count * width);
  final raw = _sequence(count, seed, 5001);
  for (var i = 0; i < count; i++) {
    final value = switch (i % 97) {
      0 => double.nan,
      1 => double.infinity,
      2 => double.negativeInfinity,
      _ => (raw[i] - 2500) / 2000,
    };
    if (wide) {
      out.setFloat64(i * width, value, Endian.little);
    } else {
      out.setFloat32(i * width, value, Endian.little);
    }
  }
  return out;
}

Uint8List _bytes(int count, int seed) =>
    Uint8List.fromList(_sequence(count, seed, 256));

final _cases = <String, Uint8List>{
  'unsigned 8-bit mono': _wav(
    formatTag: 1,
    channels: 1,
    sampleRate: 8000,
    bitsPerSample: 8,
    payload: _bytes(1500, 11),
  ),
  '16-bit stereo': _wav(
    formatTag: 1,
    channels: 2,
    sampleRate: 44100,
    bitsPerSample: 16,
    payload: _bytes(4 * 2205, 12),
  ),
  '24-bit stereo, extensible, LIST chunk': _wav(
    formatTag: 1,
    channels: 2,
    sampleRate: 48000,
    bitsPerSample: 24,
    payload: _bytes(6 * 1200, 13),
    listChunk: true,
    extensibleTag: 1,
  ),
  '32-bit integer mono': _wav(
    formatTag: 1,
    channels: 1,
    sampleRate: 22050,
    bitsPerSample: 32,
    payload: _bytes(4 * 1000, 14),
  ),
  '32-bit float stereo': _wav(
    formatTag: 3,
    channels: 2,
    sampleRate: 32000,
    bitsPerSample: 32,
    payload: _floats(2 * 900, 15, wide: false).buffer.asUint8List(),
  ),
  '64-bit float mono with trailing bytes': _wav(
    formatTag: 3,
    channels: 1,
    sampleRate: 16000,
    bitsPerSample: 64,
    payload: Uint8List.fromList([
      ..._floats(700, 16, wide: true).buffer.asUint8List(),
      1,
      2,
      3,
    ]),
  ),
};

/// Geometry and sample checksum of [decodeWav] for each case, from the VM.
const _expectedWav = <String, (int, int, int, int)>{
  'unsigned 8-bit mono': (8000, 1, 1500, 1984752458),
  '16-bit stereo': (44100, 2, 2205, 1844826773),
  '24-bit stereo, extensible, LIST chunk': (48000, 2, 1200, 1086981854),
  '32-bit integer mono': (22050, 1, 1000, 2119667158),
  '32-bit float stereo': (32000, 2, 900, 1128648505),
  '64-bit float mono with trailing bytes': (16000, 1, 700, 732693984),
};

/// Checksums of the helpers applied to the 16-bit stereo case, from the VM.
const _expectedHelpers = <String, int>{
  'toMono': 279075674,
  'PcmAudio.toMono': 279075674,
  'resample to 16000': 867229098,
  'resample to 48000': 1919080415,
  'toSpeechPcm': 1231301201,
  'toSpeechPcm at 8000': 52294573,
  'toFloat32 bits': 1802311544,
  'channel 1 bits': 1332893511,
  'encodeWav bytes': 503052988,
};

void main() {
  group('detectFormat', () {
    for (final name in fixtureNames) {
      test('recognises $name', () async {
        final bytes = await loadFixture(name);
        final expected = name.endsWith('.ogg')
            ? AudioFormat.ogg
            : AudioFormat.mp3;
        expect(detectFormat(bytes), expected);
      });
    }

    test('recognises every generated WAV', () {
      for (final MapEntry(:key, :value) in _cases.entries) {
        expect(detectFormat(value), AudioFormat.wav, reason: key);
      }
    });
  });

  group('WAV decoding gives the VM result', () {
    for (final MapEntry(:key, :value) in _cases.entries) {
      test(key, () {
        final (rate, channels, frames, checksum) = _expectedWav[key]!;
        final pcm = decodeWav(value);
        expect(pcm.sampleRate, rate);
        expect(pcm.channels, channels);
        expect(pcm.frameCount, frames);
        expect(_checksum(pcm.samples), checksum);

        final dispatched = decodeAudio(value);
        expect(dispatched.samples, pcm.samples);

        final info = AudioInfo(
          sampleRate: rate,
          channels: channels,
          frameCount: frames,
        );
        expect(wavInfo(value), info);
        expect(audioInfo(value), info);
      });
    }
  });

  group('helpers give the VM result', () {
    final pcm = decodeWav(_cases['16-bit stereo']!);
    final actual = <String, int Function()>{
      'toMono': () => _checksum(toMono(pcm).samples),
      'PcmAudio.toMono': () => _checksum(pcm.toMono().samples),
      'resample to 16000': () => _checksum(resample(pcm, 16000).samples),
      'resample to 48000': () => _checksum(resample(pcm, 48000).samples),
      'toSpeechPcm': () => _checksum(toSpeechPcm(pcm).samples),
      'toSpeechPcm at 8000': () =>
          _checksum(toSpeechPcm(pcm, sampleRate: 8000).samples),
      'toFloat32 bits': () => _checksum(pcm.toFloat32().buffer.asUint32List()),
      'channel 1 bits': () => _checksum(pcm.channel(1).buffer.asUint32List()),
      'encodeWav bytes': () => _checksum(encodeWav(pcm)),
    };
    for (final MapEntry(:key, :value) in _expectedHelpers.entries) {
      test(key, () => expect(actual[key]!(), value));
    }
  });

  group('input errors match the VM', () {
    test('empty bytes throw ArgumentError', () {
      expect(() => decodeAudio(Uint8List(0)), throwsArgumentError);
      expect(() => audioInfo(Uint8List(0)), throwsArgumentError);
    });

    test('unrecognised bytes throw AudioDecodeException', () {
      final garbage = Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9]);
      final unrecognised = isA<AudioDecodeException>().having(
        (e) => e.message,
        'message',
        'unrecognized audio format',
      );
      expect(() => decodeAudio(garbage), throwsA(unrecognised));
      expect(() => audioInfo(garbage), throwsA(unrecognised));
    });
  });
}
