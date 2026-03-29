import 'entity_alias.dart';
import 'entity_memory.dart';
import 'entity_relation.dart';

class RecalledEntity {
  final EntityMemory memory;
  final List<EntityAlias> aliases;
  final double score;

  const RecalledEntity({
    required this.memory,
    required this.aliases,
    required this.score,
  });
}

class EntityPromptBundle {
  final List<RecalledEntity> entities;
  final List<EntityRelation> relations;
  final String sttSection;
  final String correctionEntitySection;
  final String correctionRelationSection;

  const EntityPromptBundle({
    this.entities = const [],
    this.relations = const [],
    this.sttSection = '',
    this.correctionEntitySection = '',
    this.correctionRelationSection = '',
  });

  bool get hasEntities => entities.isNotEmpty;
  bool get hasRelations => relations.isNotEmpty;
  bool get hasPromptData =>
      sttSection.trim().isNotEmpty ||
      correctionEntitySection.trim().isNotEmpty ||
      correctionRelationSection.trim().isNotEmpty;
}
