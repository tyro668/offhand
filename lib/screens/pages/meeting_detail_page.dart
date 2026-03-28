import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../l10n/app_localizations.dart';
import '../../models/meeting.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/dictionary_entry_dialog.dart';
import '../../widgets/meeting_markdown_editor.dart';
import '../../widgets/meeting_markdown_view.dart';

class MeetingDetailPage extends StatefulWidget {
  final String meetingId;

  const MeetingDetailPage({super.key, required this.meetingId});

  @override
  State<MeetingDetailPage> createState() => _MeetingDetailPageState();
}

class _MeetingDetailPageState extends State<MeetingDetailPage> {
  ColorScheme get _cs => Theme.of(context).colorScheme;

  MeetingRecord? _meeting;
  bool _loading = true;
  bool _editingTitle = false;

  /// 跟踪上一次观察到的 isFinalizingMeeting 状态
  bool _wasFinalizing = false;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();
  final TextEditingController _summaryController = TextEditingController();
  final ScrollController _summaryScrollController = ScrollController();

  bool _summaryCollapsed = true;
  bool _regeneratingSummary = false;
  bool _editingSummary = false;
  bool _savingSummary = false;
  bool _editingDetail = false;
  bool _savingDetail = false;
  bool _detailCollapsed = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    _summaryController.dispose();
    _summaryScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final provider = context.read<MeetingProvider>();
    await provider.refreshMeetings();

    final meeting = provider.meetings
        .where((m) => m.id == widget.meetingId)
        .firstOrNull;

    var detailText = (meeting?.fullTranscription ?? '').trim();
    var summaryText = (meeting?.summary ?? '').trim();

    if (meeting != null && detailText.isEmpty) {
      final segments = await AppDatabase.instance.getMeetingSegments(
        meeting.id,
      );
      segments.sort((a, b) => a.segmentIndex.compareTo(b.segmentIndex));
      final fallback = segments
          .map((s) => (s.displayText ?? '').trim())
          .where((t) => t.isNotEmpty)
          .join('\n');
      if (fallback.isNotEmpty) {
        detailText = fallback;
      }
    }

    if (meeting != null && summaryText.isEmpty) {
      final isCurrentFinalizing =
          provider.finalizingMeetingId == widget.meetingId ||
          meeting.status == MeetingStatus.finalizing;
      if (isCurrentFinalizing &&
          provider.incrementalSummary.trim().isNotEmpty) {
        summaryText = provider.incrementalSummary.trim();
      }
    }

    if (!mounted) return;

