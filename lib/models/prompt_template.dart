import 'package:uuid/uuid.dart';

class BuiltinPromptTemplateDef {
  final String id;
  final String name;
  final String summary;
  final String assetPath;

  const BuiltinPromptTemplateDef({
    required this.id,
    required this.name,
    required this.summary,
    required this.assetPath,
  });
}

/// A reusable prompt template for AI text enhancement.
class PromptTemplate {
  static const String defaultBuiltinId = 'builtin_default';

  static const List<BuiltinPromptTemplateDef> builtinDefinitions = [
    BuiltinPromptTemplateDef(
      id: defaultBuiltinId,
      name: '默认提示词',
      summary: '通用文本规整与可读性优化',
      assetPath: 'assets/prompts/default_prompt.md',
    ),
    BuiltinPromptTemplateDef(
      id: 'builtin_punctuation',
      name: '标点修正',
      summary: '仅修正断句与标点，不改原意',
      assetPath: 'assets/prompts/template_punctuation.md',
    ),
    BuiltinPromptTemplateDef(
      id: 'builtin_formal',
      name: '正式文书',
      summary: '将口语文本调整为正式书面语',
      assetPath: 'assets/prompts/template_formal.md',
    ),
    BuiltinPromptTemplateDef(
      id: 'builtin_colloquial',
      name: '口语化保留',
      summary: '轻度纠错并保留自然口语风格',
      assetPath: 'assets/prompts/template_colloquial.md',
    ),
    BuiltinPromptTemplateDef(
      id: 'builtin_translate_en',
      name: '翻译为英文',
      summary: '将输入翻译为自然流畅英文',
      assetPath: 'assets/prompts/template_translate_en.md',
    ),
  ];

  final String id;
  final String name;
  final String summary;
  final String content;
  final bool isBuiltin;
  final DateTime createdAt;

  const PromptTemplate({
    required this.id,
    required this.name,
    required this.summary,
    required this.content,
    this.isBuiltin = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'summary': summary,
    'content': content,
    'isBuiltin': isBuiltin,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PromptTemplate.fromJson(Map<String, dynamic> json) => PromptTemplate(
    id: json['id'] as String,
    name: json['name'] as String,
    summary: (json['summary'] as String?)?.trim().isNotEmpty == true
        ? json['summary'] as String
        : defaultSummaryFromContent((json['content'] as String?) ?? ''),
    content: json['content'] as String,
    isBuiltin: json['isBuiltin'] as bool? ?? false,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  PromptTemplate copyWith({String? name, String? summary, String? content}) =>
      PromptTemplate(
        id: id,
        name: name ?? this.name,
        summary: summary ?? this.summary,
        content: content ?? this.content,
        isBuiltin: isBuiltin,
        createdAt: createdAt,
      );

  static String defaultSummaryFromContent(String content) {
    final line = content
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^\s+|\s+$'), '');
    if (line.isEmpty) return 'Custom Template';
    return line.length > 24 ? '${line.substring(0, 24)}…' : line;
  }

  /// Create a new user template.
  static PromptTemplate create({
    required String name,
    required String content,
    String? summary,
  }) => PromptTemplate(
    id: const Uuid().v4(),
    name: name,
    summary: (summary?.trim().isNotEmpty == true)
        ? summary!.trim()
        : defaultSummaryFromContent(content),
    content: content,
    isBuiltin: false,
    createdAt: DateTime.now(),
  );
}
