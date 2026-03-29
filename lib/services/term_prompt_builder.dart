import '../models/dictionary_entry.dart';
import '../models/entity_alias.dart';
import '../models/entity_memory.dart';
import '../models/entity_relation.dart';
import '../models/term_context_entry.dart';
import '../models/term_prompt_bundle.dart';
import '../models/transcription.dart';
import 'entity_recall_service.dart';
import 'session_glossary.dart';
import 'session_entity_state.dart';
import 'term_recall_service.dart';

class TermPromptBuilder {
  final TermRecallService recallService;
  final EntityRecallService entityRecallService;

  const TermPromptBuilder({
    this.recallService = const TermRecallService(),
    this.entityRecallService = const EntityRecallService(),
  });

  TermPromptBundle build({
    required String scene,
    required String currentText,
    required List<Transcription> history,
    required List<DictionaryEntry> dictionaryEntries,
    required SessionGlossary sessionGlossary,
    SessionEntityState? sessionEntityState,
    List<TermContextEntry> termContextEntries = const [],
    List<EntityMemory> entityMemories = const [],
    List<EntityAlias> entityAliases = const [],
    List<EntityRelation> entityRelations = const [],
    int maxTerms = TermRecallService.defaultMaxTerms,
  }) {
    final contextDocuments = _selectContextDocuments(termContextEntries);
    final preferredTerms = recallService.recallPreferredTerms(
      currentText: currentText,
      history: history,
      dictionaryEntries: dictionaryEntries,
      sessionGlossary: sessionGlossary,
      termContextEntries: termContextEntries,
      maxTerms: maxTerms,
    );

    final entityBundle = entityRecallService.buildForStt(
      currentText: currentText,
      historyTexts: history.take(5).map((e) => e.text).toList(growable: false),
      contextTexts: contextDocuments
          .map((e) => _truncateContext(e.content ?? ''))
          .toList(growable: false),
      memories: entityMemories,
      aliases: entityAliases,
      relations: entityRelations,
      sessionState: sessionEntityState ?? SessionEntityState(),
    );

    if (preferredTerms.isEmpty &&
        contextDocuments.isEmpty &&
        !entityBundle.hasPromptData) {
      return const TermPromptBundle();
    }

    final mergedPreferredTerms = <String>[
      ...preferredTerms,
      ...entityBundle.entities.map((e) => e.memory.canonicalName),
    ].toSet().toList(growable: false);
    final preserveTerms = mergedPreferredTerms.toList(growable: false);
    final correctionReferences = _buildCorrectionReferences(
      dictionaryEntries,
      sessionGlossary,
    );

    final prompt = StringBuffer()
      ..writeln('请将这段音频准确转写为纯文本，仅返回转写结果。')
      ..writeln('当前场景：$scene。');
    if (mergedPreferredTerms.isNotEmpty) {
      prompt.writeln('优先识别并保持以下术语写法：');
      for (final term in mergedPreferredTerms) {
        prompt.writeln('- $term');
      }
      prompt.writeln('若听到相近发音，优先输出上述写法。');
    }
    if (contextDocuments.isNotEmpty) {
      prompt.writeln('参考以下上下文：');
      for (final entry in contextDocuments) {
        prompt.writeln('[${entry.displayTitle}]');
        prompt.writeln(_truncateContext(entry.content ?? ''));
      }
    }
    if (entityBundle.sttSection.trim().isNotEmpty) {
      prompt.writeln(entityBundle.sttSection.trim());
    }

    return TermPromptBundle(
      sttPrompt: prompt.toString().trim(),
      preferredTerms: mergedPreferredTerms,
      preserveTerms: preserveTerms,
      correctionReferences: correctionReferences,
      entityCorrectionSection: entityBundle.correctionEntitySection,
      entityRelationSection: entityBundle.correctionRelationSection,
    );
  }

  List<TermContextEntry> _selectContextDocuments(
    List<TermContextEntry> termContextEntries,
  ) {
    return termContextEntries
        .where((e) => e.enabled && e.isDocumentContext)
        .take(3)
        .toList(growable: false);
  }

  String _truncateContext(String content) {
    final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 1200) return normalized;
    return '${normalized.substring(0, 1200)}...';
  }

  List<String> _buildCorrectionReferences(
    List<DictionaryEntry> dictionaryEntries,
    SessionGlossary sessionGlossary,
  ) {
    final refs = <String>{};
    for (final pin in sessionGlossary.strongEntries.values) {
      if (pin.original.trim().isNotEmpty && pin.corrected.trim().isNotEmpty) {
        refs.add('${pin.original}->${pin.corrected}');
      }
    }
    for (final entry in dictionaryEntries.where((e) => e.enabled)) {
      final original = entry.original.trim();
      final corrected = (entry.corrected ?? '').trim();
      if (entry.type == DictionaryEntryType.correction &&
          original.isNotEmpty &&
          corrected.isNotEmpty) {
        refs.add('$original->$corrected');
      }
    }
    return refs.toList(growable: false);
  }
}
