import '../models/ai_enhance_config.dart';
import '../models/correction_change_log.dart';
import '../models/dictionary_entry.dart';
import 'ai_enhance_service.dart';
import 'correction_change_log_service.dart';
import 'correction_context.dart';
import 'log_service.dart';
import 'pinyin_matcher.dart';
import 'correction_stats_service.dart';
import 'session_glossary.dart';
import 'token_stats_service.dart';

/// 纠错结果
class CorrectionResult {
  /// 纠错后的文本
  final String text;

  /// 是否实际调用了 LLM（false 表示跳过纠错直接返回原文）
  final bool llmInvoked;

  /// LLM 消耗的 token 数量
  final int promptTokens;
  final int completionTokens;

  const CorrectionResult({
    required this.text,
    this.llmInvoked = false,
    this.promptTokens = 0,
    this.completionTokens = 0,
  });

  int get totalTokens => promptTokens + completionTokens;
}

/// 语音输入纠错服务。
///
/// 核心流程：
/// 1. 对 ASR 原始文本用 [PinyinMatcher] 检索匹配的词典条目
/// 2. 若无匹配 → 跳过 LLM，Token 消耗 = 0
/// 3. 若有匹配 → 构建 #R/#I/#C 符号化协议，调用 LLM 进行纠错
/// 4. 更新 [CorrectionContext] 上下文窗口
class CorrectionService {
  final PinyinMatcher matcher;
  final CorrectionContext context;
  final AiEnhanceConfig aiConfig;
  final String correctionPrompt;
  final int maxReferenceEntries;
  final double minCandidateScore;
  final SessionGlossary? sessionGlossary;

  CorrectionService({
    required this.matcher,
    required this.context,
    required this.aiConfig,
    required this.correctionPrompt,
    this.maxReferenceEntries = 15,
    this.minCandidateScore = 0.30,
    this.sessionGlossary,
  });