    setState(() {
      _meeting = meeting;
      _loading = false;
      _titleController.text = meeting?.title ?? '';
      _detailController.text = detailText;
      _summaryController.text = summaryText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<MeetingProvider>();

    // 检测后台精细化完成：之前在 finalizing 且当前不再 finalizing
    final isFinalizingThis =
        (provider.isFinalizingMeeting &&
            provider.finalizingMeetingId == widget.meetingId) ||
        (_meeting?.status == MeetingStatus.finalizing);

    if (isFinalizingThis &&
        !_editingDetail &&
        _detailController.text.trim().isEmpty) {
      final liveDetail = provider.mergedNoteContent.trim();
      if (liveDetail.isNotEmpty) {
        _detailController.text = liveDetail;
      }
    }

    if (isFinalizingThis &&
        !_editingSummary &&
        _summaryController.text.trim().isEmpty) {
      final liveSummary = provider.incrementalSummary.trim();
      if (liveSummary.isNotEmpty) {
        _summaryController.text = liveSummary;
      }
    }

    if (_wasFinalizing && !isFinalizingThis) {
      // 后台精细化完成，重新加载数据
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    }
    _wasFinalizing = isFinalizingThis;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.meetingMinutes)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_meeting == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.meetingMinutes)),
        body: Center(child: Text(l10n.meetingNotFound)),
      );
    }

    final meeting = _meeting!;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(meeting.createdAt);

    return Scaffold(
      backgroundColor: _cs.surfaceContainer,
      body: Column(
        children: [
          _buildHeader(meeting, dateStr, l10n, isFinalizingThis),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 上方：会议摘要（阅读优先）
                  if (_summaryCollapsed)
                    _buildCollapsedSummaryPanel(l10n)
                  else
                    Expanded(
                      flex: 2,
                      child: _buildPanel(
                        icon: Icons.summarize_outlined,
                        title: l10n.meetingSummary,
                        trailing: _buildSummaryActions(l10n),
                        body: _buildTextEditor(
                          controller: _summaryController,
                          emptyHint: l10n.meetingNoSummary,
                          readOnly: !_editingSummary,
                          enableDictionaryMenu: true,
                          scrollController: _summaryScrollController,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  // 下方：完整转写
                  if (_detailCollapsed)
                    _buildCollapsedDetailPanel(l10n)
                  else
                    Expanded(
                      flex: _summaryCollapsed ? 1 : 3,
                      child: _buildPanel(
                        icon: Icons.article_outlined,
                        title: l10n.meetingFullTranscription,
                        trailing: _buildDetailActions(l10n),
                        body: _buildTextEditor(
                          controller: _detailController,
                          emptyHint: l10n.meetingNoContent,
                          readOnly: !_editingDetail,
                          enableDictionaryMenu: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCollapseButton() {
    return SizedBox(
      height: 28,
      width: 28,
      child: IconButton(
        onPressed: _toggleSummaryCollapsed,
        padding: EdgeInsets.zero,
        icon: Icon(Icons.expand_less, size: 16, color: _cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildCollapsedSummaryPanel(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Icon(
              Icons.summarize_outlined,
              size: 16,
              color: _cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.meetingSummary,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildRegenerateSummaryButton(l10n, compact: true),
            const SizedBox(width: 2),
            SizedBox(
              height: 28,
              width: 28,
              child: IconButton(
                onPressed: _toggleSummaryCollapsed,
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.expand_more,
                  size: 16,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryActions(AppLocalizations l10n) {
    if (_editingSummary) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 28,
            child: TextButton.icon(
              onPressed: _savingSummary ? null : _cancelSummaryEdit,
              icon: Icon(Icons.close, size: 14, color: _cs.onSurfaceVariant),
              style: TextButton.styleFrom(
                foregroundColor: _cs.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              label: Text(l10n.cancel, style: const TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 6),
          _buildSaveButton(
            saving: _savingSummary,
            onPressed: _saveSummary,
            l10n: l10n,
          ),
          const SizedBox(width: 2),
          _buildSummaryCollapseButton(),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 28,
          child: TextButton.icon(
            onPressed: _startSummaryEdit,
            icon: Icon(
              Icons.edit_outlined,
              size: 14,
              color: _cs.onSurfaceVariant,
            ),
            label: Text(l10n.edit, style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: _cs.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        _buildRegenerateSummaryButton(l10n),
        const SizedBox(width: 2),
        _buildSummaryCollapseButton(),
      ],
    );
  }

  Widget _buildRegenerateSummaryButton(
    AppLocalizations l10n, {
    bool compact = false,
  }) {
    if (compact) {
      return SizedBox(
        width: 28,
        height: 28,
        child: IconButton(
          tooltip: l10n.meetingRegenerateSummary,
          onPressed: _regeneratingSummary ? null : _regenerateSummary,
          padding: EdgeInsets.zero,
          icon: _regeneratingSummary
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              : Icon(
                  Icons.auto_awesome_outlined,
                  size: 15,
                  color: _cs.onSurfaceVariant,
                ),
        ),
      );
    }

    return SizedBox(
      height: 28,
      child: TextButton.icon(
        onPressed: _regeneratingSummary ? null : _regenerateSummary,
        icon: _regeneratingSummary
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : Icon(
                Icons.auto_awesome_outlined,
                size: 14,
                color: _cs.onSurfaceVariant,
              ),
        label: Text(
          l10n.meetingRegenerateSummary,
          style: const TextStyle(fontSize: 12),
        ),
        style: TextButton.styleFrom(
          foregroundColor: _cs.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }

  // ──────────────── Header ────────────────

  Widget _buildHeader(
    MeetingRecord meeting,
    String dateStr,
    AppLocalizations l10n,
    bool isFinalizingThis,
  ) {
    final charCount = _detailController.text.length;

    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
      decoration: BoxDecoration(
        color: _cs.surface,
        border: Border(
          bottom: BorderSide(color: _cs.outlineVariant.withValues(alpha: 0.55)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: 4),
          // 可编辑标题
          Expanded(child: _buildTitleArea(meeting)),
          const SizedBox(width: 12),
          // 信息标签
          _buildBadge(Icons.calendar_today_outlined, dateStr),
          const SizedBox(width: 6),
          _buildBadge(Icons.timer_outlined, meeting.formattedDuration),
          const SizedBox(width: 6),
          _buildBadge(Icons.text_fields, '$charCount'),
          // 后台精细化进度徽章
          if (isFinalizingThis) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.meetingFinalizing,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 4),
          // 操作菜单
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: _cs.onSurfaceVariant),
            onSelected: (v) => _handleMenuAction(v, meeting, l10n),
            itemBuilder: (_) => [
              _menuItem('copy', Icons.copy, l10n.meetingCopyAll),
              _menuItem(
                'export_text',
                Icons.text_snippet_outlined,
                l10n.meetingExportText,
              ),
              _menuItem(
                'export_md',
                Icons.description_outlined,
                l10n.meetingExportMarkdown,
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.delete,
                      style: TextStyle(color: Colors.red.shade300),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }

  Widget _buildTitleArea(MeetingRecord meeting) {
    if (_editingTitle) {
      return SizedBox(
        height: 34,
        child: TextField(
          controller: _titleController,
          autofocus: true,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _cs.onSurface,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: _cs.outline),
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.check, size: 16, color: _cs.primary),
                  onPressed: _saveTitle,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: _cs.outline),
                  onPressed: () {
                    _titleController.text = _meeting?.title ?? '';
                    setState(() => _editingTitle = false);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
          onSubmitted: (_) => _saveTitle(),
        ),
      );
    }

    return GestureDetector(
      onDoubleTap: () => setState(() => _editingTitle = true),
      child: Row(
        children: [
          Flexible(
            child: Text(
              meeting.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _cs.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.edit_outlined, size: 14, color: _cs.outline),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: _cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ──────────────── Content Panels ────────────────

  Widget _buildPanel({
    required IconData icon,
    required String title,
    required Widget trailing,
    required Widget body,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 面板标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: _cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
          Divider(height: 1, color: _cs.outlineVariant.withValues(alpha: 0.4)),
          // 编辑区域
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildTextEditor({
    required TextEditingController controller,
    required String emptyHint,
    bool readOnly = false,
    bool enableDictionaryMenu = true,
    ScrollController? scrollController,
  }) {
    if (readOnly) {
      final markdownText = controller.text.trim();
      return SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(14),
        child: MeetingMarkdownView(
          markdown: markdownText,
          emptyHint: emptyHint,
          selectable: true,
          density: MeetingMarkdownDensity.compact,
          onAddToDictionary: enableDictionaryMenu ? _addToDictionary : null,
        ),
      );
    }

    return MeetingMarkdownEditor(
      controller: controller,
      emptyHint: emptyHint,
      enableDictionaryMenu: enableDictionaryMenu,
      onAddToDictionary: _addToDictionary,
      scrollController: scrollController,
      density: MeetingMarkdownDensity.compact,
    );
  }

  Widget _buildDetailActions(AppLocalizations l10n) {
    if (_editingDetail) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 28,
            child: TextButton.icon(
              onPressed: _savingDetail ? null : _cancelDetailEdit,
              icon: Icon(Icons.close, size: 14, color: _cs.onSurfaceVariant),
              style: TextButton.styleFrom(
                foregroundColor: _cs.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              label: Text(l10n.cancel, style: const TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 6),
          _buildSaveButton(
            saving: _savingDetail,
            onPressed: _saveDetail,
            l10n: l10n,
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 28,
          child: TextButton.icon(
            onPressed: _startDetailEdit,
            icon: Icon(
              Icons.edit_outlined,
              size: 14,
              color: _cs.onSurfaceVariant,
            ),
            label: Text(l10n.edit, style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: _cs.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        _buildDetailCollapseButton(),
      ],
    );
  }

  Widget _buildSaveButton({
    required bool saving,
    required VoidCallback onPressed,
    required AppLocalizations l10n,
  }) {
    return SizedBox(
      height: 28,
      child: TextButton.icon(
        onPressed: saving ? null : onPressed,
        icon: saving
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : Icon(Icons.save_outlined, size: 14, color: _cs.onSurfaceVariant),
        label: Text(l10n.saveChanges, style: const TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: _cs.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }

  // ──────────────── Data Actions ────────────────

  Future<void> _saveTitle() async {
    if (_titleController.text.isEmpty) return;
    await context.read<MeetingProvider>().updateMeetingTitle(
      widget.meetingId,
      _titleController.text,
    );
    if (!mounted) return;
    setState(() {
      _meeting!.title = _titleController.text;
      _editingTitle = false;
    });
    _showSavedSnackBar();
  }

  Future<void> _saveDetail() async {
    setState(() => _savingDetail = true);
    try {
      final stored = _detailController.text;
      await context.read<MeetingProvider>().updateMeetingFullTranscription(
        widget.meetingId,
        stored,
      );
      if (!mounted) return;
      _meeting?.fullTranscription = stored;
      _showSavedSnackBar();
      setState(() => _editingDetail = false);
    } finally {
      if (mounted) setState(() => _savingDetail = false);
    }
  }

  void _startDetailEdit() {
    setState(() {
      _detailController.text = _meeting?.fullTranscription ?? '';
      _editingDetail = true;
    });
  }

  void _cancelDetailEdit() {
    setState(() {
      _detailController.text = _meeting?.fullTranscription ?? '';
      _editingDetail = false;
    });
  }

  void _startSummaryEdit() {
    setState(() {
      _summaryController.text = _meeting?.summary ?? '';
      _editingSummary = true;
    });
  }

  void _cancelSummaryEdit() {
    setState(() {
      _summaryController.text = _meeting?.summary ?? '';
      _editingSummary = false;
    });
  }

  Future<void> _saveSummary() async {
    setState(() => _savingSummary = true);
    try {
      final stored = _summaryController.text;
      await context.read<MeetingProvider>().updateMeetingSummary(
        widget.meetingId,
        stored,
      );
      if (!mounted) return;
      _meeting?.summary = stored;
      _showSavedSnackBar();
      setState(() => _editingSummary = false);
    } finally {
      if (mounted) setState(() => _savingSummary = false);
    }
  }

  void _toggleSummaryCollapsed() {
    setState(() => _summaryCollapsed = !_summaryCollapsed);
  }

  void _toggleDetailCollapsed() {
    setState(() => _detailCollapsed = !_detailCollapsed);
  }

  Widget _buildDetailCollapseButton() {
    return SizedBox(
      height: 28,
      width: 28,
      child: IconButton(
        onPressed: _toggleDetailCollapsed,
        padding: EdgeInsets.zero,
        icon: Icon(Icons.expand_less, size: 16, color: _cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildCollapsedDetailPanel(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Icon(Icons.article_outlined, size: 16, color: _cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.meetingFullTranscription,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              height: 28,
              width: 28,
              child: IconButton(
                onPressed: _toggleDetailCollapsed,
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.expand_more,
                  size: 16,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _regenerateSummary() async {
    final l10n = AppLocalizations.of(context)!;
    if (_regeneratingSummary) return;

    final content = _detailController.text.trim();
    if (content.isEmpty) {
      _showSnackBarMessage(l10n.meetingNoContent);
      return;
    }

    final confirmed = await _confirmRegenerateSummary(l10n);
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _regeneratingSummary = true);
    final oldSummary = _summaryController.text.trim();
    _summaryController.text = '';
    final buffer = StringBuffer();
    try {
      final settings = context.read<SettingsProvider>();
      final meetingProvider = context.read<MeetingProvider>();

      var hasChunk = false;
      await for (final chunk
          in meetingProvider.regenerateSummaryStreamByContent(
            widget.meetingId,
            content: content,
            aiConfig: settings.effectiveAiEnhanceConfig,
            dictionarySuffix: settings.dictionaryWordsForPrompt,
          )) {
        hasChunk = true;
        if (chunk.isEmpty) continue;
        buffer.write(chunk);
        if (!mounted) return;
        setState(() {
          _summaryController.text = buffer.toString();
        });
      }

      if (!mounted) return;
      final newSummary = buffer.toString().trim();
      if (!hasChunk || newSummary.isEmpty) {
        _showSnackBarMessage(l10n.meetingError);
        return;
      }

      _meeting?.summary = newSummary;
      _summaryController.text = newSummary;
      if (newSummary.isEmpty && oldSummary.isEmpty) {
        _showSnackBarMessage(l10n.meetingNoSummary);
      } else {
        _showSavedSnackBar();
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBarMessage(l10n.meetingError);
    } finally {
      if (mounted) setState(() => _regeneratingSummary = false);
    }
  }

  Future<bool> _confirmRegenerateSummary(AppLocalizations l10n) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.meetingRegenerateSummary),
        content: Text('${l10n.confirm}${l10n.meetingRegenerateSummary}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    return result ?? false;
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

  Future<void> _handleMenuAction(
    String action,
    MeetingRecord meeting,
    AppLocalizations l10n,
  ) async {
    switch (action) {
      case 'copy':
        final text = _detailController.text;
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.copiedToClipboard),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        break;
      case 'export_text':
        final content = await context.read<MeetingProvider>().exportAsText(
          widget.meetingId,
        );
        await Clipboard.setData(ClipboardData(text: content));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.meetingExported),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        break;
      case 'export_md':
        final content = await context.read<MeetingProvider>().exportAsMarkdown(
          widget.meetingId,
        );
        await Clipboard.setData(ClipboardData(text: content));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.meetingExported),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        break;
      case 'delete':
        final isEmpty = (meeting.fullTranscription ?? '').trim().isEmpty;
        if (isEmpty) {
          await context.read<MeetingProvider>().deleteMeeting(meeting.id);
          if (mounted) Navigator.pop(context);
        } else {
          _confirmDelete(meeting, l10n);
        }
        break;
    }
  }

  void _confirmDelete(MeetingRecord meeting, AppLocalizations l10n) {
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
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<MeetingProvider>().deleteMeeting(meeting.id);
              if (mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _showSavedSnackBar() {
    final l10n = AppLocalizations.of(context)!;
    _showSnackBarMessage(l10n.meetingSaved);
  }

  void _showSnackBarMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
