import 'dart:convert';
import 'dart:io';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../../models/dictionary_entry.dart';
import '../../models/dictation_term_pending_candidate.dart';
import '../../models/transcription.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/recording_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/dictionary_entry_dialog.dart';
import 'context_page.dart';

class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  ColorScheme get _cs => Theme.of(context).colorScheme;
  static const _historyCorrectionCategory = '历史修正';

  /// 当前选中的分类筛选（null = 全部）
  String? _selectedCategory;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _pendingSearchCtrl = TextEditingController();
  _EntryStatusFilter _statusFilter = _EntryStatusFilter.all;
  _PendingCandidateSort _pendingCandidateSort = _PendingCandidateSort.recent;
  _PendingCandidateFilter _pendingCandidateFilter = _PendingCandidateFilter.all;
  final Set<String> _selectedPendingCandidateIds = {};
  int _rowsPerPage = 100;
  int _currentPage = 0;

  static const List<int> _pageSizeOptions = [50, 100, 200, 500];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _pendingSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final recording = context.watch<RecordingProvider>();
    final l10n = AppLocalizations.of(context)!;
    final allEntries = settings.dictionaryEntries;
    final pendingCandidates = List<DictationTermPendingCandidate>.from(
      settings.dictationTermPendingCandidates,
    );
    final history = recording.history;
    final categories = settings.dictionaryCategories;
    final hasHistoryCorrectionEntries = allEntries.any(
      (entry) => entry.source == DictionaryEntrySource.historyEdit,
    );
    final search = _searchCtrl.text.trim().toLowerCase();
    final pendingSearch = _pendingSearchCtrl.text.trim().toLowerCase();

    final entries = allEntries.where((entry) {
      if (_selectedCategory == _historyCorrectionCategory &&
          entry.source != DictionaryEntrySource.historyEdit) {
        return false;
      }
      if (_selectedCategory != null &&
          _selectedCategory != _historyCorrectionCategory &&
          entry.category != _selectedCategory) {
        return false;
      }
      if (_statusFilter == _EntryStatusFilter.enabledOnly && !entry.enabled) {
        return false;
      }
      if (_statusFilter == _EntryStatusFilter.disabledOnly && entry.enabled) {
        return false;
      }
      if (search.isEmpty) return true;
      final inOriginal = entry.original.toLowerCase().contains(search);
      final inCorrected = (entry.corrected ?? '').toLowerCase().contains(
        search,
      );
      final inCategory = (entry.category ?? '').toLowerCase().contains(search);
      final inSource =
          entry.source == DictionaryEntrySource.historyEdit &&
          _historyCorrectionCategory.contains(search);
      final inPinyin = entry.pinyinNormalized.toLowerCase().contains(search);
      return inOriginal || inCorrected || inCategory || inSource || inPinyin;
    }).toList();

    entries.sort((a, b) {
      if (a.enabled != b.enabled) {
        return a.enabled ? -1 : 1;
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    pendingCandidates.removeWhere(
      (candidate) => !_matchesPendingCandidate(candidate, pendingSearch),
    );
    pendingCandidates.removeWhere(
      (candidate) => !_matchesPendingCandidateFilter(candidate),
    );
    _sortPendingCandidates(pendingCandidates);
    _selectedPendingCandidateIds.removeWhere(
      (id) => !pendingCandidates.any((candidate) => candidate.id == id),
    );

    final enabledCount = allEntries.where((e) => e.enabled).length;
    final disabledCount = allEntries.length - enabledCount;

    final totalPages = entries.isEmpty
        ? 1
        : ((entries.length - 1) ~/ _rowsPerPage) + 1;
    if (_currentPage >= totalPages) {
      _currentPage = totalPages - 1;
    }
    final pageStart = _currentPage * _rowsPerPage;
    final pageEntries = entries
        .skip(pageStart)
        .take(_rowsPerPage)
        .toList(growable: false);

    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: _cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _cs.outlineVariant),
              ),
              child: TabBar(
                tabs: [
                  Tab(text: l10n.dictionarySettings),
                  Tab(text: l10n.contextTab),
                ],
                labelColor: _cs.primary,
                unselectedLabelColor: _cs.onSurfaceVariant,
                indicatorSize: TabBarIndicatorSize.tab,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                children: [
                  _buildDictionaryTab(
                    settings: settings,
                    recording: recording,
                    l10n: l10n,
                    allEntries: allEntries,
                    pendingCandidates: pendingCandidates,
                    history: history,
                    categories: categories,
                    hasHistoryCorrectionEntries: hasHistoryCorrectionEntries,
                    entries: entries,
                    enabledCount: enabledCount,
                    disabledCount: disabledCount,
                    pageStart: pageStart,
                    pageEntries: pageEntries,
                    totalPages: totalPages,
                  ),
                  const ContextPage(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDictionaryTab({
    required SettingsProvider settings,
    required RecordingProvider recording,
    required AppLocalizations l10n,
    required List<DictionaryEntry> allEntries,
    required List<DictationTermPendingCandidate> pendingCandidates,
    required List<Transcription> history,
    required List<String> categories,
    required bool hasHistoryCorrectionEntries,
    required List<DictionaryEntry> entries,
    required int enabledCount,
    required int disabledCount,
    required int pageStart,
    required List<DictionaryEntry> pageEntries,
    required int totalPages,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pendingCandidates.isNotEmpty) ...[
          _buildPendingCandidatesCard(settings, pendingCandidates, history),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _cs.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 980;
                      final searchBox = SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => _resetToFirstPage(),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: l10n.dictionarySearchHint,
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: _cs.outline,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              size: 18,
                              color: _cs.outline,
                            ),
                            suffixIcon: _searchCtrl.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _resetToFirstPage();
                                    },
                                    icon: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: _cs.outline,
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 0,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: _cs.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: _cs.outlineVariant,
                              ),
                            ),
                            isDense: true,
                          ),
                        ),
                      );

                      final controls = Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildDropdownFilter<_EntryStatusFilter>(
                            value: _statusFilter,
                            items: [
                              (_EntryStatusFilter.all, l10n.dictionaryFilterAll),
                              (
                                _EntryStatusFilter.enabledOnly,
                                l10n.dictionaryFilterEnabled,
                              ),
                              (
                                _EntryStatusFilter.disabledOnly,
                                l10n.dictionaryFilterDisabled,
                              ),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _statusFilter = v;
                                _currentPage = 0;
                              });
                            },
                          ),
                          if (categories.isNotEmpty)
                            _buildDropdownFilter<String?>(
                              value: _selectedCategory,
                              items: [
                                (null, l10n.dictionaryCategoryAll),
                                ...categories.map((c) => (c, c)),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  _selectedCategory = v;
                                  _currentPage = 0;
                                });
                              },
                            ),
                          if (hasHistoryCorrectionEntries)
                            FilterChip(
                              label: const Text(
                                _historyCorrectionCategory,
                                style: TextStyle(fontSize: 12),
                              ),
                              selected:
                                  _selectedCategory == _historyCorrectionCategory,
                              onSelected: (_) {
                                setState(() {
                                  _selectedCategory =
                                      _selectedCategory ==
                                          _historyCorrectionCategory
                                      ? null
                                      : _historyCorrectionCategory;
                                  _currentPage = 0;
                                });
                              },
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          IconButton(
                            onPressed: () => _handleExportCsv(settings, l10n),
                            icon: Icon(
                              Icons.download_outlined,
                              size: 20,
                              color: _cs.onSurfaceVariant,
                            ),
                            tooltip: l10n.dictionaryExportCsv,
                          ),
                          IconButton(
                            onPressed: () => _handleImportCsv(settings, l10n),
                            icon: Icon(
                              Icons.upload_outlined,
                              size: 20,
                              color: _cs.onSurfaceVariant,
                            ),
                            tooltip: l10n.dictionaryImportCsv,
                          ),
                          IconButton(
                            onPressed: () => _handleAddEntry(settings),
                            icon: Icon(
                              Icons.add_circle_outline,
                              size: 22,
                              color: _cs.primary,
                            ),
                            tooltip: l10n.dictionaryAdd,
                          ),
                        ],
                      );

                      if (compact) {
                        return Column(
                          children: [
                            searchBox,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: controls,
                            ),
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: searchBox),
                          const SizedBox(width: 8),
                          Flexible(child: controls),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 760;
                      final metrics = Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          Text(
                            '${l10n.dictionaryCountTotal} ${allEntries.length}',
                            style: TextStyle(fontSize: 11, color: _cs.outline),
                          ),
                          Text(
                            '${l10n.dictionaryCountEnabled} $enabledCount',
                            style: TextStyle(fontSize: 11, color: _cs.outline),
                          ),
                          Text(
                            '${l10n.dictionaryCountDisabled} $disabledCount',
                            style: TextStyle(fontSize: 11, color: _cs.outline),
                          ),
                        ],
                      );
                      final paging = Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            l10n.dictionaryPageSummary(
                              entries.isEmpty ? 0 : pageStart + 1,
                              pageStart + pageEntries.length,
                              entries.length,
                            ),
                            style: TextStyle(fontSize: 11, color: _cs.outline),
                          ),
                          SizedBox(
                            width: 56,
                            height: 28,
                            child: DropdownButton<int>(
                              value: _rowsPerPage,
                              underline: const SizedBox.shrink(),
                              isDense: true,
                              isExpanded: true,
                              iconSize: 16,
                              style: TextStyle(
                                fontSize: 12,
                                color: _cs.onSurface,
                              ),
                              items: _pageSizeOptions
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text('$e'),
                                    ),
                                  )
                                  .toList(growable: false),
                              selectedItemBuilder: (context) => _pageSizeOptions
                                  .map(
                                    (e) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text('$e'),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _rowsPerPage = v;
                                  _currentPage = 0;
                                });
                              },
                            ),
                          ),
                          IconButton(
                            onPressed: _currentPage > 0
                                ? () => setState(() => _currentPage -= 1)
                                : null,
                            icon: const Icon(Icons.chevron_left, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            tooltip: l10n.dictionaryPagePrev,
                          ),
                          Text(
                            '${_currentPage + 1}/$totalPages',
                            style: TextStyle(fontSize: 11, color: _cs.outline),
                          ),
                          IconButton(
                            onPressed: _currentPage + 1 < totalPages
                                ? () => setState(() => _currentPage += 1)
                                : null,
                            icon: const Icon(Icons.chevron_right, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            tooltip: l10n.dictionaryPageNext,
                          ),
                        ],
                      );

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            metrics,
                            const SizedBox(height: 8),
                            paging,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: metrics),
                          const SizedBox(width: 12),
                          paging,
                        ],
                      );
                    },
                  ),
                ),
                Divider(height: 1, color: _cs.outlineVariant),
                if (entries.isEmpty)
                  _buildEmptyState(l10n)
                else
                  Expanded(
                    child: DataTable2(
                      columnSpacing: 12,
                      horizontalMargin: 16,
                      minWidth: 760,
                      headingRowHeight: 36,
                      dataRowHeight: 44,
                      headingRowColor: WidgetStateProperty.all(
                        _cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      ),
                      headingTextStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _cs.onSurfaceVariant,
                      ),
                      columns: [
                        const DataColumn2(label: Text('#'), fixedWidth: 44),
                        DataColumn2(
                          label: Text(l10n.dictionaryFilterEnabled),
                          fixedWidth: 60,
                        ),
                        DataColumn2(
                          label: Text(l10n.dictionaryTypeCorrection),
                          fixedWidth: 68,
                        ),
                        DataColumn2(
                          label: Text(l10n.dictionaryOriginal),
                          size: ColumnSize.L,
                        ),
                        DataColumn2(
                          label: Text(l10n.dictionaryCorrected),
                          size: ColumnSize.L,
                        ),
                        DataColumn2(
                          label: Text(l10n.dictionaryCategoryAll),
                          size: ColumnSize.S,
                        ),
                        if (settings.correctionEnabled)
                          DataColumn2(
                            label: Text(l10n.pinyinPreview),
                            size: ColumnSize.M,
                          ),
                        DataColumn2(label: Text(l10n.edit), fixedWidth: 88),
                      ],
                      rows: pageEntries
                          .asMap()
                          .entries
                          .map((e) {
                            final idx = pageStart + e.key + 1;
                            final entry = e.value;
                            final isCorr =
                                entry.type == DictionaryEntryType.correction;
                            final typeClr = isCorr ? _cs.primary : _cs.tertiary;

                            return DataRow2(
                              color: WidgetStateProperty.resolveWith<Color?>(
                                (states) => !entry.enabled
                                    ? _cs.surfaceContainerHighest.withValues(
                                        alpha: 0.3,
                                      )
                                    : null,
                              ),
                              cells: [
                                DataCell(
                                  Text(
                                    '$idx',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _cs.outline,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Center(
                                    child: Transform.scale(
                                      scale: 0.6,
                                      child: Switch(
                                        value: entry.enabled,
                                        onChanged: (v) =>
                                            settings.toggleDictionaryEntry(
                                              entry.id,
                                              v,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: typeClr.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isCorr
                                          ? l10n.dictionaryTypeCorrection
                                          : l10n.dictionaryTypePreserve,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: typeClr,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    entry.original.trim().isEmpty
                                        ? '—'
                                        : entry.original,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isCorr
                                          ? _cs.onSurfaceVariant
                                          : _cs.onSurface,
                                      decoration: isCorr
                                          ? TextDecoration.lineThrough
                                          : null,
                                      fontWeight: isCorr
                                          ? FontWeight.normal
                                          : FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    entry.corrected ?? '—',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _cs.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (entry.category != null &&
                                          entry.category!.isNotEmpty)
                                        _buildMetaTag(
                                          entry.category!,
                                          _cs.tertiary,
                                        ),
                                      if (entry.source ==
                                          DictionaryEntrySource.historyEdit) ...[
                                        if (entry.category != null &&
                                            entry.category!.isNotEmpty)
                                          const SizedBox(width: 4),
                                        _buildMetaTag(
                                          _historyCorrectionCategory,
                                          _cs.secondary,
                                        ),
                                      ],
                                      if (entry.source ==
                                          DictionaryEntrySource.markdownImport) ...[
                                        if ((entry.category != null &&
                                                entry.category!.isNotEmpty) ||
                                            entry.source ==
                                                DictionaryEntrySource
                                                    .historyEdit)
                                          const SizedBox(width: 4),
                                        _buildMetaTag('Markdown导入', _cs.primary),
                                      ],
                                      if ((entry.category == null ||
                                              entry.category!.isEmpty) &&
                                          entry.source !=
                                              DictionaryEntrySource.historyEdit &&
                                          entry.source !=
                                              DictionaryEntrySource
                                                  .markdownImport)
                                        Text(
                                          '—',
                                          style: TextStyle(color: _cs.outline),
                                        ),
                                    ],
                                  ),
                                ),
                                if (settings.correctionEnabled)
                                  DataCell(
                                    Text(
                                      entry.pinyinNormalized,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _cs.outline,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        onPressed: () =>
                                            _handleEditEntry(settings, entry),
                                        icon: Icon(
                                          Icons.edit_outlined,
                                          size: 15,
                                          color: _cs.onSurfaceVariant,
                                        ),
                                        tooltip: l10n.edit,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 30,
                                          minHeight: 30,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => settings
                                            .deleteDictionaryEntry(entry.id),
                                        icon: Icon(
                                          Icons.delete_outline,
                                          size: 15,
                                          color: _cs.error,
                                        ),
                                        tooltip: l10n.delete,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 30,
                                          minHeight: 30,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownFilter<T>({
    required T value,
    required List<(T, String)> items,
    required ValueChanged<T> onChanged,
  }) {
    return SizedBox(
      height: 36,
      child: PopupMenuButton<T>(
        initialValue: value,
        onSelected: onChanged,
        tooltip: '',
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _cs.outlineVariant),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                items.firstWhere((e) => e.$1 == value).$2,
                style: TextStyle(fontSize: 12, color: _cs.onSurface),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 18, color: _cs.outline),
            ],
          ),
        ),
        itemBuilder: (_) => items
            .map(
              (e) => PopupMenuItem<T>(
                value: e.$1,
                height: 36,
                child: Text(e.$2, style: const TextStyle(fontSize: 13)),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildPendingCandidatesCard(
    SettingsProvider settings,
    List<DictationTermPendingCandidate> pendingCandidates,
    List<Transcription> history,
  ) {
    final selectedCount = _selectedPendingCandidateIds.length;
    final hasSelection = selectedCount > 0;
    final allSelected =
        pendingCandidates.isNotEmpty &&
        selectedCount == pendingCandidates.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cs.outlineVariant),
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
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '待确认术语候选',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasSelection
                          ? '已选择 $selectedCount 条候选，可只处理选中的内容。'
                          : '来自历史修正的高置信候选，确认后会进入词典并立即影响后续听写。',
                      style: TextStyle(fontSize: 11, color: _cs.outline),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: allSelected,
                tristate: hasSelection && !allSelected,
                onChanged: (_) =>
                    _toggleSelectAllPendingCandidates(pendingCandidates),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                '全选',
                style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              _buildPendingSortDropdown(),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => hasSelection
                    ? _handleRejectSelectedPendingCandidates(settings)
                    : _handleRejectAllPendingCandidates(settings),
                child: Text(hasSelection ? '拒绝选中' : '全部拒绝'),
              ),
              const SizedBox(width: 4),
              FilledButton.tonal(
                onPressed: () => hasSelection
                    ? _handleAcceptSelectedPendingCandidates(settings)
                    : _handleAcceptAllPendingCandidates(settings),
                child: Text(hasSelection ? '接受选中' : '全部接受'),
              ),
              const SizedBox(width: 8),
              _buildMetaTag('${pendingCandidates.length} 条', _cs.secondary),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _pendingSearchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '搜索候选术语',
                      hintStyle: TextStyle(fontSize: 13, color: _cs.outline),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 18,
                        color: _cs.outline,
                      ),
                      suffixIcon: _pendingSearchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _pendingSearchCtrl.clear();
                                setState(() {});
                              },
                              icon: Icon(
                                Icons.close,
                                size: 14,
                                color: _cs.outline,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _cs.outlineVariant),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildPendingFilterDropdown(),
            ],
          ),
          const SizedBox(height: 14),
          if (pendingCandidates.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: _cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _cs.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Center(
                child: Text(
                  '当前筛选条件下没有候选术语',
                  style: TextStyle(fontSize: 12, color: _cs.outline),
                ),
              ),
            )
          else
            ...pendingCandidates.map(
              (candidate) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildPendingCandidateRow(
                  settings,
                  candidate,
                  history,
                  isSelected: _selectedPendingCandidateIds.contains(
                    candidate.id,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPendingCandidateRow(
    SettingsProvider settings,
    DictationTermPendingCandidate candidate,
    List<Transcription> history, {
    required bool isSelected,
  }) {
    final confidence = (candidate.confidence * 100).round().clamp(0, 100);
    final sourceHistory = _findSourceHistory(
      history,
      candidate.sourceHistoryId,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: (_) => _togglePendingCandidateSelection(candidate.id),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      '${candidate.original} -> ${candidate.corrected}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _cs.onSurface,
                      ),
                    ),
                    _buildMetaTag('置信度 $confidence%', _cs.primary),
                    _buildMetaTag('历史修正', _cs.secondary),
                    if (candidate.category != null &&
                        candidate.category!.isNotEmpty)
                      _buildMetaTag(candidate.category!, _cs.tertiary),
                    if (candidate.occurrenceCount > 1)
                      _buildMetaTag(
                        '累计 ${candidate.occurrenceCount} 次',
                        _cs.outline,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _pendingCandidateSummary(candidate, sourceHistory),
                  style: TextStyle(fontSize: 11, color: _cs.outline),
                ),
                if (sourceHistory != null) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () =>
                        _showPendingCandidateSource(candidate, sourceHistory),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _pendingCandidatePreview(sourceHistory),
                        style: TextStyle(
                          fontSize: 11,
                          color: _cs.primary,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => _handleEditPendingCandidate(settings, candidate),
            icon: Icon(
              Icons.edit_outlined,
              size: 16,
              color: _cs.onSurfaceVariant,
            ),
            tooltip: '编辑候选',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 4),
          if (sourceHistory != null)
            IconButton(
              onPressed: () =>
                  _showPendingCandidateSource(candidate, sourceHistory),
              icon: Icon(
                Icons.visibility_outlined,
                size: 16,
                color: _cs.primary,
              ),
              tooltip: '查看来源',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => _handleRejectPendingCandidate(settings, candidate),
            child: const Text('拒绝'),
          ),
          const SizedBox(width: 4),
          FilledButton.tonal(
            onPressed: () => _handleAcceptPendingCandidate(settings, candidate),
            child: const Text('接受并入词典'),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingSortDropdown() {
    return SizedBox(
      height: 32,
      child: PopupMenuButton<_PendingCandidateSort>(
        initialValue: _pendingCandidateSort,
        onSelected: (value) {
          setState(() {
            _pendingCandidateSort = value;
          });
        },
        tooltip: '',
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _cs.outlineVariant),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _pendingCandidateSort.label,
                style: TextStyle(fontSize: 12, color: _cs.onSurface),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 18, color: _cs.outline),
            ],
          ),
        ),
        itemBuilder: (_) => _PendingCandidateSort.values
            .map(
              (sort) => PopupMenuItem<_PendingCandidateSort>(
                value: sort,
                height: 36,
                child: Text(sort.label, style: const TextStyle(fontSize: 13)),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildPendingFilterDropdown() {
    return SizedBox(
      height: 32,
      child: PopupMenuButton<_PendingCandidateFilter>(
        initialValue: _pendingCandidateFilter,
        onSelected: (value) {
          setState(() {
            _pendingCandidateFilter = value;
          });
        },
        tooltip: '',
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _cs.outlineVariant),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _pendingCandidateFilter.label,
                style: TextStyle(fontSize: 12, color: _cs.onSurface),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 18, color: _cs.outline),
            ],
          ),
        ),
        itemBuilder: (_) => _PendingCandidateFilter.values
            .map(
              (filter) => PopupMenuItem<_PendingCandidateFilter>(
                value: filter,
                height: 36,
                child: Text(filter.label, style: const TextStyle(fontSize: 13)),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cs.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.menu_book_outlined, size: 40, color: _cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            l10n.dictionaryEmpty,
            style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.dictionaryEmptyHint,
            style: TextStyle(fontSize: 12, color: _cs.outline),
          ),
        ],
      ),
    );
  }

  /// 统一的添加/编辑对话框
  Future<void> _handleAddEntry(SettingsProvider settings) async {
    final entry = await showDictionaryEntryDialog(context);
    if (entry != null) {
      await settings.addDictionaryEntry(entry);
      await _applySessionGlossaryOverride(entry);
    }
  }

  Future<void> _handleEditEntry(
    SettingsProvider settings,
    DictionaryEntry existing,
  ) async {
    final entry = await showDictionaryEntryDialog(context, existing: existing);
    if (entry != null) {
      await settings.updateDictionaryEntry(entry);
      await _applySessionGlossaryOverride(entry);
    }
  }

  Future<void> _handleAcceptPendingCandidate(
    SettingsProvider settings,
    DictationTermPendingCandidate candidate,
  ) async {
    final beforeCount = settings.dictationTermPendingCandidates.length;
    final confirmed = await _confirmAcceptPendingCandidates([candidate]);
    if (!confirmed) return;
    final entry = await settings.acceptTermPendingCandidate(candidate.id);
    if (entry == null) return;
    await _applySessionGlossaryOverride(entry);
    _showCompletionAwareSnackBar(
      settings,
      beforeCount: beforeCount,
      fallbackMessage: '已加入词典: ${entry.original} -> ${entry.corrected ?? ''}',
    );
  }

  Future<void> _handleRejectPendingCandidate(
    SettingsProvider settings,
    DictationTermPendingCandidate candidate,
  ) async {
    final beforeCount = settings.dictationTermPendingCandidates.length;
    await settings.rejectTermPendingCandidate(candidate.id);
    _showCompletionAwareSnackBar(
      settings,
      beforeCount: beforeCount,
      fallbackMessage: '已忽略候选: ${candidate.original}',
    );
  }

  Future<void> _handleEditPendingCandidate(
    SettingsProvider settings,
    DictationTermPendingCandidate candidate,
  ) async {
    final originalController = TextEditingController(text: candidate.original);
    final correctedController = TextEditingController(
      text: candidate.corrected,
    );
    final categoryController = TextEditingController(
      text: candidate.category ?? '',
    );
    final edited = await showDialog<(String, String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑候选术语'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: originalController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '原词',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: correctedController,
                decoration: const InputDecoration(
                  labelText: '修正词',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(
                  labelText: '分类（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, (
              originalController.text.trim(),
              correctedController.text.trim(),
              categoryController.text.trim(),
            )),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    originalController.dispose();
    correctedController.dispose();
    categoryController.dispose();

    if (edited == null) return;
    final nextOriginal = edited.$1.trim();
    final nextCorrected = edited.$2.trim();
    final nextCategory = edited.$3.trim();
    if (nextOriginal.isEmpty || nextCorrected.isEmpty) {
      _showSnackBar('原词和修正词都不能为空', isError: true);
      return;
    }
    if (nextOriginal == candidate.original &&
        nextCorrected == candidate.corrected &&
        nextCategory == (candidate.category ?? '')) {
      return;
    }

    final updated = await settings.updateTermPendingCandidate(
      id: candidate.id,
      original: nextOriginal,
      corrected: nextCorrected,
      category: nextCategory,
    );
    if (!mounted) return;
    _selectedPendingCandidateIds.remove(candidate.id);
    if (updated == null) {
      _showSnackBar('该术语已存在于词典，候选已自动移除');
      return;
    }
    _showSnackBar(
      updated.category == null || updated.category!.isEmpty
          ? '已更新候选: ${updated.original} -> ${updated.corrected}'
          : '已更新候选: ${updated.original} -> ${updated.corrected} [${updated.category}]',
    );
  }

  Future<void> _handleAcceptAllPendingCandidates(
    SettingsProvider settings,
  ) async {
    final candidates = settings.dictationTermPendingCandidates;
    final beforeCount = candidates.length;
    final confirmed = await _confirmAcceptPendingCandidates(candidates);
    if (!confirmed) return;
    final entries = await settings.acceptAllTermPendingCandidates();
    for (final entry in entries) {
      await _applySessionGlossaryOverride(entry);
    }
    if (entries.isEmpty) return;
    setState(() {
      _selectedPendingCandidateIds.clear();
    });
    _showCompletionAwareSnackBar(
      settings,
      beforeCount: beforeCount,
      fallbackMessage: '已批量加入词典: ${entries.length} 条',
    );
  }

  Future<void> _handleRejectAllPendingCandidates(
    SettingsProvider settings,
  ) async {
    final count = settings.dictationTermPendingCandidates.length;
    await settings.rejectAllTermPendingCandidates();
    if (count == 0) return;
    setState(() {
      _selectedPendingCandidateIds.clear();
    });
    _showCompletionAwareSnackBar(
      settings,
      beforeCount: count,
      fallbackMessage: '已批量忽略候选: $count 条',
    );
  }

  Future<void> _handleAcceptSelectedPendingCandidates(
    SettingsProvider settings,
  ) async {
    final selectedIds = _selectedPendingCandidateIds.toList(growable: false);
    final candidates = settings.dictationTermPendingCandidates
        .where((candidate) => selectedIds.contains(candidate.id))
        .toList(growable: false);
    final beforeCount = settings.dictationTermPendingCandidates.length;
    final confirmed = await _confirmAcceptPendingCandidates(candidates);
    if (!confirmed) return;
    final entries = await settings.acceptTermPendingCandidates(selectedIds);
    for (final entry in entries) {
      await _applySessionGlossaryOverride(entry);
    }
    if (entries.isEmpty) return;
    setState(() {
      _selectedPendingCandidateIds.clear();
    });
    _showCompletionAwareSnackBar(
      settings,
      beforeCount: beforeCount,
      fallbackMessage: '已将选中候选加入词典: ${entries.length} 条',
    );
  }

  Future<void> _handleRejectSelectedPendingCandidates(
    SettingsProvider settings,
  ) async {
    final count = _selectedPendingCandidateIds.length;
    final beforeCount = settings.dictationTermPendingCandidates.length;
    await settings.rejectTermPendingCandidates(_selectedPendingCandidateIds);
    if (count == 0) return;
    setState(() {
      _selectedPendingCandidateIds.clear();
    });
    _showCompletionAwareSnackBar(
      settings,
      beforeCount: beforeCount,
      fallbackMessage: '已忽略选中候选: $count 条',
    );
  }

  Future<bool> _confirmAcceptPendingCandidates(
    List<DictationTermPendingCandidate> candidates,
  ) async {
    if (candidates.isEmpty) return false;
    final history = Provider.of<RecordingProvider>(
      context,
      listen: false,
    ).history;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(candidates.length == 1 ? '确认加入词典' : '确认批量加入词典'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                candidates.length == 1
                    ? '以下候选将写入正式词典，并立即用于后续听写修正：'
                    : '以下 ${candidates.length} 条候选将写入正式词典，并立即用于后续听写修正：',
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Column(
                    children: candidates
                        .map(
                          (candidate) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildAcceptPreviewCard(
                              ctx,
                              candidate,
                              _findSourceHistory(
                                history,
                                candidate.sourceHistoryId,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
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
            child: Text(candidates.length == 1 ? '确认加入' : '确认批量加入'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _showPendingCandidateSource(
    DictationTermPendingCandidate candidate,
    Transcription sourceHistory,
  ) async {
    final createdAt = DateFormat('M月d日 HH:mm').format(sourceHistory.createdAt);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('候选来源'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildMetaTag(
                    '${candidate.original} -> ${candidate.corrected}',
                    Theme.of(ctx).colorScheme.primary,
                  ),
                  if (candidate.category != null &&
                      candidate.category!.isNotEmpty)
                    _buildMetaTag(
                      candidate.category!,
                      Theme.of(ctx).colorScheme.tertiary,
                    ),
                  _buildMetaTag(createdAt, Theme.of(ctx).colorScheme.secondary),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '修正后的历史文本',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              _buildSourceTextCard(
                ctx,
                sourceHistory.text,
                candidate: candidate,
                preferCorrected: true,
              ),
              if (sourceHistory.hasRawText) ...[
                const SizedBox(height: 14),
                Text(
                  '原始识别文本',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                _buildSourceTextCard(
                  ctx,
                  sourceHistory.rawText ?? '',
                  candidate: candidate,
                  preferCorrected: false,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: sourceHistory.text));
              Navigator.pop(ctx);
              _showSnackBar('已复制来源文本');
            },
            child: const Text('复制来源文本'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptPreviewCard(
    BuildContext context,
    DictationTermPendingCandidate candidate,
    Transcription? sourceHistory,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetaTag(
                '${candidate.original} -> ${candidate.corrected}',
                colorScheme.primary,
              ),
              if (candidate.category != null && candidate.category!.isNotEmpty)
                _buildMetaTag(candidate.category!, colorScheme.tertiary),
              _buildMetaTag('历史修正', colorScheme.secondary),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sourceHistory == null
                ? '来源: 历史记录已不可用'
                : _pendingCandidatePreview(sourceHistory),
            style: TextStyle(fontSize: 11, color: colorScheme.outline),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _applySessionGlossaryOverride(DictionaryEntry entry) async {
    if (entry.type != DictionaryEntryType.correction) return;
    final corrected = (entry.corrected ?? '').trim();
    if (corrected.isEmpty) return;

    final recording = Provider.of<RecordingProvider?>(context, listen: false);
    final meeting = Provider.of<MeetingProvider?>(context, listen: false);
    recording?.applySessionGlossaryOverride(entry.original, corrected);
    meeting?.applySessionGlossaryOverride(entry.original, corrected);
  }

  Future<void> _handleExportCsv(
    SettingsProvider settings,
    AppLocalizations l10n,
  ) async {
    try {
      final now = DateTime.now();
      final fileName =
          'dictionary_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.csv';

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.dictionaryExportCsv,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (savePath == null || savePath.trim().isEmpty) return;

      final targetPath = savePath.toLowerCase().endsWith('.csv')
          ? savePath
          : '$savePath.csv';
      final csv = settings.exportDictionaryAsCsv();
      await File(targetPath).writeAsString('\uFEFF$csv', encoding: utf8);

      _showSnackBar(l10n.dictionaryExportSuccess(targetPath));
    } catch (_) {
      _showSnackBar(l10n.dictionaryExportFailed, isError: true);
    }
  }

  Future<void> _handleImportCsv(
    SettingsProvider settings,
    AppLocalizations l10n,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: l10n.dictionaryImportCsv,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null || path.trim().isEmpty) {
        _showSnackBar(l10n.dictionaryImportFailed, isError: true);
        return;
      }

      final csvContent = await File(path).readAsString(encoding: utf8);
      final imported = await settings.importDictionaryFromCsv(csvContent);
      _resetToFirstPage();

      _showSnackBar(
        l10n.dictionaryImportSuccess(
          imported.importedRows,
          imported.skippedRows,
          imported.totalRows,
        ),
      );
    } on FormatException {
      _showSnackBar(l10n.dictionaryImportInvalidFormat, isError: true);
    } catch (_) {
      _showSnackBar(l10n.dictionaryImportFailed, isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _cs.error : null,
      ),
    );
  }

  void _showCompletionAwareSnackBar(
    SettingsProvider settings, {
    required int beforeCount,
    required String fallbackMessage,
  }) {
    final afterCount = settings.dictationTermPendingCandidates.length;
    if (beforeCount > 0 && afterCount == 0) {
      _showSnackBar('待确认术语候选已全部处理完');
      return;
    }
    _showSnackBar(fallbackMessage);
  }

  Widget _buildMetaTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: color.withValues(alpha: 0.1),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  void _resetToFirstPage() {
    setState(() {
      _currentPage = 0;
    });
  }

  void _sortPendingCandidates(List<DictationTermPendingCandidate> candidates) {
    candidates.sort((a, b) {
      switch (_pendingCandidateSort) {
        case _PendingCandidateSort.recent:
          return b.createdAt.compareTo(a.createdAt);
        case _PendingCandidateSort.occurrence:
          final byCount = b.occurrenceCount.compareTo(a.occurrenceCount);
          if (byCount != 0) return byCount;
          return b.createdAt.compareTo(a.createdAt);
        case _PendingCandidateSort.confidence:
          final byConfidence = b.confidence.compareTo(a.confidence);
          if (byConfidence != 0) return byConfidence;
          return b.createdAt.compareTo(a.createdAt);
      }
    });
  }

  bool _matchesPendingCandidate(
    DictationTermPendingCandidate candidate,
    String pendingSearch,
  ) {
    if (pendingSearch.isEmpty) return true;
    return candidate.original.toLowerCase().contains(pendingSearch) ||
        candidate.corrected.toLowerCase().contains(pendingSearch) ||
        (candidate.category ?? '').toLowerCase().contains(pendingSearch);
  }

  bool _matchesPendingCandidateFilter(DictationTermPendingCandidate candidate) {
    switch (_pendingCandidateFilter) {
      case _PendingCandidateFilter.all:
        return true;
      case _PendingCandidateFilter.highFrequency:
        return candidate.occurrenceCount >= 2;
      case _PendingCandidateFilter.highConfidence:
        return candidate.confidence >= 0.8;
    }
  }

  void _togglePendingCandidateSelection(String id) {
    setState(() {
      if (_selectedPendingCandidateIds.contains(id)) {
        _selectedPendingCandidateIds.remove(id);
      } else {
        _selectedPendingCandidateIds.add(id);
      }
    });
  }

  void _toggleSelectAllPendingCandidates(
    List<DictationTermPendingCandidate> pendingCandidates,
  ) {
    final candidateIds = pendingCandidates.map((candidate) => candidate.id);
    final allSelected =
        pendingCandidates.isNotEmpty &&
        pendingCandidates.every(
          (candidate) => _selectedPendingCandidateIds.contains(candidate.id),
        );
    setState(() {
      if (allSelected) {
        _selectedPendingCandidateIds.removeAll(candidateIds);
      } else {
        _selectedPendingCandidateIds.addAll(candidateIds);
      }
    });
  }

  Transcription? _findSourceHistory(
    List<Transcription> history,
    String? sourceHistoryId,
  ) {
    if (sourceHistoryId == null || sourceHistoryId.isEmpty) {
      return null;
    }
    for (final item in history) {
      if (item.id == sourceHistoryId) {
        return item;
      }
    }
    return null;
  }

  String _pendingCandidateSummary(
    DictationTermPendingCandidate candidate,
    Transcription? sourceHistory,
  ) {
    if (sourceHistory != null) {
      final formatted = DateFormat(
        'M月d日 HH:mm',
      ).format(sourceHistory.createdAt);
      return '最近来自 $formatted 的历史修正';
    }
    if (DateTime.now().difference(candidate.createdAt).inDays == 0) {
      return '刚刚加入待确认列表';
    }
    return '加入于 ${candidate.createdAt.month}/${candidate.createdAt.day}';
  }

  String _pendingCandidatePreview(Transcription sourceHistory) {
    final text = sourceHistory.text.trim();
    if (text.isEmpty) {
      return '来源文本为空';
    }
    if (text.length <= 48) {
      return '来源: $text';
    }
    return '来源: ${text.substring(0, 48)}...';
  }

  Widget _buildSourceTextCard(
    BuildContext context,
    String text, {
    required DictationTermPendingCandidate candidate,
    required bool preferCorrected,
  }) {
    final displayText = text.trim().isEmpty ? '暂无内容' : text;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: SelectableText.rich(
          _buildHighlightedSourceText(
            context,
            displayText,
            candidate: candidate,
            preferCorrected: preferCorrected,
          ),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.55,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  TextSpan _buildHighlightedSourceText(
    BuildContext context,
    String text, {
    required DictationTermPendingCandidate candidate,
    required bool preferCorrected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryTerm = preferCorrected
        ? candidate.corrected.trim()
        : candidate.original.trim();
    final secondaryTerm = preferCorrected
        ? candidate.original.trim()
        : candidate.corrected.trim();
    final spans = <InlineSpan>[];
    var cursor = 0;

    void addNormal(String value) {
      if (value.isEmpty) return;
      spans.add(TextSpan(text: value));
    }

    void addHighlight(String value, Color background, Color foreground) {
      if (value.isEmpty) return;
      spans.add(
        TextSpan(
          text: value,
          style: TextStyle(
            backgroundColor: background,
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final ranges = <({int start, int end, bool primary})>[
      ..._findAllCaseInsensitiveRanges(
        text,
        primaryTerm,
      ).map((range) => (start: range.$1, end: range.$2, primary: true)),
    ];
    final primaryRanges = ranges
        .map((range) => (range.start, range.end))
        .toList(growable: false);
    ranges.addAll(
      _findAllCaseInsensitiveRanges(text, secondaryTerm)
          .where(
            (secondaryRange) => !_hasOverlap(secondaryRange, primaryRanges),
          )
          .map((range) => (start: range.$1, end: range.$2, primary: false)),
    );
    ranges.sort((a, b) => a.start.compareTo(b.start));

    for (final range in ranges) {
      if (range.start > cursor) {
        addNormal(text.substring(cursor, range.start));
      }
      final highlightText = text.substring(range.start, range.end);
      if (range.primary) {
        addHighlight(
          highlightText,
          colorScheme.primaryContainer,
          colorScheme.onPrimaryContainer,
        );
      } else {
        addHighlight(
          highlightText,
          colorScheme.secondaryContainer,
          colorScheme.onSecondaryContainer,
        );
      }
      cursor = range.end;
    }

    if (cursor < text.length) {
      addNormal(text.substring(cursor));
    }

    return TextSpan(children: spans);
  }

  List<(int, int)> _findAllCaseInsensitiveRanges(String text, String keyword) {
    final normalizedKeyword = keyword.trim();
    if (normalizedKeyword.isEmpty) return const [];
    final lowerText = text.toLowerCase();
    final lowerKeyword = normalizedKeyword.toLowerCase();
    final ranges = <(int, int)>[];
    var searchStart = 0;
    while (searchStart < lowerText.length) {
      final start = lowerText.indexOf(lowerKeyword, searchStart);
      if (start < 0) break;
      ranges.add((start, start + normalizedKeyword.length));
      searchStart = start + normalizedKeyword.length;
    }
    return ranges;
  }

  bool _hasOverlap((int, int) target, List<(int, int)> ranges) {
    for (final range in ranges) {
      if (target.$1 < range.$2 && target.$2 > range.$1) {
        return true;
      }
    }
    return false;
  }
}

enum _EntryStatusFilter { all, enabledOnly, disabledOnly }

enum _PendingCandidateSort {
  recent('按最近'),
  occurrence('按出现次数'),
  confidence('按置信度');

  const _PendingCandidateSort(this.label);

  final String label;
}

enum _PendingCandidateFilter {
  all('全部候选'),
  highFrequency('高频候选'),
  highConfidence('高置信');

  const _PendingCandidateFilter(this.label);

  final String label;
}
