import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../database/app_database.dart';
import '../models/dictionary_entry.dart';
import '../models/meeting.dart';
import '../models/merged_note.dart';
import '../models/provider_config.dart';
import '../models/ai_enhance_config.dart';
import '../models/term_context_entry.dart';
import '../services/meeting_recording_service.dart';
import '../services/meeting_export_service.dart';
import '../services/ai_enhance_service.dart';
import '../services/overlay_service.dart';
import '../services/log_service.dart';
import '../services/token_stats_service.dart';
import '../services/pinyin_matcher.dart';
import '../services/incremental_summary_service.dart';

/// 会议记录状态管理
class MeetingProvider extends ChangeNotifier {
  static const String _overlayOwner = 'meeting';
  final MeetingRecordingService _recordingService = MeetingRecordingService();

  /// 所有会议记录列表
  List<MeetingRecord> _meetings = [];
  List<MeetingRecord> get meetings => List.unmodifiable(_meetings);

  /// 当前录制会议的分段列表
  List<MeetingSegment> _currentSegments = [];
  List<MeetingSegment> get currentSegments =>
      List.unmodifiable(_currentSegments);

  /// 录制状态
  bool get isRecording => _recordingService.isRecording;
  bool get isPaused => _recordingService.isPaused;
  MeetingRecord? get currentMeeting => _recordingService.currentMeeting;
  Duration get recordingDuration => _recordingService.recordingDuration;

  /// 状态标识
  String _status = 'idle'; // idle, recording, paused, processing, completed
  String get status => _status;
  String _error = '';
  String get error => _error;

  /// 合并纪要状态字段
  String _mergedNote = '';
  String _streamingText = '';
  bool _isStreamingMerge = false;

  /// 流式中返回 _streamingText，否则返回 _mergedNote
  String get mergedNoteContent =>
      _isStreamingMerge ? _streamingText : _mergedNote;

  /// 是否正在流式合并
  bool get isStreamingMerge => _isStreamingMerge;

  /// Overlay 状态标签（国际化）
  String _startingLabel = '准备中';
  String _recordingLabel = '会议录音中';
  String _processingLabel = '处理中';

  /// 振幅监听
  StreamSubscription<double>? _amplitudeSub;
  Timer? _recordingHeartbeatTimer;
  double _latestAmplitudeLevel = 0.0;

  /// AI 增强配置（会议期间保留，用于结束时合并整理）
  AiEnhanceConfig? _aiConfig;
  bool _aiEnhanceEnabled = false;

  /// 词典提示词后缀（会议期间保留，追加到各专用 prompt 后）
  String _dictionarySuffix = '';

  /// 事件流订阅
  StreamSubscription<MeetingSegment>? _segmentReadySub;
  StreamSubscription<MeetingSegment>? _segmentUpdatedSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<Duration>? _durationSub;

  /// 合并器事件流订阅
  StreamSubscription<MergedNote>? _mergeCompletedSub;
  StreamSubscription<MergeStreamEvent>? _streamChunkSub;

  /// 增量摘要事件流订阅
  StreamSubscription<String>? _incrementalSummarySub;
  StreamSubscription<String>? _incrementalSummaryChunkSub;
  StreamSubscription<void>? _incrementalSummaryUpdateStartedSub;

  /// 提前生成标题事件流订阅
  StreamSubscription<String>? _earlyTitleSub;

  /// 增量摘要内容（录制过程中实时更新）
  String _incrementalSummary = '';
  String get incrementalSummary => _incrementalSummary;

  /// provider 自主跟踪的摘要流式状态（解决 isUpdating 与 notifyListeners 时序错配问题）
  bool _isStreamingSummary = false;

  /// 增量摘要是否正在更新中
  bool get isUpdatingIncrementalSummary =>
      _isStreamingSummary ||
      (_recordingService.incrementalSummary?.isUpdating ?? false);

  /// 后台收尾是否正在执行
  bool _isFinalizingMeeting = false;
  bool get isFinalizingMeeting => _isFinalizingMeeting;

  /// 是否正在执行“停止会议”请求（用于 UI 交互锁定）
  bool _isStoppingMeeting = false;
  bool get isStoppingMeeting => _isStoppingMeeting;

  /// 正在收尾的会议 ID
  String? _finalizingMeetingId;
  String? get finalizingMeetingId => _finalizingMeetingId;

  /// 音频波形流
  Stream<double> get amplitudeStream => _recordingService.amplitudeStream;

  static const String _meetingGroupsSettingKey = 'meeting_groups_v1';
  static const String defaultMeetingGroup = '未分组';
  final Map<String, String> _meetingGroupMap = {};
  bool _meetingGroupsLoaded = false;

  List<String> get allMeetingGroups {
    final groups =
        _meetingGroupMap.values
            .map(_normalizeGroupName)
            .where((g) => g.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (!groups.contains(defaultMeetingGroup)) {
      groups.insert(0, defaultMeetingGroup);
    }
    return groups;
  }

  String getMeetingGroup(String meetingId) {
    return _normalizeGroupName(_meetingGroupMap[meetingId]);
  }

  String _normalizeGroupName(String? group) {
    final trimmed = (group ?? '').trim();
    return trimmed.isEmpty ? defaultMeetingGroup : trimmed;
  }

  Future<void> _ensureMeetingGroupsLoaded() async {
    if (_meetingGroupsLoaded) return;
    final raw = await AppDatabase.instance.getSetting(_meetingGroupsSettingKey);
    if (raw == null || raw.trim().isEmpty) {
      _meetingGroupsLoaded = true;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _meetingGroupMap
          ..clear()
          ..addAll(
            decoded.map(
              (k, v) => MapEntry(k.toString(), _normalizeGroupName('$v')),
            ),
          );
      }
    } catch (_) {
      _meetingGroupMap.clear();
    }
    _meetingGroupsLoaded = true;
  }

