import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

void saveFile(Uint8List bytes, String fileName) {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute("download", fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

Future<void> copyImageToClipboard(Uint8List bytes) async {
  try {
    final blob = html.Blob([bytes], 'image/png');
    final item = html.ClipboardItem({'image/png': blob});
    await html.window.navigator.clipboard!.write([item]);
  } catch (e) {
    debugPrint('Browser clipboard write failed: $e');
    rethrow;
  }
}
