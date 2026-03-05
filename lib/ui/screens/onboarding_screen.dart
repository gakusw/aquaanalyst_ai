import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _visionController = TextEditingController();
  final _coachController = TextEditingController();
  double _expertiseLevel = 5;
  bool _strictMode = false;

  @override
  void dispose() {
    _visionController.dispose();
    _coachController.dispose();
    super.dispose();
  }

  void _completeOnboarding() {
    // 実際のアプリではここで設定内容をローカル保存/プロバイダーにセットする
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AquaAnalyst AI - 初期設定'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ようこそ，分析型AIコーチングへ．\nまずはあなたの情報を教えてください．',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // 1. ビジョン
                const Text('1. ビジョン(最終目標)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _visionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: '例: 1年後のインカレで50m自由形23秒台を出して決勝に残りたい',
                    border: OutlineInputBorder(),
                    helperText: 'これがすべてのコーチングのブレない指針となります．',
                  ),
                ),
                const SizedBox(height: 24),

                // 2. 専門性と理想のコーチ像
                const Text('2. 分析の専門性と理想のコーチ像', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('専門性レベル (初心者1 〜 エリート10):'),
                    Expanded(
                      child: Slider(
                        value: _expertiseLevel,
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: _expertiseLevel.round().toString(),
                        onChanged: (value) => setState(() => _expertiseLevel = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _coachController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: '例: ロジカルに，かつモチベーションが上がる言い回しが良い',
                    border: OutlineInputBorder(),
                    labelText: 'どんなコーチが良いか（自由記述）',
                  ),
                ),
                const SizedBox(height: 24),

                // 3. 厳格モード
                const Text('3. コーチングモード', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('【厳格モード】をオンにする'),
                  subtitle: const Text('希望的観測を徹底的に排除し，極めて現実的で厳しいフィードバックのみを返します．'),
                  value: _strictMode,
                  activeColor: Colors.redAccent,
                  onChanged: (value) => setState(() => _strictMode = value),
                ),
                const SizedBox(height: 48),

                FilledButton(
                  onPressed: _completeOnboarding,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  child: const Text('設定を完了して分析を始める'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

