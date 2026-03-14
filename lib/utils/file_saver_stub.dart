import 'dart:typed_data';

void saveFile(Uint8List bytes, String fileName) {
  throw UnsupportedError('Cannot save file without dart:html or dart:io');
}

Future<void> copyImageToClipboard(Uint8List bytes) {
  throw UnsupportedError('Cannot copy image to clipboard without dart:html or dart:io');
}
