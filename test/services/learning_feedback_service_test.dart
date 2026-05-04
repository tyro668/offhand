import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/memory_item.dart';
import 'package:voicetype/models/stt_request_context.dart';
import 'package:voicetype/services/learning_feedback_service.dart';
import 'package:voicetype/services/session_glossary.dart';

void main() {
  group('LearningFeedbackService', () {
    const service = LearningFeedbackService();

    test('records history edits as memory evidence', () {
      final result = service.recordHistoryEdit(
        currentItems: const [],
        beforeText: '今天讨论低铺戏客方案',
        afterText: '今天讨论DeepSeek方案',
        rawText: '今天讨论低铺戏客方案',
        sourceHistoryId: 'history-1',
      );

      expect(result.learnedItems, hasLength(1));
      expect(result.events, hasLength(1));
      expect(result.learnedItems.single.original, '低铺戏客');
      expect(result.learnedItems.single.canonical, 'DeepSeek');
      expect(result.events.single.sourceRef, 'history-1');
    });

    test('keeps suppressed mappings from being relearned during cooldown', () {
      final suppressed = MemoryItem.create(
        kind: MemoryItemKind.correction,
        status: MemoryItemStatus.suppressed,
        scope: MemoryItemScope.user,
        original: '低铺戏客',
        canonical: 'DeepSeek',
      ).copyWith(cooldownUntil: DateTime.now().add(const Duration(days: 1)));

      final result = service.recordHistoryEdit(
        currentItems: [suppressed],
        beforeText: '今天讨论低铺戏客方案',
        afterText: '今天讨论DeepSeek方案',
      );

      expect(result.learnedItems, isEmpty);
      expect(result.events, isEmpty);
      expect(result.items.single.status, MemoryItemStatus.suppressed);
    });

    test('flushes strong session glossary entries as weak active memory', () {
      final glossary = SessionGlossary()..override('反软', '帆软');

      final result = service.flushSessionGlossary(
        currentItems: const [],
        strongEntries: glossary.strongEntries,
        sourceRef: 'history-2',
      );

      expect(result.learnedItems.single.status, MemoryItemStatus.weakActive);
      expect(result.events.single.sourceRef, 'history-2');
    });

    test('records prompt injection and correction hit events', () {
      final item = MemoryItem.create(
        kind: MemoryItemKind.correction,
        status: MemoryItemStatus.active,
        scope: MemoryItemScope.user,
        original: '反软',
        canonical: '帆软',
      );
      final prompted = service.recordPromptInjected(
        currentItems: [item],
        context: SttRequestContext(
          scene: 'dictation',
          promptTraceId: 'trace-1',
          includedMemoryItemIds: [item.id],
        ),
      );
      expect(prompted.events.single.sourceRef, 'trace-1');
      expect(prompted.items.single.stats.promptInjectionCount, 1);

      final hit = service.recordCorrectionHit(
        currentItems: prompted.items,
        memoryItemIds: [item.id],
        sourceRef: 'realtime',
      );
      expect(hit.events.single.sourceRef, 'realtime');
      expect(hit.items.single.stats.correctionHitCount, 1);
    });
  });
}
