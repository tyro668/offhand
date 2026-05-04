import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt_template.dart';
import '../../providers/settings_provider.dart';
import '../../services/ai_enhance_service.dart';
import '../../services/correction_context.dart';
import '../../services/correction_service.dart';
import 'package:lpinyin/lpinyin.dart';
import '../../models/dictionary_entry.dart';

class PromptWorkshopPage extends StatefulWidget {
  const PromptWorkshopPage({super.key});

  @override
  State<PromptWorkshopPage> createState() => _PromptWorkshopPageState();
}

class _PromptWorkshopPageState extends State<PromptWorkshopPage> {
  ColorScheme get _cs => Theme.of(context).colorScheme;

  String _localizedTemplateName(
    PromptTemplate template,
    AppLocalizations l10n,
  ) {
    if (!template.isBuiltin) return template.name;
    switch (template.id) {
      case PromptTemplate.defaultBuiltinId:
        return l10n.promptBuiltinDefaultName;
      case 'builtin_punctuation':
        return l10n.promptBuiltinPunctuationName;
      case 'builtin_formal':
        return l10n.promptBuiltinFormalName;
      case 'builtin_colloquial':
        return l10n.promptBuiltinColloquialName;
      case 'builtin_translate_en':
        return l10n.promptBuiltinTranslateEnName;
      default:
        return template.name;
    }
  }

  String _localizedTemplateSummary(
    PromptTemplate template,
    AppLocalizations l10n,
  ) {
    if (!template.isBuiltin) return template.summary;
    switch (template.id) {
      case PromptTemplate.defaultBuiltinId:
        return l10n.promptBuiltinDefaultSummary;
      case 'builtin_punctuation':
        return l10n.promptBuiltinPunctuationSummary;
      case 'builtin_formal':
        return l10n.promptBuiltinFormalSummary;
      case 'builtin_colloquial':
        return l10n.promptBuiltinColloquialSummary;
      case 'builtin_translate_en':
        return l10n.promptBuiltinTranslateEnSummary;
      default:
        return template.summary;
    }
  }

  final _testInputController = TextEditingController();
  final _testOutputController = TextEditingController();
  bool _testing = false;
  String _testError = '';
  String? _previewTemplateId;
  bool _showTest = false;

