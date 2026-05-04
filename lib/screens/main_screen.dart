import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/prompt_template.dart';
import '../models/provider_config.dart';
import '../providers/recording_provider.dart';
import '../providers/settings_provider.dart';
import '../services/log_service.dart';
import '../services/audio_recorder.dart';
import '../services/overlay_service.dart';
import 'pages/dictionary_page.dart';
import 'pages/history_page.dart';
import 'pages/dashboard_page.dart';
import 'onboarding_wizard.dart';
import 'settings_screen.dart';

/// macOS keyCode 到 Flutter LogicalKeyboardKey 的映射
const _macKeyCodeMap = <int, LogicalKeyboardKey>{
  63: LogicalKeyboardKey.fn,
  46: LogicalKeyboardKey.keyM,
  120: LogicalKeyboardKey.f2,
  99: LogicalKeyboardKey.f3,
  118: LogicalKeyboardKey.f4,
  96: LogicalKeyboardKey.f5,
  97: LogicalKeyboardKey.f6,
  98: LogicalKeyboardKey.f7,
  100: LogicalKeyboardKey.f8,
  101: LogicalKeyboardKey.f9,
  109: LogicalKeyboardKey.f10,
  103: LogicalKeyboardKey.f11,
  111: LogicalKeyboardKey.f12,
  49: LogicalKeyboardKey.space,
  36: LogicalKeyboardKey.enter,
  53: LogicalKeyboardKey.escape,
  48: LogicalKeyboardKey.tab,
};

