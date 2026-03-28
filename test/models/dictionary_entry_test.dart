import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/dictionary_entry.dart';

void main() {
  group('DictionaryEntry', () {
    test('toJson and fromJson round-trip with correction type', () {
      final entry = DictionaryEntry.create(
        original: '帆软',
        corrected: 'FanRuan',
        category: '品牌',
        pinyinOverride: 'fan ruan',
      );

      final json = entry.toJson();
      final restored = DictionaryEntry.fromJson(json);

      expect(restored.id, entry.id);
      expect(restored.original, '帆软');
      expect(restored.corrected, 'FanRuan');
      expect(restored.category, '品牌');
      expect(restored.enabled, true);
      expect(restored.pinyinOverride, 'fan ruan');
      expect(restored.type, DictionaryEntryType.correction);
    });

    test('toJson and fromJson round-trip with preserve type', () {
      final entry = DictionaryEntry.create(original: 'Metis');

      final json = entry.toJson();
      final restored = DictionaryEntry.fromJson(json);

      expect(restored.original, 'Metis');
      expect(restored.corrected, isNull);
      expect(restored.type, DictionaryEntryType.preserve);
      expect(restored.pinyinOverride, isNull);
    });

    test('fromJson backward compatibility: word/description fields', () {
      final json = {
        'id': 'test-id',
        'word': '旧格式原始词',
        'description': '旧格式纠正词',
        'enabled': true,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final restored = DictionaryEntry.fromJson(json);
      expect(restored.original, '旧格式原始词');
      expect(restored.corrected, '旧格式纠正词');
    });

    test('fromJson backward compatibility: pinyin absent', () {
      final json = {
        'id': 'test-id',
        'original': '帆软',
        'corrected': 'FanRuan',
        'enabled': true,
        'createdAt': DateTime.now().toIso8601String(),
        // no pinyinOverride field
      };

      final restored = DictionaryEntry.fromJson(json);
      expect(restored.pinyinOverride, isNull);
      // pinyinNormalized should auto-compute
      expect(restored.pinyinNormalized, isNotEmpty);
    });

    test('pinyinNormalized uses pinyinOverride when set', () {
      final entry = DictionaryEntry.create(
        original: '乐',
        pinyinOverride: 'yue',
      );
      expect(entry.pinyinNormalized, 'yue');
    });

    test('pinyinNormalized auto-computes when override is null', () {
      final entry = DictionaryEntry.create(original: '你好');
      expect(entry.pinyinNormalized, isNotEmpty);
      expect(entry.pinyinNormalized, contains(' ')); // 2 characters
    });

    test('autoPinyin always auto-computes', () {
      final entry = DictionaryEntry.create(
        original: '测试',
        pinyinOverride: 'custom pinyin',
      );
      // autoPinyin ignores override
      expect(entry.autoPinyin, isNotEmpty);
      expect(entry.autoPinyin, isNot('custom pinyin'));
    });

    test('copyWith preserves pinyinOverride', () {
      final entry = DictionaryEntry.create(
        original: '帆软',
        corrected: 'FanRuan',
        pinyinOverride: 'fan ruan',
      );
      final copied = entry.copyWith(original: '新帆软');
      expect(copied.pinyinOverride, 'fan ruan');
    });

    test('clearCorrected preserves pinyinOverride', () {
      final entry = DictionaryEntry.create(
        original: '帆软',
        corrected: 'FanRuan',
        pinyinOverride: 'fan ruan',
      );
      final cleared = entry.clearCorrected();
      expect(cleared.corrected, isNull);
      expect(cleared.pinyinOverride, 'fan ruan');
    });

    test('clearPinyinOverride preserves other fields', () {
      final entry = DictionaryEntry.create(
        original: '帆软',
        corrected: 'FanRuan',
        category: '品牌',
        pinyinOverride: 'fan ruan',
      );
      final cleared = entry.clearPinyinOverride();
      expect(cleared.pinyinOverride, isNull);
      expect(cleared.corrected, 'FanRuan');
      expect(cleared.category, '品牌');
    });

    test('pinyinPattern round-trip and normalization', () {
      final entry = DictionaryEntry.create(
        original: '',
        corrected: '帆软',
        pinyinPattern: '  FAN   RUAN ',
      );

      final json = entry.toJson();
      final restored = DictionaryEntry.fromJson(json);

      expect(restored.pinyinPattern, 'fan ruan');
      expect(restored.pinyinNormalized, 'fan ruan');
    });

    test('pinyinPattern has higher priority than pinyinOverride', () {
      final entry = DictionaryEntry.create(
        original: '乐谱',
        corrected: '乐谱',
        pinyinOverride: 'yue pu',
        pinyinPattern: 'le pu',
      );

      expect(entry.pinyinNormalized, 'le pu');
    });

    test('parses markdown import source', () {
      final json = {
        'id': 'test-id',
        'original': 'DeepSeek',
        'source': 'markdownImport',
        'enabled': true,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final restored = DictionaryEntry.fromJson(json);
      expect(restored.source, DictionaryEntrySource.markdownImport);
    });
  });
}
