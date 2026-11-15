import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'audio_decode_base.dart';
import 'bindings.dart';

// The native decoders, selected by the conditional import in
// audio_decode_base.dart when dart:ffi is available. The public functions of
// the same name in that file carry the documentation and call these.

PcmAudio decodeOgg(Uint8List bytes) =>
    _decode(bytes, adDecodeVorbis, 'Ogg Vorbis');

PcmAudio decodeMp3(Uint8List bytes) => _decode(bytes, adDecodeMp3, 'MP3');

AudioInfo oggInfo(Uint8List bytes) => _info(bytes, adInfoVorbis, 'Ogg Vorbis');

AudioInfo mp3Info(Uint8List bytes) => _info(bytes, adInfoMp3, 'MP3');

/// The shared decode path. It validates the input, copies it into native
/// memory, calls the decoder, copies the samples back into a Dart [Int16List]
/// and frees the native buffer.
typedef _DecodeFn =
    int Function(
      Pointer<Uint8>,
      int,
      Pointer<Int>,
      Pointer<Int>,
      Pointer<Int>,
      Pointer<Pointer<Int16>>,
    );

PcmAudio _decode(Uint8List bytes, _DecodeFn decode, String formatName) {
  checkNotEmpty(bytes);

  final dataPtr = malloc<Uint8>(bytes.length);
  final outChannels = malloc<Int>();
  final outRate = malloc<Int>();
  final outSamplesPerChannel = malloc<Int>();
  final outSamples = malloc<Pointer<Int16>>();
  Pointer<Int16>? nativeSamples;
  try {
    dataPtr.asTypedList(bytes.length).setAll(0, bytes);
    final rc = decode(
      dataPtr,
      bytes.length,
      outChannels,
      outRate,
      outSamplesPerChannel,
      outSamples,
    );
    if (rc != 0) {
      throw AudioDecodeException('not a decodable $formatName stream');
    }
    final channels = outChannels.value;
    final rate = outRate.value;
    final samplesPerChannel = outSamplesPerChannel.value;
    if (samplesPerChannel <= 0 || channels <= 0 || rate <= 0) {
      // A stream whose header parses but which yields nothing. Truncating an
      // Ogg file part way through its first audio page lands here. The decoder
      // reports success and zero frames, and every caller then works with an
      // empty result it never checked for. An empty decode is never a useful
      // answer, and this treats it as an error.
      nativeSamples = outSamples.value;
      if (nativeSamples != nullptr) adFree(nativeSamples);
      nativeSamples = null;
      throw AudioDecodeException(
        'decoded no audio from this $formatName stream; it is empty or '
        'truncated before the first complete audio frame',
      );
    }
    nativeSamples = outSamples.value;
    final total = channels * samplesPerChannel;
    // Copy out of native memory before freeing it. Callers never see a native
    // pointer.
    final samples = Int16List.fromList(nativeSamples.asTypedList(total));
    adFree(nativeSamples);
    nativeSamples = null;
    return PcmAudio(sampleRate: rate, channels: channels, samples: samples);
  } finally {
    malloc.free(dataPtr);
    malloc.free(outChannels);
    malloc.free(outRate);
    malloc.free(outSamplesPerChannel);
    malloc.free(outSamples);
    // Catches a native buffer that was allocated but never reached adFree(),
    // for example because copying it out threw.
    if (nativeSamples != null) {
      adFree(nativeSamples);
    }
  }
}

typedef _InfoFn =
    int Function(Pointer<Uint8>, int, Pointer<Int>, Pointer<Int>, Pointer<Int>);

AudioInfo _info(Uint8List bytes, _InfoFn readInfo, String formatName) {
  checkNotEmpty(bytes);

  final dataPtr = malloc<Uint8>(bytes.length);
  final outChannels = malloc<Int>();
  final outRate = malloc<Int>();
  final outFrames = malloc<Int>();
  try {
    dataPtr.asTypedList(bytes.length).setAll(0, bytes);
    final rc = readInfo(dataPtr, bytes.length, outChannels, outRate, outFrames);
    if (rc != 0) {
      throw AudioDecodeException('not a readable $formatName stream');
    }
    return AudioInfo(
      sampleRate: outRate.value,
      channels: outChannels.value,
      frameCount: outFrames.value,
    );
  } finally {
    malloc.free(dataPtr);
    malloc.free(outChannels);
    malloc.free(outRate);
    malloc.free(outFrames);
  }
}
