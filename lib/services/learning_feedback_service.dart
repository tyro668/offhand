import '../models/memory_event.dart';
import '../models/memory_item.dart';
import '../models/stt_request_context.dart';
import 'dictation_term_memory_service.dart';
import 'memory_evolution_engine.dart';
import 'session_glossary.dart';

class LearningFeedbackResult {
  final List<MemoryItem> items;
  final List<MemoryEvent> events;
  final List<MemoryItem> learnedItems;

  const LearningFeedbackResult({
    required this.items,
    this.events = const [],
    this.learnedItems = const [],
  });

  bool get hasChanges => events.isNotEmpty || learnedItems.isNotEmpty;
}

class LearningFeedbackService {
  final DictationTermMemoryService termMemoryService;
  final MemoryEvolutionEngine evolutionEngine;

  const LearningFeedbackService({
    this.termMemoryService = const DictationTermMemoryService(),
    this.evolutionEngine = const MemoryEvolutionEngine(),
  });

  LearningFeedbackResult recordHistoryEdit({
    required List<MemoryItem> currentItems,
    required String beforeText,
    required String afterText,
    String? rawText,
    String sourceHistoryId = '',
  }) {
    final candidates = termMemoryService.extractCandidates(
      beforeText: beforeText,
      afterText: afterText,
      rawText: rawText,
    );
    if (candidates.isEmpty) {
      return LearningFeedbackResult(items: currentItems);
    }

    var nextItems = currentItems;
    final events = <MemoryEvent>[];
    final learned = <MemoryItem>[];
    for (final candidate in candidates) {
      if (_isSuppressed(
        nextItems,
        original: candidate.original,
        canonical: candidate.corrected,
      )) {
        continue;
      }
      final result = evolutionEngine.observeCorrection(
        currentItems: nextItems,
        original: candidate.original,
        canonical: candidate.corrected,
        sourceType: 'history_edit',
        sourceRef: sourceHistoryId,
        beforeText: beforeText,
        afterText: afterText,
        rawText: rawText,
        confidence: candidate.confidence,
        source: 'history_edit',
      );
      nextItems = result.items;
      events.add(result.event);
      learned.add(result.item);
    }

    return LearningFeedbackResult(
      items: nextItems,
      events: events,
      learnedItems: learned,
    );
  }

  LearningFeedbackResult flushSessionGlossary({
    required List<MemoryItem> currentItems,
    required Map<String, TermPin> strongEntries,
    String sourceRef = '',
  }) {
    if (strongEntries.isEmpty) {
      return LearningFeedbackResult(items: currentItems);
    }

    var nextItems = currentItems;
    final events = <MemoryEvent>[];
    final learned = <MemoryItem>[];
    for (final pin in strongEntries.values) {
      if (pin.original.trim().isEmpty ||
          pin.corrected.trim().isEmpty ||
          pin.original.trim() == pin.corrected.trim()) {
        continue;
      }
      if (_isSuppressed(
        nextItems,
        original: pin.original,
        canonical: pin.corrected,
      )) {
        continue;
      }
      final result = evolutionEngine.observeCorrection(
        currentItems: nextItems,
        original: pin.original,
        canonical: pin.corrected,
        sourceType: 'session_glossary',
        sourceRef: sourceRef,
        confidence: 0.78,
        scope: MemoryItemScope.session,
        initialStatus: MemoryItemStatus.weakActive,
        source: 'session',
      );
      nextItems = result.items;
      events.add(result.event);
      learned.add(result.item);
    }

    return LearningFeedbackResult(
      items: nextItems,
      events: events,
      learnedItems: learned,
    );
  }

  LearningFeedbackResult recordPromptInjected({
    required List<MemoryItem> currentItems,
    required SttRequestContext context,
  }) {
    final ids = context.includedMemoryItemIds.toSet();
    if (ids.isEmpty) {
      return LearningFeedbackResult(items: currentItems);
    }

    final nextItems = evolutionEngine.recordPromptInjected(currentItems, ids);
    final byId = {for (final item in nextItems) item.id: item};
    final events = <MemoryEvent>[];
    for (final id in ids) {
      final item = byId[id];
      if (item == null) continue;
      events.add(
        MemoryEvent.create(
          memoryId: id,
          eventType: MemoryEventType.promptInjected,
          sourceType: 'prompt_trace',
          sourceRef: context.promptTraceId ?? '',
          original: item.original,
          canonical: item.canonical,
          strengthDelta: 0.1,
        ),
      );
    }

    return LearningFeedbackResult(items: nextItems, events: events);
  }

  LearningFeedbackResult recordCorrectionHit({
    required List<MemoryItem> currentItems,
    required Iterable<String> memoryItemIds,
    String sourceRef = '',
  }) {
    final ids = memoryItemIds.toSet();
    if (ids.isEmpty) {
      return LearningFeedbackResult(items: currentItems);
    }

    final nextItems = evolutionEngine.recordCorrectionHit(currentItems, ids);
    final byId = {for (final item in nextItems) item.id: item};
    final events = <MemoryEvent>[];
    for (final id in ids) {
      final item = byId[id];
      if (item == null) continue;
      events.add(
        MemoryEvent.create(
          memoryId: id,
          eventType: MemoryEventType.correctionHit,
          sourceType: 'correction_log',
          sourceRef: sourceRef,
          original: item.original,
          canonical: item.canonical,
          strengthDelta: 1,
        ),
      );
    }

    return LearningFeedbackResult(items: nextItems, events: events);
  }

  bool _isSuppressed(
    List<MemoryItem> items, {
    required String original,
    required String canonical,
  }) {
    final key = MemoryItem.buildKey(
      kind: MemoryItemKind.correction,
      original: original,
      canonical: canonical,
    );
    final now = DateTime.now();
    for (final item in items) {
      if (item.normalizedKey != key ||
          item.status != MemoryItemStatus.suppressed) {
        continue;
      }
      final cooldown = item.cooldownUntil;
      if (cooldown == null || cooldown.isAfter(now)) return true;
    }
    return false;
  }
}
