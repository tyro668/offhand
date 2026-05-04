import '../models/dictation_term_pending_candidate.dart';
import '../models/dictionary_entry.dart';
import '../models/entity_alias.dart';
import '../models/entity_memory.dart';
import '../models/term_context_entry.dart';
import '../models/memory_item.dart';
import 'session_glossary.dart';

class AdaptiveMemoryRepository {
  const AdaptiveMemoryRepository();

  List<MemoryItem> mergeWithLegacy({
    required List<MemoryItem> memoryItems,
    required List<DictionaryEntry> dictionaryEntries,
    required List<DictationTermPendingCandidate> pendingCandidates,
    required List<TermContextEntry> termContextEntries,
    required List<EntityMemory> entityMemories,
    required List<EntityAlias> entityAliases,
    SessionGlossary? sessionGlossary,
  }) {
    final merged = <String, MemoryItem>{
      for (final item in memoryItems) item.normalizedKey: item,
    };

    void addIfAbsent(MemoryItem item) {
      merged.putIfAbsent(item.normalizedKey, () => item);
    }

    for (final entry in dictionaryEntries.where((e) => e.enabled)) {
      addIfAbsent(_fromDictionaryEntry(entry));
    }

    for (final candidate in pendingCandidates) {
      addIfAbsent(_fromPendingCandidate(candidate));
    }

    for (final entry in termContextEntries.where((e) => e.enabled)) {
      final item = _fromTermContextEntry(entry);
      if (item != null) addIfAbsent(item);
    }

    final aliasesByEntity = <String, List<EntityAlias>>{};
    for (final alias in entityAliases) {
      aliasesByEntity.putIfAbsent(alias.entityId, () => []).add(alias);
    }
    for (final entity in entityMemories.where((e) => e.enabled)) {
      addIfAbsent(_fromEntityMemory(entity, aliasesByEntity[entity.id] ?? []));
    }

    if (sessionGlossary != null) {
      for (final pin in sessionGlossary.strongEntries.values) {
        addIfAbsent(_fromSessionPin(pin));
      }
    }

    final result = merged.values.toList(growable: false)
      ..sort(_compareForRecall);
    return result;
  }

  List<MemoryItem> recall({
    required List<MemoryItem> memoryItems,
    required String currentText,
    int maxItems = 24,
    bool includeWeakActive = false,
  }) {
    final now = DateTime.now();
    final candidates = memoryItems
        .where((item) {
          if (item.status == MemoryItemStatus.archived ||
              item.status == MemoryItemStatus.suppressed) {
            return false;
          }
          if (item.cooldownUntil != null && item.cooldownUntil!.isAfter(now)) {
            return false;
          }
          if (item.status == MemoryItemStatus.active) return true;
          return includeWeakActive &&
              item.status == MemoryItemStatus.weakActive;
        })
        .toList(growable: false);

    final scored =
        candidates
            .map((item) => _ScoredMemoryItem(item, _score(item, currentText)))
            .where((item) => item.score > 0)
            .toList(growable: false)
          ..sort((a, b) {
            final byScore = b.score.compareTo(a.score);
            if (byScore != 0) return byScore;
            return _compareForRecall(a.item, b.item);
          });

    return scored.map((e) => e.item).take(maxItems).toList(growable: false);
  }

  MemoryItem _fromDictionaryEntry(DictionaryEntry entry) {
    final kind = entry.type == DictionaryEntryType.correction
        ? MemoryItemKind.correction
        : MemoryItemKind.preserve;
    final canonical = entry.type == DictionaryEntryType.correction
        ? (entry.corrected ?? '').trim()
        : entry.original.trim();
    return MemoryItem.create(
      kind: kind,
      status: MemoryItemStatus.active,
      scope: MemoryItemScope.user,
      original: entry.original,
      canonical: canonical,
      category: entry.category,
      source: entry.source.name,
      confidence: entry.source == DictionaryEntrySource.historyEdit
          ? 0.9
          : 0.85,
      strength: entry.source == DictionaryEntrySource.historyEdit ? 8 : 5,
      now: entry.createdAt,
      stats: const MemoryItemStats(evidenceCount: 1, positiveCount: 1),
    );
  }

  MemoryItem _fromPendingCandidate(DictationTermPendingCandidate candidate) {
    final status =
        candidate.occurrenceCount >= 2 && candidate.confidence >= 0.75
        ? MemoryItemStatus.weakActive
        : MemoryItemStatus.pending;
    return MemoryItem.create(
      kind: MemoryItemKind.correction,
      status: status,
      scope: MemoryItemScope.user,
      original: candidate.original,
      canonical: candidate.corrected,
      category: candidate.category,
      source: 'pending',
      confidence: candidate.confidence,
      strength: candidate.occurrenceCount.toDouble(),
      now: candidate.createdAt,
      stats: MemoryItemStats(
        evidenceCount: candidate.occurrenceCount,
        positiveCount: candidate.occurrenceCount,
      ),
    );
  }

