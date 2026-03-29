import 'package:uuid/uuid.dart';

enum EntityType { person, company, product, project, system, custom }

class EntityMemory {
  static const Uuid _uuid = Uuid();

  final String id;
  final String canonicalName;
  final EntityType type;
  final bool enabled;
  final double confidence;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EntityMemory({
    required this.id,
    required this.canonicalName,
    required this.type,
    required this.enabled,
    required this.confidence,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EntityMemory.create({
    required String canonicalName,
    required EntityType type,
    bool enabled = true,
    double confidence = 0.85,
  }) {
    final now = DateTime.now();
    return EntityMemory(
      id: _uuid.v4(),
      canonicalName: canonicalName.trim(),
      type: type,
      enabled: enabled,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      createdAt: now,
      updatedAt: now,
    );
  }

  EntityMemory copyWith({
    String? id,
    String? canonicalName,
    EntityType? type,
    bool? enabled,
    double? confidence,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EntityMemory(
      id: id ?? this.id,
      canonicalName: canonicalName ?? this.canonicalName,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      confidence: confidence ?? this.confidence,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'canonicalName': canonicalName,
    'type': type.name,
    'enabled': enabled,
    'confidence': confidence,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory EntityMemory.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String? ?? '').trim();
    var type = EntityType.custom;
    for (final value in EntityType.values) {
      if (value.name == rawType) {
        type = value;
        break;
      }
    }
    return EntityMemory(
      id: (json['id'] as String? ?? '').trim(),
      canonicalName: (json['canonicalName'] as String? ?? '').trim(),
      type: type,
      enabled: json['enabled'] as bool? ?? true,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.85,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
