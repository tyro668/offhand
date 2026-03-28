import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../models/meeting.dart';
import '../models/merged_note.dart';
import '../models/provider_config.dart';
import '../models/ai_enhance_config.dart';
import 'audio_recorder.dart';
import 'stt_service.dart';
import 'ai_enhance_service.dart';
import 'log_service.dart';
import 'sliding_window_merger.dart';
import 'token_stats_service.dart';
import 'correction_service.dart';
import 'correction_context.dart';
import 'session_glossary.dart';
import 'pinyin_matcher.dart';
import 'vad_service.dart';
import 'correction_stats_service.dart';
import 'incremental_summary_service.dart';

/// 会议录音服务 — 管理分段录音与自动转文字流水线
class MeetingRecordingService {
  static const _uuid = Uuid();
  static const Duration _segmentStartTimeout = Duration(seconds: 8);

  final AudioRecorderService _recorder = AudioRecorderService();

  /// 分段时长（秒），默认 30 秒（仅回退模式使用）
  int segmentDurationSeconds = 30;

  /// 智能分段参数
  int _softMinSeconds = 20;
  int _hardMaxSeconds = 30;
  double _silenceThreshold = 0.05;
  int _silenceDurationMs = 500;
  bool _useSmartSegment = true;

  /// VAD 静音检测服务（智能分段模式）
  VadService? _vadService;
  StreamSubscription<void>? _vadSubscription;

  /// 硬截断计时器（到 hardMaxSeconds 强制截断）
  Timer? _hardCutTimer;

  /// 当前分段开始时间（用于计算实际段时长）
  DateTime? _segmentStartTime;

  /// 当前会议记录
  MeetingRecord? _currentMeeting;

  /// 当前分段索引
  int _segmentIndex = 0;

  /// 录音状态
  bool _isRecording = false;
  bool _isPaused = false;
  bool _segmentSwitching = false;
  bool _stopping = false;
  Future<MeetingRecord>? _stopMeetingFuture;

  /// 计时器
  Timer? _segmentTimer;
  Timer? _durationTimer;
  DateTime? _recordingStartTime;
  Duration _recordingDuration = Duration.zero;
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStartTime;

  /// 事件流
  final StreamController<MeetingSegment> _onSegmentReady =
      StreamController<MeetingSegment>.broadcast();
  final StreamController<MeetingSegment> _onSegmentUpdated =
      StreamController<MeetingSegment>.broadcast();
  final StreamController<String> _onStatusChanged =
      StreamController<String>.broadcast();
  final StreamController<Duration> _onDurationChanged =
      StreamController<Duration>.broadcast();

  Stream<MeetingSegment> get onSegmentReady => _onSegmentReady.stream;
  Stream<MeetingSegment> get onSegmentUpdated => _onSegmentUpdated.stream;
  Stream<String> get onStatusChanged => _onStatusChanged.stream;
  Stream<Duration> get onDurationChanged => _onDurationChanged.stream;
  Stream<double> get amplitudeStream => _recorder.amplitudeStream;

  /// 当前会议
  MeetingRecord? get currentMeeting => _currentMeeting;
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  Duration get recordingDuration {
    if (_isRecording && !_isPaused && _recordingStartTime != null) {
      _refreshRecordingDuration();
    }
    return _recordingDuration;
  }

  void _refreshRecordingDuration({bool emit = false}) {
    final start = _recordingStartTime;
    if (start == null) return;
    final live = DateTime.now().difference(start) - _pausedDuration;
    _recordingDuration = live.isNegative ? Duration.zero : live;
    if (emit) {
      _onDurationChanged.add(_recordingDuration);
    }
  }

  /// 会话内手动覆盖术语映射（来自词典编辑）。
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

  /// 待处理分段队列
  final List<_PendingSegment> _processingQueue = [];
  bool _processingWorkerRunning = false;

  /// STT 和 AI 增强配置（由外部传入）
  SttProviderConfig? _sttConfig;
  AiEnhanceConfig? _aiConfig;
  bool _aiEnhanceEnabled = false;

  /// 滑动窗口合并器
  SlidingWindowMerger? _merger;

