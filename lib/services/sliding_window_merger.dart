import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;

import '../models/ai_enhance_config.dart';
import '../models/meeting.dart';
import '../models/merged_note.dart';
import 'ai_enhance_service.dart';
import 'log_service.dart';

/// 滑动窗口合并器，在会议录制过程中以滑动窗口方式选取相邻分段文本
/// 并提交 AI 进行跨段合并增强，支持流式输出。
class SlidingWindowMerger {
  /// 窗口大小，范围 [2, 10]
  final int windowSize;

  /// AI 增强配置
  final AiEnhanceConfig aiConfig;
  final String promptSuffix;

  /// 当前合并任务标识，用于取消控制
  int _currentTaskId = 0;

  /// 当前是否有合并任务在执行
  bool _isMerging = false;

  /// 是否有合并任务正在执行
  bool get isMerging => _isMerging;

  /// 是否暂停
  bool _paused = false;

  /// 已完成的合并纪要缓存（按窗口范围存储）
  final List<MergedNote> _mergedNotes = [];

  /// 最近一次收到的、可用于构建完整文稿的有效分段（按 segmentIndex 升序）
  List<MeetingSegment> _latestValidSegments = const [];

  /// 当前最优合并文稿（去重拼接所有缓存的 MergedNote）
  String get currentFullText => _buildFullText();

  /// 已覆盖到的最大分段索引（-1 表示尚无合并结果）
  int get lastCoveredSegmentIndex {
    if (_mergedNotes.isEmpty) return -1;
    return _mergedNotes
        .map((n) => n.endSegmentIndex)
        .reduce((a, b) => a > b ? a : b);
  }

  /// 合并结果事件流（完整结果）
  final StreamController<MergedNote> _mergeCompletedController =
      StreamController<MergedNote>.broadcast();

  /// 流式输出事件流（逐 token）
  final StreamController<MergeStreamEvent> _streamChunkController =
      StreamController<MergeStreamEvent>.broadcast();

  /// 合并完成事件流
  Stream<MergedNote> get onMergeCompleted => _mergeCompletedController.stream;

  /// 流式 chunk 事件流
  Stream<MergeStreamEvent> get onStreamChunk => _streamChunkController.stream;

  SlidingWindowMerger({
    required this.windowSize,
    required this.aiConfig,
    this.promptSuffix = '',
  });

  String _segmentDisplayText(MeetingSegment segment) {
    return (segment.displayText ?? '').trim();
  }

  /// 当新分段完成转写时调用，触发窗口选取和合并。
  /// [allSegments] 为当前会议的所有分段列表。
  ///
  /// 并发控制：递增 [_currentTaskId] 使前一个正在执行的合并任务自动失效，
  /// 新任务以 fire-and-forget 方式异步执行，不阻塞调用方。
  Future<void> onSegmentCompleted(List<MeetingSegment> allSegments) async {
    // 暂停状态下不触发新合并任务
    if (_paused) return;

    _latestValidSegments =
        allSegments
            .where(
              (s) =>
                  s.status == SegmentStatus.done &&
                  _segmentDisplayText(s).isNotEmpty,
            )
            .toList()
          ..sort((a, b) => a.segmentIndex.compareTo(b.segmentIndex));

    final windowSegments = selectWindow(allSegments);
    if (windowSegments.isEmpty) return;

    // 递增 taskId，使任何正在执行的旧任务在下次检查时自动失效
    _currentTaskId++;
    final taskId = _currentTaskId;

    _isMerging = true;

    // fire-and-forget：异步执行合并，不阻塞调用方
    unawaited(
      _executeMerge(windowSegments, taskId).whenComplete(() {
        // 仅当此任务仍是最新任务时才清除 merging 标志
        if (taskId == _currentTaskId) {
          _isMerging = false;
        }
      }),
    );
  }

