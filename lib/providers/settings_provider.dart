import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/ai_enhance_config.dart';
import '../models/ai_model_entry.dart';
import '../models/ai_vendor_preset.dart';
import '../models/network_settings.dart';
import '../models/dictionary_entry.dart';
import '../models/prompt_template.dart';
import '../models/provider_config.dart';
import '../models/scene_mode.dart';
import '../models/stt_model_entry.dart';
import '../database/app_database.dart';
import '../services/network_client_service.dart';
import '../services/pinyin_matcher.dart';
import '../services/local_llm_service.dart';

class DictionaryCsvImportResult {
  final int totalRows;
  final int importedRows;
  final int skippedRows;

  const DictionaryCsvImportResult({
    required this.totalRows,
    required this.importedRows,
    required this.skippedRows,
  });
}

class SettingsProvider extends ChangeNotifier {
  static const _correctionMaxReferenceEntries = 15;
  static const _correctionMinCandidateScore = 0.30;
  static const _correctionEnableSingleCharFuzzy = false;

  static const _configKey = 'stt_provider_config';
  static const _hotkeyKey = 'hotkey';
  static const _meetingHotkeyKey = 'meeting_hotkey';
  static const _meetingHotkeyModifiersKey = 'meeting_hotkey_modifiers';
  static const _activationModeKey = 'activation_mode';
  static const _aiEnhanceEnabledKey = 'ai_enhance_enabled';
  static const _aiEnhanceConfigKey = 'ai_enhance_config';
  static const _aiEnhanceDefaultModelsKey = 'ai_enhance_default_models';
  static const _aiEnhanceUseCustomPromptKey = 'ai_enhance_use_custom_prompt';
  static const _minRecordingSecondsKey = 'min_recording_seconds';
  static const _aiModelEntriesKey = 'ai_model_entries';
  static const _sttModelEntriesKey = 'stt_model_entries';
  static const _localeKey = 'locale';
  static const _networkProxyModeKey = 'network_proxy_mode';
  static const _themeModeKey = 'theme_mode';
  static const _vadEnabledKey = 'vad_enabled';
  static const _vadSilenceThresholdKey = 'vad_silence_threshold';
  static const _vadSilenceDurationKey = 'vad_silence_duration';
  static const _promptTemplatesKey = 'prompt_templates';
  static const _activePromptTemplateIdKey = 'active_prompt_template_id';
  static const _sceneModeKey = 'scene_mode';
  static const _dictionaryEntriesKey = 'dictionary_entries';
  static const _correctionEnabledKey = 'correction_enabled';
  static const _retrospectiveCorrectionEnabledKey =
      'retrospective_correction_enabled';
  static const _localLlmIdleUnloadMinutesKey = 'local_llm_idle_unload_minutes';
  static const _speaker3dEnabledKey = 'speaker_3d_enabled';
  static const _speaker3dModelPathKey = 'speaker_3d_model_path';
  static const _speaker3dModelPathsKey = 'speaker_3d_model_paths';
  static const _speaker3dMaxSpeakersKey = 'speaker_3d_max_speakers';
  static const _speaker3dSingleSpeakerModeKey =
      'speaker_3d_single_speaker_mode';
  static const _speaker3dOnlineBaseThresholdKey =
      'speaker_3d_online_base_threshold';
  static const _speaker3dTop1Top2MarginKey = 'speaker_3d_top1_top2_margin';
  static const _speaker3dOfflineMergeThresholdKey =
      'speaker_3d_offline_merge_threshold';
  static const _speaker3dDownloadSourceModeKey =
      'speaker_3d_download_source_mode';
  static const _speaker3dDownloadSourceModeAuto = 'auto';
  static const _speaker3dDownloadSourceModeDirect = 'direct';
  static const _speaker3dDownloadSourceModeMirror = 'mirror';
  static const speaker3dPresetConsistency = 'consistency';
  static const speaker3dPresetBalanced = 'balanced';
  static const speaker3dPresetSeparation = 'separation';

  List<SttProviderConfig> _sttPresets = List<SttProviderConfig>.from(
    SttProviderConfig.fallbackPresets,
  );
  List<AiVendorPreset> _aiPresets = List<AiVendorPreset>.from(
    AiVendorPreset.fallbackPresets,
  );
  SttProviderConfig _config = SttProviderConfig.fallbackPresets.first;
  List<SttProviderConfig> _customProviders = [];

