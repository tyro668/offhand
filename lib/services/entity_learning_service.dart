import '../models/entity_alias.dart';
import '../models/entity_memory.dart';
import 'dictation_term_memory_service.dart';

class EntityLearningCandidate {
  final String original;
  final String canonicalName;
  final EntityType entityType;
  final EntityAliasType aliasType;
  final double confidence;

  const EntityLearningCandidate({
    required this.original,
    required this.canonicalName,
    required this.entityType,
    required this.aliasType,
    required this.confidence,
  });
}

class EntityLearningService {
  final DictationTermMemoryService termMemoryService;

  const EntityLearningService({
    this.termMemoryService = const DictationTermMemoryService(),
  });

  List<EntityLearningCandidate> extractCandidates({
    required String beforeText,
    required String afterText,
    String? rawText,
  }) {
    final termCandidates = termMemoryService.extractCandidates(
      beforeText: beforeText,
      afterText: afterText,
      rawText: rawText,
    );
    final results = <EntityLearningCandidate>[];
    for (final candidate in termCandidates) {
      final canonical = candidate.corrected.trim();
      final original = candidate.original.trim();
      if (!_looksLikeEntity(canonical)) continue;
      results.add(
        EntityLearningCandidate(
          original: original,
          canonicalName: canonical,
          entityType: _inferEntityType(canonical),
          aliasType: _inferAliasType(original, canonical),
          confidence: (candidate.confidence + 0.1).clamp(0.0, 1.0).toDouble(),
        ),
      );
    }
    return results;
  }

  bool _looksLikeEntity(String text) {
    final value = text.trim();
    if (value.isEmpty || value.length < 2 || value.length > 24) return false;
    if (value.contains('\n')) return false;
    if (RegExp(r'[\u4e00-\u9fff]{2,4}').hasMatch(value)) return true;
    if (RegExp(r'[A-Z][A-Za-z0-9\-_]{1,}').hasMatch(value)) return true;
    if (RegExp(r'(公司|集团|科技|数据|系统|项目)$').hasMatch(value)) return true;
    return false;
  }

  EntityType _inferEntityType(String canonical) {
    if (RegExp(r'(公司|集团|科技|数据)$').hasMatch(canonical)) {
      return EntityType.company;
    }
    if (RegExp(r'(系统)$').hasMatch(canonical)) {
      return EntityType.system;
    }
    if (RegExp(r'(项目)$').hasMatch(canonical)) {
      return EntityType.project;
    }
    if (RegExp(r'[A-Z][A-Za-z0-9\-_]{1,}').hasMatch(canonical)) {
      return EntityType.product;
    }
    if (RegExp(r'^[\u4e00-\u9fff]{2,4}$').hasMatch(canonical)) {
      return EntityType.person;
    }
    return EntityType.custom;
  }

  EntityAliasType _inferAliasType(String original, String canonical) {
    final trimmedOriginal = original.trim();
    if (trimmedOriginal.isEmpty || trimmedOriginal == canonical.trim()) {
      return EntityAliasType.alias;
    }
    if (RegExp(r'^[A-Z0-9\-_]{2,}$').hasMatch(trimmedOriginal)) {
      return EntityAliasType.abbreviation;
    }
    return EntityAliasType.misrecognition;
  }
}
