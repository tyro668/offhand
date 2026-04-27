import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/stt_request_context.dart';
import '../log_service.dart';
import '../model_request_options.dart';
import '../network_client_service.dart';
import 'stt_provider.dart';

/// Aliyun DashScope STT Provider。
///
/// 不支持标准 /audio/transcriptions，直接走 /chat/completions：
/// - 音频使用 data URI 格式 (`data:audio/wav;base64,...`)
/// - 包含 `asr_options` 特有参数
/// - 模型名需规范化（下划线→连字符）
class AliyunSttProvider extends SttProvider {
  AliyunSttProvider(super.config);

  @override
  SttProviderCapabilities get capabilities => const SttProviderCapabilities(
    supportsPrompt: true,
    supportsPreferredTerms: true,
  );

  /// 规范化 Aliyun 模型名称。
  String _resolvedModel() {
    final model = config.model.trim();
    final canonical = model.toLowerCase().replaceAll('_', '-');
    switch (canonical) {
      case 'qwen3-asr-flash':
      case 'qwen-asr-flash':
      case 'qwen3asrflash':
        return 'qwen3-asr-flash';
      default:
        return canonical;
    }
  }

  @override
  Future<String> transcribe(
    String audioPath, {
    SttRequestContext? context,
  }) async {
    final resolvedModel = _resolvedModel();
    await LogService.info(
      'STT',
      'Aliyun transcribe model=${config.model} resolvedModel=$resolvedModel baseUrl=${config.baseUrl} file=$audioPath',
    );

    final apiKeyError = apiKeyValidationMessage();
    if (apiKeyError != null) {
      await LogService.error('STT', 'api key validation failed: $apiKeyError');
      throw SttException(apiKeyError);
    }

    final uri = Uri.parse(
      '${normalizeBaseUrl(config.baseUrl)}/chat/completions',
    );
    await LogService.info('STT', 'POST $uri (aliyun)');

    final bytes = await File(audioPath).readAsBytes();
    final base64Audio = base64Encode(bytes);
    final audioFormat = detectAudioFormat(audioPath);

    final instruction = (context?.prompt ?? '').trim().isNotEmpty
        ? context!.prompt!.trim()
        : '请将这段音频准确转写为纯文本，仅返回转写结果。';

    final headers = buildHeaders();
    final payload = <String, dynamic>{
      'model': resolvedModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': instruction},
            {
              'type': 'input_audio',
              'input_audio': {
                'data': 'data:audio/$audioFormat;base64,$base64Audio',
              },
            },
          ],
        },
      ],
      'stream': false,
      'asr_options': {'enable_itn': false},
    };
    payload.addAll(buildDefaultThinkingOptions(resolvedModel));
    final body = json.encode(payload);

    final client = NetworkClientService.createClient();
    try {
      final response = await client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 120));

      await LogService.info(
        'STT',
        'Aliyun response status=${response.statusCode} bodyLength=${response.body.length}',
      );

      if (response.statusCode != 200) {
        final message = buildTranscribeErrorMessage(
          response.statusCode,
          response.body,
        );
        await LogService.error('STT', message);
        throw SttException(message);
      }

      return extractTextFromChatCompletion(response.body);
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
      return await checkModelsEndpoint(config.baseUrl);
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