  @override
  void dispose() {
    _testInputController.dispose();
    _testOutputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use side-by-side layout when wide enough, otherwise stack
        final wide = constraints.maxWidth >= 680;
        if (wide) {
          return _buildSplitLayout(settings, l10n);
        }
        return _buildStackedLayout(settings, l10n);
      },
    );
  }

  // ===== Split layout: list left, detail right =====

  Widget _buildSplitLayout(SettingsProvider settings, AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: template list
        SizedBox(width: 260, child: _buildTemplateList(settings, l10n)),
        // Divider
        Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 16),
          color: _cs.outlineVariant.withValues(alpha: 0.5),
        ),
        // Right: detail / test panel
        Expanded(child: _buildDetailPanel(settings, l10n)),
      ],
    );
  }

  // ===== Stacked layout for narrow screens =====

  Widget _buildStackedLayout(SettingsProvider settings, AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTemplateGrid(settings, l10n),
          const SizedBox(height: 16),
          _buildDetailCard(settings, l10n),
        ],
      ),
    );
  }

  // ===== Template list (left panel) =====

  Widget _buildTemplateList(SettingsProvider settings, AppLocalizations l10n) {
    final templates = settings.promptTemplates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header — aligned with right panel title
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 16, 16),
          child: Row(
            children: [
              Text(
                l10n.promptTemplates,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _cs.onSurface,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              Material(
                color: _cs.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _showCreateTemplateDialog(settings, l10n),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: _cs.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Template items
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemCount: templates.length,
            separatorBuilder: (context, index) => const SizedBox(height: 2),
            itemBuilder: (_, i) =>
                _buildTemplateListItem(templates[i], settings, l10n),
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateListItem(
    PromptTemplate template,
    SettingsProvider settings,
    AppLocalizations l10n,
  ) {
    final isActive = settings.activePromptTemplateId == template.id;
    final isPreviewing = _previewTemplateId == template.id;
    final selectedTone = isActive || isPreviewing;

    return Material(
      color: selectedTone
          ? _cs.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        hoverColor: _cs.surfaceContainerHighest.withValues(alpha: 0.5),
        onTap: () {
          setState(() {
            _previewTemplateId = template.id;
            _showTest = false;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: selectedTone
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _cs.primary.withValues(alpha: 0.22),
                  ),
                )
              : null,
          child: Row(
            children: [
              // Active indicator bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 5,
                height: 34,
                decoration: BoxDecoration(
                  color: selectedTone ? _cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _localizedTemplateName(template, l10n),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selectedTone
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: selectedTone ? _cs.primary : _cs.onSurface,
                              height: 1.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (template.isBuiltin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: _cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              l10n.promptBuiltin,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                color: _cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _cs.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _cs.primary.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Text(
                              l10n.currentlyInUse,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: _cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _localizedTemplateSummary(template, l10n),
                      style: TextStyle(
                        fontSize: 11,
                        color: _cs.outline,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (selectedTone)
                Icon(
                  isActive ? Icons.check_circle_rounded : Icons.visibility,
                  size: 16,
                  color: _cs.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== Detail panel (right side) =====

  Widget _buildDetailPanel(SettingsProvider settings, AppLocalizations l10n) {
    final template = _resolvePreviewTemplate(settings);
    if (template == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 40,
                color: _cs.outlineVariant,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.promptSelectHint,
                style: TextStyle(fontSize: 14, color: _cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Template header
          _buildDetailHeader(template, settings, l10n),
          const SizedBox(height: 20),
          // Toggle: preview / test
          _buildDetailToggle(l10n),
          const SizedBox(height: 20),
          if (!_showTest)
            _buildPreviewContent(template)
          else
            _buildTestPanel(settings, l10n),
        ],
      ),
    );
  }

  Widget _buildDetailHeader(
    PromptTemplate template,
    SettingsProvider settings,
    AppLocalizations l10n,
  ) {
    final isActive = settings.activePromptTemplateId == template.id;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localizedTemplateName(template, l10n),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _cs.onSurface,
                  letterSpacing: -0.3,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _localizedTemplateSummary(template, l10n),
                style: TextStyle(fontSize: 13, color: _cs.outline, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (!isActive)
          FilledButton.tonalIcon(
            onPressed: () => settings.setActivePromptTemplate(template.id),
            icon: const Icon(Icons.check, size: 16),
            label: Text(
              l10n.useThisModel,
              style: const TextStyle(fontSize: 12),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _cs.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 14, color: _cs.onPrimary),
                const SizedBox(width: 4),
                Text(
                  l10n.inUse,
                  style: TextStyle(
                    fontSize: 12,
                    color: _cs.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (!template.isBuiltin) ...[
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'edit') {
                _showEditTemplateDialog(template, settings, l10n);
              } else if (action == 'delete') {
                settings.deletePromptTemplate(template.id);
                setState(() => _previewTemplateId = null);
              }
            },
            icon: Icon(Icons.more_vert, size: 20, color: _cs.onSurfaceVariant),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.edit),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 16, color: Colors.red.shade400),
                    const SizedBox(width: 8),
                    Text(
                      l10n.delete,
                      style: TextStyle(color: Colors.red.shade400),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDetailToggle(AppLocalizations l10n) {
    return Row(
      children: [
        _buildToggleChip(
          label: l10n.promptPreview,
          icon: Icons.visibility_outlined,
          selected: !_showTest,
          onTap: () => setState(() => _showTest = false),
        ),
        const SizedBox(width: 8),
        _buildToggleChip(
          label: l10n.test,
          icon: Icons.play_arrow_outlined,
          selected: _showTest,
          onTap: () => setState(() => _showTest = true),
        ),
      ],
    );
  }

  Widget _buildToggleChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? _cs.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: _cs.surfaceContainerHighest.withValues(alpha: 0.5),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? _cs.primary.withValues(alpha: 0.4)
                  : _cs.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? _cs.primary : _cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? _cs.primary : _cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewContent(PromptTemplate template) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: SelectableText(
        template.content,
        style: TextStyle(fontSize: 13, height: 1.7, color: _cs.onSurface),
      ),
    );
  }

  // ===== Test panel =====

  Widget _buildTestPanel(SettingsProvider settings, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Input
        _buildFieldLabel(l10n.testInput),
        const SizedBox(height: 6),
        TextField(
          controller: _testInputController,
          maxLines: 4,
          style: const TextStyle(fontSize: 13),
          decoration: _fieldDecoration(l10n.enterTestText),
        ),
        const SizedBox(height: 12),
        // Run button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _testing ? null : () => _runTest(settings),
            icon: _testing
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _cs.onPrimary,
                    ),
                  )
                : const Icon(Icons.play_arrow, size: 16),
            label: Text(
              _testing ? l10n.running : l10n.runTest,
              style: const TextStyle(fontSize: 13),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        if (_testError.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              _testError,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // Output
        _buildFieldLabel(l10n.outputResult),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 100),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _cs.outlineVariant.withValues(alpha: 0.28),
            ),
          ),
          child: _testOutputController.text.isEmpty
              ? Text(
                  l10n.outputWillAppearHere,
                  style: TextStyle(fontSize: 13, color: _cs.outline),
                )
              : SelectableText(
                  _testOutputController.text,
                  style: TextStyle(
                    fontSize: 13,
                    color: _cs.onSurface,
                    height: 1.5,
                  ),
                ),
        ),
      ],
    );
  }

  // ===== Template grid for narrow layout =====

  Widget _buildTemplateGrid(SettingsProvider settings, AppLocalizations l10n) {
    final templates = settings.promptTemplates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 18,
              color: _cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.promptTemplates,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ),
            SizedBox(
              height: 28,
              width: 28,
              child: IconButton(
                onPressed: () => _showCreateTemplateDialog(settings, l10n),
                icon: Icon(Icons.add, size: 16, color: _cs.primary),
                padding: EdgeInsets.zero,
                tooltip: l10n.promptCreateTemplate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: templates.map((t) {
            final isActive = settings.activePromptTemplateId == t.id;
            final isPreviewing = _previewTemplateId == t.id;
            return ChoiceChip(
              label: Text(_localizedTemplateName(t, l10n)),
              selected: isPreviewing,
              avatar: isActive
                  ? Icon(Icons.check_circle, size: 16, color: _cs.primary)
                  : null,
              backgroundColor: _cs.primary.withValues(alpha: 0.03),
              selectedColor: _cs.primary.withValues(alpha: 0.10),
              side: BorderSide(color: _cs.primary.withValues(alpha: 0.10)),
              labelStyle: TextStyle(
                fontWeight: isPreviewing || isActive
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: isPreviewing || isActive
                    ? _cs.primary
                    : _cs.onSurfaceVariant,
              ),
              onSelected: (_) {
                setState(() {
                  _previewTemplateId = t.id;
                  _showTest = false;
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDetailCard(SettingsProvider settings, AppLocalizations l10n) {
    final template = _resolvePreviewTemplate(settings);
    if (template == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailHeader(template, settings, l10n),
          const SizedBox(height: 16),
          _buildDetailToggle(l10n),
          const SizedBox(height: 16),
          if (!_showTest)
            _buildPreviewContent(template)
          else
            _buildTestPanel(settings, l10n),
        ],
      ),
    );
  }

  // ===== Helpers =====

  PromptTemplate? _resolvePreviewTemplate(SettingsProvider settings) {
    final templates = settings.promptTemplates;
    if (templates.isEmpty) return null;
    final id = _previewTemplateId ?? settings.activePromptTemplateId;
    try {
      return templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return templates.first;
    }
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _cs.onSurfaceVariant,
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _cs.outline, fontSize: 13),
      filled: true,
      fillColor: _cs.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _cs.primary, width: 1.5),
      ),
    );
  }

  Future<void> _runTest(SettingsProvider settings) async {
    setState(() {
      _testing = true;
      _testError = '';
      _testOutputController.text = '';
    });

    final correctionEntries = _activeCorrectionEntries(settings);

    try {
      var inputText = _testInputController.text;

      // 若纠错已启用且词典非空，先执行字典纠错
      if (settings.correctionEnabled &&
          settings.dictionaryEntries.isNotEmpty &&
          settings.correctionPrompt.isNotEmpty) {
        final correctionService = CorrectionService(
          matcher: settings.pinyinMatcher,
          context: CorrectionContext(),
          aiConfig: settings.effectiveAiEnhanceConfig,
          correctionPrompt: settings.correctionPrompt,
          maxReferenceEntries: settings.correctionMaxReferenceEntries,
          minCandidateScore: settings.correctionMinCandidateScore,
        );
        final correctionResult = await correctionService.correct(inputText);
        inputText = correctionResult.text;
      }
      if (correctionEntries.isNotEmpty) {
        inputText = _applyDictionaryCorrections(inputText, correctionEntries);
      }

      final config = settings.effectiveAiEnhanceConfig;
      final service = AiEnhanceService(config);
      final outputBuffer = StringBuffer();
      await for (final chunk in service.enhanceStream(inputText)) {
        if (!mounted) break;
        outputBuffer.write(chunk);
        setState(() {
          _testOutputController.text = outputBuffer.toString();
        });
      }

      var outputText = outputBuffer.toString().trim();
      if (outputText.isEmpty) {
        final result = await service.enhance(inputText);
        outputText = result.text;
      }
      if (correctionEntries.isNotEmpty) {
        outputText = _applyDictionaryCorrections(outputText, correctionEntries);
        outputText = _restoreChineseTermsFromTransliteration(
          outputText,
          correctionEntries,
        );
      }
      if (mounted) {
        setState(() {
          _testOutputController.text = outputText;
        });
      } else {
        _testOutputController.text = outputText;
      }
    } catch (e) {
      setState(() {
        _testError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  List<DictionaryEntry> _activeCorrectionEntries(SettingsProvider settings) {
    return settings.dictionaryEntries
        .where(
          (e) =>
              e.enabled &&
              e.type == DictionaryEntryType.correction &&
              e.corrected != null &&
              e.corrected!.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  String _applyDictionaryCorrections(
    String text,
    List<DictionaryEntry> entries,
  ) {
    var output = text;
    for (final entry in entries) {
      final original = entry.original.trim();
      final corrected = (entry.corrected ?? '').trim();
      if (original.isEmpty || corrected.isEmpty) continue;
      final target = _dictionaryOutputTarget(entry);
      output = output.replaceAll(original, target);
      if (_isChineseToLatinAlias(entry)) {
        output = output.replaceAll(
          RegExp(RegExp.escape(corrected), caseSensitive: false),
          original,
        );
      }
    }
    return output;
  }

  bool _containsChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }

  String _pinyinWithSeparator(String text, {required String separator}) {
    if (text.trim().isEmpty) return '';
    try {
      return PinyinHelper.getPinyinE(
        text,
        separator: separator,
        defPinyin: '#',
        format: PinyinFormat.WITHOUT_TONE,
      ).toLowerCase().replaceAll('#', '').trim();
    } catch (_) {
      return '';
    }
  }

  String _restoreChineseTermsFromTransliteration(
    String text,
    List<DictionaryEntry> entries,
  ) {
    var output = text;
    for (final entry in entries) {
      final corrected = _preferredChineseTerm(entry);
      if (corrected == null || corrected.isEmpty) continue;

      final pinyinSpaced = _pinyinWithSeparator(corrected, separator: ' ');
      if (pinyinSpaced.isEmpty) continue;

      final syllables = pinyinSpaced
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (syllables.isEmpty) continue;

      final pattern = RegExp(
        '\\b${syllables.map(RegExp.escape).join(r'[\\s_-]*')}\\b',
        caseSensitive: false,
      );
      output = output.replaceAll(pattern, corrected);
    }
    return output;
  }

  bool _isChineseToLatinAlias(DictionaryEntry entry) {
    final original = entry.original.trim();
    final corrected = (entry.corrected ?? '').trim();
    return corrected.isNotEmpty &&
        _containsChinese(original) &&
        !_containsChinese(corrected);
  }

  String _dictionaryOutputTarget(DictionaryEntry entry) {
    final original = entry.original.trim();
    final corrected = (entry.corrected ?? '').trim();
    if (corrected.isEmpty) return original;
    if (_isChineseToLatinAlias(entry)) {
      return original;
    }
    return corrected;
  }

  String? _preferredChineseTerm(DictionaryEntry entry) {
    final original = entry.original.trim();
    if (_containsChinese(original)) {
      return original;
    }
    final corrected = (entry.corrected ?? '').trim();
    if (_containsChinese(corrected)) {
      return corrected;
    }
    return null;
  }

  void _showEditTemplateDialog(
    PromptTemplate template,
    SettingsProvider settings,
    AppLocalizations l10n,
  ) {
    final contentController = TextEditingController(text: template.content);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${l10n.edit}: ${template.name}'),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: contentController,
            decoration: InputDecoration(
              labelText: l10n.promptTemplateContent,
              border: const OutlineInputBorder(),
            ),
            maxLines: 10,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              settings.updatePromptTemplate(
                template.copyWith(
                  content: contentController.text,
                  summary: PromptTemplate.defaultSummaryFromContent(
                    contentController.text,
                  ),
                ),
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.promptTemplateSaved),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Text(l10n.saveChanges),
          ),
        ],
      ),
    );
  }

  void _showCreateTemplateDialog(
    SettingsProvider settings,
    AppLocalizations l10n,
  ) {
    final nameController = TextEditingController();
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.promptCreateTemplate),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l10n.promptTemplateName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: InputDecoration(
                  labelText: l10n.promptTemplateContent,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 6,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) return;
              final template = PromptTemplate.create(
                name: nameController.text.trim(),
                content: contentController.text.trim(),
              );
              settings.addPromptTemplate(template);
              Navigator.pop(ctx);
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }
}
