import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/entity_alias.dart';
import 'package:voicetype/models/entity_memory.dart';
import 'package:voicetype/models/entity_relation.dart';
import 'package:voicetype/services/entity_recall_service.dart';
import 'package:voicetype/services/session_entity_state.dart';

void main() {
  group('EntityRecallService', () {
    const service = EntityRecallService();

    final zhang = EntityMemory.create(
      canonicalName: '张三丰',
      type: EntityType.person,
    );
    final li = EntityMemory.create(
      canonicalName: '李四娃',
      type: EntityType.person,
    );

    final aliases = <EntityAlias>[
      EntityAlias.create(
        entityId: zhang.id,
        aliasText: '接龙',
        aliasType: EntityAliasType.misrecognition,
      ),
      EntityAlias.create(
        entityId: zhang.id,
        aliasText: '三丰',
        aliasType: EntityAliasType.nickname,
      ),
      EntityAlias.create(
        entityId: li.id,
        aliasText: '金雨希',
        aliasType: EntityAliasType.misrecognition,
      ),
    ];

    final relations = <EntityRelation>[
      EntityRelation.create(
        sourceEntityId: zhang.id,
        targetEntityId: li.id,
        relationType: '哥哥',
      ),
    ];

    test('buildForStt returns entity section and relation hints', () {
      final session = SessionEntityState()
        ..activate(entityId: zhang.id, canonicalName: '张三丰', alias: '接龙');

      final bundle = service.buildForStt(
        currentText: '接龙和金雨希马上出来了',
        historyTexts: const ['刚刚张三丰已经到了'],
        contextTexts: const ['会议参与人包括张三丰和李四娃'],
        memories: [zhang, li],
        aliases: aliases,
        relations: relations,
        sessionState: session,
      );

      expect(bundle.hasEntities, isTrue);
      expect(bundle.sttSection, contains('当前活跃实体参考'));
      expect(bundle.sttSection, contains('张三丰'));
      expect(bundle.sttSection, contains('李四娃'));
      expect(bundle.sttSection, contains('实体关系参考'));
    });

    test(
      'limits aliases and can keep related entity via relation expansion',
      () {
        final manyAliases = <EntityAlias>[
          ...aliases,
          EntityAlias.create(
            entityId: zhang.id,
            aliasText: '三哥',
            aliasType: EntityAliasType.alias,
            confidence: 0.7,
          ),
          EntityAlias.create(
            entityId: zhang.id,
            aliasText: '张老师',
            aliasType: EntityAliasType.nickname,
            confidence: 0.9,
          ),
          EntityAlias.create(
            entityId: zhang.id,
            aliasText: 'ZSF',
            aliasType: EntityAliasType.abbreviation,
            confidence: 0.8,
          ),
        ];

        final session = SessionEntityState()
          ..activate(entityId: zhang.id, canonicalName: '张三丰', alias: '张三丰');

        final bundle = service.buildForCorrection(
          currentText: '我们继续聊张三丰的事情',
          contextText: '李四娃和张三丰是一组人物',
          memories: [zhang, li],
          aliases: manyAliases,
          relations: relations,
          sessionState: session,
          maxEntities: 2,
        );

        expect(bundle.entities, hasLength(2));
        expect(
          bundle.entities.any((item) => item.memory.canonicalName == '李四娃'),
          isTrue,
        );
        final recalledZhang = bundle.entities.firstWhere(
          (item) => item.memory.canonicalName == '张三丰',
        );
        expect(recalledZhang.aliases.length, lessThanOrEqualTo(3));
      },
    );
  });
}
