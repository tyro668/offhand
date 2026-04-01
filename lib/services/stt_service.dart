import '../models/provider_config.dart';
import '../models/stt_request_context.dart';
import 'stt_providers/stt_provider.dart';
import 'stt_providers/openai_stt_provider.dart';
import 'stt_providers/zai_stt_provider.dart';
import 'stt_providers/aliyun_stt_provider.dart';
import 'stt_providers/gemini_stt_provider.dart';
import 'stt_providers/sense_voice_stt_provider.dart';

// Re-export types for backward compatibility
export 'stt_providers/stt_provider.dart'
    show SttConnectionCheckResult, SttException;

/// STT 服务路由器。
///
/// 根据 [SttProviderConfig] 自动选择对应厂商的 [SttProvider] 实现，
/// 将 transcribe / checkAvailability 委托给具体 Provider。
///
/// 调用方式不变：`SttService(config).transcribe(audioPath)`
class SttService {
  final SttProviderConfig config;

  SttService(this.config);

  /// 根据 config 路由到对应的 SttProvider 实现。
  SttProvider _resolveProvider() {
    // 本地 sherpa-onnx / SenseVoice FFI
    if (config.type == SttProviderType.senseVoice) {
      return SenseVoiceSttProvider(config);
    }

    final baseUrl = config.baseUrl.trim().toLowerCase();

    // Google Gemini
    if (baseUrl.contains('generativelanguage.googleapis.com')) {
      return GeminiSttProvider(config);
    }

    // Aliyun DashScope
    if (baseUrl.contains('dashscope.aliyuncs.com') ||
        baseUrl.contains('dashscope-intl.aliyuncs.com') ||
        baseUrl.contains('dashscope-us.aliyuncs.com')) {
      return AliyunSttProvider(config);
    }

    // Z.AI（智谱）
    if (baseUrl.contains('open.bigmodel.cn')) {
      return ZaiSttProvider(config);
    }

    // OpenAI 及其他兼容服务（兜底）
    return OpenAiSttProvider(config);
  }

  /// 将音频文件转写为文本。
  Future<String> transcribe(String audioPath, {SttRequestContext? context}) {
    return _resolveProvider().transcribe(audioPath, context: context);
  }

  /// 检查服务是否可用（简单版本）。
  Future<bool> checkAvailability() async {
    final result = await checkAvailabilityDetailed();
    return result.ok;
  }

  /// 检查服务是否可用（详细版本，返回错误信息）。
  Future<SttConnectionCheckResult> checkAvailabilityDetailed() {
    return _resolveProvider().checkAvailabilityDetailed();
  }
}
