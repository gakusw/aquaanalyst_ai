import 'package:flutter/material.dart';
import '../widgets/body_composition_form.dart';

class BodyCompositionScreen extends StatelessWidget {
  const BodyCompositionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('体組成記録')),
      body: const BodyCompositionForm(),
    );
  }
}
