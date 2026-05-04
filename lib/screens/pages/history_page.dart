import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/dictionary_entry.dart';
import '../../models/dictation_term_pending_candidate.dart';
import '../../models/entity_alias.dart';
import '../../models/entity_memory.dart';
import '../../models/memory_item.dart';
import '../../models/transcription.dart';
import '../../providers/recording_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/dictation_term_memory_service.dart';
import '../../widgets/dictionary_entry_dialog.dart';
import '../../widgets/modern_ui.dart';

class HistoryPage extends StatefulWidget {
  final VoidCallback? onOpenPendingCandidates;

  const HistoryPage({super.key, this.onOpenPendingCandidates});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  ColorScheme get _cs => Theme.of(context).colorScheme;
  static const _termMemoryService = DictationTermMemoryService();
  static const _editedBadgeText = '已人工修正';
  static const _historyPageSize = 20;

  /// 记录哪些 item id 的原始文本处于展开状态
  final Set<String> _expandedRawText = {};
  int _currentPage = 0;

  void _showFloatingSnackBar(String message, {Duration? duration}) {
    final text = message.trim();
    if (!mounted || text.isEmpty) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
          duration: duration ?? const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final recording = context.watch<RecordingProvider>();
    final settings = context.watch<SettingsProvider>();
    final history = recording.history;
    final pendingCandidates = settings.dictationTermPendingCandidates;
    final totalPages = _totalHistoryPages(history.length);
    final currentPage = _clampedHistoryPage(history.length);
    if (_currentPage != currentPage) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _currentPage = currentPage);
      });
    }
    final hasLearnableEditedHistory = history.any(
      (item) =>
          recording.isHistoryEdited(item.id) &&
          item.hasRawText &&
          item.rawText!.trim().isNotEmpty &&
          item.rawText!.trim() != item.text.trim(),
    );
    final l10n = AppLocalizations.of(context)!;

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(34, 24, 34, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pendingCandidates.isNotEmpty) ...[
            _buildPendingCandidatesSummary(pendingCandidates),
            const SizedBox(height: 18),
          ],
          Expanded(
            child: history.isEmpty
                ? _buildEmpty(l10n)
                : _buildList(
                    context,
                    recording,
                    history,
                    l10n,
                    pageStart: currentPage * _historyPageSize,
                  ),
          ),
          const SizedBox(height: 10),
          _buildArchiveHeader(
            recording: recording,
            settings: settings,
            historyCount: history.length,
            currentPage: currentPage,
            totalPages: totalPages,
            hasLearnableEditedHistory: hasLearnableEditedHistory,
            l10n: l10n,
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveHeader({
    required RecordingProvider recording,
    required SettingsProvider settings,
    required int historyCount,
    required int currentPage,
    required int totalPages,
    required bool hasLearnableEditedHistory,
    required AppLocalizations l10n,
  }) {
    return _buildArchiveToolbar(
      recording: recording,
      settings: settings,
      historyCount: historyCount,
      currentPage: currentPage,
      totalPages: totalPages,
      hasLearnableEditedHistory: hasLearnableEditedHistory,
      l10n: l10n,
    );
  }

  int _totalHistoryPages(int itemCount) =>
      itemCount == 0 ? 0 : ((itemCount - 1) ~/ _historyPageSize) + 1;

  int _clampedHistoryPage(int itemCount) {
    final totalPages = _totalHistoryPages(itemCount);
    if (totalPages == 0) return 0;
    return _currentPage.clamp(0, totalPages - 1).toInt();
  }

  Widget _buildArchiveToolbar({
    required RecordingProvider recording,
    required SettingsProvider settings,
    required int historyCount,
    required int currentPage,
    required int totalPages,
    required bool hasLearnableEditedHistory,
    required AppLocalizations l10n,
  }) {
    final hasHistory = historyCount > 0;

    final toolbarItems = <Widget>[
      if (hasLearnableEditedHistory)
        _ArchivePagerButton(
          label: '同步修正',
          enabled: true,
          onPressed: () => _syncEditedHistoryCorrections(recording, settings),
        ),
      _ArchivePagerButton(
        label: '上一页',
        enabled: hasHistory && currentPage > 0,
        onPressed: () {
          setState(() => _currentPage = currentPage - 1);
        },
      ),
      Text(
        hasHistory ? '${currentPage + 1} / $totalPages' : '0 / 0',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _cs.onSurfaceVariant.withValues(alpha: 0.78),
        ),
      ),
      _ArchivePagerButton(
        label: '下一页',
        enabled: hasHistory && currentPage < totalPages - 1,
        onPressed: () {
          setState(() => _currentPage = currentPage + 1);
        },
      ),
      _ArchivePagerButton(
        label: l10n.clear,
        enabled: hasHistory,
        destructive: true,
        onPressed: () => _confirmClearAll(context, recording, l10n),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < toolbarItems.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  toolbarItems[i],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _syncEditedHistoryCorrections(
    RecordingProvider recording,
    SettingsProvider settings,
  ) async {
    final learnedTerms = <String>{};
    final learnedEntities = <String>{};
    var skippedItems = 0;

    for (final item in recording.history) {
      if (!recording.isHistoryEdited(item.id)) continue;
      final rawText = (item.rawText ?? '').trim();
      final editedText = item.text.trim();
      if (rawText.isEmpty || editedText.isEmpty || rawText == editedText) {
        skippedItems++;
        continue;
      }

      await settings.recordHistoryEditToMemory(
        beforeText: rawText,
        afterText: editedText,
        rawText: rawText,
        sourceHistoryId: item.id,
      );

      final candidates = _termMemoryService.extractCandidates(
        beforeText: rawText,
        afterText: editedText,
        rawText: rawText,
      );
      if (candidates.isEmpty) {
        skippedItems++;
        continue;
      }

      for (final candidate in candidates) {
        final entry = await settings.upsertDictionaryCorrectionEntry(
          original: candidate.original,
          corrected: candidate.corrected,
          source: DictionaryEntrySource.historyEdit,
        );
        final corrected = (entry.corrected ?? '').trim();
        if (corrected.isEmpty) continue;
        recording.applySessionGlossaryOverride(entry.original, corrected);
        learnedTerms.add('${entry.original} -> $corrected');
      }

      final entityResults = await settings.learnEntitiesFromHistoryEdit(
        beforeText: rawText,
        afterText: editedText,
        rawText: rawText,
        sourceHistoryId: item.id,
      );
      for (final entity in entityResults) {
        recording.activateSessionEntity(
          entityId: entity.id,
          canonicalName: entity.canonicalName,
          alias: entity.canonicalName,
        );
        learnedEntities.add(entity.canonicalName);
      }
    }

    if (!mounted) return;
    final message = learnedTerms.isEmpty && learnedEntities.isEmpty
        ? '没有可同步的历史修正'
        : [
            if (learnedTerms.isNotEmpty) '已同步 ${learnedTerms.length} 条历史修正',
            if (learnedEntities.isNotEmpty) '已学习 ${learnedEntities.length} 个实体',
            if (skippedItems > 0) '跳过 $skippedItems 条',
          ].join('，');
    _showFloatingSnackBar(message, duration: const Duration(seconds: 2));
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    return ModernEmptyState(
      icon: Icons.history_rounded,
      title: l10n.noHistory,
      description: l10n.historyHint,
    );
  }

  Widget _buildPendingCandidatesSummary(
    List<DictationTermPendingCandidate> pendingCandidates,
  ) {
    final previewItems = pendingCandidates.take(3).toList(growable: false);
    return ModernSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pending_actions_outlined,
                size: 20,
                color: _cs.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '待确认术语候选',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _cs.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${pendingCandidates.length} 条',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _cs.onSecondaryContainer,
                  ),
                ),
              ),
              if (widget.onOpenPendingCandidates != null) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: widget.onOpenPendingCandidates,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('前往词典处理'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '你刚刚从历史修正里沉淀的候选会先出现在这里，正式管理入口也在词典页顶部。',
            style: TextStyle(fontSize: 12, color: _cs.outline, height: 1.45),
          ),
          const SizedBox(height: 12),
          ...previewItems.map(
            (candidate) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildPendingCandidatePreview(candidate),
            ),
          ),
          if (pendingCandidates.length > previewItems.length)
            Text(
              '还有 ${pendingCandidates.length - previewItems.length} 条候选待确认，可前往词典页继续处理。',
              style: TextStyle(fontSize: 11, color: _cs.outline),
            ),
        ],
      ),
    );
  }

  Widget _buildPendingCandidatePreview(
    DictationTermPendingCandidate candidate,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _cs.primary.withValues(alpha: 0.018),
          _cs.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cs.primary.withValues(alpha: 0.08)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${candidate.original} -> ${candidate.corrected}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          if (candidate.category != null && candidate.category!.isNotEmpty)
            _buildChip(
              candidate.category!,
              _cs.tertiary,
              _cs.onTertiaryContainer,
            ),
          _buildChip('待确认', _cs.primary, _cs.onPrimaryContainer),
          if (candidate.occurrenceCount > 1)
            _buildChip(
              '累计 ${candidate.occurrenceCount} 次',
              _cs.secondary,
              _cs.onSecondaryContainer,
            ),
        ],
      ),
    );
  }

  Widget _buildChip(String text, Color color, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.10)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    RecordingProvider recording,
    List<Transcription> history,
    AppLocalizations l10n, {
    required int pageStart,
  }) {
    final visibleHistory = history
        .skip(pageStart)
        .take(_historyPageSize)
        .toList(growable: false);

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: visibleHistory.length,
      itemBuilder: (context, index) {
        final item = visibleHistory[index];
        final historyIndex = pageStart + index;
        final wasEdited = recording.isHistoryEdited(item.id);

        return _buildArchiveCard(
          item: item,
          historyIndex: historyIndex,
          totalCount: history.length,
          recording: recording,
          l10n: l10n,
          wasEdited: wasEdited,
        );
      },
    );
  }

  Widget _buildArchiveCard({
    required Transcription item,
    required int historyIndex,
    required int totalCount,
    required RecordingProvider recording,
    required AppLocalizations l10n,
    required bool wasEdited,
  }) {
    final isExpanded = _expandedRawText.contains(item.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _cs.primary.withValues(alpha: 0.022),
          _cs.surface.withValues(alpha: 0.96),
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: _cs.primary.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildArchiveActions(
            item: item,
            historyIndex: historyIndex,
            totalCount: totalCount,
            recording: recording,
            l10n: l10n,
            isExpanded: isExpanded,
          ),
          const SizedBox(height: 6),
          _buildSelectableHistoryText(item, l10n),
          const SizedBox(height: 6),
          _buildArchiveMeta(item: item, wasEdited: wasEdited),
          if (item.hasRawText && isExpanded) ...[
            const SizedBox(height: 8),
            _buildRawTextPanel(item),
          ],
        ],
      ),
    );
  }

  Widget _buildArchiveActions({
    required Transcription item,
    required int historyIndex,
    required int totalCount,
    required RecordingProvider recording,
    required AppLocalizations l10n,
    required bool isExpanded,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ArchiveActionButton(
                  label: l10n.edit,
                  tooltip: l10n.edit,
                  onTap: () => _editHistoryItem(item),
                ),
                const SizedBox(width: 4),
                _ArchiveActionButton(
                  label: l10n.copy,
                  tooltip: l10n.copy,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: item.text));
                    _showFloatingSnackBar(
                      l10n.copiedToClipboard,
                      duration: const Duration(seconds: 1),
                    );
                  },
                ),
                const SizedBox(width: 4),
                _ArchiveActionButton(
                  label: l10n.delete,
                  tooltip: l10n.delete,
                  destructive: true,
                  onTap: () {
                    recording.removeHistory(historyIndex);
                    final nextCount = totalCount - 1;
                    final nextPage = _clampedHistoryPage(nextCount);
                    if (nextPage != _currentPage || isExpanded) {
                      setState(() {
                        _currentPage = nextPage;
                        _expandedRawText.remove(item.id);
                      });
                    }
                  },
                ),
                const SizedBox(width: 4),
                _ArchiveActionButton(
                  label: l10n.originalSttText,
                  tooltip: l10n.originalSttText,
                  enabled: item.hasRawText,
                  selected: isExpanded,
                  onTap: item.hasRawText
                      ? () {
                          setState(() {
                            if (isExpanded) {
                              _expandedRawText.remove(item.id);
                            } else {
                              _expandedRawText.add(item.id);
                            }
                          });
                        }
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectableHistoryText(
    Transcription item,
    AppLocalizations l10n,
  ) {
    return SelectableText(
      item.text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: _cs.onSurface.withValues(alpha: 0.92),
        height: 1.45,
      ),
      contextMenuBuilder: (ctx, editableTextState) {
        final selectedText = editableTextState.textEditingValue.selection
            .textInside(editableTextState.textEditingValue.text);
        final builtinItems = editableTextState.contextMenuButtonItems;
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: [
            ...builtinItems,
            if (selectedText.trim().isNotEmpty)
              ContextMenuButtonItem(
                label: l10n.addToDictionary,
                onPressed: () {
                  ContextMenuController.removeAny();
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _addToDictionary(selectedText.trim());
                  });
                },
              ),
            if (selectedText.trim().isNotEmpty)
              ContextMenuButtonItem(
                label: '作为实体学习',
                onPressed: () {
                  ContextMenuController.removeAny();
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _addSelectedTextAsEntity(selectedText.trim());
                  });
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildArchiveMeta({
    required Transcription item,
    required bool wasEdited,
  }) {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(item.createdAt);

    return Wrap(
      spacing: 5,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildMetaText(dateStr),
        if (item.llmProcessingDuration != null) ...[
          _buildMetaDot(),
          _buildMetaText(
            '文本增强耗时 ${item.llmProcessingDuration!.inMilliseconds} ms',
          ),
        ],
        if (item.llmInputTokens != null) ...[
          _buildMetaDot(),
          _buildMetaText('输入 tokens ${item.llmInputTokens}'),
        ],
        if (item.llmOutputTokens != null) ...[
          _buildMetaDot(),
          _buildMetaText('输出 tokens ${item.llmOutputTokens}'),
        ],
        if (wasEdited) ...[_buildMetaDot(), _buildMetaBadge(_editedBadgeText)],
      ],
    );
  }

  Widget _buildMetaText(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        color: _cs.onSurfaceVariant.withValues(alpha: 0.56),
        height: 1.15,
      ),
    );
  }

  Widget _buildMetaDot() {
    return Text(
      '·',
      style: TextStyle(
        fontSize: 11,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        color: _cs.onSurfaceVariant.withValues(alpha: 0.42),
      ),
    );
  }

  Widget _buildMetaBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _cs.secondaryContainer.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: _cs.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildRawTextPanel(Transcription item) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _cs.primary.withValues(alpha: 0.018),
          _cs.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cs.primary.withValues(alpha: 0.08)),
      ),
      child: SelectableText(
        item.rawText ?? '',
        style: TextStyle(
          fontSize: 12.5,
          color: _cs.onSurfaceVariant.withValues(alpha: 0.82),
          height: 1.4,
        ),
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
    _showFloatingSnackBar(
      '${l10n.addedToDictionary}: ${entry.original}',
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _editHistoryItem(Transcription item) async {
    final l10n = AppLocalizations.of(context)!;
    var draftText = item.text;
    final edited = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.edit),
        content: SizedBox(
          width: 520,
          child: TextFormField(
            initialValue: item.text,
            autofocus: true,
            minLines: 6,
            maxLines: 14,
            onChanged: (value) => draftText = value,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: l10n.historyHint,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, draftText.trim()),
            child: Text(l10n.saveChanges),
          ),
        ],
      ),
    );

    final nextText = (edited ?? '').trim();
    if (!mounted || nextText.isEmpty || nextText == item.text.trim()) {
      return;
    }

    final recording = context.read<RecordingProvider>();
    final settings = context.read<SettingsProvider>();
    await recording.updateHistoryText(item.id, nextText);

    final learnedMemories = await settings.recordHistoryEditToMemory(
      beforeText: item.text,
      afterText: nextText,
      rawText: item.rawText,
      sourceHistoryId: item.id,
    );
    for (final memory in learnedMemories) {
      if (memory.kind != MemoryItemKind.correction ||
          !memory.isCorrectionEligible) {
        continue;
      }
      recording.applySessionGlossaryOverride(memory.original, memory.canonical);
    }
    final learnedEntities = await settings.learnEntitiesFromHistoryEdit(
      beforeText: item.text,
      afterText: nextText,
      rawText: item.rawText,
      sourceHistoryId: item.id,
    );
    for (final entity in learnedEntities) {
      recording.activateSessionEntity(
        entityId: entity.id,
        canonicalName: entity.canonicalName,
        alias: entity.canonicalName,
      );
    }

    if (!mounted || (learnedMemories.isEmpty && learnedEntities.isEmpty)) {
      return;
    }
    final entityNames = learnedEntities
        .map((e) => e.canonicalName)
        .toSet()
        .toList(growable: false);
    final summary = <String>[
      if (learnedMemories.isNotEmpty) '已记录 ${learnedMemories.length} 条学习记忆',
      if (entityNames.isNotEmpty) '已学习 ${entityNames.length} 个实体',
    ].join('，');
    _showFloatingSnackBar(summary, duration: const Duration(seconds: 2));
  }

  Future<void> _addSelectedTextAsEntity(String selectedText) async {
    final canonicalCtrl = TextEditingController(text: selectedText);
    final aliasCtrl = TextEditingController(text: selectedText);
    EntityType type = EntityType.person;
    EntityAliasType aliasType = EntityAliasType.misrecognition;
    var highConfidence = true;
    try {
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('作为实体学习'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: canonicalCtrl,
                    decoration: const InputDecoration(
                      labelText: '标准名',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: aliasCtrl,
                    decoration: const InputDecoration(
                      labelText: '别名 / 原词',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<EntityType>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: '类型',
                      border: OutlineInputBorder(),
                    ),
                    items: EntityType.values
                        .map((value) {
                          return DropdownMenuItem(
                            value: value,
                            child: Text(_entityTypeLabel(value)),
                          );
                        })
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<EntityAliasType>(
                    initialValue: aliasType,
                    decoration: const InputDecoration(
                      labelText: '别名类型',
                      border: OutlineInputBorder(),
                    ),
                    items: EntityAliasType.values
                        .map((value) {
                          return DropdownMenuItem(
                            value: value,
                            child: Text(_entityAliasTypeLabel(value)),
                          );
                        })
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => aliasType = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: highConfidence,
                    title: const Text('立即提升为高置信'),
                    onChanged: (value) {
                      setState(() => highConfidence = value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
      if (shouldSave != true || !mounted) return;
      await context.read<SettingsProvider>().addManualEntity(
        canonicalName: canonicalCtrl.text.trim(),
        type: type,
        aliases: [aliasCtrl.text.trim()],
        aliasType: aliasType,
        confidence: highConfidence ? 0.98 : 0.85,
      );
      if (!mounted) return;
      _showFloatingSnackBar('已作为实体学习');
    } finally {
      canonicalCtrl.dispose();
      aliasCtrl.dispose();
    }
  }

  String _entityTypeLabel(EntityType type) {
    switch (type) {
      case EntityType.person:
        return '人名';
      case EntityType.company:
        return '公司';
      case EntityType.product:
        return '产品';
      case EntityType.project:
        return '项目';
      case EntityType.system:
        return '系统';
      case EntityType.custom:
        return '自定义';
    }
  }

  String _entityAliasTypeLabel(EntityAliasType type) {
    switch (type) {
      case EntityAliasType.fullName:
        return '全名';
      case EntityAliasType.nickname:
        return '小名';
      case EntityAliasType.alias:
        return '外号';
      case EntityAliasType.misrecognition:
        return '误识别';
      case EntityAliasType.abbreviation:
        return '缩写';
    }
  }

  void _confirmClearAll(
    BuildContext context,
    RecordingProvider recording,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clearHistory),
        content: Text(l10n.clearHistoryConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              recording.clearAllHistory();
              if (mounted) {
                setState(() {
                  _currentPage = 0;
                  _expandedRawText.clear();
                });
              }
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(l10n.clear),
          ),
        ],
      ),
    );
  }
}