/// Windows Virtual-Key 到 Flutter LogicalKeyboardKey 的映射
const _windowsKeyCodeMap = <int, LogicalKeyboardKey>{
  0x4D: LogicalKeyboardKey.keyM,
  0x71: LogicalKeyboardKey.f2,
  0x72: LogicalKeyboardKey.f3,
  0x73: LogicalKeyboardKey.f4,
  0x74: LogicalKeyboardKey.f5,
  0x75: LogicalKeyboardKey.f6,
  0x76: LogicalKeyboardKey.f7,
  0x77: LogicalKeyboardKey.f8,
  0x78: LogicalKeyboardKey.f9,
  0x79: LogicalKeyboardKey.f10,
  0x7A: LogicalKeyboardKey.f11,
  0x7B: LogicalKeyboardKey.f12,
  0x20: LogicalKeyboardKey.space,
  0x0D: LogicalKeyboardKey.enter,
  0x1B: LogicalKeyboardKey.escape,
  0x09: LogicalKeyboardKey.tab,
};

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  ColorScheme get _cs => Theme.of(context).colorScheme;

  String _localizedTemplateName(
    PromptTemplate template,
    AppLocalizations l10n,
  ) {
    if (!template.isBuiltin) return template.name;
    switch (template.id) {
      case PromptTemplate.defaultBuiltinId:
        return l10n.promptBuiltinDefaultName;
      case 'builtin_punctuation':
        return l10n.promptBuiltinPunctuationName;
      case 'builtin_formal':
        return l10n.promptBuiltinFormalName;
      case 'builtin_colloquial':
        return l10n.promptBuiltinColloquialName;
      case 'builtin_translate_en':
        return l10n.promptBuiltinTranslateEnName;
      default:
        return template.name;
    }
  }

  int _selectedNav = 0;
  late VoidCallback _settingsListener;
  SettingsProvider? _settingsProvider;
  bool _homeMicPermission = false;
  bool _homeAccessibilityPermission = false;
  bool _checkingHomePermissions = false;
  bool _homePermissionsChecked = false;
  LogicalKeyboardKey? _lastRegisteredHotkey;
  bool _fnTapToTalkPressCandidate = false;
  bool _onboardingDialogShown = false;

  /// 主导航项（首页 / 记忆库 / 转写档案）
  List<_NavItem> _getNavItems(
    AppLocalizations l10n, {
    required int pendingCandidateCount,
  }) => [
    _NavItem(icon: Icons.home_outlined, label: l10n.home),
    _NavItem(
      icon: Icons.menu_book_outlined,
      label: l10n.dictionarySettings,
      badgeCount: pendingCandidateCount,
    ),
    _NavItem(icon: Icons.history_outlined, label: l10n.history),
  ];

  @override
  void initState() {
    super.initState();
    OverlayService.init();
    OverlayService.onGlobalKeyEvent = _handleGlobalKeyEvent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsProvider>();
      _settingsProvider = settings;
      _settingsListener = () {
        _registerCurrentHotkey(settings);
        _maybeShowOnboarding(settings);
      };
      settings.addListener(_settingsListener);
      _settingsListener();
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        unawaited(_refreshHomePermissions());
      }
    });
  }

  Future<void> _refreshHomePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) return;
    if (_checkingHomePermissions) return;
    setState(() => _checkingHomePermissions = true);
    try {
      final mic = await AudioRecorderService().hasPermission();
      final accessibility = await OverlayService.checkAccessibility();
      if (!mounted) return;
      setState(() {
        _homeMicPermission = mic;
        _homeAccessibilityPermission = accessibility;
        _homePermissionsChecked = true;
      });
    } finally {
      if (mounted) {
        setState(() => _checkingHomePermissions = false);
      }
    }
  }

  Future<void> _requestMicPermissionFromHome() async {
    await AudioRecorderService().hasPermission();
    await _refreshHomePermissions();
    if (_homeMicPermission) return;
    await OverlayService.openMicrophonePrivacy();
  }

  Future<void> _requestAccessibilityPermissionFromHome() async {
    await OverlayService.requestAccessibility();
    await _refreshHomePermissions();
    if (_homeAccessibilityPermission) return;
    await OverlayService.openAccessibilityPrivacy();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
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

  void _registerCurrentHotkey(SettingsProvider settings) {
    // 只在热键实际变化时才重新注册，避免不必要的反复注册
    if (settings.hotkey == _lastRegisteredHotkey) return;
    _lastRegisteredHotkey = settings.hotkey;

    final keyCode = _platformKeyCodeFor(settings.hotkey);
    if (keyCode == null) return;

    LogService.info('HOTKEY', 'registering hotkey keyCode=$keyCode');
    OverlayService.registerHotkey(keyCode: keyCode).then((ok) {
      LogService.info('HOTKEY', 'registerHotkey result=$ok');
      if (!mounted || ok) return;
    });
  }

  void _maybeShowOnboarding(SettingsProvider settings) {
    if (!settings.loadCompleted ||
        !settings.shouldShowOnboardingOnLaunch ||
        _onboardingDialogShown) {
      return;
    }
    _onboardingDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !settings.shouldShowOnboardingOnLaunch) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const OnboardingWizard(),
      );
    });
  }

  bool _hasValidSttModel(SettingsProvider settings) {
    final model = settings.config.model.trim();
    if (model.isEmpty) return false;
    // 本地 sherpa-onnx 模型只需检查 model 非空即可；
    // 它们的模型文件名不在云端 preset 的 availableModels 列表中。
    if (settings.config.type == SttProviderType.senseVoice) {
      return true;
    }
    final preset = settings.currentPreset;
    if (preset != null && preset.availableModels.isNotEmpty) {
      return preset.availableModels.any((m) => m.id == model);
    }
    return true;
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        return Dialog(
          insetPadding: const EdgeInsets.all(32),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SizedBox(
            width: size.width * 0.95,
            height: size.height * 0.9,
            child: const SettingsScreen(),
          ),
        );
      },
    );
  }

  void _promptSttConfig() {
    OverlayService.showMainWindow();
    if (!mounted) return;
    // 打开设置界面，定位到语音模型页面
    _openSettings();
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.pleaseConfigureSttModel),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    OverlayService.onGlobalKeyEvent = null;
    _settingsProvider?.removeListener(_settingsListener);
    super.dispose();
  }

  int? _macKeyCodeFor(LogicalKeyboardKey key) {
    for (final entry in _macKeyCodeMap.entries) {
      if (entry.value == key) {
        return entry.key;
      }
    }
    return null;
  }

  int? _windowsKeyCodeFor(LogicalKeyboardKey key) {
    for (final entry in _windowsKeyCodeMap.entries) {
      if (entry.value == key) {
        return entry.key;
      }
    }
    return null;
  }

  int? _platformKeyCodeFor(LogicalKeyboardKey key) {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return _windowsKeyCodeFor(key);
    }
    return _macKeyCodeFor(key);
  }

  LogicalKeyboardKey? _platformKeyFromCode(int keyCode) {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return _windowsKeyCodeMap[keyCode];
    }
    return _macKeyCodeMap[keyCode];
  }

  void _handleGlobalKeyEvent(
    int keyCode,
    String type,
    bool isRepeat,
    bool hasModifiers,
    int modifiers,
  ) {
    if (isRepeat) return;

    final settings = context.read<SettingsProvider>();
    final key = _platformKeyFromCode(keyCode);
    if (key == null) return;

    // 单键快捷键：有修饰键（Cmd/Ctrl/Alt/Shift）按下时忽略
    if (hasModifiers) return;

    // 语音输入快捷键处理
    if (key != settings.hotkey) return;

    final recording = context.read<RecordingProvider>();

    LogService.info(
      'HOTKEY',
      'hotkey type=$type state=${recording.state} busy=${recording.busy} mode=${settings.activationMode}',
    );

    var effectiveType = type;

    if (settings.activationMode == ActivationMode.tapToTalk &&
        settings.hotkey == LogicalKeyboardKey.fn) {
      if (type == 'down') {
        _fnTapToTalkPressCandidate = !hasModifiers;
        return;
      }
      if (type == 'up') {
        final shouldTrigger = _fnTapToTalkPressCandidate && !hasModifiers;
        _fnTapToTalkPressCandidate = false;
        if (!shouldTrigger) return;
        effectiveType = 'down';
      } else {
        return;
      }
    }

    if (recording.busy) return;

    if (settings.activationMode == ActivationMode.tapToTalk) {
      if (effectiveType == 'down') {
        if (recording.state == RecordingState.recording) {
          // 防止重复触发 stop
          recording.stopAndTranscribe(
            settings.config,
            aiEnhanceEnabled: settings.aiEnhanceEnabled,
            aiEnhanceConfig: settings.effectiveAiEnhanceConfig,
            historyContextEnhancementEnabled:
                settings.historyContextEnhancementEnabled,
            minRecordingSeconds: settings.minRecordingSeconds,
            useStreaming: settings.aiEnhanceEnabled,
          );
        } else if (recording.state == RecordingState.idle) {
          if (!_hasValidSttModel(settings)) {
            _promptSttConfig();
            return;
          }
          _configureCorrection(settings, recording);
          recording.startRecording(settings.config);
          _startVadIfEnabled(settings, recording);
        }
        // transcribing 状态下忽略
      }
    } else {
      // push-to-talk 模式
      if (type == 'down' && recording.state == RecordingState.idle) {
        if (!_hasValidSttModel(settings)) {
          _promptSttConfig();
          return;
        }
        _configureCorrection(settings, recording);
        recording.startRecording(settings.config);
        _startVadIfEnabled(settings, recording);
      } else if (type == 'up' && recording.state == RecordingState.recording) {
        recording.stopAndTranscribe(
          settings.config,
          aiEnhanceEnabled: settings.aiEnhanceEnabled,
          aiEnhanceConfig: settings.effectiveAiEnhanceConfig,
          historyContextEnhancementEnabled:
              settings.historyContextEnhancementEnabled,
          minRecordingSeconds: settings.minRecordingSeconds,
          useStreaming: settings.aiEnhanceEnabled,
        );
      }
    }
  }

  /// 根据 SettingsProvider 状态配置或禁用纠错服务。
  void _configureCorrection(
    SettingsProvider settings,
    RecordingProvider recording,
  ) {
    if (settings.correctionEffective) {
      recording.configureCorrectionService(
        matcher: settings.pinyinMatcher,
        aiConfig: settings.effectiveAiEnhanceConfig,
        correctionPrompt: settings.correctionPrompt,
        dictionaryEntries: settings.dictionaryEntries,
        termContextEntries: settings.termContextEntries,
        entityMemories: settings.entityMemories,
        entityAliases: settings.entityAliases,
        entityRelations: settings.entityRelations,
        memoryItems: settings.adaptiveMemoryItems,
        maxReferenceEntries: settings.correctionMaxReferenceEntries,
        minCandidateScore: settings.correctionMinCandidateScore,
      );
      recording.onSessionGlossaryFlush = (entries, sourceRef) {
        return settings.recordSessionGlossaryMemory(
          entries,
          sourceRef: sourceRef,
        );
      };
      recording.onSttPromptTrace = settings.recordMemoryPromptInjection;
      recording.onMemoryCorrectionHit = (ids, {sourceRef = ''}) {
        return settings.recordMemoryCorrectionHit(ids, sourceRef: sourceRef);
      };
    } else {
      recording.disableCorrectionService();
      recording.onSessionGlossaryFlush = null;
      recording.onSttPromptTrace = null;
      recording.onMemoryCorrectionHit = null;
    }
    // 终态回溯开关同步
    recording.retrospectiveCorrectionEnabled =
        settings.retrospectiveCorrectionEnabled;
  }

  void _startVadIfEnabled(
    SettingsProvider settings,
    RecordingProvider recording,
  ) {
    if (!settings.vadEnabled) return;
    recording.onVadTriggered = () {
      if (recording.state == RecordingState.recording && !recording.busy) {
        recording.stopAndTranscribe(
          settings.config,
          aiEnhanceEnabled: settings.aiEnhanceEnabled,
          aiEnhanceConfig: settings.effectiveAiEnhanceConfig,
          historyContextEnhancementEnabled:
              settings.historyContextEnhancementEnabled,
          minRecordingSeconds: settings.minRecordingSeconds,
          useStreaming: settings.aiEnhanceEnabled,
        );
      }
    };
    recording.startVad(
      silenceThreshold: settings.vadSilenceThreshold,
      silenceDurationSeconds: settings.vadSilenceDurationSeconds,
      minRecordingSeconds: settings.minRecordingSeconds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    context.read<RecordingProvider>().setOverlayStateLabels(
      starting: l10n.overlayStarting,
      recording: l10n.overlayRecording,
      transcribing: l10n.overlayTranscribing,
      enhancing: l10n.overlayEnhancing,
      transcribeFailed: l10n.overlayTranscribeFailed,
    );
    OverlayService.setTrayLabels(open: l10n.trayOpen, quit: l10n.trayQuit);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                _cs.primary.withValues(alpha: 0.08),
                _cs.surface,
              ),
              Color.alphaBlend(
                _cs.primary.withValues(alpha: 0.04),
                _cs.surfaceContainerLow,
              ),
              _cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          minimum: const EdgeInsets.all(20),
          child: Container(
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                _cs.primary.withValues(alpha: 0.015),
                _cs.surface.withValues(alpha: 0.98),
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: _cs.primary.withValues(alpha: 0.09)),
              boxShadow: [
                BoxShadow(
                  color: _cs.primary.withValues(alpha: 0.04),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Row(
                children: [
                  _buildSidebar(),
                  Expanded(
                    child: Container(
                      color: _cs.surface,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                        child: _buildContent(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final navItems = _getNavItems(
      l10n,
      pendingCandidateCount: settings.dictationTermPendingCandidates.length,
    );
    return Container(
      width: 252,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _cs.primary.withValues(alpha: 0.035),
          _cs.surfaceContainerLow.withValues(alpha: 0.88),
        ),
        border: Border(
          right: BorderSide(color: _cs.primary.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _cs.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.mic_rounded,
                      size: 21,
                      color: _cs.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.appTitle,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _cs.onSurface,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Speak freely, write unbound',
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.2,
                            color: _cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text(
                l10n.workspaceLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurfaceVariant.withValues(alpha: 0.72),
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...List.generate(navItems.length, (i) {
              final item = navItems[i];
              final selected = _selectedNav == i;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                child: Material(
                  color: selected
                      ? _cs.primary.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _selectedNav = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: selected
                                  ? _cs.primary.withValues(alpha: 0.10)
                                  : Color.alphaBlend(
                                      _cs.primary.withValues(alpha: 0.02),
                                      _cs.surface,
                                    ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              item.icon,
                              size: 18,
                              color: selected
                                  ? _cs.primary
                                  : _cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: selected
                                    ? _cs.primary
                                    : _cs.onSurfaceVariant.withValues(
                                        alpha: 0.9,
                                      ),
                              ),
                            ),
                          ),
                          if (item.badgeCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? _cs.primary.withValues(alpha: 0.16)
                                    : _cs.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                item.badgeCount > 99
                                    ? '99+'
                                    : '${item.badgeCount}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? _cs.primary
                                      : _cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
            _buildSidebarPermissionPanel(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Divider(
                height: 1,
                thickness: 1,
                color: _cs.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            // 底部设置按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              child: Material(
                color: Color.alphaBlend(
                  _cs.primary.withValues(alpha: 0.015),
                  _cs.surface,
                ),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _openSettings,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Color.alphaBlend(
                              _cs.primary.withValues(alpha: 0.05),
                              _cs.surfaceContainerHigh,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.settings_outlined,
                            size: 16,
                            color: _cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          l10n.settings,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _cs.onSurface,
                          ),
                        ),
                        const Spacer(),
                        _buildPromptTemplateSelector(settings, l10n),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptTemplateSelector(
    SettingsProvider settings,
    AppLocalizations l10n,
  ) {
    final templates = settings.promptTemplates;
    if (templates.isEmpty) return const SizedBox.shrink();

    final activeTemplateId =
        templates.any(
          (template) => template.id == settings.activePromptTemplateId,
        )
        ? settings.activePromptTemplateId
        : templates.first.id;
    final activeTemplateIndex = templates.indexWhere(
      (template) => template.id == activeTemplateId,
    );
    final activeTemplateNumber = activeTemplateIndex >= 0
        ? activeTemplateIndex + 1
        : 1;

    return PopupMenuButton<String>(
      tooltip: l10n.promptTemplates,
      initialValue: activeTemplateId,
      onSelected: (templateId) {
        if (templateId == settings.activePromptTemplateId) return;
        settings.setActivePromptTemplate(templateId);
      },
      itemBuilder: (_) => templates.map((template) {
        return CheckedPopupMenuItem<String>(
          value: template.id,
          checked: template.id == activeTemplateId,
          child: SizedBox(
            width: 180,
            child: Text(
              _localizedTemplateName(template, l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_fix_high_outlined,
              size: 14,
              color: _cs.onSurfaceVariant.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 2),
            Text(
              '#$activeTemplateNumber',
              style: TextStyle(
                fontSize: 10,
                color: _cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return switch (_selectedNav) {
      0 => const DashboardPage(),
      1 => const DictionaryPage(),
      2 => HistoryPage(
        onOpenPendingCandidates: () {
          setState(() {
            _selectedNav = 1;
          });
        },
      ),
      _ => const SizedBox(),
    };
  }

  Widget _buildSidebarPermissionPanel() {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return const SizedBox.shrink();
    }

    final hasMissingPermission =
        !_homePermissionsChecked ||
        !_homeMicPermission ||
        !_homeAccessibilityPermission;
    if (!_checkingHomePermissions && !hasMissingPermission) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final showMic = !_homeMicPermission;
    final showAccessibility = !_homeAccessibilityPermission;

    Widget permissionRow({
      required IconData icon,
      required String title,
      required bool granted,
      required VoidCallback? onTap,
    }) {
      final statusColor = granted ? _cs.primary : _cs.error;
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: _cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (granted)
              Icon(Icons.check_circle_rounded, size: 16, color: statusColor)
            else
              SizedBox(
                height: 28,
                child: FilledButton.tonal(
                  onPressed: _checkingHomePermissions ? null : onTap,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(l10n.openSettings),
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            _cs.error.withValues(alpha: hasMissingPermission ? 0.035 : 0.0),
            _cs.surface,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasMissingPermission
                ? _cs.error.withValues(alpha: 0.18)
                : _cs.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security_outlined, size: 17, color: _cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.permissions,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.fixPermissionIssues,
                  visualDensity: VisualDensity.compact,
                  onPressed: _checkingHomePermissions
                      ? null
                      : _refreshHomePermissions,
                  icon: _checkingHomePermissions
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _cs.primary,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 17),
                ),
              ],
            ),
            if (!_homePermissionsChecked && !_checkingHomePermissions)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.fixPermissionIssues,
                  style: TextStyle(
                    fontSize: 12,
                    color: _cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (showMic || !_homePermissionsChecked)
              permissionRow(
                icon: Icons.mic_outlined,
                title: l10n.testMicrophonePermission,
                granted: _homePermissionsChecked && _homeMicPermission,
                onTap: _requestMicPermissionFromHome,
              ),
            if (showAccessibility || !_homePermissionsChecked)
              permissionRow(
                icon: Icons.accessibility_new_outlined,
                title: l10n.testAccessibilityPermission,
                granted:
                    _homePermissionsChecked && _homeAccessibilityPermission,
                onTap: _requestAccessibilityPermissionFromHome,
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final int badgeCount;

  const _NavItem({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });
}
