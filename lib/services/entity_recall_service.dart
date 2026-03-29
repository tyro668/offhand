import '../models/entity_alias.dart';
import '../models/entity_memory.dart';
import '../models/entity_prompt_bundle.dart';
import '../models/entity_relation.dart';
import 'entity_prompt_composer.dart';
import 'session_entity_state.dart';

class EntityRecallService {
  static const int defaultMaxSttEntities = 5;
  static const int defaultMaxCorrectionEntities = 8;
  static const int _maxRelationExpansionEntities = 2;
  static const int _maxAliasesPerEntity = 3;

  final EntityPromptComposer promptComposer;

  const EntityRecallService({
    this.promptComposer = const EntityPromptComposer(),
  });

  EntityPromptBundle buildForStt({
    required String currentText,
    required List<String> historyTexts,
    required List<String> contextTexts,
    required List<EntityMemory> memories,
    required List<EntityAlias> aliases,
    required List<EntityRelation> relations,
    required SessionEntityState sessionState,
    int maxEntities = defaultMaxSttEntities,
  }) {
    final recalled = _recall(
      currentText: currentText,
      historyTexts: historyTexts,
      contextTexts: contextTexts,
      memories: memories,
      aliases: aliases,
      relations: relations,
      sessionState: sessionState,
      maxEntities: maxEntities,
    );
    final bundle = EntityPromptBundle(
      entities: recalled.entities,
      relations: recalled.relations,
    );
    return EntityPromptBundle(
      entities: bundle.entities,
      relations: bundle.relations,
      sttSection: promptComposer.buildSttSection(bundle),
      correctionEntitySection: promptComposer.buildCorrectionEntitySection(
        bundle,
      ),
      correctionRelationSection: promptComposer.buildCorrectionRelationSection(
        bundle,
      ),
    );
  }

  EntityPromptBundle buildForCorrection({
    required String currentText,
    required String contextText,
    required List<EntityMemory> memories,
    required List<EntityAlias> aliases,
    required List<EntityRelation> relations,
    required SessionEntityState sessionState,
    int maxEntities = defaultMaxCorrectionEntities,
  }) {
    final recalled = _recall(
      currentText: currentText,
      historyTexts: contextText.trim().isEmpty ? const [] : [contextText],
      contextTexts: const [],
      memories: memories,
      aliases: aliases,
      relations: relations,
      sessionState: sessionState,
      maxEntities: maxEntities,
    );
    final bundle = EntityPromptBundle(
      entities: recalled.entities,
      relations: recalled.relations,
    );
    return EntityPromptBundle(
      entities: bundle.entities,
      relations: bundle.relations,
      sttSection: promptComposer.buildSttSection(bundle),
      correctionEntitySection: promptComposer.buildCorrectionEntitySection(
        bundle,
      ),
      correctionRelationSection: promptComposer.buildCorrectionRelationSection(
        bundle,
      ),
    );
  }