  /// 选取合并窗口：以最新完成转写的分段为末端，
  /// 向前选取 [windowSize] 个有效分段（转写文本非空），
  /// 跳过空文本分段并从更早分段补充，按 segmentIndex 升序排列。
  List<MeetingSegment> selectWindow(List<MeetingSegment> segments) {
    // Filter to segments that completed STT with non-empty display text
    final validSegments = segments
        .where(
          (s) =>
              s.status == SegmentStatus.done &&
              _segmentDisplayText(s).isNotEmpty,
        )
        .toList();

    if (validSegments.isEmpty) {
      return [];
    }

    // Sort by segmentIndex ascending to ensure consistent ordering
    validSegments.sort((a, b) => a.segmentIndex.compareTo(b.segmentIndex));

    // Take the last windowSize valid segments (or all if fewer)
    final startIndex = validSegments.length > windowSize
        ? validSegments.length - windowSize
        : 0;

    return validSegments.sublist(startIndex);
  }

  /// 执行合并增强：将窗口内分段文本拼接后提交 AI 服务。
  /// 云端模型使用 SSE 流式输出，失败时回退到批量模式重试一次。
  /// AI 调用完全失败时，将窗口内各分段原始转写文本拼接作为降级 MergedNote。
  Future<void> _executeMerge(
    List<MeetingSegment> windowSegments,
    int taskId,
  ) async {
    if (windowSegments.isEmpty) return;

    final startIdx = windowSegments.first.segmentIndex;
    final endIdx = windowSegments.last.segmentIndex;

    // 1. 拼接窗口内所有分段文本（优先 enhancedText）
    final concatenatedText = windowSegments
        .map(_segmentDisplayText)
        .where((t) => t.trim().isNotEmpty)
        .join('\n');

    if (concatenatedText.trim().isEmpty) return;

    await LogService.info(
      'MERGER',
      'executeMerge taskId=$taskId segments=[$startIdx..$endIdx] textLength=${concatenatedText.length}',
    );

    // 2. 加载 meeting_merge_prompt 并构建 AiEnhanceConfig
    String mergePrompt;
    try {
      mergePrompt = await rootBundle.loadString(
        'assets/prompts/meeting_merge_prompt.md',
      );
    } catch (e) {
      await LogService.error('MERGER', 'failed to load merge prompt: $e');
      mergePrompt = aiConfig.prompt;
    }

    final mergeConfig = aiConfig.copyWith(prompt: mergePrompt + promptSuffix);
    final enhancer = AiEnhanceService(mergeConfig);

    // 3. 判断云端 vs 本地模型
    final isLocal =
        mergeConfig.baseUrl.trim().isEmpty && mergeConfig.apiKey.trim().isEmpty;

    if (isLocal) {
      // 本地模型：批量模式，完成后一次性推送
      try {
        final result = await enhancer.enhance(concatenatedText);

        // 检查 taskId，若已被取消则丢弃结果
        if (taskId != _currentTaskId) {
          await LogService.info(
            'MERGER',
            'task $taskId cancelled, discarding local result',
          );
          return;
        }

        final content = result.text.trim().isNotEmpty
            ? result.text.trim()
            : concatenatedText;

        _emitStreamChunk(content, startIdx, endIdx, isComplete: true);
        _emitMergedNote(startIdx, endIdx, content);

        await LogService.info('MERGER', 'local merge complete taskId=$taskId');
      } catch (e) {
        // 本地模型调用失败：降级为原始文本拼接
        await LogService.error(
          'MERGER',
          'local enhance failed, degrading to raw text: $e',
        );

        if (taskId != _currentTaskId) return;

        _emitStreamChunk(concatenatedText, startIdx, endIdx, isComplete: true);
        _emitMergedNote(startIdx, endIdx, concatenatedText);
      }
    } else {
      // 云端模型：SSE 流式输出，逐 chunk 推送
      try {
        final buffer = StringBuffer();

        await for (final chunk in enhancer.enhanceStream(concatenatedText)) {
          // 每个 chunk 前检查 taskId
          if (taskId != _currentTaskId) {
            await LogService.info(
              'MERGER',
              'task $taskId cancelled during streaming',
            );
            return;
          }

          buffer.write(chunk);
          _emitStreamChunk(chunk, startIdx, endIdx, isComplete: false);
        }

        // 流式完成后检查 taskId
        if (taskId != _currentTaskId) {
          await LogService.info(
            'MERGER',
            'task $taskId cancelled after streaming',
          );
          return;
        }

        final fullContent = buffer.toString().trim().isNotEmpty
            ? buffer.toString().trim()
            : concatenatedText;

        // 发送完成标记
        _emitStreamChunk('', startIdx, endIdx, isComplete: true);
        _emitMergedNote(startIdx, endIdx, fullContent);

        await LogService.info(
          'MERGER',
          'streaming merge complete taskId=$taskId',
        );
      } catch (e) {
        // SSE 流式请求失败：回退到批量模式重试一次
        await LogService.error(
          'MERGER',
          'streaming enhance failed, falling back to batch mode: $e',
        );

        if (taskId != _currentTaskId) return;

        try {
          final batchResult = await enhancer.enhance(concatenatedText);

          if (taskId != _currentTaskId) {
            await LogService.info(
              'MERGER',
              'task $taskId cancelled, discarding batch fallback result',
            );
            return;
          }

          final content = batchResult.text.trim().isNotEmpty
              ? batchResult.text.trim()
              : concatenatedText;

          _emitStreamChunk(content, startIdx, endIdx, isComplete: true);
          _emitMergedNote(startIdx, endIdx, content);

          await LogService.info(
            'MERGER',
            'batch fallback merge complete taskId=$taskId',
          );
        } catch (batchError) {
          // 批量模式也失败：降级为原始文本拼接
          await LogService.error(
            'MERGER',
            'batch fallback also failed, degrading to raw text: $batchError',
          );

          if (taskId != _currentTaskId) return;

          _emitStreamChunk(
            concatenatedText,
            startIdx,
            endIdx,
            isComplete: true,
          );
          _emitMergedNote(startIdx, endIdx, concatenatedText);
        }
      }
    }
  }

