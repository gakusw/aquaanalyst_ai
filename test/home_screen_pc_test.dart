
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aquaanalyst_ai/ui/screens/home_screen.dart';
import 'package:aquaanalyst_ai/data/providers/providers.dart';
import 'package:aquaanalyst_ai/data/models/training_record.dart';

void main() {
  testWidgets('Render HomeScreen on PC dimensions', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weeklyPlansProvider.overrideWith((ref) => const AsyncValue.data([])),
          userProfileProvider.overrideWith((ref) => const AsyncValue.loading()),
          trainingRecordsProvider.overrideWith((ref) => const AsyncValue.loading()),
          goalTimesProvider.overrideWith((ref) => const AsyncValue.data([])),
          todayRecordsProvider.overrideWith((ref) => []),
          categorizedPbsProvider.overrideWith((ref) => {'swim': [], 'dryland': []}),
          pbHistoryProvider.overrideWith((ref) => {'swim': [], 'dryland': []}),
          bodyCompositionRecordsProvider.overrideWith((ref) => []),
          recordsByEffectiveDayProvider.overrideWith((ref) => {}),
          raceRecordsProvider.overrideWith((ref) => const AsyncValue.data([])),
        ],
        child: const MaterialApp(
          home: Scaffold(body: HomeScreen()),
        ),
      ),
    );

    await tester.pumpAndSettle();
    
    // now try loaded state
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weeklyPlansProvider.overrideWith((ref) => const AsyncValue.data([])),
          userProfileProvider.overrideWith((ref) => AsyncValue.data(null)), // or mock user
          trainingRecordsProvider.overrideWith((ref) => const AsyncValue.data([])),
          goalTimesProvider.overrideWith((ref) => const AsyncValue.data([])),
          todayRecordsProvider.overrideWith((ref) => []),
          categorizedPbsProvider.overrideWith((ref) => {'swim': [], 'dryland': []}),
          pbHistoryProvider.overrideWith((ref) => {'swim': [], 'dryland': []}),
          bodyCompositionRecordsProvider.overrideWith((ref) => []),
          recordsByEffectiveDayProvider.overrideWith((ref) => {}),
          raceRecordsProvider.overrideWith((ref) => const AsyncValue.data([])),
        ],
        child: const MaterialApp(
          home: Scaffold(body: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}