  void activateMentions({
    required String text,
    required EntityPromptBundle bundle,
    required SessionEntityState sessionState,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    for (final recalled in bundle.entities) {
      if (normalized.contains(recalled.memory.canonicalName)) {
        sessionState.activate(
          entityId: recalled.memory.id,
          canonicalName: recalled.memory.canonicalName,
          alias: recalled.memory.canonicalName,
          score: 1.2,
        );
        continue;
      }
      for (final alias in recalled.aliases) {
        if (!normalized.contains(alias.aliasText)) continue;
        sessionState.activate(
          entityId: recalled.memory.id,
          canonicalName: recalled.memory.canonicalName,
          alias: alias.aliasText,
          score: alias.aliasType == EntityAliasType.misrecognition ? 1.0 : 0.8,
        );
        break;
      }
    }
  }

  _RecallResult _recall({
    required String currentText,
    required List<String> historyTexts,
    required List<String> contextTexts,
    required List<EntityMemory> memories,
    required List<EntityAlias> aliases,
    required List<EntityRelation> relations,
    required SessionEntityState sessionState,
    required int maxEntities,
  }) {
    final aliasByEntity = <String, List<EntityAlias>>{};
    for (final alias in aliases) {
      aliasByEntity.putIfAbsent(alias.entityId, () => []).add(alias);
    }

    final relationIndex = _buildRelationIndex(relations);
    final scored = <RecalledEntity>[];
    for (final memory in memories.where((e) => e.enabled)) {
      final entityAliases = aliasByEntity[memory.id] ?? const [];
      final score = _scoreEntity(
        memory: memory,
        aliases: entityAliases,
        relations: relationIndex[memory.id] ?? const [],
        currentText: currentText,
        historyTexts: historyTexts,
        contextTexts: contextTexts,
        sessionState: sessionState,
      );
      if (score <= 0) continue;
      scored.add(
        RecalledEntity(
          memory: memory,
          aliases: _limitAliases(entityAliases),
          score: score,
        ),
      );
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.memory.canonicalName.compareTo(b.memory.canonicalName);
    });

    final selected = _selectEntitiesWithRelationExpansion(
      scored: scored,
      relations: relations,
      maxEntities: maxEntities,
    );
    final selectedIds = selected.map((e) => e.memory.id).toSet();
    final selectedRelations = relations
        .where((relation) {
          return selectedIds.contains(relation.sourceEntityId) &&
              selectedIds.contains(relation.targetEntityId) &&
              relation.confidence >= 0.5;
        })
        .take(4)
        .toList(growable: false);

    return _RecallResult(entities: selected, relations: selectedRelations);
  }

  Map<String, List<EntityRelation>> _buildRelationIndex(
    List<EntityRelation> relations,
  ) {
    final index = <String, List<EntityRelation>>{};
    for (final relation in relations) {
      index.putIfAbsent(relation.sourceEntityId, () => []).add(relation);
      index.putIfAbsent(relation.targetEntityId, () => []).add(relation);
    }
    return index;
  }

