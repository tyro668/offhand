import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app.dart';
import 'database/app_database.dart';
import 'services/local_asr_worker_main.dart';
import 'services/overlay_service.dart';

void main(List<String> args) async {
  if (args.contains('--asr-worker')) {
    await LocalAsrWorkerMain.run();
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await AppDatabase.getInstance();

  // macOS: 恢复 Dock 显示设置
  if (Platform.isMacOS) {
    final showInDock = await AppDatabase.instance.getSetting('show_in_dock');
    if (showInDock == 'false') {
      await OverlayService.setShowInDock(false);
    }
  }

  runApp(const VoiceTypeApp());
}
