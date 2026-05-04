import 'package:uuid/uuid.dart';

enum MemoryEventType {
  observe,
  accept,
  reject,
  revert,
  promptInjected,
  correctionHit,
  userKept,
  userEdited,
  archive,
}

class MemoryEvent {
  static const Uuid _uuid = Uuid();

  final String id;
  final String? memoryId;
  final MemoryEventType eventType;
  final String sourceType;
  final String sourceRef;
  final String original;
  final String canonical;
  final String? beforeTextExcerpt;
  final String? afterTextExcerpt;
  final String? rawTextExcerpt;
  final double confidenceDelta;
  final double strengthDelta;
  final DateTime createdAt;

  const MemoryEvent({
    required this.id,
    this.memoryId,
    required this.eventType,
    required this.sourceType,
    required this.sourceRef,
    required this.original,
    required this.canonical,
    this.beforeTextExcerpt,
    this.afterTextExcerpt,
    this.rawTextExcerpt,
    this.confidenceDelta = 0,
    this.strengthDelta = 0,
    required this.createdAt,
  });

  factory MemoryEvent.create({
    String? memoryId,
    required MemoryEventType eventType,
    required String sourceType,
    String sourceRef = '',
    String original = '',
    String canonical = '',
    String? beforeTextExcerpt,
    String? afterTextExcerpt,
    String? rawTextExcerpt,
    double confidenceDelta = 0,
    double strengthDelta = 0,
    DateTime? createdAt,
  }) {
    return MemoryEvent(
      id: _uuid.v4(),
      memoryId: _nullableTrim(memoryId),
      eventType: eventType,
      sourceType: sourceType.trim(),
      sourceRef: sourceRef.trim(),
      original: original.trim(),
      canonical: canonical.trim(),
      beforeTextExcerpt: _nullableTrim(beforeTextExcerpt),
      afterTextExcerpt: _nullableTrim(afterTextExcerpt),
      rawTextExcerpt: _nullableTrim(rawTextExcerpt),
      confidenceDelta: confidenceDelta,
      strengthDelta: strengthDelta,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  MemoryEvent copyWith({
    String? id,
    String? memoryId,
    bool clearMemoryId = false,
    MemoryEventType? eventType,
    String? sourceType,
    String? sourceRef,
    String? original,
    String? canonical,
    String? beforeTextExcerpt,
    bool clearBeforeTextExcerpt = false,
    String? afterTextExcerpt,
    bool clearAfterTextExcerpt = false,
    String? rawTextExcerpt,
    bool clearRawTextExcerpt = false,
    double? confidenceDelta,
    double? strengthDelta,
    DateTime? createdAt,
  }) {
    return MemoryEvent(
      id: id ?? this.id,
      memoryId: clearMemoryId ? null : (memoryId ?? this.memoryId),
      eventType: eventType ?? this.eventType,
      sourceType: sourceType ?? this.sourceType,
      sourceRef: sourceRef ?? this.sourceRef,
      original: original ?? this.original,
      canonical: canonical ?? this.canonical,
      beforeTextExcerpt: clearBeforeTextExcerpt
          ? null
          : (beforeTextExcerpt ?? this.beforeTextExcerpt),
      afterTextExcerpt: clearAfterTextExcerpt
          ? null
          : (afterTextExcerpt ?? this.afterTextExcerpt),
      rawTextExcerpt: clearRawTextExcerpt
          ? null
          : (rawTextExcerpt ?? this.rawTextExcerpt),
      confidenceDelta: confidenceDelta ?? this.confidenceDelta,
      strengthDelta: strengthDelta ?? this.strengthDelta,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'memoryId': memoryId,
    'eventType': eventType.name,
    'sourceType': sourceType,
    'sourceRef': sourceRef,
    'original': original,
    'canonical': canonical,
    'beforeTextExcerpt': beforeTextExcerpt,
    'afterTextExcerpt': afterTextExcerpt,
    'rawTextExcerpt': rawTextExcerpt,
    'confidenceDelta': confidenceDelta,
    'strengthDelta': strengthDelta,
    'createdAt': createdAt.toIso8601String(),
  };

  factory MemoryEvent.fromJson(Map<String, dynamic> json) {
    return MemoryEvent(
      id: (json['id'] as String? ?? '').trim(),
      memoryId: _nullableTrim(json['memoryId'] as String?),
      eventType: _parseEventType(json['eventType'] as String?),
      sourceType: (json['sourceType'] as String? ?? '').trim(),
      sourceRef: (json['sourceRef'] as String? ?? '').trim(),
      original: (json['original'] as String? ?? '').trim(),
      canonical: (json['canonical'] as String? ?? '').trim(),
      beforeTextExcerpt: _nullableTrim(json['beforeTextExcerpt'] as String?),
      afterTextExcerpt: _nullableTrim(json['afterTextExcerpt'] as String?),
      rawTextExcerpt: _nullableTrim(json['rawTextExcerpt'] as String?),
      confidenceDelta: (json['confidenceDelta'] as num? ?? 0).toDouble(),
      strengthDelta: (json['strengthDelta'] as num? ?? 0).toDouble(),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static MemoryEventType _parseEventType(String? raw) {
    final normalized = (raw ?? '').trim();
    for (final value in MemoryEventType.values) {
      if (value.name == normalized) return value;
    }
    return MemoryEventType.observe;
  }

  static String? _nullableTrim(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
