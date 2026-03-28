import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../../l10n/app_localizations.dart';
import '../../models/provider_config.dart';
import '../../models/scene_mode.dart';
import '../../providers/settings_provider.dart';
import '../../services/audio_recorder.dart';
import '../../services/log_service.dart';
import '../../services/overlay_service.dart';

class GeneralPage extends StatefulWidget {
  const GeneralPage({super.key});

  @override
  State<GeneralPage> createState() => _GeneralPageState();
}

class _GeneralPageState extends State<GeneralPage> {
  ColorScheme get _cs => Theme.of(context).colorScheme;

  bool? _micPermission;
  bool? _accessibilityPermission;
  String _currentDeviceName = '';
  bool _checkingMic = false;
  bool _checkingAccessibility = false;

  // Log
  String _logPath = '';
  String _logDirPath = '';
  int? _logFileSize;
  bool _logFileExists = false;

  // Recordings
  String _recordingsDirPath = '';
  int _recordingsFileCount = 0;
  int _recordingsTotalSize = 0;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadInputDevices();
    _loadLogInfo();
    _loadRecordingsInfo();
  }

  Future<void> _loadPermissions() async {
    final recorder = AudioRecorderService();
    final mic = await recorder.hasPermission();
    final accessibility = await OverlayService.checkAccessibility();
    if (mounted) {
      setState(() {
        _micPermission = mic;
        _accessibilityPermission = accessibility;
      });
    }
    recorder.dispose();
  }

  Future<void> _loadInputDevices() async {
    final recorder = AudioRecorderService();
    final devices = await recorder.listInputDevices();
    final preferred = await recorder.getPreferredInputDevice();
    if (mounted) {
      setState(() {
        _currentDeviceName = preferred?.label ?? _pickDeviceName(devices);
      });
    }
    recorder.dispose();
  }

  String _pickDeviceName(List<InputDevice> devices) {
    if (devices.isEmpty) return '';
    final defaultDevice = devices.firstWhere(
      (d) =>
          d.id.toLowerCase() == 'default' ||
          d.label.toLowerCase().contains('default'),
      orElse: () => devices.first,
    );
    return defaultDevice.label;
  }

  Future<void> _testMicPermission() async {
    setState(() => _checkingMic = true);
    final recorder = AudioRecorderService();
    final result = await recorder.hasPermission();
    if (mounted) {
      setState(() {
        _micPermission = result;
        _checkingMic = false;
      });
    }
    recorder.dispose();
  }

  Future<void> _testAccessibilityPermission() async {
    setState(() => _checkingAccessibility = true);
    final result = await OverlayService.requestAccessibility();
    if (mounted) {
      setState(() {
        _accessibilityPermission = result;
        _checkingAccessibility = false;
      });
    }
  }

  Future<void> _openAccessibilityPrivacyAndRemind(AppLocalizations l10n) async {
    await OverlayService.openAccessibilityPrivacy();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${l10n.openAccessibilityPrivacy} → ${l10n.testAccessibilityPermission}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadLogInfo() async {
    final logPath = await LogService.logFilePath;
    final logDirPath = await LogService.logDirectoryPath;
    final fileSize = await LogService.getLogFileSize();
    final fileExists = await LogService.logFileExists();
    if (mounted) {
      setState(() {
        _logPath = logPath;
        _logDirPath = logDirPath;
        _logFileSize = fileSize;
        _logFileExists = fileExists;
      });
    }
  }

  Future<void> _loadRecordingsInfo() async {
    try {
      final dir = await _getRecordingsDirectory();
      final dirPath = dir.path;
      var count = 0;
      var totalSize = 0;
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            count++;
            totalSize += await entity.length();
          }
        }
      }
      if (mounted) {
        setState(() {
          _recordingsDirPath = dirPath;
          _recordingsFileCount = count;
          _recordingsTotalSize = totalSize;
        });
      }
    } catch (_) {}
  }

  Future<Directory> _getRecordingsDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    return Directory('${appDir.path}/recordings');
  }

  Future<void> _openRecordingsDirectory() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('explorer', [_recordingsDirPath]);
      } else {
        result = await Process.run('open', [_recordingsDirPath]);
      }
      if (result.exitCode != 0 && !Platform.isWindows) {
        _showError(l10n.openFolderFailed);
      }
    } catch (e) {
      _showError(l10n.openFolderFailed);
    }
  }

  Future<void> _copyRecordingsPath() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: _recordingsDirPath));
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.recordingPathCopied),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearRecordings() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clearRecordingFiles),
        content: Text(l10n.clearRecordingFilesConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final dir = await _getRecordingsDirectory();
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
      await _loadRecordingsInfo();
    } catch (e) {
      _showError(l10n.cleanupFailed);
    }
  }

  Future<void> _openLogDirectory() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('explorer', [_logDirPath]);
      } else {
        result = await Process.run('open', [_logDirPath]);
      }
      if (result.exitCode != 0 && !Platform.isWindows) {
        _showError(l10n.openFolderFailed);
      }
    } catch (e) {
      _showError(l10n.openFolderFailed);
    }
  }

  Future<void> _copyLogPath() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: _logPath));
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.logPathCopied),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== 激活模式 =====
          Text(
            l10n.activationMode,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _ActivationModeSelector(settings: settings, l10n: l10n),
          const SizedBox(height: 8),
          Center(
            child: Text(
              settings.activationMode == ActivationMode.tapToTalk
                  ? l10n.tapToTalkDescription
                  : l10n.pushToTalkDescription,
              style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 32),

          // ===== 听写快捷键 =====
          Text(
            l10n.dictationHotkey,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.dictationHotkeyDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _HotkeyCapture(settings: settings, l10n: l10n),
          const SizedBox(height: 36),

          // ===== 会议快捷键 =====
          Text(
            l10n.meetingHotkey,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.meetingHotkeyDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _MeetingHotkeyCapture(settings: settings, l10n: l10n),
          const SizedBox(height: 36),

          // ===== 权限设置 =====
          Text(
            l10n.permissions,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.permissionsDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildPermissionButtons(l10n),
          const SizedBox(height: 12),
          _buildPermissionHint(l10n),
          const SizedBox(height: 36),

          // ===== 麦克风输入 =====
          Text(
            l10n.microphoneInput,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.microphoneInputDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildPreferBuiltIn(settings, l10n),
          const SizedBox(height: 12),
          _buildCurrentDevice(l10n),
          const SizedBox(height: 36),

          // ===== 最短录音时长 =====
          Text(
            l10n.minRecordingDuration,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.minRecordingDurationDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildMinDuration(settings, l10n),
          const SizedBox(height: 36),

          // ===== 智能静音检测 (VAD) =====
          Text(
            l10n.vadTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.vadDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildVadSection(settings, l10n),
          const SizedBox(height: 36),

          // ===== 场景模式 =====
          Text(
            l10n.sceneModeTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.sceneModeDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildSceneModeSelector(settings, l10n),
          const SizedBox(height: 36),

          Text(
            l10n.textProcessing,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.textProcessingDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildCorrectionSection(settings, l10n),
          const SizedBox(height: 12),
          _buildHistoryContextSection(settings, l10n),
          const SizedBox(height: 36),

          Text(
            l10n.language,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.languageDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildLanguageSelector(settings, l10n),
          const SizedBox(height: 36),

          // ===== 外观主题 =====
          Text(
            l10n.theme,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.themeDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildThemeSelector(settings, l10n),
          const SizedBox(height: 36),

          // ===== 本地模型闲置释放 =====
          Text(
            l10n.localModelIdleUnloadTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.localModelIdleUnloadDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildLocalLlmIdleUnloadSection(settings, l10n),
          const SizedBox(height: 36),

          // ===== 日志 =====
          Text(
            l10n.logs,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.logsDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildLogSection(l10n),
          const SizedBox(height: 36),

          // ===== 录音文件存储 =====
          Text(
            l10n.recordingStorage,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.recordingStorageDescription,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildRecordingsSection(l10n),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildMinDuration(SettingsProvider settings, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 20, color: _cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.ignoreShortRecordings,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _cs.onSurface,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: settings.minRecordingSeconds > 1
                ? () => settings.setMinRecordingSeconds(
                    settings.minRecordingSeconds - 1,
                  )
                : null,
            color: _cs.primary,
            splashRadius: 18,
          ),
          Text(
            '${settings.minRecordingSeconds} ${l10n.seconds}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: settings.minRecordingSeconds < 30
                ? () => settings.setMinRecordingSeconds(
                    settings.minRecordingSeconds + 1,
                  )
                : null,
            color: _cs.primary,
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildVadSection(SettingsProvider settings, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.mic_off_outlined,
                size: 20,
                color: _cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.vadEnable,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _cs.onSurface,
                  ),
                ),
              ),
              Switch(
                value: settings.vadEnabled,
                onChanged: (v) => settings.setVadEnabled(v),
              ),
            ],
          ),
          if (settings.vadEnabled) ...[
            const SizedBox(height: 16),
            Text(
              '${l10n.vadSilenceThreshold}: ${settings.vadSilenceThreshold.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
            ),
            Slider(
              value: settings.vadSilenceThreshold,
              min: 0.01,
              max: 0.3,
              divisions: 29,
              label: settings.vadSilenceThreshold.toStringAsFixed(2),
              onChanged: (v) => settings.setVadSilenceThreshold(v),
            ),
            const SizedBox(height: 8),
            Text(
              '${l10n.vadSilenceDuration}: ${settings.vadSilenceDurationSeconds} ${l10n.seconds}',
              style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
            ),
            Slider(
              value: settings.vadSilenceDurationSeconds.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '${settings.vadSilenceDurationSeconds} ${l10n.seconds}',
              onChanged: (v) => settings.setVadSilenceDuration(v.round()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSceneModeSelector(
    SettingsProvider settings,
    AppLocalizations l10n,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.category_outlined, size: 20, color: _cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.sceneModeLabel,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _cs.onSurface,
              ),
            ),
          ),
          DropdownButton<SceneMode>(
            value: settings.sceneMode,
            underline: const SizedBox(),
            borderRadius: BorderRadius.circular(8),
            items: SceneMode.values.map((mode) {
              final label = l10n.localeName == 'zh' ? mode.label : mode.labelEn;
              return DropdownMenuItem(value: mode, child: Text(label));
            }).toList(),
            onChanged: (mode) {
              if (mode != null) settings.setSceneMode(mode);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCorrectionSection(
    SettingsProvider settings,
    AppLocalizations l10n,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.spellcheck, size: 20, color: _cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.correctionEnabled,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.correctionDescription,
                      style: TextStyle(fontSize: 12, color: _cs.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: settings.correctionEnabled,
                onChanged: (v) => settings.setCorrectionEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.retrospectiveCorrectionEnabled,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.retrospectiveCorrectionDescription,
                      style: TextStyle(fontSize: 12, color: _cs.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: settings.retrospectiveCorrectionEnabled,
                onChanged: settings.correctionEnabled
                    ? (v) => settings.setRetrospectiveCorrectionEnabled(v)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryContextSection(
    SettingsProvider settings,
    AppLocalizations l10n,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.history_toggle_off_outlined, size: 20, color: _cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.historyContextEnabled,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.historyContextEnabledDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: _cs.outline,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: settings.historyContextEnhancementEnabled,
            onChanged: (v) => settings.setHistoryContextEnhancementEnabled(v),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector(
    SettingsProvider settings,
    AppLocalizations l10n,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.language_outlined, size: 20, color: _cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.interfaceLanguage,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<Locale>(
            segments: [
              ButtonSegment(
                value: const Locale('zh'),
                label: Text(l10n.simplifiedChinese),
              ),
              ButtonSegment(
                value: const Locale('en'),
                label: Text(l10n.english),
              ),
            ],
            selected: {settings.locale},
            onSelectionChanged: (selected) {
              if (selected.isNotEmpty) {
                settings.setLocale(selected.first);
              }
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _cs.primary;
                }
                return Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _cs.onPrimary;
                }
                return _cs.onSurface;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector(SettingsProvider settings, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.brightness_6_outlined,
            size: 20,
            color: _cs.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.themeMode,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text(l10n.themeSystem),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(l10n.themeLight),
              ),
              ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selected) {
              if (selected.isNotEmpty) {
                settings.setThemeMode(selected.first);
              }
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _cs.primary;
                }
                return Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _cs.onPrimary;
                }
                return _cs.onSurface;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalLlmIdleUnloadSection(
    SettingsProvider settings,
    AppLocalizations l10n,
  ) {
    const options = [0, 1, 3, 5, 10];
    final current = options.contains(settings.localLlmIdleUnloadMinutes)
        ? settings.localLlmIdleUnloadMinutes
        : 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.memory_outlined, size: 20, color: _cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.localModelIdleUnloadTiming,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: current,
            onChanged: (value) {
              if (value == null) return;
              settings.setLocalLlmIdleUnloadMinutes(value);
            },
            items: options
                .map(
                  (value) => DropdownMenuItem<int>(
                    value: value,
                    child: Text(
                      value == 0 ? l10n.off : l10n.minutesShort(value),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogSection(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                color: _cs.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.logFile,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurface,
                ),
              ),
              const Spacer(),
              if (_logFileExists)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    LogService.formatFileSize(_logFileSize ?? 0),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade700,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l10n.noLogFile,
                    style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                _logPath.isEmpty ? l10n.loading : _logPath,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: _cs.onSurfaceVariant,
                ),
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _logPath.isNotEmpty ? _openLogDirectory : null,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text(l10n.openLogDirectory),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _cs.primary,
                    foregroundColor: _cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _logPath.isNotEmpty ? _copyLogPath : null,
                icon: const Icon(Icons.copy, size: 18),
                label: Text(l10n.copyLogPath),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _cs.onSurfaceVariant,
                  side: BorderSide(color: _cs.outline),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingsSection(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.folder_outlined,
                color: _cs.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.recordingFiles,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$_recordingsFileCount ${l10n.files}  ·  ${LogService.formatFileSize(_recordingsTotalSize)}',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                _recordingsDirPath.isEmpty ? l10n.loading : _recordingsDirPath,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: _cs.onSurfaceVariant,
                ),
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _recordingsDirPath.isNotEmpty
                      ? _openRecordingsDirectory
                      : null,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text(l10n.openRecordingFolder),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _cs.primary,
                    foregroundColor: _cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _recordingsDirPath.isNotEmpty
                    ? _copyRecordingsPath
                    : null,
                icon: const Icon(Icons.copy, size: 18),
                label: Text(l10n.copyPath),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _cs.onSurfaceVariant,
                  side: BorderSide(color: _cs.outline),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _recordingsFileCount > 0 ? _clearRecordings : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(l10n.clearRecordingFiles),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(
                    color: _recordingsFileCount > 0
                        ? Colors.red.shade300
                        : _cs.outline,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionButtons(AppLocalizations l10n) {
    return Column(
      children: [
        // 测试麦克风权限
        _PermissionButton(
          icon: Icons.mic_outlined,
          label: l10n.testMicrophonePermission,
          status: _micPermission,
          loading: _checkingMic,
          onTap: _testMicPermission,
        ),
        const SizedBox(height: 8),
        // 测试辅助功能权限
        _PermissionButton(
          icon: Icons.accessibility_new_outlined,
          label: l10n.testAccessibilityPermission,
          status: _accessibilityPermission,
          loading: _checkingAccessibility,
          onTap: _testAccessibilityPermission,
        ),
        const SizedBox(height: 8),
        // 修复权限问题
        _PermissionButton(
          icon: Icons.build_outlined,
          label: l10n.fixPermissionIssues,
          onTap: () async {
            await _testMicPermission();
            await _testAccessibilityPermission();
          },
        ),
      ],
    );
  }

  Widget _buildPermissionHint(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.permissionHint,
            style: TextStyle(
              fontSize: 13,
              color: Colors.brown.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HintActionButton(
                label: l10n.openSoundInput,
                onTap: OverlayService.openSoundInput,
              ),
              _HintActionButton(
                label: l10n.openMicrophonePrivacy,
                onTap: OverlayService.openMicrophonePrivacy,
              ),
              _HintActionButton(
                label: l10n.openAccessibilityPrivacy,
                onTap: () => _openAccessibilityPrivacyAndRemind(l10n),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreferBuiltIn(SettingsProvider settings, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.preferBuiltInMicrophone,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.preferBuiltInMicrophoneSubtitle,
                  style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: settings.preferBuiltInMicrophone,
            activeTrackColor: _cs.primary,
            onChanged: (v) async {
              await settings.setPreferBuiltInMicrophone(v);
              await _loadInputDevices();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentDevice(AppLocalizations l10n) {
    final name = _currentDeviceName.isNotEmpty
        ? _currentDeviceName
        : l10n.noMicrophoneDetected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, size: 18, color: Colors.green.shade700),
          const SizedBox(width: 10),
          Text(
            '${l10n.using}: $name',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.green.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 权限按钮 ====================
class _PermissionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool? status; // null=未检测, true=已授权, false=未授权
  final bool loading;
  final VoidCallback onTap;

  const _PermissionButton({
    required this.icon,
    required this.label,
    this.status,
    this.loading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: loading ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (status != null && !loading)
                Icon(
                  status! ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color: status! ? Colors.green : Colors.red,
                )
              else if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 提示区操作按钮 ====================
class _HintActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _HintActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.brown.shade700,
        side: BorderSide(color: Colors.brown.shade300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

// ==================== 快捷键捕获组件 ====================
class _HotkeyCapture extends StatefulWidget {
  final SettingsProvider settings;
  final AppLocalizations l10n;
  const _HotkeyCapture({required this.settings, required this.l10n});

  @override
  State<_HotkeyCapture> createState() => _HotkeyCaptureState();
}

class _HotkeyCaptureState extends State<_HotkeyCapture> {
  ColorScheme get _cs => Theme.of(context).colorScheme;

  bool _listening = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            setState(() => _listening = true);
            _focusNode.requestFocus();
          },
          child: KeyboardListener(
            focusNode: _focusNode,
            onKeyEvent: _listening
                ? (event) {
                    if (event is KeyDownEvent) {
                      widget.settings.setHotkey(event.logicalKey);
                      setState(() => _listening = false);
                    }
                  }
                : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: _cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _listening ? _cs.primary : _cs.outlineVariant,
                  width: _listening ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: _cs.shadow.withValues(alpha: 0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _listening ? '...' : widget.settings.hotkeyLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _listening
                        ? widget.l10n.pressKeyToSet
                        : widget.l10n.clickToChangeHotkey,
                    style: TextStyle(
                      fontSize: 13,
                      color: _listening ? _cs.primary : _cs.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => widget.settings.resetHotkey(),
            icon: const Icon(Icons.restore, size: 16),
            label: Text(
              widget.l10n.resetHotkeyDefault(Platform.isWindows ? 'F2' : 'Fn'),
            ),
            style: TextButton.styleFrom(foregroundColor: _cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

// ==================== 会议快捷键捕获组件 ====================
class _MeetingHotkeyCapture extends StatefulWidget {
  final SettingsProvider settings;
  final AppLocalizations l10n;
  const _MeetingHotkeyCapture({required this.settings, required this.l10n});

  @override
  State<_MeetingHotkeyCapture> createState() => _MeetingHotkeyCaptureState();
}

class _MeetingHotkeyCaptureState extends State<_MeetingHotkeyCapture> {
  ColorScheme get _cs => Theme.of(context).colorScheme;

  bool _listening = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            setState(() => _listening = true);
            _focusNode.requestFocus();
          },
          child: KeyboardListener(
            focusNode: _focusNode,
            onKeyEvent: _listening
                ? (event) {
                    if (event is KeyDownEvent) {
                      if (SettingsProvider.isModifierKey(event.logicalKey)) {
                        return;
                      }
                      final pressedKeys =
                          HardwareKeyboard.instance.logicalKeysPressed;
                      final modifiers =
                          SettingsProvider.meetingModifiersFromPressedKeys(
                            pressedKeys,
                          );
                      widget.settings.setMeetingHotkey(
                        event.logicalKey,
                        modifiers: modifiers,
                      );
                      setState(() => _listening = false);
                    }
                  }
                : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: _cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _listening ? _cs.primary : _cs.outlineVariant,
                  width: _listening ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: _cs.shadow.withValues(alpha: 0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _listening ? '...' : widget.settings.meetingHotkeyLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _listening
                        ? widget.l10n.pressKeyToSet
                        : widget.l10n.clickToChangeHotkey,
                    style: TextStyle(
                      fontSize: 13,
                      color: _listening ? _cs.primary : _cs.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => widget.settings.resetMeetingHotkey(),
            icon: const Icon(Icons.restore, size: 16),
            label: Text(widget.l10n.resetHotkeyDefault('Ctrl+M')),
            style: TextButton.styleFrom(foregroundColor: _cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

// ==================== 激活模式选择器 ====================
class _ActivationModeSelector extends StatelessWidget {
  final SettingsProvider settings;
  final AppLocalizations l10n;
  const _ActivationModeSelector({required this.settings, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeCard(
            icon: Icons.touch_app_outlined,
            title: l10n.tapToTalk,
            subtitle: l10n.tapToTalkSubtitle,
            selected: settings.activationMode == ActivationMode.tapToTalk,
            onTap: () => settings.setActivationMode(ActivationMode.tapToTalk),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ModeCard(
            icon: Icons.pan_tool_outlined,
            title: l10n.pushToTalk,
            subtitle: l10n.pushToTalkSubtitle,
            selected: settings.activationMode == ActivationMode.pushToTalk,
            onTap: () => settings.setActivationMode(ActivationMode.pushToTalk),
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
