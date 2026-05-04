import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/l10n/app_localizations_en.dart';
import 'package:voicetype/l10n/app_localizations_zh.dart';
import 'package:voicetype/l10n/memory_source_localizations.dart';

void main() {
  group('MemorySourceLocalizations', () {
    test('localizes known memory source codes', () {
      final zh = AppLocalizationsZh();
      final en = AppLocalizationsEn();

      expect(zh.memorySourceDisplayName('manual'), '手动添加');
      expect(en.memorySourceDisplayName('manual'), 'Manual');
      expect(zh.memorySourceDisplayName('history_edit'), '历史修正');
      expect(en.memorySourceDisplayName('historyEdit'), 'History edit');
      expect(zh.memorySourceDisplayName('entity-memory'), '实体记忆');
      expect(
        en.memorySourceDisplayName('markdown_document'),
        'Markdown document',
      );
    });

    test('falls back to raw source for unknown codes', () {
      final zh = AppLocalizationsZh();

      expect(zh.memorySourceDisplayName('custom_import'), 'custom_import');
    });
  });
}