  Future<void> _saveMeetingGroups() async {
    await AppDatabase.instance.setSetting(
      _meetingGroupsSettingKey,
      jsonEncode(_meetingGroupMap),
    );
  }

  Future<void> moveMeetingToGroup(String meetingId, String group) async {
    await _ensureMeetingGroupsLoaded();
    _meetingGroupMap[meetingId] = _normalizeGroupName(group);
    await _saveMeetingGroups();
    notifyListeners();
  }

  Future<void> ensureMeetingGroupExists(String group) async {
    await _ensureMeetingGroupsLoaded();
    final normalized = _normalizeGroupName(group);
    if (_meetingGroupMap.values.any(
      (g) => _normalizeGroupName(g) == normalized,
    )) {
      return;
    }
    _meetingGroupMap['__group__$normalized'] = normalized;
    await _saveMeetingGroups();
    notifyListeners();
  }

  Future<void> renameMeetingGroup(String oldName, String newName) async {
    await _ensureMeetingGroupsLoaded();
    final oldGroup = _normalizeGroupName(oldName);
    final targetGroup = _normalizeGroupName(newName);
    if (oldGroup == targetGroup) return;

    final ids = _meetingGroupMap.entries
        .where((e) => _normalizeGroupName(e.value) == oldGroup)
        .map((e) => e.key)
        .toList();
    for (final id in ids) {
      _meetingGroupMap[id] = targetGroup;
    }
    await _saveMeetingGroups();
    notifyListeners();
  }

  Future<void> deleteMeetingGroup(
    String group, {
    String fallbackGroup = defaultMeetingGroup,
  }) async {
    await _ensureMeetingGroupsLoaded();
    final source = _normalizeGroupName(group);
    final fallback = _normalizeGroupName(fallbackGroup);
    for (final entry in _meetingGroupMap.entries.toList()) {
      if (_normalizeGroupName(entry.value) == source) {
        if (entry.key.startsWith('__group__')) {
          _meetingGroupMap.remove(entry.key);
        } else {
          _meetingGroupMap[entry.key] = fallback;
        }
      }
    }
    await _saveMeetingGroups();
    notifyListeners();
  }

  /// 设置 Overlay 状态标签（国际化）
  void setOverlayStateLabels({
    required String starting,
    required String recording,
    required String processing,
  }) {
    _startingLabel = starting;
    _recordingLabel = recording;
    _processingLabel = processing;
  }

  String get _durationStr {
    final m = recordingDuration.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final s = recordingDuration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '$m:$s';
  }

  MeetingProvider() {
    _loadMeetings();
    _setupListeners();
  }

  void _setupListeners() {
    _segmentReadySub = _recordingService.onSegmentReady.listen((segment) {
      _currentSegments.add(segment);
      notifyListeners();
    });

    _segmentUpdatedSub = _recordingService.onSegmentUpdated.listen((segment) {
      final idx = _currentSegments.indexWhere((s) => s.id == segment.id);
      if (idx >= 0) {
        _currentSegments[idx] = segment;
      }
      notifyListeners();
    });

    _statusSub = _recordingService.onStatusChanged.listen((status) {
      _status = status;
      if (status == 'recording') {
        _startRecordingHeartbeat();
      } else {
        _stopRecordingHeartbeat();
      }
      notifyListeners();
    });

    _durationSub = _recordingService.onDurationChanged.listen((_) {
      notifyListeners();
    });
  }

