import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/dictionary_entry.dart';
import 'package:voicetype/models/entity_alias.dart';
import 'package:voicetype/models/entity_memory.dart';
import 'package:voicetype/models/entity_relation.dart';
import 'package:voicetype/models/memory_item.dart';
import 'package:voicetype/models/term_context_entry.dart';
import 'package:voicetype/models/transcription.dart';
import 'package:voicetype/services/session_entity_state.dart';
import 'package:voicetype/services/session_glossary.dart';
import 'package:voicetype/services/term_prompt_builder.dart';

void main() {
  group('TermPromptBuilder', () {
    const builder = TermPromptBuilder();

    test('builds prompt from dictionary, session glossary, and references', () {
      final glossary = SessionGlossary()
        ..override('反软', '帆软')
        ..override('低铺戏客', 'DeepSeek');
      final zhang = EntityMemory.create(
        canonicalName: '张三丰',
        type: EntityType.person,
      );
      final li = EntityMemory.create(
        canonicalName: '李四娃',
        type: EntityType.person,
      );
      final sessionEntityState = SessionEntityState()
        ..activate(entityId: zhang.id, canonicalName: '张三丰', alias: '接龙');

      final bundle = builder.build(
        scene: 'dictation',
        currentText: '我们要讨论报表和 MCP 接入',
        history: [
          Transcription(
            id: '1',
            text: '昨天在 DeepSeek 里看了 MCP 文档',
            createdAt: DateTime(2026, 3, 28),
            duration: const Duration(seconds: 5),
            provider: 'test',
            model: 'test',
            providerConfigJson: '{}',
          ),
        ],
        dictionaryEntries: [
          DictionaryEntry.create(
            original: '反软',
            corrected: '帆软',
            source: DictionaryEntrySource.historyEdit,
          ),
          DictionaryEntry.create(original: 'MCP'),
          DictionaryEntry.create(original: '好数连', corrected: 'hao shu lian'),
        ],
        sessionGlossary: glossary,
        sessionEntityState: sessionEntityState,
        termContextEntries: [
          TermContextEntry.create(
            term: 'glossary.md',
            canonical: 'glossary.md',
            content: 'Function Calling 是当前重点能力，MCP 是相关协议。',
            sourceName: 'glossary.md',
            entryType: TermContextEntryType.reference,
          ),
        ],
        entityMemories: [zhang, li],
        entityAliases: [
          EntityAlias.create(
            entityId: zhang.id,
            aliasText: '接龙',
            aliasType: EntityAliasType.misrecognition,
          ),
          EntityAlias.create(
            entityId: li.id,
            aliasText: '金雨希',
            aliasType: EntityAliasType.misrecognition,
          ),
        ],
        entityRelations: [
          EntityRelation.create(
            sourceEntityId: zhang.id,
            targetEntityId: li.id,
            relationType: '哥哥',
          ),
        ],
      );

      expect(bundle.hasPrompt, isTrue);
      expect(bundle.preferredTerms, contains('帆软'));
      expect(bundle.preferredTerms, contains('DeepSeek'));
      expect(bundle.preferredTerms, contains('MCP'));
      expect(bundle.preferredTerms, contains('好数连'));
      expect(bundle.sttPrompt, contains('优先识别并保持以下术语写法'));
      expect(bundle.sttPrompt, contains('帆软'));
      expect(bundle.sttPrompt, contains('参考以下上下文'));
      expect(bundle.sttPrompt, contains('glossary.md'));
      expect(bundle.sttPrompt, contains('当前活跃实体参考'));
      expect(bundle.sttPrompt, contains('张三丰'));
      expect(bundle.memoryPromptSuffix, contains('【听写记忆参考】'));
      expect(bundle.memoryPromptSuffix, contains('反软->帆软'));
      expect(bundle.memoryPromptSuffix, contains('glossary.md'));
      expect(bundle.memoryPromptSuffix, contains('张三丰 | type=person'));
      expect(bundle.entityCorrectionSection, contains('张三丰 | type=person'));
      expect(bundle.entityRelationSection, contains('张三丰 -> 李四娃 : 哥哥'));
    });

    test(
      'builds prompt from context documents when no terms can be recalled',
      () {
        final bundle = builder.build(
          scene: 'dictation',
          currentText: '',
          history: const [],
          dictionaryEntries: const [],
          sessionGlossary: SessionGlossary(),
          termContextEntries: [
            TermContextEntry.create(
              term: 'notes.md',
              canonical: 'notes.md',
              content: '这里是项目相关背景，上下文里提到了客户和系统信息。',
              sourceName: 'notes.md',
              entryType: TermContextEntryType.reference,
            ),
          ],
        );

        expect(bundle.hasPrompt, isTrue);
        expect(bundle.preferredTerms, isEmpty);
        expect(bundle.sttPrompt, contains('notes.md'));
      },
    );

    test(
      'dictation prompt can recall terms from transcription history only',
      () {
        final bundle = builder.build(
          scene: 'dictation',
          currentText: '',
          history: [
            Transcription(
              id: 'h1',
              text: '上次录音确认帆软和张三丰都会继续参加。',
              createdAt: DateTime(2026, 3, 29),
              duration: const Duration(seconds: 8),
              provider: 'test',
              model: 'test',
              providerConfigJson: '{}',
            ),
          ],
          dictionaryEntries: [
            DictionaryEntry.create(
              original: '反软',
              corrected: '帆软',
              source: DictionaryEntrySource.historyEdit,
            ),
          ],
          sessionGlossary: SessionGlossary(),
        );

        expect(bundle.hasPrompt, isTrue);
        expect(bundle.preferredTerms, contains('帆软'));
        expect(bundle.sttPrompt, contains('帆软'));
      },
    );

    test(
      'uses active memory in STT prompt and weak memory only in references',
      () {
        final active = MemoryItem.create(
          kind: MemoryItemKind.correction,
          status: MemoryItemStatus.active,
          scope: MemoryItemScope.user,
          original: '反软',
          canonical: '帆软',
        );
        final weak = MemoryItem.create(
          kind: MemoryItemKind.correction,
          status: MemoryItemStatus.weakActive,
          scope: MemoryItemScope.user,
          original: '低铺戏客',
          canonical: 'DeepSeek',
        );

        final bundle = builder.build(
          scene: 'dictation',
          currentText: '今天讨论低铺戏客',
          history: const [],
          dictionaryEntries: const [],
          sessionGlossary: SessionGlossary(),
          memoryItems: [active, weak],
        );

        expect(bundle.sttPrompt, contains('帆软'));
        expect(bundle.sttPrompt, isNot(contains('DeepSeek')));
        expect(bundle.correctionReferences, contains('反软->帆软'));
        expect(bundle.correctionReferences, contains('低铺戏客->DeepSeek'));
        expect(bundle.includedMemoryItemIds, contains(active.id));
        expect(bundle.includedMemoryItemIds, isNot(contains(weak.id)));
        expect(bundle.includedWeakMemoryItemIds, contains(weak.id));
      },
    );

    test('uses active reference memory as STT context', () {
      final reference = MemoryItem.create(
        kind: MemoryItemKind.reference,
        status: MemoryItemStatus.active,
        scope: MemoryItemScope.user,
        canonical: '项目背景',
        content: 'Offhand 是一个用于语音输入和上下文增强的工具。',
      );

      final bundle = builder.build(
        scene: 'dictation',
        currentText: '',
        history: const [],
        dictionaryEntries: const [],
        sessionGlossary: SessionGlossary(),
        memoryItems: [reference],
      );

      expect(bundle.hasPrompt, isTrue);
      expect(bundle.sttPrompt, contains('参考以下记忆片段'));
      expect(bundle.sttPrompt, contains('Offhand 是一个用于语音输入'));
      expect(bundle.memoryPromptSuffix, contains('可参考以下手动记忆片段'));
      expect(bundle.includedMemoryItemIds, contains(reference.id));
    });
  });
}
