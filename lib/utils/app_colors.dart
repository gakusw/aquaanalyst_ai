import 'package:flutter/material.dart';

class AppColors {
  // Brand Categories
  static const Color pool = Color(0xFF1E40AF);    // Deep Blue / Navy
  static const Color dryland = Color(0xFFFACC15); // Yellow
  static const Color protein = Color(0xFFFB7185); // Rose/Coral
  static const Color fat = Color(0xFFFB923C);     // Orange
  static const Color carbs = Color(0xFF4ADE80);   // Green
  static const Color sleep = Color(0xFFA78BFA);   // Violet/Lavender (User favorite)

  // Helper to get color with higher contrast for light mode if needed
  static Color getEffectiveColor(BuildContext context, Color color) {
    if (Theme.of(context).brightness == Brightness.light) {
      // Darken slightly for light mode backgrounds
      if (color == pool) return const Color(0xFF1E3A8A); // Darker Blue
      if (color == dryland) return Colors.orange.shade800;
      if (color == protein) return Colors.red.shade800;
      if (color == fat) return Colors.orange.shade900;
      if (color == carbs) return Colors.green.shade800;
      if (color == sleep) return Colors.deepPurple.shade700;
    }
    return color;
  }
}
