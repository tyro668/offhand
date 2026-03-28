class TermPromptBundle {
  final String sttPrompt;
  final List<String> preferredTerms;
  final List<String> preserveTerms;
  final List<String> correctionReferences;

  const TermPromptBundle({
    this.sttPrompt = '',
    this.preferredTerms = const [],
    this.preserveTerms = const [],
    this.correctionReferences = const [],
  });

  bool get hasPrompt => sttPrompt.trim().isNotEmpty;
}
