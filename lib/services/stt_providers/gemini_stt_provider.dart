import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/stt_request_context.dart';
import '../log_service.dart';
import '../network_client_service.dart';
import 'stt_provider.dart';

/// Google Gemini STT Provider。
///
/// baseUrl 为 Gemini 原生端点 `/v1beta`，内部拼接 `/openai/chat/completions` 走
/// OpenAI 兼容层。未来可切换为原生 `generateContent` API。
///
/// 音频编码方式：纯 base64 + format 字段分离，含 text prompt。
class GeminiSttProvider extends SttProvider {
  GeminiSttProvider(super.config);

  @override
  SttProviderCapabilities get capabilities => const SttProviderCapabilities(
    supportsPrompt: true,
    supportsPreferredTerms: true,
  );

  static const String _fallbackSttModel = 'gemini-2.5-flash';

  /// 获取 OpenAI 兼容层的 baseUrl。
  /// 如果用户配置的 baseUrl 已经以 /openai 结尾，直接使用；
  /// 否则自动追加 /openai。
  String _openAiBaseUrl() {
    final base = normalizeBaseUrl(config.baseUrl);
    if (base.endsWith('/openai')) return base;
    return '$base/openai';
  }

  String _resolveGeminiSttModel(String model) {
    final normalized = model.trim().toLowerCase();
    if (normalized.startsWith('gemini-3.0-')) {
      return _fallbackSttModel;
    }
    return model.trim();
  }

  bool _isModelNotFoundResponse(int statusCode, String body) {
    if (statusCode != 404) return false;
    final lower = body.toLowerCase();
    return lower.contains('models/') &&
        (lower.contains('not found') || lower.contains('not_found'));
  }

  @override
  Future<String> transcribe(
    String audioPath, {
    SttRequestContext? context,
  }) async {
    final requestedModel = config.model.trim();
    final model = _resolveGeminiSttModel(requestedModel);
    await LogService.info(
      'STT',
      'Gemini transcribe model=$requestedModel resolvedModel=$model baseUrl=${config.baseUrl} file=$audioPath',
    );

    final apiKeyError = apiKeyValidationMessage();
    if (apiKeyError != null) {
      await LogService.error('STT', 'api key validation failed: $apiKeyError');
      throw SttException(apiKeyError);
    }

    final uri = Uri.parse('${_openAiBaseUrl()}/chat/completions');
    await LogService.info('STT', 'POST $uri (gemini)');

    final bytes = await File(audioPath).readAsBytes();
    final base64Audio = base64Encode(bytes);
    final audioFormat = detectAudioFormat(audioPath);

    final instruction = (context?.prompt ?? '').trim().isNotEmpty
        ? context!.prompt!.trim()
        : '请将这段音频准确转写为纯文本，仅返回转写结果。';

    final headers = buildHeaders();
    final client = NetworkClientService.createClient();
    try {
      Future<String> sendWithModel(String currentModel) async {
        final currentBody = json.encode({
          'model': currentModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': instruction},
                {
                  'type': 'input_audio',
                  'input_audio': {'data': base64Audio, 'format': audioFormat},
                },
              ],
            },
          ],
          'stream': false,
          'temperature': 0,
        });

        final response = await client
            .post(uri, headers: headers, body: currentBody)
            .timeout(const Duration(seconds: 120));

        await LogService.info(
          'STT',
          'Gemini response status=${response.statusCode} bodyLength=${response.body.length} model=$currentModel',
        );

        if (response.statusCode == 200) {
          return extractTextFromChatCompletion(response.body);
        }

        if (currentModel != _fallbackSttModel &&
            _isModelNotFoundResponse(response.statusCode, response.body)) {
          await LogService.info(
            'STT',
            'Gemini model $currentModel not found, retry with fallback $_fallbackSttModel',
          );
          return sendWithModel(_fallbackSttModel);
        }

        final message = buildTranscribeErrorMessage(
          response.statusCode,
          response.body,
        );
        await LogService.error('STT', message);
        throw SttException(message);
      }

      return sendWithModel(model);
    } finally {
      client.close();
    }
  }

  @override
  Future<SttConnectionCheckResult> checkAvailabilityDetailed() async {
    await LogService.info(
      'STT',
      'checkAvailability provider=${config.name} model=${config.model} baseUrl=${config.baseUrl}',
    );

    final apiKeyError = apiKeyValidationMessage();
    if (apiKeyError != null) {
      await LogService.error('STT', 'checkAvailability failed: $apiKeyError');
      return SttConnectionCheckResult(ok: false, message: apiKeyError);
    }

    try {
      // 使用 OpenAI 兼容层的 /models 端点
      return await checkModelsEndpoint(_openAiBaseUrl());
    } on TimeoutException {
      await LogService.error('STT', 'checkAvailability timeout');
      return const SttConnectionCheckResult(ok: false, message: '请求超时，请检查网络连接');
    } on SocketException catch (e) {
      await LogService.error(
        'STT',
        'checkAvailability socket error: ${e.message}',
      );
      return SttConnectionCheckResult(
        ok: false,
        message: '网络连接失败: ${e.message}',
      );
    } catch (e) {
      await LogService.error('STT', 'checkAvailability error: $e');
      return SttConnectionCheckResult(ok: false, message: '连接失败: $e');
    }
  }
}
