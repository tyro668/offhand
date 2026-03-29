import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicetype/database/app_database.dart';
import 'package:voicetype/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.resetForTest();
  });

  test('meeting hotkey defaults to Ctrl+M after load', () async {
    final settings = SettingsProvider();
    await settings.load();

    expect(settings.meetingHotkey, LogicalKeyboardKey.keyM);
    expect(
      settings.meetingHotkeyModifiers,
      SettingsProvider.meetingHotkeyModifierCtrl,
    );
    expect(settings.meetingHotkeyLabel, 'Ctrl+M');
  });

  test('meeting hotkey persists key combination', () async {
    final settings = SettingsProvider();
    await settings.load();

    await settings.setMeetingHotkey(
      LogicalKeyboardKey.keyK,
      modifiers:
          SettingsProvider.meetingHotkeyModifierCtrl |
          SettingsProvider.meetingHotkeyModifierShift,
    );

    final reloaded = SettingsProvider();
    await reloaded.load();

    expect(reloaded.meetingHotkey, LogicalKeyboardKey.keyK);
    expect(
      reloaded.meetingHotkeyModifiers,
      SettingsProvider.meetingHotkeyModifierCtrl |
          SettingsProvider.meetingHotkeyModifierShift,
    );
    expect(reloaded.meetingHotkeyLabel, 'Ctrl+Shift+K');
  });
}
