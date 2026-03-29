import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/entity_alias.dart';
import 'package:voicetype/models/entity_evidence.dart';
import 'package:voicetype/models/entity_memory.dart';
import 'package:voicetype/models/entity_relation.dart';

void main() {
  test('EntityMemory toJson/fromJson round-trip', () {
    final entity = EntityMemory.create(
      canonicalName: '张三丰',
      type: EntityType.person,
      confidence: 0.92,
    );

    final decoded = EntityMemory.fromJson(entity.toJson());
    expect(decoded.canonicalName, '张三丰');
    expect(decoded.type, EntityType.person);
    expect(decoded.confidence, closeTo(0.92, 0.0001));
  });

  test('EntityAlias toJson/fromJson round-trip', () {
    final alias = EntityAlias.create(
      entityId: 'e1',
      aliasText: '接龙',
      aliasType: EntityAliasType.misrecognition,
      source: 'history-edit',
      confidence: 0.88,
    );

    final decoded = EntityAlias.fromJson(alias.toJson());
    expect(decoded.entityId, 'e1');
    expect(decoded.aliasText, '接龙');
    expect(decoded.aliasType, EntityAliasType.misrecognition);
  });

  test('EntityRelation toJson/fromJson round-trip', () {
    final relation = EntityRelation.create(
      sourceEntityId: 'e1',
      targetEntityId: 'e2',
      relationType: '哥哥',
      confidence: 0.8,
    );

    final decoded = EntityRelation.fromJson(relation.toJson());
    expect(decoded.sourceEntityId, 'e1');
    expect(decoded.targetEntityId, 'e2');
    expect(decoded.relationType, '哥哥');
  });

  test('EntityEvidence toJson/fromJson round-trip', () {
    final evidence = EntityEvidence.create(
      entityId: 'e1',
      sourceType: 'history-edit',
      sourceRef: 'history-1',
      beforeText: '接龙马上出来了',
      afterText: '张三丰马上出来了',
      extractedAlias: '接龙',
    );

    final decoded = EntityEvidence.fromJson(evidence.toJson());
    expect(decoded.entityId, 'e1');
    expect(decoded.sourceType, 'history-edit');
    expect(decoded.extractedAlias, '接龙');
  });
}