  static LogicalKeyboardKey get defaultHotkey {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return LogicalKeyboardKey.f2;
    }
    return LogicalKeyboardKey.fn;
  }

  static LogicalKeyboardKey get defaultMeetingHotkey {
    return LogicalKeyboardKey.keyM;
  }

  static const int meetingHotkeyModifierCtrl = 1 << 0;
  static const int meetingHotkeyModifierAlt = 1 << 1;
  static const int meetingHotkeyModifierShift = 1 << 2;
  static const int meetingHotkeyModifierMeta = 1 << 3;

  static int get defaultMeetingHotkeyModifiers => meetingHotkeyModifierCtrl;

  // 快捷键配置
  LogicalKeyboardKey _hotkey = defaultHotkey;
  LogicalKeyboardKey _meetingHotkey = defaultMeetingHotkey;
  int _meetingHotkeyModifiers = defaultMeetingHotkeyModifiers;
  ActivationMode _activationMode = ActivationMode.tapToTalk;

  /// 每个服务商独立存储的 API Key（按 name 索引）
  final Map<String, String> _apiKeys = {};

  bool _aiEnhanceEnabled = false;
  AiEnhanceConfig _aiEnhanceConfig = AiEnhanceConfig.defaultConfig;
  final Map<String, String> _aiEnhanceDefaultModels = {};
  bool _aiEnhanceUseCustomPrompt = false;
  String _aiEnhanceDefaultPrompt = AiEnhanceConfig.defaultPrompt;
  int _minRecordingSeconds = 3;
  List<AiModelEntry> _aiModelEntries = [];
  List<SttModelEntry> _sttModelEntries = [];
  Locale _locale = const Locale('zh');
  NetworkProxyMode _networkProxyMode = NetworkProxyMode.none;
  ThemeMode _themeMode = ThemeMode.system;

  // VAD settings
  bool _vadEnabled = false;
  double _vadSilenceThreshold = 0.05;
  int _vadSilenceDurationSeconds = 3;

  // Prompt template management
  List<PromptTemplate> _promptTemplates = [];
  String? _activePromptTemplateId;

  // Scene mode
  SceneMode _sceneMode = SceneMode.general;

  // Dictionary entries
  List<DictionaryEntry> _dictionaryEntries = [];

  // Correction settings
  bool _correctionEnabled = true;
  bool _retrospectiveCorrectionEnabled = false;
  String _correctionPrompt = '';
  int _localLlmIdleUnloadMinutes = 3;
  bool _speaker3dEnabled = true;
  String _speaker3dModelPath = '';
  List<String> _speaker3dModelPaths = [];
  int _speaker3dMaxSpeakers = 6;
  bool _speaker3dSingleSpeakerMode = false;
  double _speaker3dOnlineBaseThreshold = 0.78;
  double _speaker3dTop1Top2Margin = 0.04;
  double _speaker3dOfflineMergeThreshold = 0.80;
  String _speaker3dDownloadSourceMode = _speaker3dDownloadSourceModeAuto;
  final PinyinMatcher _pinyinMatcher = PinyinMatcher(
    enableSingleCharFuzzy: _correctionEnableSingleCharFuzzy,
  );

  SttProviderConfig get config => _config;
  List<SttProviderConfig> get sttPresets => _sttPresets;
  List<AiVendorPreset> get aiPresets => _aiPresets;
  LogicalKeyboardKey get hotkey => _hotkey;
  LogicalKeyboardKey get meetingHotkey => _meetingHotkey;
  int get meetingHotkeyModifiers => _meetingHotkeyModifiers;
  ActivationMode get activationMode => _activationMode;
  bool get aiEnhanceEnabled => _aiEnhanceEnabled;
  AiEnhanceConfig get aiEnhanceConfig => _aiEnhanceConfig;
  bool get aiEnhanceUseCustomPrompt => _aiEnhanceUseCustomPrompt;
  String get aiEnhanceDefaultPrompt => _aiEnhanceDefaultPrompt;
  int get minRecordingSeconds => _minRecordingSeconds;
  List<AiModelEntry> get aiModelEntries => List.unmodifiable(_aiModelEntries);
  AiModelEntry? get activeAiModelEntry {
    try {
      return _aiModelEntries.firstWhere((e) => e.enabled);
    } catch (_) {
      return null;
    }
  }

  List<SttModelEntry> get sttModelEntries =>
      List.unmodifiable(_sttModelEntries);
  SttModelEntry? get activeSttModelEntry {
    try {
      return _sttModelEntries.firstWhere((e) => e.enabled);
    } catch (_) {
      return null;
    }
  }

  Locale get locale => _locale;
  NetworkProxyMode get networkProxyMode => _networkProxyMode;
  ThemeMode get themeMode => _themeMode;

  // VAD getters
  bool get vadEnabled => _vadEnabled;
  double get vadSilenceThreshold => _vadSilenceThreshold;
  int get vadSilenceDurationSeconds => _vadSilenceDurationSeconds;

  // Prompt template getters
  List<PromptTemplate> get promptTemplates =>
      List.unmodifiable(_promptTemplates);
  String? get activePromptTemplateId => _activePromptTemplateId;
  PromptTemplate? get activePromptTemplate {
    if (_activePromptTemplateId == null) return null;
    try {
      return _promptTemplates.firstWhere(
        (t) => t.id == _activePromptTemplateId,
      );
    } catch (_) {
      return null;
    }
  }

  // Scene mode getter
  SceneMode get sceneMode => _sceneMode;

  // Dictionary getter
  List<DictionaryEntry> get dictionaryEntries =>
      List.unmodifiable(_dictionaryEntries);

  // Correction getters
  bool get correctionEnabled => _correctionEnabled;
  bool get retrospectiveCorrectionEnabled => _retrospectiveCorrectionEnabled;
  String get correctionPrompt => _correctionPrompt;
  int get localLlmIdleUnloadMinutes => _localLlmIdleUnloadMinutes;
  bool get speaker3dEnabled => _speaker3dEnabled;
  String get speaker3dModelPath => _speaker3dModelPath;
  List<String> get speaker3dModelPaths =>
      List.unmodifiable(_speaker3dModelPaths);
  int get speaker3dMaxSpeakers => _speaker3dMaxSpeakers;
  bool get speaker3dSingleSpeakerMode => _speaker3dSingleSpeakerMode;
  double get speaker3dOnlineBaseThreshold => _speaker3dOnlineBaseThreshold;
  double get speaker3dTop1Top2Margin => _speaker3dTop1Top2Margin;
  double get speaker3dOfflineMergeThreshold => _speaker3dOfflineMergeThreshold;
  String get speaker3dDownloadSourceMode => _speaker3dDownloadSourceMode;
  PinyinMatcher get pinyinMatcher => _pinyinMatcher;
  int get correctionMaxReferenceEntries => _correctionMaxReferenceEntries;
  double get correctionMinCandidateScore => _correctionMinCandidateScore;
  bool get correctionEnableSingleCharFuzzy => _correctionEnableSingleCharFuzzy;

  AiEnhanceConfig get effectiveAiEnhanceConfig {
    final active = activeAiModelEntry;
    final base = active != null
        ? _aiEnhanceConfig.copyWith(
            baseUrl: active.baseUrl,
            apiKey: active.apiKey,
            model: active.model,
          )
        : _aiEnhanceConfig;
    // Priority: active template > custom prompt > default prompt
    String resolvedPrompt;
    final template = activePromptTemplate;
    if (template != null) {
      resolvedPrompt = template.content;
    } else if (_aiEnhanceUseCustomPrompt) {
      resolvedPrompt = base.prompt;
    } else {
      resolvedPrompt = _aiEnhanceDefaultPrompt;
    }

    // Append scene mode suffix if not general
    if (_sceneMode != SceneMode.general) {
      resolvedPrompt += _sceneMode.promptSuffix;
    }

    // Append dictionary words to AI enhance prompt so the LLM preserves
    // corrected terms and does not rewrite them (e.g. 帆软 → FanRuan).
    final dictSuffix = dictionaryWordsForPrompt;
    if (dictSuffix.isNotEmpty) {
      resolvedPrompt += dictSuffix;
    }

    return base.copyWith(prompt: resolvedPrompt);
  }

  String? aiEnhanceDefaultModelFor(String baseUrl) =>
      _aiEnhanceDefaultModels[baseUrl];

  List<SttProviderConfig> get allProviders => [
    ..._sttPresets,
    ..._customProviders,
  ];

  List<SttProviderConfig> get customProviders => _customProviders;

  /// 获取当前选中服务商的 preset（带 availableModels）
  SttProviderConfig? get currentPreset {
    try {
      return _sttPresets.firstWhere((p) => p.name == _config.name);
    } catch (_) {
      return null;
    }
  }

  // ===== API Key 辅助方法 =====

  /// 去除旧的 ENC: 加密前缀（兼容迁移），返回明文。
  String _resolveApiKey(String raw) {
    var value = raw.trim();
    // 旧版本可能存有 ENC: 前缀的加密密钥，无法解密则清空
    if (value.startsWith('ENC:')) return '';
    return value;
  }

  Future<void> load() async {
    final db = AppDatabase.instance;

    await _loadPresetsFromAssets();

    // 加载服务商配置
    final configJson = await db.getSetting(_configKey);
    if (configJson != null) {
      final decoded = json.decode(configJson) as Map<String, dynamic>;
      _config = SttProviderConfig.fromJson(_cleanApiKeyInJson(decoded));
    }

    // 加载自定义服务商
    final customJson = await db.getSetting('custom_providers');
    if (customJson != null) {
      _customProviders = (json.decode(customJson) as List)
          .map(
            (e) => SttProviderConfig.fromJson(
              _cleanApiKeyInJson(e as Map<String, dynamic>),
            ),
          )
          .toList();
    }

    // 加载 API Keys
    final keysJson = await db.getSetting('api_keys');
    if (keysJson != null) {
      final raw = Map<String, String>.from(json.decode(keysJson));
      for (final entry in raw.entries) {
        _apiKeys[entry.key] = _resolveApiKey(entry.value);
      }
    }
    // 将存储的 apiKey 应用到当前配置
    if (_apiKeys.containsKey(_config.name)) {
      _config = _config.copyWith(apiKey: _apiKeys[_config.name]);
    }

    // 加载快捷键
    final hotkeyStr = await db.getSetting(_hotkeyKey);
    if (hotkeyStr != null) {
      _hotkey = LogicalKeyboardKey(int.parse(hotkeyStr));
    }
    if (defaultTargetPlatform == TargetPlatform.windows &&
        _hotkey == LogicalKeyboardKey.fn) {
      _hotkey = LogicalKeyboardKey.f2;
      await _saveSetting(_hotkeyKey, _hotkey.keyId.toString());
    }

    // 加载会议快捷键
    final meetingHotkeyStr = await db.getSetting(_meetingHotkeyKey);
    if (meetingHotkeyStr != null) {
      _meetingHotkey = LogicalKeyboardKey(int.parse(meetingHotkeyStr));
    }
    final meetingHotkeyModifiersStr = await db.getSetting(
      _meetingHotkeyModifiersKey,
    );
    if (meetingHotkeyModifiersStr != null) {
      _meetingHotkeyModifiers =
          int.tryParse(meetingHotkeyModifiersStr) ??
          defaultMeetingHotkeyModifiers;
    }
    if (_meetingHotkey == LogicalKeyboardKey.fn) {
      _meetingHotkey = defaultMeetingHotkey;
      _meetingHotkeyModifiers = defaultMeetingHotkeyModifiers;
      await _saveSetting(_meetingHotkeyKey, _meetingHotkey.keyId.toString());
      await _saveSetting(
        _meetingHotkeyModifiersKey,
        _meetingHotkeyModifiers.toString(),
      );
    }

    // 加载激活模式
    final modeStr = await db.getSetting(_activationModeKey);
    if (modeStr != null) {
      _activationMode = ActivationMode.values[int.parse(modeStr)];
    }

    final aiEnabledStr = await db.getSetting(_aiEnhanceEnabledKey);
    if (aiEnabledStr != null) {
      _aiEnhanceEnabled = aiEnabledStr == 'true';
    }

    final useCustomStr = await db.getSetting(_aiEnhanceUseCustomPromptKey);
    if (useCustomStr != null) {
      _aiEnhanceUseCustomPrompt = useCustomStr == 'true';
    }

    final minSecStr = await db.getSetting(_minRecordingSecondsKey);
    if (minSecStr != null) {
      _minRecordingSeconds = int.parse(minSecStr);
    }

    try {
      final prompt = await rootBundle.loadString(
        'assets/prompts/default_prompt.md',
      );
      _aiEnhanceDefaultPrompt = prompt;
    } catch (_) {}

    final aiEnhanceJson = await db.getSetting(_aiEnhanceConfigKey);
    if (aiEnhanceJson != null) {
      final decoded = json.decode(aiEnhanceJson) as Map<String, dynamic>;
      _aiEnhanceConfig = AiEnhanceConfig.fromJson(_cleanApiKeyInJson(decoded));
    } else {
      _aiEnhanceConfig = _aiEnhanceConfig.copyWith(
        prompt: _aiEnhanceDefaultPrompt,
      );
    }

    final defaultModelsJson = await db.getSetting(_aiEnhanceDefaultModelsKey);
    if (defaultModelsJson != null) {
      _aiEnhanceDefaultModels.addAll(
        Map<String, String>.from(json.decode(defaultModelsJson)),
      );
    }

    // 加载文本模型条目列表
    final entriesJson = await db.getSetting(_aiModelEntriesKey);
    if (entriesJson != null) {
      try {
        final list = json.decode(entriesJson) as List<dynamic>;
        _aiModelEntries = list
            .whereType<Map<String, dynamic>>()
            .map((e) => AiModelEntry.fromJson(_cleanApiKeyInJson(e)))
            .toList();
      } catch (_) {}
    }
    // 如果有激活条目，同步到 aiEnhanceConfig
    final active = activeAiModelEntry;
    if (active != null) {
      _aiEnhanceConfig = _aiEnhanceConfig.copyWith(
        baseUrl: active.baseUrl,
        apiKey: active.apiKey,
        model: active.model,
      );
    }

    // 加载语音模型条目列表
    final sttEntriesJson = await db.getSetting(_sttModelEntriesKey);
    if (sttEntriesJson != null) {
      try {
        final list = json.decode(sttEntriesJson) as List<dynamic>;
        _sttModelEntries = list
            .whereType<Map<String, dynamic>>()
            .map((e) => SttModelEntry.fromJson(_cleanApiKeyInJson(e)))
            .toList();
      } catch (_) {}
    }
    // 如果有激活的语音模型条目，同步到 config
    final activeStt = activeSttModelEntry;
    if (activeStt != null) {
      _syncSttConfigFromActiveEntry();
    }

    // 加载语言设置
    final localeStr = await db.getSetting(_localeKey);
    if (localeStr != null) {
      _locale = Locale(localeStr);
    }

    // 加载主题模式
    final themeModeStr = await db.getSetting(_themeModeKey);
    if (themeModeStr != null) {
      _themeMode = switch (themeModeStr) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    }

    final proxyModeStr = await db.getSetting(_networkProxyModeKey);
    _networkProxyMode = NetworkProxyModeX.fromStorage(proxyModeStr);
    NetworkClientService.setProxyMode(_networkProxyMode);

    // 加载 VAD 设置
    final vadEnabledStr = await db.getSetting(_vadEnabledKey);
    if (vadEnabledStr != null) {
      _vadEnabled = vadEnabledStr == 'true';
    }
    final vadThresholdStr = await db.getSetting(_vadSilenceThresholdKey);
    if (vadThresholdStr != null) {
      _vadSilenceThreshold = double.tryParse(vadThresholdStr) ?? 0.05;
    }
    final vadDurationStr = await db.getSetting(_vadSilenceDurationKey);
    if (vadDurationStr != null) {
      _vadSilenceDurationSeconds = int.tryParse(vadDurationStr) ?? 3;
    }

    // 加载 Prompt 模板
    final templatesJson = await db.getSetting(_promptTemplatesKey);
    if (templatesJson != null) {
      try {
        final list = json.decode(templatesJson) as List<dynamic>;
        _promptTemplates = list
            .whereType<Map<String, dynamic>>()
            .map((e) => PromptTemplate.fromJson(e))
            .toList();
      } catch (_) {}
    }
    final builtins = await _loadBuiltinPromptTemplates();
    final customTemplates = _promptTemplates
        .where((t) => !t.isBuiltin)
        .toList();
    _promptTemplates = [...builtins, ...customTemplates];

    final activeTemplateIdRaw = await db.getSetting(_activePromptTemplateIdKey);
    _activePromptTemplateId = _resolvedActivePromptTemplateId(
      activeTemplateIdRaw,
    );

    await _savePromptTemplates();
    await _saveSetting(
      _activePromptTemplateIdKey,
      _activePromptTemplateId ?? PromptTemplate.defaultBuiltinId,
    );

    // 加载场景模式
    final sceneModeStr = await db.getSetting(_sceneModeKey);
    if (sceneModeStr != null) {
      _sceneMode = SceneMode.fromString(sceneModeStr);
    }

    // 加载词典
    final dictJson = await db.getSetting(_dictionaryEntriesKey);
    if (dictJson != null) {
      try {
        final list = json.decode(dictJson) as List<dynamic>;
        _dictionaryEntries = list
            .whereType<Map<String, dynamic>>()
            .map((e) => DictionaryEntry.fromJson(e))
            .toList();
      } catch (_) {}
    }

    // 构建拼音索引
    _pinyinMatcher.buildIndex(_dictionaryEntries);

    // 加载纠错设置
    final correctionEnabledStr = await db.getSetting(_correctionEnabledKey);
    if (correctionEnabledStr != null) {
      _correctionEnabled = correctionEnabledStr == 'true';
    }

    final retroStr = await db.getSetting(_retrospectiveCorrectionEnabledKey);
    if (retroStr != null) {
      _retrospectiveCorrectionEnabled = retroStr == 'true';
    }

    final localLlmIdleUnloadMinutesStr = await db.getSetting(
      _localLlmIdleUnloadMinutesKey,
    );
    if (localLlmIdleUnloadMinutesStr != null) {
      _localLlmIdleUnloadMinutes =
          int.tryParse(localLlmIdleUnloadMinutesStr)?.clamp(0, 30) ?? 3;
    }

    final speaker3dEnabledStr = await db.getSetting(_speaker3dEnabledKey);
    if (speaker3dEnabledStr != null) {
      _speaker3dEnabled = speaker3dEnabledStr == 'true';
    }

    final speaker3dModelPathStr = await db.getSetting(_speaker3dModelPathKey);
    if (speaker3dModelPathStr != null) {
      _speaker3dModelPath = speaker3dModelPathStr.trim();
    }

    final speaker3dModelPathsStr = await db.getSetting(_speaker3dModelPathsKey);
    if (speaker3dModelPathsStr != null && speaker3dModelPathsStr.isNotEmpty) {
      try {
        final decoded = json.decode(speaker3dModelPathsStr);
        if (decoded is List) {
          _speaker3dModelPaths = decoded
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList();
        }
      } catch (_) {}
    }

    if (_speaker3dModelPath.isNotEmpty &&
        !_speaker3dModelPaths.contains(_speaker3dModelPath)) {
      _speaker3dModelPaths = [_speaker3dModelPath, ..._speaker3dModelPaths];
    }
    if (_speaker3dModelPath.isEmpty && _speaker3dModelPaths.isNotEmpty) {
      _speaker3dModelPath = _speaker3dModelPaths.first;
    }
    if (_speaker3dModelPath.isNotEmpty) {
      await _saveSetting(_speaker3dModelPathKey, _speaker3dModelPath);
    }
    await _saveSetting(
      _speaker3dModelPathsKey,
      json.encode(_speaker3dModelPaths),
    );

    final speaker3dMaxSpeakersStr = await db.getSetting(
      _speaker3dMaxSpeakersKey,
    );
    if (speaker3dMaxSpeakersStr != null) {
      _speaker3dMaxSpeakers =
          int.tryParse(speaker3dMaxSpeakersStr)?.clamp(1, 12) ?? 6;
    }

    final speaker3dSingleSpeakerModeStr = await db.getSetting(
      _speaker3dSingleSpeakerModeKey,
    );
    if (speaker3dSingleSpeakerModeStr != null) {
      _speaker3dSingleSpeakerMode = speaker3dSingleSpeakerModeStr == 'true';
    }

    final speaker3dOnlineBaseThresholdStr = await db.getSetting(
      _speaker3dOnlineBaseThresholdKey,
    );
    if (speaker3dOnlineBaseThresholdStr != null) {
      _speaker3dOnlineBaseThreshold =
          (double.tryParse(speaker3dOnlineBaseThresholdStr) ??
                  _speaker3dOnlineBaseThreshold)
              .clamp(0.5, 0.95)
              .toDouble();
    }

    final speaker3dTop1Top2MarginStr = await db.getSetting(
      _speaker3dTop1Top2MarginKey,
    );
    if (speaker3dTop1Top2MarginStr != null) {
      _speaker3dTop1Top2Margin =
          (double.tryParse(speaker3dTop1Top2MarginStr) ??
                  _speaker3dTop1Top2Margin)
              .clamp(0.0, 0.20)
              .toDouble();
    }

    final speaker3dOfflineMergeThresholdStr = await db.getSetting(
      _speaker3dOfflineMergeThresholdKey,
    );
    if (speaker3dOfflineMergeThresholdStr != null) {
      _speaker3dOfflineMergeThreshold =
          (double.tryParse(speaker3dOfflineMergeThresholdStr) ??
                  _speaker3dOfflineMergeThreshold)
              .clamp(0.5, 0.95)
              .toDouble();
    }

    if (_speaker3dSingleSpeakerMode) {
      _speaker3dMaxSpeakers = 1;
    }

    final speaker3dDownloadSourceModeStr = await db.getSetting(
      _speaker3dDownloadSourceModeKey,
    );
    if (speaker3dDownloadSourceModeStr != null) {
      _speaker3dDownloadSourceMode = _normalizeSpeaker3dDownloadSourceMode(
        speaker3dDownloadSourceModeStr,
      );
    }

    // 加载纠错 prompt
    try {
      _correctionPrompt = await rootBundle.loadString(
        'assets/prompts/correction_prompt.md',
      );
    } catch (_) {}

    await LocalLlmService.setIdleUnloadMinutes(_localLlmIdleUnloadMinutes);

    notifyListeners();
  }

  /// 清理 JSON Map 中的 apiKey 字段（去除旧 ENC: 前缀）。
  Map<String, dynamic> _cleanApiKeyInJson(Map<String, dynamic> jsonMap) {
    final copy = Map<String, dynamic>.from(jsonMap);
    final apiKey = copy['apiKey'];
    if (apiKey is String && apiKey.isNotEmpty) {
      copy['apiKey'] = _resolveApiKey(apiKey);
    }
    return copy;
  }

  Future<void> _loadPresetsFromAssets() async {
    try {
      final raw = await rootBundle.loadString('assets/presets/models.json');
      final jsonMap = json.decode(raw) as Map<String, dynamic>;
      final stt = jsonMap['stt'] as List<dynamic>?;
      final ai = jsonMap['ai'] as List<dynamic>?;
      if (stt != null) {
        final parsed = SttProviderConfig.fromPresetJsonList(stt);
        if (parsed.isNotEmpty) {
          _sttPresets = parsed;
        }
      }
      if (ai != null) {
        final parsed = AiVendorPreset.fromPresetJsonList(ai);
        if (parsed.isNotEmpty) {
          _aiPresets = parsed;
        }
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> setConfig(SttProviderConfig config) async {
    _config = config;
    await _saveSetting(_configKey, json.encode(_config.toJson()));
    notifyListeners();
  }

  /// 选择服务商（从 preset 或 custom 列表中选择）
  Future<void> selectProvider(SttProviderConfig provider) async {
    // 恢复该服务商之前存储的 apiKey
    final savedKey = _apiKeys[provider.name] ?? '';
    _config = provider.copyWith(apiKey: savedKey);
    await _saveSetting(_configKey, json.encode(_config.toJson()));
    notifyListeners();
  }

  /// 设置当前服务商的 API Key
  Future<void> setApiKey(String apiKey) async {
    final normalizedApiKey = apiKey.trim();
    _apiKeys[_config.name] = normalizedApiKey;
    _config = _config.copyWith(apiKey: normalizedApiKey);
    await _saveSetting('api_keys', json.encode(_apiKeys));
    await _saveSetting(_configKey, json.encode(_config.toJson()));
    notifyListeners();
  }

  /// 设置当前服务商的模型
  Future<void> setModel(String model) async {
    _config = _config.copyWith(model: model);
    await _saveSetting(_configKey, json.encode(_config.toJson()));
    notifyListeners();
  }

  Future<void> setHotkey(LogicalKeyboardKey key) async {
    _hotkey = key;
    await _saveSetting(_hotkeyKey, key.keyId.toString());
    notifyListeners();
  }

  Future<void> resetHotkey() async {
    _hotkey = defaultHotkey;
    await AppDatabase.instance.removeSetting(_hotkeyKey);
    notifyListeners();
  }

  Future<void> setMeetingHotkey(
    LogicalKeyboardKey key, {
    int? modifiers,
  }) async {
    _meetingHotkey = key;
    _meetingHotkeyModifiers = modifiers ?? _meetingHotkeyModifiers;
    await _saveSetting(_meetingHotkeyKey, key.keyId.toString());
    await _saveSetting(
      _meetingHotkeyModifiersKey,
      _meetingHotkeyModifiers.toString(),
    );
    notifyListeners();
  }

  Future<void> resetMeetingHotkey() async {
    _meetingHotkey = defaultMeetingHotkey;
    _meetingHotkeyModifiers = defaultMeetingHotkeyModifiers;
    await AppDatabase.instance.removeSetting(_meetingHotkeyKey);
    await AppDatabase.instance.removeSetting(_meetingHotkeyModifiersKey);
    notifyListeners();
  }

  static bool isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  static int meetingModifiersFromPressedKeys(Set<LogicalKeyboardKey> pressed) {
    var value = 0;
    if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.control)) {
      value |= meetingHotkeyModifierCtrl;
    }
    if (pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight) ||
        pressed.contains(LogicalKeyboardKey.alt)) {
      value |= meetingHotkeyModifierAlt;
    }
    if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight) ||
        pressed.contains(LogicalKeyboardKey.shift)) {
      value |= meetingHotkeyModifierShift;
    }
    if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.meta)) {
      value |= meetingHotkeyModifierMeta;
    }
    return value;
  }

  static String meetingModifierLabel(int modifiers) {
    final parts = <String>[];
    if ((modifiers & meetingHotkeyModifierCtrl) != 0) {
      parts.add('Ctrl');
    }
    if ((modifiers & meetingHotkeyModifierAlt) != 0) {
      parts.add('Alt');
    }
    if ((modifiers & meetingHotkeyModifierShift) != 0) {
      parts.add('Shift');
    }
    if ((modifiers & meetingHotkeyModifierMeta) != 0) {
      parts.add(defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd' : 'Win');
    }
    return parts.join('+');
  }

  /// 设置激活模式
  Future<void> setActivationMode(ActivationMode mode) async {
    _activationMode = mode;
    await _saveSetting(_activationModeKey, mode.index.toString());
    notifyListeners();
  }

  Future<void> setAiEnhanceEnabled(bool enabled) async {
    _aiEnhanceEnabled = enabled;
    await _saveSetting(_aiEnhanceEnabledKey, enabled.toString());
    notifyListeners();
  }

  Future<void> setAiEnhanceUseCustomPrompt(bool enabled) async {
    _aiEnhanceUseCustomPrompt = enabled;
    await _saveSetting(_aiEnhanceUseCustomPromptKey, enabled.toString());
    notifyListeners();
  }

  Future<void> setMinRecordingSeconds(int seconds) async {
    _minRecordingSeconds = seconds.clamp(1, 30);
    await _saveSetting(
      _minRecordingSecondsKey,
      _minRecordingSeconds.toString(),
    );
    notifyListeners();
  }

  Future<void> setAiEnhanceConfig(AiEnhanceConfig config) async {
    _aiEnhanceConfig = config;
    await _saveSetting(
      _aiEnhanceConfigKey,
      json.encode(_aiEnhanceConfig.toJson()),
    );
    notifyListeners();
  }

  Future<void> setAiEnhanceBaseUrl(String baseUrl) async {
    await setAiEnhanceConfig(_aiEnhanceConfig.copyWith(baseUrl: baseUrl));
  }

  Future<void> setAiEnhanceApiKey(String apiKey) async {
    await setAiEnhanceConfig(_aiEnhanceConfig.copyWith(apiKey: apiKey));
  }

  Future<void> setAiEnhanceModel(String model) async {
    await setAiEnhanceConfig(_aiEnhanceConfig.copyWith(model: model));
  }

  Future<void> setAiEnhancePrompt(String prompt) async {
    await setAiEnhanceConfig(_aiEnhanceConfig.copyWith(prompt: prompt));
  }

  Future<void> setAiEnhanceAgentName(String agentName) async {
    await setAiEnhanceConfig(_aiEnhanceConfig.copyWith(agentName: agentName));
  }

  Future<void> setAiEnhanceDefaultModel(String baseUrl, String model) async {
    _aiEnhanceDefaultModels[baseUrl] = model;
    await _saveSetting(
      _aiEnhanceDefaultModelsKey,
      json.encode(_aiEnhanceDefaultModels),
    );
    notifyListeners();
  }

  // ===== 文本模型条目管理 =====

  Future<void> _saveAiModelEntries() async {
    await _saveSetting(
      _aiModelEntriesKey,
      json.encode(_aiModelEntries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> addAiModelEntry(AiModelEntry entry) async {
    // 如果是第一个条目，自动启用
    final shouldEnable = _aiModelEntries.isEmpty;
    final newEntry = shouldEnable ? entry.copyWith(enabled: true) : entry;
    if (shouldEnable) {
      // 禁用其他
      _aiModelEntries = _aiModelEntries
          .map((e) => e.copyWith(enabled: false))
          .toList();
    }
    _aiModelEntries.add(newEntry);
    await _saveAiModelEntries();
    _syncAiConfigFromActiveEntry();
    notifyListeners();
  }

  Future<void> removeAiModelEntry(String id) async {
    _aiModelEntries.removeWhere((e) => e.id == id);
    await _saveAiModelEntries();
    _syncAiConfigFromActiveEntry();
    notifyListeners();
  }

  Future<void> enableAiModelEntry(String id) async {
    _aiModelEntries = _aiModelEntries.map((e) {
      return e.copyWith(enabled: e.id == id);
    }).toList();
    await _saveAiModelEntries();
    _syncAiConfigFromActiveEntry();
    notifyListeners();
  }

  Future<void> updateAiModelEntry(AiModelEntry updated) async {
    _aiModelEntries = _aiModelEntries.map((e) {
      return e.id == updated.id ? updated.copyWith(enabled: e.enabled) : e;
    }).toList();
    await _saveAiModelEntries();
    _syncAiConfigFromActiveEntry();
    notifyListeners();
  }

  void _syncAiConfigFromActiveEntry() {
    final active = activeAiModelEntry;
    if (active != null) {
      // 本地模型：baseUrl 和 apiKey 保持为空，
      // AiEnhanceService 会自动检测并使用 LocalLlmService.localBaseUrl
      _aiEnhanceConfig = _aiEnhanceConfig.copyWith(
        baseUrl: active.baseUrl,
        apiKey: active.apiKey,
        model: active.model,
      );
      _saveSetting(_aiEnhanceConfigKey, json.encode(_aiEnhanceConfig.toJson()));
    }
  }

  // ===== 语音模型条目管理 =====

  Future<void> _saveSttModelEntries() async {
    await _saveSetting(
      _sttModelEntriesKey,
      json.encode(_sttModelEntries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> addSttModelEntry(SttModelEntry entry) async {
    // 如果是第一个条目，自动启用
    final shouldEnable = _sttModelEntries.isEmpty;
    final newEntry = shouldEnable ? entry.copyWith(enabled: true) : entry;
    if (shouldEnable) {
      // 禁用其他
      _sttModelEntries = _sttModelEntries
          .map((e) => e.copyWith(enabled: false))
          .toList();
    }
    _sttModelEntries.add(newEntry);
    await _saveSttModelEntries();
    _syncSttConfigFromActiveEntry();
    notifyListeners();
  }

  Future<void> removeSttModelEntry(String id) async {
    _sttModelEntries.removeWhere((e) => e.id == id);
    await _saveSttModelEntries();
    _syncSttConfigFromActiveEntry();
    notifyListeners();
  }

  Future<void> enableSttModelEntry(String id) async {
    _sttModelEntries = _sttModelEntries.map((e) {
      return e.copyWith(enabled: e.id == id);
    }).toList();
    await _saveSttModelEntries();
    _syncSttConfigFromActiveEntry();
    notifyListeners();
  }

  Future<void> updateSttModelEntry(SttModelEntry updated) async {
    _sttModelEntries = _sttModelEntries.map((e) {
      return e.id == updated.id ? updated.copyWith(enabled: e.enabled) : e;
    }).toList();
    await _saveSttModelEntries();
    _syncSttConfigFromActiveEntry();
    notifyListeners();
  }

  void _syncSttConfigFromActiveEntry() {
    final active = activeSttModelEntry;
    if (active != null) {
      // 根据 vendorName + 模型文件名判断 provider type
      SttProviderType type;
      if (active.vendorName == 'Local Model' ||
          active.vendorName == '本地模型' ||
          active.vendorName == '本地 whisper.cpp' ||
          active.vendorName == 'whisper.cpp' ||
          active.vendorName == 'SenseVoice' ||
          active.vendorName == 'sensevoice' ||
          active.vendorName == '本地 SenseVoice') {
        // 通过模型文件名区分 SenseVoice 和 Whisper
        type = SttProviderConfig.isSenseVoiceModel(active.model)
            ? SttProviderType.senseVoice
            : SttProviderType.whisperCpp;
      } else {
        type = SttProviderType.cloud;
      }
      _config = _config.copyWith(
        type: type,
        name: active.vendorName,
        baseUrl: active.baseUrl,
        apiKey: active.apiKey,
        model: active.model,
      );
      _saveSetting(_configKey, json.encode(_config.toJson()));
    }
  }

  Future<void> addCustomProvider(SttProviderConfig provider) async {
    _customProviders.add(provider);
    await _saveSetting(
      'custom_providers',
      json.encode(_customProviders.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> removeCustomProvider(int index) async {
    _customProviders.removeAt(index);
    await _saveSetting(
      'custom_providers',
      json.encode(_customProviders.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  /// 获取快捷键的显示名称
  String get hotkeyLabel {
    return _hotkey.keyLabel.isNotEmpty
        ? _hotkey.keyLabel
        : _hotkey.debugName ?? 'Unknown';
  }

  /// 获取会议快捷键的显示名称
  String get meetingHotkeyLabel {
    final keyLabel = _meetingHotkey.keyLabel.isNotEmpty
        ? _meetingHotkey.keyLabel
        : _meetingHotkey.debugName ?? 'Unknown';
    if (_meetingHotkeyModifiers == 0) {
      return keyLabel;
    }
    final modifierLabel = meetingModifierLabel(_meetingHotkeyModifiers);
    if (modifierLabel.isEmpty) {
      return keyLabel;
    }
    return '$modifierLabel+$keyLabel';
  }

  /// 设置语言
  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    await _saveSetting(_localeKey, locale.languageCode);
    notifyListeners();
  }

  Future<void> setNetworkProxyMode(NetworkProxyMode mode) async {
    _networkProxyMode = mode;
    NetworkClientService.setProxyMode(mode);
    await _saveSetting(_networkProxyModeKey, mode.storageValue);
    notifyListeners();
  }

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _saveSetting(_themeModeKey, value);
    notifyListeners();
  }

  // ===== VAD 设置 =====

  Future<void> setVadEnabled(bool enabled) async {
    _vadEnabled = enabled;
    await _saveSetting(_vadEnabledKey, enabled.toString());
    notifyListeners();
  }

  Future<void> setVadSilenceThreshold(double threshold) async {
    _vadSilenceThreshold = threshold.clamp(0.01, 0.3);
    await _saveSetting(
      _vadSilenceThresholdKey,
      _vadSilenceThreshold.toString(),
    );
    notifyListeners();
  }

  Future<void> setVadSilenceDuration(int seconds) async {
    _vadSilenceDurationSeconds = seconds.clamp(1, 10);
    await _saveSetting(
      _vadSilenceDurationKey,
      _vadSilenceDurationSeconds.toString(),
    );
    notifyListeners();
  }

  // ===== Prompt 模板管理 =====

  Future<void> _savePromptTemplates() async {
    await _saveSetting(
      _promptTemplatesKey,
      json.encode(_promptTemplates.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<PromptTemplate>> _loadBuiltinPromptTemplates() async {
    final now = DateTime.now();
    final templates = <PromptTemplate>[];

    for (final def in PromptTemplate.builtinDefinitions) {
      String content = '';
      try {
        content = await rootBundle.loadString(def.assetPath);
      } catch (_) {}

      if (content.trim().isEmpty && def.id == PromptTemplate.defaultBuiltinId) {
        content = _aiEnhanceDefaultPrompt;
      }

      templates.add(
        PromptTemplate(
          id: def.id,
          name: def.name,
          summary: def.summary,
          content: content,
          isBuiltin: true,
          createdAt: now,
        ),
      );
    }

    return templates;
  }

  Future<void> addPromptTemplate(PromptTemplate template) async {
    _promptTemplates.add(template);
    await _savePromptTemplates();
    notifyListeners();
  }

  Future<void> updatePromptTemplate(PromptTemplate updated) async {
    _promptTemplates = _promptTemplates.map((t) {
      return t.id == updated.id ? updated : t;
    }).toList();
    await _savePromptTemplates();
    notifyListeners();
  }

  Future<void> deletePromptTemplate(String id) async {
    _promptTemplates.removeWhere((t) => t.id == id && !t.isBuiltin);
    _activePromptTemplateId = _resolvedActivePromptTemplateId(
      _activePromptTemplateId,
    );
    await _savePromptTemplates();
    await _saveSetting(
      _activePromptTemplateIdKey,
      _activePromptTemplateId ?? PromptTemplate.defaultBuiltinId,
    );
    notifyListeners();
  }

  Future<void> setActivePromptTemplate(String? id) async {
    _activePromptTemplateId = _resolvedActivePromptTemplateId(id);
    await _saveSetting(
      _activePromptTemplateIdKey,
      _activePromptTemplateId ?? PromptTemplate.defaultBuiltinId,
    );
    notifyListeners();
  }

  String _resolvedActivePromptTemplateId(String? preferredId) {
    final defaultId = PromptTemplate.defaultBuiltinId;
    final defaultExists = _promptTemplates.any((t) => t.id == defaultId);
    final fallbackId = defaultExists
        ? defaultId
        : (_promptTemplates.isNotEmpty ? _promptTemplates.first.id : defaultId);
    final targetId = (preferredId != null && preferredId.trim().isNotEmpty)
        ? preferredId.trim()
        : fallbackId;
    final exists = _promptTemplates.any((t) => t.id == targetId);
    return exists ? targetId : fallbackId;
  }

  // ===== 场景模式 =====

  Future<void> setSceneMode(SceneMode mode) async {
    _sceneMode = mode;
    await _saveSetting(_sceneModeKey, mode.name);
    notifyListeners();
  }

  // ===== 词典管理 =====

  Future<void> _saveDictionaryEntries() async {
    await _saveSetting(
      _dictionaryEntriesKey,
      json.encode(_dictionaryEntries.map((e) => e.toJson()).toList()),
    );
  }

  /// 重建拼音索引（词典变更后调用）
  void _rebuildPinyinIndex() {
    _pinyinMatcher.buildIndex(_dictionaryEntries);
  }

  Future<void> addDictionaryEntry(DictionaryEntry entry) async {
    _dictionaryEntries.add(entry);
    await _saveDictionaryEntries();
    _rebuildPinyinIndex();
    notifyListeners();
  }

  Future<void> updateDictionaryEntry(DictionaryEntry updated) async {
    _dictionaryEntries = _dictionaryEntries.map((e) {
      return e.id == updated.id ? updated : e;
    }).toList();
    await _saveDictionaryEntries();
    _rebuildPinyinIndex();
    notifyListeners();
  }

  Future<void> deleteDictionaryEntry(String id) async {
    _dictionaryEntries.removeWhere((e) => e.id == id);
    await _saveDictionaryEntries();
    _rebuildPinyinIndex();
    notifyListeners();
  }

  Future<void> toggleDictionaryEntry(String id, bool enabled) async {
    _dictionaryEntries = _dictionaryEntries.map((e) {
      return e.id == id ? e.copyWith(enabled: enabled) : e;
    }).toList();
    await _saveDictionaryEntries();
    _rebuildPinyinIndex();
    notifyListeners();
  }

  String exportDictionaryAsCsv() {
    final rows = <List<dynamic>>[
      ['pinyinPattern', 'corrected', 'enabled', 'category', 'original'],
      ..._dictionaryEntries.map(
        (entry) => [
          entry.pinyinPattern ?? entry.pinyinNormalized,
          entry.corrected ?? '',
          entry.enabled ? 'true' : 'false',
          entry.category ?? '',
          entry.original,
        ],
      ),
    ];
    return const ListToCsvConverter().convert(rows);
  }

  Future<DictionaryCsvImportResult> importDictionaryFromCsv(
    String csvContent, {
    bool replaceExisting = false,
  }) async {
    final text = csvContent.trim();
    if (text.isEmpty) {
      return const DictionaryCsvImportResult(
        totalRows: 0,
        importedRows: 0,
        skippedRows: 0,
      );
    }

    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(csvContent);
    if (rows.isEmpty) {
      return const DictionaryCsvImportResult(
        totalRows: 0,
        importedRows: 0,
        skippedRows: 0,
      );
    }

    final header = rows.first;
    final headerMap = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      headerMap[_normalizeCsvHeader(_csvCellToString(header[i]))] = i;
    }

    int? indexFor(List<String> aliases) {
      for (final alias in aliases) {
        final idx = headerMap[_normalizeCsvHeader(alias)];
        if (idx != null) return idx;
      }
      return null;
    }

    final originalIndex = indexFor(['original', 'originalword', '原始词']);
    final pinyinPatternIndex = indexFor([
      'pinyinpattern',
      'pinyin_pattern',
      '拼音规则',
      '拼音',
      'pinyinoverride',
      '自定义拼音',
    ]);
    if (pinyinPatternIndex == null) {
      throw const FormatException('Missing required column: pinyinPattern');
    }
    final correctedIndex = indexFor(['corrected', 'correctto', '纠正为']);
    final categoryIndex = indexFor(['category', '分类']);
    final enabledIndex = indexFor(['enabled', '启用']);

    final nextEntries = replaceExisting
        ? <DictionaryEntry>[]
        : List<DictionaryEntry>.from(_dictionaryEntries);
    final dedup = <String>{
      for (final item in nextEntries)
        _dictionaryDedupKey(
          item.original,
          item.corrected,
          item.category,
          item.pinyinPattern,
        ),
    };

    var totalRows = 0;
    var importedRows = 0;
    var skippedRows = 0;

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowIsEmpty = row.every(
        (cell) => _csvCellToString(cell).trim().isEmpty,
      );
      if (rowIsEmpty) continue;

      totalRows += 1;

      final pinyinPattern = _csvValueAt(row, pinyinPatternIndex).trim();
      final correctedRaw = correctedIndex == null
          ? ''
          : _csvValueAt(row, correctedIndex).trim();
      if (pinyinPattern.isEmpty || correctedRaw.isEmpty) {
        skippedRows += 1;
        continue;
      }

      final corrected = correctedRaw.isEmpty ? null : correctedRaw;
      final original = originalIndex == null
          ? ''
          : _csvValueAt(row, originalIndex).trim();

      final categoryRaw = categoryIndex == null
          ? ''
          : _csvValueAt(row, categoryIndex).trim();
      final category = categoryRaw.isEmpty ? null : categoryRaw;

      final enabled = enabledIndex == null
          ? true
          : _parseCsvEnabled(_csvValueAt(row, enabledIndex));

      final dedupKey = _dictionaryDedupKey(
        original,
        corrected,
        category,
        pinyinPattern,
      );
      if (dedup.contains(dedupKey)) {
        skippedRows += 1;
        continue;
      }

      nextEntries.add(
        DictionaryEntry.create(
          original: original,
          corrected: corrected,
          category: category,
          enabled: enabled,
          pinyinPattern: pinyinPattern,
        ),
      );
      dedup.add(dedupKey);
      importedRows += 1;
    }

    if (replaceExisting || importedRows > 0) {
      _dictionaryEntries = nextEntries;
      await _saveDictionaryEntries();
      _rebuildPinyinIndex();
      notifyListeners();
    }

    return DictionaryCsvImportResult(
      totalRows: totalRows,
      importedRows: importedRows,
      skippedRows: skippedRows,
    );
  }

  String _csvCellToString(dynamic value) {
    if (value == null) return '';
    return value.toString().replaceFirst('\uFEFF', '');
  }

  String _csvValueAt(List<dynamic> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return _csvCellToString(row[index]);
  }

  String _normalizeCsvHeader(String value) {
    return value
        .replaceFirst('\uFEFF', '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-]'), '');
  }

  bool _parseCsvEnabled(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    if ({
      '1',
      'true',
      'yes',
      'y',
      'on',
      '是',
      '启用',
      '启用中',
    }.contains(normalized)) {
      return true;
    }
    if ({
      '0',
      'false',
      'no',
      'n',
      'off',
      '否',
      '禁用',
      '已禁用',
    }.contains(normalized)) {
      return false;
    }
    return true;
  }

  String _dictionaryDedupKey(
    String original,
    String? corrected,
    String? category,
    String? pinyinPattern,
  ) {
    final originalPart = original.trim().toLowerCase();
    final correctedPart = (corrected ?? '').trim().toLowerCase();
    final categoryPart = (category ?? '').trim().toLowerCase();
    final pinyinPart = (pinyinPattern ?? '').trim().toLowerCase();
    return '$originalPart|$correctedPart|$categoryPart|$pinyinPart';
  }

  /// 获取所有不重复的词典分类
  List<String> get dictionaryCategories {
    final cats = <String>{};
    for (final e in _dictionaryEntries) {
      if (e.category != null && e.category!.isNotEmpty) {
        cats.add(e.category!);
      }
    }
    return cats.toList()..sort();
  }

  /// 生成结构化的词典提示词后缀，注入到 AI prompt 中。
  ///
  /// 格式示例：
  /// 【词典纠正规则】
  /// 以下是需要遵守的文字纠正和术语规范：
  /// - 纠正规则：遇到"原始词"时，应替换为"纠正词"
  /// - 保留规则：遇到"术语"时，保持原样不要改写
  String get dictionaryWordsForPrompt {
    final active = _dictionaryEntries.where((e) => e.enabled).toList();
    if (active.isEmpty) return '';

    final corrections = active
        .where((e) => e.type == DictionaryEntryType.correction)
        .toList();
    final preserves = active
        .where((e) => e.type == DictionaryEntryType.preserve)
        .toList();

    final buf = StringBuffer('\n\n【词典纠正规则】\n以下是需要遵守的文字纠正和术语规范：');

    if (corrections.isNotEmpty) {
      buf.writeln();
      for (final e in corrections) {
        final cat = (e.category != null && e.category!.isNotEmpty)
            ? '[${e.category}] '
            : '';
        final original = e.original.trim();
        final corrected = (e.corrected ?? '').trim();
        final target = _correctionTargetText(e);
        final pinyinPattern = e.pinyinPattern?.trim() ?? '';
        if (original.isNotEmpty) {
          buf.writeln('- $cat遇到"$original"时，应替换为"$target"');
        } else if (pinyinPattern.isNotEmpty) {
          buf.writeln('- $cat遇到发音接近 "$pinyinPattern" 的词时，应替换为"$target"');
        }
        if (_isChineseToLatinAliasEntry(e) && corrected.isNotEmpty) {
          buf.writeln('- $cat遇到"$corrected"时，应替换为"$original"');
        }
      }
    }

    // 收集所有需要保留原样的词：显式 preserve 条目 + correction 条目的纠正后形式
    final preserveWords = <String>{};
    for (final e in preserves) {
      if (e.original.trim().isNotEmpty) {
        preserveWords.add(e.original);
      }
    }
    for (final e in corrections) {
      if (e.corrected != null && e.corrected!.isNotEmpty) {
        preserveWords.add(e.corrected!);
      }
    }

    if (preserveWords.isNotEmpty) {
      buf.writeln();
      for (final word in preserveWords) {
        buf.writeln('- 遇到"$word"时，保持原样不要改写');
      }
    }

    final preservePatterns = preserves
        .map((e) => e.pinyinPattern?.trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet();
    if (preservePatterns.isNotEmpty) {
      buf.writeln();
      for (final pattern in preservePatterns) {
        buf.writeln('- 遇到发音接近 "$pattern" 的词时，保持原样不要改写');
      }
    }

    return buf.toString();
  }

  // ===== 纠错设置 =====

  Future<void> setCorrectionEnabled(bool enabled) async {
    _correctionEnabled = enabled;
    await _saveSetting(_correctionEnabledKey, enabled.toString());
    notifyListeners();
  }

  Future<void> setRetrospectiveCorrectionEnabled(bool enabled) async {
    _retrospectiveCorrectionEnabled = enabled;
    await _saveSetting(_retrospectiveCorrectionEnabledKey, enabled.toString());
    notifyListeners();
  }

  Future<void> setLocalLlmIdleUnloadMinutes(int minutes) async {
    _localLlmIdleUnloadMinutes = minutes.clamp(0, 30);
    await _saveSetting(
      _localLlmIdleUnloadMinutesKey,
      _localLlmIdleUnloadMinutes.toString(),
    );
    await LocalLlmService.setIdleUnloadMinutes(_localLlmIdleUnloadMinutes);
    notifyListeners();
  }

  Future<void> setSpeaker3dEnabled(bool enabled) async {
    _speaker3dEnabled = enabled;
    await _saveSetting(_speaker3dEnabledKey, enabled.toString());
    notifyListeners();
  }

  Future<void> setSpeaker3dModelPath(String path) async {
    await addSpeaker3dModelPath(path, setActive: true);
  }

  Future<void> addSpeaker3dModelPath(
    String path, {
    bool setActive = true,
  }) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;

    _speaker3dModelPaths = [
      normalized,
      ..._speaker3dModelPaths.where((e) => e != normalized),
    ];
    if (setActive) {
      _speaker3dModelPath = normalized;
      await _saveSetting(_speaker3dModelPathKey, _speaker3dModelPath);
    }
    await _saveSetting(
      _speaker3dModelPathsKey,
      json.encode(_speaker3dModelPaths),
    );
    notifyListeners();
  }

  Future<void> setActiveSpeaker3dModelPath(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty || !_speaker3dModelPaths.contains(normalized)) {
      return;
    }
    _speaker3dModelPath = normalized;
    await _saveSetting(_speaker3dModelPathKey, _speaker3dModelPath);
    notifyListeners();
  }

  Future<void> removeSpeaker3dModelPath(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;

    _speaker3dModelPaths = _speaker3dModelPaths
        .where((e) => e != normalized)
        .toList();
    if (_speaker3dModelPath == normalized) {
      _speaker3dModelPath = _speaker3dModelPaths.isNotEmpty
          ? _speaker3dModelPaths.first
          : '';
      await _saveSetting(_speaker3dModelPathKey, _speaker3dModelPath);
    }
    await _saveSetting(
      _speaker3dModelPathsKey,
      json.encode(_speaker3dModelPaths),
    );
    notifyListeners();
  }

  Future<void> setSpeaker3dMaxSpeakers(int value) async {
    _speaker3dMaxSpeakers = value.clamp(1, 12);
    if (_speaker3dMaxSpeakers > 1 && _speaker3dSingleSpeakerMode) {
      _speaker3dSingleSpeakerMode = false;
      await _saveSetting(_speaker3dSingleSpeakerModeKey, 'false');
    }
    await _saveSetting(
      _speaker3dMaxSpeakersKey,
      _speaker3dMaxSpeakers.toString(),
    );
    notifyListeners();
  }

  Future<void> setSpeaker3dSingleSpeakerMode(bool enabled) async {
    _speaker3dSingleSpeakerMode = enabled;
    await _saveSetting(_speaker3dSingleSpeakerModeKey, enabled.toString());
    if (enabled) {
      _speaker3dMaxSpeakers = 1;
      await _saveSetting(_speaker3dMaxSpeakersKey, '1');
    }
    notifyListeners();
  }

  Future<void> setSpeaker3dOnlineBaseThreshold(double value) async {
    _speaker3dOnlineBaseThreshold = value.clamp(0.5, 0.95).toDouble();
    await _saveSetting(
      _speaker3dOnlineBaseThresholdKey,
      _speaker3dOnlineBaseThreshold.toStringAsFixed(2),
    );
    notifyListeners();
  }

  Future<void> setSpeaker3dTop1Top2Margin(double value) async {
    _speaker3dTop1Top2Margin = value.clamp(0.0, 0.20).toDouble();
    await _saveSetting(
      _speaker3dTop1Top2MarginKey,
      _speaker3dTop1Top2Margin.toStringAsFixed(2),
    );
    notifyListeners();
  }

  Future<void> setSpeaker3dOfflineMergeThreshold(double value) async {
    _speaker3dOfflineMergeThreshold = value.clamp(0.5, 0.95).toDouble();
    await _saveSetting(
      _speaker3dOfflineMergeThresholdKey,
      _speaker3dOfflineMergeThreshold.toStringAsFixed(2),
    );
    notifyListeners();
  }

  Future<void> applySpeaker3dPreset(String preset) async {
    switch (preset) {
      case speaker3dPresetConsistency:
        _speaker3dSingleSpeakerMode = false;
        _speaker3dMaxSpeakers = 2;
        _speaker3dOnlineBaseThreshold = 0.72;
        _speaker3dTop1Top2Margin = 0.01;
        _speaker3dOfflineMergeThreshold = 0.72;
        break;
      case speaker3dPresetSeparation:
        _speaker3dSingleSpeakerMode = false;
        _speaker3dMaxSpeakers = 8;
        _speaker3dOnlineBaseThreshold = 0.84;
        _speaker3dTop1Top2Margin = 0.06;
        _speaker3dOfflineMergeThreshold = 0.84;
        break;
      case speaker3dPresetBalanced:
      default:
        _speaker3dSingleSpeakerMode = false;
        _speaker3dMaxSpeakers = 6;
        _speaker3dOnlineBaseThreshold = 0.78;
        _speaker3dTop1Top2Margin = 0.04;
        _speaker3dOfflineMergeThreshold = 0.80;
        break;
    }

    await _saveSetting(
      _speaker3dSingleSpeakerModeKey,
      _speaker3dSingleSpeakerMode.toString(),
    );
    await _saveSetting(
      _speaker3dMaxSpeakersKey,
      _speaker3dMaxSpeakers.toString(),
    );
    await _saveSetting(
      _speaker3dOnlineBaseThresholdKey,
      _speaker3dOnlineBaseThreshold.toStringAsFixed(2),
    );
    await _saveSetting(
      _speaker3dTop1Top2MarginKey,
      _speaker3dTop1Top2Margin.toStringAsFixed(2),
    );
    await _saveSetting(
      _speaker3dOfflineMergeThresholdKey,
      _speaker3dOfflineMergeThreshold.toStringAsFixed(2),
    );
    notifyListeners();
  }

  Future<void> setSpeaker3dDownloadSourceMode(String mode) async {
    _speaker3dDownloadSourceMode = _normalizeSpeaker3dDownloadSourceMode(mode);
    await _saveSetting(
      _speaker3dDownloadSourceModeKey,
      _speaker3dDownloadSourceMode,
    );
    notifyListeners();
  }

  String _normalizeSpeaker3dDownloadSourceMode(String mode) {
    final normalized = mode.trim().toLowerCase();
    switch (normalized) {
      case _speaker3dDownloadSourceModeDirect:
      case _speaker3dDownloadSourceModeMirror:
      case _speaker3dDownloadSourceModeAuto:
        return normalized;
      default:
        return _speaker3dDownloadSourceModeAuto;
    }
  }

  bool _containsChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }

  bool _isChineseToLatinAliasEntry(DictionaryEntry entry) {
    final original = entry.original.trim();
    final corrected = (entry.corrected ?? '').trim();
    return entry.type == DictionaryEntryType.correction &&
        corrected.isNotEmpty &&
        _containsChinese(original) &&
        !_containsChinese(corrected);
  }

  String _correctionTargetText(DictionaryEntry entry) {
    final corrected = (entry.corrected ?? '').trim();
    if (corrected.isEmpty) {
      return entry.original;
    }
    if (_isChineseToLatinAliasEntry(entry)) {
      return entry.original;
    }
    return corrected;
  }

  /// 纠错是否实际生效（总开关已开 + 词典非空）
  bool get correctionEffective =>
      _correctionEnabled && _dictionaryEntries.any((e) => e.enabled);

  // ===== 通用持久化辅助 =====

  Future<void> _saveSetting(String key, String value) async {
    await AppDatabase.instance.setSetting(key, value);
  }
}
