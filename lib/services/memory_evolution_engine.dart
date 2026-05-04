import '../models/memory_event.dart';
import '../models/memory_item.dart';

class MemoryEvolutionResult {
  final List<MemoryItem> items;
  final MemoryItem item;
  final MemoryEvent event;

  const MemoryEvolutionResult({
    required this.items,
    required this.item,
    required this.event,
  });
}

class MemoryEvolutionEngine {
  const MemoryEvolutionEngine();

  MemoryEvolutionResult observeCorrection({
    required List<MemoryItem> currentItems,
    required String original,
    required String canonical,
    required String sourceType,
    String sourceRef = '',
    String? beforeText,
    String? afterText,
    String? rawText,
    double confidence = 0.7,
    MemoryItemScope scope = MemoryItemScope.user,
    MemoryItemStatus initialStatus = MemoryItemStatus.pending,
    String source = 'history_edit',
  }) {
    final event = MemoryEvent.create(
      eventType: MemoryEventType.observe,
      sourceType: sourceType,
      sourceRef: sourceRef,
      original: original,
      canonical: canonical,
      beforeTextExcerpt: _excerpt(beforeText),
      afterTextExcerpt: _excerpt(afterText),
      rawTextExcerpt: _excerpt(rawText),
      confidenceDelta: confidence,
      strengthDelta: 1,
    );

    final key = MemoryItem.buildKey(
      kind: MemoryItemKind.correction,
      original: original,
      canonical: canonical,
    );
    final existingIndex = currentItems.indexWhere((item) {
      return item.normalizedKey == key &&
          item.status != MemoryItemStatus.archived;
    });

    final now = event.createdAt;
    if (existingIndex >= 0) {
      final existing = currentItems[existingIndex];
      final nextStats = existing.stats.add(evidence: 1, positive: 1);
      final nextStatus = _statusAfterPositiveEvidence(
        existing.status,
        nextStats: nextStats,
        confidence: _max(existing.confidence, confidence),
        now: now,
        cooldownUntil: existing.cooldownUntil,
      );
      final updated = existing.copyWith(
        status: nextStatus,
        confidence: _max(existing.confidence, confidence),
        strength: existing.strength + 1,
        lastSeenAt: now,
        updatedAt: now,
        stats: nextStats,
      );
      final items = List<MemoryItem>.from(currentItems);
      items[existingIndex] = updated;
      return MemoryEvolutionResult(
        items: items,
        item: updated,
        event: event.copyWith(memoryId: updated.id),
      );
    }

    final stats = const MemoryItemStats().add(evidence: 1, positive: 1);
    final created = MemoryItem.create(
      kind: MemoryItemKind.correction,
      status: initialStatus,
      scope: scope,
      original: original,
      canonical: canonical,
      source: source,
      confidence: confidence,
      strength: 1,
      now: now,
      stats: stats,
    );
    return MemoryEvolutionResult(
      items: [created, ...currentItems],
      item: created,
      event: event.copyWith(memoryId: created.id),
    );
  }

  List<MemoryItem> accept(List<MemoryItem> items, String id) {
    return _updateStatus(
      items,
      id,
      status: MemoryItemStatus.active,
      clearCooldown: true,
      positive: 1,
    );
  }

  List<MemoryItem> suppress(
    List<MemoryItem> items,
    String id, {
    Duration cooldown = const Duration(days: 90),
  }) {
    return _updateStatus(
      items,
      id,
      status: MemoryItemStatus.suppressed,
      cooldownUntil: DateTime.now().add(cooldown),
      negative: 1,
      rejected: 1,
    );
  }

  List<MemoryItem> recordPromptInjected(
    List<MemoryItem> items,
    Iterable<String> ids,
  ) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return items;
    final now = DateTime.now();
    return items
        .map((item) {
          if (!idSet.contains(item.id)) return item;
          return item.copyWith(
            lastUsedAt: now,
            updatedAt: now,
            stats: item.stats.add(promptInjection: 1),
          );
        })
        .toList(growable: false);
  }

  List<MemoryItem> recordCorrectionHit(
    List<MemoryItem> items,
    Iterable<String> ids,
  ) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return items;
    final now = DateTime.now();
    return items
        .map((item) {
          if (!idSet.contains(item.id)) return item;
          return item.copyWith(
            strength: item.strength + 1,
            lastUsedAt: now,
            updatedAt: now,
            stats: item.stats.add(correctionHit: 1),
          );
        })
        .toList(growable: false);
  }

  List<MemoryItem> _updateStatus(
    List<MemoryItem> items,
    String id, {
    required MemoryItemStatus status,
    DateTime? cooldownUntil,
    bool clearCooldown = false,
    int positive = 0,
    int negative = 0,
    int rejected = 0,
  }) {
    final now = DateTime.now();
    return items
        .map((item) {
          if (item.id != id) return item;
          return item.copyWith(
            status: status,
            cooldownUntil: cooldownUntil,
            clearCooldownUntil: clearCooldown,
            updatedAt: now,
            stats: item.stats.add(
              positive: positive,
              negative: negative,
              rejected: rejected,
            ),
          );
        })
        .toList(growable: false);
  }

  MemoryItemStatus _statusAfterPositiveEvidence(
    MemoryItemStatus current, {
    required MemoryItemStats nextStats,
    required double confidence,
    required DateTime now,
    DateTime? cooldownUntil,
  }) {
    if (current == MemoryItemStatus.active ||
        current == MemoryItemStatus.archived) {
      return current;
    }
    if (current == MemoryItemStatus.suppressed &&
        cooldownUntil != null &&
        cooldownUntil.isAfter(now)) {
      return current;
    }
    if (nextStats.evidenceCount >= 2 && confidence >= 0.75) {
      return MemoryItemStatus.weakActive;
    }
    return current == MemoryItemStatus.suppressed
        ? MemoryItemStatus.pending
        : current;
  }

  String? _excerpt(String? text) {
    final normalized = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    if (normalized.length <= 240) return normalized;
    return '${normalized.substring(0, 240)}...';
  }

  double _max(double a, double b) => a > b ? a : b;
}
