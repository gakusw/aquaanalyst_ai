import 'package:flutter/material.dart';
import '../widgets/nutrition_form.dart';

class NutritionScreen extends StatelessWidget {
  const NutritionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('食事記録')),
      body: const NutritionForm(),
    );
  }
}
