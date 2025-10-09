// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:coalition_app_v2/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_http_overrides.dart';

void main() {
  testWidgets(
    'Bottom navigation switches to candidates page',
    (WidgetTester tester) async {
      await runWithHttpOverrides(tester, () async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MyApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.text('Feed'), findsWidgets);

        await tester.tap(find.text('Candidates'));
        await tester.pumpAndSettle();

        expect(find.text('TODO: Candidates page'), findsOneWidget);
      });
    },
  );
}
