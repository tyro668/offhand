import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/entity_alias.dart';
import 'package:voicetype/models/entity_memory.dart';
import 'package:voicetype/services/entity_dictionary_bridge.dart';
import 'package:voicetype/services/entity_learning_service.dart';

void main() {
  group('EntityLearningService', () {
    const service = EntityLearningService();

    test('extracts person misrecognition from edited history', () {
      final candidates = service.extractCandidates(
        beforeText: '快走，接龙啊，马上出来了。',
        afterText: '快走，张三丰啊，马上出来了。',
        rawText: '快走，接龙啊，马上出来了。',
      );

      expect(candidates, hasLength(1));
      expect(candidates.first.original, '接龙');
      expect(candidates.first.canonicalName, '张三丰');
      expect(candidates.first.entityType, EntityType.person);
      expect(candidates.first.aliasType, EntityAliasType.misrecognition);
    });

    test('ignores broad rewrites that are not safe to learn', () {
      final candidates = service.extractCandidates(
        beforeText: '今天下午开会讨论功能细节。',
        afterText: '我们明天再单独约时间重新梳理方案和排期。',
        rawText: '今天下午开会讨论功能细节。',
      );

      expect(candidates, isEmpty);
    });
  });

  group('EntityDictionaryBridge', () {
    const bridge = EntityDictionaryBridge();

    test('bridges high confidence misrecognition', () {
      final shouldBridge = bridge.shouldBridge(
        aliasType: EntityAliasType.misrecognition,
        aliasText: '接龙',
        canonicalName: '张三丰',
        confidence: 0.88,
      );

      expect(shouldBridge, isTrue);
    });

    test('does not bridge ambiguous alias', () {
      final shouldBridge = bridge.shouldBridge(
        aliasType: EntityAliasType.alias,
        aliasText: '老张',
        canonicalName: '张三丰',
        confidence: 0.95,
      );

      expect(shouldBridge, isFalse);
    });
  });
}
