class AiVendorPreset {
  final String name;
  final String baseUrl;
  final List<AiModel> models;
  final String? defaultModelIdOverride;

  const AiVendorPreset({
    required this.name,
    required this.baseUrl,
    required this.models,
    this.defaultModelIdOverride,
  });

  String get defaultModelId => defaultModelIdOverride ?? models.first.id;

  static const fallbackPresets = [
    AiVendorPreset(
      name: 'Z.AI',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      models: [
        AiModel(id: 'GLM-4.7', description: 'GLM-4.7'),
        AiModel(id: 'GLM-4.7-FlashX', description: 'GLM-4.7-FlashX'),
      ],
      defaultModelIdOverride: 'GLM-4.7-FlashX',
    ),
    AiVendorPreset(
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      models: [AiModel(id: 'deepseek-chat', description: 'DeepSeek 默认模型')],
    ),
    AiVendorPreset(
      name: 'Aliyun',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      models: [
        AiModel(id: 'qwen-plus', description: '千问 Plus'),
        AiModel(id: 'qwen-max', description: '千问 Max'),
        AiModel(id: 'qwen-turbo', description: '千问 Turbo'),
      ],
    ),
    AiVendorPreset(
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      models: [
        AiModel(id: 'gpt-5', description: 'GPT-5'),
        AiModel(id: 'gpt-5-mini', description: 'GPT-5 mini'),
        AiModel(id: 'gpt-5-nano', description: 'GPT-5 nano'),
        AiModel(id: 'gpt-4.1', description: 'GPT-4.1'),
      ],
      defaultModelIdOverride: 'gpt-5-mini',
    ),
    AiVendorPreset(
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      models: [
        AiModel(id: 'gemini-3.0-pro', description: 'Gemini 3.0 Pro'),
        AiModel(id: 'gemini-3.0-flash', description: 'Gemini 3.0 Flash'),
        AiModel(
          id: 'gemini-3.0-flash-lite',
          description: 'Gemini 3.0 Flash-Lite',
        ),
        AiModel(id: 'gemini-2.5-pro', description: 'Gemini 2.5 Pro'),
        AiModel(id: 'gemini-2.5-flash', description: 'Gemini 2.5 Flash'),
        AiModel(
          id: 'gemini-2.5-flash-lite',
          description: 'Gemini 2.5 Flash-Lite',
        ),
        AiModel(id: 'gemini-2.0-flash', description: 'Gemini 2.0 Flash'),
      ],
      defaultModelIdOverride: 'gemini-3.0-pro',
    ),
  ];

  static List<AiVendorPreset> fromPresetJsonList(List<dynamic> items) {
    return items
        .whereType<Map<String, dynamic>>()
        .map((item) {
          return AiVendorPreset(
            name: item['name'] ?? '',
            baseUrl: item['baseUrl'] ?? '',
            models: (item['models'] as List<dynamic>? ?? [])
                .whereType<Map<String, dynamic>>()
                .map(AiModel.fromJson)
                .toList(),
            defaultModelIdOverride: _resolveDefaultModelId(
              item['defaultModel']?.toString(),
              item['models'],
            ),
          );
        })
        .where(
          (preset) =>
              preset.name.isNotEmpty &&
              preset.baseUrl.isNotEmpty &&
              preset.models.isNotEmpty,
        )
        .toList();
  }

  static String? _resolveDefaultModelId(
    String? defaultModel,
    dynamic rawModels,
  ) {
    if (defaultModel == null || defaultModel.isEmpty) return null;
    if (rawModels is List) {
      final exists = rawModels.whereType<Map<String, dynamic>>().any(
        (model) => model['id'] == defaultModel,
      );
      return exists ? defaultModel : null;
    }
    return null;
  }
}

class AiModel {
  final String id;
  final String description;

  const AiModel({required this.id, required this.description});

  factory AiModel.fromJson(Map<String, dynamic> json) =>
      AiModel(id: json['id'] ?? '', description: json['description'] ?? '');
}
