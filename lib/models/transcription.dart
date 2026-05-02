class Transcription {
  final String id;
  final String text;
  final String? rawText;
  final DateTime createdAt;
  final Duration duration;
  final Duration? llmProcessingDuration;
  final int? llmInputTokens;
  final int? llmOutputTokens;
  final String provider;
  final String model;
  final String providerConfigJson;

  Transcription({
    required this.id,
    required this.text,
    this.rawText,
    required this.createdAt,
    required this.duration,
    this.llmProcessingDuration,
    this.llmInputTokens,
    this.llmOutputTokens,
    required this.provider,
    required this.model,
    required this.providerConfigJson,
  });

  /// 是否启用了 AI 增强（rawText 被记录）
  bool get hasRawText => rawText != null && rawText!.isNotEmpty;

  /// AI 增强是否实际改变了文本
  bool get isEnhanced =>
      rawText != null && rawText!.isNotEmpty && rawText != text;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'rawText': rawText,
    'createdAt': createdAt.toIso8601String(),
    'duration': duration.inMilliseconds,
    'llmProcessingDuration': llmProcessingDuration?.inMilliseconds,
    'llmInputTokens': llmInputTokens,
    'llmOutputTokens': llmOutputTokens,
    'provider': provider,
    'model': model,
    'providerConfigJson': providerConfigJson,
  };

  Map<String, dynamic> toDb() => {
    'id': id,
    'text': text,
    'raw_text': rawText,
    'created_at': createdAt.toIso8601String(),
    'duration_ms': duration.inMilliseconds,
    'llm_processing_duration_ms': llmProcessingDuration?.inMilliseconds,
    'llm_input_tokens': llmInputTokens,
    'llm_output_tokens': llmOutputTokens,
    'provider': provider,
    'model': model,
    'provider_config': providerConfigJson,
  };

  factory Transcription.fromJson(Map<String, dynamic> json) => Transcription(
    id: json['id'],
    text: json['text'],
    rawText: json['rawText'],
    createdAt: DateTime.parse(json['createdAt']),
    duration: Duration(milliseconds: json['duration']),
    llmProcessingDuration: json['llmProcessingDuration'] == null
        ? null
        : Duration(milliseconds: json['llmProcessingDuration']),
    llmInputTokens: json['llmInputTokens'] as int?,
    llmOutputTokens: json['llmOutputTokens'] as int?,
    provider: json['provider'],
    model: json['model'] ?? '',
    providerConfigJson: json['providerConfigJson'] ?? '{}',
  );

  factory Transcription.fromDb(Map<String, dynamic> row) => Transcription(
    id: row['id'] as String,
    text: row['text'] as String,
    rawText: row['raw_text'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    duration: Duration(milliseconds: row['duration_ms'] as int),
    llmProcessingDuration: row['llm_processing_duration_ms'] == null
        ? null
        : Duration(milliseconds: row['llm_processing_duration_ms'] as int),
    llmInputTokens: row['llm_input_tokens'] as int?,
    llmOutputTokens: row['llm_output_tokens'] as int?,
    provider: row['provider'] as String,
    model: (row['model'] as String?) ?? '',
    providerConfigJson: (row['provider_config'] as String?) ?? '{}',
  );
}
