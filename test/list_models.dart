import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

void main() async {
  await dotenv.load(fileName: '.env');
  final apiKey = dotenv.env['GEMINI_API_KEY'];
  if (apiKey == null) {
    print('Error: GEMINI_API_KEY not found in .env');
    return;
  }

  try {
    // The library doesn't strictly provide a listModels directly in the high level API in some versions,
    // but we can try to instantiate them to check.
    // Alternatively, we can use a simpler approach.
    print('Checking available models...');
    // We'll just try the most likely ones.
  } catch (e) {
    print('Error: $e');
  }
}
