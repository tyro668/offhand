import 'app_localizations.dart';

extension MemorySourceLocalizations on AppLocalizations {
  String memorySourceDisplayName(String source) {
    switch (_normalizeMemorySource(source)) {
      case 'manual':
        return memorySourceManual;
      case 'history_edit':
        return memorySourceHistoryEdit;
      case 'pending':
        return memorySourcePending;
      case 'session':
        return memorySourceSession;
      case 'session_glossary':
        return memorySourceSessionGlossary;
      case 'markdown':
        return memorySourceMarkdown;
      case 'markdown_document':
        return memorySourceMarkdownDocument;
      case 'markdown_import':
        return memorySourceMarkdownImport;
      case 'entity_memory':
        return memorySourceEntityMemory;
      case 'prompt_trace':
        return memorySourcePromptTrace;
      case 'correction_log':
        return memorySourceCorrectionLog;
      case 'dictionary_accept':
        return memorySourceDictionaryAccept;
      case 'dictionary_reject':
        return memorySourceDictionaryReject;
      case 'entity_learning':
        return memorySourceEntityLearning;
      case 'realtime':
        return memorySourceRealtime;
      case 'retrospective':
        return memorySourceRetrospective;
      case 'system':
        return memorySourceSystem;
    }
    return source.trim();
  }
}

String _normalizeMemorySource(String source) {
  final trimmed = source.trim();
  return switch (trimmed) {
    'historyEdit' => 'history_edit',
    'markdownImport' => 'markdown_import',
    _ => trimmed.replaceAll('-', '_').toLowerCase(),
  };
}
