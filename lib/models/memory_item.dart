import 'package:uuid/uuid.dart';

enum MemoryItemKind { correction, preserve, entity, reference }

enum MemoryItemStatus { pending, weakActive, active, suppressed, archived }

enum MemoryItemScope { session, user, imported }

class MemoryItemStats {
  final int evidenceCount;
  final int positiveCount;
  final int negativeCount;
  final int promptInjectionCount;
  final int correctionHitCount;
  final int userKeptCount;
  final int userRevertedCount;
  final int rejectedCount;

  const MemoryItemStats({
    this.evidenceCount = 0,
    this.positiveCount = 0,
    this.negativeCount = 0,
    this.promptInjectionCount = 0,
    this.correctionHitCount = 0,
    this.userKeptCount = 0,
    this.userRevertedCount = 0,
    this.rejectedCount = 0,
  });

  MemoryItemStats copyWith({
    int? evidenceCount,
    int? positiveCount,
    int? negativeCount,
    int? promptInjectionCount,
    int? correctionHitCount,
    int? userKeptCount,
    int? userRevertedCount,
    int? rejectedCount,
  }) {
    return MemoryItemStats(
      evidenceCount: evidenceCount ?? this.evidenceCount,
      positiveCount: positiveCount ?? this.positiveCount,
      negativeCount: negativeCount ?? this.negativeCount,
      promptInjectionCount: promptInjectionCount ?? this.promptInjectionCount,
      correctionHitCount: correctionHitCount ?? this.correctionHitCount,
      userKeptCount: userKeptCount ?? this.userKeptCount,
      userRevertedCount: userRevertedCount ?? this.userRevertedCount,
      rejectedCount: rejectedCount ?? this.rejectedCount,
    );
  }

  MemoryItemStats add({
    int evidence = 0,
    int positive = 0,
    int negative = 0,
    int promptInjection = 0,
    int correctionHit = 0,
    int userKept = 0,
    int userReverted = 0,
    int rejected = 0,
  }) {
    return copyWith(
      evidenceCount: evidenceCount + evidence,
      positiveCount: positiveCount + positive,
      negativeCount: negativeCount + negative,
      promptInjectionCount: promptInjectionCount + promptInjection,
      correctionHitCount: correctionHitCount + correctionHit,
      userKeptCount: userKeptCount + userKept,
      userRevertedCount: userRevertedCount + userReverted,
      rejectedCount: rejectedCount + rejected,
    );
  }

  Map<String, dynamic> toJson() => {
    'evidenceCount': evidenceCount,
    'positiveCount': positiveCount,
    'negativeCount': negativeCount,
    'promptInjectionCount': promptInjectionCount,
    'correctionHitCount': correctionHitCount,
    'userKeptCount': userKeptCount,
    'userRevertedCount': userRevertedCount,
    'rejectedCount': rejectedCount,
  };

  factory MemoryItemStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MemoryItemStats();
    return MemoryItemStats(
      evidenceCount: (json['evidenceCount'] as num? ?? 0).toInt(),
      positiveCount: (json['positiveCount'] as num? ?? 0).toInt(),
      negativeCount: (json['negativeCount'] as num? ?? 0).toInt(),
      promptInjectionCount: (json['promptInjectionCount'] as num? ?? 0).toInt(),
      correctionHitCount: (json['correctionHitCount'] as num? ?? 0).toInt(),
      userKeptCount: (json['userKeptCount'] as num? ?? 0).toInt(),
      userRevertedCount: (json['userRevertedCount'] as num? ?? 0).toInt(),
      rejectedCount: (json['rejectedCount'] as num? ?? 0).toInt(),
    );
  }
}

class MemoryItem {
  static const Uuid _uuid = Uuid();

  final String id;
  final MemoryItemKind kind;
  final MemoryItemStatus status;
  final MemoryItemScope scope;
  final String original;
  final String canonical;
  final List<String> aliases;
  final String? content;
  final String? category;
  final String source;
  final double confidence;
  final double strength;
  final DateTime? cooldownUntil;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final DateTime? lastUsedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MemoryItemStats stats;

  const MemoryItem({
    required this.id,
    required this.kind,
    required this.status,
    required this.scope,
    required this.original,
    required this.canonical,
    this.aliases = const [],
    this.content,
    this.category,
    required this.source,
    required this.confidence,
    required this.strength,
    this.cooldownUntil,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.lastUsedAt,
    required this.createdAt,
    required this.updatedAt,
    this.stats = const MemoryItemStats(),
  });

  factory MemoryItem.create({
    required MemoryItemKind kind,
    required MemoryItemStatus status,
    required MemoryItemScope scope,
    String original = '',
    String canonical = '',
    List<String> aliases = const [],
    String? content,
    String? category,
    String source = 'manual',
    double confidence = 0.8,
    double strength = 0.0,
    DateTime? now,
    MemoryItemStats stats = const MemoryItemStats(),
  }) {
    final timestamp = now ?? DateTime.now();
    return MemoryItem(
      id: _uuid.v4(),
      kind: kind,
      status: status,
      scope: scope,
      original: original.trim(),
      canonical: canonical.trim(),
      aliases: _normalizeAliases(aliases),
      content: _nullableTrim(content),
      category: _nullableTrim(category),
      source: source.trim().isEmpty ? 'manual' : source.trim(),
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      strength: strength,
      firstSeenAt: timestamp,
      lastSeenAt: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
      stats: stats,
    );
  }

