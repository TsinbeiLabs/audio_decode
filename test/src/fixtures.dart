// Fixture loading for tests that run on the VM and in a browser.
export 'fixtures_io.dart' if (dart.library.js_interop) 'fixtures_web.dart';

/// Every file in `test/fixtures/`.
const fixtureNames = [
  'sine_44100_mono_1s.mp3',
  'sine_44100_mono_1s.ogg',
  'sine_44100_stereo_1s.mp3',
  'sine_44100_stereo_1s.ogg',
  'sine_48000_mono_halfsec.mp3',
  'sine_48000_mono_halfsec.ogg',
];
