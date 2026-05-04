import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/memory_item.dart';
import 'package:voicetype/services/memory_evolution_engine.dart';

void main() {
  group('MemoryEvolutionEngine', () {
    const engine = MemoryEvolutionEngine();

    test('promotes repeated positive evidence from pending to weak active', () {
      final first = engine.observeCorrection(
        currentItems: const [],
        original: '反软',
        canonical: '帆软',
        sourceType: 'history_edit',
        confidence: 0.82,
      );
      expect(first.item.status, MemoryItemStatus.pending);
      expect(first.item.stats.evidenceCount, 1);
      expect(first.event.memoryId, first.item.id);

      final second = engine.observeCorrection(
        currentItems: first.items,
        original: '反软',
        canonical: '帆软',
        sourceType: 'history_edit',
        confidence: 0.82,
      );
      expect(second.item.id, first.item.id);
      expect(second.item.status, MemoryItemStatus.weakActive);
      expect(second.item.stats.evidenceCount, 2);
    });

    test('suppressed memory remains suppressed during cooldown', () {
      final observed = engine.observeCorrection(
        currentItems: const [],
        original: '开会',
        canonical: '开胃',
        sourceType: 'history_edit',
        confidence: 0.9,
      );
      final suppressed = engine.suppress(observed.items, observed.item.id);
      final item = suppressed.first;
      expect(item.status, MemoryItemStatus.suppressed);

      final next = engine.observeCorrection(
        currentItems: suppressed,
        original: '开会',
        canonical: '开胃',
        sourceType: 'history_edit',
        confidence: 0.9,
      );
      expect(next.item.status, MemoryItemStatus.suppressed);
      expect(next.item.stats.rejectedCount, 1);
    });

    test('records prompt injections and correction hits', () {
      final item = MemoryItem.create(
        kind: MemoryItemKind.correction,
        status: MemoryItemStatus.active,
        scope: MemoryItemScope.user,
        original: '反软',
        canonical: '帆软',
      );

      final prompted = engine.recordPromptInjected([item], [item.id]).single;
      expect(prompted.stats.promptInjectionCount, 1);
      expect(prompted.lastUsedAt, isNotNull);

      final hit = engine.recordCorrectionHit([prompted], [item.id]).single;
      expect(hit.stats.correctionHitCount, 1);
      expect(hit.strength, prompted.strength + 1);
    });
  });
}