  void _startRecordingHeartbeat() {
    _recordingHeartbeatTimer?.cancel();

    void tick() {
      if (!isRecording || isPaused) return;
      notifyListeners();
      unawaited(
        OverlayService.updateOverlay(
          state: 'recording',
          duration: _durationStr,
          level: _latestAmplitudeLevel,
          stateLabel: _recordingLabel,
          owner: _overlayOwner,
        ),
      );
    }

    tick();
    _recordingHeartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      tick();
    });
  }

  void _stopRecordingHeartbeat() {
    _recordingHeartbeatTimer?.cancel();
    _recordingHeartbeatTimer = null;
  }

  /// 监听合并器的 onStreamChunk 和 onMergeCompleted 事件流
  void _setupMergerListeners() {
    // 先取消旧的订阅
    _mergeCompletedSub?.cancel();
    _streamChunkSub?.cancel();
    _incrementalSummarySub?.cancel();
    _incrementalSummaryChunkSub?.cancel();
    _incrementalSummaryUpdateStartedSub?.cancel();
    _earlyTitleSub?.cancel();

    final merger = _recordingService.merger;
    if (merger == null) return;

    _streamChunkSub = merger.onStreamChunk.listen((event) {
      if (!event.isComplete) {
        _streamingText += event.chunk;
        _isStreamingMerge = true;
        notifyListeners();
      } else {
        _isStreamingMerge = false;
        notifyListeners();
      }
    });

    _mergeCompletedSub = merger.onMergeCompleted.listen((note) {
      _mergedNote = _recordingService.currentFullText;
      if (_mergedNote.trim().isEmpty) {
        _mergedNote = note.content;
      }
      _streamingText = '';
      _isStreamingMerge = false;
      notifyListeners();
    });

    // 设置增量摘要 listener
    _recordingService.setupIncrementalSummaryListener();

    // 监听增量摘要更新
    final incrSummary = _recordingService.incrementalSummary;
    if (incrSummary != null) {
      _incrementalSummaryUpdateStartedSub = incrSummary.onSummaryUpdateStarted
          .listen((_) {
            _isStreamingSummary = true;
            _incrementalSummary = '';
            notifyListeners();
          });

      _incrementalSummaryChunkSub = incrSummary.onSummaryChunk.listen((chunk) {
        if (chunk.isEmpty) return;
        _incrementalSummary += chunk;
        notifyListeners();
      });

      _incrementalSummarySub = incrSummary.onSummaryUpdated.listen((summary) {
        _incrementalSummary = summary;
        _isStreamingSummary = false;
        notifyListeners();
      });
    }

    // 监听提前生成的标题
    _earlyTitleSub = _recordingService.onTitleGenerated.listen((title) {
      if (title.isNotEmpty && _recordingService.currentMeeting != null) {
        final meeting = _recordingService.currentMeeting!;
        if (_isDefaultTitle(meeting.title)) {
          meeting.title = title;
          // 持久化标题
          AppDatabase.instance.updateMeeting(meeting).catchError((e) {
            LogService.error('MEETING_PROVIDER', 'save early title failed: $e');
          });
          notifyListeners();
        }
      }
    });
  }

  /// 取消合并器事件流订阅
  void _cancelMergerListeners() {
    _mergeCompletedSub?.cancel();
    _mergeCompletedSub = null;
    _streamChunkSub?.cancel();
    _streamChunkSub = null;
    _incrementalSummarySub?.cancel();
    _incrementalSummarySub = null;
    _incrementalSummaryChunkSub?.cancel();
    _incrementalSummaryChunkSub = null;
    _incrementalSummaryUpdateStartedSub?.cancel();
    _incrementalSummaryUpdateStartedSub = null;
    _isStreamingSummary = false;
    _earlyTitleSub?.cancel();
    _earlyTitleSub = null;
  }

  /// 加载所有会议记录
  Future<void> _loadMeetings() async {
    try {
      await _recordingService.recoverStuckRecordingIfNeeded();
      if (!isRecording) {
        _stopRecordingHeartbeat();
      }
      await _ensureMeetingGroupsLoaded();
      _meetings = await AppDatabase.instance.getAllMeetings();
      // 修复因崩溃/异常导致的残留 recording/paused 状态
      // finalizing 表示后台整理中，不应在这里强制改为 completed
      final activeId = _recordingService.currentMeeting?.id;
      for (final m in _meetings) {
        final isStaleActiveStatus =
            (m.status == MeetingStatus.recording ||
                m.status == MeetingStatus.paused) &&
            m.id != activeId;
        if (isStaleActiveStatus) {
          m.status = MeetingStatus.completed;
          await AppDatabase.instance.updateMeeting(m);
        }
      }
      notifyListeners();
    } catch (e) {
      await LogService.error('MEETING_PROVIDER', 'load meetings failed: $e');
    }
  }

  /// 刷新会议列表
  Future<void> refreshMeetings() async {
    await _loadMeetings();
  }

  /// 手动修复卡住的录音会话。
  /// 返回修复条数（包含会话态与数据库状态修复）。
  Future<int> manualRecoverStuckRecording() async {
    var fixedCount = 0;

    final recoveredId = await _recordingService.forceRecoverRecordingSession();
    if (recoveredId != null) {
      fixedCount++;
    }

    final allMeetings = await AppDatabase.instance.getAllMeetings();
    for (final meeting in allMeetings) {
      if (meeting.status == MeetingStatus.recording ||
          meeting.status == MeetingStatus.paused) {
        meeting.status = MeetingStatus.completed;
        meeting.updatedAt = DateTime.now();
        await AppDatabase.instance.updateMeeting(meeting);
        fixedCount++;
      }
    }

    await _loadMeetings();
    return fixedCount;
  }

  /// 统一重算历史会议内容：
  /// - 按分段优先 enhancedText 合并为会议纪要
  /// - 基于统一后的纪要重新生成总结
  /// - 默认标题时尝试重新生成标题
  ///
  /// 返回成功更新的会议数量。
  Future<int> rebuildHistoricalMeetingsFromSegments({
    required AiEnhanceConfig aiConfig,
    String dictionarySuffix = '',
  }) async {
    final meetings = await AppDatabase.instance.getAllMeetings();
    var updatedCount = 0;

    final oldEnabled = _aiEnhanceEnabled;
    final oldConfig = _aiConfig;
    final oldDictSuffix = _dictionarySuffix;

    _aiEnhanceEnabled = true;
    _aiConfig = aiConfig;
    _dictionarySuffix = dictionarySuffix;

    try {
      for (final meeting in meetings) {
        if (meeting.status == MeetingStatus.recording ||
            meeting.status == MeetingStatus.paused) {
          continue;
        }

        final segments = await AppDatabase.instance.getMeetingSegments(
          meeting.id,
        );
        segments.sort((a, b) => a.segmentIndex.compareTo(b.segmentIndex));

        final mergedText = segments
            .map((s) => (s.displayText ?? '').trim())
            .where((text) => text.isNotEmpty)
            .join('\n')
            .trim();

        if (mergedText.isEmpty) {
          continue;
        }

        try {
          final polished = await _polishMergedText(mergedText);
          final finalText = polished.trim().isNotEmpty
              ? polished.trim()
              : mergedText;
          final summary = await _generateSummary(finalText);

          meeting.fullTranscription = finalText;
          if (summary.isNotEmpty) {
            meeting.summary = summary;
          }

          if (_isDefaultTitle(meeting.title)) {
            final autoTitle = await _generateTitle(finalText);
            if (autoTitle.isNotEmpty) {
              meeting.title = autoTitle;
            }
          }

          meeting.updatedAt = DateTime.now();
          await AppDatabase.instance.updateMeeting(meeting);
          updatedCount++;
        } catch (e) {
          await LogService.error(
            'MEETING',
            'rebuild historical meeting failed id=${meeting.id}: $e',
          );
        }
      }
    } finally {
      _aiEnhanceEnabled = oldEnabled;
      _aiConfig = oldConfig;
      _dictionarySuffix = oldDictSuffix;
    }

    await _loadMeetings();
    return updatedCount;
  }

  /// 手动覆盖会话术语映射（由词典页编辑触发）。
  void applySessionGlossaryOverride(String original, String corrected) {
    _recordingService.applySessionGlossaryOverride(original, corrected);
  }

  /// 开始新会议
  Future<MeetingRecord> startMeeting({
    String? title,
    required SttProviderConfig sttConfig,
    AiEnhanceConfig? aiConfig,
    bool aiEnhanceEnabled = false,
    int? segmentSeconds,
    int windowSize = 5,
    String dictionarySuffix = '',
    List<DictionaryEntry> dictionaryEntries = const [],
    List<TermContextEntry> termContextEntries = const [],
    PinyinMatcher? pinyinMatcher,
    String? correctionPrompt,
    int maxReferenceEntries = 15,
    double minCandidateScore = 0.30,
  }) async {
    _error = '';
    _currentSegments = [];
    _aiConfig = aiConfig;
    _aiEnhanceEnabled = aiEnhanceEnabled;
    _dictionarySuffix = dictionarySuffix;

    // 重置合并纪要状态
    _mergedNote = '';
    _streamingText = '';
    _isStreamingMerge = false;
    _incrementalSummary = '';
    _isFinalizingMeeting = false;
    _finalizingMeetingId = null;

    try {
      // 显示 overlay — starting 状态
      unawaited(
        OverlayService.showOverlay(
          state: 'starting',
          duration: '00:00',
          level: 0.0,
          stateLabel: _startingLabel,
          owner: _overlayOwner,
        ),
      );

      final meeting = await _recordingService.startMeeting(
        title: title,
        sttConfig: sttConfig,
        aiConfig: aiConfig,
        aiEnhanceEnabled: aiEnhanceEnabled,
        segmentSeconds: segmentSeconds,
        windowSize: windowSize,
        dictionaryEntries: dictionaryEntries,
        termContextEntries: termContextEntries,
        pinyinMatcher: pinyinMatcher,
        correctionPrompt: correctionPrompt,
        maxReferenceEntries: maxReferenceEntries,
        minCandidateScore: minCandidateScore,
      );

      // 监听合并器事件流
      _setupMergerListeners();

      // 切换到 recording 状态
      unawaited(
        OverlayService.showOverlay(
          state: 'recording',
          duration: '00:00',
          level: 0.0,
          stateLabel: _recordingLabel,
          owner: _overlayOwner,
        ),
      );

      // 监听音频振幅，实时更新 overlay
      _amplitudeSub?.cancel();
      _amplitudeSub = _recordingService.amplitudeStream.listen((level) {
        _latestAmplitudeLevel = level;
        OverlayService.updateOverlay(
          state: 'recording',
          duration: _durationStr,
          level: level,
          stateLabel: _recordingLabel,
          owner: _overlayOwner,
        );
      });
      _startRecordingHeartbeat();

      await _loadMeetings();
      notifyListeners();
      return meeting;
    } catch (e) {
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 暂停录音
  Future<void> pauseMeeting() async {
    try {
      await _recordingService.pause();
      _amplitudeSub?.cancel();
      _amplitudeSub = null;
      _stopRecordingHeartbeat();
      // 暂停时隐藏 overlay
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 恢复录音
  Future<void> resumeMeeting() async {
    try {
      await _recordingService.resume();
      // 恢复时重新显示 overlay
      unawaited(
        OverlayService.showOverlay(
          state: 'recording',
          duration: _durationStr,
          level: 0.0,
          stateLabel: _recordingLabel,
          owner: _overlayOwner,
        ),
      );
      // 重新监听振幅
      _amplitudeSub?.cancel();
      _amplitudeSub = _recordingService.amplitudeStream.listen((level) {
        _latestAmplitudeLevel = level;
        OverlayService.updateOverlay(
          state: 'recording',
          duration: _durationStr,
          level: level,
          stateLabel: _recordingLabel,
          owner: _overlayOwner,
        );
      });
      _startRecordingHeartbeat();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 结束录音
  /// 快速结束会议：复用 Merger 已合并的全文和增量摘要，立即返回。
  /// 后台异步执行尾部 polish、最终摘要和标题确认。
  Future<MeetingRecord> stopMeetingFast() async {
    _isStoppingMeeting = true;
    notifyListeners();
    try {
      _amplitudeSub?.cancel();
      _amplitudeSub = null;
      _stopRecordingHeartbeat();

      // 点击结束后立即隐藏录音标识 overlay，不展示处理进度
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      await LogService.info(
        'MEETING_PROVIDER',
        'stop requested, progress moved to meeting page ($_processingLabel)',
      );

      // 先快照增量摘要服务
      final incrService = _recordingService.incrementalSummary;

      // 快照 Merger 已合并的全文
      final cachedFullText = _recordingService.currentFullText.trim();
      final cachedMergedNote = _mergedNote.trim();
      final cachedLastCoveredIndex = _recordingService.lastCoveredSegmentIndex;
      final cachedSummary = incrService?.currentSummary ?? '';

      _cancelMergerListeners();

      final meeting = await _recordingService.stopMeeting();

      // 从已落库分段构建即时文稿兜底，避免停止后会议内容为空。
      final persistedSegments = await AppDatabase.instance.getMeetingSegments(
        meeting.id,
      );
      persistedSegments.sort(
        (a, b) => a.segmentIndex.compareTo(b.segmentIndex),
      );
      final immediateBuffer = StringBuffer();
      for (final seg in persistedSegments) {
        final text = (seg.displayText ?? '').trim();
        if (text.isNotEmpty) {
          immediateBuffer.writeln(text);
        }
      }
      final immediateText = immediateBuffer.toString().trim();

      // 使用 Merger 已合并的全文作为即时文稿
      if (cachedFullText.isNotEmpty) {
        meeting.fullTranscription = cachedFullText;
      } else if (cachedMergedNote.isNotEmpty) {
        meeting.fullTranscription = cachedMergedNote;
      } else if (immediateText.isNotEmpty) {
        meeting.fullTranscription = immediateText;
      }

      // 使用增量摘要作为即时总结
      if (cachedSummary.isNotEmpty) {
        meeting.summary = cachedSummary;
      }

      // 点击结束后立即标记为“会议整理中”
      meeting.status = MeetingStatus.finalizing;
      meeting.updatedAt = DateTime.now();

      await AppDatabase.instance.updateMeeting(meeting);

      // 隐藏 overlay，让用户立即进入详情
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      await _loadMeetings();

      // 启动后台精细化
      _finalizeMeetingInBackground(
        meeting.id,
        incrService,
        cachedFullText,
        cachedLastCoveredIndex,
      );

      return meeting;
    } catch (e) {
      final recoveredId = await _recordingService
          .recoverStuckRecordingIfNeeded();
      if (recoveredId != null) {
        await _loadMeetings();
        final recoveredMeeting = await AppDatabase.instance.getMeetingById(
          recoveredId,
        );
        if (recoveredMeeting != null) {
          return recoveredMeeting;
        }
      }
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      _error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _isStoppingMeeting = false;
      notifyListeners();
    }
  }

  /// 后台精细化：尾部 polish、最终摘要更新、标题确认（并行执行）
  Future<void> _finalizeMeetingInBackground(
    String meetingId,
    IncrementalSummaryService? incrService,
    String cachedFullText,
    int cachedLastCoveredIndex,
  ) async {
    _isFinalizingMeeting = true;
    _finalizingMeetingId = meetingId;
    notifyListeners();

    try {
      final meeting = await AppDatabase.instance.getMeetingById(meetingId);
      if (meeting == null) return;

      // 获取所有分段并等待其处理落库，避免 stop 后立即读取导致内容为空。
      final segments = await _collectSegmentsForFinalization(meetingId);

      final buffer = StringBuffer();
      for (final seg in segments) {
        final text = (seg.displayText ?? '').trim();
        if (text.isNotEmpty) {
          buffer.writeln(text);
        }
      }
      final fullRawText = buffer.toString().trim();
      final hasCachedMerged = cachedFullText.isNotEmpty;
      final tailText = segments
          .where((s) => s.segmentIndex > cachedLastCoveredIndex)
          .map((s) => (s.displayText ?? '').trim())
          .where((text) => text.isNotEmpty)
          .join('\n');

      final summaryInput = hasCachedMerged
          ? [
              cachedFullText,
              tailText,
            ].where((s) => s.trim().isNotEmpty).join('\n\n').trim()
          : fullRawText;

      if (summaryInput.isEmpty) {
        // 尚无可整理内容时，保持 finalizing，等待后续分段处理完成后再次触发整理。
        await LogService.error(
          'MEETING',
          'finalization deferred: empty summary input for $meetingId',
        );
        return;
      }

      final Future<String> polishFuture;
      if (hasCachedMerged && tailText.trim().isEmpty) {
        polishFuture = Future.value(cachedFullText);
      } else if (hasCachedMerged) {
        polishFuture = _polishMergedText(tailText).then((polishedTail) {
          final tail = polishedTail.trim().isNotEmpty ? polishedTail : tailText;
          if (tail.trim().isEmpty) return cachedFullText;
          return '$cachedFullText\n\n$tail'.trim();
        });
      } else {
        polishFuture = _polishMergedText(fullRawText);
      }

      // 并行执行: 尾部增量 polish + 最终摘要 + 标题生成
      final summaryFuture = incrService != null
          ? incrService.finalUpdate(summaryInput)
          : _generateSummary(summaryInput);
      final titleFuture = _isDefaultTitle(meeting.title)
          ? _generateTitle(summaryInput)
          : Future.value('');

      final results = await Future.wait([
        polishFuture,
        summaryFuture,
        titleFuture,
      ]);

      final polished = results[0];
      final summary = results[1];
      final title = results[2];

      if (polished.isNotEmpty) {
        meeting.fullTranscription = polished;
      }
      if (summary.isNotEmpty) {
        meeting.summary = summary;
      }
      if (title.isNotEmpty) {
        meeting.title = title;
      }

      // 后台整理完成后切回“已完成”
      meeting.status = MeetingStatus.completed;
      meeting.updatedAt = DateTime.now();
      await AppDatabase.instance.updateMeeting(meeting);
      await _loadMeetings();

      await LogService.info(
        'MEETING',
        'background finalization complete for $meetingId',
      );
    } catch (e) {
      await LogService.error('MEETING', 'background finalization failed: $e');
    } finally {
      _isFinalizingMeeting = false;
      _finalizingMeetingId = null;
      notifyListeners();
    }
  }

  Future<List<MeetingSegment>> _collectSegmentsForFinalization(
    String meetingId,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    List<MeetingSegment> latest = [];

    while (true) {
      latest = await AppDatabase.instance.getMeetingSegments(meetingId);
      latest.sort((a, b) => a.segmentIndex.compareTo(b.segmentIndex));

      final hasText = latest.any(
        (segment) => (segment.displayText ?? '').trim().isNotEmpty,
      );
      final hasPending = latest.any(
        (segment) =>
            segment.status == SegmentStatus.pending ||
            segment.status == SegmentStatus.transcribing ||
            segment.status == SegmentStatus.enhancing,
      );

      if (!hasPending && latest.isNotEmpty) {
        return latest;
      }
      if (hasText && DateTime.now().isAfter(deadline)) {
        return latest;
      }
      if (DateTime.now().isAfter(deadline)) {
        return latest;
      }

      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  /// 旧版同步停止会议（兼容回退）
  Future<MeetingRecord> stopMeeting() async {
    try {
      _amplitudeSub?.cancel();
      _amplitudeSub = null;
      _stopRecordingHeartbeat();
      _cancelMergerListeners();

      // 点击结束后立即隐藏录音标识 overlay，不展示处理进度
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      await LogService.info(
        'MEETING_PROVIDER',
        'stop requested(sync), progress moved to meeting page ($_processingLabel)',
      );

      final meeting = await _recordingService.stopMeeting();

      // 合并所有分段文字为完整文稿
      final segments = await AppDatabase.instance.getMeetingSegments(
        meeting.id,
      );
      segments.sort((a, b) => a.segmentIndex.compareTo(b.segmentIndex));

      final buffer = StringBuffer();
      for (final seg in segments) {
        final text = (seg.displayText ?? '').trim();
        if (text.isNotEmpty) {
          buffer.writeln(text);
        }
      }

      final mergedText = buffer.toString().trim();
      if (mergedText.isNotEmpty) {
        // 使用大模型对合并文本进行整理
        final polished = await _polishMergedText(mergedText);
        meeting.fullTranscription = polished;

        // 自动生成会议总结
        final summary = await _generateSummary(polished);
        if (summary.isNotEmpty) {
          meeting.summary = summary;
        }

        // 如果标题仍是默认标题，则根据内容自动生成
        if (_isDefaultTitle(meeting.title)) {
          final autoTitle = await _generateTitle(polished);
          if (autoTitle.isNotEmpty) {
            meeting.title = autoTitle;
          }
        }

        await AppDatabase.instance.updateMeeting(meeting);
      }

      // 处理完成，隐藏 overlay
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      await _loadMeetings();
      return meeting;
    } catch (e) {
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 使用大模型整理合并后的会议文稿
  Future<String> _polishMergedText(String rawText) async {
    if (!_aiEnhanceEnabled || _aiConfig == null) {
      return rawText;
    }

    try {
      await LogService.info(
        'MEETING',
        'polishing merged text with LLM, length=${rawText.length}',
      );

      // 加载会议合并专用提示词
      final mergePrompt = await rootBundle.loadString(
        'assets/prompts/meeting_merge_prompt.md',
      );

      // 使用会议合并提示词覆盖默认提示词，并追加词典后缀
      final mergeConfig = _aiConfig!.copyWith(
        prompt: mergePrompt + _dictionarySuffix,
      );
      final enhancer = AiEnhanceService(mergeConfig);
      final result = await enhancer.enhance(
        rawText,
        timeout: const Duration(seconds: 120),
      );

      // 记录 token 用量
      if (result.promptTokens > 0 || result.completionTokens > 0) {
        await TokenStatsService.instance.addMeetingTokens(
          promptTokens: result.promptTokens,
          completionTokens: result.completionTokens,
        );
      }

      await LogService.info(
        'MEETING',
        'polish complete, result length=${result.text.length}',
      );

      // 如果 LLM 返回了有效内容则使用，否则回退到原始合并文本
      return result.text.trim().isNotEmpty ? result.text.trim() : rawText;
    } catch (e) {
      await LogService.error('MEETING', 'polish merged text failed: $e');
      // 整理失败不影响基本功能，回退到原始合并文本
      return rawText;
    }
  }

  /// 使用大模型生成会议总结
  Future<String> _generateSummary(String content) async {
    if (!_aiEnhanceEnabled || _aiConfig == null) return '';

    try {
      await LogService.info(
        'MEETING',
        'generating summary from content, length=${content.length}',
      );

      // 加载会议总结专用提示词
      final summaryPrompt = await rootBundle.loadString(
        'assets/prompts/meeting_summary_prompt.md',
      );

      final summaryConfig = _aiConfig!.copyWith(
        prompt: summaryPrompt + _dictionarySuffix,
      );
      final enhancer = AiEnhanceService(summaryConfig);
      final result = await enhancer.enhance(
        content,
        timeout: const Duration(seconds: 120),
      );

      // 记录 token 用量
      if (result.promptTokens > 0 || result.completionTokens > 0) {
        await TokenStatsService.instance.addMeetingTokens(
          promptTokens: result.promptTokens,
          completionTokens: result.completionTokens,
        );
      }

      await LogService.info(
        'MEETING',
        'summary generated, length=${result.text.length}',
      );
      return result.text.trim();
    } catch (e) {
      await LogService.error('MEETING', 'generate summary failed: $e');
      return '';
    }
  }

  /// 重新生成会议总结（供外部调用）
  Future<void> regenerateSummary(String meetingId) async {
    await regenerateSummaryByContent(meetingId);
  }

  /// 基于指定会议纪要内容重新生成会议总结。
  ///
  /// 当 [content] 为空时，将回退到数据库中该会议的 fullTranscription。
  /// 返回值表示是否成功生成并更新了总结。
  Future<bool> regenerateSummaryByContent(
    String meetingId, {
    String? content,
    AiEnhanceConfig? aiConfig,
    String dictionarySuffix = '',
  }) async {
    final meeting = await AppDatabase.instance.getMeetingById(meetingId);
    if (meeting == null) return false;

    final mergedContent = (content ?? meeting.fullTranscription ?? '').trim();
    if (mergedContent.isEmpty) return false;

    // 优先使用显式传入的 AI 配置，避免依赖会话态配置
    final config = aiConfig ?? _aiConfig;
    if (config == null) return false;

    final oldEnabled = _aiEnhanceEnabled;
    final oldConfig = _aiConfig;
    final oldDictSuffix = _dictionarySuffix;
    try {
      _aiEnhanceEnabled = true;
      _aiConfig = config;
      _dictionarySuffix = dictionarySuffix;

      final summary = await _generateSummary(mergedContent);
      if (summary.isEmpty) return false;

      meeting.summary = summary;
      meeting.fullTranscription = mergedContent;
      meeting.updatedAt = DateTime.now();
      await AppDatabase.instance.updateMeeting(meeting);
      await _loadMeetings();
      return true;
    } finally {
      _aiEnhanceEnabled = oldEnabled;
      _aiConfig = oldConfig;
      _dictionarySuffix = oldDictSuffix;
    }
  }

  /// 流式重新生成会议总结，逐块返回文本
  Stream<String> regenerateSummaryStream(
    String meetingId, {
    required AiEnhanceConfig aiConfig,
    String dictionarySuffix = '',
  }) async* {
    final meeting = await AppDatabase.instance.getMeetingById(meetingId);
    if (meeting == null) return;

    final content = (meeting.fullTranscription ?? '').trim();
    if (content.isEmpty) return;

    yield* regenerateSummaryStreamByContent(
      meetingId,
      content: content,
      aiConfig: aiConfig,
      dictionarySuffix: dictionarySuffix,
    );
  }

  /// 基于显式内容流式生成会议总结，逐块返回文本。
  Stream<String> regenerateSummaryStreamByContent(
    String meetingId, {
    required String content,
    required AiEnhanceConfig aiConfig,
    String dictionarySuffix = '',
  }) async* {
    final meeting = await AppDatabase.instance.getMeetingById(meetingId);
    if (meeting == null) return;

    final mergedContent = content.trim();
    if (mergedContent.isEmpty) return;

    await LogService.info(
      'MEETING',
      'streaming summary regeneration, content length=${mergedContent.length}',
    );

    final summaryPrompt = await rootBundle.loadString(
      'assets/prompts/meeting_summary_prompt.md',
    );

    final summaryConfig = aiConfig.copyWith(
      prompt: summaryPrompt + dictionarySuffix,
    );
    final enhancer = AiEnhanceService(summaryConfig);

    final buffer = StringBuffer();
    await for (final chunk in enhancer.enhanceStream(
      mergedContent,
      timeout: const Duration(seconds: 120),
    )) {
      buffer.write(chunk);
      yield chunk;
    }

    // 流式结束后持久化
    final fullSummary = buffer.toString().trim();
    if (fullSummary.isNotEmpty) {
      meeting.summary = fullSummary;
      meeting.fullTranscription = mergedContent;
      meeting.updatedAt = DateTime.now();
      await AppDatabase.instance.updateMeeting(meeting);
      await _loadMeetings();
    }

    await LogService.info(
      'MEETING',
      'streaming summary complete, length=${fullSummary.length}',
    );
  }

  /// 判断标题是否为系统默认生成的标题（格式：会议 M/D HH:mm）
  bool _isDefaultTitle(String title) {
    return RegExp(r'^会议 \d{1,2}/\d{1,2} \d{1,2}:\d{2}$').hasMatch(title.trim());
  }

  /// 使用大模型根据会议内容生成简短标题
  Future<String> _generateTitle(String content) async {
    if (!_aiEnhanceEnabled || _aiConfig == null) return '';

    try {
      await LogService.info('MEETING', 'generating title from content');

      const titlePrompt =
          '你是一个会议标题生成助手。根据用户提供的会议内容，生成一个简洁的会议标题。\n\n'
          '## 规则\n'
          '- 标题应概括会议的核心主题，不超过20个字\n'
          '- 只输出标题本身，不要添加引号、书名号、前后缀或任何解释\n'
          '- 使用与内容相同的语言';

      final titleConfig = _aiConfig!.copyWith(prompt: titlePrompt);
      final enhancer = AiEnhanceService(titleConfig);

      // 只取前1500字作为上下文，避免 token 浪费
      final snippet = content.length > 1500
          ? content.substring(0, 1500)
          : content;
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

      await LogService.info('MEETING', 'generated title: $title');
      return title.length > 50 ? title.substring(0, 50) : title;
    } catch (e) {
      await LogService.error('MEETING', 'generate title failed: $e');
      return '';
    }
  }

  /// 取消录音
  Future<void> cancelMeeting() async {
    try {
      _amplitudeSub?.cancel();
      _amplitudeSub = null;
      _cancelMergerListeners();
      await _recordingService.cancelMeeting();
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      _currentSegments = [];
      await _loadMeetings();
      notifyListeners();
    } catch (e) {
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 获取指定会议的分段列表
  Future<List<MeetingSegment>> getSegments(String meetingId) async {
    return await AppDatabase.instance.getMeetingSegments(meetingId);
  }

  /// 更新会议标题
  Future<void> updateMeetingTitle(String meetingId, String title) async {
    final meeting = await AppDatabase.instance.getMeetingById(meetingId);
    if (meeting == null) return;

    meeting.title = title;
    meeting.updatedAt = DateTime.now();
    await AppDatabase.instance.updateMeeting(meeting);
    await _loadMeetings();
  }

  /// 更新会议摘要
  Future<void> updateMeetingSummary(String meetingId, String summary) async {
    final meeting = await AppDatabase.instance.getMeetingById(meetingId);
    if (meeting == null) return;

    meeting.summary = summary;
    meeting.updatedAt = DateTime.now();
    await AppDatabase.instance.updateMeeting(meeting);
    await _loadMeetings();
  }

  /// 更新会议完整文稿
  Future<void> updateMeetingFullTranscription(
    String meetingId,
    String text,
  ) async {
    final meeting = await AppDatabase.instance.getMeetingById(meetingId);
    if (meeting == null) return;

    meeting.fullTranscription = text;
    meeting.updatedAt = DateTime.now();
    await AppDatabase.instance.updateMeeting(meeting);
    await _loadMeetings();
  }

  /// 删除会议
  Future<void> deleteMeeting(String meetingId) async {
    final meeting = await AppDatabase.instance.getMeetingById(meetingId);
    final isActiveMeeting = _recordingService.currentMeeting?.id == meetingId;

    if (isActiveMeeting ||
        meeting?.status == MeetingStatus.recording ||
        meeting?.status == MeetingStatus.paused) {
      _amplitudeSub?.cancel();
      _amplitudeSub = null;
      _cancelMergerListeners();
      await _recordingService.forceRecoverRecordingSession();
      unawaited(OverlayService.hideOverlay(owner: _overlayOwner));

      _currentSegments = [];
      _mergedNote = '';
      _streamingText = '';
      _incrementalSummary = '';
      _isStreamingMerge = false;
      _isStreamingSummary = false;
      _isStoppingMeeting = false;
      _status = 'idle';
    }

    await _ensureMeetingGroupsLoaded();
    _meetingGroupMap.remove(meetingId);
    await _saveMeetingGroups();
    await AppDatabase.instance.deleteMeetingById(meetingId);
    await _loadMeetings();
  }

  /// 导出会议为纯文本
  Future<String> exportAsText(String meetingId) async {
    final meeting = await AppDatabase.instance.getMeetingById(meetingId);
    if (meeting == null) return '';
    return MeetingExportService.exportAsText(meeting);
  }

  /// 导出会议为 Markdown
  Future<String> exportAsMarkdown(String meetingId) async {
    final meeting = await AppDatabase.instance.getMeetingById(meetingId);
    if (meeting == null) return '';
    return MeetingExportService.exportAsMarkdown(meeting);
  }

  /// 复制会议全文到剪贴板
  Future<void> copyFullText(String meetingId) async {
    final meeting = await AppDatabase.instance.getMeetingById(meetingId);
    if (meeting == null) return;
    await MeetingExportService.copyToClipboard(meeting.fullTranscription ?? '');
  }

  /// 重试失败的分段
  Future<void> retrySegment(MeetingSegment segment) async {
    await _recordingService.retrySegment(segment);
  }

  /// 更新分段文本（手动编辑）
  Future<void> updateSegmentText(String segmentId, String newText) async {
    final db = AppDatabase.instance;
    // We need to find and update the segment
    // Since we have the segment in _currentSegments or can get from DB
    for (var i = 0; i < _currentSegments.length; i++) {
      if (_currentSegments[i].id == segmentId) {
        _currentSegments[i].enhancedText = newText;
        await db.updateMeetingSegment(_currentSegments[i]);
        notifyListeners();
        return;
      }
    }
  }

  @override
  void dispose() {
    _segmentReadySub?.cancel();
    _segmentUpdatedSub?.cancel();
    _statusSub?.cancel();
    _durationSub?.cancel();
    _amplitudeSub?.cancel();
    _stopRecordingHeartbeat();
    _cancelMergerListeners();
    _recordingService.dispose();
    super.dispose();
  }
}