class _ArchivePagerButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool destructive;
  final VoidCallback onPressed;

  const _ArchivePagerButton({
    required this.label,
    required this.enabled,
    this.destructive = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minWidth = label.runes.length > 2 ? 54.0 : 38.0;
    final accent = destructive ? Colors.redAccent : cs.primary;
    final borderColor = enabled
        ? destructive
              ? accent.withValues(alpha: 0.18)
              : cs.primary.withValues(alpha: 0.08)
        : cs.primary.withValues(alpha: 0.05);
    final background = enabled
        ? Color.alphaBlend(
            cs.primary.withValues(alpha: destructive ? 0.0 : 0.022),
            cs.surface.withValues(alpha: 0.96),
          )
        : Color.alphaBlend(
            cs.primary.withValues(alpha: 0.012),
            cs.surfaceContainerLow.withValues(alpha: 0.55),
          );
    final foreground = enabled
        ? destructive
              ? accent
              : cs.onSurfaceVariant.withValues(alpha: 0.84)
        : cs.onSurfaceVariant.withValues(alpha: 0.34);

    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? onPressed : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: Ink(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchiveActionButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool enabled;
  final bool selected;
  final bool destructive;
  final VoidCallback? onTap;

  const _ArchiveActionButton({
    required this.label,
    required this.tooltip,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minWidth = label.runes.length > 2 ? 54.0 : 38.0;
    final accent = destructive ? Colors.redAccent : cs.primary;
    final foreground = !enabled
        ? cs.onSurfaceVariant.withValues(alpha: 0.34)
        : destructive
        ? Colors.redAccent
        : selected
        ? cs.primary
        : cs.onSurfaceVariant.withValues(alpha: 0.84);
    final background = selected
        ? accent.withValues(alpha: 0.08)
        : Color.alphaBlend(
            cs.primary.withValues(alpha: 0.022),
            cs.surface.withValues(alpha: 0.96),
          );
    final borderColor = !enabled
        ? cs.primary.withValues(alpha: 0.05)
        : selected || destructive
        ? accent.withValues(alpha: destructive ? 0.18 : 0.22)
        : cs.primary.withValues(alpha: 0.08);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: Ink(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
