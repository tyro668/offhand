import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicetype/app.dart';
import 'package:voicetype/database/app_database.dart';
import 'package:voicetype/providers/settings_provider.dart';
import 'package:voicetype/screens/main_screen.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await AppDatabase.resetForTest();
    await AppDatabase.instance.setSetting(
      SettingsProvider.onboardingCompletedStorageKey,
      'true',
    );
  });

  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const VoiceTypeApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ShadApp), findsOneWidget);
    expect(find.byType(MainScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('App renders on narrow layout without overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VoiceTypeApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ShadApp), findsOneWidget);
    await tester.tap(find.text('记忆库'));
    await tester.pumpAndSettle();
    expect(find.text('添加记忆'), findsOneWidget);
    expect(find.text('上下文'), findsNothing);
    expect(find.text('实体'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 11));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 11));
  });
}