  MemoryItem? _fromTermContextEntry(TermContextEntry entry) {
    if (entry.isDocumentContext) {
      return MemoryItem.create(
        kind: MemoryItemKind.reference,
        status: MemoryItemStatus.active,
        scope: MemoryItemScope.imported,
        canonical: entry.promptTerm,
        content: entry.content,
        source: entry.sourceType,
        confidence: entry.confidence,
        strength: 2,
        now: entry.createdAt,
      );
    }
    if (entry.promotableAsCorrection) {
      return MemoryItem.create(
        kind: MemoryItemKind.correction,
        status: MemoryItemStatus.pending,
        scope: MemoryItemScope.imported,
        original: entry.alias ?? '',
        canonical: entry.promptTerm,
        source: entry.sourceType,
        confidence: entry.confidence,
        strength: 1,
        now: entry.createdAt,
      );
    }
    if (entry.promotableAsPreserve || entry.promptTerm.isNotEmpty) {
      return MemoryItem.create(
        kind: MemoryItemKind.preserve,
        status: MemoryItemStatus.active,
        scope: MemoryItemScope.imported,
        canonical: entry.promptTerm,
        source: entry.sourceType,
        confidence: entry.confidence,
        strength: 2,
        now: entry.createdAt,
      );
    }
    return null;
  }

  MemoryItem _fromEntityMemory(EntityMemory entity, List<EntityAlias> aliases) {
    return MemoryItem.create(
      kind: MemoryItemKind.entity,
      status: MemoryItemStatus.active,
      scope: MemoryItemScope.user,
      canonical: entity.canonicalName,
      aliases: aliases.map((e) => e.aliasText).toList(growable: false),
      category: entity.type.name,
      source: 'entity-memory',
      confidence: entity.confidence,
      strength: entity.confidence * 10,
      now: entity.createdAt,
      stats: const MemoryItemStats(evidenceCount: 1, positiveCount: 1),
    ).copyWith(updatedAt: entity.updatedAt);
  }

  MemoryItem _fromSessionPin(TermPin pin) {
    return MemoryItem.create(
      kind: MemoryItemKind.correction,
      status: MemoryItemStatus.weakActive,
      scope: MemoryItemScope.session,
      original: pin.original,
      canonical: pin.corrected,
      source: 'session',
      confidence: 0.78,
      strength: 20 + pin.hitCount.toDouble(),
      stats: MemoryItemStats(
        evidenceCount: pin.hitCount,
        positiveCount: pin.hitCount,
      ),
    );
  }

  double _score(MemoryItem item, String currentText) {
    var score = item.strength + item.confidence * 10;
    if (item.status == MemoryItemStatus.active) score += 20;
    if (item.status == MemoryItemStatus.weakActive) score += 6;
    if (item.scope == MemoryItemScope.session) score += 25;
    if (item.source == 'historyEdit' || item.source == 'history_edit') {
      score += 6;
    }
    final current = currentText.toLowerCase();
    final original = item.original.toLowerCase();
    final canonical = item.canonical.toLowerCase();
    if (original.isNotEmpty && current.contains(original)) score += 20;
    if (canonical.isNotEmpty && current.contains(canonical)) score += 16;
    for (final alias in item.aliases) {
      if (alias.isNotEmpty && current.contains(alias.toLowerCase())) {
        score += 12;
        break;
      }
    }
    if (item.stats.userRevertedCount > 0) {
      score -= item.stats.userRevertedCount * 8;
    }
    if (item.stats.rejectedCount > 0) {
      score -= item.stats.rejectedCount * 12;
    }
    return score;
  }

  int _compareForRecall(MemoryItem a, MemoryItem b) {
    final byStatus = _statusPriority(
      a.status,
    ).compareTo(_statusPriority(b.status));
    if (byStatus != 0) return byStatus;
    final byStrength = b.strength.compareTo(a.strength);
    if (byStrength != 0) return byStrength;
    final byConfidence = b.confidence.compareTo(a.confidence);
    if (byConfidence != 0) return byConfidence;
    return a.displayText.compareTo(b.displayText);
  }

  int _statusPriority(MemoryItemStatus status) {
    return switch (status) {
      MemoryItemStatus.active => 0,
      MemoryItemStatus.weakActive => 1,
      MemoryItemStatus.pending => 2,
      MemoryItemStatus.suppressed => 3,
      MemoryItemStatus.archived => 4,
    };
  }
}

class _ScoredMemoryItem {
  final MemoryItem item;
  final double score;

  const _ScoredMemoryItem(this.item, this.score);
}
