import 'dart:convert';

import '../../models/provider_config.dart';
import '../../models/stt_request_context.dart';
import '../log_service.dart';
import '../network_client_service.dart';

/// STT 服务连接检查结果
class SttConnectionCheckResult {
  final bool ok;
  final String message;

  const SttConnectionCheckResult({required this.ok, required this.message});
}

/// STT 服务异常
class SttException implements Exception {
  final String message;
  SttException(this.message);

  @override
  String toString() => message;
}

class SttProviderCapabilities {
  final bool supportsPrompt;
  final bool supportsPreferredTerms;

  const SttProviderCapabilities({
    this.supportsPrompt = false,
    this.supportsPreferredTerms = false,
  });
}

/// STT Provider 抽象基类。
///
/// 每个厂商实现自己的 [transcribe] 和 [checkAvailabilityDetailed] 方法。
abstract class SttProvider {
  final SttProviderConfig config;

  SttProvider(this.config);

  SttProviderCapabilities get capabilities => const SttProviderCapabilities();

  /// 将音频文件转写为文本。
  Future<String> transcribe(
    String audioPath, {
    SttRequestContext? context,
  });

  /// 检查服务是否可用（详细版本）。
  Future<SttConnectionCheckResult> checkAvailabilityDetailed();

  // ─── 共享工具方法 ───

  /// 去除尾部斜杠的标准化 baseUrl。
  String normalizeBaseUrl(String baseUrl) {
    var result = baseUrl.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// 构建认证 headers。
  Map<String, String> buildHeaders({String contentType = 'application/json'}) {
    final headers = <String, String>{'Content-Type': contentType};
    if (config.apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }
    return headers;
  }

  /// 校验 API Key，返回 null 表示通过。
  String? apiKeyValidationMessage() {
    final apiKey = config.apiKey.trim();
    if (apiKey.isEmpty) {
      return 'API密钥为空，请先填写 API Key';
    }
    if (apiKey.startsWith('ENC:')) {
      return 'API密钥解密失败，请重新输入 API Key';
    }
    return null;
  }

  /// 通用 /models 端点连通性检查。
  Future<SttConnectionCheckResult> checkModelsEndpoint(String baseUrl) async {
    final uri = Uri.parse('${normalizeBaseUrl(baseUrl)}/models');
    await LogService.info('STT', 'GET $uri');
    final client = NetworkClientService.createClient();
    try {
      final response = await client
          .get(
            uri,
            headers: config.apiKey.isNotEmpty
                ? {'Authorization': 'Bearer ${config.apiKey}'}
                : null,
          )
          .timeout(const Duration(seconds: 15));

      await LogService.info(
        'STT',
        '/models response status=${response.statusCode} bodyLength=${response.body.length}',
      );

      if (response.statusCode == 200) {
        return SttConnectionCheckResult(
          ok: true,
          message: '连接成功 (${uri.host})',
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        try {
          final jsonBody = json.decode(response.body) as Map<String, dynamic>;
          final error = jsonBody['error'] as Map<String, dynamic>?;
          final errorMsg =
              error?['message'] as String? ??
              jsonBody['message'] as String? ??
              '认证失败';
          return SttConnectionCheckResult(
            ok: false,
            message: 'API密钥无效: $errorMsg',
          );
        } catch (_) {
          return SttConnectionCheckResult(
            ok: false,
            message: 'API密钥无效 (${response.statusCode})',
          );
        }
      }

      // 404/405 说明服务端可达但不支持 /models 端点，仍视为连接成功
      if (response.statusCode == 404 || response.statusCode == 405) {
        return SttConnectionCheckResult(
          ok: true,
          message: '连接成功 (${uri.host})',
        );
      }

      return SttConnectionCheckResult(
        ok: false,
        message: '接口返回错误 ${response.statusCode}',
      );
    } finally {
      client.close();
    }
  }

  /// 从 /audio/transcriptions 响应中提取文本。
  String extractTranscriptionText(String responseBody) {
    try {
      final body = json.decode(responseBody);
      if (body is Map<String, dynamic>) {
        final text = body['text']?.toString();
        if (text != null && text.trim().isNotEmpty) {
          return text.trim();
        }

        final transcript = body['transcript']?.toString();
        if (transcript != null && transcript.trim().isNotEmpty) {
          return transcript.trim();
        }

        final result = body['result'];
        if (result is String && result.trim().isNotEmpty) {
          return result.trim();
        }
      }
    } catch (_) {}

    return '';
  }

  /// 从 chat/completions 响应中提取文本。
  String extractTextFromChatCompletion(String responseBody) {
    final jsonBody = json.decode(responseBody) as Map<String, dynamic>;
    final choices = jsonBody['choices'] as List<dynamic>?;
    final message = choices?.isNotEmpty == true
        ? choices!.first['message'] as Map<String, dynamic>?
        : null;
    final content = message?['content'];

    if (content is String) {
      return content.trim();
    }

    if (content is List) {
      for (final item in content) {
        if (item is Map<String, dynamic> && item['type'] == 'text') {
          final text = item['text']?.toString();
          if (text != null && text.trim().isNotEmpty) {
            return text.trim();
          }
        }
      }
    }

    return '';
  }

  /// 检测音频文件格式。
  String detectAudioFormat(String audioPath) {
    final lower = audioPath.toLowerCase();
    if (lower.endsWith('.mp3')) return 'mp3';
    if (lower.endsWith('.m4a')) return 'm4a';
    if (lower.endsWith('.ogg')) return 'ogg';
    if (lower.endsWith('.flac')) return 'flac';
    if (lower.endsWith('.webm')) return 'webm';
    return 'wav';
  }

  /// 构建转写错误消息。
  String buildTranscribeErrorMessage(int statusCode, String responseBody) {
    try {
      final body = json.decode(responseBody);
      if (body is Map<String, dynamic>) {
        final error = body['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message']?.toString();
          if (message != null && message.isNotEmpty) {
            return '转录失败 ($statusCode): $message';
          }
        }

        final message = body['message']?.toString();
        if (message != null && message.isNotEmpty) {
          return '转录失败 ($statusCode): $message';
        }
      }
    } catch (_) {}

    return '转录失败 ($statusCode): $responseBody';
  }
}
