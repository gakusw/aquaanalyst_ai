import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'data/services/gemini_service.dart';

import 'ui/layouts/responsive_layout.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/agent_feedback_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/insight_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/weekly_plan_screen.dart';
import 'ui/screens/training_screen.dart';
import 'ui/screens/nutrition_screen.dart';
import 'ui/screens/body_composition_screen.dart';
import 'ui/screens/analysis_sheet_form.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/deferred_admin_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';

/// アプリ全体で共有するテーマ通知子（グローバル）
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.dark);

void main() async {
  debugPrint('--- APP STARTING ---');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('WidgetsFlutterBinding Initialized');
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('Firebase Initialized');

  try {
    await dotenv.load(fileName: ".env");
    debugPrint('.env loaded');
  } catch (e) {
    debugPrint('.env file not found. Ensure GEMINI_API_KEY is available in platform runtime.');
  }
  
  GeminiService().init();
  debugPrint('GeminiService Initialized');

  runApp(const ProviderScope(child: MyApp()));
  debugPrint('runApp called');
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home', // ログイン済みならHome、未ログインならredirectでAuthへ
  redirect: (context, state) {
    // 現在のユーザーログイン状態を確認
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    final isGoingToAuth = state.matchedLocation == '/auth';

    if (!isLoggedIn && !isGoingToAuth) {
      // 未ログインかつAuth画面以外に向かおうとしている場合はAuthへリダイレクト
      return '/auth';
    }
    if (isLoggedIn && isGoingToAuth) {
      // ログイン済みでAuth画面に向かおうとしている場合はHomeへリダイレクト
      return '/home';
    }
    return null;
  },
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('ページが見つかりません')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('パスが見つかりません: ${state.uri}'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context.go('/home'),
            child: const Text('ホームへ戻る'),
          ),
        ],
      ),
    ),
  ),
  routes: [
    GoRoute(
      path: '/',
      redirect: (_, __) => '/auth',
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return ResponsiveLayout(child: child);
      },
      routes: [
        GoRoute(path: '/home', builder: (context, state) => HomeScreen()),
        GoRoute(path: '/training', builder: (context, state) => const TrainingScreen()),
        GoRoute(path: '/nutrition', builder: (context, state) => const NutritionScreen()),
        GoRoute(path: '/body_composition', builder: (context, state) => const BodyCompositionScreen()),
        GoRoute(path: '/analysis', builder: (context, state) => const AnalysisSheetForm()),
        GoRoute(path: '/agent', builder: (context, state) => const AgentFeedbackScreen()),
        GoRoute(path: '/weekly', builder: (context, state) => const WeeklyPlanScreen()),
        GoRoute(path: '/insight', builder: (context, state) => const InsightScreen()),
        GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      ],
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const DeferredAdminScreen(),
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) {
        return MaterialApp.router(
          title: 'AquaAnalyst AI',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal, 
              brightness: Brightness.light,
            ).copyWith(
              onSurface: const Color(0xFF003737), // 濃いティール
              primary: const Color(0xFF006A6A),
              secondary: const Color(0xFF006A6A),
            ),
            useMaterial3: true,
            // 文字色全体を濃くする
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: Color(0xFF002222)),
              bodyMedium: TextStyle(color: Color(0xFF002222)),
              titleLarge: TextStyle(color: Color(0xFF002222)),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          themeMode: mode,
          routerConfig: _router,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ja', 'JP'),
          ],
        );
      },
    );
  }
}
