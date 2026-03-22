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
  // Stub implementation as it's not currently used and causing build issues
  debugPrint('copyImageToClipboard is not implemented on web');
  return;
}
