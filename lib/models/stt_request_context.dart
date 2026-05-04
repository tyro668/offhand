class SttRequestContext {
  final String scene;
  final String? prompt;
  final List<String> preferredTerms;
  final List<String> preserveTerms;
  final String? promptTraceId;
  final List<String> includedMemoryItemIds;
  final List<String> includedWeakMemoryItemIds;
  final String? memorySnapshotVersion;

  const SttRequestContext({
    required this.scene,
    this.prompt,
    this.preferredTerms = const [],
    this.preserveTerms = const [],
    this.promptTraceId,
    this.includedMemoryItemIds = const [],
    this.includedWeakMemoryItemIds = const [],
    this.memorySnapshotVersion,
  });

  bool get hasPrompt => (prompt ?? '').trim().isNotEmpty;
}