  String get displayText {
    if (canonical.trim().isNotEmpty) return canonical.trim();
    if (original.trim().isNotEmpty) return original.trim();
    return (content ?? '').trim();
  }

  bool get isPromptEligible => status == MemoryItemStatus.active;

  bool get isCorrectionEligible =>
      status == MemoryItemStatus.active ||
      status == MemoryItemStatus.weakActive;

  String get normalizedKey {
    return buildKey(kind: kind, original: original, canonical: canonical);
  }

  static String buildKey({
    required MemoryItemKind kind,
    required String original,
    required String canonical,
  }) {
    return [
      kind.name,
      _normalizeKeyPart(original),
      _normalizeKeyPart(canonical),
    ].join('|');
  }

  MemoryItem copyWith({
    String? id,
    MemoryItemKind? kind,
    MemoryItemStatus? status,
    MemoryItemScope? scope,
    String? original,
    String? canonical,
    List<String>? aliases,
    String? content,
    bool clearContent = false,
    String? category,
    bool clearCategory = false,
    String? source,
    double? confidence,
    double? strength,
    DateTime? cooldownUntil,
    bool clearCooldownUntil = false,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
    DateTime? lastUsedAt,
    bool clearLastUsedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    MemoryItemStats? stats,
  }) {
    return MemoryItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      scope: scope ?? this.scope,
      original: original ?? this.original,
      canonical: canonical ?? this.canonical,
      aliases: aliases ?? this.aliases,
      content: clearContent ? null : (content ?? this.content),
      category: clearCategory ? null : (category ?? this.category),
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      strength: strength ?? this.strength,
      cooldownUntil: clearCooldownUntil
          ? null
          : (cooldownUntil ?? this.cooldownUntil),
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastUsedAt: clearLastUsedAt ? null : (lastUsedAt ?? this.lastUsedAt),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      stats: stats ?? this.stats,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'status': status.name,
    'scope': scope.name,
    'original': original,
    'canonical': canonical,
    'aliases': aliases,
    'content': content,
    'category': category,
    'source': source,
    'confidence': confidence,
    'strength': strength,
    'cooldownUntil': cooldownUntil?.toIso8601String(),
    'firstSeenAt': firstSeenAt.toIso8601String(),
    'lastSeenAt': lastSeenAt.toIso8601String(),
    'lastUsedAt': lastUsedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'stats': stats.toJson(),
  };

  factory MemoryItem.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return MemoryItem(
      id: (json['id'] as String? ?? '').trim(),
      kind: _parseEnum(
        MemoryItemKind.values,
        json['kind'] as String?,
        MemoryItemKind.correction,
      ),
      status: _parseEnum(
        MemoryItemStatus.values,
        json['status'] as String?,
        MemoryItemStatus.pending,
      ),
      scope: _parseEnum(
        MemoryItemScope.values,
        json['scope'] as String?,
        MemoryItemScope.user,
      ),
      original: (json['original'] as String? ?? '').trim(),
      canonical: (json['canonical'] as String? ?? '').trim(),
      aliases:
          (json['aliases'] as List?)
              ?.whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false) ??
          const [],
      content: _nullableTrim(json['content'] as String?),
      category: _nullableTrim(json['category'] as String?),
      source: (json['source'] as String? ?? 'manual').trim(),
      confidence: (json['confidence'] as num? ?? 0.8)
          .toDouble()
          .clamp(0.0, 1.0)
          .toDouble(),
      strength: (json['strength'] as num? ?? 0).toDouble(),
      cooldownUntil: DateTime.tryParse(json['cooldownUntil'] as String? ?? ''),
      firstSeenAt:
          DateTime.tryParse(json['firstSeenAt'] as String? ?? '') ?? now,
      lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? '') ?? now,
      lastUsedAt: DateTime.tryParse(json['lastUsedAt'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      stats: MemoryItemStats.fromJson(
        (json['stats'] as Map?)?.cast<String, dynamic>(),
      ),
    );
  }

  static T _parseEnum<T extends Enum>(List<T> values, String? raw, T fallback) {
    final normalized = (raw ?? '').trim();
    for (final value in values) {
      if (value.name == normalized) return value;
    }
    return fallback;
  }

  static String _normalizeKeyPart(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static List<String> _normalizeAliases(List<String> aliases) {
    final seen = <String>{};
    final result = <String>[];
    for (final alias in aliases) {
      final value = alias.trim();
      if (value.isEmpty) continue;
      if (seen.add(value.toLowerCase())) result.add(value);
    }
    return result;
  }

  static String? _nullableTrim(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
