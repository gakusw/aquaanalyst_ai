import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:js_util' as js_util;
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
    // Check if ClipboardItem is supported (it's not in dart:html, so we use js_util)
    final clipboardItemConstructor = js_util.getProperty(html.window, 'ClipboardItem');
    if (clipboardItemConstructor == null) {
      throw Exception('ClipboardItem is not supported in this browser');
    }

    final blob = html.Blob([bytes], 'image/png');
    
    // Create the ClipboardItem using js_util
    // Constructor takes an object where keys are MIME types and values are Blobs
    final data = js_util.newObject();
    js_util.setProperty(data, 'image/png', blob);
    
    final clipboardItem = js_util.callConstructor(clipboardItemConstructor, [data]);
    
    // Call navigator.clipboard.write([clipboardItem])
    final clipboard = js_util.getProperty(html.window.navigator, 'clipboard');
    if (clipboard == null) {
       throw Exception('Navigator clipboard is not supported');
    }
    
    await js_util.promiseToFuture(js_util.callMethod(clipboard, 'write', [[clipboardItem]]));
  } catch (e) {
    debugPrint('Browser clipboard write failed: $e');
    rethrow;
  }
}
