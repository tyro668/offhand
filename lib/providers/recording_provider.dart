import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../models/dictionary_entry.dart';
import '../models/stt_request_context.dart';
import '../models/term_context_entry.dart';
import '../models/transcription.dart';
import '../models/ai_enhance_config.dart';
import '../models/provider_config.dart';
import '../services/audio_recorder.dart';
import '../services/ai_enhance_service.dart';
import '../services/history_db.dart';
import '../services/stt_service.dart';
import '../services/overlay_service.dart';
import '../services/log_service.dart';
import '../services/token_stats_service.dart';
import '../services/vad_service.dart';
import '../services/correction_service.dart';
import '../services/correction_context.dart';
import '../services/pinyin_matcher.dart';
import '../services/session_glossary.dart';
import '../services/correction_stats_service.dart';
import '../services/context_recall_service.dart';
import '../services/term_prompt_builder.dart';

enum RecordingState { idle, recording, transcribing }

class RecordingProvider extends ChangeNotifier {
  static const Duration _segmentDuration = Duration(seconds: 10);
  static const String _overlayOwner = 'dictation';
  static const String _editedHistoryIdsKey = 'edited_history_ids_v1';

  final AudioRecorderService _recorder = AudioRecorderService();
  final HistoryDb _historyDb = HistoryDb.instance;

  RecordingState _state = RecordingState.idle;
  bool _busy = false;
  String _transcribedText = '';
  String _error = '';
  DateTime? _recordingStartTime;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  Timer? _healthTimer;
  Timer? _segmentTimer;
  StreamSubscription<double>? _amplitudeSub;
  final List<Transcription> _history = [];
  final Set<String> _editedHistoryIds = {};
  Completer<void>? _stopCompleter;
  Completer<void>? _segmentDrainCompleter;
  VadService? _vadService;
  StreamSubscription<void>? _vadSub;
  final List<String> _segmentQueue = [];
  final StringBuffer _rawTextBuffer = StringBuffer();
  final StringBuffer _realtimeTextBuffer = StringBuffer();
  bool _segmentWorkerRunning = false;
  bool _segmentSwitching = false;
  bool _sessionStopping = false;
  int _sessionId = 0;
  SttProviderConfig? _activeSttConfig;
  // VAD auto-stop callback — set by the screen that owns the provider
  void Function()? onVadTriggered;

  // Correction pipeline
  CorrectionService? _correctionService;
  final CorrectionContext _correctionContext = CorrectionContext();
  final SessionGlossary _sessionGlossary = SessionGlossary();
  static const ContextRecallService _contextRecallService =
      ContextRecallService();
  bool _retrospectiveCorrectionEnabled = false;
  List<DictionaryEntry> _dictionaryEntries = const [];
  List<TermContextEntry> _termContextEntries = const [];
  final TermPromptBuilder _termPromptBuilder = const TermPromptBuilder();
  String _startingLabel = 'Starting';
  String _recordingLabel = 'Recording';
  String _transcribingLabel = 'Transcribing';
  String _enhancingLabel = 'Enhancing';
  String _transcribeFailedLabel = 'Transcribe failed';

  RecordingProvider() {
    _loadHistory();
  }

  /// 配置纠错服务。在 startRecording 之前调用。
  ///
  /// [matcher] 拼音匹配器实例（来自 SettingsProvider）
  /// [aiConfig] 用于纠错 LLM 调用的配置
  /// [correctionPrompt] 纠错专用 prompt
  void configureCorrectionService({
    required PinyinMatcher matcher,
    required AiEnhanceConfig aiConfig,
    required String correctionPrompt,
    List<DictionaryEntry> dictionaryEntries = const [],
    List<TermContextEntry> termContextEntries = const [],
    int maxReferenceEntries = 15,
    double minCandidateScore = 0.30,
  }) {
    _dictionaryEntries = List<DictionaryEntry>.from(dictionaryEntries);
    _termContextEntries = List<TermContextEntry>.from(termContextEntries);
    _correctionService = CorrectionService(
      matcher: matcher,
      context: _correctionContext,
      aiConfig: aiConfig,
      correctionPrompt: correctionPrompt,
      maxReferenceEntries: maxReferenceEntries,
      minCandidateScore: minCandidateScore,
      sessionGlossary: _sessionGlossary,
    );
  }

