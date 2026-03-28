import '../models/markdown_term_import_result.dart';
import '../models/term_context_entry.dart';

class MarkdownTermImportService {
  const MarkdownTermImportService();

  MarkdownTermImportResult parse(
    String markdown, {
    required String fileName,
  }) {
    final content = _normalizeMarkdown(markdown);
    if (content.isEmpty) {
      return const MarkdownTermImportResult(
        fileName: '',
        warnings: ['Markdown 内容为空，未导入上下文'],
      ).copyWithFileName(fileName);
    }

    return MarkdownTermImportResult(
      fileName: fileName,
      contextEntries: [
        TermContextEntry.create(
          term: fileName,
          canonical: fileName,
          content: content,
          sourceName: fileName,
          sourceType: 'markdown_document',
          entryType: TermContextEntryType.reference,
          confidence: 1,
        ),
      ],
    );
  }

  String _normalizeMarkdown(String markdown) {
    return markdown
        .replaceFirst(RegExp(r'^---[\s\S]*?---\s*', multiLine: false), '')
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
