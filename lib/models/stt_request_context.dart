class SttRequestContext {
  final String scene;
  final String? prompt;
  final List<String> preferredTerms;
  final List<String> preserveTerms;

  const SttRequestContext({
    required this.scene,
    this.prompt,
    this.preferredTerms = const [],
    this.preserveTerms = const [],
  });

  bool get hasPrompt => (prompt ?? '').trim().isNotEmpty;
}
