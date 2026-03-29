import 'package:uuid/uuid.dart';

class EntityEvidence {
  static const Uuid _uuid = Uuid();

  final String id;
  final String entityId;
  final String sourceType;
  final String sourceRef;
  final String beforeText;
  final String afterText;
  final String extractedAlias;
  final DateTime createdAt;

  const EntityEvidence({
    required this.id,
    required this.entityId,
    required this.sourceType,
    required this.sourceRef,
    required this.beforeText,
    required this.afterText,
    required this.extractedAlias,
    required this.createdAt,
  });

  factory EntityEvidence.create({
    required String entityId,
    required String sourceType,
    required String sourceRef,
    required String beforeText,
    required String afterText,
    required String extractedAlias,
  }) {
    return EntityEvidence(
      id: _uuid.v4(),
      entityId: entityId,
      sourceType: sourceType.trim(),
      sourceRef: sourceRef.trim(),
      beforeText: beforeText.trim(),
      afterText: afterText.trim(),
      extractedAlias: extractedAlias.trim(),
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityId': entityId,
    'sourceType': sourceType,
    'sourceRef': sourceRef,
    'beforeText': beforeText,
    'afterText': afterText,
    'extractedAlias': extractedAlias,
    'createdAt': createdAt.toIso8601String(),
  };

  factory EntityEvidence.fromJson(Map<String, dynamic> json) {
    return EntityEvidence(
      id: (json['id'] as String? ?? '').trim(),
      entityId: (json['entityId'] as String? ?? '').trim(),
      sourceType: (json['sourceType'] as String? ?? '').trim(),
      sourceRef: (json['sourceRef'] as String? ?? '').trim(),
      beforeText: (json['beforeText'] as String? ?? '').trim(),
      afterText: (json['afterText'] as String? ?? '').trim(),
      extractedAlias: (json['extractedAlias'] as String? ?? '').trim(),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
