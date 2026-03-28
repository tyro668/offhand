class ImportedReferenceTerm {
  final String term;
  final String sourceName;
  final DateTime createdAt;

  const ImportedReferenceTerm({
    required this.term,
    required this.sourceName,
    required this.createdAt,
  });

  factory ImportedReferenceTerm.create({
    required String term,
    required String sourceName,
  }) {
    return ImportedReferenceTerm(
      term: term.trim(),
      sourceName: sourceName.trim(),
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'term': term,
    'sourceName': sourceName,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ImportedReferenceTerm.fromJson(Map<String, dynamic> json) {
    return ImportedReferenceTerm(
      term: (json['term'] as String? ?? '').trim(),
      sourceName: (json['sourceName'] as String? ?? '').trim(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
