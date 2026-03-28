import 'package:uuid/uuid.dart';

class DictationTermPendingCandidate {
  final String id;
  final String original;
  final String corrected;
  final String? category;
  final double confidence;
  final int occurrenceCount;
  final String? sourceHistoryId;
  final DateTime createdAt;

  const DictationTermPendingCandidate({
    required this.id,
    required this.original,
    required this.corrected,
    this.category,
    required this.confidence,
    required this.occurrenceCount,
    this.sourceHistoryId,
    required this.createdAt,
  });

  factory DictationTermPendingCandidate.create({
    required String original,
    required String corrected,
    String? category,
    required double confidence,
    String? sourceHistoryId,
  }) {
    return DictationTermPendingCandidate(
      id: const Uuid().v4(),
      original: original.trim(),
      corrected: corrected.trim(),
      category: (category == null || category.trim().isEmpty)
          ? null
          : category.trim(),
      confidence: confidence.clamp(0, 1).toDouble(),
      occurrenceCount: 1,
      sourceHistoryId: sourceHistoryId,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'original': original,
    'corrected': corrected,
    'category': category,
    'confidence': confidence,
    'occurrenceCount': occurrenceCount,
    'sourceHistoryId': sourceHistoryId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory DictationTermPendingCandidate.fromJson(Map<String, dynamic> json) {
    return DictationTermPendingCandidate(
      id: json['id'] as String,
      original: (json['original'] as String? ?? '').trim(),
      corrected: (json['corrected'] as String? ?? '').trim(),
      category: (json['category'] as String?)?.trim().isEmpty == true
          ? null
          : (json['category'] as String?)?.trim(),
      confidence: (json['confidence'] as num? ?? 0).toDouble(),
      occurrenceCount: (json['occurrenceCount'] as num? ?? 1).toInt(),
      sourceHistoryId: json['sourceHistoryId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  DictationTermPendingCandidate copyWith({
    String? original,
    String? corrected,
    String? category,
    double? confidence,
    int? occurrenceCount,
    String? sourceHistoryId,
    DateTime? createdAt,
  }) {
    return DictationTermPendingCandidate(
      id: id,
      original: original ?? this.original,
      corrected: corrected ?? this.corrected,
      category: category ?? this.category,
      confidence: confidence ?? this.confidence,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
      sourceHistoryId: sourceHistoryId ?? this.sourceHistoryId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
