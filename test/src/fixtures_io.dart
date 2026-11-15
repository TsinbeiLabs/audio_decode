import 'dart:io';
import 'dart:typed_data';

/// Reads a committed fixture from `test/fixtures/`.
Future<Uint8List> loadFixture(String name) =>
    File('test/fixtures/$name').readAsBytes();
