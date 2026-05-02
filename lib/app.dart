import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'l10n/app_localizations.dart';
import 'providers/recording_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/main_screen.dart';

class VoiceTypeApp extends StatelessWidget {
  const VoiceTypeApp({super.key});

  String? get _platformFontFamily {
    return defaultTargetPlatform == TargetPlatform.windows
        ? 'Microsoft YaHei'
        : null;
  }

  ShadThemeData _buildTheme(Brightness brightness) {
    final textTheme = _platformFontFamily == null
        ? ShadTextTheme()
        : ShadTextTheme(family: _platformFontFamily);
    return ShadThemeData(
      brightness: brightness,
      colorScheme: brightness == Brightness.dark
          ? const ShadBlueColorScheme.dark()
          : const ShadBlueColorScheme.light(),
      textTheme: textTheme,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()..load()),
        ChangeNotifierProvider(create: (_) => RecordingProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ShadApp(
            onGenerateTitle: (context) =>
                AppLocalizations.of(context)?.appTitle ?? 'Offhand',
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            locale: settings.locale,
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalShadLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const MainScreen(),
          );
        },
      ),
    );
  }
}