  /// 禁用纠错服务。
  void disableCorrectionService() {
    _correctionService = null;
    _dictionaryEntries = const [];
    _termContextEntries = const [];
  }

  /// 设置终态回溯纠错开关。
  set retrospectiveCorrectionEnabled(bool value) {
    _retrospectiveCorrectionEnabled = value;
  }

  /// 手动覆盖会话术语映射（由词典页编辑触发）。
  void applySessionGlossaryOverride(String original, String corrected) {
    _sessionGlossary.override(original, corrected);
  }

  Future<void> _flushGlossaryStats() async {
    try {
      await CorrectionStatsService.instance.flushGlossaryStats(
        pins: _sessionGlossary.pinsCount,
        strongPromotions: _sessionGlossary.strongPromotionsCount,
        overrides: _sessionGlossary.overridesCount,
        injections: _sessionGlossary.injectionsCount,
      );
    } catch (_) {}
  }

  RecordingState get state => _state;
  bool get busy => _busy;
  String get transcribedText => _transcribedText;
  String get error => _error;
  Duration get recordingDuration => _recordingDuration;
  List<Transcription> get history => List.unmodifiable(_history);
  Stream<double> get amplitudeStream => _recorder.amplitudeStream;
  bool isHistoryEdited(String id) => _editedHistoryIds.contains(id);

  void setOverlayStateLabels({
    required String starting,
    required String recording,
    required String transcribing,
    required String enhancing,
    required String transcribeFailed,
  }) {
    _startingLabel = starting;
    _recordingLabel = recording;
    _transcribingLabel = transcribing;
    _enhancingLabel = enhancing;
    _transcribeFailedLabel = transcribeFailed;
  }

  String get _durationStr {
    final m = _recordingDuration.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final s = _recordingDuration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> startRecording(SttProviderConfig config) async {
    if (_busy) return;
    _busy = true;
    try {
      await _startRecordingInternal(config).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          LogService.error('RECORDING', 'startRecording timed out after 15s');
          _state = RecordingState.idle;
          unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
          notifyListeners();
        },
      );
    } catch (e) {
      _error = '录音启动失败: $e';
      _state = RecordingState.idle;
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  Future<void> _startRecordingInternal(SttProviderConfig config) async {
    // 等待上一次 stop 操作完成，避免竞态
    if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
      await LogService.info('RECORDING', 'waiting for stopCompleter');
      await _stopCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
    }
    _error = '';
    _activeSttConfig = config;
    _sessionId += 1;
    _sessionStopping = false;
    _segmentSwitching = false;
    _segmentTimer?.cancel();
    _segmentTimer = null;
    _segmentQueue.clear();
    _segmentDrainCompleter = null;
    _rawTextBuffer.clear();
    _realtimeTextBuffer.clear();
    _transcribedText = '';
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _correctionContext.reset();
    unawaited(_flushGlossaryStats());
    _sessionGlossary.reset();

    // 无论当前状态如何，都先 reset recorder，确保干净状态
    await LogService.info('RECORDING', 'resetting recorder');
    try {
      await _recorder.reset().timeout(const Duration(seconds: 3));
    } catch (_) {
      // reset 超时也继续尝试录音
      await LogService.info('RECORDING', 'reset timeout, continuing');
    }
    await LogService.info('RECORDING', 'checking permission');
    final hasPermission = await _recorder.hasPermission().timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );
    if (!hasPermission) {
      _error = '需要麦克风权限才能录音';
      notifyListeners();
      return;
    }

    await LogService.info('RECORDING', 'showing starting overlay');
    // 不 await overlay 调用，避免阻塞录音流程
    unawaited(
      OverlayService.showOverlay(
        state: 'starting',
        duration: '00:00',
        level: 0.0,
        stateLabel: _startingLabel,
        owner: _overlayOwner,
      ),
    );

