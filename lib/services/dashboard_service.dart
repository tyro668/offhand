import 'dart:convert';

import '../database/app_database.dart';
import '../models/dashboard_stats.dart';
import '../models/memory_event.dart';
import '../models/memory_item.dart';
import 'correction_stats_service.dart';
import 'token_stats_service.dart';

/// 仪表盘统计计算服务。
///
/// 从数据库获取全部转录记录，在 Dart 层计算各维度统计指标。
class DashboardService {
  DashboardService._();
  static final instance = DashboardService._();
  static const _adaptiveMemoryItemsKey = 'adaptive_memory_items_v1';
  static const _memoryEventsKey = 'memory_events_v1';

  final _db = AppDatabase.instance;

  /// 计算完整的仪表盘统计数据。
  Future<DashboardStats> computeStats({
    TrendGranularity granularity = TrendGranularity.day,
  }) async {
    final all = await _db.getAllHistory();

    // ── 核心汇总 ──
    final totalCount = all.length;
    int totalDurationMs = 0;
    int totalCharCount = 0;
    for (final t in all) {
      totalDurationMs += t.duration.inMilliseconds;
      totalCharCount += t.text.length;
    }
    final avgCharsPerSession = totalCount > 0
        ? totalCharCount / totalCount
        : 0.0;
    final avgDurationMs = totalCount > 0 ? totalDurationMs / totalCount : 0.0;

    // ── 效率 ──
    final totalMinutes = totalDurationMs / 60000.0;
    final avgCharsPerMinute = totalMinutes > 0
        ? totalCharCount / totalMinutes
        : 0.0;

    // ── 今日 / 本周 / 本月 ──
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    // 本周一
    final weekStart = todayStart.subtract(
      Duration(days: todayStart.weekday - 1),
    );
    final monthStart = DateTime(now.year, now.month, 1);

    int todayCount = 0, todayDurationMs = 0, todayChars = 0;
    int weekCount = 0, weekDurationMs = 0, weekChars = 0;
    int monthCount = 0, monthDurationMs = 0, monthChars = 0;

    // ── 分布 ──
    final providerDist = <String, int>{};
    final modelDist = <String, int>{};

    // ── 按天分组（用于活跃度和趋势计算） ──
    final dailyMap = <DateTime, _DailyAccumulator>{};

    for (final t in all) {
      final dayKey = DateTime(
        t.createdAt.year,
        t.createdAt.month,
        t.createdAt.day,
      );
      final acc = dailyMap.putIfAbsent(dayKey, _DailyAccumulator.new);
      acc.count++;
      acc.durationMs += t.duration.inMilliseconds;
      acc.charCount += t.text.length;

      // 今日 / 本周 / 本月
      if (!t.createdAt.isBefore(todayStart)) {
        todayCount++;
        todayDurationMs += t.duration.inMilliseconds;
        todayChars += t.text.length;
      }
      if (!t.createdAt.isBefore(weekStart)) {
        weekCount++;
        weekDurationMs += t.duration.inMilliseconds;
        weekChars += t.text.length;
      }
      if (!t.createdAt.isBefore(monthStart)) {
        monthCount++;
        monthDurationMs += t.duration.inMilliseconds;
        monthChars += t.text.length;
      }

      // 分布
      final pKey = t.provider.isEmpty ? 'Unknown' : t.provider;
      providerDist[pKey] = (providerDist[pKey] ?? 0) + 1;
      final mKey = t.model.isEmpty ? 'Unknown' : t.model;
      modelDist[mKey] = (modelDist[mKey] ?? 0) + 1;
    }

    // ── 活跃度 ──
    final lastTranscriptionAt = all.isEmpty
        ? null
        : all.first.createdAt; // getAll 按 DESC 排序
    final sortedDays = dailyMap.keys.toList()..sort();

    // 最活跃的一天
    DateTime? mostActiveDate;
    int mostActiveDateCount = 0;
    for (final entry in dailyMap.entries) {
      if (entry.value.count > mostActiveDateCount) {
        mostActiveDateCount = entry.value.count;
        mostActiveDate = entry.key;
      }
    }

    // 连续使用天数 streak（从今天或昨天往回数）
    final currentStreak = _computeStreak(sortedDays, todayStart);

    // ── 时间趋势 ──
    final trendData = _buildTrendData(
      dailyMap: dailyMap,
      granularity: granularity,
      now: now,
    );

    // ── AI 增强 token 用量 ──
    final tokenStats = await TokenStatsService.instance.getTokens();

    // ── 纠错 token 用量 ──
    final correctionStats = await CorrectionStatsService.instance.getSnapshot();

    // ── 学习记忆 ──
    final learningStats = await _computeLearningStats(weekStart: weekStart);

    return DashboardStats(
      totalCount: totalCount,
      totalDurationMs: totalDurationMs,
      totalCharCount: totalCharCount,
      avgCharsPerSession: avgCharsPerSession,
      avgDurationMs: avgDurationMs,
      todayCount: todayCount,
      todayDurationMs: todayDurationMs,
      todayChars: todayChars,
      weekCount: weekCount,
      weekDurationMs: weekDurationMs,
      weekChars: weekChars,
      monthCount: monthCount,
      monthDurationMs: monthDurationMs,
      monthChars: monthChars,
      currentStreak: currentStreak,
      lastTranscriptionAt: lastTranscriptionAt,
      mostActiveDate: mostActiveDate,
      mostActiveDateCount: mostActiveDateCount,
      avgCharsPerMinute: avgCharsPerMinute,
      trendData: trendData,
      trendGranularity: granularity,
      providerDistribution: providerDist,
      modelDistribution: modelDist,
      enhancePromptTokens: tokenStats.promptTokens,
      enhanceCompletionTokens: tokenStats.completionTokens,
      correctionPromptTokens: correctionStats.promptTokens,
      correctionCompletionTokens: correctionStats.completionTokens,
      correctionCalls: correctionStats.calls,
      correctionLlmCalls: correctionStats.llmCalls,
      correctionMatches: correctionStats.matches,
      correctionSelected: correctionStats.selected,
      correctionReferenceChars: correctionStats.referenceChars,
      retroCalls: correctionStats.retroCalls,
      retroLlmCalls: correctionStats.retroLlmCalls,
      retroPromptTokens: correctionStats.retroPromptTokens,
      retroCompletionTokens: correctionStats.retroCompletionTokens,
      retroTextChanged: correctionStats.retroTextChanged,
      memoryTotalCount: learningStats.totalCount,
      memoryPendingCount: learningStats.pendingCount,
      memoryWeakActiveCount: learningStats.weakActiveCount,
      memoryActiveCount: learningStats.activeCount,
      memorySuppressedCount: learningStats.suppressedCount,
      memoryHighConfidenceCount: learningStats.highConfidenceCount,
      memoryWeekNewCount: learningStats.weekNewCount,
      memoryEventsCount: learningStats.eventsCount,
      memoryPromptInjectionCount: learningStats.promptInjectionCount,
      memoryCorrectionHitCount: learningStats.correctionHitCount,
    );
  }