  /// 对 ASR 原始文本执行纠错。
  ///
  /// 若词典中无匹配条目，直接返回原文不调用 LLM。
  Future<CorrectionResult> correct(String rawSttText) async {
    if (rawSttText.trim().isEmpty) {
      return CorrectionResult(text: rawSttText);
    }

    var matchesCount = 0;
    var selectedCount = 0;
    var referenceChars = 0;
    var fallbackText = rawSttText;

    try {
      // 1. 拼音模糊匹配
      final matchHits = matcher.findMatchHits(rawSttText);
      matchesCount = matchHits.length;

      if (matchHits.isEmpty) {
        // 无匹配 → 跳过 LLM，直接输出
        await LogService.info(
          'CORRECTION',
          'no dictionary matches, skipping LLM',
        );
        await _recordStatsSafely(
          matchesCount: 0,
          selectedCount: 0,
          referenceChars: 0,
          llmInvoked: false,
        );
        context.addSegment(rawSttText);
        return CorrectionResult(text: rawSttText);
      }

      await LogService.info(
        'CORRECTION',
        'found ${matchHits.length} dictionary hit spans',
      );

      final selectedHits = _selectHitsForReference(rawSttText, matchHits);
      selectedCount = selectedHits.length;
      if (selectedHits.isEmpty) {
        await LogService.info(
          'CORRECTION',
          'all matches filtered out locally, skipping LLM',
        );
        await _recordStatsSafely(
          matchesCount: matchesCount,
          selectedCount: 0,
          referenceChars: 0,
          llmInvoked: false,
        );
        context.addSegment(rawSttText);
        return CorrectionResult(text: rawSttText);
      }

      fallbackText = _normalizeMatchedTermsFromHits(rawSttText, selectedHits);

      // 2. 构建 #R 引用表
      final referenceStr = _buildReferenceStringFromHits(selectedHits);
      referenceChars = referenceStr.length;

      await LogService.info(
        'CORRECTION',
        'reference selected ${selectedHits.length}/${matchHits.length}, '
            'referenceChars=${referenceStr.length}',
      );

      // 3. 构建完整 prompt 消息（追加 SessionGlossary 强锚定）
      var finalReference = referenceStr;
      if (sessionGlossary != null && sessionGlossary!.hasStrongEntries) {
        final glossaryRef = sessionGlossary!.buildReferenceAppend();
        if (glossaryRef.isNotEmpty) {
          finalReference = '$referenceStr|$glossaryRef';
        }
      }
      final userMessage = _buildUserMessage(
        reference: finalReference,
        input: rawSttText,
        contextStr: context.getContextString(),
      );

      // 4. 调用 LLM
      final correctionConfig = aiConfig.copyWith(prompt: correctionPrompt);
      final enhancer = AiEnhanceService(correctionConfig);

      final result = await enhancer.enhance(userMessage);
      var correctedText = result.text.trim();

      // 安全校验：若 LLM 返回空，退回原文
      if (correctedText.isEmpty) {
        correctedText = fallbackText;
      }

      correctedText = _normalizeMatchedTermsFromHits(
        correctedText,
        selectedHits,
      );

      // 5. 记录 Token 消耗
      if (result.totalTokens > 0) {
        try {
          await TokenStatsService.instance.addTokens(
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
          );
        } catch (_) {}
      }

      await _recordStatsSafely(
        matchesCount: matchesCount,
        selectedCount: selectedCount,
        referenceChars: referenceChars,
        llmInvoked: true,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
      );

      // 6. 更新上下文
      context.addSegment(correctedText);

      // 7. 自动提取新的同音字映射到 SessionGlossary
      if (sessionGlossary != null && correctedText != rawSttText) {
        sessionGlossary!.extractAndPin(rawSttText, correctedText);
      }

      await LogService.info(
        'CORRECTION',
        'corrected: ${rawSttText.length} → ${correctedText.length} chars, '
            'tokens: ${result.totalTokens}',
      );

      if (correctedText != rawSttText) {
        try {
          await CorrectionChangeLogService.instance.recordChange(
            source: 'realtime',
            inputText: rawSttText,
            outputText: correctedText,
            terms: _buildTermPairsFromHits(selectedHits),
          );
        } catch (_) {}
      }

      return CorrectionResult(
        text: correctedText,
        llmInvoked: true,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
      );
    } catch (e) {
      await LogService.error('CORRECTION', 'correction failed: $e');
      await _recordStatsSafely(
        matchesCount: matchesCount,
        selectedCount: selectedCount,
        referenceChars: referenceChars,
        llmInvoked: false,
      );
      // 纠错失败不影响主流程，退回原文
      context.addSegment(fallbackText);
      return CorrectionResult(text: fallbackText);
    }
  }

  /// 终态回溯：对整段文本（已经过逐句纠错）再做一次全段复核。
  ///
  /// 与 [correct] 的区别：
  /// - 不更新 [CorrectionContext] 上下文窗口（避免重复污染）
  /// - 可传入自定义上下文（如前一段落文本）
  /// - 用于段落结束时的二次校验
  Future<CorrectionResult> correctParagraph(
    String paragraphText, {
    String previousParagraph = '',
  }) async {
    if (paragraphText.trim().isEmpty) {
      return CorrectionResult(text: paragraphText);
    }

    try {
      final matchHits = matcher.findMatchHits(paragraphText);

      if (matchHits.isEmpty) {
        await LogService.info(
          'CORRECTION',
          'retrospective: no dictionary matches, skipping',
        );
        await _recordRetroSafely(llmInvoked: false, textChanged: false);
        return CorrectionResult(text: paragraphText);
      }

      final selectedHits = _selectHitsForReference(paragraphText, matchHits);
      if (selectedHits.isEmpty) {
        await LogService.info(
          'CORRECTION',
          'retrospective: all matches filtered, skipping',
        );
        await _recordRetroSafely(llmInvoked: false, textChanged: false);
        return CorrectionResult(text: paragraphText);
      }

      final fallbackText = _normalizeMatchedTermsFromHits(
        paragraphText,
        selectedHits,
      );

      final referenceStr = _buildReferenceStringFromHits(selectedHits);

      // 使用提供的前段文本作为上下文，若为空则用当前上下文窗口
      final contextStr = previousParagraph.isNotEmpty
          ? previousParagraph
          : context.getContextString();

      final userMessage = _buildUserMessage(
        reference: referenceStr,
        input: paragraphText,
        contextStr: contextStr,
      );

      final correctionConfig = aiConfig.copyWith(prompt: correctionPrompt);
      final enhancer = AiEnhanceService(correctionConfig);
      final result = await enhancer.enhance(userMessage);

      var correctedText = result.text.trim();
      if (correctedText.isEmpty) {
        correctedText = fallbackText;
      }

      correctedText = _normalizeMatchedTermsFromHits(
        correctedText,
        selectedHits,
      );

      if (result.totalTokens > 0) {
        try {
          await TokenStatsService.instance.addTokens(
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
          );
        } catch (_) {}
      }

      await LogService.info(
        'CORRECTION',
        'retrospective: ${paragraphText.length} → ${correctedText.length} chars, '
            'tokens: ${result.totalTokens}',
      );

      if (correctedText != paragraphText) {
        try {
          await CorrectionChangeLogService.instance.recordChange(
            source: 'retrospective',
            inputText: paragraphText,
            outputText: correctedText,
            terms: _buildTermPairsFromHits(selectedHits),
          );
        } catch (_) {}
      }

      await _recordRetroSafely(
        llmInvoked: true,
        textChanged: correctedText != paragraphText,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
      );

      return CorrectionResult(
        text: correctedText,
        llmInvoked: true,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
      );
    } catch (e) {
      await LogService.error(
        'CORRECTION',
        'retrospective correction failed: $e',
      );
      return CorrectionResult(text: paragraphText);
    }
  }

