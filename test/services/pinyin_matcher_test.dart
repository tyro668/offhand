import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/dictionary_entry.dart';
import 'package:voicetype/services/pinyin_matcher.dart';

void main() {
  group('PinyinMatcher', () {
    late PinyinMatcher matcher;

    setUp(() {
      matcher = PinyinMatcher();
    });

    test('empty index returns no matches', () {
      matcher.buildIndex([]);
      final results = matcher.findMatches('测试文本');
      expect(results, isEmpty);
    });

    test('empty text returns no matches', () {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);
      final results = matcher.findMatches('');
      expect(results, isEmpty);
    });

    test('exact literal match for original', () {
      final entry = DictionaryEntry.create(original: '墨提斯', corrected: 'Metis');
      matcher.buildIndex([entry]);

      final results = matcher.findMatches('今天用了墨提斯做报表');
      expect(results, hasLength(1));
      expect(results.first.original, '墨提斯');
      expect(results.first.corrected, 'Metis');
    });

    test('pinyin match: same pinyin different characters', () {
      final entry = DictionaryEntry.create(original: '墨提斯', corrected: 'Metis');
      matcher.buildIndex([entry]);

      // "莫提斯" has the same pinyin as "墨提斯" (mo ti si)
      final results = matcher.findMatches('今天用了莫提斯做报表');
      expect(results, hasLength(1));
      expect(results.first.corrected, 'Metis');
    });

    test('no match for unrelated text', () {
      final entry = DictionaryEntry.create(original: '墨提斯', corrected: 'Metis');
      matcher.buildIndex([entry]);

      final results = matcher.findMatches('今天天气不错');
      expect(results, isEmpty);
    });

    test('multiple matches in same text', () {
      final entries = [
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
        DictionaryEntry.create(original: '星阔', corrected: 'XingKuo'),
      ];
      matcher.buildIndex(entries);

      final results = matcher.findMatches('在墨提斯里看了星阔的数据');
      expect(results, hasLength(2));
    });

    test('disabled entries are not indexed', () {
      final entry = DictionaryEntry.create(
        original: '墨提斯',
        corrected: 'Metis',
        enabled: false,
      );
      matcher.buildIndex([entry]);

      final results = matcher.findMatches('墨提斯');
      expect(results, isEmpty);
    });

    test('preserve type entries are matched', () {
      final entry = DictionaryEntry.create(original: 'Metis');
      matcher.buildIndex([entry]);

      final results = matcher.findMatches('今天用了Metis');
      expect(results, hasLength(1));
      expect(results.first.type, DictionaryEntryType.preserve);
    });

    test('rebuildIndex clears old data', () {
      final entry1 = DictionaryEntry.create(
        original: '墨提斯',
        corrected: 'Metis',
      );
      matcher.buildIndex([entry1]);
      expect(matcher.findMatches('墨提斯'), hasLength(1));

      // Rebuild with different data
      final entry2 = DictionaryEntry.create(
        original: '星阔',
        corrected: 'XingKuo',
      );
      matcher.buildIndex([entry2]);

      // Old entry should not match
      expect(matcher.findMatches('墨提斯'), isEmpty);
      // New entry should match
      expect(matcher.findMatches('星阔'), hasLength(1));
    });

    test('pinyinOverride is used for matching', () {
      // "乐" is polyphonic: le or yue
      final entry = DictionaryEntry.create(
        original: '乐谱',
        corrected: '乐谱',
        pinyinOverride: 'yue pu',
      );
      matcher.buildIndex([entry]);

      // Should match via the override pinyin
      final results = matcher.findMatches('乐谱');
      expect(results, hasLength(1));
    });

    test('computePinyin produces expected output', () {
      final pinyin = PinyinMatcher.computePinyin('你好世界');
      expect(pinyin, isNotEmpty);
      expect(pinyin, contains(' ')); // space separated
    });

    test('corrected word in text also triggers match', () {
      final entry = DictionaryEntry.create(original: '莫提斯', corrected: 'Metis');
      matcher.buildIndex([entry]);

      // Text already contains the corrected form
      final results = matcher.findMatches('今天用了Metis做报表');
      expect(results, hasLength(1));
    });

    test('single char fuzzy is disabled by default', () {
      final entry = DictionaryEntry.create(original: '柯', corrected: '科');
      matcher.buildIndex([entry]);

      // 库(ku) 与 柯(ke) 同声母 k，旧逻辑会被单字模糊误召回
      final results = matcher.findMatches('库存充足');
      expect(results, isEmpty);
    });

    test('single char fuzzy can be enabled explicitly', () {
      final fuzzyMatcher = PinyinMatcher(enableSingleCharFuzzy: true);
      final entry = DictionaryEntry.create(original: '柯', corrected: '科');
      fuzzyMatcher.buildIndex([entry]);

      final results = fuzzyMatcher.findMatches('库存充足');
      expect(results, hasLength(1));
    });

    test('pinyinPattern-only entry can match even when original is empty', () {
      final entry = DictionaryEntry.create(
        original: '',
        corrected: '墨提斯',
        pinyinPattern: 'mo ti si',
      );
      matcher.buildIndex([entry]);

      final results = matcher.findMatches('今天用了莫提斯做报表');
      expect(results, hasLength(1));
      expect(results.first.corrected, '墨提斯');
      expect(results.first.original, isEmpty);
    });
  });
}
