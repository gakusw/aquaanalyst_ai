import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';

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
import 'ui/screens/analysis_sheet_form.dart';
import 'ui/screens/auth_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// アプリ全体で共有するテーマ通知子（グローバル）
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('.env file not found. Ensure GEMINI_API_KEY is available in platform runtime.');
  }
  GeminiService().init();

  runApp(const MyApp());
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/auth',
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
  routes: [
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
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => NoTransitionPage(
            child: HomeScreen(),
          ),
          routes: [
            GoRoute(path: 'training', builder: (context, state) => const TrainingScreen()),
            GoRoute(path: 'nutrition', builder: (context, state) => const NutritionScreen()),
            GoRoute(path: 'analysis', builder: (context, state) => const AnalysisSheetForm()),
          ],
        ),
        GoRoute(
          path: '/agent',
          pageBuilder: (context, state) => const NoTransitionPage(child: AgentFeedbackScreen()),
        ),
        GoRoute(
          path: '/weekly',
          pageBuilder: (context, state) => const NoTransitionPage(child: WeeklyPlanScreen()),
        ),
        GoRoute(
          path: '/insight',
          pageBuilder: (context, state) => const NoTransitionPage(child: InsightScreen()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(child: SettingsScreen()),
        ),
      ],
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
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.light),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          themeMode: mode,
          routerConfig: _router,
        );
      },
    );
  }
}
