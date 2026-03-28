import '../models/dictionary_entry.dart';
import '../models/term_context_entry.dart';
import '../models/transcription.dart';
import 'session_glossary.dart';

class TermRecallService {
  static const int defaultMaxTerms = 18;

  const TermRecallService();

  List<String> recallPreferredTerms({
    required String currentText,
    required List<Transcription> history,
    required List<DictionaryEntry> dictionaryEntries,
    required SessionGlossary sessionGlossary,
    List<TermContextEntry> termContextEntries = const [],
    int maxTerms = defaultMaxTerms,
  }) {
    final queryKeywords = _buildQueryKeywords(currentText, history);
    final scored = <_ScoredTerm>[];
    final seen = <String>{};

    for (final pin in sessionGlossary.strongEntries.values) {
      final canonical = pin.corrected.trim();
      if (canonical.isEmpty) continue;
      final key = canonical.toLowerCase();
      if (!seen.add(key)) continue;
      scored.add(
        _ScoredTerm(
          term: canonical,
          score: 100 + pin.hitCount.toDouble(),
          sourcePriority: 0,
        ),
      );
    }

    for (final entry in dictionaryEntries.where((e) => e.enabled)) {
      final canonical = _canonicalTerm(entry);
      if (canonical.isEmpty) continue;
      final key = canonical.toLowerCase();
      if (!seen.add(key)) continue;
      final score = _scoreTerm(canonical, queryKeywords) +
          (entry.source == DictionaryEntrySource.historyEdit ? 8 : 4);
      scored.add(
        _ScoredTerm(
          term: canonical,
          score: score,
          sourcePriority: entry.source == DictionaryEntrySource.historyEdit
              ? 1
              : 2,
        ),
      );
    }

    for (final entry in termContextEntries.where((e) => e.enabled)) {
      if (entry.isDocumentContext) continue;
      final value = entry.promptTerm.trim();
      if (value.isEmpty) continue;
      final key = value.toLowerCase();
      if (!seen.add(key)) continue;
      final sourceBonus = switch (entry.entryType) {
        TermContextEntryType.correctionHint => 3.5,
        TermContextEntryType.preserveHint => 3.0,
        TermContextEntryType.reference => 1.5,
      };
      scored.add(
        _ScoredTerm(
          term: value,
          score: _scoreTerm(value, queryKeywords) + sourceBonus + entry.confidence,
          sourcePriority: 3,
        ),
      );
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final bySource = a.sourcePriority.compareTo(b.sourcePriority);
      if (bySource != 0) return bySource;
      final byLength = b.term.length.compareTo(a.term.length);
      if (byLength != 0) return byLength;
      return a.term.compareTo(b.term);
    });

    final terms = scored
        .map((e) => e.term)
        .take(maxTerms)
        .toList(growable: false);
    if (terms.isNotEmpty) return terms;

    return dictionaryEntries
        .where((e) => e.enabled)
        .map(_canonicalTerm)
        .where((e) => e.isNotEmpty)
        .take(maxTerms)
        .toList(growable: false);
  }

  Set<String> _buildQueryKeywords(
    String currentText,
    List<Transcription> history,
  ) {
    final candidates = <String>[
      currentText,
      ...history.take(5).map((e) => e.text),
    ];
    final keywords = <String>{};
    final regex = RegExp(
      r'[A-Za-z][A-Za-z0-9\-_]{1,}|[0-9]+(?:\.[0-9]+)?|[\u4e00-\u9fff]{2,}',
    );
    for (final text in candidates) {
      for (final match in regex.allMatches(text)) {
        final value = match.group(0)!.trim().toLowerCase();
        if (value.length >= 2) {
          keywords.add(value);
        }
      }
    }
    return keywords;
  }

  double _scoreTerm(String term, Set<String> queryKeywords) {
    if (queryKeywords.isEmpty) {
      return term.length <= 8 ? 1 : 0.5;
    }
    final normalized = term.toLowerCase();
    var score = 0.0;
    for (final keyword in queryKeywords) {
      if (normalized == keyword) {
        score += 20;
        continue;
      }
      if (normalized.contains(keyword) || keyword.contains(normalized)) {
        score += 8;
      }
    }
    if (RegExp(r'[A-Z]').hasMatch(term)) {
      score += 1.5;
    }
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(term)) {
      score += 1;
    }
    return score;
  }

  String _canonicalTerm(DictionaryEntry entry) {
    final corrected = (entry.corrected ?? '').trim();
    final original = entry.original.trim();
    if (entry.type == DictionaryEntryType.correction && corrected.isNotEmpty) {
      final originalHasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(original);
      final correctedHasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(corrected);
      if (originalHasChinese && !correctedHasChinese) {
        return original;
      }
      return corrected;
    }
    return original;
  }
}

class _ScoredTerm {
  final String term;
  final double score;
  final int sourcePriority;

  const _ScoredTerm({
    required this.term,
    required this.score,
    required this.sourcePriority,
  });
}
