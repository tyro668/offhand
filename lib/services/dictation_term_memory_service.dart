class DictationTermCandidate {
  final String original;
  final String corrected;
  final double confidence;

  const DictationTermCandidate({
    required this.original,
    required this.corrected,
    required this.confidence,
  });
}

/// 从历史听写编辑中抽取可复用的术语修正规则。
///
/// 该版本以保守策略为主，只识别局部短语替换，避免把整句改写误收敛为词典规则。
class DictationTermMemoryService {
  const DictationTermMemoryService();

  List<DictationTermCandidate> extractCandidates({
    required String beforeText,
    required String afterText,
    String? rawText,
  }) {
    final before = _normalizeText(beforeText);
    final after = _normalizeText(afterText);
    if (before.isEmpty || after.isEmpty || before == after) {
      return const [];
    }

    final span = _extractChangedSpan(before, after);
    if (span == null) return const [];

    final original = _trimNoise(span.before);
    final corrected = _trimNoise(span.after);
    if (!_isValidCandidate(original, corrected)) {
      return const [];
    }

    final confidence = _scoreCandidate(
      original: original,
      corrected: corrected,
      rawText: rawText,
    );
    if (confidence < 0.58) {
      return const [];
    }

    return [
      DictationTermCandidate(
        original: original,
        corrected: corrected,
        confidence: confidence,
      ),
    ];
  }

  String _normalizeText(String text) {
    return text.replaceAll('\r\n', '\n').trim();
  }

  _ChangedSpan? _extractChangedSpan(String before, String after) {
    var prefix = 0;
    while (prefix < before.length &&
        prefix < after.length &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }

    var beforeSuffix = before.length - 1;
    var afterSuffix = after.length - 1;
    while (beforeSuffix >= prefix &&
        afterSuffix >= prefix &&
        before.codeUnitAt(beforeSuffix) == after.codeUnitAt(afterSuffix)) {
      beforeSuffix--;
      afterSuffix--;
    }

    final changedBefore = before.substring(prefix, beforeSuffix + 1);
    final changedAfter = after.substring(prefix, afterSuffix + 1);
    if (changedBefore.trim().isEmpty || changedAfter.trim().isEmpty) {
      return null;
    }

    return _ChangedSpan(before: changedBefore, after: changedAfter);
  }

  String _trimNoise(String text) {
    const trimChars = r'[\s,，.。:：;；!！?？()]+';
    return text
        .trim()
        .replaceFirst(RegExp('^$trimChars'), '')
        .replaceFirst(RegExp('$trimChars\$'), '')
        .trim();
  }

  bool _isValidCandidate(String original, String corrected) {
    if (original.isEmpty || corrected.isEmpty || original == corrected) {
      return false;
    }
    if (original.contains('\n') || corrected.contains('\n')) {
      return false;
    }
    if (original.length < 2 || corrected.length < 2) {
      return false;
    }
    if (original.length > 24 || corrected.length > 24) {
      return false;
    }

    final originalWords = original.split(RegExp(r'\s+')).length;
    final correctedWords = corrected.split(RegExp(r'\s+')).length;
    if (originalWords > 4 || correctedWords > 4) {
      return false;
    }

    final noisePattern = RegExp(r'^[\W_]+$');
    if (noisePattern.hasMatch(original) || noisePattern.hasMatch(corrected)) {
      return false;
    }

    final lengthGap = (original.length - corrected.length).abs();
    if (lengthGap > 6) {
      return false;
    }

    return true;
  }

  double _scoreCandidate({
    required String original,
    required String corrected,
    String? rawText,
  }) {
    var score = 0.60;

    final containsChinese = RegExp(r'[\u4e00-\u9fff]');
    final containsAsciiWord = RegExp(r'[A-Za-z0-9]');

    if (containsChinese.hasMatch(original) &&
        containsChinese.hasMatch(corrected)) {
      score += 0.12;
    }
    if (containsAsciiWord.hasMatch(original) &&
        containsAsciiWord.hasMatch(corrected)) {
      score += 0.08;
    }
    if ((rawText ?? '').contains(original)) {
      score += 0.08;
    }
    if ((original.length - corrected.length).abs() <= 2) {
      score += 0.05;
    }
    if (original.contains(' ') || corrected.contains(' ')) {
      score -= 0.05;
    }
    if (original.length > 12 || corrected.length > 12) {
      score -= 0.08;
    }

    return score.clamp(0.0, 1.0);
  }
}

class _ChangedSpan {
  final String before;
  final String after;

  const _ChangedSpan({required this.before, required this.after});
}
