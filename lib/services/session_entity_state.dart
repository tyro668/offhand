class SessionEntityActivation {
  final String entityId;
  final String canonicalName;
  final double score;
  final DateTime lastActivatedAt;
  final Set<String> recentAliases;

  const SessionEntityActivation({
    required this.entityId,
    required this.canonicalName,
    required this.score,
    required this.lastActivatedAt,
    required this.recentAliases,
  });

  SessionEntityActivation copyWith({
    String? entityId,
    String? canonicalName,
    double? score,
    DateTime? lastActivatedAt,
    Set<String>? recentAliases,
  }) {
    return SessionEntityActivation(
      entityId: entityId ?? this.entityId,
      canonicalName: canonicalName ?? this.canonicalName,
      score: score ?? this.score,
      lastActivatedAt: lastActivatedAt ?? this.lastActivatedAt,
      recentAliases: recentAliases ?? this.recentAliases,
    );
  }
}

class SessionEntityState {
  final Map<String, SessionEntityActivation> _activations = {};

  Map<String, SessionEntityActivation> get activations =>
      Map.unmodifiable(_activations);

  bool get hasActivations => _activations.isNotEmpty;

  void activate({
    required String entityId,
    required String canonicalName,
    required String alias,
    double score = 1.0,
  }) {
    final normalizedAlias = alias.trim();
    if (entityId.trim().isEmpty || canonicalName.trim().isEmpty) return;
    final now = DateTime.now();
    final current = _activations[entityId];
    final nextAliases = <String>{
      ...?current?.recentAliases,
      if (normalizedAlias.isNotEmpty) normalizedAlias,
    };
    _activations[entityId] = SessionEntityActivation(
      entityId: entityId,
      canonicalName: canonicalName.trim(),
      score: (current?.score ?? 0) + score,
      lastActivatedAt: now,
      recentAliases: nextAliases,
    );
  }

  List<SessionEntityActivation> topActivations({int limit = 8}) {
    final items = _activations.values.toList(growable: false)
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return b.lastActivatedAt.compareTo(a.lastActivatedAt);
      });
    return items.take(limit).toList(growable: false);
  }

  void decay({double factor = 0.9}) {
    final next = <String, SessionEntityActivation>{};
    for (final entry in _activations.entries) {
      final score = entry.value.score * factor;
      if (score < 0.25) continue;
      next[entry.key] = entry.value.copyWith(score: score);
    }
    _activations
      ..clear()
      ..addAll(next);
  }

  void reset() {
    _activations.clear();
  }
}