    await LogService.info('RECORDING', 'starting recorder');
    try {
      await _recorder.startWithTimeout(const Duration(seconds: 2));
    } catch (e) {
      await LogService.info(
        'RECORDING',
        'start failed ($e), resetting and retrying',
      );
      try {
        await _recorder.reset().timeout(const Duration(seconds: 3));
      } catch (_) {}
      await _recorder.startWithTimeout(const Duration(seconds: 2));
    }
    await LogService.info('RECORDING', 'recorder started successfully');
    _state = RecordingState.recording;
    _recordingStartTime = DateTime.now();
    _recordingDuration = Duration.zero;

    unawaited(
      OverlayService.showOverlay(
        state: 'recording',
        duration: '00:00',
        level: 0.0,
        stateLabel: _recordingLabel,
        owner: _overlayOwner,
      ),
    );

    _amplitudeSub = _recorder.amplitudeStream.listen((level) {
      OverlayService.updateOverlay(
        state: 'recording',
        duration: _durationStr,
        level: level,
        stateLabel: _recordingLabel,
        owner: _overlayOwner,
      );
    });

    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        await _recorder.isRecording();
        await _recorder.currentFileSize();
      } catch (_) {}
    });

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recordingDuration = DateTime.now().difference(_recordingStartTime!);
      notifyListeners();
    });

    _segmentTimer = Timer.periodic(_segmentDuration, (_) {
      unawaited(_handleSegmentTick(_sessionId));
    });

    notifyListeners();
  }

  Future<void> _handleSegmentTick(int sessionId) async {
    if (_state != RecordingState.recording || _sessionStopping) return;
    if (_segmentSwitching) return;
    if (_activeSttConfig == null) return;
    if (sessionId != _sessionId) return;

    _segmentSwitching = true;
    try {
      await _rotateSegment(sessionId);
    } catch (e) {
      await LogService.error('SEGMENT', 'rotate segment failed: $e');
    } finally {
      _segmentSwitching = false;
    }
  }

  Future<void> _rotateSegment(int sessionId) async {
    if (sessionId != _sessionId || _sessionStopping) return;

    final stopFuture = _recorder.stop();
    final fallbackPath = _recorder.currentPath;

    var path = await stopFuture.timeout(
      const Duration(seconds: 20),
      onTimeout: () => null,
    );

    if (path == null && fallbackPath != null) {
      path = await _waitForFileReady(fallbackPath, const Duration(seconds: 20));
    }

    if (path != null) {
      _enqueueSegmentPath(path, sessionId);
    }

    if (_sessionStopping || sessionId != _sessionId) return;

    try {
      await _recorder.startWithTimeout(const Duration(seconds: 2));
    } catch (e) {
      await LogService.info(
        'SEGMENT',
        'restart failed ($e), resetting and retrying',
      );
      try {
        await _recorder.reset().timeout(const Duration(seconds: 3));
      } catch (_) {}
      await _recorder.startWithTimeout(const Duration(seconds: 2));
    }
  }

  void _enqueueSegmentPath(String path, int sessionId) {
    _segmentQueue.add(path);
    _segmentDrainCompleter ??= Completer<void>();
    if (!_segmentWorkerRunning) {
      unawaited(_runSegmentWorker(sessionId));
    }
  }

  Future<void> _runSegmentWorker(int sessionId) async {
    if (_segmentWorkerRunning) return;
    _segmentWorkerRunning = true;
    try {
      while (_segmentQueue.isNotEmpty) {
        final path = _segmentQueue.removeAt(0);
        final config = _activeSttConfig;
        if (config == null) {
          continue;
        }
        try {
          final sttContext = _buildSttRequestContext(
            scene: 'dictation',
            currentText: _realtimeTextBuffer.toString(),
          );
          var text = await SttService(
            config,
          ).transcribe(path, context: sttContext);
          // 纠错：若已配置 CorrectionService，对 STT 结果做拼音匹配 + LLM 纠错
          if (sessionId == _sessionId &&
              _correctionService != null &&
              text.trim().isNotEmpty) {
            try {
              final result = await _correctionService!.correct(text);
              text = result.text;
            } catch (e) {
              await LogService.error('SEGMENT', 'correction failed: $e');
              // 纠错失败不影响主流程
            }
          }
          if (sessionId == _sessionId) {
            _appendRealtimeText(text);
          }
        } catch (e) {
          await LogService.error('SEGMENT', 'segment transcribe failed: $e');
        }
      }
    } finally {
      _segmentWorkerRunning = false;
      if (_segmentQueue.isEmpty) {
        if (_segmentDrainCompleter != null &&
            !_segmentDrainCompleter!.isCompleted) {
          _segmentDrainCompleter!.complete();
        }
        _segmentDrainCompleter = null;
      }
    }
  }

  SttRequestContext? _buildSttRequestContext({
    required String scene,
    required String currentText,
  }) {
    final bundle = _termPromptBuilder.build(
      scene: scene,
      currentText: currentText,
      history: _history,
      dictionaryEntries: _dictionaryEntries,
      sessionGlossary: _sessionGlossary,
      termContextEntries: _termContextEntries,
    );
    if (!bundle.hasPrompt) return null;
    return SttRequestContext(
      scene: scene,
      prompt: bundle.sttPrompt,
      preferredTerms: bundle.preferredTerms,
      preserveTerms: bundle.preserveTerms,
    );
  }

  void _appendRealtimeText(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return;

    if (_rawTextBuffer.isNotEmpty) {
      _rawTextBuffer.write('\n');
      _realtimeTextBuffer.write('\n');
    }
    _rawTextBuffer.write(normalized);
    _realtimeTextBuffer.write(normalized);
    _transcribedText = _realtimeTextBuffer.toString();
    unawaited(
      OverlayService.updateOverlayText(_transcribedText, owner: _overlayOwner),
    );
    notifyListeners();
  }

  Future<void> _waitForSegmentDrain() async {
    if (_segmentQueue.isEmpty && !_segmentWorkerRunning) {
      return;
    }
    _segmentDrainCompleter ??= Completer<void>();
    await _segmentDrainCompleter!.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {},
    );
  }

  /// Start VAD monitoring. Call after startRecording().
  void startVad({
    double silenceThreshold = 0.05,
    int silenceDurationSeconds = 3,
    int minRecordingSeconds = 3,
  }) {
    stopVad();
    _vadService = VadService(
      silenceThreshold: silenceThreshold,
      silenceDuration: Duration(seconds: silenceDurationSeconds),
      minRecordingDuration: Duration(seconds: minRecordingSeconds),
    );
    _vadSub = _vadService!.onSilenceDetected.listen((_) {
      LogService.info('VAD', 'silence detected, triggering auto-stop');
      onVadTriggered?.call();
    });
    _vadService!.start(_recorder.amplitudeStream);
  }

  /// Stop VAD monitoring.
  void stopVad() {
    _vadSub?.cancel();
    _vadSub = null;
    _vadService?.dispose();
    _vadService = null;
  }

  Future<void> stopAndTranscribe(
    SttProviderConfig config, {
    bool aiEnhanceEnabled = false,
    AiEnhanceConfig? aiEnhanceConfig,
    bool historyContextEnhancementEnabled = false,
    int minRecordingSeconds = 3,
    bool useStreaming = false,
  }) async {
    if (_busy) return;
    _busy = true;
    _activeSttConfig ??= config;
    stopVad();
    try {
      _durationTimer?.cancel();
      _durationTimer = null;
      _healthTimer?.cancel();
      _healthTimer = null;
      _segmentTimer?.cancel();
      _segmentTimer = null;
      _amplitudeSub?.cancel();
      _amplitudeSub = null;

      final duration = _recordingDuration;

      // 录音时长不足，忽略本次输入
      if (duration.inSeconds < minRecordingSeconds) {
        _sessionStopping = true;
        _state = RecordingState.idle;
        unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
        _stopCompleter = Completer<void>();
        _recorder.stop().then((_) => _recorder.reset()).whenComplete(() {
          if (!_stopCompleter!.isCompleted) _stopCompleter!.complete();
        });
        notifyListeners();
        return;
      }

      unawaited(
        OverlayService.showOverlay(
          state: 'transcribing',
          stateLabel: _transcribingLabel,
          owner: _overlayOwner,
        ),
      );
      _state = RecordingState.idle;
      notifyListeners();

      _stopCompleter = Completer<void>();
      unawaited(
        _stopAndTranscribeInBackground(
          config,
          duration,
          aiEnhanceEnabled: aiEnhanceEnabled,
          aiEnhanceConfig: aiEnhanceConfig,
          historyContextEnhancementEnabled: historyContextEnhancementEnabled,
          useStreaming: useStreaming,
        ),
      );
    } catch (e) {
      _error = '停止录音失败: $e';
      _state = RecordingState.idle;
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      _amplitudeSub?.cancel();
      _amplitudeSub = null;
      if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
        _stopCompleter!.complete();
      }
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  Future<void> _stopAndTranscribeInBackground(
    SttProviderConfig config,
    Duration duration, {
    required bool aiEnhanceEnabled,
    required AiEnhanceConfig? aiEnhanceConfig,
    required bool historyContextEnhancementEnabled,
    bool useStreaming = false,
  }) async {
    final sw = Stopwatch()..start();
    try {
      _sessionStopping = true;
      while (_segmentSwitching) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await LogService.info('TRANSCRIBE', 'step1: stopping recorder...');
      final stopFuture = _recorder.stop();
      final fallbackPath = _recorder.currentPath;

      var path = await stopFuture.timeout(
        const Duration(seconds: 20),
        onTimeout: () => null,
      );
      await LogService.info(
        'TRANSCRIBE',
        'step1 done: recorder.stop() ${sw.elapsedMilliseconds}ms, path=${path != null}',
      );

      if (path == null && fallbackPath != null) {
        await LogService.info(
          'TRANSCRIBE',
          'step2: waiting for file ready fallbackPath=$fallbackPath',
        );
        path = await _waitForFileReady(
          fallbackPath,
          const Duration(seconds: 20),
        );
        await LogService.info(
          'TRANSCRIBE',
          'step2 done: ${sw.elapsedMilliseconds}ms, path=${path != null}',
        );
      }

      if (path == null) {
        await LogService.info('TRANSCRIBE', 'step3: retry stop...');
        path = await stopFuture.timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
        await LogService.info(
          'TRANSCRIBE',
          'step3 done: ${sw.elapsedMilliseconds}ms, path=${path != null}',
        );
      }

      // recorder 已停止，允许下一次录音
      if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
        _stopCompleter!.complete();
      }

      if (path == null) {
        await LogService.info(
          'TRANSCRIBE',
          'final segment path unavailable, continue with queued segments',
        );
      } else {
        _enqueueSegmentPath(path, _sessionId);
      }

      await _waitForSegmentDrain();

      var rawText = _rawTextBuffer.toString().trim();
      await LogService.info(
        'TRANSCRIBE',
        'segment collection done: ${sw.elapsedMilliseconds}ms, textLength=${rawText.length}',
      );

      if (rawText.isEmpty) {
        _error = '转录结果为空';
        await LogService.error(
          'TRANSCRIBE',
          'empty segment result after ${sw.elapsedMilliseconds}ms',
        );
        _showTranscribeFailedOverlay();
        notifyListeners();
        return;
      }

      // M2 终态回溯：对全段已纠错文本做一次段落级复核
      if (_retrospectiveCorrectionEnabled &&
          _correctionService != null &&
          rawText.trim().isNotEmpty) {
        try {
          await LogService.info(
            'TRANSCRIBE',
            'retrospective correction start...',
          );
          final retroResult = await _correctionService!.correctParagraph(
            rawText,
          );
          if (retroResult.text.trim().isNotEmpty) {
            rawText = retroResult.text;
            // 同步更新实时展示文本
            _transcribedText = rawText;
            unawaited(
              OverlayService.updateOverlayText(
                _transcribedText,
                owner: _overlayOwner,
              ),
            );
            notifyListeners();
          }
          await LogService.info(
            'TRANSCRIBE',
            'retrospective correction done: ${sw.elapsedMilliseconds}ms',
          );
        } catch (e) {
          await LogService.error(
            'TRANSCRIBE',
            'retrospective correction failed: $e',
          );
          // 终态回溯失败不影响主流程
        }
      }

      _finalizeTranscriptionFromRawText(
        rawText,
        config,
        duration,
        aiEnhanceEnabled: aiEnhanceEnabled,
        aiEnhanceConfig: aiEnhanceConfig,
        historyContextEnhancementEnabled: historyContextEnhancementEnabled,
        useStreaming: useStreaming,
      );
    } catch (e) {
      _error = '停止录音失败: $e';
      await LogService.error(
        'TRANSCRIBE',
        'stop failed after ${sw.elapsedMilliseconds}ms: $e',
      );
      if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
        _stopCompleter!.complete();
      }
      await _recorder.reset();
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      notifyListeners();
    }
  }

  Future<String?> _waitForFileReady(String filePath, Duration timeout) async {
    final maxTicks = timeout.inMilliseconds ~/ 200;
    for (var i = 0; i < maxTicks; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      final file = File(filePath);
      if (await file.exists()) {
        final size = await file.length();
        if (size > 0) {
          return filePath;
        }
      }
    }

    return null;
  }

  void _finalizeTranscriptionFromRawText(
    String rawText,
    SttProviderConfig config,
    Duration duration, {
    required bool aiEnhanceEnabled,
    required AiEnhanceConfig? aiEnhanceConfig,
    required bool historyContextEnhancementEnabled,
    bool useStreaming = false,
  }) async {
    final sw = Stopwatch()..start();
    try {
      await LogService.info(
        'TRANSCRIBE',
        'finalize start: provider=${config.name} model=${config.model} rawTextLength=${rawText.length}',
      );
      var finalText = rawText;

      if (aiEnhanceEnabled && aiEnhanceConfig != null) {
        try {
          await LogService.info('TRANSCRIBE', 'ai enhance start...');
          unawaited(
            OverlayService.showOverlay(
              state: 'enhancing',
              stateLabel: _enhancingLabel,
              owner: _overlayOwner,
            ),
          );
          var effectiveEnhanceConfig = aiEnhanceConfig;
          if (historyContextEnhancementEnabled) {
            final contextHints = _contextRecallService.recall(
              currentText: rawText,
              history: _history,
            );
            if (contextHints.hasContent) {
              effectiveEnhanceConfig = aiEnhanceConfig.copyWith(
                prompt: aiEnhanceConfig.prompt + contextHints.toPromptSuffix(),
              );
              await LogService.info(
                'TRANSCRIBE',
                'history context injected: refs=${contextHints.referenceTexts.length} topic=${contextHints.recentTopic ?? '-'} style=${contextHints.recentStyle ?? '-'}',
              );
            }
          }
          final enhancer = AiEnhanceService(effectiveEnhanceConfig);

          if (useStreaming) {
            // Streaming mode: show text in real-time on overlay
            final buffer = StringBuffer();
            try {
              await for (final chunk in enhancer.enhanceStream(rawText)) {
                buffer.write(chunk);
                unawaited(
                  OverlayService.updateOverlayText(
                    buffer.toString(),
                    owner: _overlayOwner,
                  ),
                );
              }
              finalText = buffer.toString().trim();
              if (finalText.isEmpty) finalText = rawText;
            } catch (e) {
              await LogService.error(
                'TRANSCRIBE',
                'streaming enhance failed: $e, falling back to batch',
              );
              // Fallback to batch mode
              final enhanceResult = await enhancer.enhance(rawText);
              finalText = enhanceResult.text;
              if (enhanceResult.totalTokens > 0) {
                try {
                  await TokenStatsService.instance.addTokens(
                    promptTokens: enhanceResult.promptTokens,
                    completionTokens: enhanceResult.completionTokens,
                  );
                } catch (_) {}
              }
            }
          } else {
            // Batch mode (original)
            final enhanceResult = await enhancer.enhance(rawText);
            finalText = enhanceResult.text;
            // 累计 token 用量
            if (enhanceResult.totalTokens > 0) {
              try {
                await TokenStatsService.instance.addTokens(
                  promptTokens: enhanceResult.promptTokens,
                  completionTokens: enhanceResult.completionTokens,
                );
              } catch (_) {}
            }
          }
          await LogService.info(
            'TRANSCRIBE',
            'ai enhance done: ${sw.elapsedMilliseconds}ms',
          );
        } catch (e) {
          await LogService.error('TRANSCRIBE', 'ai enhance failed: $e');
          finalText = rawText;
        }
      }

      _transcribedText = finalText;

      if (finalText.isNotEmpty) {
        final safeConfig = config.copyWith(apiKey: '');
        final item = Transcription(
          id: const Uuid().v4(),
          text: finalText,
          rawText: aiEnhanceEnabled ? rawText : null,
          createdAt: DateTime.now(),
          duration: duration,
          provider: config.name,
          model: config.model,
          providerConfigJson: json.encode(safeConfig.toJson()),
        );
        _history.insert(0, item);
        try {
          await _historyDb.insert(item);
        } catch (e) {
          // ignore
        }
        try {
          await LogService.info('TRANSCRIBE', 'inserting text...');
          await OverlayService.insertText(finalText);
          await LogService.info(
            'TRANSCRIBE',
            'insertText done: ${sw.elapsedMilliseconds}ms',
          );
        } catch (e) {
          await LogService.error('TRANSCRIBE', 'insertText failed: $e');
        }
        unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
        await LogService.info(
          'TRANSCRIBE',
          'complete success: total ${sw.elapsedMilliseconds}ms',
        );
      } else {
        _error = '转录结果为空';
        await LogService.error(
          'TRANSCRIBE',
          'empty result after ${sw.elapsedMilliseconds}ms',
        );
        _showTranscribeFailedOverlay();
      }

      notifyListeners();
    } catch (e) {
      _error = '转录失败: $e';
      await LogService.error(
        'TRANSCRIBE',
        'failed after ${sw.elapsedMilliseconds}ms: $e',
      );
      _showTranscribeFailedOverlay();
      notifyListeners();
    }
  }

  void _showTranscribeFailedOverlay() {
    // 不 await overlay 调用，避免 MethodChannel 阻塞后续录音
    OverlayService.showOverlay(
      state: 'transcribe_failed',
      stateLabel: _transcribeFailedLabel,
      owner: _overlayOwner,
    ).catchError((_) {});
    Future.delayed(const Duration(seconds: 3), () {
      OverlayService.hideOverlay(owner: _overlayOwner).catchError((_) {});
    });
  }

  Future<void> _loadHistory() async {
    try {
      final items = await _historyDb.getAll();
      _history
        ..clear()
        ..addAll(items);
      final raw = await AppDatabase.instance.getSetting(_editedHistoryIdsKey);
      _editedHistoryIds
        ..clear()
        ..addAll(_decodeEditedHistoryIds(raw));
      notifyListeners();
    } catch (e) {
      // ignore
    }
  }

  Set<String> _decodeEditedHistoryIds(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String>{};
    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().map((e) => e.trim()).toSet();
      }
    } catch (_) {}
    return <String>{};
  }

  Future<void> _saveEditedHistoryIds() async {
    await AppDatabase.instance.setSetting(
      _editedHistoryIdsKey,
      json.encode(_editedHistoryIds.toList()..sort()),
    );
  }

  void clearText() {
    _transcribedText = '';
    notifyListeners();
  }

  void clearError() {
    _error = '';
    notifyListeners();
  }

  void removeHistory(int index) {
    final item = _history.removeAt(index);
    _editedHistoryIds.remove(item.id);
    unawaited(_saveEditedHistoryIds());
    _historyDb.deleteById(item.id);
    notifyListeners();
  }

  Future<void> updateHistoryText(String id, String text) async {
    final index = _history.indexWhere((item) => item.id == id);
    if (index < 0) return;

    final current = _history[index];
    final updated = Transcription(
      id: current.id,
      text: text.trim(),
      rawText: current.rawText,
      createdAt: current.createdAt,
      duration: current.duration,
      provider: current.provider,
      model: current.model,
      providerConfigJson: current.providerConfigJson,
    );

    _history[index] = updated;
    _editedHistoryIds.add(id);
    await _saveEditedHistoryIds();
    await _historyDb.insert(updated);
    notifyListeners();
  }

  void clearAllHistory() {
    _history.clear();
    _editedHistoryIds.clear();
    unawaited(_saveEditedHistoryIds());
    _historyDb.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _healthTimer?.cancel();
    _segmentTimer?.cancel();
    _amplitudeSub?.cancel();
    stopVad();
    _recorder.dispose();
    super.dispose();
  }
}
