import 'package:uuid/uuid.dart';

class EntityRelation {
  static const Uuid _uuid = Uuid();

  final String id;
  final String sourceEntityId;
  final String targetEntityId;
  final String relationType;
  final double confidence;
  final String source;

  const EntityRelation({
    required this.id,
    required this.sourceEntityId,
    required this.targetEntityId,
    required this.relationType,
    required this.confidence,
    required this.source,
  });

  factory EntityRelation.create({
    required String sourceEntityId,
    required String targetEntityId,
    required String relationType,
    double confidence = 0.8,
    String source = 'manual',
  }) {
    return EntityRelation(
      id: _uuid.v4(),
      sourceEntityId: sourceEntityId,
      targetEntityId: targetEntityId,
      relationType: relationType.trim(),
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      source: source.trim().isEmpty ? 'manual' : source.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceEntityId': sourceEntityId,
    'targetEntityId': targetEntityId,
    'relationType': relationType,
    'confidence': confidence,
    'source': source,
  };

  factory EntityRelation.fromJson(Map<String, dynamic> json) {
    return EntityRelation(
      id: (json['id'] as String? ?? '').trim(),
      sourceEntityId: (json['sourceEntityId'] as String? ?? '').trim(),
      targetEntityId: (json['targetEntityId'] as String? ?? '').trim(),
      relationType: (json['relationType'] as String? ?? '').trim(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
      source: (json['source'] as String? ?? 'manual').trim(),
    );
  }
}
