import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

void saveFile(Uint8List bytes, String fileName) async {
  // Mobile/Desktop implementation
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes);
}

Future<void> copyImageToClipboard(Uint8List bytes) async {
  // On IO platforms, we use Pasteboard in home_screen.dart directly
  return;
}
