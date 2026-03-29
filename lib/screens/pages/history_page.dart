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
import '../../models/transcription.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/recording_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/dictation_term_memory_service.dart';
import '../../widgets/dictionary_entry_dialog.dart';

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

  /// 记录哪些 item id 的原始文本处于展开状态
  final Set<String> _expandedRawText = {};

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
    final hasLearnableEditedHistory = history.any(
      (item) =>
          recording.isHistoryEdited(item.id) &&
          item.hasRawText &&
          item.rawText!.trim().isNotEmpty &&
          item.rawText!.trim() != item.text.trim(),
    );
    final l10n = AppLocalizations.of(context)!;

    return Container(
      color: _cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 22,
                color: _cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.history,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _cs.onSurface,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (hasLearnableEditedHistory)
                IconButton(
                  icon: Icon(
                    Icons.sync_alt_rounded,
                    color: _cs.primary,
                    size: 22,
                  ),
                  tooltip: '同步历史修正',
                  onPressed: () =>
                      _syncEditedHistoryCorrections(recording, settings),
                ),
              if (history.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: _cs.outline.withValues(alpha: 0.55),
                    size: 22,
                  ),
                  tooltip: l10n.clearAll,
                  onPressed: () => _confirmClearAll(context, recording, l10n),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (pendingCandidates.isNotEmpty) ...[
            _buildPendingCandidatesSummary(pendingCandidates),
            const SizedBox(height: 16),
          ],
          // 列表
          Expanded(
            child: history.isEmpty
                ? _buildEmpty(l10n)
                : _buildList(context, recording, history, l10n),
          ),
        ],
      ),
    );
  }

  Future<void> _syncEditedHistoryCorrections(
    RecordingProvider recording,
    SettingsProvider settings,
  ) async {
    final meeting = context.read<MeetingProvider?>();
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
        meeting?.applySessionGlossaryOverride(entry.original, corrected);
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
        meeting?.activateSessionEntity(
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            size: 52,
            color: _cs.outline.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.noHistory,
            style: TextStyle(fontSize: 15, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.historyHint,
            style: TextStyle(
              fontSize: 13,
              color: _cs.outline.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCandidatesSummary(
    List<DictationTermPendingCandidate> pendingCandidates,
  ) {
    final previewItems = pendingCandidates.take(3).toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.3)),
      ),
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
        color: _cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.5)),
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
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    RecordingProvider recording,
    List<Transcription> history,
    AppLocalizations l10n,
  ) {
    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[index];
        final number = history.length - index;
        final dateStr = DateFormat('M月d日 HH:mm').format(item.createdAt);
        final wasEdited = recording.isHistoryEdited(item.id);

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: _cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _cs.outlineVariant.withValues(alpha: 0.28),
            ),
            boxShadow: [
              BoxShadow(
                color: _cs.shadow.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：编号 + 时间 + 操作按钮
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE7F6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '#$number',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF5C3BBF),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 13,
                      color: _cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  if (wasEdited) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _editedBadgeText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _cs.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // 复制按钮
                  _ActionIcon(
                    icon: Icons.copy_outlined,
                    tooltip: l10n.copy,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: item.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.copiedToClipboard),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  _ActionIcon(
                    icon: Icons.edit_outlined,
                    tooltip: l10n.edit,
                    onTap: () => _editHistoryItem(item),
                  ),
                  const SizedBox(width: 4),
                  // 删除按钮
                  _ActionIcon(
                    icon: Icons.delete_outline,
                    tooltip: l10n.delete,
                    color: Colors.red.shade300,
                    onTap: () => recording.removeHistory(index),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 文本内容（右键可加入词典）
              SelectableText(
                item.text,
                style: TextStyle(
                  fontSize: 14.5,
                  color: _cs.onSurface.withValues(alpha: 0.88),
                  height: 1.65,
                ),
                contextMenuBuilder: (ctx, editableTextState) {
                  final selectedText = editableTextState
                      .textEditingValue
                      .selection
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
              ),
              // 原始录音文字（折叠/展开）
              if (item.hasRawText) ...[
                const SizedBox(height: 8),
                _buildRawTextToggle(item, l10n),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRawTextToggle(dynamic item, AppLocalizations l10n) {
    final isExpanded = _expandedRawText.contains(item.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedRawText.remove(item.id);
              } else {
                _expandedRawText.add(item.id);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: _cs.outline.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.originalSttText,
                  style: TextStyle(
                    fontSize: 12,
                    color: _cs.outline.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              item.rawText ?? '',
              style: TextStyle(
                fontSize: 13,
                color: _cs.onSurfaceVariant.withValues(alpha: 0.8),
                height: 1.55,
              ),
            ),
          ),
        ],
      ],
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

    final candidates = _termMemoryService.extractCandidates(
      beforeText: item.text,
      afterText: nextText,
      rawText: item.rawText,
    );

    final recording = context.read<RecordingProvider>();
    final settings = context.read<SettingsProvider>();
    await recording.updateHistoryText(item.id, nextText);

    if (candidates.isEmpty || !mounted) {
      return;
    }

    final meeting = context.read<MeetingProvider?>();
    final learnedTerms = <String>[];
    for (final candidate in candidates) {
      final entry = await settings.upsertDictionaryCorrectionEntry(
        original: candidate.original,
        corrected: candidate.corrected,
        source: DictionaryEntrySource.historyEdit,
      );
      final corrected = (entry.corrected ?? '').trim();
      if (corrected.isNotEmpty) {
        recording.applySessionGlossaryOverride(entry.original, corrected);
        meeting?.applySessionGlossaryOverride(entry.original, corrected);
        learnedTerms.add('${entry.original} -> $corrected');
      }
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
      meeting?.activateSessionEntity(
        entityId: entity.id,
        canonicalName: entity.canonicalName,
        alias: entity.canonicalName,
      );
    }

    if (!mounted || (learnedTerms.isEmpty && learnedEntities.isEmpty)) return;
    final entityNames = learnedEntities
        .map((e) => e.canonicalName)
        .toSet()
        .toList(growable: false);
    final summary = <String>[
      if (learnedTerms.isNotEmpty) '已学习 ${learnedTerms.length} 条历史修正',
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
                    value: type,
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
                    value: aliasType,
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

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            icon,
            size: 18,
            color: color ?? cs.outline.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}
