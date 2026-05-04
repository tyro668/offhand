import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/dictation_term_pending_candidate.dart';
import 'package:voicetype/models/dictionary_entry.dart';
import 'package:voicetype/models/memory_item.dart';
import 'package:voicetype/services/adaptive_memory_repository.dart';

void main() {
  group('AdaptiveMemoryRepository', () {
    const repository = AdaptiveMemoryRepository();

    test(
      'projects legacy dictionary and pending candidates into MemoryItems',
      () {
        final items = repository.mergeWithLegacy(
          memoryItems: const [],
          dictionaryEntries: [
            DictionaryEntry.create(
              original: '反软',
              corrected: '帆软',
              source: DictionaryEntrySource.historyEdit,
            ),
            DictionaryEntry.create(original: 'MCP'),
          ],
          pendingCandidates: [
            DictationTermPendingCandidate.create(
              original: '低铺戏客',
              corrected: 'DeepSeek',
              confidence: 0.82,
            ).copyWith(occurrenceCount: 2),
          ],
          termContextEntries: const [],
          entityMemories: const [],
          entityAliases: const [],
        );

        expect(
          items.any(
            (item) =>
                item.kind == MemoryItemKind.correction &&
                item.status == MemoryItemStatus.active &&
                item.original == '反软' &&
                item.canonical == '帆软',
          ),
          isTrue,
        );
        expect(
          items.any(
            (item) =>
                item.kind == MemoryItemKind.preserve &&
                item.status == MemoryItemStatus.active &&
                item.canonical == 'MCP',
          ),
          isTrue,
        );
        expect(
          items.any(
            (item) =>
                item.original == '低铺戏客' &&
                item.canonical == 'DeepSeek' &&
                item.status == MemoryItemStatus.weakActive,
          ),
          isTrue,
        );
      },
    );

    test('recall excludes suppressed memories and can include weak active', () {
      final active = MemoryItem.create(
        kind: MemoryItemKind.correction,
        status: MemoryItemStatus.active,
        scope: MemoryItemScope.user,
        original: '反软',
        canonical: '帆软',
        strength: 3,
      );
      final weak = MemoryItem.create(
        kind: MemoryItemKind.correction,
        status: MemoryItemStatus.weakActive,
        scope: MemoryItemScope.user,
        original: '低铺戏客',
        canonical: 'DeepSeek',
        strength: 3,
      );
      final suppressed = MemoryItem.create(
        kind: MemoryItemKind.correction,
        status: MemoryItemStatus.suppressed,
        scope: MemoryItemScope.user,
        original: '开会',
        canonical: '开胃',
        strength: 100,
      );

      final promptRecall = repository.recall(
        memoryItems: [active, weak, suppressed],
        currentText: '反软 和 低铺戏客',
      );
      expect(promptRecall, contains(active));
      expect(promptRecall, isNot(contains(weak)));
      expect(promptRecall, isNot(contains(suppressed)));

      final correctionRecall = repository.recall(
        memoryItems: [active, weak, suppressed],
        currentText: '反软 和 低铺戏客',
        includeWeakActive: true,
      );
      expect(correctionRecall, contains(active));
      expect(correctionRecall, contains(weak));
      expect(correctionRecall, isNot(contains(suppressed)));
    });
  });
}
