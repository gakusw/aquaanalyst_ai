import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/firestore_service.dart';
import '../../data/models/app_user.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true; // true: Login, false: SignUp
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _getAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return '無効なメールアドレス形式です。';
      case 'user-disabled':
        return 'このアカウントは無効化されています。';
      case 'user-not-found':
        return 'ユーザーが見つかりません。';
      case 'wrong-password':
        return 'パスワードが間違っています。';
      case 'email-already-in-use':
        return 'このメールアドレスは既に登録されています。';
      case 'operation-not-allowed':
        return 'この認証方法は許可されていません。';
      case 'weak-password':
        return 'パスワードが弱すぎます（6文字以上必要です）。';
      case 'invalid-credential':
        return 'メールアドレスまたはパスワードが間違っています。';
      default:
        return '認証エラーが発生しました（${e.code}）';
    }
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isLogin) {
        // ログイン処理
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        // ログイン成功時に自己ベストの初期構築/更新バッチを実行
        FirestoreService().generateInitialDrylandPbs().catchError((e) {
          debugPrint('Dryland PB Auto-update failed: $e');
        });
      } else {
        // 新規登録処理
        final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        // 登録直後に初期プロフィールデータをFirestoreに作成
        if (userCredential.user != null) {
          final newUser = AppUser(
            uid: userCredential.user!.uid,
            displayName: 'スイマー', // デフォルト名
            vision: '',
            baseProfile: {
              'age': '', 'height': '', 'weight': '', 'environment': ''
            },
          );
          await FirestoreService().saveUserProfile(newUser);
        }
      }
      // 成功時は自動でStreamBuilderが反応して画面遷移する想定だが、念のため明示的にルーティング
      if (mounted) {
        context.go('/home');
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getAuthErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _errorMessage = '予期せぬエラーが発生しました: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = GoogleAuthProvider();
      final userCredential = await FirebaseAuth.instance.signInWithPopup(provider);
      
      if (userCredential.user != null && userCredential.additionalUserInfo?.isNewUser == true) {
        final newUser = AppUser(
          uid: userCredential.user!.uid,
          displayName: userCredential.user!.displayName ?? 'スイマー',
          vision: '',
          baseProfile: {
            'age': '', 'height': '', 'weight': '', 'environment': ''
          },
        );
        await FirestoreService().saveUserProfile(newUser);
      }
      
      if (mounted) {
        context.go('/home');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _getAuthErrorMessage(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '予期せぬエラーが発生しました: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'ログイン' : '新規登録'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.pool,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'AquaAnalyst AI',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 32),
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 16),
                    color: Colors.red.withOpacity(0.1),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'パスワード',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isLogin ? 'ログイン' : '登録する', style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('または'),
                    ),
                    Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: Text(_isLogin ? 'Googleでログイン' : 'Googleで登録', style: const TextStyle(fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = !_isLogin;
                      _errorMessage = null;
                    });
                  },
                  child: Text(
                    _isLogin ? '初めての方はこちら（新規登録）' : 'すでにアカウントをお持ちの方（ログイン）',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
