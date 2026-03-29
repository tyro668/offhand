import 'package:uuid/uuid.dart';

enum EntityAliasType { fullName, nickname, alias, misrecognition, abbreviation }

class EntityAlias {
  static const Uuid _uuid = Uuid();

  final String id;
  final String entityId;
  final String aliasText;
  final EntityAliasType aliasType;
  final String source;
  final double confidence;
  final DateTime createdAt;

  const EntityAlias({
    required this.id,
    required this.entityId,
    required this.aliasText,
    required this.aliasType,
    required this.source,
    required this.confidence,
    required this.createdAt,
  });

  factory EntityAlias.create({
    required String entityId,
    required String aliasText,
    required EntityAliasType aliasType,
    String source = 'manual',
    double confidence = 0.8,
  }) {
    return EntityAlias(
      id: _uuid.v4(),
      entityId: entityId,
      aliasText: aliasText.trim(),
      aliasType: aliasType,
      source: source.trim().isEmpty ? 'manual' : source.trim(),
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      createdAt: DateTime.now(),
    );
  }

  EntityAlias copyWith({
    String? id,
    String? entityId,
    String? aliasText,
    EntityAliasType? aliasType,
    String? source,
    double? confidence,
    DateTime? createdAt,
  }) {
    return EntityAlias(
      id: id ?? this.id,
      entityId: entityId ?? this.entityId,
      aliasText: aliasText ?? this.aliasText,
      aliasType: aliasType ?? this.aliasType,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityId': entityId,
    'aliasText': aliasText,
    'aliasType': aliasType.name,
    'source': source,
    'confidence': confidence,
    'createdAt': createdAt.toIso8601String(),
  };

  factory EntityAlias.fromJson(Map<String, dynamic> json) {
    final rawType = (json['aliasType'] as String? ?? '').trim();
    var aliasType = EntityAliasType.alias;
    for (final value in EntityAliasType.values) {
      if (value.name == rawType) {
        aliasType = value;
        break;
      }
    }
    return EntityAlias(
      id: (json['id'] as String? ?? '').trim(),
      entityId: (json['entityId'] as String? ?? '').trim(),
      aliasText: (json['aliasText'] as String? ?? '').trim(),
      aliasType: aliasType,
      source: (json['source'] as String? ?? 'manual').trim(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
