import 'dart:typed_data';

import 'audio_decode_base.dart';

// Stands in for native_ffi.dart where dart:ffi is missing, which is the web.
// Each call throws. Returning an empty PcmAudio would let a caller treat
// missing audio as silence.

PcmAudio decodeOgg(Uint8List bytes) => _unavailable('Ogg Vorbis decoding');

PcmAudio decodeMp3(Uint8List bytes) => _unavailable('MP3 decoding');

AudioInfo oggInfo(Uint8List bytes) => _unavailable('Reading Ogg Vorbis info');

AudioInfo mp3Info(Uint8List bytes) => _unavailable('Reading MP3 info');

Never _unavailable(String operation) => throw UnsupportedError(
  '$operation needs the native decoder. '
  'Native decoding is not available on the web.',
);