  /// 构建 #R 引用表字符串。
  ///
  /// 格式：`错词->正词|错词2->正词2`
  /// - correction 类型：`original->corrected`
  /// - preserve 类型：`original->original`（保持原样）
  String _buildReferenceStringFromHits(List<PinyinMatchHit> hits) {
    final parts = <String>[];
    final dedup = <String>{};
    for (final hit in hits) {
      final entry = hit.entry;
      if (entry.type == DictionaryEntryType.correction) {
        final target = _targetTextForEntry(entry);
        final source = hit.observedText.trim().isNotEmpty
            ? hit.observedText.trim()
            : entry.original;
        final forward = '$source->$target';
        if (dedup.add(forward)) {
          parts.add(forward);
        }

        final corrected = entry.corrected?.trim() ?? '';
        final original = entry.original.trim();
        if (_isChineseToLatinAlias(entry) && corrected.isNotEmpty) {
          if (_containsChinese(source) && source != original) {
            final observedToCanonical = '$source->$original';
            if (dedup.add(observedToCanonical)) {
              parts.add(observedToCanonical);
            }
          }
          final reverse = '$corrected->$original';
          if (dedup.add(reverse)) {
            parts.add(reverse);
          }
        }
      } else {
        // preserve 类型：告知 LLM 保持原样
        final source = hit.observedText.trim().isNotEmpty
            ? hit.observedText.trim()
            : entry.original.trim();
        if (source.isEmpty) continue;
        final keep = '$source->$source';
        if (dedup.add(keep)) {
          parts.add(keep);
        }
      }
    }
    return parts.join('|');
  }

  /// 构建用于纠错的 user message（#R/#I/#C 符号化协议）。
  String _buildUserMessage({
    required String reference,
    required String input,
    required String contextStr,
  }) {
    final buf = StringBuffer();
    buf.writeln('#R: $reference');
    if (contextStr.isNotEmpty) {
      buf.writeln('#C: $contextStr');
    }
    buf.writeln('#I: $input');
    return buf.toString().trim();
  }

