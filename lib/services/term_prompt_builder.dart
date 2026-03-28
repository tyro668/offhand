import '../models/dictionary_entry.dart';
import '../models/term_context_entry.dart';
import '../models/term_prompt_bundle.dart';
import '../models/transcription.dart';
import 'session_glossary.dart';
import 'term_recall_service.dart';

class TermPromptBuilder {
  final TermRecallService recallService;

  const TermPromptBuilder({
    this.recallService = const TermRecallService(),
  });

  TermPromptBundle build({
    required String scene,
    required String currentText,
    required List<Transcription> history,
    required List<DictionaryEntry> dictionaryEntries,
    required SessionGlossary sessionGlossary,
    List<TermContextEntry> termContextEntries = const [],
    int maxTerms = TermRecallService.defaultMaxTerms,
  }) {
    final contextDocuments = _selectContextDocuments(termContextEntries);
    final preferredTerms = recallService.recallPreferredTerms(
      currentText: currentText,
      history: history,
      dictionaryEntries: dictionaryEntries,
      sessionGlossary: sessionGlossary,
      termContextEntries: termContextEntries,
      maxTerms: maxTerms,
    );

    if (preferredTerms.isEmpty && contextDocuments.isEmpty) {
      return const TermPromptBundle();
    }

    final preserveTerms = preferredTerms.toList(growable: false);
    final correctionReferences = _buildCorrectionReferences(
      dictionaryEntries,
      sessionGlossary,
    );

    final prompt = StringBuffer()
      ..writeln('请将这段音频准确转写为纯文本，仅返回转写结果。')
      ..writeln('当前场景：$scene。');
    if (preferredTerms.isNotEmpty) {
      prompt.writeln('优先识别并保持以下术语写法：');
      for (final term in preferredTerms) {
        prompt.writeln('- $term');
      }
      prompt.writeln('若听到相近发音，优先输出上述写法。');
    }
    if (contextDocuments.isNotEmpty) {
      prompt.writeln('参考以下上下文：');
      for (final entry in contextDocuments) {
        prompt.writeln('[${entry.displayTitle}]');
        prompt.writeln(_truncateContext(entry.content ?? ''));
      }
    }

    return TermPromptBundle(
      sttPrompt: prompt.toString().trim(),
      preferredTerms: preferredTerms,
      preserveTerms: preserveTerms,
      correctionReferences: correctionReferences,
    );
  }

  List<TermContextEntry> _selectContextDocuments(
    List<TermContextEntry> termContextEntries,
  ) {
    return termContextEntries
        .where((e) => e.enabled && e.isDocumentContext)
        .take(3)
        .toList(growable: false);
  }

  String _truncateContext(String content) {
    final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 1200) return normalized;
    return '${normalized.substring(0, 1200)}...';
  }

  List<String> _buildCorrectionReferences(
    List<DictionaryEntry> dictionaryEntries,
    SessionGlossary sessionGlossary,
  ) {
    final refs = <String>{};
    for (final pin in sessionGlossary.strongEntries.values) {
      if (pin.original.trim().isNotEmpty && pin.corrected.trim().isNotEmpty) {
        refs.add('${pin.original}->${pin.corrected}');
      }
    }
    for (final entry in dictionaryEntries.where((e) => e.enabled)) {
      final original = entry.original.trim();
      final corrected = (entry.corrected ?? '').trim();
      if (entry.type == DictionaryEntryType.correction &&
          original.isNotEmpty &&
          corrected.isNotEmpty) {
        refs.add('$original->$corrected');
      }
    }
    return refs.toList(growable: false);
  }
}
