import 'package:uuid/uuid.dart';

enum TermContextEntryType { correctionHint, preserveHint, reference }

class TermContextEntry {
  static const Uuid _uuid = Uuid();

  final String id;
  final String term;
  final String? alias;
  final String? canonical;
  final String? content;
  final String sourceName;
  final String sourceType;
  final TermContextEntryType entryType;
  final bool enabled;
  final double confidence;
  final DateTime createdAt;

  const TermContextEntry({
    required this.id,
    required this.term,
    required this.alias,
    required this.canonical,
    required this.content,
    required this.sourceName,
    required this.sourceType,
    required this.entryType,
    required this.enabled,
    required this.confidence,
    required this.createdAt,
  });

  factory TermContextEntry.create({
    required String term,
    String? alias,
    String? canonical,
    String? content,
    required String sourceName,
    String sourceType = 'markdown',
    required TermContextEntryType entryType,
    bool enabled = true,
    double confidence = 0.8,
  }) {
    return TermContextEntry(
      id: _uuid.v4(),
      term: term.trim(),
      alias: alias?.trim().isEmpty ?? true ? null : alias!.trim(),
      canonical: canonical?.trim().isEmpty ?? true ? null : canonical!.trim(),
      content: content?.trim().isEmpty ?? true ? null : content!.trim(),
      sourceName: sourceName.trim(),
      sourceType: sourceType.trim().isEmpty ? 'markdown' : sourceType.trim(),
      entryType: entryType,
      enabled: enabled,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      createdAt: DateTime.now(),
    );
  }

  String get promptTerm {
    final canonicalTerm = canonical?.trim() ?? '';
    if (canonicalTerm.isNotEmpty) return canonicalTerm;
    return term.trim();
  }

  bool get promotableAsCorrection =>
      !isDocumentContext &&
      entryType == TermContextEntryType.correctionHint &&
      (alias?.trim().isNotEmpty ?? false) &&
      promptTerm.isNotEmpty;

  bool get promotableAsPreserve =>
      !isDocumentContext &&
      entryType == TermContextEntryType.preserveHint && promptTerm.isNotEmpty;

  bool get isDocumentContext => (content?.trim().isNotEmpty ?? false);

  String get displayTitle => sourceName.trim().isNotEmpty ? sourceName : term.trim();

  String get contentPreview {
    final text = (content ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 160) return text;
    return '${text.substring(0, 160)}...';
  }

  String get signature {
    return [
      entryType.name,
      term.trim().toLowerCase(),
      (alias ?? '').trim().toLowerCase(),
      (canonical ?? '').trim().toLowerCase(),
      (content ?? '').trim().toLowerCase(),
      sourceName.trim().toLowerCase(),
      sourceType.trim().toLowerCase(),
    ].join('|');
  }

  TermContextEntry copyWith({
    String? id,
    String? term,
    String? alias,
    bool clearAlias = false,
    String? canonical,
    bool clearCanonical = false,
    String? content,
    bool clearContent = false,
    String? sourceName,
    String? sourceType,
    TermContextEntryType? entryType,
    bool? enabled,
    double? confidence,
    DateTime? createdAt,
  }) {
    return TermContextEntry(
      id: id ?? this.id,
      term: term ?? this.term,
      alias: clearAlias ? null : (alias ?? this.alias),
      canonical: clearCanonical ? null : (canonical ?? this.canonical),
      content: clearContent ? null : (content ?? this.content),
      sourceName: sourceName ?? this.sourceName,
      sourceType: sourceType ?? this.sourceType,
      entryType: entryType ?? this.entryType,
      enabled: enabled ?? this.enabled,
      confidence: confidence ?? this.confidence,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'term': term,
    'alias': alias,
    'canonical': canonical,
    'content': content,
    'sourceName': sourceName,
    'sourceType': sourceType,
    'entryType': entryType.name,
    'enabled': enabled,
    'confidence': confidence,
    'createdAt': createdAt.toIso8601String(),
  };

  factory TermContextEntry.fromJson(Map<String, dynamic> json) {
    return TermContextEntry(
      id: (json['id'] as String? ?? '').trim(),
      term: (json['term'] as String? ?? '').trim(),
      alias: (json['alias'] as String?)?.trim(),
      canonical: (json['canonical'] as String?)?.trim(),
      content: (json['content'] as String?)?.trim(),
      sourceName: (json['sourceName'] as String? ?? '').trim(),
      sourceType: (json['sourceType'] as String? ?? 'markdown').trim(),
      entryType: _entryTypeFromString(json['entryType'] as String?),
      enabled: json['enabled'] as bool? ?? true,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static TermContextEntryType _entryTypeFromString(String? raw) {
    for (final value in TermContextEntryType.values) {
      if (value.name == (raw ?? '').trim()) return value;
    }
    return TermContextEntryType.reference;
  }
}