  /// 向 onStreamChunk 推送一个流式事件
  void _emitStreamChunk(
    String chunk,
    int startIdx,
    int endIdx, {
    required bool isComplete,
  }) {
    if (!_streamChunkController.isClosed) {
      _streamChunkController.add(
        MergeStreamEvent(
          chunk: chunk,
          startSegmentIndex: startIdx,
          endSegmentIndex: endIdx,
          isComplete: isComplete,
        ),
      );
    }
  }

  /// 创建 MergedNote 并推送到 onMergeCompleted，同时缓存
  void _emitMergedNote(int startIdx, int endIdx, String content) {
    final mergedNote = MergedNote(
      startSegmentIndex: startIdx,
      endSegmentIndex: endIdx,
      content: content,
      createdAt: DateTime.now(),
    );

    // 缓存到 _mergedNotes
    _mergedNotes.add(mergedNote);

    if (!_mergeCompletedController.isClosed) {
      _mergeCompletedController.add(mergedNote);
    }
  }

  /// 对缓存的 MergedNote 做贪心去重拼接，构建当前最优合并文稿。
  /// 选取覆盖范围互不重叠（或递增覆盖）的 note 集合，按 segmentIndex 升序排列。
  String _buildFullText() {
    // 以全部已完成分段为主构建完整文稿，避免仅保留最后一个窗口内容。
    if (_latestValidSegments.isNotEmpty) {
      final text = _latestValidSegments
          .map(_segmentDisplayText)
          .where((t) => t.isNotEmpty)
          .join('\n');
      if (text.trim().isNotEmpty) return text.trim();
    }

    // 兜底：若尚未拿到有效分段，再退回到合并缓存。
    if (_mergedNotes.isEmpty) return '';
    final sorted = List<MergedNote>.from(_mergedNotes)
      ..sort((a, b) => a.endSegmentIndex.compareTo(b.endSegmentIndex));
    for (var i = sorted.length - 1; i >= 0; i--) {
      final content = sorted[i].content.trim();
      if (content.isNotEmpty) return content;
    }
    return '';
  }

  /// 暂停合并触发
  void pause() {
    _paused = true;
    LogService.info('MERGER', 'merger paused');
  }

  /// 恢复合并触发
  void resume() {
    _paused = false;
    LogService.info('MERGER', 'merger resumed');
  }

  /// 释放资源
  void dispose() {
    _mergeCompletedController.close();
    _streamChunkController.close();
    LogService.info('MERGER', 'merger disposed');
  }
}
