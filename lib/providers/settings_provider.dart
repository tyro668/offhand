import 'dart:async';
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
import '../models/dictation_term_pending_candidate.dart';
import '../models/entity_alias.dart';
import '../models/entity_evidence.dart';
import '../models/entity_memory.dart';
import '../models/entity_relation.dart';
import '../models/imported_reference_term.dart';
import '../models/markdown_term_import_result.dart';
import '../models/prompt_template.dart';
import '../models/provider_config.dart';
import '../models/scene_mode.dart';
import '../models/stt_model_entry.dart';
import '../models/term_context_entry.dart';
import '../database/app_database.dart';
import '../services/network_client_service.dart';
import '../services/pinyin_matcher.dart';
import '../services/audio_recorder.dart';
import '../services/local_llm_service.dart';
import '../services/entity_dictionary_bridge.dart';
import '../services/entity_learning_service.dart';
import '../services/markdown_term_import_service.dart';

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
  static const _defaultLocalAsrModelId = 'sense-voice-zh-en';
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
  static const _preferBuiltInMicrophoneKey = 'prefer_built_in_microphone';
  static const _vadEnabledKey = 'vad_enabled';
  static const _vadSilenceThresholdKey = 'vad_silence_threshold';
  static const _vadSilenceDurationKey = 'vad_silence_duration';
  static const _promptTemplatesKey = 'prompt_templates';
  static const _activePromptTemplateIdKey = 'active_prompt_template_id';
  static const _sceneModeKey = 'scene_mode';
  static const _dictionaryEntriesKey = 'dictionary_entries';
  static const _dictationTermPendingCandidatesKey =
      'dictation_term_pending_candidates_v1';
  static const _termContextEntriesKey = 'term_context_entries_v1';
  static const _entityMemoriesKey = 'entity_memories_v1';
  static const _entityAliasesKey = 'entity_aliases_v1';
  static const _entityRelationsKey = 'entity_relations_v1';
  static const _entityEvidencesKey = 'entity_evidences_v1';
  static const _importedReferenceTermsKey = 'imported_reference_terms_v1';
  static const _correctionEnabledKey = 'correction_enabled';
  static const _retrospectiveCorrectionEnabledKey =
      'retrospective_correction_enabled';
  static const _historyContextEnhancementEnabledKey =
      'history_context_enhancement_enabled';
  static const _localLlmIdleUnloadMinutesKey = 'local_llm_idle_unload_minutes';

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
  bool _preferBuiltInMicrophone = true;

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
  List<DictationTermPendingCandidate> _dictationTermPendingCandidates = [];
  List<TermContextEntry> _termContextEntries = [];
  List<EntityMemory> _entityMemories = [];
  List<EntityAlias> _entityAliases = [];
  List<EntityRelation> _entityRelations = [];
  List<EntityEvidence> _entityEvidences = [];

  // Correction settings
  bool _correctionEnabled = true;
  bool _retrospectiveCorrectionEnabled = false;
  bool _historyContextEnhancementEnabled = true;
  String _correctionPrompt = '';
  int _localLlmIdleUnloadMinutes = 3;
  final PinyinMatcher _pinyinMatcher = PinyinMatcher(
    enableSingleCharFuzzy: _correctionEnableSingleCharFuzzy,
  );
  static const MarkdownTermImportService _markdownTermImportService =
      MarkdownTermImportService();
  static const EntityLearningService _entityLearningService =
      EntityLearningService();
  static const EntityDictionaryBridge _entityDictionaryBridge =
      EntityDictionaryBridge();

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
  bool get preferBuiltInMicrophone => _preferBuiltInMicrophone;

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
  List<DictationTermPendingCandidate> get dictationTermPendingCandidates =>
      List.unmodifiable(_dictationTermPendingCandidates);
  List<TermContextEntry> get termContextEntries =>
      List.unmodifiable(_termContextEntries);
  List<EntityMemory> get entityMemories => List.unmodifiable(_entityMemories);
  List<EntityAlias> get entityAliases => List.unmodifiable(_entityAliases);
  List<EntityRelation> get entityRelations =>
      List.unmodifiable(_entityRelations);
  List<EntityEvidence> get entityEvidences =>
      List.unmodifiable(_entityEvidences);

  // Correction getters
  bool get correctionEnabled => _correctionEnabled;
  bool get retrospectiveCorrectionEnabled => _retrospectiveCorrectionEnabled;
  bool get historyContextEnhancementEnabled =>
      _historyContextEnhancementEnabled;
  String get correctionPrompt => _correctionPrompt;
  int get localLlmIdleUnloadMinutes => _localLlmIdleUnloadMinutes;
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
      _config = _normalizeSttConfig(_config);
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
            .map(
              (e) => _normalizeSttModelEntry(
                SttModelEntry.fromJson(_cleanApiKeyInJson(e)),
              ),
            )
            .toList();
        await _saveSttModelEntries();
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

    final preferBuiltInMicrophoneStr = await db.getSetting(
      _preferBuiltInMicrophoneKey,
    );
    if (preferBuiltInMicrophoneStr != null) {
      _preferBuiltInMicrophone = preferBuiltInMicrophoneStr == 'true';
    }
    AudioRecorderService.setPreferBuiltInMicrophone(_preferBuiltInMicrophone);

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

    final pendingCandidatesJson = await db.getSetting(
      _dictationTermPendingCandidatesKey,
    );
    if (pendingCandidatesJson != null) {
      try {
        final list = json.decode(pendingCandidatesJson) as List<dynamic>;
        _dictationTermPendingCandidates =
            list
                .whereType<Map<String, dynamic>>()
                .map((e) => DictationTermPendingCandidate.fromJson(e))
                .where(
                  (candidate) =>
                      candidate.original.isNotEmpty &&
                      candidate.corrected.isNotEmpty,
                )
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } catch (_) {}
    }

    final termContextEntriesJson = await db.getSetting(_termContextEntriesKey);
    if (termContextEntriesJson != null) {
      try {
        final list = json.decode(termContextEntriesJson) as List<dynamic>;
        _termContextEntries = list
            .whereType<Map<String, dynamic>>()
            .map((e) => TermContextEntry.fromJson(e))
            .where((entry) => entry.promptTerm.isNotEmpty)
            .toList(growable: false);
      } catch (_) {}
    } else {
      final importedReferenceTermsJson = await db.getSetting(
        _importedReferenceTermsKey,
      );
      if (importedReferenceTermsJson != null) {
        try {
          final list = json.decode(importedReferenceTermsJson) as List<dynamic>;
          _termContextEntries = list
              .whereType<Map<String, dynamic>>()
              .map((e) => ImportedReferenceTerm.fromJson(e))
              .where((term) => term.term.isNotEmpty)
              .map(
                (term) => TermContextEntry.create(
                  term: term.term,
                  canonical: term.term,
                  sourceName: term.sourceName,
                  entryType: TermContextEntryType.reference,
                  confidence: 0.6,
                ).copyWith(createdAt: term.createdAt),
              )
              .toList(growable: false);
          if (_termContextEntries.isNotEmpty) {
            await _saveTermContextEntries();
          }
        } catch (_) {}
      }
    }

    final entityMemoriesJson = await db.getSetting(_entityMemoriesKey);
    if (entityMemoriesJson != null) {
      try {
        final list = json.decode(entityMemoriesJson) as List<dynamic>;
        _entityMemories = list
            .whereType<Map<String, dynamic>>()
            .map(EntityMemory.fromJson)
            .where((item) => item.canonicalName.isNotEmpty)
            .toList(growable: false);
      } catch (_) {}
    }

    final entityAliasesJson = await db.getSetting(_entityAliasesKey);
    if (entityAliasesJson != null) {
      try {
        final list = json.decode(entityAliasesJson) as List<dynamic>;
        _entityAliases = list
            .whereType<Map<String, dynamic>>()
            .map(EntityAlias.fromJson)
            .where(
              (item) => item.entityId.isNotEmpty && item.aliasText.isNotEmpty,
            )
            .toList(growable: false);
      } catch (_) {}
    }

    final entityRelationsJson = await db.getSetting(_entityRelationsKey);
    if (entityRelationsJson != null) {
      try {
        final list = json.decode(entityRelationsJson) as List<dynamic>;
        _entityRelations = list
            .whereType<Map<String, dynamic>>()
            .map(EntityRelation.fromJson)
            .where(
              (item) =>
                  item.sourceEntityId.isNotEmpty &&
                  item.targetEntityId.isNotEmpty &&
                  item.relationType.isNotEmpty,
            )
            .toList(growable: false);
      } catch (_) {}
    }

    final entityEvidencesJson = await db.getSetting(_entityEvidencesKey);
    if (entityEvidencesJson != null) {
      try {
        final list = json.decode(entityEvidencesJson) as List<dynamic>;
        _entityEvidences = list
            .whereType<Map<String, dynamic>>()
            .map(EntityEvidence.fromJson)
            .where((item) => item.entityId.isNotEmpty)
            .toList(growable: false);
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

    final historyContextStr = await db.getSetting(
      _historyContextEnhancementEnabledKey,
    );
    if (historyContextStr != null) {
      _historyContextEnhancementEnabled = historyContextStr == 'true';
    }

    final localLlmIdleUnloadMinutesStr = await db.getSetting(
      _localLlmIdleUnloadMinutesKey,
    );
    if (localLlmIdleUnloadMinutesStr != null) {
      _localLlmIdleUnloadMinutes =
          int.tryParse(localLlmIdleUnloadMinutesStr)?.clamp(0, 30) ?? 3;
    }

    // 加载纠错 prompt
    try {
      _correctionPrompt = await rootBundle.loadString(
        'assets/prompts/correction_prompt.md',
      );
    } catch (_) {}

    await LocalLlmService.setIdleUnloadMinutes(_localLlmIdleUnloadMinutes);
    await _cleanupRemovedSpeakerSettings();

    notifyListeners();
  }

  Future<void> _cleanupRemovedSpeakerSettings() async {
    const keys = [
      'speaker_3d_enabled',
      'speaker_3d_model_path',
      'speaker_3d_model_paths',
      'speaker_3d_max_speakers',
      'speaker_3d_single_speaker_mode',
      'speaker_3d_online_base_threshold',
      'speaker_3d_top1_top2_margin',
      'speaker_3d_offline_merge_threshold',
      'speaker_3d_download_source_mode',
    ];
    for (final key in keys) {
      await AppDatabase.instance.removeSetting(key);
    }
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
      final normalized = _normalizeSttModelEntry(active);
      if (normalized.vendorName != active.vendorName ||
          normalized.baseUrl != active.baseUrl ||
          normalized.model != active.model ||
          normalized.apiKey != active.apiKey) {
        _sttModelEntries = _sttModelEntries.map((e) {
          return e.id == active.id
              ? normalized.copyWith(enabled: e.enabled)
              : e;
        }).toList();
        unawaited(_saveSttModelEntries());
      }

      // 根据 vendorName + 模型文件名判断 provider type
      SttProviderType type;
      if (_isLocalSttVendorName(normalized.vendorName)) {
        type = SttProviderType.senseVoice;
      } else {
        type = SttProviderType.cloud;
      }
      _config = _normalizeSttConfig(
        _config.copyWith(
          type: type,
          name: normalized.vendorName,
          baseUrl: normalized.baseUrl,
          apiKey: normalized.apiKey,
          model: normalized.model,
        ),
      );
      _saveSetting(_configKey, json.encode(_config.toJson()));
    }
  }

  bool _isLocalSttVendorName(String vendorName) {
    return vendorName == 'Local Model' ||
        vendorName == '本地模型' ||
        vendorName == '本地 whisper.cpp' ||
        vendorName == 'whisper.cpp' ||
        vendorName == 'SenseVoice' ||
        vendorName == 'sensevoice' ||
        vendorName == '本地 SenseVoice';
  }

  SttProviderConfig _normalizeSttConfig(SttProviderConfig config) {
    if (config.type != SttProviderType.senseVoice &&
        !_isLocalSttVendorName(config.name)) {
      return config;
    }

    final model = SttProviderConfig.isSenseVoiceModel(config.model)
        ? config.model
        : _defaultLocalAsrModelId;
    return config.copyWith(
      type: SttProviderType.senseVoice,
      name: 'Local Model',
      baseUrl: '',
      apiKey: '',
      model: model,
    );
  }

  SttModelEntry _normalizeSttModelEntry(SttModelEntry entry) {
    if (!_isLocalSttVendorName(entry.vendorName)) {
      return entry;
    }

    final model = SttProviderConfig.isSenseVoiceModel(entry.model)
        ? entry.model
        : _defaultLocalAsrModelId;
    return entry.copyWith(
      vendorName: 'Local Model',
      baseUrl: '',
      apiKey: '',
      model: model,
    );
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

  Future<void> setPreferBuiltInMicrophone(bool enabled) async {
    _preferBuiltInMicrophone = enabled;
    AudioRecorderService.setPreferBuiltInMicrophone(enabled);
    await _saveSetting(_preferBuiltInMicrophoneKey, enabled.toString());
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

  Future<void> _saveDictationTermPendingCandidates() async {
    await _saveSetting(
      _dictationTermPendingCandidatesKey,
      json.encode(
        _dictationTermPendingCandidates.map((e) => e.toJson()).toList(),
      ),
    );
  }

  Future<void> _saveTermContextEntries() async {
    await _saveSetting(
      _termContextEntriesKey,
      json.encode(_termContextEntries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveImportedReferenceTerms() async {
    await _saveSetting(
      _importedReferenceTermsKey,
      json.encode(const <Map<String, dynamic>>[]),
    );
  }

  Future<void> _saveEntityMemories() async {
    await _saveSetting(
      _entityMemoriesKey,
      json.encode(_entityMemories.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveEntityAliases() async {
    await _saveSetting(
      _entityAliasesKey,
      json.encode(_entityAliases.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveEntityRelations() async {
    await _saveSetting(
      _entityRelationsKey,
      json.encode(_entityRelations.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveEntityEvidences() async {
    await _saveSetting(
      _entityEvidencesKey,
      json.encode(_entityEvidences.map((e) => e.toJson()).toList()),
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

  Future<DictationTermPendingCandidate?> addOrMergeTermPendingCandidate({
    required String original,
    required String corrected,
    String? category,
    required double confidence,
    String? sourceHistoryId,
  }) async {
    final normalizedOriginal = original.trim();
    final normalizedCorrected = corrected.trim();
    if (normalizedOriginal.isEmpty || normalizedCorrected.isEmpty) {
      throw ArgumentError('original/corrected must not be empty');
    }

    for (final entry in _dictionaryEntries) {
      if (entry.type == DictionaryEntryType.correction &&
          entry.original.trim().toLowerCase() ==
              normalizedOriginal.toLowerCase() &&
          (entry.corrected ?? '').trim().toLowerCase() ==
              normalizedCorrected.toLowerCase()) {
        return null;
      }
    }

    for (var i = 0; i < _dictationTermPendingCandidates.length; i++) {
      final existing = _dictationTermPendingCandidates[i];
      if (existing.original.toLowerCase() == normalizedOriginal.toLowerCase() &&
          existing.corrected.toLowerCase() ==
              normalizedCorrected.toLowerCase()) {
        final merged = DictationTermPendingCandidate(
          id: existing.id,
          original: existing.original,
          corrected: existing.corrected,
          category: existing.category ?? category?.trim(),
          confidence: confidence > existing.confidence
              ? confidence
              : existing.confidence,
          occurrenceCount: existing.occurrenceCount + 1,
          sourceHistoryId: sourceHistoryId ?? existing.sourceHistoryId,
          createdAt: DateTime.now(),
        );
        _dictationTermPendingCandidates[i] = merged;
        await _saveDictationTermPendingCandidates();
        notifyListeners();
        return merged;
      }
    }

    final created = DictationTermPendingCandidate.create(
      original: normalizedOriginal,
      corrected: normalizedCorrected,
      category: category,
      confidence: confidence,
      sourceHistoryId: sourceHistoryId,
    );
    _dictationTermPendingCandidates = [
      created,
      ..._dictationTermPendingCandidates,
    ];
    await _saveDictationTermPendingCandidates();
    notifyListeners();
    return created;
  }

  Future<DictationTermPendingCandidate?> updateTermPendingCandidate({
    required String id,
    required String original,
    required String corrected,
    String? category,
  }) async {
    final normalizedOriginal = original.trim();
    final normalizedCorrected = corrected.trim();
    if (normalizedOriginal.isEmpty || normalizedCorrected.isEmpty) {
      throw ArgumentError('original/corrected must not be empty');
    }

    final index = _dictationTermPendingCandidates.indexWhere(
      (candidate) => candidate.id == id,
    );
    if (index < 0) return null;

    final current = _dictationTermPendingCandidates[index];

    for (final entry in _dictionaryEntries) {
      if (entry.type == DictionaryEntryType.correction &&
          entry.original.trim().toLowerCase() ==
              normalizedOriginal.toLowerCase() &&
          (entry.corrected ?? '').trim().toLowerCase() ==
              normalizedCorrected.toLowerCase()) {
        _dictationTermPendingCandidates.removeAt(index);
        await _saveDictationTermPendingCandidates();
        notifyListeners();
        return null;
      }
    }

    for (var i = 0; i < _dictationTermPendingCandidates.length; i++) {
      if (i == index) continue;
      final existing = _dictationTermPendingCandidates[i];
      if (existing.original.toLowerCase() == normalizedOriginal.toLowerCase() &&
          existing.corrected.toLowerCase() ==
              normalizedCorrected.toLowerCase()) {
        final merged = existing.copyWith(
          category: existing.category ?? category?.trim() ?? current.category,
          confidence: existing.confidence > current.confidence
              ? existing.confidence
              : current.confidence,
          occurrenceCount: existing.occurrenceCount + current.occurrenceCount,
          sourceHistoryId: current.sourceHistoryId ?? existing.sourceHistoryId,
          createdAt: DateTime.now(),
        );
        _dictationTermPendingCandidates[i] = merged;
        _dictationTermPendingCandidates.removeAt(index);
        await _saveDictationTermPendingCandidates();
        notifyListeners();
        return merged;
      }
    }

    final updated = current.copyWith(
      original: normalizedOriginal,
      corrected: normalizedCorrected,
      category: (category == null || category.trim().isEmpty)
          ? null
          : category.trim(),
      createdAt: DateTime.now(),
    );
    _dictationTermPendingCandidates[index] = updated;
    await _saveDictationTermPendingCandidates();
    notifyListeners();
    return updated;
  }

  Future<DictionaryEntry?> acceptTermPendingCandidate(String id) async {
    DictationTermPendingCandidate? candidate;
    for (final item in _dictationTermPendingCandidates) {
      if (item.id == id) {
        candidate = item;
        break;
      }
    }
    if (candidate == null) return null;

    final entry = await upsertDictionaryCorrectionEntry(
      original: candidate.original,
      corrected: candidate.corrected,
      category: candidate.category,
      source: DictionaryEntrySource.historyEdit,
    );
    _dictationTermPendingCandidates.removeWhere((item) => item.id == id);
    await _saveDictationTermPendingCandidates();
    notifyListeners();
    return entry;
  }

  Future<List<DictionaryEntry>> acceptAllTermPendingCandidates() async {
    if (_dictationTermPendingCandidates.isEmpty) {
      return const [];
    }

    final acceptedEntries = <DictionaryEntry>[];
    final snapshot = List<DictationTermPendingCandidate>.from(
      _dictationTermPendingCandidates,
    );
    for (final candidate in snapshot) {
      final entry = await upsertDictionaryCorrectionEntry(
        original: candidate.original,
        corrected: candidate.corrected,
        category: candidate.category,
        source: DictionaryEntrySource.historyEdit,
      );
      acceptedEntries.add(entry);
    }
    _dictationTermPendingCandidates.clear();
    await _saveDictationTermPendingCandidates();
    notifyListeners();
    return acceptedEntries;
  }

  Future<List<DictionaryEntry>> acceptTermPendingCandidates(
    Iterable<String> ids,
  ) async {
    final targetIds = ids.toSet();
    if (targetIds.isEmpty) {
      return const [];
    }

    final snapshot = _dictationTermPendingCandidates
        .where((candidate) => targetIds.contains(candidate.id))
        .toList(growable: false);
    if (snapshot.isEmpty) {
      return const [];
    }

    final acceptedEntries = <DictionaryEntry>[];
    for (final candidate in snapshot) {
      final entry = await upsertDictionaryCorrectionEntry(
        original: candidate.original,
        corrected: candidate.corrected,
        category: candidate.category,
        source: DictionaryEntrySource.historyEdit,
      );
      acceptedEntries.add(entry);
    }
    _dictationTermPendingCandidates.removeWhere(
      (candidate) => targetIds.contains(candidate.id),
    );
    await _saveDictationTermPendingCandidates();
    notifyListeners();
    return acceptedEntries;
  }

  Future<void> rejectTermPendingCandidate(String id) async {
    final hadCandidate = _dictationTermPendingCandidates.any(
      (item) => item.id == id,
    );
    if (!hadCandidate) return;
    _dictationTermPendingCandidates.removeWhere((item) => item.id == id);
    await _saveDictationTermPendingCandidates();
    notifyListeners();
  }

  Future<void> rejectAllTermPendingCandidates() async {
    if (_dictationTermPendingCandidates.isEmpty) return;
    _dictationTermPendingCandidates.clear();
    await _saveDictationTermPendingCandidates();
    notifyListeners();
  }

  Future<void> rejectTermPendingCandidates(Iterable<String> ids) async {
    final targetIds = ids.toSet();
    if (targetIds.isEmpty) return;
    final hadCandidate = _dictationTermPendingCandidates.any(
      (candidate) => targetIds.contains(candidate.id),
    );
    if (!hadCandidate) return;
    _dictationTermPendingCandidates.removeWhere(
      (candidate) => targetIds.contains(candidate.id),
    );
    await _saveDictationTermPendingCandidates();
    notifyListeners();
  }

  Future<DictionaryEntry> upsertDictionaryCorrectionEntry({
    required String original,
    required String corrected,
    String? category,
    DictionaryEntrySource source = DictionaryEntrySource.manual,
  }) async {
    final normalizedOriginal = original.trim();
    final normalizedCorrected = corrected.trim();
    if (normalizedOriginal.isEmpty || normalizedCorrected.isEmpty) {
      throw ArgumentError('original/corrected must not be empty');
    }

    for (final entry in _dictionaryEntries) {
      if (entry.type == DictionaryEntryType.correction &&
          entry.original.trim().toLowerCase() ==
              normalizedOriginal.toLowerCase() &&
          (entry.corrected ?? '').trim().toLowerCase() ==
              normalizedCorrected.toLowerCase()) {
        final enabledEntry = entry.enabled
            ? entry
            : entry.copyWith(enabled: true);
        if (!identical(enabledEntry, entry)) {
          await updateDictionaryEntry(enabledEntry);
        }
        return enabledEntry;
      }
    }

    for (final entry in _dictionaryEntries) {
      if (entry.type == DictionaryEntryType.correction &&
          entry.original.trim().toLowerCase() ==
              normalizedOriginal.toLowerCase()) {
        final updated = entry.copyWith(
          corrected: normalizedCorrected,
          category: category ?? entry.category,
          source: source,
          enabled: true,
        );
        await updateDictionaryEntry(updated);
        return updated;
      }
    }

    final created = DictionaryEntry.create(
      original: normalizedOriginal,
      corrected: normalizedCorrected,
      category: category,
      source: source,
    );
    await addDictionaryEntry(created);
    return created;
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

  MarkdownTermImportResult previewContextMarkdownImport(
    String markdownContent, {
    required String fileName,
  }) {
    return _markdownTermImportService.parse(
      markdownContent,
      fileName: fileName,
    );
  }

  Future<MarkdownTermImportResult> applyTermContextMarkdownImport(
    MarkdownTermImportResult result,
  ) async {
    final mergedEntries = <TermContextEntry>[];
    final existingBySignature = <String, TermContextEntry>{
      for (final entry in _termContextEntries) entry.signature: entry,
    };

    for (final entry in [
      ...result.contextEntries,
      ...result.referenceOnlyTerms,
    ]) {
      final existing = existingBySignature[entry.signature];
      if (existing != null) {
        if (!existing.enabled && entry.enabled) {
          final updated = existing.copyWith(enabled: true);
          _termContextEntries = _termContextEntries
              .map((item) => item.id == existing.id ? updated : item)
              .toList(growable: false);
          existingBySignature[entry.signature] = updated;
          mergedEntries.add(updated);
        } else {
          mergedEntries.add(existing);
        }
        continue;
      }

      final normalized = entry.copyWith(
        sourceName: entry.sourceName.isEmpty
            ? result.fileName
            : entry.sourceName,
      );
      _termContextEntries = [normalized, ..._termContextEntries];
      existingBySignature[normalized.signature] = normalized;
      mergedEntries.add(normalized);
    }

    if (mergedEntries.isNotEmpty) {
      await _saveTermContextEntries();
      await _saveImportedReferenceTerms();
      notifyListeners();
    }

    final mergedSignatures = <String, TermContextEntry>{
      for (final entry in mergedEntries) entry.signature: entry,
    };
    TermContextEntry resolve(TermContextEntry entry) =>
        mergedSignatures[entry.signature] ?? entry;

    return MarkdownTermImportResult(
      fileName: result.fileName,
      contextEntries: result.contextEntries
          .map(resolve)
          .toList(growable: false),
      promotableCorrections: result.promotableCorrections
          .map(resolve)
          .toList(growable: false),
      promotablePreserves: result.promotablePreserves
          .map(resolve)
          .toList(growable: false),
      referenceOnlyTerms: result.referenceOnlyTerms
          .map(resolve)
          .toList(growable: false),
      warnings: result.warnings,
      skippedItems: result.skippedItems,
    );
  }

  Future<void> removeTermContextEntries(List<String> ids) async {
    if (ids.isEmpty) return;
    final idSet = ids.toSet();
    final next = _termContextEntries
        .where((entry) => !idSet.contains(entry.id))
        .toList(growable: false);
    if (next.length == _termContextEntries.length) return;
    _termContextEntries = next;
    await _saveTermContextEntries();
    notifyListeners();
  }

  Future<void> setTermContextEntryEnabled(String id, bool enabled) async {
    var changed = false;
    _termContextEntries = _termContextEntries
        .map((entry) {
          if (entry.id != id || entry.enabled == enabled) return entry;
          changed = true;
          return entry.copyWith(enabled: enabled);
        })
        .toList(growable: false);
    if (!changed) return;
    await _saveTermContextEntries();
    notifyListeners();
  }

  Future<void> removeTermContextEntry(String id) async {
    final next = _termContextEntries.where((entry) => entry.id != id).toList();
    if (next.length == _termContextEntries.length) return;
    _termContextEntries = next;
    await _saveTermContextEntries();
    notifyListeners();
  }

  Future<DictionaryEntry?> promoteTermContextEntryToDictionary(
    String id,
  ) async {
    TermContextEntry? entry;
    for (final item in _termContextEntries) {
      if (item.id == id) {
        entry = item;
        break;
      }
    }
    if (entry == null) return null;
    final selectedEntry = entry;

    if (selectedEntry.promotableAsCorrection) {
      return upsertDictionaryCorrectionEntry(
        original: selectedEntry.alias ?? '',
        corrected: selectedEntry.promptTerm,
        category: 'Context提升',
        source: DictionaryEntrySource.manual,
      );
    }

    if (!selectedEntry.promotableAsPreserve) {
      return null;
    }

    final existing = _dictionaryEntries
        .where((item) {
          return item.type == DictionaryEntryType.preserve &&
              item.original.trim().toLowerCase() ==
                  selectedEntry.promptTerm.toLowerCase();
        })
        .toList(growable: false);

    if (existing.isNotEmpty) {
      final found = existing.first;
      if (!found.enabled) {
        final updated = found.copyWith(enabled: true);
        await updateDictionaryEntry(updated);
        return updated;
      }
      return found;
    }

    final created = DictionaryEntry.create(
      original: selectedEntry.promptTerm,
      category: 'Context提升',
      source: DictionaryEntrySource.manual,
    );
    await addDictionaryEntry(created);
    return created;
  }

  EntityMemory? findEntityByCanonicalName(String canonicalName) {
    final normalized = canonicalName.trim().toLowerCase();
    for (final item in _entityMemories) {
      if (item.canonicalName.trim().toLowerCase() == normalized) {
        return item;
      }
    }
    return null;
  }

  List<EntityAlias> aliasesForEntity(String entityId) {
    return _entityAliases
        .where((alias) => alias.entityId == entityId)
        .toList(growable: false);
  }

  List<EntityEvidence> evidencesForEntity(String entityId) {
    return _entityEvidences
        .where((evidence) => evidence.entityId == entityId)
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  EntityEvidence? latestEvidenceForEntity(String entityId) {
    final evidences = evidencesForEntity(entityId);
    if (evidences.isEmpty) return null;
    return evidences.first;
  }

  Future<EntityMemory> upsertEntityMemory({
    required String canonicalName,
    required EntityType type,
    double confidence = 0.85,
  }) async {
    final normalized = canonicalName.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('canonicalName must not be empty');
    }
    for (final item in _entityMemories) {
      if (item.canonicalName.trim().toLowerCase() == normalized.toLowerCase()) {
        final updated = item.copyWith(
          type: type,
          enabled: true,
          confidence: confidence > item.confidence
              ? confidence
              : item.confidence,
          updatedAt: DateTime.now(),
        );
        _entityMemories = _entityMemories
            .map((entry) => entry.id == item.id ? updated : entry)
            .toList(growable: false);
        await _saveEntityMemories();
        notifyListeners();
        return updated;
      }
    }
    final created = EntityMemory.create(
      canonicalName: normalized,
      type: type,
      confidence: confidence,
    );
    _entityMemories = [created, ..._entityMemories];
    await _saveEntityMemories();
    notifyListeners();
    return created;
  }

  Future<EntityMemory> updateEntityMemory({
    required String entityId,
    required String canonicalName,
    required EntityType type,
    required bool enabled,
    required double confidence,
  }) async {
    final normalized = canonicalName.trim();
    if (entityId.trim().isEmpty || normalized.isEmpty) {
      throw ArgumentError('entityId/canonicalName must not be empty');
    }
    EntityMemory? updated;
    _entityMemories = _entityMemories
        .map((item) {
          if (item.id != entityId) return item;
          updated = item.copyWith(
            canonicalName: normalized,
            type: type,
            enabled: enabled,
            confidence: confidence.clamp(0.0, 1.0).toDouble(),
            updatedAt: DateTime.now(),
          );
          return updated!;
        })
        .toList(growable: false);
    if (updated == null) {
      throw ArgumentError('entity not found: $entityId');
    }
    await _saveEntityMemories();
    await addOrMergeEntityAlias(
      entityId: entityId,
      aliasText: normalized,
      aliasType: EntityAliasType.fullName,
      source: 'manual',
      confidence: 1.0,
    );
    notifyListeners();
    return updated!;
  }

  Future<EntityAlias> addOrMergeEntityAlias({
    required String entityId,
    required String aliasText,
    required EntityAliasType aliasType,
    required String source,
    double confidence = 0.8,
  }) async {
    final normalized = aliasText.trim();
    if (entityId.trim().isEmpty || normalized.isEmpty) {
      throw ArgumentError('entityId/aliasText must not be empty');
    }
    for (final item in _entityAliases) {
      if (item.entityId == entityId &&
          item.aliasText.trim().toLowerCase() == normalized.toLowerCase()) {
        final updated = item.copyWith(
          aliasType: aliasType,
          source: source,
          confidence: confidence > item.confidence
              ? confidence
              : item.confidence,
          createdAt: DateTime.now(),
        );
        _entityAliases = _entityAliases
            .map((entry) => entry.id == item.id ? updated : entry)
            .toList(growable: false);
        await _saveEntityAliases();
        notifyListeners();
        return updated;
      }
    }
    final created = EntityAlias.create(
      entityId: entityId,
      aliasText: normalized,
      aliasType: aliasType,
      source: source,
      confidence: confidence,
    );
    _entityAliases = [created, ..._entityAliases];
    await _saveEntityAliases();
    notifyListeners();
    return created;
  }

  Future<EntityEvidence> addEntityEvidence({
    required String entityId,
    required String sourceType,
    required String sourceRef,
    required String beforeText,
    required String afterText,
    required String extractedAlias,
  }) async {
    final created = EntityEvidence.create(
      entityId: entityId,
      sourceType: sourceType,
      sourceRef: sourceRef,
      beforeText: beforeText,
      afterText: afterText,
      extractedAlias: extractedAlias,
    );
    _entityEvidences = [created, ..._entityEvidences];
    await _saveEntityEvidences();
    notifyListeners();
    return created;
  }

  Future<List<EntityMemory>> learnEntitiesFromHistoryEdit({
    required String beforeText,
    required String afterText,
    String? rawText,
    String sourceHistoryId = '',
  }) async {
    final candidates = _entityLearningService.extractCandidates(
      beforeText: beforeText,
      afterText: afterText,
      rawText: rawText,
    );
    if (candidates.isEmpty) return const [];

    final learned = <EntityMemory>[];
    for (final candidate in candidates) {
      final entity = await upsertEntityMemory(
        canonicalName: candidate.canonicalName,
        type: candidate.entityType,
        confidence: candidate.confidence,
      );
      await addOrMergeEntityAlias(
        entityId: entity.id,
        aliasText: entity.canonicalName,
        aliasType: EntityAliasType.fullName,
        source: 'entity-memory',
        confidence: 1.0,
      );
      final alias = await addOrMergeEntityAlias(
        entityId: entity.id,
        aliasText: candidate.original,
        aliasType: candidate.aliasType,
        source: 'history-edit',
        confidence: candidate.confidence,
      );
      await addEntityEvidence(
        entityId: entity.id,
        sourceType: 'history-edit',
        sourceRef: sourceHistoryId,
        beforeText: beforeText,
        afterText: afterText,
        extractedAlias: candidate.original,
      );
      if (_entityDictionaryBridge.shouldBridge(
        aliasType: alias.aliasType,
        aliasText: alias.aliasText,
        canonicalName: entity.canonicalName,
        confidence: alias.confidence,
      )) {
        await upsertDictionaryCorrectionEntry(
          original: alias.aliasText,
          corrected: entity.canonicalName,
          category: '实体桥接',
          source: DictionaryEntrySource.historyEdit,
        );
      }
      learned.add(entity);
    }
    return learned;
  }

  Future<EntityMemory> addManualEntity({
    required String canonicalName,
    required EntityType type,
    List<String> aliases = const [],
    EntityAliasType aliasType = EntityAliasType.alias,
    double confidence = 0.95,
  }) async {
    final entity = await upsertEntityMemory(
      canonicalName: canonicalName,
      type: type,
      confidence: confidence,
    );
    await addOrMergeEntityAlias(
      entityId: entity.id,
      aliasText: entity.canonicalName,
      aliasType: EntityAliasType.fullName,
      source: 'manual',
      confidence: 1.0,
    );
    for (final alias in aliases) {
      final normalized = alias.trim();
      if (normalized.isEmpty || normalized == entity.canonicalName) continue;
      await addOrMergeEntityAlias(
        entityId: entity.id,
        aliasText: normalized,
        aliasType: aliasType,
        source: 'manual',
        confidence: confidence >= 0.95 ? 0.95 : 0.85,
      );
      await addEntityEvidence(
        entityId: entity.id,
        sourceType: 'manual',
        sourceRef: 'entity-page',
        beforeText: normalized,
        afterText: entity.canonicalName,
        extractedAlias: normalized,
      );
    }
    return entity;
  }

  Future<void> deleteEntity(String entityId) async {
    final nextMemories = _entityMemories
        .where((entity) => entity.id != entityId)
        .toList(growable: false);
    if (nextMemories.length == _entityMemories.length) return;
    _entityMemories = nextMemories;
    _entityAliases = _entityAliases
        .where((alias) => alias.entityId != entityId)
        .toList(growable: false);
    _entityRelations = _entityRelations
        .where(
          (relation) =>
              relation.sourceEntityId != entityId &&
              relation.targetEntityId != entityId,
        )
        .toList(growable: false);
    _entityEvidences = _entityEvidences
        .where((evidence) => evidence.entityId != entityId)
        .toList(growable: false);
    await _saveEntityMemories();
    await _saveEntityAliases();
    await _saveEntityRelations();
    await _saveEntityEvidences();
    notifyListeners();
  }

  Future<void> deleteEntityAlias(String aliasId) async {
    final next = _entityAliases
        .where((alias) => alias.id != aliasId)
        .toList(growable: false);
    if (next.length == _entityAliases.length) return;
    _entityAliases = next;
    await _saveEntityAliases();
    notifyListeners();
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

  Future<void> setHistoryContextEnhancementEnabled(bool enabled) async {
    _historyContextEnhancementEnabled = enabled;
    await _saveSetting(
      _historyContextEnhancementEnabledKey,
      enabled.toString(),
    );
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
