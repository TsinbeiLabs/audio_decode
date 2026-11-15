import 'dart:js_interop';
import 'dart:typed_data';

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

extension type _Response._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

/// Fetches a committed fixture from `test/fixtures/`.
///
/// The test runner serves the package directory, and the URL resolves against
/// the page of the running test file in `test/`.
Future<Uint8List> loadFixture(String name) async {
  final response = await _fetch('fixtures/$name'.toJS).toDart;
  if (!response.ok) {
    throw StateError('fetching fixture $name failed with ${response.status}');
  }
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
