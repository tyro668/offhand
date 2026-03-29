class TermPromptBundle {
  final String sttPrompt;
  final List<String> preferredTerms;
  final List<String> preserveTerms;
  final List<String> correctionReferences;
  final String entityCorrectionSection;
  final String entityRelationSection;

  const TermPromptBundle({
    this.sttPrompt = '',
    this.preferredTerms = const [],
    this.preserveTerms = const [],
    this.correctionReferences = const [],
    this.entityCorrectionSection = '',
    this.entityRelationSection = '',
  });

  bool get hasPrompt => sttPrompt.trim().isNotEmpty;
}
