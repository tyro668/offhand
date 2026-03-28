import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/correction_change_log.dart';
import '../../models/dashboard_stats.dart';
import '../../services/correction_change_log_service.dart';
import '../../services/dashboard_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardStats _stats = DashboardStats.empty;
  List<CorrectionChangeLog> _correctionLogs = const [];
  bool _correctionLogsExpanded = false;
  bool _loading = true;
  TrendGranularity _granularity = TrendGranularity.day;
  int _periodTab = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        DashboardService.instance.computeStats(granularity: _granularity),
        CorrectionChangeLogService.instance.getRecent(limit: 20),
      ]);
      final stats = results[0] as DashboardStats;
      final correctionLogs = results[1] as List<CorrectionChangeLog>;
      if (mounted) {
        setState(() {
          _stats = stats;
          _correctionLogs = correctionLogs;
          if (showLoading) _loading = false;
        });
      }
    } catch (_) {
      if (mounted && showLoading) {
        setState(() => _loading = false);
      }
    }
  }

  void _setGranularity(TrendGranularity g) {
    if (g == _granularity) return;
    _granularity = g;
    _loadStats(showLoading: false);
  }

  ColorScheme get _cs => Theme.of(context).colorScheme;
  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _stats.isEmpty
        ? _buildEmptyState()
        : _buildContent();
  }

  // ─────────────── Empty State ───────────────

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _cs.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bar_chart_rounded,
              size: 36,
              color: _cs.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _l10n.noDataYet,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _buildCorrectionChangeLogsSection(),
        ],
      ),
    );
  }

  // ─────────────── Main Content ───────────────

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroStats(),
          const SizedBox(height: 16),
          _buildPeriodAndActivityRow(),
          const SizedBox(height: 16),
          _buildTokenSection(),
          const SizedBox(height: 16),
          _buildCorrectionEfficiencySection(),
          const SizedBox(height: 16),
          _buildCorrectionChangeLogsSection(),
          const SizedBox(height: 16),
          _buildRetrospectiveSection(),
          const SizedBox(height: 16),
          _buildGlossarySection(),
          const SizedBox(height: 16),
          _buildTrendSection(),
          const SizedBox(height: 16),
          _buildDistributionSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─────────────── Hero Stats ───────────────

  Widget _buildHeroStats() {
    final items = [
      _HeroData(
        icon: Icons.mic_none_rounded,
        label: _l10n.totalTranscriptions,
        value: _formatNumber(_stats.totalCount),
        gradient: [_cs.primary, _cs.primary.withValues(alpha: 0.7)],
      ),
      _HeroData(
        icon: Icons.timer_outlined,
        label: _l10n.totalRecordingTime,
        value: _formatDuration(_stats.totalDurationMs),
        gradient: [_cs.tertiary, _cs.tertiary.withValues(alpha: 0.7)],
      ),
      _HeroData(
        icon: Icons.text_fields_rounded,
        label: _l10n.totalCharacters,
        value: _formatNumber(_stats.totalCharCount),
        gradient: [_cs.secondary, _cs.secondary.withValues(alpha: 0.7)],
      ),
      _HeroData(
        icon: Icons.speed_rounded,
        label: _l10n.charsPerMinute,
        value: _stats.avgCharsPerMinute.toStringAsFixed(1),
        gradient: [Colors.orange, Colors.orange.shade300],
      ),
    ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items.map((item) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: item == items.last ? 0 : 12),
              child: _buildHeroCard(item),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeroCard(_HeroData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            data.gradient[0].withValues(alpha: 0.08),
            data.gradient[1].withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: data.gradient[0].withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: data.gradient[0].withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(data.icon, size: 15, color: data.gradient[0]),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _cs.onSurface,
                letterSpacing: -0.5,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            style: TextStyle(fontSize: 11, color: _cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ─────────────── Period + Activity Row ───────────────

  Widget _buildPeriodAndActivityRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 920;
        if (compact) {
          return Column(
            children: [
              _buildPeriodCard(),
              const SizedBox(height: 12),
              _buildActivityCard(),
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: _buildPeriodCard()),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: _buildActivityCard()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPeriodCard() {
    final tabs = [_l10n.today, _l10n.thisWeek, _l10n.thisMonth];
    int count, durationMs, chars;
    switch (_periodTab) {
      case 1:
        count = _stats.weekCount;
        durationMs = _stats.weekDurationMs;
        chars = _stats.weekChars;
        break;
      case 2:
        count = _stats.monthCount;
        durationMs = _stats.monthDurationMs;
        chars = _stats.monthChars;
        break;
      default:
        count = _stats.todayCount;
        durationMs = _stats.todayDurationMs;
        chars = _stats.todayChars;
    }

    return _Card(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period tabs as chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(tabs.length, (i) {
              final selected = _periodTab == i;
              return Material(
                color: selected ? _cs.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _periodTab = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: selected
                          ? null
                          : Border.all(color: _cs.outlineVariant),
                    ),
                    child: Text(
                      tabs[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected ? _cs.onPrimary : _cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          // Stats in a row with dividers
          Row(
            children: [
              Expanded(
                child: _PeriodStat(
                  value: '$count',
                  label: _l10n.transcriptionCount,
                  color: _cs.primary,
                  cs: _cs,
                ),
              ),
              _buildVerticalDivider(),
              Expanded(
                child: _PeriodStat(
                  value: _formatDuration(durationMs),
                  label: _l10n.recordingTime,
                  color: _cs.tertiary,
                  cs: _cs,
                ),
              ),
              _buildVerticalDivider(),
              Expanded(
                child: _PeriodStat(
                  value: _formatNumber(chars),
                  label: _l10n.characters,
                  color: _cs.secondary,
                  cs: _cs,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Averages row
          Divider(color: _cs.outlineVariant.withValues(alpha: 0.5), height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.short_text_rounded,
                    size: 14,
                    color: _cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_l10n.avgCharsPerSession}: ${_stats.avgCharsPerSession.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.av_timer_rounded,
                    size: 14,
                    color: _cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_l10n.avgRecordingDuration}: ${_formatDuration(_stats.avgDurationMs.round())}',
                    style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: _cs.outlineVariant.withValues(alpha: 0.5),
    );
  }

  Widget _buildActivityCard() {
    return _Card(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _l10n.activity,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _buildActivityRow(
            Icons.local_fire_department_rounded,
            Colors.orange,
            _l10n.currentStreak,
            _l10n.streakDays(_stats.currentStreak),
          ),
          const SizedBox(height: 14),
          _buildActivityRow(
            Icons.access_time_rounded,
            _cs.tertiary,
            _l10n.lastUsed,
            _stats.lastTranscriptionAt != null
                ? _formatTimeAgo(_stats.lastTranscriptionAt!)
                : '-',
          ),
          const SizedBox(height: 14),
          _buildActivityRow(
            Icons.emoji_events_rounded,
            Colors.amber.shade700,
            _l10n.mostActiveDay,
            _stats.mostActiveDate != null
                ? '${DateFormat('M/d').format(_stats.mostActiveDate!)} (${_l10n.sessions(_stats.mostActiveDateCount)})'
                : '-',
          ),
        ],
      ),
    );
  }

  Widget _buildActivityRow(
    IconData icon,
    Color color,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────── Trend Chart ───────────────

  Widget _buildTrendSection() {
    final granLabels = {
      TrendGranularity.day: _l10n.day,
      TrendGranularity.week: _l10n.week,
      TrendGranularity.month: _l10n.month,
    };

    return _Card(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 540;
              final chips = Wrap(
                spacing: 4,
                runSpacing: 4,
                children: TrendGranularity.values.map((g) {
                  final selected = _granularity == g;
                  return Material(
                    color: selected
                        ? _cs.secondaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _setGranularity(g),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: Text(
                          granLabels[g]!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? _cs.onSecondaryContainer
                                : _cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _l10n.usageTrend,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    chips,
                  ],
                );
              }

              return Row(
                children: [
                  Text(
                    _l10n.usageTrend,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _cs.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  chips,
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          SizedBox(height: 180, child: _buildBarChart()),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    final data = _stats.trendData;
    if (data.isEmpty) return const SizedBox();

    final maxY = data.fold<int>(0, (m, d) => d.count > m ? d.count : m);
    final effectiveMaxY = (maxY == 0 ? 5 : maxY) * 1.2;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: effectiveMaxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIdx, rod, rodIdx) {
              final dp = data[groupIdx];
              return BarTooltipItem(
                '${_l10n.sessions(dp.count)}\n${_formatNumber(dp.charCount)} ${_l10n.characters}',
                TextStyle(color: _cs.onInverseSurface, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => value == meta.max
                  ? const SizedBox.shrink()
                  : Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        fontSize: 10,
                        color: _cs.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= data.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _formatTrendLabel(data[idx].date),
                    style: TextStyle(fontSize: 9, color: _cs.onSurfaceVariant),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: _cs.outlineVariant.withValues(alpha: 0.3),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(data.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: data[i].count.toDouble(),
                width: _granularity == TrendGranularity.month ? 18 : 12,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [_cs.primary.withValues(alpha: 0.6), _cs.primary],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  String _formatTrendLabel(DateTime date) {
    switch (_granularity) {
      case TrendGranularity.day:
        return DateFormat('M/d').format(date);
      case TrendGranularity.week:
        return DateFormat('M/d').format(date);
      case TrendGranularity.month:
        return DateFormat('yyyy/M').format(date);
    }
  }

  // ─────────────── Distribution ───────────────

  Widget _buildDistributionSection() {
    final hasProvider = _stats.providerDistribution.isNotEmpty;
    final hasModel = _stats.modelDistribution.isNotEmpty;
    if (!hasProvider && !hasModel) return const SizedBox.shrink();

    // Both exist: side by side
    if (hasProvider && hasModel) {
      return _Card(
        cs: _cs,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildMiniPie(
                  title: _l10n.providerDistribution,
                  data: _stats.providerDistribution,
                ),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                color: _cs.outlineVariant.withValues(alpha: 0.5),
              ),
              Expanded(
                child: _buildMiniPie(
                  title: _l10n.modelDistribution,
                  data: _stats.modelDistribution,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Only one
    return _Card(
      cs: _cs,
      child: _buildMiniPie(
        title: hasProvider
            ? _l10n.providerDistribution
            : _l10n.modelDistribution,
        data: hasProvider
            ? _stats.providerDistribution
            : _stats.modelDistribution,
      ),
    );
  }

  Widget _buildMiniPie({
    required String title,
    required Map<String, int> data,
  }) {
    final total = data.values.fold<int>(0, (a, b) => a + b);
    final colors = _distributionColors;
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 20,
                  sections: List.generate(entries.length, (i) {
                    final e = entries[i];
                    final pct = total > 0 ? e.value / total * 100 : 0.0;
                    return PieChartSectionData(
                      value: e.value.toDouble(),
                      color: colors[i % colors.length],
                      radius: 28,
                      title: pct >= 12 ? '${pct.toStringAsFixed(0)}%' : '',
                      titleStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(
                  entries.length > 5 ? 5 : entries.length,
                  (i) {
                    final e = entries[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colors[i % colors.length],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              e.key,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: _cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            '${e.value}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTokenSection() {
    final hasEnhance = _stats.enhanceTotalTokens > 0;
    final hasMeeting = _stats.meetingEnhanceTotalTokens > 0;
    final hasCorrection = _stats.correctionTotalTokens > 0;
    final hasRetro = _stats.retroTotalTokens > 0;
    if (!hasEnhance && !hasMeeting && !hasCorrection && !hasRetro) {
      return const SizedBox.shrink();
    }

    final categoryCount = [
      hasEnhance,
      hasMeeting,
      hasCorrection,
      hasRetro,
    ].where((v) => v).length;
    final showAll = categoryCount >= 2;

    return _Card(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary row at top if both exist
          if (showAll) ...[
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.token_rounded,
                    size: 15,
                    color: _cs.primary,
                  ),
                ),
                Text(
                  _l10n.allTokenUsage,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  _formatNumber(_stats.allTotalTokens),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(
              color: _cs.outlineVariant.withValues(alpha: 0.5),
              height: 1,
            ),
            const SizedBox(height: 16),
          ],
          // Token blocks
          if (hasEnhance)
            _buildTokenBlock(
              title: _l10n.enhanceTokenUsage,
              input: _stats.enhancePromptTokens,
              output: _stats.enhanceCompletionTokens,
              total: _stats.enhanceTotalTokens,
            ),
          if (hasEnhance && hasMeeting) const SizedBox(height: 16),
          if (hasMeeting)
            _buildTokenBlock(
              title: _l10n.meetingTokenUsage,
              input: _stats.meetingEnhancePromptTokens,
              output: _stats.meetingEnhanceCompletionTokens,
              total: _stats.meetingEnhanceTotalTokens,
            ),
          if ((hasEnhance || hasMeeting) && hasCorrection)
            const SizedBox(height: 16),
          if (hasCorrection)
            _buildTokenBlock(
              title: _l10n.correctionTokenUsage,
              input: _stats.correctionPromptTokens,
              output: _stats.correctionCompletionTokens,
              total: _stats.correctionTotalTokens,
            ),
          if (hasCorrection && hasRetro) const SizedBox(height: 16),
          if (hasRetro)
            _buildTokenBlock(
              title: _l10n.retroTokenUsage,
              input: _stats.retroPromptTokens,
              output: _stats.retroCompletionTokens,
              total: _stats.retroTotalTokens,
            ),
        ],
      ),
    );
  }

  Widget _buildCorrectionEfficiencySection() {
    if (_stats.correctionCalls <= 0) return const SizedBox.shrink();

    return _Card(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _l10n.correctionRecallEfficiency,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _buildEfficiencyItem(
                _l10n.correctionTotalCalls,
                _formatNumber(_stats.correctionCalls),
              ),
              _buildEfficiencyItem(
                _l10n.correctionLlmCalls,
                _formatNumber(_stats.correctionLlmCalls),
              ),
              _buildEfficiencyItem(
                _l10n.correctionLlmRate,
                _formatPercent(_stats.correctionLlmInvokeRate),
              ),
              _buildEfficiencyItem(
                _l10n.correctionSelectedRate,
                _formatPercent(_stats.correctionSelectedRate),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEfficiencyItem(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildCorrectionChangeLogsSection() {
    return _Card(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _l10n.correctionChangesTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _cs.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _correctionLogsExpanded = !_correctionLogsExpanded;
                  });
                },
                icon: Icon(
                  _correctionLogsExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                ),
                label: Text(
                  _correctionLogsExpanded
                      ? _l10n.correctionChangesCollapse
                      : _l10n.correctionChangesExpand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_correctionLogsExpanded)
            Text(
              _l10n.correctionChangesCollapsedHint,
              style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
            ),
          if (_correctionLogsExpanded) ...[
            const SizedBox(height: 12),
            if (_correctionLogs.isEmpty)
              Text(
                _l10n.correctionChangesEmpty,
                style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
              )
            else
              ..._correctionLogs.asMap().entries.map((entry) {
                final index = entry.key;
                final log = entry.value;
                final pairText = log.terms
                    .map(
                      (e) =>
                          '${e.observed.isEmpty ? e.original : e.observed}→${e.corrected}',
                    )
                    .join('、');
                final sourceLabel = log.source == 'retrospective'
                    ? _l10n.correctionSourceRetrospective
                    : _l10n.correctionSourceRealtime;

                return Container(
                  margin: EdgeInsets.only(
                    bottom: index == _correctionLogs.length - 1 ? 0 : 12,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _cs.surfaceContainerHighest.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _cs.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            DateFormat('MM-dd HH:mm:ss').format(log.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: _cs.onSurfaceVariant,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              color: _cs.primary.withValues(alpha: 0.12),
                            ),
                            child: Text(
                              sourceLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: _cs.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (pairText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${_l10n.correctionChangedTerms}: $pairText',
                          style: TextStyle(fontSize: 12, color: _cs.onSurface),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        _l10n.correctionBeforeText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        log.inputText,
                        style: TextStyle(fontSize: 12, color: _cs.onSurface),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _l10n.correctionAfterText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        log.outputText,
                        style: TextStyle(fontSize: 12, color: _cs.onSurface),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  // ─────────────── Retrospective Section ───────────────

  Widget _buildRetrospectiveSection() {
    if (_stats.retroCalls <= 0) return const SizedBox.shrink();

    return _Card(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _l10n.retroSectionTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _buildEfficiencyItem(
                _l10n.retroTotalCalls,
                _formatNumber(_stats.retroCalls),
              ),
              _buildEfficiencyItem(
                _l10n.retroLlmCalls,
                _formatNumber(_stats.retroLlmCalls),
              ),
              _buildEfficiencyItem(
                _l10n.retroTextChangedCount,
                _formatNumber(_stats.retroTextChanged),
              ),
              _buildEfficiencyItem(
                _l10n.retroTextChangedRate,
                _formatPercent(
                  _stats.retroCalls > 0
                      ? _stats.retroTextChanged / _stats.retroCalls
                      : 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────── Glossary Section ───────────────

  Widget _buildGlossarySection() {
    final total =
        _stats.glossaryPins +
        _stats.glossaryStrongPromotions +
        _stats.glossaryOverrides +
        _stats.glossaryInjections;
    if (total <= 0) return const SizedBox.shrink();

    return _Card(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _l10n.glossarySectionTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _buildEfficiencyItem(
                _l10n.glossaryPins,
                _formatNumber(_stats.glossaryPins),
              ),
              _buildEfficiencyItem(
                _l10n.glossaryStrongPromotions,
                _formatNumber(_stats.glossaryStrongPromotions),
              ),
              _buildEfficiencyItem(
                _l10n.glossaryOverrides,
                _formatNumber(_stats.glossaryOverrides),
              ),
              _buildEfficiencyItem(
                _l10n.glossaryInjections,
                _formatNumber(_stats.glossaryInjections),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTokenBlock({
    required String title,
    required int input,
    required int output,
    required int total,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title + total on the right
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _cs.onSurface,
              ),
            ),
            Text(
              '${_l10n.enhanceTotalTokens}: ${_formatNumber(total)}',
              style: TextStyle(
                fontSize: 12,
                color: _cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                Expanded(
                  flex: input,
                  child: Container(color: Colors.orange.shade400),
                ),
                Expanded(
                  flex: output > 0 ? output : 1,
                  child: Container(color: Colors.teal.shade400),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Labels
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _TokenLabel(
              color: Colors.orange.shade400,
              label: _l10n.enhanceInputTokens,
              value: _formatNumber(input),
              cs: _cs,
            ),
            _TokenLabel(
              color: Colors.teal.shade400,
              label: _l10n.enhanceOutputTokens,
              value: _formatNumber(output),
              cs: _cs,
            ),
          ],
        ),
      ],
    );
  }

  List<Color> get _distributionColors => [
    _cs.primary,
    _cs.tertiary,
    _cs.secondary,
    Colors.orange,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.amber,
  ];

  // ─────────────── Helpers ───────────────

  String _formatNumber(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    if (totalSeconds < 60) return '$totalSeconds${_l10n.secondShort}';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes < 60) {
      return seconds > 0
          ? '$minutes${_l10n.minuteShort}$seconds${_l10n.secondShort}'
          : '$minutes${_l10n.minuteShort}';
    }
    final hours = minutes ~/ 60;
    final remainMin = minutes % 60;
    return remainMin > 0
        ? '$hours${_l10n.hourShort}$remainMin${_l10n.minuteShort}'
        : '$hours${_l10n.hourShort}';
  }

  String _formatPercent(double value) {
    return '${(value * 100).toStringAsFixed(1)}%';
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) {
      return _l10n.timeAgo('<1${_l10n.minuteShort}');
    }
    if (diff.inHours < 1) {
      return _l10n.timeAgo('${diff.inMinutes}${_l10n.minuteShort}');
    }
    if (diff.inDays < 1) {
      return _l10n.timeAgo('${diff.inHours}${_l10n.hourShort}');
    }
    if (diff.inDays < 30) {
      return _l10n.timeAgo('${diff.inDays}d');
    }
    return DateFormat('yyyy/M/d').format(dt);
  }
}

// ═══════════════════════════════════════════════════
// Private widgets
// ═══════════════════════════════════════════════════

class _HeroData {
  final IconData icon;
  final String label;
  final String value;
  final List<Color> gradient;
  const _HeroData({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
  });
}

class _Card extends StatelessWidget {
  final Widget child;
  final ColorScheme cs;
  const _Card({required this.child, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

class _PeriodStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final ColorScheme cs;
  const _PeriodStat({
    required this.value,
    required this.label,
    required this.color,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _TokenLabel extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final ColorScheme cs;
  const _TokenLabel({
    required this.color,
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: $value',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
