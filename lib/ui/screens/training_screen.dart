import 'package:flutter/material.dart';
import '../widgets/training_form.dart';

class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('トレーニングメニュー入力')),
      body: const TrainingForm(),
    );
  }
}