  Future<_LearningStats> _computeLearningStats({
    required DateTime weekStart,
  }) async {
    try {
      final memoryJson = await _db.getSetting(_adaptiveMemoryItemsKey);
      final eventJson = await _db.getSetting(_memoryEventsKey);
      final memoryItems = _decodeMemoryItems(memoryJson);
      final memoryEvents = _decodeMemoryEvents(eventJson);

      var pending = 0;
      var weakActive = 0;
      var active = 0;
      var suppressed = 0;
      var highConfidence = 0;
      var weekNew = 0;
      var promptInjections = 0;
      var correctionHits = 0;

      for (final item in memoryItems) {
        switch (item.status) {
          case MemoryItemStatus.pending:
            pending++;
            break;
          case MemoryItemStatus.weakActive:
            weakActive++;
            break;
          case MemoryItemStatus.active:
            active++;
            break;
          case MemoryItemStatus.suppressed:
            suppressed++;
            break;
          case MemoryItemStatus.archived:
            break;
        }
        if (!item.createdAt.isBefore(weekStart)) weekNew++;
        if (item.status == MemoryItemStatus.weakActive &&
            item.stats.evidenceCount >= 3 &&
            item.stats.negativeCount == 0 &&
            item.confidence >= 0.8) {
          highConfidence++;
        }
        promptInjections += item.stats.promptInjectionCount;
        correctionHits += item.stats.correctionHitCount;
      }

      return _LearningStats(
        totalCount: memoryItems
            .where((item) => item.status != MemoryItemStatus.archived)
            .length,
        pendingCount: pending,
        weakActiveCount: weakActive,
        activeCount: active,
        suppressedCount: suppressed,
        highConfidenceCount: highConfidence,
        weekNewCount: weekNew,
        eventsCount: memoryEvents.length,
        promptInjectionCount: promptInjections,
        correctionHitCount: correctionHits,
      );
    } catch (_) {
      return const _LearningStats();
    }
  }

  List<MemoryItem> _decodeMemoryItems(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final list = json.decode(raw) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map(MemoryItem.fromJson)
        .where((item) => item.displayText.isNotEmpty)
        .toList(growable: false);
  }

