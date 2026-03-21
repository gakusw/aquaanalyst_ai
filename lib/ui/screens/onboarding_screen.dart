import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/firestore_service.dart';
import '../../data/models/app_user.dart';
import '../widgets/stable_text_field.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _visionController = TextEditingController();
  final _coachController = TextEditingController();
  final _firestoreService = FirestoreService();
  bool _isLoading = false;

  @override
  void dispose() {
    _visionController.dispose();
    _coachController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final uid = _firestoreService.currentUserId;
    if (uid == null) {
      context.go('/auth');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final currentProfile = await _firestoreService.getUserProfileStream().first;
      
      Map<String, dynamic> baseProfile = currentProfile != null 
          ? Map<String, dynamic>.from(currentProfile.baseProfile) 
          : {};
      
      baseProfile['idealCoachPersona'] = _coachController.text;
      
      final updatedUser = AppUser(
        uid: uid,
        displayName: currentProfile?.displayName ?? 'ゲストユーザー',
        vision: _visionController.text,
        baseProfile: baseProfile,
        createdAt: currentProfile?.createdAt,
      );

      await _firestoreService.saveUserProfile(updatedUser);
      
      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('情報の保存中にエラーが発生しました。しばらく待ってから再度お試しください。')),
        );
      }
    }
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
                StableTextField(
                  controller: _visionController,
                  lines: 6,
                  hintText: '例: 1年後のインカレで50m自由形23秒台を出して決勝に残りたい\n（※これがすべてのコーチングの指針となります）',
                  labelText: '1. ビジョン(最終目標)',
                ),
                const SizedBox(height: 24),

                // 2. 理想のコーチ像
                StableTextField(
                  controller: _coachController,
                  lines: 5,
                  hintText: '例: ロジカルに，かつモチベーションが上がる言い回しが良い',
                  labelText: '2. 理想のコーチ像',
                ),
                const SizedBox(height: 16),

                const SizedBox(height: 48),

                FilledButton(
                  onPressed: _isLoading ? null : _completeOnboarding,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  child: _isLoading 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('設定を完了して分析を始める'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