  bool _containsChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }

  bool _isChineseToLatinAlias(DictionaryEntry entry) {
    final original = entry.original.trim();
    final corrected = entry.corrected?.trim() ?? '';
    return entry.type == DictionaryEntryType.correction &&
        corrected.isNotEmpty &&
        _containsChinese(original) &&
        !_containsChinese(corrected);
  }

  String _targetTextForEntry(DictionaryEntry entry) {
    if (entry.type != DictionaryEntryType.correction) {
      return entry.original;
    }
    final corrected = entry.corrected?.trim() ?? '';
    if (corrected.isEmpty) return entry.original;
    if (_isChineseToLatinAlias(entry)) {
      return entry.original;
    }
    return corrected;
  }

  String _normalizeMatchedTermsFromHits(
    String text,
    List<PinyinMatchHit> hits,
  ) {
    var output = text;
    for (final hit in hits) {
      final entry = hit.entry;
      final alias = entry.corrected?.trim() ?? '';
      final original = entry.original.trim();
      final observed = hit.observedText.trim();

      if (_isChineseToLatinAlias(entry)) {
        final target = original;
        if (alias.isEmpty || target.isEmpty) continue;

        if (observed.isNotEmpty &&
            observed != target &&
            _containsChinese(observed)) {
          output = output.replaceAll(observed, target);
        }

        output = output.replaceAll(
          RegExp(RegExp.escape(alias), caseSensitive: false),
          target,
        );

        final pinyin = PinyinMatcher.computePinyin(target);
        if (pinyin.isNotEmpty) {
          final syllables = pinyin
              .split(RegExp(r'\s+'))
              .where((s) => s.isNotEmpty)
              .toList(growable: false);
          if (syllables.isNotEmpty) {
            final pattern = RegExp(
              '\\b${syllables.map(RegExp.escape).join(r'[\\s_-]*')}\\b',
              caseSensitive: false,
            );
            output = output.replaceAll(pattern, target);
          }
        }
        continue;
      }

      // Also normalize latin/romanized aliases back to canonical Chinese
      // when the selected hit already proves they should collapse.
      if (entry.type == DictionaryEntryType.correction &&
          alias.isNotEmpty &&
          _containsChinese(alias) &&
          observed.isNotEmpty &&
          !_containsChinese(observed)) {
        output = output.replaceAll(
          RegExp(RegExp.escape(observed), caseSensitive: false),
          alias,
        );
        if (original.isNotEmpty && !_containsChinese(original)) {
          output = output.replaceAll(
            RegExp(RegExp.escape(original), caseSensitive: false),
            alias,
          );
        }
      }
    }
    return output;
  }

  List<PinyinMatchHit> _selectHitsForReference(
    String rawText,
    List<PinyinMatchHit> hits,
  ) {
    if (hits.isEmpty) return const [];
    final ranked = hits
        .map((hit) => _RankedHit(hit: hit, score: _scoreHit(rawText, hit)))
        .where((r) => r.score >= minCandidateScore)
        .toList();

    if (ranked.isEmpty) return const [];

    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final aLen = a.hit.observedText.length;
      final bLen = b.hit.observedText.length;
      final byLen = bLen.compareTo(aLen);
      if (byLen != 0) return byLen;
      return a.hit.entry.id.compareTo(b.hit.entry.id);
    });

    final result = <PinyinMatchHit>[];
    final seen = <String>{};
    for (final item in ranked) {
      final key = _referenceDedupKey(item.hit);
      if (!seen.add(key)) continue;
      result.add(item.hit);
      if (result.length >= maxReferenceEntries) break;
    }
    return result;
  }

  String _referenceDedupKey(PinyinMatchHit hit) {
    final entry = hit.entry;
    final target = _targetTextForEntry(entry);
    final source = hit.observedText.trim().isNotEmpty
        ? hit.observedText.trim()
        : entry.original;
    return '$source->$target';
  }

  double _scoreHit(String rawText, PinyinMatchHit hit) {
    final source = rawText.trim();
    if (source.isEmpty) return 0;

    final entry = hit.entry;
    final original = entry.original.trim();
    final corrected = (entry.corrected ?? '').trim();
    final observed = hit.observedText.trim();
    if (original.isEmpty && corrected.isEmpty) return 0;

    if (hit.matchType == PinyinMatchType.literal) {
      return 1;
    }

    var bestCharSimilarity = 0.0;
    if (observed.isNotEmpty && original.isNotEmpty) {
      final s = _normalizedSimilarity(observed, original);
      if (s > bestCharSimilarity) bestCharSimilarity = s;
    }
    if (observed.isNotEmpty && corrected.isNotEmpty) {
      final s = _normalizedSimilarity(observed, corrected);
      if (s > bestCharSimilarity) bestCharSimilarity = s;
    }

    var bestPinyinSimilarity = 0.0;
    if (observed.isNotEmpty &&
        original.isNotEmpty &&
        _containsChinese(observed) &&
        _containsChinese(original)) {
      final observedPinyin = PinyinMatcher.computePinyin(observed);
      final originalPinyin = PinyinMatcher.computePinyin(original);
      final s = _normalizedSimilarity(observedPinyin, originalPinyin);
      if (s > bestPinyinSimilarity) bestPinyinSimilarity = s;
    }
    if (observed.isNotEmpty &&
        corrected.isNotEmpty &&
        _containsChinese(observed) &&
        _containsChinese(corrected)) {
      final observedPinyin = PinyinMatcher.computePinyin(observed);
      final correctedPinyin = PinyinMatcher.computePinyin(corrected);
      final s = _normalizedSimilarity(observedPinyin, correctedPinyin);
      if (s > bestPinyinSimilarity) bestPinyinSimilarity = s;
    }
    if (observed.isNotEmpty &&
        entry.hasPinyinPattern &&
        _containsChinese(observed)) {
      final observedPinyin = PinyinMatcher.computePinyin(observed);
      final s = _normalizedSimilarity(observedPinyin, entry.pinyinNormalized);
      if (s > bestPinyinSimilarity) bestPinyinSimilarity = s;
    }

    final typeBonus = entry.type == DictionaryEntryType.correction ? 0.05 : 0.0;
    final patternBonus = entry.hasPinyinPattern ? 0.18 : 0.0;
    final matchTypeBonus = switch (hit.matchType) {
      PinyinMatchType.pinyinExact => 0.12,
      PinyinMatchType.pinyinFuzzy => 0.06,
      PinyinMatchType.literal => 0.18,
    };
    final combined =
        bestCharSimilarity * 0.55 +
        bestPinyinSimilarity * 0.45 +
        typeBonus +
        patternBonus +
        matchTypeBonus;
    return combined > 1.0 ? 1.0 : combined;
  }

  double _normalizedSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final distance = _levenshtein(a, b);
    final base = a.length > b.length ? a.length : b.length;
    if (base == 0) return 0;
    final sim = 1 - (distance / base);
    return sim < 0 ? 0 : sim;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var prev = List.generate(b.length + 1, (i) => i);
    var curr = List.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final deletion = prev[j] + 1;
        final insertion = curr[j - 1] + 1;
        final substitution = prev[j - 1] + cost;
        var value = deletion < insertion ? deletion : insertion;
        if (substitution < value) value = substitution;
        curr[j] = value;
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[b.length];
  }

  List<CorrectionTermPair> _buildTermPairsFromHits(List<PinyinMatchHit> hits) {
    final seen = <String>{};
    final pairs = <CorrectionTermPair>[];
    for (final hit in hits) {
      final original = hit.entry.original.trim();
      final corrected = (hit.entry.corrected ?? '').trim();
      final observed = hit.observedText.trim();
      if (original.isEmpty || corrected.isEmpty) continue;
      final key = '$observed|$original|$corrected';
      if (!seen.add(key)) continue;
      pairs.add(
        CorrectionTermPair(
          observed: observed,
          original: original,
          corrected: corrected,
        ),
      );
    }
    return pairs;
  }

  Future<void> _recordStatsSafely({
    required int matchesCount,
    required int selectedCount,
    required int referenceChars,
    required bool llmInvoked,
    int promptTokens = 0,
    int completionTokens = 0,
  }) async {
    try {
      await CorrectionStatsService.instance.recordCall(
        matchesCount: matchesCount,
        selectedCount: selectedCount,
        referenceChars: referenceChars,
        llmInvoked: llmInvoked,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      );
    } catch (_) {}
  }

  Future<void> _recordRetroSafely({
    required bool llmInvoked,
    required bool textChanged,
    int promptTokens = 0,
    int completionTokens = 0,
  }) async {
    try {
      await CorrectionStatsService.instance.recordRetroCall(
        llmInvoked: llmInvoked,
        textChanged: textChanged,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      );
    } catch (_) {}
  }
}

class _RankedHit {
  final PinyinMatchHit hit;
  final double score;

  const _RankedHit({required this.hit, required this.score});
}
