import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/dictionary_entry.dart';
import 'package:voicetype/models/term_context_entry.dart';
import 'package:voicetype/models/transcription.dart';
import 'package:voicetype/services/session_glossary.dart';
import 'package:voicetype/services/term_prompt_builder.dart';

void main() {
  group('TermPromptBuilder', () {
    const builder = TermPromptBuilder();

    test('builds prompt from dictionary, session glossary, and references', () {
      final glossary = SessionGlossary()
        ..override('反软', '帆软')
        ..override('低铺戏客', 'DeepSeek');

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
          DictionaryEntry.create(
            original: '好数连',
            corrected: 'hao shu lian',
          ),
        ],
        sessionGlossary: glossary,
        termContextEntries: [
          TermContextEntry.create(
            term: 'glossary.md',
            canonical: 'glossary.md',
            content: 'Function Calling 是当前重点能力，MCP 是相关协议。',
            sourceName: 'glossary.md',
            entryType: TermContextEntryType.reference,
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
    });

    test('builds prompt from context documents when no terms can be recalled', () {
      final bundle = builder.build(
        scene: 'meeting',
        currentText: '',
        history: const [],
        dictionaryEntries: const [],
        sessionGlossary: SessionGlossary(),
        termContextEntries: [
          TermContextEntry.create(
            term: 'notes.md',
            canonical: 'notes.md',
            content: '这里是会议相关背景，上下文里提到了客户和系统信息。',
            sourceName: 'notes.md',
            entryType: TermContextEntryType.reference,
          ),
        ],
      );

      expect(bundle.hasPrompt, isTrue);
      expect(bundle.preferredTerms, isEmpty);
      expect(bundle.sttPrompt, contains('notes.md'));
    });
  });
}
