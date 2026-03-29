import '../models/entity_alias.dart';
import '../models/entity_prompt_bundle.dart';

class EntityPromptComposer {
  const EntityPromptComposer();

  String buildSttSection(EntityPromptBundle bundle) {
    if (!bundle.hasEntities) return '';
    final buf = StringBuffer()..writeln('当前活跃实体参考：');
    for (final recalled in bundle.entities) {
      buf.writeln('- ${_buildNaturalLanguageLine(recalled)}');
    }
    if (bundle.hasRelations) {
      buf.writeln();
      buf.writeln('实体关系参考：');
      for (final relation in bundle.relations) {
        String? source;
        String? target;
        for (final entity in bundle.entities) {
          if (entity.memory.id == relation.sourceEntityId) {
            source = entity.memory.canonicalName;
          }
          if (entity.memory.id == relation.targetEntityId) {
            target = entity.memory.canonicalName;
          }
        }
        if (source == null || target == null) continue;
        buf.writeln('- $source 是 $target 的 ${relation.relationType}');
      }
    }
    return buf.toString().trim();
  }

  String buildCorrectionEntitySection(EntityPromptBundle bundle) {
    if (!bundle.hasEntities) return '';
    final lines = bundle.entities.map(_buildProtocolEntityLine).toList();
    return lines.join('\n').trim();
  }

  String buildCorrectionRelationSection(EntityPromptBundle bundle) {
    if (!bundle.hasRelations) return '';
    final entityById = {
      for (final item in bundle.entities)
        item.memory.id: item.memory.canonicalName,
    };
    final lines = <String>[];
    for (final relation in bundle.relations) {
      final source = entityById[relation.sourceEntityId];
      final target = entityById[relation.targetEntityId];
      if (source == null || target == null) continue;
      lines.add('$source -> $target : ${relation.relationType}');
    }
    return lines.join('\n').trim();
  }

  String _buildNaturalLanguageLine(RecalledEntity recalled) {
    final aliasesByType = <EntityAliasType, List<String>>{};
    for (final alias in recalled.aliases) {
      aliasesByType.putIfAbsent(alias.aliasType, () => []).add(alias.aliasText);
    }
    final parts = <String>[
      '${_labelForType(recalled.memory.type)}：${recalled.memory.canonicalName}',
    ];
    final nicknames = aliasesByType[EntityAliasType.nickname] ?? const [];
    final aliases = aliasesByType[EntityAliasType.alias] ?? const [];
    final mis = aliasesByType[EntityAliasType.misrecognition] ?? const [];
    final abbr = aliasesByType[EntityAliasType.abbreviation] ?? const [];
    if (nicknames.isNotEmpty) parts.add('小名：${nicknames.join('、')}');
    if (aliases.isNotEmpty) parts.add('别称：${aliases.join('、')}');
    if (mis.isNotEmpty) parts.add('常见误识别：${mis.join('、')}');
    if (abbr.isNotEmpty) parts.add('缩写：${abbr.join('、')}');
    if (parts.length == 1) return parts.first;
    return '${parts.first}（${parts.skip(1).join('；')}）';
  }

  String _buildProtocolEntityLine(RecalledEntity recalled) {
    final grouped = <String>[];
    final aliasesByType = <EntityAliasType, List<String>>{};
    for (final alias in recalled.aliases) {
      aliasesByType.putIfAbsent(alias.aliasType, () => []).add(alias.aliasText);
    }
    void add(String label, EntityAliasType type) {
      final values = aliasesByType[type];
      if (values == null || values.isEmpty) return;
      grouped.add('$label=${values.join('、')}');
    }

    add('nickname', EntityAliasType.nickname);
    add('alias', EntityAliasType.alias);
    add('mis', EntityAliasType.misrecognition);
    add('abbr', EntityAliasType.abbreviation);

    final suffix = grouped.isEmpty ? '' : ' | ${grouped.join(' | ')}';
    return '${recalled.memory.canonicalName} | type=${recalled.memory.type.name}$suffix';
  }

  String _labelForType(Object type) {
    final name = '$type'.split('.').last;
    switch (name) {
      case 'person':
        return '人名';
      case 'company':
        return '公司';
      case 'product':
        return '产品';
      case 'project':
        return '项目';
      case 'system':
        return '系统';
      default:
        return '实体';
    }
  }
}
