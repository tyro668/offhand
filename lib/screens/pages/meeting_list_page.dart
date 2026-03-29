import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/meeting.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/recording_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/meeting_markdown_view.dart';
import 'meeting_detail_page.dart';
import 'meeting_recording_page.dart';

class MeetingListPage extends StatefulWidget {
  const MeetingListPage({super.key});

  @override
  State<MeetingListPage> createState() => _MeetingListPageState();
}

class _MeetingListPageState extends State<MeetingListPage> {
  static const String _allGroupFilterToken = '__all__';

  ColorScheme get _cs => Theme.of(context).colorScheme;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedGroup = _allGroupFilterToken;
  bool _isUnifyRebuilding = false;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meetingProvider = context.watch<MeetingProvider>();
    final meetings = meetingProvider.meetings;
    final l10n = AppLocalizations.of(context)!;

    final groups = [_allGroupFilterToken, ...meetingProvider.allMeetingGroups];
    if (!groups.contains(_selectedGroup)) {
      _selectedGroup = _allGroupFilterToken;
    }

    final filteredMeetings = _filterMeetings(meetings, meetingProvider);
    final groupedMeetings = _groupMeetings(filteredMeetings, meetingProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(meetingProvider, meetings.length, l10n),
          const SizedBox(height: 14),
          _buildSearchBar(l10n),
          const SizedBox(height: 12),
          _buildGroupFilterBar(groups, meetingProvider, l10n),
          const SizedBox(height: 12),
          Expanded(
            child: filteredMeetings.isEmpty
                ? _buildEmpty(l10n)
                : _buildGroupedList(groupedMeetings, meetingProvider, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    MeetingProvider provider,
    int totalCount,
    AppLocalizations l10n,
  ) {
    final completedCount = provider.meetings
        .where((m) => m.status == MeetingStatus.completed)
        .length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.forum_outlined,
              color: _cs.onPrimaryContainer,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.meetingMinutes,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.meetingStatsSummary(totalCount, completedCount),
                  style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (provider.isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _cs.errorContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _cs.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.meetingRecording,
                    style: TextStyle(
                      color: _cs.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: provider.isRecording || _isUnifyRebuilding
                ? null
                : () => _confirmUnifyRebuild(provider, l10n),
            icon: _isUnifyRebuilding
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: _cs.primary,
                    ),
                  )
                : const Icon(Icons.auto_fix_high_outlined, size: 18),
            label: Text(l10n.meetingUnifyRebuild),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: provider.isRecording
                ? null
                : () => _startNewMeeting(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.meetingNew),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value.trim()),
      decoration: InputDecoration(
        hintText: l10n.meetingSearchHint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: const Icon(Icons.close),
              ),
        filled: true,
        fillColor: _cs.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _cs.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupFilterBar(
    List<String> groups,
    MeetingProvider provider,
    AppLocalizations l10n,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final group in groups) ...[
            FilterChip(
              selected: _selectedGroup == group,
              label: Text(_groupDisplayName(group, l10n)),
              onSelected: (_) => setState(() => _selectedGroup = group),
            ),
            const SizedBox(width: 8),
          ],
          OutlinedButton.icon(
            onPressed: () => _showManageGroupsDialog(provider),
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: Text(l10n.meetingManageGroups),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList(
    Map<String, List<MeetingRecord>> grouped,
    MeetingProvider provider,
    AppLocalizations l10n,
  ) {
    final entries = grouped.entries.toList()
      ..sort((a, b) {
        if (a.key == MeetingProvider.defaultMeetingGroup) return -1;
        if (b.key == MeetingProvider.defaultMeetingGroup) return 1;
        return a.key.compareTo(b.key);
      });

    return ListView(
      children: [
        for (final entry in entries) ...[
          _buildGroupHeader(entry.key, entry.value.length),
          const SizedBox(height: 8),
          for (final meeting in entry.value)
            _buildMeetingCard(context, provider, meeting, l10n),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildGroupHeader(String groupName, int count) {
    return Row(
      children: [
        Icon(Icons.folder_outlined, size: 16, color: _cs.primary),
        const SizedBox(width: 6),
        Text(
          groupName,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _cs.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _cs.secondaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              color: _cs.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMeetingCard(
    BuildContext context,
    MeetingProvider provider,
    MeetingRecord meeting,
    AppLocalizations l10n,
  ) {
    final locale = Localizations.localeOf(context).toString();
    final dateStr = DateFormat('MMMd HH:mm', locale).format(meeting.createdAt);
    final statusLabel = _statusLabel(meeting.status, l10n);
    final statusColor = _statusColor(meeting.status);
    final groupName = provider.getMeetingGroup(meeting.id);
    final groupDisplayName = _groupDisplayName(groupName, l10n);
    final durationInline = meeting.totalDuration.inSeconds > 0
        ? ' · ${meeting.formattedDuration}'
        : '';
    final metaLine = '$dateStr$durationInline · $groupDisplayName';

    final isEmpty =
        meeting.status == MeetingStatus.completed &&
        (meeting.fullTranscription == null ||
            meeting.fullTranscription!.trim().isEmpty);

    final previewText = (meeting.summary ?? meeting.fullTranscription ?? '')
        .trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEmpty
              ? _cs.error.withValues(alpha: 0.3)
              : _cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: meeting.status == MeetingStatus.recording
            ? () => _navigateToRecording(context)
            : () => _navigateToDetail(context, meeting),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _cs.primaryContainer.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      meeting.status == MeetingStatus.recording
                          ? Icons.graphic_eq_rounded
                          : Icons.article_outlined,
                      color: _cs.onPrimaryContainer,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: meeting.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _cs.onSurface,
                                  ),
                                ),
                                TextSpan(
                                  text: ' · $metaLine',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: _cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildStatusChip(statusLabel, statusColor),
                        const SizedBox(width: 1),
                        PopupMenuButton<String>(
                          tooltip: l10n.meetingMoreActions,
                          icon: Icon(
                            Icons.more_horiz,
                            size: 16,
                            color: _cs.outline,
                          ),
                          padding: EdgeInsets.zero,
                          splashRadius: 16,
                          itemBuilder: (_) => [
                            PopupMenuItem<String>(
                              value: 'move',
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.drive_file_move_outline,
                                    size: 18,
                                  ),
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
                                    Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: isEmpty ? _cs.error : _cs.outline,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      l10n.delete,
                                      style: TextStyle(
                                        color: isEmpty
                                            ? _cs.error
                                            : _cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          onSelected: (value) {
                            if (value == 'move') {
                              _showMoveGroupSheet(provider, meeting);
                              return;
                            }
                            if (value == 'delete') {
                              if (isEmpty) {
                                provider.deleteMeeting(meeting.id);
                              } else {
                                _confirmDelete(
                                  context,
                                  provider,
                                  meeting,
                                  l10n,
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (previewText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SizedBox(
                    height: 48,
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

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 54, color: _cs.outline),
          const SizedBox(height: 12),
          Text(
            l10n.meetingEmpty,
            style: TextStyle(fontSize: 16, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.meetingEmptyHint,
            style: TextStyle(fontSize: 13, color: _cs.outline),
          ),
        ],
      ),
    );
  }

  List<MeetingRecord> _filterMeetings(
    List<MeetingRecord> meetings,
    MeetingProvider provider,
  ) {
    return meetings.where((meeting) {
      final groupName = provider.getMeetingGroup(meeting.id);
      if (_selectedGroup != _allGroupFilterToken &&
          groupName != _selectedGroup) {
        return false;
      }

      if (_searchQuery.isEmpty) return true;

      final keyword = _searchQuery.toLowerCase();
      final title = meeting.title.toLowerCase();
      final summary = (meeting.summary ?? '').toLowerCase();
      final fullText = (meeting.fullTranscription ?? '').toLowerCase();
      return title.contains(keyword) ||
          summary.contains(keyword) ||
          fullText.contains(keyword);
    }).toList();
  }

  Map<String, List<MeetingRecord>> _groupMeetings(
    List<MeetingRecord> meetings,
    MeetingProvider provider,
  ) {
    final map = <String, List<MeetingRecord>>{};
    for (final meeting in meetings) {
      final group = provider.getMeetingGroup(meeting.id);
      map.putIfAbsent(group, () => []).add(meeting);
    }
    return map;
  }

  Future<void> _showMoveGroupSheet(
    MeetingProvider provider,
    MeetingRecord meeting,
  ) async {
    final l10n = AppLocalizations.of(context)!;
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
                  title: Text(_groupDisplayName(group, l10n)),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(provider.moveMeetingToGroup(meeting.id, group));
                  },
                ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text(l10n.meetingCreateGroupAndMove),
                onTap: () async {
                  Navigator.pop(ctx);
                  final newGroup = await _promptCreateGroup();
                  if (newGroup != null && newGroup.isNotEmpty) {
                    await provider.moveMeetingToGroup(meeting.id, newGroup);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showManageGroupsDialog(MeetingProvider provider) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final groups = provider.allMeetingGroups
                .where((g) => g != MeetingProvider.defaultMeetingGroup)
                .toList();

            return AlertDialog(
              title: Text(l10n.meetingGroupManageTitle),
              content: SizedBox(
                width: 420,
                child: groups.isEmpty
                    ? Text(l10n.meetingGroupManageEmptyHint)
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: groups.length,
                        itemBuilder: (_, index) {
                          final group = groups[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(_groupDisplayName(group, l10n)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () async {
                                    final renamed = await _promptRenameGroup(
                                      group,
                                    );
                                    if (renamed != null && renamed.isNotEmpty) {
                                      await provider.renameMeetingGroup(
                                        group,
                                        renamed,
                                      );
                                      setLocalState(() {});
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  onPressed: () async {
                                    await provider.deleteMeetingGroup(group);
                                    setLocalState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.meetingGroupClose),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final newGroup = await _promptCreateGroup();
                    if (newGroup != null && newGroup.isNotEmpty) {
                      await provider.ensureMeetingGroupExists(newGroup);
                      setLocalState(() {});
                    }
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(l10n.meetingGroupCreate),
                ),
              ],
            );
          },
        );
      },
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<String?> _promptCreateGroup() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.meetingGroupCreateTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.meetingGroupNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    return result?.trim();
  }

  Future<String?> _promptRenameGroup(String oldName) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: oldName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.meetingGroupRenameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.meetingGroupRenameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    return result?.trim();
  }

  String _groupDisplayName(String group, AppLocalizations l10n) {
    if (group == _allGroupFilterToken) {
      return l10n.meetingAllGroups;
    }
    if (group == MeetingProvider.defaultMeetingGroup) {
      return l10n.meetingUngrouped;
    }
    return group;
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

  void _startNewMeeting(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final meetingProvider = context.read<MeetingProvider>();

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
          value: meetingProvider,
          child: MeetingRecordingPage(
            sttConfig: settings.config,
            aiConfig: settings.effectiveAiEnhanceConfig,
            aiEnhanceEnabled: settings.aiEnhanceEnabled,
            dictionarySuffix: settings.dictionaryWordsForPrompt,
          ),
        ),
      ),
    );
  }

  void _navigateToRecording(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final meetingProvider = context.read<MeetingProvider>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: meetingProvider,
          child: MeetingRecordingPage(
            sttConfig: settings.config,
            aiConfig: settings.effectiveAiEnhanceConfig,
            aiEnhanceEnabled: settings.aiEnhanceEnabled,
            dictionarySuffix: settings.dictionaryWordsForPrompt,
          ),
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context, MeetingRecord meeting) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<MeetingProvider>(),
          child: MeetingDetailPage(meetingId: meeting.id),
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
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

  Future<void> _confirmUnifyRebuild(
    MeetingProvider provider,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.meetingUnifyRebuildTitle),
        content: Text(l10n.meetingUnifyRebuildConfirm),
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

    if (confirmed != true || !mounted) return;

    final settings = context.read<SettingsProvider>();

    setState(() => _isUnifyRebuilding = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.meetingUnifyRebuildRunning),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final count = await provider.rebuildHistoricalMeetingsFromSegments(
        aiConfig: settings.effectiveAiEnhanceConfig,
        dictionarySuffix: settings.dictionaryWordsForPrompt,
        dictionaryEntries: settings.dictionaryEntries,
        termContextEntries: settings.termContextEntries,
        historyEntries: context.read<RecordingProvider>().history,
        entityMemories: settings.entityMemories,
        entityAliases: settings.entityAliases,
        entityRelations: settings.entityRelations,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.meetingUnifyRebuildDone(count)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUnifyRebuilding = false);
      }
    }
  }
}
