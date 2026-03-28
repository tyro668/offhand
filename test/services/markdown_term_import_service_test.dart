import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/services/markdown_term_import_service.dart';

void main() {
  group('MarkdownTermImportService', () {
    const service = MarkdownTermImportService();

    test('imports markdown as a single document context', () {
      const markdown = '''
# 项目上下文

这里记录帆软、DeepSeek、MCP 和报表平台的背景说明。
''';

      final result = service.parse(markdown, fileName: 'rules.md');

      expect(result.contextEntries, hasLength(1));
      expect(result.contextEntries.single.sourceName, 'rules.md');
      expect(result.contextEntries.single.content, contains('帆软、DeepSeek、MCP'));
      expect(result.promotableCorrections, isEmpty);
      expect(result.promotablePreserves, isEmpty);
      expect(result.referenceOnlyTerms, isEmpty);
    });

    test('returns warning for empty markdown', () {
      final result = service.parse('   \n\n ', fileName: 'empty.md');

      expect(result.contextEntries, isEmpty);
      expect(result.warnings, isNotEmpty);
    });
  });
}
