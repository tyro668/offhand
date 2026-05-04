/// 时间趋势图的粒度。
enum TrendGranularity { day, week, month }

/// 时间趋势中的单个数据点。
class TrendDataPoint {
  /// 该时段的起始日期（天 = 当天 0:00，周 = 周一，月 = 1 号）。
  final DateTime date;

  /// 该时段内的转录次数。
  final int count;

  /// 该时段内的总录音时长（毫秒）。
  final int durationMs;

  /// 该时段内的总字数。
  final int charCount;

  const TrendDataPoint({
    required this.date,
    required this.count,
    required this.durationMs,
    required this.charCount,
  });
}

/// 仪表盘统计汇总数据。
class DashboardStats {
  // ── 核心汇总 ──
  final int totalCount;
  final int totalDurationMs;
  final int totalCharCount;
  final double avgCharsPerSession;
  final double avgDurationMs;

  // ── 今日 / 本周 / 本月 ──
  final int todayCount;
  final int todayDurationMs;
  final int todayChars;

  final int weekCount;
  final int weekDurationMs;
  final int weekChars;

  final int monthCount;
  final int monthDurationMs;
  final int monthChars;

  // ── 活跃度 ──
  final int currentStreak;
  final DateTime? lastTranscriptionAt;
  final DateTime? mostActiveDate;
  final int mostActiveDateCount;

  // ── 效率 ──
  final double avgCharsPerMinute;

  // ── 时间趋势 ──
  final List<TrendDataPoint> trendData;
  final TrendGranularity trendGranularity;

  // ── 分布 ──
  final Map<String, int> providerDistribution;
  final Map<String, int> modelDistribution;

  // ── AI 增强 token 用量 ──
  final int enhancePromptTokens;
  final int enhanceCompletionTokens;

  // ── 纠错 token 用量 ──
  final int correctionPromptTokens;
  final int correctionCompletionTokens;

  // ── 纠错召回效率 ──
  final int correctionCalls;
  final int correctionLlmCalls;
  final int correctionMatches;
  final int correctionSelected;
  final int correctionReferenceChars;

  // ── 终态回溯 ──
  final int retroCalls;
  final int retroLlmCalls;
  final int retroPromptTokens;
  final int retroCompletionTokens;
  final int retroTextChanged;

  // ── 学习记忆 ──
  final int memoryTotalCount;
  final int memoryPendingCount;
  final int memoryWeakActiveCount;
  final int memoryActiveCount;
  final int memorySuppressedCount;
  final int memoryHighConfidenceCount;
  final int memoryWeekNewCount;
  final int memoryEventsCount;
  final int memoryPromptInjectionCount;
  final int memoryCorrectionHitCount;

  const DashboardStats({
    required this.totalCount,
    required this.totalDurationMs,
    required this.totalCharCount,
    required this.avgCharsPerSession,
    required this.avgDurationMs,
    required this.todayCount,
    required this.todayDurationMs,
    required this.todayChars,
    required this.weekCount,
    required this.weekDurationMs,
    required this.weekChars,
    required this.monthCount,
    required this.monthDurationMs,
    required this.monthChars,
    required this.currentStreak,
    this.lastTranscriptionAt,
    this.mostActiveDate,
    required this.mostActiveDateCount,
    required this.avgCharsPerMinute,
    required this.trendData,
    required this.trendGranularity,
    required this.providerDistribution,
    required this.modelDistribution,
    required this.enhancePromptTokens,
    required this.enhanceCompletionTokens,
    this.correctionPromptTokens = 0,
    this.correctionCompletionTokens = 0,
    this.correctionCalls = 0,
    this.correctionLlmCalls = 0,
    this.correctionMatches = 0,
    this.correctionSelected = 0,
    this.correctionReferenceChars = 0,
    this.retroCalls = 0,
    this.retroLlmCalls = 0,
    this.retroPromptTokens = 0,
    this.retroCompletionTokens = 0,
    this.retroTextChanged = 0,
    this.memoryTotalCount = 0,
    this.memoryPendingCount = 0,
    this.memoryWeakActiveCount = 0,
    this.memoryActiveCount = 0,
    this.memorySuppressedCount = 0,
    this.memoryHighConfidenceCount = 0,
    this.memoryWeekNewCount = 0,
    this.memoryEventsCount = 0,
    this.memoryPromptInjectionCount = 0,
    this.memoryCorrectionHitCount = 0,
  });

  /// 空状态。
  static const empty = DashboardStats(
    totalCount: 0,
    totalDurationMs: 0,
    totalCharCount: 0,
    avgCharsPerSession: 0,
    avgDurationMs: 0,
    todayCount: 0,
    todayDurationMs: 0,
    todayChars: 0,
    weekCount: 0,
    weekDurationMs: 0,
    weekChars: 0,
    monthCount: 0,
    monthDurationMs: 0,
    monthChars: 0,
    currentStreak: 0,
    mostActiveDateCount: 0,
    avgCharsPerMinute: 0,
    trendData: [],
    trendGranularity: TrendGranularity.day,
    providerDistribution: {},
    modelDistribution: {},
    enhancePromptTokens: 0,
    enhanceCompletionTokens: 0,
    correctionPromptTokens: 0,
    correctionCompletionTokens: 0,
    correctionCalls: 0,
    correctionLlmCalls: 0,
    correctionMatches: 0,
    correctionSelected: 0,
    correctionReferenceChars: 0,
    retroCalls: 0,
    retroLlmCalls: 0,
    retroPromptTokens: 0,
    retroCompletionTokens: 0,
    retroTextChanged: 0,
    memoryTotalCount: 0,
    memoryPendingCount: 0,
    memoryWeakActiveCount: 0,
    memoryActiveCount: 0,
    memorySuppressedCount: 0,
    memoryHighConfidenceCount: 0,
    memoryWeekNewCount: 0,
    memoryEventsCount: 0,
    memoryPromptInjectionCount: 0,
    memoryCorrectionHitCount: 0,
  );

  bool get isEmpty =>
      totalCount == 0 && memoryTotalCount == 0 && memoryEventsCount == 0;

  int get enhanceTotalTokens => enhancePromptTokens + enhanceCompletionTokens;

  int get correctionTotalTokens =>
      correctionPromptTokens + correctionCompletionTokens;

  int get retroTotalTokens => retroPromptTokens + retroCompletionTokens;

  double get correctionLlmInvokeRate =>
      correctionCalls > 0 ? correctionLlmCalls / correctionCalls : 0;

  double get correctionSelectedRate =>
      correctionMatches > 0 ? correctionSelected / correctionMatches : 0;

  /// 所有来源的总 token 数
  int get allPromptTokens =>
      enhancePromptTokens + correctionPromptTokens + retroPromptTokens;
  int get allCompletionTokens =>
      enhanceCompletionTokens +
      correctionCompletionTokens +
      retroCompletionTokens;
  int get allTotalTokens => allPromptTokens + allCompletionTokens;

  double get memoryHitRate => memoryPromptInjectionCount > 0
      ? memoryCorrectionHitCount / memoryPromptInjectionCount
      : 0;
}
