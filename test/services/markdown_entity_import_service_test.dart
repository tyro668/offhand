import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/entity_memory.dart';
import 'package:voicetype/services/markdown_entity_import_service.dart';

void main() {
  group('MarkdownEntityImportService', () {
    const service = MarkdownEntityImportService();

    test('parses markdown bullet entities with aliases', () {
      final result = service.parse('''
- 张三丰（别名：三丰、老张）
- 观远数据
- DataForge
''');

      expect(result, hasLength(3));
      expect(result.first.canonicalName, '张三丰');
      expect(result.first.aliases, containsAll(['三丰', '老张']));
      expect(result[1].type, EntityType.company);
      expect(result[2].type, EntityType.product);
    });

    test('ignores non-entity prose lines', () {
      final result = service.parse('''
# 会议纪要
今天讨论了很多内容，需要明天继续梳理方案。
- 张三丰
''');

      expect(result, hasLength(1));
      expect(result.first.canonicalName, '张三丰');
    });

    test('infers entity type from markdown section heading', () {
      final result = service.parse('''
# 参会人员
- 老王

# 产品列表
- Phoenix
''');

      expect(result, hasLength(2));
      expect(result[0].type, EntityType.person);
      expect(result[1].type, EntityType.product);
    });
  });
}
