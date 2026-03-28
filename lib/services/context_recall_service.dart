import '../models/context_hints.dart';
import '../models/transcription.dart';

class ContextRecallService {
  static const int defaultMaxCandidates = 10;
  static const int defaultMaxReferences = 3;

  const ContextRecallService();

  ContextHints recall({
    required String currentText,
    required List<Transcription> history,
    int maxCandidates = defaultMaxCandidates,
    int maxReferences = defaultMaxReferences,
  }) {
    final normalizedCurrentText = currentText.trim();
    if (normalizedCurrentText.isEmpty || history.isEmpty) {
      return const ContextHints();
    }

    final recentHistory = history.take(maxCandidates).toList(growable: false);
    final currentKeywords = _extractKeywords(normalizedCurrentText);
    final currentStyle = _detectStyle(normalizedCurrentText);

    final scored = <_ScoredHistory>[];
    for (var i = 0; i < recentHistory.length; i++) {
      final item = recentHistory[i];
      final text = item.text.trim();
      if (text.isEmpty) continue;
      final keywords = _extractKeywords(text);
      final sharedKeywordCount = keywords.intersection(currentKeywords).length;
      final style = _detectStyle(text);

      var score = (maxCandidates - i) / maxCandidates;
      score += sharedKeywordCount * 2.0;
      if (currentStyle == style && style != '通用') {
        score += 0.8;
      }
      if (normalizedCurrentText.length <= 18 && i < 3) {
        score += 0.6;
      }
      if (score <= 1.0 && sharedKeywordCount == 0 && i >= 3) {
        continue;
      }

      scored.add(
        _ScoredHistory(
          item: item,
          score: score,
          style: style,
          topic: _inferTopic(text),
          entities: _extractEntities(text),
        ),
      );
    }

    if (scored.isEmpty) {
      return const ContextHints();
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final references = scored.take(maxReferences).toList(growable: false);

    final topicCounts = <String, int>{};
    final styleCounts = <String, int>{};
    final entityCounts = <String, int>{};
    final referenceTexts = <String>[];

    for (final reference in references) {
      if (reference.topic != null && reference.topic!.isNotEmpty) {
        topicCounts.update(
          reference.topic!,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      styleCounts.update(
        reference.style,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      for (final entity in reference.entities) {
        entityCounts.update(entity, (value) => value + 1, ifAbsent: () => 1);
      }
      referenceTexts.add(reference.item.text.trim());
    }

    final sortedEntities = entityCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ContextHints(
      recentTopic: _topValue(topicCounts),
      recentStyle: _topValue(styleCounts),
      relatedEntities: sortedEntities
          .take(4)
          .map((entry) => entry.key)
          .toList(growable: false),
      referenceTexts: referenceTexts.take(3).toList(growable: false),
    );
  }

  Set<String> _extractKeywords(String text) {
    final matches = RegExp(
      r'[A-Za-z][A-Za-z0-9\-_]{1,}|[0-9]+(?:\.[0-9]+)?|[\u4e00-\u9fff]{2,}',
    ).allMatches(text);
    return matches
        .map((match) => match.group(0)!.trim().toLowerCase())
        .where((value) => value.length >= 2)
        .toSet();
  }

  List<String> _extractEntities(String text) {
    final seen = <String>{};
    final entities = <String>[];
    final matches = RegExp(
      r'[A-Z][A-Za-z0-9\-_]{1,}|v?[0-9]+\.[0-9]+(?:\.[0-9]+)?|[\u4e00-\u9fff]{2,6}',
    ).allMatches(text);
    for (final match in matches) {
      final value = match.group(0)!.trim();
      if (value.length < 2) continue;
      final key = value.toLowerCase();
      if (seen.add(key)) {
        entities.add(value);
      }
      if (entities.length >= 5) break;
    }
    return entities;
  }

  String _detectStyle(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '通用';
    final lower = trimmed.toLowerCase();
    if (lower.contains('dear ') ||
        lower.contains('regards') ||
        lower.contains('best,') ||
        lower.contains('thanks')) {
      return '英文商务';
    }
    if (trimmed.contains('您好') ||
        trimmed.contains('感谢') ||
        trimmed.contains('请您') ||
        trimmed.contains('烦请')) {
      return '正式';
    }
    if (RegExp(r'^[\x00-\x7F\s\p{P}]+$', unicode: true).hasMatch(trimmed)) {
      return '英文';
    }
    if (trimmed.contains('这个') ||
        trimmed.contains('然后') ||
        trimmed.contains('先')) {
      return '口语';
    }
    return '通用';
  }

  String? _inferTopic(String text) {
    if (text.contains('岗位') || text.contains('候选人') || text.contains('招聘')) {
      return '招聘';
    }
    if (text.contains('邮件') || text.contains('您好') || text.contains('感谢')) {
      return '邮件沟通';
    }
    if (text.contains('日报') || text.contains('周报') || text.contains('同步')) {
      return '工作同步';
    }
    if (text.contains('接口') || text.contains('版本') || text.contains('发布')) {
      return '技术方案';
    }
    return null;
  }

  String? _topValue(Map<String, int> counts) {
    if (counts.isEmpty) return null;
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }
}

class _ScoredHistory {
  final Transcription item;
  final double score;
  final String style;
  final String? topic;
  final List<String> entities;

  const _ScoredHistory({
    required this.item,
    required this.score,
    required this.style,
    required this.topic,
    required this.entities,
  });
}