  /// 暴露合并器实例，供 MeetingProvider 监听其事件流
  SlidingWindowMerger? get merger => _merger;

  /// 增量摘要服务
  IncrementalSummaryService? _incrementalSummary;

  /// 暴露增量摘要实例
  IncrementalSummaryService? get incrementalSummary => _incrementalSummary;

  /// 当前合并文稿（来自 Merger 缓存）
  String get currentFullText => _merger?.currentFullText ?? '';

  /// 当前增量摘要
  String get currentSummary => _incrementalSummary?.currentSummary ?? '';

  /// 已覆盖到的最大分段索引
  int get lastCoveredSegmentIndex => _merger?.lastCoveredSegmentIndex ?? -1;

  /// 是否已自动生成过标题
  bool _earlyTitleGenerated = false;
  bool get earlyTitleGenerated => _earlyTitleGenerated;

  /// 提前生成的标题事件流
  final StreamController<String> _onTitleGenerated =
      StreamController<String>.broadcast();
  Stream<String> get onTitleGenerated => _onTitleGenerated.stream;

  /// 纠错服务
  CorrectionService? _correctionService;
  final CorrectionContext _correctionContext = CorrectionContext();
  final SessionGlossary _sessionGlossary = SessionGlossary();

  /// 开始新的会议录音
  Future<MeetingRecord> startMeeting({
    String? title,
    required SttProviderConfig sttConfig,
    AiEnhanceConfig? aiConfig,
    bool aiEnhanceEnabled = false,
    int? segmentSeconds,
    int windowSize = 5,
    PinyinMatcher? pinyinMatcher,
    String? correctionPrompt,
    int maxReferenceEntries = 15,
    double minCandidateScore = 0.30,
    int softMinSeconds = 20,
    int hardMaxSeconds = 30,
    double silenceThreshold = 0.05,
    int silenceDurationMs = 500,
  }) async {
    if (_isRecording) {
      throw MeetingRecordingException('已有会议正在录制中');
    }

    _sttConfig = sttConfig;
    _aiConfig = aiConfig;
    _aiEnhanceEnabled = aiEnhanceEnabled;

    // 智能分段参数
    _softMinSeconds = softMinSeconds;
    _hardMaxSeconds = hardMaxSeconds;
    _silenceThreshold = silenceThreshold;
    _silenceDurationMs = silenceDurationMs;

    // 如果外部显式传入 segmentSeconds，回退到固定截断模式
    if (segmentSeconds != null) {
      segmentDurationSeconds = segmentSeconds;
      _useSmartSegment = false;
    } else {
      segmentDurationSeconds = hardMaxSeconds;
      _useSmartSegment = true;
    }

    // 初始化纠错服务
    _correctionContext.reset();
    unawaited(_flushGlossaryStats());
    _sessionGlossary.reset();
    if (pinyinMatcher != null &&
        aiConfig != null &&
        correctionPrompt != null &&
        correctionPrompt.isNotEmpty) {
      _correctionService = CorrectionService(
        matcher: pinyinMatcher,
        context: _correctionContext,
        aiConfig: aiConfig,
        correctionPrompt: correctionPrompt,
        maxReferenceEntries: maxReferenceEntries,
        minCandidateScore: minCandidateScore,
        sessionGlossary: _sessionGlossary,
      );
    } else {
      _correctionService = null;
    }

    // 创建滑动窗口合并器（需要 AI 配置）
    if (_aiConfig != null) {
      final clampedWindowSize = clampWindowSize(windowSize);
      _merger = SlidingWindowMerger(
        windowSize: clampedWindowSize,
        aiConfig: _aiConfig!,
      );
    }

    // 创建增量摘要服务
    _incrementalSummary?.dispose();
    if (_aiConfig != null && aiEnhanceEnabled) {
      _incrementalSummary = IncrementalSummaryService(aiConfig: _aiConfig!);
    } else {
      _incrementalSummary = null;
    }
    _earlyTitleGenerated = false;

    final now = DateTime.now();
    final meeting = MeetingRecord(
      id: _uuid.v4(),
      title:
          title ??
          '会议 ${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
      createdAt: now,
      updatedAt: now,
      status: MeetingStatus.recording,
    );

    // 持久化
    final db = AppDatabase.instance;
    await db.insertMeeting(meeting);

    _currentMeeting = meeting;
    _segmentIndex = 0;
    _recordingDuration = Duration.zero;
    _pausedDuration = Duration.zero;
    _stopping = false;

    await LogService.info('MEETING', 'starting meeting: ${meeting.id}');

    // 开始第一段录音（如果失败则清理数据库中的会议记录）
    try {
      await _startSegmentRecording();
    } catch (e) {
      // 录音启动失败，清理已写入的会议记录
      await db.deleteMeetingById(meeting.id);
      _currentMeeting = null;
      await LogService.error(
        'MEETING',
        'start recording failed, cleaned up: $e',
      );
      rethrow;
    }

    // 启动计时器
    _recordingStartTime = now;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused) {
        _refreshRecordingDuration(emit: true);
      }
    });

    // 启动分段控制
    _startSegmentControl();

    _isRecording = true;
    _isPaused = false;
    _onStatusChanged.add('recording');

    return meeting;
  }

  /// 启动分段控制（智能模式或固定模式）
  void _startSegmentControl() {
    if (_useSmartSegment) {
      _startSmartSegmentControl();
    } else {
      // 回退到固定周期截断
      _segmentTimer = Timer.periodic(
        Duration(seconds: segmentDurationSeconds),
        (_) => _handleSegmentTick(),
      );
    }
  }

  /// 启动智能分段控制：VAD 监听 + 硬截断计时器
  void _startSmartSegmentControl() {
    _segmentStartTime = DateTime.now();

    // 创建 VAD 实例
    _vadService?.dispose();
    _vadService = VadService(
      silenceThreshold: _silenceThreshold,
      silenceDuration: Duration(milliseconds: _silenceDurationMs),
      minRecordingDuration: Duration(seconds: _softMinSeconds),
    );

    // 监听静音事件
    _vadSubscription?.cancel();
    _vadSubscription = _vadService!.onSilenceDetected.listen((_) {
      _handleSilenceDetected();
    });

    // 启动 VAD 监听振幅流
    _vadService!.start(_recorder.amplitudeStream);

    // 设置硬截断计时器
    _hardCutTimer?.cancel();
    _hardCutTimer = Timer(
      Duration(seconds: _hardMaxSeconds),
      () => _handleHardCut(),
    );
  }

  /// 停止智能分段控制
  void _stopSmartSegmentControl() {
    _vadSubscription?.cancel();
    _vadSubscription = null;
    _vadService?.stop();
    _hardCutTimer?.cancel();
    _hardCutTimer = null;
  }

  /// VAD 检测到静音 — 柔性截断
  Future<void> _handleSilenceDetected() async {
    if (!_isRecording || _isPaused || _stopping) return;
    if (_segmentSwitching) return;

    _segmentSwitching = true;
    try {
      _stopSmartSegmentControl();

      final elapsed = _segmentStartTime != null
          ? DateTime.now().difference(_segmentStartTime!).inSeconds
          : 0;
      await LogService.info(
        'MEETING',
        'silence detected at ${elapsed}s, soft-cutting segment',
      );

      await _finalizeCurrentSegmentWithTimeout();
      await _startSegmentRecording();
      _startSmartSegmentControl();
    } catch (e) {
      await LogService.error('MEETING', 'smart segment rotation failed: $e');
      await _recoverSegmentRotation(trigger: 'silence');
    } finally {
      _segmentSwitching = false;
    }
  }

  /// 到达硬上限 — 强制截断
  Future<void> _handleHardCut() async {
    if (!_isRecording || _isPaused || _stopping) return;
    if (_segmentSwitching) return;

    _segmentSwitching = true;
    try {
      _stopSmartSegmentControl();

      await LogService.info('MEETING', 'hard cut at ${_hardMaxSeconds}s');

      await _finalizeCurrentSegmentWithTimeout();
      await _startSegmentRecording();
      _startSmartSegmentControl();
    } catch (e) {
      await LogService.error('MEETING', 'hard cut rotation failed: $e');
      await _recoverSegmentRotation(trigger: 'hard-cut');
    } finally {
      _segmentSwitching = false;
    }
  }

  /// 暂停会议录音
  Future<void> pause() async {
    if (!_isRecording || _isPaused) return;

    _refreshRecordingDuration();
    _isPaused = true;
    _pauseStartTime = DateTime.now();
    _segmentTimer?.cancel();
    _segmentTimer = null;
    _stopSmartSegmentControl();

    // 停止当前录音段并保存
    await _finalizeCurrentSegmentWithTimeout();

    _merger?.pause();

    _onStatusChanged.add('paused');
    await LogService.info('MEETING', 'meeting paused');
  }

  /// 恢复会议录音
  Future<void> resume() async {
    if (!_isRecording || !_isPaused) return;

    if (_pauseStartTime != null) {
      _pausedDuration += DateTime.now().difference(_pauseStartTime!);
      _pauseStartTime = null;
    }

    _isPaused = false;

    _merger?.resume();

    // 开始新的录音段
    await _startSegmentRecording();

    // 重新启动分段控制
    _startSegmentControl();

    _onStatusChanged.add('recording');
    await LogService.info('MEETING', 'meeting resumed');
  }

  /// 结束会议录音
  Future<MeetingRecord> stopMeeting() async {
    final inFlight = _stopMeetingFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _stopMeetingInternal();
    _stopMeetingFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_stopMeetingFuture, future)) {
        _stopMeetingFuture = null;
      }
    }
  }

  Future<MeetingRecord> _stopMeetingInternal() async {
    if (!_isRecording || _currentMeeting == null) {
      throw MeetingRecordingException('没有正在录制的会议');
    }

    _stopping = true;
    _segmentTimer?.cancel();
    _segmentTimer = null;
    _stopSmartSegmentControl();
    _durationTimer?.cancel();
    _durationTimer = null;

    // 若分段轮转正在进行，先短暂等待，避免并发 stop 录音器造成异常。
    await _waitUntil(
      () => !_segmentSwitching,
      timeout: const Duration(seconds: 2),
    );

    // 停止当前录音段
    if (!_isPaused) {
      try {
        await _finalizeCurrentSegmentWithTimeout(
          timeout: const Duration(seconds: 10),
        );
      } catch (e) {
        await LogService.error(
          'MEETING',
          'finalize current segment during stop failed: $e',
        );
        // 兜底确保底层录音器已停止，避免后续一直卡在录音状态。
        await _recorder.stopWithTimeout(const Duration(seconds: 2));
      }
    }

    // 等待所有分段处理完成
    _onStatusChanged.add('processing');
    await _waitForProcessingComplete(timeout: const Duration(seconds: 15));

    // 等待当前合并任务完成
    if (_merger != null) {
      await _waitForMergerComplete(timeout: const Duration(seconds: 10));
    }

    // 更新会议状态：进入后台整理中
    final meeting = _currentMeeting!;
    _refreshRecordingDuration();
    meeting.status = MeetingStatus.finalizing;
    meeting.updatedAt = DateTime.now();
    meeting.totalDuration = _recordingDuration;
    await AppDatabase.instance.updateMeeting(meeting);

    _isRecording = false;
    _isPaused = false;
    _onStatusChanged.add('finalizing');

    await LogService.info(
      'MEETING',
      'meeting completed: ${meeting.id}, duration: ${meeting.formattedDuration}',
    );

    final result = meeting;
    _currentMeeting = null;
    return result;
  }

  /// 取消并丢弃当前会议
  Future<void> cancelMeeting() async {
    if (!_isRecording && _currentMeeting == null) return;

    _stopping = true;
    _segmentTimer?.cancel();
    _segmentTimer = null;
    _stopSmartSegmentControl();
    _durationTimer?.cancel();
    _durationTimer = null;

    try {
      await _recorder.stop();
    } catch (_) {}

    if (_currentMeeting != null) {
      await AppDatabase.instance.deleteMeetingById(_currentMeeting!.id);
    }

    _isRecording = false;
    _isPaused = false;
    _currentMeeting = null;
    _processingQueue.clear();
    _onStatusChanged.add('cancelled');

    await LogService.info('MEETING', 'meeting cancelled');
  }

  /// 开始一个新的录音分段
  Future<void> _startSegmentRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw MeetingRecordingException('需要麦克风权限');
    }

    try {
      await _recorder.startWithTimeout(_segmentStartTimeout);
      await LogService.info(
        'MEETING',
        'segment ${_segmentIndex + 1} recording started',
      );
    } catch (e) {
      // 重试一次
      try {
        await _recorder.reset();
        await _recorder.startWithTimeout(_segmentStartTimeout);
        await LogService.info(
          'MEETING',
          'segment ${_segmentIndex + 1} recording started after reset retry',
        );
      } catch (e2) {
        throw MeetingRecordingException('录音启动失败（可能被系统音频设备占用或无权限）: $e2');
      }
    }
  }

  /// 处理分段计时器到期
  Future<void> _handleSegmentTick() async {
    if (!_isRecording || _isPaused || _stopping) return;
    if (_segmentSwitching) return;

    _segmentSwitching = true;
    try {
      await _finalizeCurrentSegmentWithTimeout();
      await _startSegmentRecording();
    } catch (e) {
      await LogService.error('MEETING', 'segment rotation failed: $e');
      await _recoverSegmentRotation(trigger: 'timer');
    } finally {
      _segmentSwitching = false;
    }
  }

  /// 当轮转异常时尝试自愈，避免后续分段中断导致内容丢失。
  Future<void> _recoverSegmentRotation({required String trigger}) async {
    if (!_isRecording || _isPaused || _stopping) return;

    try {
      final stillRecording = await _recorder.isRecording();
      if (!stillRecording) {
        await LogService.info(
          'MEETING',
          'rotation recovery($trigger): recorder not recording, restarting...',
        );
        await _startSegmentRecording();
      }

      if (_useSmartSegment) {
        _stopSmartSegmentControl();
        _startSmartSegmentControl();
      } else {
        _segmentTimer?.cancel();
        _segmentTimer = Timer.periodic(
          Duration(seconds: segmentDurationSeconds),
          (_) => _handleSegmentTick(),
        );
      }

      await LogService.info('MEETING', 'rotation recovery($trigger) succeeded');
    } catch (e) {
      await LogService.error(
        'MEETING',
        'rotation recovery($trigger) failed: $e',
      );
    }
  }

  /// 结束当前录音分段并提交处理队列
  Future<void> _finalizeCurrentSegment() async {
    final audioPath = await _recorder.stop();
    if (audioPath == null) return;

    // 检查文件是否存在且大小合理
    final file = File(audioPath);
    if (!await file.exists()) return;
    final fileSize = await file.length();
    if (fileSize < 1000) {
      // 文件太小，可能是空录音
      await LogService.info(
        'MEETING',
        'segment audio too small ($fileSize bytes), skipping',
      );
      return;
    }

    final now = DateTime.now();
    final actualDuration = _segmentStartTime != null
        ? now.difference(_segmentStartTime!)
        : Duration(seconds: segmentDurationSeconds);
    final segmentStart = _segmentStartTime ?? now.subtract(actualDuration);
    final segment = MeetingSegment(
      id: _uuid.v4(),
      meetingId: _currentMeeting!.id,
      segmentIndex: _segmentIndex,
      startTime: segmentStart,
      duration: actualDuration,
      audioFilePath: audioPath,
      status: SegmentStatus.pending,
    );

    _segmentIndex++;

    // 持久化
    await AppDatabase.instance.insertMeetingSegment(segment);

    // 通知 UI 新分段已就绪（状态 pending）
    _onSegmentReady.add(segment);

    // 加入处理队列
    _processingQueue.add(
      _PendingSegment(segment: segment, audioPath: audioPath),
    );
    _startProcessingWorker();

    await LogService.info(
      'MEETING',
      'segment ${segment.segmentIndex} finalized: $audioPath ($fileSize bytes)',
    );
  }

  Future<void> _finalizeCurrentSegmentWithTimeout({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await _finalizeCurrentSegment().timeout(
      timeout,
      onTimeout: () async {
        await LogService.error(
          'MEETING',
          'finalize segment timeout after ${timeout.inSeconds}s, forcing recorder stop',
        );
        await _recorder.stopWithTimeout(const Duration(seconds: 2));
      },
    );
  }

  /// 启动处理工作线程（如果尚未运行）
  void _startProcessingWorker() {
    if (_processingWorkerRunning) return;
    _processingWorkerRunning = true;
    _runProcessingWorker();
  }

  /// 处理队列中的分段
  Future<void> _runProcessingWorker() async {
    while (_processingQueue.isNotEmpty) {
      final pending = _processingQueue.removeAt(0);
      await _processSegment(pending);
    }
    _processingWorkerRunning = false;
  }

  /// 对一个分段执行 STT + AI 增强
  Future<void> _processSegment(_PendingSegment pending) async {
    final segment = pending.segment;
    final db = AppDatabase.instance;

    try {
      // 1. 语音转文字
      segment.status = SegmentStatus.transcribing;
      await db.updateMeetingSegment(segment);
      _onSegmentUpdated.add(segment);

      if (_sttConfig == null) {
        throw MeetingRecordingException('未配置语音转文字服务');
      }

      final sttService = SttService(_sttConfig!);
      final rawText = await sttService.transcribe(pending.audioPath);

      if (rawText.trim().isEmpty) {
        segment.status = SegmentStatus.done;
        segment.transcription = '';
        await db.updateMeetingSegment(segment);
        _onSegmentUpdated.add(segment);
        return;
      }

      segment.transcription = rawText;

      // 1.5 纠错：拼音匹配 + LLM 同音字纠正
      if (_correctionService != null) {
        try {
          final corrResult = await _correctionService!.correct(rawText);
          if (corrResult.text.trim().isNotEmpty) {
            segment.transcription = corrResult.text;
          }
        } catch (e) {
          await LogService.error(
            'MEETING',
            'correction failed for segment ${segment.segmentIndex}: $e',
          );
          // 纠错失败不影响主流程
        }
      }

      // 2. AI 文字增强（如果启用）
      // M1: 使用纠错后文本（segment.transcription）作为增强输入，
      // 而非原始 rawText，确保增强阶段基于最准确的文本。
      final enhanceInput = segment.transcription ?? rawText;
      if (_aiEnhanceEnabled && _aiConfig != null) {
        segment.status = SegmentStatus.enhancing;
        await db.updateMeetingSegment(segment);
        _onSegmentUpdated.add(segment);

        try {
          final enhancer = AiEnhanceService(_aiConfig!);
          final result = await enhancer.enhance(enhanceInput);
          segment.enhancedText = result.text;

          // 记录会议 AI 增强 token 用量
          if (result.promptTokens > 0 || result.completionTokens > 0) {
            await TokenStatsService.instance.addMeetingTokens(
              promptTokens: result.promptTokens,
              completionTokens: result.completionTokens,
            );
          }
        } catch (e) {
          await LogService.error(
            'MEETING',
            'AI enhance failed for segment ${segment.segmentIndex}: $e',
          );
          // 增强失败不影响转写结果
        }
      }

      segment.status = SegmentStatus.done;
      await db.updateMeetingSegment(segment);
      _onSegmentUpdated.add(segment);

      // 分段 STT 完成且转写非空时，通知合并器触发窗口合并
      if (segment.transcription != null &&
          segment.transcription!.trim().isNotEmpty) {
        _notifyMerger();
      }

      await LogService.info(
        'MEETING',
        'segment ${segment.segmentIndex} processed: ${rawText.length} chars',
      );
    } catch (e) {
      segment.status = SegmentStatus.error;
      segment.errorMessage = e.toString();
      await db.updateMeetingSegment(segment);
      _onSegmentUpdated.add(segment);
      await LogService.error(
        'MEETING',
        'segment ${segment.segmentIndex} processing failed: $e',
      );
    }
  }

  /// 等待所有分段处理完成
  Future<void> _waitForProcessingComplete({Duration? timeout}) async {
    final start = DateTime.now();
    while (_processingWorkerRunning || _processingQueue.isNotEmpty) {
      if (timeout != null && DateTime.now().difference(start) >= timeout) {
        await LogService.error(
          'MEETING',
          'wait processing timeout, continue stopping in background',
        );
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// 重新处理失败的分段
  Future<void> retrySegment(MeetingSegment segment) async {
    if (segment.audioFilePath == null) return;
    final file = File(segment.audioFilePath!);
    if (!await file.exists()) return;

    segment.status = SegmentStatus.pending;
    segment.errorMessage = null;
    await AppDatabase.instance.updateMeetingSegment(segment);
    _onSegmentUpdated.add(segment);

    _processingQueue.add(
      _PendingSegment(segment: segment, audioPath: segment.audioFilePath!),
    );
    _startProcessingWorker();
  }

  /// 通知合并器有新分段完成，传入当前会议的所有分段
  void _notifyMerger() {
    if (_merger == null || _currentMeeting == null) return;

    // 从数据库异步获取所有分段并通知合并器
    AppDatabase.instance
        .getMeetingSegments(_currentMeeting!.id)
        .then((segments) {
          _merger?.onSegmentCompleted(segments);

          // 触发增量摘要：监听 merger.onMergeCompleted 由 _setupMergerIncrementalSummary 处理
        })
        .catchError((e) {
          LogService.error(
            'MEETING',
            'failed to fetch segments for merger: $e',
          );
        });

    // P2: 提前生成标题 — 当第 5 段完成后触发
    if (!_earlyTitleGenerated && _segmentIndex >= 5) {
      _earlyTitleGenerated = true;
      _tryGenerateEarlyTitle();
    }
  }

  /// 监听合并器的 onMergeCompleted，转发给增量摘要服务
  StreamSubscription<MergedNote>? _incrementalSummarySub;

  void setupIncrementalSummaryListener() {
    _incrementalSummarySub?.cancel();
    if (_merger == null || _incrementalSummary == null) return;

    _incrementalSummarySub = _merger!.onMergeCompleted.listen((note) {
      final fullText = _merger!.currentFullText;
      _incrementalSummary!.onMergeCompleted(note, fullText);
    });
  }

  /// P2: 提前生成标题
  Future<void> _tryGenerateEarlyTitle() async {
    if (_currentMeeting == null || _aiConfig == null || !_aiEnhanceEnabled) {
      return;
    }

    // 使用 merger 已合并的文本
    final text = _merger?.currentFullText ?? '';
    if (text.trim().isEmpty) return;

    try {
      const titlePrompt =
          '你是一个会议标题生成助手。根据用户提供的会议内容，生成一个简洁的会议标题。\n\n'
          '## 规则\n'
          '- 标题应概括会议的核心主题，不超过20个字\n'
          '- 只输出标题本身，不要添加引号、书名号、前后缀或任何解释\n'
          '- 使用与内容相同的语言';

      final titleConfig = _aiConfig!.copyWith(prompt: titlePrompt);
      final enhancer = AiEnhanceService(titleConfig);

      final snippet = text.length > 1500 ? text.substring(0, 1500) : text;
      final result = await enhancer.enhance(
        snippet,
        timeout: const Duration(seconds: 15),
      );

      final title = result.text
          .trim()
          .replaceAll(RegExp(r'^["""「」『』《》【】]+'), '')
          .replaceAll(RegExp(r'["""「」『』《》【】]+$'), '')
          .trim();

      if (result.promptTokens > 0 || result.completionTokens > 0) {
        await TokenStatsService.instance.addMeetingTokens(
          promptTokens: result.promptTokens,
          completionTokens: result.completionTokens,
        );
      }

      if (title.isNotEmpty) {
        final finalTitle = title.length > 50 ? title.substring(0, 50) : title;
        _onTitleGenerated.add(finalTitle);
        await LogService.info('MEETING', 'early title generated: $finalTitle');
      }
    } catch (e) {
      await LogService.error('MEETING', 'early title generation failed: $e');
    }
  }

  /// 等待合并器当前任务完成
  Future<void> _waitForMergerComplete({Duration? timeout}) async {
    if (_merger == null) return;
    final start = DateTime.now();
    // 轮询等待合并器完成当前任务
    while (_merger!.isMerging) {
      if (timeout != null && DateTime.now().difference(start) >= timeout) {
        await LogService.error(
          'MEETING',
          'wait merger timeout, continue stopping in background',
        );
        return;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> _waitUntil(
    bool Function() condition, {
    required Duration timeout,
    Duration poll = const Duration(milliseconds: 80),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) return;
      await Future.delayed(poll);
    }
  }

  /// 自愈卡死的录音会话：当内存状态与底层录音器状态不一致时，
  /// 强制清理会话并将会议状态从 recording/paused 纠正为 completed。
  ///
  /// 返回被修复的会议 ID；若无需修复返回 null。
  Future<String?> recoverStuckRecordingIfNeeded() async {
    final hasSessionState =
        _isRecording || _isPaused || _currentMeeting != null;
    if (!hasSessionState) return null;

    bool recorderActuallyRecording = false;
    try {
      recorderActuallyRecording = await _recorder.isRecording();
    } catch (_) {
      recorderActuallyRecording = false;
    }

    final isConsistentActive =
        _isRecording &&
        !_isPaused &&
        _currentMeeting != null &&
        recorderActuallyRecording;
    if (isConsistentActive) {
      return null;
    }

    return forceRecoverRecordingSession();
  }

  /// 强制修复录音会话：无条件尝试停止底层录音器并清理当前会话状态。
  ///
  /// 返回被修复的会议 ID；若当前没有会话返回 null。
  Future<String?> forceRecoverRecordingSession() async {
    final hasSessionState =
        _isRecording || _isPaused || _currentMeeting != null;
    if (!hasSessionState) return null;

    final meeting = _currentMeeting;
    final recoveredMeetingId = meeting?.id;

    _segmentTimer?.cancel();
    _segmentTimer = null;
    _stopSmartSegmentControl();
    _durationTimer?.cancel();
    _durationTimer = null;
    _stopping = false;
    _segmentSwitching = false;
    _processingQueue.clear();

    // 底层录音器兜底停止（忽略异常）
    await _recorder.stopWithTimeout(const Duration(seconds: 1));

    if (meeting != null) {
      if (meeting.status == MeetingStatus.recording ||
          meeting.status == MeetingStatus.paused) {
        meeting.status = MeetingStatus.completed;
        meeting.updatedAt = DateTime.now();
        if (meeting.totalDuration == Duration.zero &&
            _recordingDuration > Duration.zero) {
          meeting.totalDuration = _recordingDuration;
        }
        await AppDatabase.instance.updateMeeting(meeting);
      }
    }

    _isRecording = false;
    _isPaused = false;
    _pauseStartTime = null;
    _currentMeeting = null;
    _stopMeetingFuture = null;
    _onStatusChanged.add('recovered');

    await LogService.error(
      'MEETING',
      'recovered stuck recording session: meetingId=${recoveredMeetingId ?? 'unknown'}',
    );

    return recoveredMeetingId;
  }

  void dispose() {
    _segmentTimer?.cancel();
    _stopSmartSegmentControl();
    _vadService?.dispose();
    _vadService = null;
    _durationTimer?.cancel();
    _incrementalSummarySub?.cancel();
    _incrementalSummarySub = null;
    _incrementalSummary?.dispose();
    _incrementalSummary = null;
    _merger?.dispose();
    _merger = null;
    _onSegmentReady.close();
    _onSegmentUpdated.close();
    _onStatusChanged.close();
    _onDurationChanged.close();
    _onTitleGenerated.close();
    _recorder.dispose();
  }
}

/// 待处理分段
class _PendingSegment {
  final MeetingSegment segment;
  final String audioPath;

  _PendingSegment({required this.segment, required this.audioPath});
}

class MeetingRecordingException implements Exception {
  final String message;
  MeetingRecordingException(this.message);

  @override
  String toString() => message;
}
