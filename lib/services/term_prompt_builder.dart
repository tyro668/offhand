import '../models/dictionary_entry.dart';
import '../models/entity_alias.dart';
import '../models/entity_memory.dart';
import '../models/entity_prompt_bundle.dart';
import '../models/entity_relation.dart';
import '../models/memory_item.dart';
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
    List<MemoryItem> memoryItems = const [],
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
    final promptMemoryItems = _promptEligibleMemoryItems(memoryItems);
    final activeMemoryTerms = _activeMemoryPreferredTerms(promptMemoryItems);
    final activeMemoryReferences = _activeMemoryReferences(promptMemoryItems);
    final includedMemoryItemIds = promptMemoryItems
        .map((item) => item.id)
        .toList(growable: false);
    final includedWeakMemoryItemIds = memoryItems
        .where(
          (item) =>
              item.status == MemoryItemStatus.weakActive &&
              item.kind == MemoryItemKind.correction &&
              item.isCorrectionEligible &&
              item.original.trim().isNotEmpty &&
              item.canonical.trim().isNotEmpty &&
              item.original.trim() != item.canonical.trim(),
        )
        .map((item) => item.id)
        .toList(growable: false);

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
        activeMemoryTerms.isEmpty &&
        activeMemoryReferences.isEmpty &&
        contextDocuments.isEmpty &&
        !entityBundle.hasPromptData) {
      return const TermPromptBundle();
    }

    final mergedPreferredTerms = {
      ...preferredTerms,
      ...activeMemoryTerms,
      ...entityBundle.entities.map((e) => e.memory.canonicalName),
    }.toList(growable: false);
    final preserveTerms = mergedPreferredTerms.toList(growable: false);
    final correctionReferences = _buildCorrectionReferences(
      dictionaryEntries,
      sessionGlossary,
      memoryItems,
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
    if (activeMemoryReferences.isNotEmpty) {
      prompt.writeln('参考以下记忆片段：');
      for (final item in activeMemoryReferences.take(3)) {
        prompt.writeln('[${item.displayText}]');
        prompt.writeln(_truncateContext(item.content ?? item.displayText));
      }
    }
    if (entityBundle.sttSection.trim().isNotEmpty) {
      prompt.writeln(entityBundle.sttSection.trim());
    }

    final memoryPromptSuffix = _buildMemoryPromptSuffix(
      preferredTerms: mergedPreferredTerms,
      correctionReferences: correctionReferences,
      contextDocuments: contextDocuments,
      memoryReferences: activeMemoryReferences,
      entityBundle: entityBundle,
    );

    return TermPromptBundle(
      sttPrompt: prompt.toString().trim(),
      memoryPromptSuffix: memoryPromptSuffix,
      preferredTerms: mergedPreferredTerms,
      preserveTerms: preserveTerms,
      correctionReferences: correctionReferences,
      includedMemoryItemIds: includedMemoryItemIds,
      includedWeakMemoryItemIds: includedWeakMemoryItemIds,
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

  String _buildMemoryPromptSuffix({
    required List<String> preferredTerms,
    required List<String> correctionReferences,
    required List<TermContextEntry> contextDocuments,
    required List<MemoryItem> memoryReferences,
    required EntityPromptBundle entityBundle,
  }) {
    final buf = StringBuffer();

    if (preferredTerms.isNotEmpty) {
      buf.writeln();
      buf.writeln('【听写记忆参考】');
      buf.writeln('请优先保持以下术语、名称与写法一致：');
      for (final term in preferredTerms.take(20)) {
        buf.writeln('- $term');
      }
    }

    if (correctionReferences.isNotEmpty) {
      if (buf.isEmpty) {
        buf.writeln();
        buf.writeln('【听写记忆参考】');
      }
      buf.writeln('若出现同音、近音或误写，请优先参考以下纠正规则：');
      for (final item in correctionReferences.take(20)) {
        buf.writeln('- $item');
      }
    }

    if (contextDocuments.isNotEmpty) {
      if (buf.isEmpty) {
        buf.writeln();
        buf.writeln('【听写记忆参考】');
      }
      buf.writeln('可参考以下上下文资料：');
      for (final entry in contextDocuments) {
        buf.writeln('[${entry.displayTitle}]');
        buf.writeln(_truncateContext(entry.content ?? ''));
      }
    }

    if (memoryReferences.isNotEmpty) {
      if (buf.isEmpty) {
        buf.writeln();
        buf.writeln('【听写记忆参考】');
      }
      buf.writeln('可参考以下手动记忆片段：');
      for (final item in memoryReferences.take(5)) {
        buf.writeln('[${item.displayText}]');
        buf.writeln(_truncateContext(item.content ?? item.displayText));
      }
    }

    if (entityBundle.correctionEntitySection.trim().isNotEmpty) {
      if (buf.isEmpty) {
        buf.writeln();
        buf.writeln('【听写记忆参考】');
      }
      buf.writeln('以下实体名称、别称和误识别映射需要优先保持一致：');
      buf.writeln(entityBundle.correctionEntitySection.trim());
    }

    if (entityBundle.correctionRelationSection.trim().isNotEmpty) {
      if (buf.isEmpty) {
        buf.writeln();
        buf.writeln('【听写记忆参考】');
      }
      buf.writeln('实体关系参考：');
      buf.writeln(entityBundle.correctionRelationSection.trim());
    }

    return buf.toString().trimRight();
  }

  List<String> _buildCorrectionReferences(
    List<DictionaryEntry> dictionaryEntries,
    SessionGlossary sessionGlossary,
    List<MemoryItem> memoryItems,
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
    for (final item in memoryItems.where((item) => item.isCorrectionEligible)) {
      if (item.kind != MemoryItemKind.correction) continue;
      final original = item.original.trim();
      final canonical = item.canonical.trim();
      if (original.isEmpty || canonical.isEmpty || original == canonical) {
        continue;
      }
      refs.add('$original->$canonical');
      for (final alias in item.aliases) {
        final value = alias.trim();
        if (value.isEmpty || value == canonical) continue;
        refs.add('$value->$canonical');
      }
    }
    return refs.toList(growable: false);
  }

  List<MemoryItem> _promptEligibleMemoryItems(List<MemoryItem> memoryItems) {
    return memoryItems
        .where((item) {
          if (!item.isPromptEligible) return false;
          switch (item.kind) {
            case MemoryItemKind.correction:
            case MemoryItemKind.preserve:
            case MemoryItemKind.entity:
              return item.displayText.trim().isNotEmpty;
            case MemoryItemKind.reference:
              return (item.content ?? item.displayText).trim().isNotEmpty;
          }
        })
        .toList(growable: false);
  }

  List<MemoryItem> _activeMemoryReferences(List<MemoryItem> memoryItems) {
    return memoryItems
        .where(
          (item) =>
              item.kind == MemoryItemKind.reference &&
              (item.content ?? item.displayText).trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  List<String> _activeMemoryPreferredTerms(List<MemoryItem> memoryItems) {
    final terms = <String>{};
    for (final item in memoryItems) {
      switch (item.kind) {
        case MemoryItemKind.correction:
        case MemoryItemKind.preserve:
        case MemoryItemKind.entity:
          final value = item.displayText.trim();
          if (value.isNotEmpty) terms.add(value);
          break;
        case MemoryItemKind.reference:
          break;
      }
    }
    return terms.toList(growable: false);
  }
}
