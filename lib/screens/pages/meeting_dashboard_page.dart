import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/meeting.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/log_service.dart';
import '../../widgets/dictionary_entry_dialog.dart';
import '../../widgets/meeting_markdown_view.dart';
import '../../widgets/modern_ui.dart';
import 'meeting_detail_page.dart';
import 'meeting_recording_page.dart';

/// 会议仪表盘页面 - 参照 SYNCPHONY 设计风格
/// 左侧: 今日会议卡片轮播 + 最近会议列表
/// 右侧: 实时会议面板 (含波形/转写/控制按钮)
class MeetingDashboardPage extends StatefulWidget {
  final VoidCallback? onStopReturnHome;

  const MeetingDashboardPage({super.key, this.onStopReturnHome});

  @override
  State<MeetingDashboardPage> createState() => _MeetingDashboardPageState();
}

class _MeetingDashboardPageState extends State<MeetingDashboardPage>
    with TickerProviderStateMixin {
  ColorScheme get _cs => Theme.of(context).colorScheme;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _liveTitleController = TextEditingController();
  final ScrollController _liveScrollController = ScrollController();
  String _searchQuery = '';
  String? _selectedMeetingId;
  bool _isStoppingMeeting = false;
  bool _autoFollowScroll = true;
  bool _isProgrammaticScrolling = false;

  /// 实时会议面板的视图模式
  _LiveViewMode _liveViewMode = _LiveViewMode.mergedNote;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MeetingProvider>().refreshMeetings();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _liveTitleController.dispose();
    _liveScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeetingProvider>();
    final l10n = AppLocalizations.of(context)!;
    final currentMeetingId = provider.currentMeeting?.id;
    final meetings = provider.meetings;
    if (meetings.isEmpty) {
      _selectedMeetingId = null;
    } else {
      final hasSelected =
          _selectedMeetingId != null &&
          meetings.any((m) => m.id == _selectedMeetingId);
      if (!hasSelected) {
        _selectedMeetingId = meetings.first.id;
      }
      if (provider.isRecording && currentMeetingId != null) {
        _selectedMeetingId ??= currentMeetingId;
      }
    }
    final selectedMeeting = meetings
        .where((m) => m.id == _selectedMeetingId)
        .cast<MeetingRecord?>()
        .firstOrNull;
    final showRightPanel = provider.isRecording || selectedMeeting != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: showRightPanel ? 5 : 10,
                  child: _buildLeftPanel(provider, l10n),
                ),
                if (showRightPanel) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: _buildRightPanel(provider, l10n, selectedMeeting),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(
    MeetingProvider provider,
    AppLocalizations l10n,
    MeetingRecord? selectedMeeting,
  ) {
    final currentId = provider.currentMeeting?.id;
    final selectedIsCurrentRecording =
        selectedMeeting != null &&
        (selectedMeeting.status == MeetingStatus.recording ||
            selectedMeeting.status == MeetingStatus.paused) &&
        selectedMeeting.id == currentId;

    if (selectedIsCurrentRecording) {
      return _buildLiveMeetingPanel(provider, l10n);
    }
    if (selectedMeeting != null) {
      return _buildMeetingDetailSidePanel(selectedMeeting, provider, l10n);
    }
    return _buildLiveMeetingPanel(provider, l10n);
  }

  // ═══════════════════════════════════════════════
  // 左侧面板
  // ═══════════════════════════════════════════════

  Widget _buildLeftPanel(MeetingProvider provider, AppLocalizations l10n) {
    final meetings = provider.meetings;
    final filteredMeetings = _filterMeetings(meetings);

    return ModernSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: Row(
              children: [
                Expanded(child: _buildSearchBar(l10n)),
                const SizedBox(width: 12),
                ShadButton(
                  enabled: !provider.isRecording,
                  onPressed: provider.isRecording ? null : _startNewMeeting,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, size: 16),
                      const SizedBox(width: 8),
                      Text(l10n.meetingNew),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildSummaryChip(
                  icon: Icons.library_books_outlined,
                  label: '全部会议',
                  value: '${meetings.length}',
                ),
                _buildSummaryChip(
                  icon: Icons.search_outlined,
                  label: '当前结果',
                  value: '${filteredMeetings.length}',
                ),
                if (provider.isRecording)
                  _buildSummaryChip(
                    icon: Icons.radio_button_checked,
                    label: '实时录制',
                    value: '进行中',
                    tone: _cs.error,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: filteredMeetings.isEmpty
                ? _buildEmptyState(l10n)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                    itemCount: filteredMeetings.length,
                    itemBuilder: (_, i) =>
                        _buildRecentCard(filteredMeetings[i], provider, l10n),
                  ),
          ),
        ],
      ),
    );
  }

  // ── 搜索栏 ──

  Widget _buildSearchBar(AppLocalizations l10n) {
    return ModernSearchInput(
      controller: _searchController,
      hintText: l10n.meetingSearchHint,
      onChanged: (v) => setState(() => _searchQuery = v.trim()),
      onClear: () {
        _searchController.clear();
        setState(() => _searchQuery = '');
      },
    );
  }

  // ── 最近会议卡片 ──

  Widget _buildRecentCard(
    MeetingRecord meeting,
    MeetingProvider provider,
    AppLocalizations l10n,
  ) {
    final locale = Localizations.localeOf(context).toString();
    final dateStr = DateFormat('MMMd, yyyy', locale).format(meeting.createdAt);
    final durationStr = meeting.formattedDuration;
    final previewText = (meeting.summary ?? meeting.fullTranscription ?? '')
        .trim();
    final isEmpty =
        meeting.status == MeetingStatus.completed &&
        (meeting.fullTranscription == null ||
            meeting.fullTranscription!.trim().isEmpty);
    final isSelected = _selectedMeetingId == meeting.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _onMeetingTap(meeting, provider),
        child: ModernSurfaceCard(
          radius: 18,
          backgroundColor: isSelected
              ? _cs.primary.withValues(alpha: 0.08)
              : _cs.surface,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      meeting.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildMeetingPopupMenu(meeting, provider, l10n),
                ],
              ),
              const SizedBox(height: 4),
              // 日期 + 时长
              Row(
                children: [
                  Text(
                    '$dateStr · $durationStr',
                    style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  _buildStatusChip(
                    _statusLabel(meeting.status, l10n),
                    _statusColor(meeting.status),
                  ),
                ],
              ),
              if (previewText.isNotEmpty) ...[
                const SizedBox(height: 10),
                // 内容预览
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: _cs.primary.withValues(alpha: 0.035),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SizedBox(
                    height: 42,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        maxHeight: double.infinity,
                        child: MeetingMarkdownView(
                          markdown: previewText,
                          density: MeetingMarkdownDensity.compact,
                          selectable: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.meetingEmptyContent,
                  style: TextStyle(
                    fontSize: 11,
                    color: _cs.error.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMeetingPopupMenu(
    MeetingRecord meeting,
    MeetingProvider provider,
    AppLocalizations l10n,
  ) {
    return PopupMenuButton<String>(
      tooltip: l10n.meetingMoreActions,
      icon: Icon(Icons.more_vert, size: 18, color: _cs.outline),
      padding: EdgeInsets.zero,
      splashRadius: 16,
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'move',
          child: Row(
            children: [
              const Icon(Icons.drive_file_move_outline, size: 18),
              const SizedBox(width: 8),
              Text(l10n.meetingMoveToGroup),
            ],
          ),
        ),
        if (meeting.status == MeetingStatus.completed ||
            meeting.status == MeetingStatus.recording ||
            meeting.status == MeetingStatus.paused)
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: _cs.error),
                const SizedBox(width: 8),
                Text(l10n.delete, style: TextStyle(color: _cs.error)),
              ],
            ),
          ),
      ],
      onSelected: (value) {
        if (value == 'move') {
          _showMoveGroupSheet(provider, meeting, l10n);
        } else if (value == 'delete') {
          _confirmDelete(provider, meeting, l10n);
        }
      },
    );
  }

  // ── 空状态 ──

  Widget _buildEmptyState(AppLocalizations l10n) {
    return ModernEmptyState(
      icon: Icons.event_note_outlined,
      title: l10n.meetingEmpty,
      description: l10n.meetingEmptyHint,
    );
  }

  // ═══════════════════════════════════════════════
  // 右侧实时会议面板
  // ═══════════════════════════════════════════════

  Widget _buildMeetingDetailSidePanel(
    MeetingRecord meeting,
    MeetingProvider provider,
    AppLocalizations l10n,
  ) {
    final locale = Localizations.localeOf(context).toString();
    final dateStr = DateFormat(
      'MMMd, yyyy HH:mm',
      locale,
    ).format(meeting.createdAt);
    final summary = (meeting.summary ?? '').trim();
    final transcription = (meeting.fullTranscription ?? '').trim();

    return ModernSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ModernSectionHeader(
                        icon: Icons.article_outlined,
                        title: l10n.meetingDetailTab,
                        subtitle: '查看会议摘要、合并笔记和最终文本内容。',
                        compact: true,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider.value(
                          value: provider,
                          child: MeetingDetailPage(meetingId: meeting.id),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(l10n.trayOpen),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meeting.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '$dateStr · ${meeting.formattedDuration}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      _buildStatusChip(
                        _statusLabel(meeting.status, l10n),
                        _statusColor(meeting.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSectionTitle(
                    l10n.meetingSummaryTab,
                    Icons.summarize_outlined,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailCard(
                    child: summary.isNotEmpty
                        ? MeetingMarkdownView(
                            markdown: summary,
                            selectable: true,
                            density: MeetingMarkdownDensity.regular,
                            onAddToDictionary: _addToDictionary,
                          )
                        : _buildPanelEmptyText(l10n.meetingNoContent),
                  ),
                  const SizedBox(height: 12),
                  _buildSectionTitle(
                    l10n.meetingMergedNoteView,
                    Icons.notes_outlined,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailCard(
                    child: transcription.isNotEmpty
                        ? MeetingMarkdownView(
                            markdown: transcription,
                            selectable: true,
                            density: MeetingMarkdownDensity.regular,
                            onAddToDictionary: _addToDictionary,
                          )
                        : _buildPanelEmptyText(l10n.meetingNoContent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String label, IconData icon) {
    return ModernSectionHeader(icon: icon, title: label, compact: true);
  }

  Widget _buildDetailCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _cs.primary.withValues(alpha: 0.015),
          _cs.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cs.primary.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }

  Widget _buildPanelEmptyText(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: _cs.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildLiveMeetingPanel(
    MeetingProvider provider,
    AppLocalizations l10n,
  ) {
    final meeting = provider.currentMeeting;
    if (meeting == null) return const SizedBox.shrink();

    // 同步标题
    final providerTitle = meeting.title;
    if (providerTitle.isNotEmpty &&
        providerTitle != _liveTitleController.text) {
      _liveTitleController.text = providerTitle;
    }

    final duration = provider.recordingDuration;
    final timeStr = _formatDuration(duration);
    final isStoppingUi = _isStoppingMeeting || provider.isStoppingMeeting;

    return ModernSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // ── 实时会议标题头 ──
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ModernSectionHeader(
                        icon: Icons.graphic_eq_outlined,
                        title: l10n.meetingDashboardLive,
                        subtitle: '实时查看转写片段、合并笔记与增量摘要。',
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PulsingDot(color: _cs.error),
                  ],
                ),
                const SizedBox(height: 12),
                // 会议标题 (可编辑)
                TextField(
                  controller: _liveTitleController,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _cs.onSurface,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: l10n.meetingTitleHint,
                    hintStyle: TextStyle(
                      color: _cs.onSurfaceVariant.withValues(alpha: 0.5),
                      fontWeight: FontWeight.normal,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      provider.updateMeetingTitle(meeting.id, value);
                    }
                  },
                ),
                // 时间
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 13,
                    color: _cs.onSurfaceVariant,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ── 音频波形区域 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 86,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  _cs.primary.withValues(alpha: 0.015),
                  _cs.surface,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _cs.primary.withValues(alpha: 0.06)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: _LiveWaveform(
                amplitudeStream: provider.amplitudeStream,
                color: _cs.primary.withValues(alpha: 0.85),
                isPaused: provider.isPaused,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── 视图切换标签 ──
          _buildLiveViewToggle(l10n),
          const SizedBox(height: 8),
          // ── 实时转写内容 ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    _cs.primary.withValues(alpha: 0.012),
                    _cs.surface,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _cs.primary.withValues(alpha: 0.06),
                  ),
                ),
                child: _buildLiveContent(provider, l10n),
              ),
            ),
          ),
          // ── 控制按钮栏 ──
          _buildControlBar(provider, l10n, isStoppingUi),
        ],
      ),
    );
  }

  // ── 实时面板视图切换 ──

  Widget _buildLiveViewToggle(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _buildViewTab(
            label: l10n.meetingMergedNoteView,
            isSelected: _liveViewMode == _LiveViewMode.mergedNote,
            onTap: () =>
                setState(() => _liveViewMode = _LiveViewMode.mergedNote),
          ),
          const SizedBox(width: 8),
          _buildViewTab(
            label: l10n.meetingSegmentView,
            isSelected: _liveViewMode == _LiveViewMode.segments,
            onTap: () => setState(() => _liveViewMode = _LiveViewMode.segments),
          ),
          const SizedBox(width: 8),
          _buildViewTab(
            label: l10n.meetingLiveSummaryView,
            isSelected: _liveViewMode == _LiveViewMode.liveSummary,
            onTap: () =>
                setState(() => _liveViewMode = _LiveViewMode.liveSummary),
          ),
        ],
      ),
    );
  }

  Widget _buildViewTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? _cs.primaryContainer.withValues(alpha: 0.7)
              : _cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? _cs.primary.withValues(alpha: 0.3)
                : _cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? _cs.onPrimaryContainer : _cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required String value,
    Color? tone,
  }) {
    final chipTone = tone ?? _cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: chipTone.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: chipTone.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: chipTone),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ── 实时内容区域 ──

  Widget _buildLiveContent(MeetingProvider provider, AppLocalizations l10n) {
    switch (_liveViewMode) {
      case _LiveViewMode.mergedNote:
        return _buildLiveMergedNote(provider, l10n);
      case _LiveViewMode.segments:
        return _buildLiveSegments(provider, l10n);
      case _LiveViewMode.liveSummary:
        return _buildLiveSummary(provider, l10n);
    }
  }

  Widget _buildLiveMergedNote(MeetingProvider provider, AppLocalizations l10n) {
    final content = provider.mergedNoteContent;
    final isStreaming = provider.isStreamingMerge;

    if (content.isEmpty && !isStreaming) {
      return _buildLiveEmptyHint(
        icon: Icons.note_alt_outlined,
        text: l10n.meetingNoContent,
      );
    }

    _scrollToBottom();

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: SingleChildScrollView(
        controller: _liveScrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isStreaming)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _cs.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.meetingStreamingMerge,
                      style: TextStyle(fontSize: 12, color: _cs.primary),
                    ),
                  ],
                ),
              ),
            MeetingMarkdownView(
              markdown: content,
              selectable: true,
              density: MeetingMarkdownDensity.regular,
              onAddToDictionary: _addToDictionary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveSegments(MeetingProvider provider, AppLocalizations l10n) {
    final segments = provider.currentSegments;

    if (segments.isEmpty && !provider.isPaused) {
      return _buildLiveEmptyHint(
        icon: Icons.mic_none_rounded,
        text: l10n.meetingListening,
      );
    }

    _scrollToBottom();

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: SingleChildScrollView(
        controller: _liveScrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < segments.length; i++) ...[
              if (i == 0 || i % 3 == 0) _buildTimeAnchor(segments[i]),
              _buildSegmentText(segments[i], l10n),
            ],
            if (provider.isRecording && !provider.isPaused)
              _buildRecordingIndicator(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveSummary(MeetingProvider provider, AppLocalizations l10n) {
    final summary = provider.incrementalSummary;
    final isUpdating = provider.isUpdatingIncrementalSummary;

    if (summary.isEmpty && !isUpdating) {
      return _buildLiveEmptyHint(
        icon: Icons.auto_awesome,
        text: l10n.meetingLiveSummaryWaiting,
      );
    }

    _scrollToBottom();

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: SingleChildScrollView(
        controller: _liveScrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUpdating)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _cs.tertiary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.meetingSummaryUpdating,
                      style: TextStyle(fontSize: 12, color: _cs.tertiary),
                    ),
                  ],
                ),
              ),
            MeetingMarkdownView(
              markdown: summary,
              selectable: true,
              density: MeetingMarkdownDensity.regular,
              onAddToDictionary: _addToDictionary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveEmptyHint({required IconData icon, required String text}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: _cs.outline.withValues(alpha: 0.45)),
          const SizedBox(height: 10),
          Text(
            text,
            style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── 分段相关辅助 ──

  Widget _buildTimeAnchor(MeetingSegment segment) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 3),
      child: Text(
        segment.formattedTimestamp,
        style: TextStyle(
          fontSize: 11,
          color: _cs.outline,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildSegmentText(MeetingSegment segment, AppLocalizations l10n) {
    final isTranscribing =
        segment.status == SegmentStatus.pending ||
        segment.status == SegmentStatus.transcribing;
    final isEnhancing = segment.status == SegmentStatus.enhancing;

    if (segment.status == SegmentStatus.error) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                segment.errorMessage ?? l10n.meetingSegmentError,
                style: const TextStyle(fontSize: 13, color: Colors.red),
              ),
            ),
            InkWell(
              onTap: () =>
                  context.read<MeetingProvider>().retrySegment(segment),
              child: Text(
                l10n.meetingRetry,
                style: TextStyle(
                  fontSize: 13,
                  color: _cs.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isTranscribing || isEnhancing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: isEnhancing ? Colors.purple : _cs.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isEnhancing ? l10n.meetingEnhancing : l10n.meetingTranscribing,
              style: TextStyle(
                fontSize: 13,
                color: isEnhancing ? Colors.purple : _cs.primary,
              ),
            ),
          ],
        ),
      );
    }

    final text = (segment.displayText ?? '').trim();
    if (text.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          l10n.meetingNoContent,
          style: TextStyle(
            fontSize: 13,
            color: _cs.outline,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(
        text,
        style: TextStyle(fontSize: 14, color: _cs.onSurface, height: 1.6),
      ),
    );
  }

  Widget _buildRecordingIndicator(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _PulsingDot(color: Colors.red),
          const SizedBox(width: 8),
          Text(
            l10n.meetingRecordingSegment,
            style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ── 控制按钮栏 ──

  Widget _buildControlBar(
    MeetingProvider provider,
    AppLocalizations l10n,
    bool isStoppingUi,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          // 暂停/继续按钮
          Expanded(
            child: FilledButton.icon(
              onPressed: isStoppingUi
                  ? null
                  : () {
                      if (provider.isPaused) {
                        provider.resumeMeeting();
                      } else {
                        provider.pauseMeeting();
                      }
                    },
              icon: Icon(
                provider.isPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                size: 20,
              ),
              label: Text(
                provider.isPaused ? l10n.meetingResume : l10n.meetingPause,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _cs.surfaceContainerHigh,
                foregroundColor: _cs.onSurface,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 保存/结束按钮
          Expanded(
            child: FilledButton.icon(
              onPressed: isStoppingUi
                  ? null
                  : () => _endMeeting(provider, l10n),
              icon: isStoppingUi
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _cs.onError,
                      ),
                    )
                  : const Icon(Icons.stop_rounded, size: 18),
              label: Text(l10n.meetingDashboardSaveNotes),
              style: FilledButton.styleFrom(
                backgroundColor: _cs.error,
                foregroundColor: _cs.onError,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════

  List<MeetingRecord> _filterMeetings(List<MeetingRecord> meetings) {
    if (_searchQuery.isEmpty) return meetings;
    final keyword = _searchQuery.toLowerCase();
    return meetings.where((m) {
      return m.title.toLowerCase().contains(keyword) ||
          (m.summary ?? '').toLowerCase().contains(keyword) ||
          (m.fullTranscription ?? '').toLowerCase().contains(keyword);
    }).toList();
  }

  void _onMeetingTap(MeetingRecord meeting, MeetingProvider provider) {
    setState(() => _selectedMeetingId = meeting.id);
  }

  void _startNewMeeting() {
    final settings = context.read<SettingsProvider>();
    final provider = context.read<MeetingProvider>();

    if (settings.config.model.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pleaseConfigureSttModel),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: provider,
          child: MeetingRecordingPage(
            sttConfig: settings.config,
            aiConfig: settings.effectiveAiEnhanceConfig,
            aiEnhanceEnabled: settings.aiEnhanceEnabled,
            dictionarySuffix: settings.dictionaryWordsForPrompt,
            onStopReturnHome: widget.onStopReturnHome,
          ),
        ),
      ),
    );
  }

  Future<void> _endMeeting(
    MeetingProvider provider,
    AppLocalizations l10n,
  ) async {
    if (_isStoppingMeeting) return;
    setState(() => _isStoppingMeeting = true);

    // 保存标题
    if (_liveTitleController.text.isNotEmpty &&
        provider.currentMeeting != null) {
      await provider.updateMeetingTitle(
        provider.currentMeeting!.id,
        _liveTitleController.text,
      );
    }

    final stopFuture = provider.stopMeetingFast();
    unawaited(() async {
      try {
        await stopFuture;
      } catch (e, st) {
        await LogService.error(
          'MEETING_DASHBOARD_PAGE',
          'stop meeting failed from dashboard: $e\n$st',
        );
      } finally {
        if (mounted) {
          setState(() => _isStoppingMeeting = false);
        }
      }
    }());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.meetingMovedToFinalizing(l10n.meetingFinalizing)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showMoveGroupSheet(
    MeetingProvider provider,
    MeetingRecord meeting,
    AppLocalizations l10n,
  ) async {
    final groups = provider.allMeetingGroups;
    final current = provider.getMeetingGroup(meeting.id);

    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                title: Text(l10n.meetingMoveToGroupTitle),
                subtitle: Text(
                  meeting.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final group in groups)
                ListTile(
                  leading: Icon(
                    group == current
                        ? Icons.check_circle
                        : Icons.folder_outlined,
                  ),
                  title: Text(
                    group == MeetingProvider.defaultMeetingGroup
                        ? l10n.meetingUngrouped
                        : group,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(provider.moveMeetingToGroup(meeting.id, group));
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(
    MeetingProvider provider,
    MeetingRecord meeting,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.meetingDeleteConfirmTitle),
        content: Text(l10n.meetingDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              provider.deleteMeeting(meeting.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _addToDictionary(String selectedWord) async {
    if (selectedWord.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();

    final entry = await showDictionaryEntryDialog(
      context,
      initialOriginal: selectedWord,
    );
    if (entry == null || !mounted) return;

    await settings.addDictionaryEntry(entry);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${l10n.addedToDictionary}: ${entry.original}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _statusLabel(MeetingStatus status, AppLocalizations l10n) {
    switch (status) {
      case MeetingStatus.recording:
        return l10n.meetingRecording;
      case MeetingStatus.paused:
        return l10n.meetingPaused;
      case MeetingStatus.finalizing:
        return l10n.meetingFinalizing;
      case MeetingStatus.completed:
        return l10n.meetingCompleted;
    }
  }

  Color _statusColor(MeetingStatus status) {
    switch (status) {
      case MeetingStatus.recording:
        return _cs.error;
      case MeetingStatus.paused:
        return _cs.tertiary;
      case MeetingStatus.finalizing:
        return _cs.primary;
      case MeetingStatus.completed:
        return Colors.green;
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  void _scrollToBottom() {
    if (!_autoFollowScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_liveScrollController.hasClients) {
        final target = _liveScrollController.position.maxScrollExtent;
        if ((_liveScrollController.position.pixels - target).abs() < 1) return;
        _isProgrammaticScrolling = true;
        _liveScrollController
            .animateTo(
              target,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            )
            .whenComplete(() {
              _isProgrammaticScrolling = false;
            });
      }
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_liveScrollController.hasClients || _isProgrammaticScrolling) {
      return false;
    }
    final metrics = notification.metrics;
    final distanceToBottom = metrics.maxScrollExtent - metrics.pixels;
    final isNearBottom = distanceToBottom <= 64;
    if (!isNearBottom && _autoFollowScroll) {
      setState(() => _autoFollowScroll = false);
    } else if (isNearBottom && !_autoFollowScroll) {
      setState(() => _autoFollowScroll = true);
    }
    return false;
  }
}

/// 实时面板视图模式
enum _LiveViewMode { mergedNote, segments, liveSummary }

// ═══════════════════════════════════════════════
// 自定义动画组件
// ═══════════════════════════════════════════════

/// 迷你波形装饰（今日卡片用）
class _MiniWaveform extends StatefulWidget {
  final Color color;

  const _MiniWaveform({required this.color});

  @override
  State<_MiniWaveform> createState() => _MiniWaveformState();
}

class _MiniWaveformState extends State<_MiniWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(12, (i) {
            final phase = (_controller.value * 2 * math.pi) + (i * 0.5);
            final h = 6.0 + math.sin(phase).abs() * 14.0;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 2.5,
              height: h,
              decoration: BoxDecoration(
                color: widget.color.withValues(
                  alpha: 0.3 + math.sin(phase).abs() * 0.5,
                ),
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 实时音频波形可视化组件
class _LiveWaveform extends StatefulWidget {
  final Stream<double> amplitudeStream;
  final Color color;
  final bool isPaused;

  const _LiveWaveform({
    required this.amplitudeStream,
    required this.color,
    this.isPaused = false,
  });

  @override
  State<_LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends State<_LiveWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  StreamSubscription<double>? _amplSub;
  double _level = 0.0;
  final List<double> _history = List.filled(64, 0.0);
  int _historyIndex = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    )..repeat();
    _amplSub = widget.amplitudeStream.listen((level) {
      if (mounted) {
        _level = level;
        _history[_historyIndex % _history.length] = level;
        _historyIndex++;
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _amplSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        return CustomPaint(
          size: Size.infinite,
          painter: _WaveformPainter(
            history: _history,
            historyIndex: _historyIndex,
            level: widget.isPaused ? 0.0 : _level,
            color: widget.color,
            isPaused: widget.isPaused,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> history;
  final int historyIndex;
  final double level;
  final Color color;
  final bool isPaused;

  _WaveformPainter({
    required this.history,
    required this.historyIndex,
    required this.level,
    required this.color,
    this.isPaused = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final barCount = 64;
    final barWidth = size.width / barCount - 1.5;
    final maxBarHeight = size.height * 0.8;

    for (int i = 0; i < barCount; i++) {
      final hIdx = (historyIndex - barCount + i) % history.length;
      final amplitude = isPaused ? 0.02 : history[hIdx < 0 ? 0 : hIdx];

      // 根据位置产生渐变效果
      final distFromCenter = (i - barCount / 2).abs() / (barCount / 2);
      final envelope = 1.0 - distFromCenter * 0.6;
      final barHeight = math.max(
        2.0,
        amplitude * maxBarHeight * envelope + 2.0,
      );

      // 颜色渐变 - 从中心到边缘渐淡
      final alpha = (0.3 + amplitude * 0.5 + (1 - distFromCenter) * 0.2).clamp(
        0.0,
        1.0,
      );

      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;

      final x = i * (barWidth + 1.5) + 0.75;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: barWidth,
          height: barHeight,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}

/// 红点脉冲动画
class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color.withValues(
              alpha: 0.4 + _controller.value * 0.6,
            ),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