  List<MemoryEvent> _decodeMemoryEvents(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final list = json.decode(raw) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map(MemoryEvent.fromJson)
        .where((event) => event.id.isNotEmpty)
        .toList(growable: false);
  }

  // ── 连续天数 ──

  int _computeStreak(List<DateTime> sortedDays, DateTime todayStart) {
    if (sortedDays.isEmpty) return 0;

    final daySet = sortedDays.toSet();
    // 如果今天有数据从今天开始，否则从昨天开始
    var checkDay = todayStart;
    if (!daySet.contains(checkDay)) {
      checkDay = checkDay.subtract(const Duration(days: 1));
    }
    int streak = 0;
    while (daySet.contains(checkDay)) {
      streak++;
      checkDay = checkDay.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // ── 趋势数据构建 ──

  List<TrendDataPoint> _buildTrendData({
    required Map<DateTime, _DailyAccumulator> dailyMap,
    required TrendGranularity granularity,
    required DateTime now,
  }) {
    switch (granularity) {
      case TrendGranularity.day:
        return _buildDailyTrend(dailyMap, now, periods: 14);
      case TrendGranularity.week:
        return _buildWeeklyTrend(dailyMap, now, periods: 12);
      case TrendGranularity.month:
        return _buildMonthlyTrend(dailyMap, now, periods: 6);
    }
  }

  List<TrendDataPoint> _buildDailyTrend(
    Map<DateTime, _DailyAccumulator> dailyMap,
    DateTime now, {
    required int periods,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(periods, (i) {
      final day = today.subtract(Duration(days: periods - 1 - i));
      final acc = dailyMap[day];
      return TrendDataPoint(
        date: day,
        count: acc?.count ?? 0,
        durationMs: acc?.durationMs ?? 0,
        charCount: acc?.charCount ?? 0,
      );
    });
  }

  List<TrendDataPoint> _buildWeeklyTrend(
    Map<DateTime, _DailyAccumulator> dailyMap,
    DateTime now, {
    required int periods,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final thisWeekMonday = today.subtract(Duration(days: today.weekday - 1));

    return List.generate(periods, (i) {
      final weekStart = thisWeekMonday.subtract(
        Duration(days: 7 * (periods - 1 - i)),
      );
      int count = 0, durationMs = 0, charCount = 0;
      for (int d = 0; d < 7; d++) {
        final day = weekStart.add(Duration(days: d));
        final acc = dailyMap[day];
        if (acc != null) {
          count += acc.count;
          durationMs += acc.durationMs;
          charCount += acc.charCount;
        }
      }
      return TrendDataPoint(
        date: weekStart,
        count: count,
        durationMs: durationMs,
        charCount: charCount,
      );
    });
  }

  List<TrendDataPoint> _buildMonthlyTrend(
    Map<DateTime, _DailyAccumulator> dailyMap,
    DateTime now, {
    required int periods,
  }) {
    return List.generate(periods, (i) {
      final offset = periods - 1 - i;
      int year = now.year;
      int month = now.month - offset;
      while (month <= 0) {
        month += 12;
        year--;
      }
      final monthStart = DateTime(year, month, 1);
      final nextMonth = DateTime(year, month + 1, 1);

      int count = 0, durationMs = 0, charCount = 0;
      for (final entry in dailyMap.entries) {
        if (!entry.key.isBefore(monthStart) && entry.key.isBefore(nextMonth)) {
          count += entry.value.count;
          durationMs += entry.value.durationMs;
          charCount += entry.value.charCount;
        }
      }
      return TrendDataPoint(
        date: monthStart,
        count: count,
        durationMs: durationMs,
        charCount: charCount,
      );
    });
  }
}

/// 每日累加器（内部使用）。
class _DailyAccumulator {
  int count = 0;
  int durationMs = 0;
  int charCount = 0;
}

class _LearningStats {
  final int totalCount;
  final int pendingCount;
  final int weakActiveCount;
  final int activeCount;
  final int suppressedCount;
  final int highConfidenceCount;
  final int weekNewCount;
  final int eventsCount;
  final int promptInjectionCount;
  final int correctionHitCount;

  const _LearningStats({
    this.totalCount = 0,
    this.pendingCount = 0,
    this.weakActiveCount = 0,
    this.activeCount = 0,
    this.suppressedCount = 0,
    this.highConfidenceCount = 0,
    this.weekNewCount = 0,
    this.eventsCount = 0,
    this.promptInjectionCount = 0,
    this.correctionHitCount = 0,
  });
}
