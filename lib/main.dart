import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'data/services/gemini_service.dart';
import 'data/services/firestore_service.dart';
import 'data/providers/providers.dart';

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
import 'ui/screens/maintenance_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
        GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
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

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // アプリ起動時/ユーザーデータ取得時にテーマを同期
    ref.listen(userProfileProvider, (previous, next) {
      final user = next.value;
      if (user != null) {
        final savedTheme = user.baseProfile['themeMode'] as String?;
        if (savedTheme != null) {
          final newMode = savedTheme == 'dark' ? ThemeMode.dark 
                        : savedTheme == 'light' ? ThemeMode.light 
                        : ThemeMode.system;
          if (appThemeMode.value != newMode) {
            appThemeMode.value = newMode;
          }
        }
      }
    });

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) {
        const primaryColor = Color(0xFF0EA5E9); // Vibrant Blue
        const secondaryColor = Color(0xFF6366F1); // Indigo
        
        return MaterialApp.router(
          title: 'AquaAnalyst AI',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryColor,
              brightness: Brightness.light,
            ).copyWith(
              primary: primaryColor,
              secondary: secondaryColor,
              surface: const Color(0xFFF8FAFC),
            ),
            useMaterial3: true,
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
              ),
              color: Colors.white,
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
              titleTextStyle: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            textTheme: const TextTheme(
              titleLarge: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
              bodyLarge: TextStyle(color: Color(0xFF1E293B)),
              bodyMedium: TextStyle(color: Color(0xFF334155)),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryColor,
              brightness: Brightness.dark,
            ).copyWith(
              primary: primaryColor,
              secondary: secondaryColor,
              surface: const Color(0xFF020617), // Rich Black (was background)
              surfaceContainerHighest: const Color(0xFF0F172A), // Deep Navy (was surface)
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF020617),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
              color: const Color(0xFF1E293B).withValues(alpha: 0.5), // Glassy effect base
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
          ),
          themeMode: mode,
          routerConfig: _router,
          builder: (context, child) {
            final userAsync = ref.watch(userProfileProvider);
            final user = userAsync.value;
            final isAdmin = user?.role == 'admin';

            final settingsAsync = ref.watch(systemSettingsProvider);
            final isMaintenance = settingsAsync.value?['maintenance_mode'] == true;

            if (isMaintenance && !isAdmin) {
              return const MaintenanceScreen();
            }
            return child!;
          },
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
