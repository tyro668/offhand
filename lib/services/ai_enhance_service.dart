import '../models/ai_enhance_config.dart';
import 'ai_providers/ai_provider.dart';
import 'ai_providers/openai_compatible_ai_provider.dart';
import 'ai_providers/openai_ai_provider.dart';
import 'ai_providers/zai_ai_provider.dart';
import 'ai_providers/deepseek_ai_provider.dart';
import 'ai_providers/aliyun_ai_provider.dart';
import 'ai_providers/gemini_ai_provider.dart';

// Re-export types for backward compatibility
export 'ai_providers/ai_provider.dart'
    show AiEnhanceResult, AiConnectionCheckResult, AiEnhanceException;

/// AI 增强服务路由器。
///
/// 根据 [AiEnhanceConfig] 自动选择对应厂商的 [AiProvider] 实现，
/// 将 enhance / enhanceStream / checkAvailability 委托给具体 Provider。
///
/// 调用方式不变：`AiEnhanceService(config).enhance(text)`
class AiEnhanceService {
  final AiEnhanceConfig config;

  AiEnhanceService(this.config);

  /// 根据 config 路由到对应的 AiProvider 实现。
  AiProvider _resolveProvider() {
    if (config.baseUrl.trim().isEmpty) {
      throw AiEnhanceException('本地文本模型已移除，请配置云端或 OpenAI 兼容文本模型');
    }

    final baseUrl = config.baseUrl.trim().toLowerCase();

    // Google Gemini
    if (baseUrl.contains('generativelanguage.googleapis.com')) {
      return GeminiAiProvider(config);
    }

    // Aliyun DashScope
    if (baseUrl.contains('dashscope.aliyuncs.com') ||
        baseUrl.contains('dashscope-intl.aliyuncs.com') ||
        baseUrl.contains('dashscope-us.aliyuncs.com')) {
      return AliyunAiProvider(config);
    }

    // DeepSeek
    if (baseUrl.contains('api.deepseek.com')) {
      return DeepSeekAiProvider(config);
    }

    // Z.AI（智谱）
    if (baseUrl.contains('open.bigmodel.cn')) {
      return ZaiAiProvider(config);
    }

    // OpenAI
    if (baseUrl.contains('api.openai.com')) {
      return OpenAiAiProvider(config);
    }

    // 兜底：自定义/未知厂商，使用通用 OpenAI 兼容协议
    return OpenAiCompatibleAiProvider(config);
  }

  /// 批量增强文本。
  Future<AiEnhanceResult> enhance(String text, {Duration? timeout}) {
    return _resolveProvider().enhance(text, timeout: timeout);
  }

  /// 构建一次文本增强请求的完整输入文本，用于按统一口径估算历史 token。
  ///
  /// 统计口径：system prompt + 实际传给模型的 user message（其中包含 source 文本）。
  String buildInputForTokenEstimate(String text) {
    final provider = _resolveProvider();
    return [
      provider.resolvePrompt(),
      provider.buildEnhanceUserMessage(text),
    ].join('\n\n');
  }

  /// 轻量 token 估算器：中文按单字计，英文/数字按约 4 字符一个 token 计。
  static int estimateTokenCount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;

    var tokens = 0;
    var asciiRunLength = 0;

    void flushAsciiRun() {
      if (asciiRunLength == 0) return;
      tokens += (asciiRunLength / 4).ceil();
      asciiRunLength = 0;
    }

    for (final rune in trimmed.runes) {
      final isAsciiLetterOrDigit =
          (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A);
      if (isAsciiLetterOrDigit) {
        asciiRunLength++;
        continue;
      }

      flushAsciiRun();

      final isWhitespace =
          rune == 0x20 || rune == 0x0A || rune == 0x0D || rune == 0x09;
      if (!isWhitespace) {
        tokens++;
      }
    }
    flushAsciiRun();
    return tokens;
  }

  /// 流式增强文本（SSE）。
  Stream<String> enhanceStream(String text, {Duration? timeout}) {
    return _resolveProvider().enhanceStream(text, timeout: timeout);
  }

  /// 检查文本模型服务是否可用（简单版本）。
  Future<bool> checkAvailability() async {
    final result = await checkAvailabilityDetailed();
    return result.ok;
  }

  /// 检查文本模型服务是否可用（详细版本）。
  Future<AiConnectionCheckResult> checkAvailabilityDetailed() {
    return _resolveProvider().checkAvailabilityDetailed();
  }
}