  List<RecalledEntity> _selectEntitiesWithRelationExpansion({
    required List<RecalledEntity> scored,
    required List<EntityRelation> relations,
    required int maxEntities,
  }) {
    if (scored.isEmpty) return const [];

    final primary = scored.take(maxEntities).toList(growable: true);
    final primaryIds = primary.map((e) => e.memory.id).toSet();
    final relationCandidates = <RecalledEntity>[];

    for (final candidate in scored) {
      if (primaryIds.contains(candidate.memory.id)) continue;
      var relationBoost = 0.0;
      for (final relation in relations) {
        final touchesPrimary =
            (primaryIds.contains(relation.sourceEntityId) &&
                relation.targetEntityId == candidate.memory.id) ||
            (primaryIds.contains(relation.targetEntityId) &&
                relation.sourceEntityId == candidate.memory.id);
        if (!touchesPrimary || relation.confidence < 0.6) continue;
        relationBoost = relationBoost < 25 * relation.confidence
            ? 25 * relation.confidence
            : relationBoost;
      }
      if (relationBoost <= 0) continue;
      relationCandidates.add(
        RecalledEntity(
          memory: candidate.memory,
          aliases: candidate.aliases,
          score: candidate.score + relationBoost,
        ),
      );
    }

    relationCandidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.memory.canonicalName.compareTo(b.memory.canonicalName);
    });

    final merged = <String, RecalledEntity>{
      for (final item in primary) item.memory.id: item,
    };
    for (final candidate in relationCandidates.take(
      _maxRelationExpansionEntities,
    )) {
      final current = merged[candidate.memory.id];
      if (current == null || candidate.score > current.score) {
        merged[candidate.memory.id] = candidate;
      }
    }

    final selected = merged.values.toList(growable: false)
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.memory.canonicalName.compareTo(b.memory.canonicalName);
      });
    return selected.take(maxEntities).toList(growable: false);
  }

  double _scoreEntity({
    required EntityMemory memory,
    required List<EntityAlias> aliases,
    required List<EntityRelation> relations,
    required String currentText,
    required List<String> historyTexts,
    required List<String> contextTexts,
    required SessionEntityState sessionState,
  }) {
    var score = 0.0;
    final current = currentText.trim();
    final history = historyTexts.join('\n');
    final context = contextTexts.join('\n');
    final activation = sessionState.activations[memory.id];
    if (activation != null) {
      score += 100 + activation.score;
    }
    if (current.contains(memory.canonicalName)) score += 80;
    if (history.contains(memory.canonicalName)) score += 35;
    if (context.contains(memory.canonicalName)) score += 30;
    if (memory.confidence >= 0.9) {
      score += 15;
    } else {
      score += memory.confidence * 15;
    }

    for (final alias in aliases) {
      final value = alias.aliasText.trim();
      if (value.isEmpty) continue;
      final currentHit = current.contains(value);
      final historyHit = history.contains(value);
      final contextHit = context.contains(value);
      final typeBonus = switch (alias.aliasType) {
        EntityAliasType.fullName => 10.0,
        EntityAliasType.nickname => 8.0,
        EntityAliasType.alias => 0.0,
        EntityAliasType.misrecognition => 4.0,
        EntityAliasType.abbreviation => 6.0,
      };
      final currentBase = alias.aliasType == EntityAliasType.misrecognition
          ? 60.0
          : 80.0;
      if (currentHit) score += currentBase + typeBonus;
      if (historyHit) score += 35 + typeBonus * 0.4;
      if (contextHit) score += 30 + typeBonus * 0.3;
      if (value.runes.length <= 1 ||
          (RegExp(r'^[A-Za-z0-9]+$').hasMatch(value) && value.length <= 2)) {
        score -= 12;
      }
    }

    for (final relation in relations) {
      final relatedId = relation.sourceEntityId == memory.id
          ? relation.targetEntityId
          : relation.sourceEntityId;
      if (sessionState.activations.containsKey(relatedId)) {
        score += 25 * relation.confidence;
      }
    }

    if (DateTime.now().difference(memory.updatedAt).inDays > 90) {
      score -= 15;
    }
    final hasManualEvidence = aliases.any(
      (alias) =>
          alias.source == 'manual' ||
          alias.source == 'history-edit' ||
          alias.source == 'entity-memory',
    );
    if (!hasManualEvidence) {
      score -= 10;
    }
    if (activation == null &&
        !current.contains(memory.canonicalName) &&
        !history.contains(memory.canonicalName) &&
        !context.contains(memory.canonicalName)) {
      score -= 20;
    }
    return score;
  }

  List<EntityAlias> _limitAliases(List<EntityAlias> aliases) {
    if (aliases.length <= _maxAliasesPerEntity) {
      return aliases.toList(growable: false);
    }
    final grouped = <EntityAliasType, List<EntityAlias>>{};
    for (final alias in aliases) {
      grouped.putIfAbsent(alias.aliasType, () => []).add(alias);
    }
    for (final values in grouped.values) {
      values.sort((a, b) {
        final byConfidence = b.confidence.compareTo(a.confidence);
        if (byConfidence != 0) return byConfidence;
        return a.aliasText.compareTo(b.aliasText);
      });
    }

    final selected = <EntityAlias>[];
    for (final type in EntityAliasType.values) {
      final values = grouped[type];
      if (values == null || values.isEmpty) continue;
      final takeCount = type == EntityAliasType.alias ? 1 : 2;
      selected.addAll(values.take(takeCount));
      if (selected.length >= _maxAliasesPerEntity) break;
    }
    if (selected.length < _maxAliasesPerEntity) {
      final leftovers =
          aliases
              .where(
                (alias) => !selected.any((picked) => picked.id == alias.id),
              )
              .toList(growable: false)
            ..sort((a, b) => b.confidence.compareTo(a.confidence));
      selected.addAll(leftovers.take(_maxAliasesPerEntity - selected.length));
    }
    return selected.take(_maxAliasesPerEntity).toList(growable: false);
  }
}

class _RecallResult {
  final List<RecalledEntity> entities;
  final List<EntityRelation> relations;

  const _RecallResult({required this.entities, required this.relations});
}
