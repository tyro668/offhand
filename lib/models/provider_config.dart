enum SttProviderType { cloud, senseVoice }

/// 激活模式
enum ActivationMode { tapToTalk, pushToTalk }

/// 模型信息
class SttModel {
  final String id;
  final String description;

  const SttModel({required this.id, required this.description});

  factory SttModel.fromJson(Map<String, dynamic> json) =>
      SttModel(id: json['id'] ?? '', description: json['description'] ?? '');
}

class SttProviderConfig {
  final SttProviderType type;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final List<SttModel> availableModels;
  final String? apiKeyUrl;

  const SttProviderConfig({
    required this.type,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.availableModels = const [],
    this.apiKeyUrl,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
  };

  factory SttProviderConfig.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'];
    final SttProviderType type;
    if (rawType is String) {
      type = _parseProviderType(rawType);
    } else if (rawType is int) {
      switch (rawType) {
        case 1:
        case 2:
        case 3:
          type = SttProviderType.senseVoice;
          break;
        case 0:
        default:
          type = SttProviderType.cloud;
          break;
      }
    } else {
      type = SttProviderType.cloud;
    }
    return SttProviderConfig(
      type: type,
      name: json['name'],
      baseUrl: json['baseUrl'],
      apiKey: json['apiKey'],
      model: json['model'],
    );
  }

  SttProviderConfig copyWith({
    SttProviderType? type,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    List<SttModel>? availableModels,
    String? apiKeyUrl,
  }) => SttProviderConfig(
    type: type ?? this.type,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    availableModels: availableModels ?? this.availableModels,
    apiKeyUrl: apiKeyUrl ?? this.apiKeyUrl,
  );

  /// 预设的云端服务商 (fallback)
  static const fallbackPresets = [
    SttProviderConfig(
      type: SttProviderType.cloud,
      name: 'Z.ai',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      apiKey: '',
      model: 'GLM-ASR-2512',
      apiKeyUrl: 'https://open.bigmodel.cn/usercenter/apikeys',
      availableModels: [
        SttModel(
          id: 'GLM-ASR-2512',
          description: 'Z.ai speech-to-text (supports wav/mp3, <=30s)',
        ),
      ],
    ),
    SttProviderConfig(
      type: SttProviderType.cloud,
      name: 'Aliyun',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      apiKey: '',
      model: 'qwen3-asr-flash',
      availableModels: [
        SttModel(
          id: 'qwen3-asr-flash',
          description: '千问3-ASR-Flash (OpenAI 兼容 + DashScope 同步)',
        ),
      ],
    ),
    SttProviderConfig(
      type: SttProviderType.cloud,
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      apiKey: '',
      model: 'gpt-4o-transcribe',
      apiKeyUrl: 'https://platform.openai.com/api-keys',
      availableModels: [
        SttModel(id: 'gpt-4o-transcribe', description: 'GPT-4o Transcribe'),
        SttModel(
          id: 'gpt-4o-mini-transcribe',
          description: 'GPT-4o mini Transcribe',
        ),
        SttModel(id: 'whisper-1', description: 'Whisper-1'),
      ],
    ),
    SttProviderConfig(
      type: SttProviderType.cloud,
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      apiKey: '',
      model: 'gemini-2.5-flash',
      apiKeyUrl: 'https://aistudio.google.com/app/apikey',
      availableModels: [
        SttModel(
          id: 'gemini-2.5-pro',
          description: 'Gemini 2.5 Pro (OpenAI 兼容)',
        ),
        SttModel(
          id: 'gemini-2.5-flash',
          description: 'Gemini 2.5 Flash (OpenAI 兼容)',
        ),
        SttModel(
          id: 'gemini-2.5-flash-lite',
          description: 'Gemini 2.5 Flash-Lite (OpenAI 兼容)',
        ),
      ],
    ),
    SttProviderConfig(
      type: SttProviderType.senseVoice,
      name: 'Local Model',
      baseUrl: '',
      apiKey: '',
      model: 'sense-voice-zh-en',
      availableModels: [
        SttModel(
          id: 'sense-voice-zh-en',
          description: 'SenseVoice 多语种 INT8 (~250MB) - 中/英/日/韩/粤',
        ),
      ],
    ),
  ];

  /// 根据模型文件名判断是否为 SenseVoice 模型
  static bool isSenseVoiceModel(String modelId) {
    return modelId.contains('sense-voice');
  }

  static List<SttProviderConfig> fromPresetJsonList(List<dynamic> items) {
    return items
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => SttProviderConfig(
            type: _parseProviderType(item['type']?.toString()),
            name: item['name'] ?? '',
            baseUrl: item['baseUrl'] ?? '',
            apiKey: '',
            model: item['defaultModel'] ?? '',
            apiKeyUrl: item['apiKeyUrl'],
            availableModels: (item['models'] as List<dynamic>? ?? [])
                .whereType<Map<String, dynamic>>()
                .map(SttModel.fromJson)
                .toList(),
          ),
        )
        .where(
          (preset) =>
              preset.name.isNotEmpty &&
              (preset.baseUrl.isNotEmpty ||
                  preset.type == SttProviderType.senseVoice) &&
              preset.model.isNotEmpty,
        )
        .toList();
  }

  static SttProviderType _parseProviderType(String? value) {
    switch (value) {
      case 'whisperCpp':
      case 'senseVoice':
      case 'localOnnx':
        return SttProviderType.senseVoice;
      case 'whisper': // 兼容旧数据，降级为 cloud
      case 'cloud':
      default:
        return SttProviderType.cloud;
    }
  }
}
