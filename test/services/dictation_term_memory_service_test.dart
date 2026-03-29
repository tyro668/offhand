import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/services/dictation_term_memory_service.dart';

void main() {
  const service = DictationTermMemoryService();

  test(
    'extractCandidates learns local phrase replacement from edited history',
    () {
      final candidates = service.extractCandidates(
        beforeText: '快走，接龙啊，马上出来了。',
        afterText: '快走，张三丰啊，马上出来了。',
        rawText: '快走，接龙啊，马上出来了。',
      );

      expect(candidates, hasLength(1));
      expect(candidates.first.original, '接龙');
      expect(candidates.first.corrected, '张三丰');
    },
  );

  test('extractCandidates ignores broad sentence rewrites', () {
    final candidates = service.extractCandidates(
      beforeText: '今天下午开会讨论功能细节、接口联调、性能优化和上线排期。',
      afterText: '我们明天再单独约时间重新梳理方案、补写文档并安排补充评审。',
      rawText: '今天下午开会讨论功能细节、接口联调、性能优化和上线排期。',
    );

    expect(candidates, isEmpty);
  });
}
