import 'term_context_entry.dart';

class MarkdownTermImportResult {
  final String fileName;
  final List<TermContextEntry> contextEntries;
  final List<TermContextEntry> promotableCorrections;
  final List<TermContextEntry> promotablePreserves;
  final List<TermContextEntry> referenceOnlyTerms;
  final List<String> warnings;
  final int skippedItems;

  const MarkdownTermImportResult({
    required this.fileName,
    this.contextEntries = const [],
    this.promotableCorrections = const [],
    this.promotablePreserves = const [],
    this.referenceOnlyTerms = const [],
    this.warnings = const [],
    this.skippedItems = 0,
  });

  int get totalImportedCount =>
      contextEntries.length +
      promotableCorrections.length +
      promotablePreserves.length +
      referenceOnlyTerms.length;

  MarkdownTermImportResult copyWithFileName(String fileName) {
    return MarkdownTermImportResult(
      fileName: fileName,
      contextEntries: contextEntries,
      promotableCorrections: promotableCorrections,
      promotablePreserves: promotablePreserves,
      referenceOnlyTerms: referenceOnlyTerms,
      warnings: warnings,
      skippedItems: skippedItems,
    );
  }
}
