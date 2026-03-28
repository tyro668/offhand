import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/stt_request_context.dart';
import '../log_service.dart';
import '../network_client_service.dart';
import 'stt_provider.dart';

/// OpenAI 标准 multipart /audio/transcriptions 接口。
///
/// 适用于 OpenAI 原生 API。
class OpenAiSttProvider extends SttProvider {
  OpenAiSttProvider(super.config);

  @override
  SttProviderCapabilities get capabilities => const SttProviderCapabilities(
    supportsPrompt: true,
    supportsPreferredTerms: true,
  );

  @override
  Future<String> transcribe(
    String audioPath, {
    SttRequestContext? context,
  }) async {
    final model = config.model.trim();
    await LogService.info(
      'STT',
      'OpenAI transcribe model=$model baseUrl=${config.baseUrl} file=$audioPath',
    );

    final apiKeyError = apiKeyValidationMessage();
    if (apiKeyError != null) {
      await LogService.error('STT', 'api key validation failed: $apiKeyError');
      throw SttException(apiKeyError);
    }

    final uri = Uri.parse(
      '${normalizeBaseUrl(config.baseUrl)}/audio/transcriptions',
    );
    await LogService.info('STT', 'POST $uri');

    final request = http.MultipartRequest('POST', uri);

    if (config.apiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${config.apiKey}';
    }

    request.fields['model'] = model;
    request.fields['response_format'] = 'json';
    if ((context?.prompt ?? '').trim().isNotEmpty) {
      request.fields['prompt'] = context!.prompt!.trim();
    }

    request.files.add(await http.MultipartFile.fromPath('file', audioPath));

    http.Response response;
    final client = NetworkClientService.createClient();
    try {
      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(seconds: 120));
      response = await http.Response.fromStream(streamedResponse);
    } on TimeoutException {
      client.close();
      rethrow;
    } on SocketException {
      client.close();
      rethrow;
    } on http.ClientException {
      client.close();
      rethrow;
    } finally {
      client.close();
    }

    await LogService.info(
      'STT',
      'transcribe response status=${response.statusCode} bodyLength=${response.body.length}',
    );

    if (response.statusCode == 200) {
      final text = extractTranscriptionText(response.body);
      await LogService.info(
        'STT',
        'transcribe success textLength=${text.length}',
      );
      return text;
    } else {
      final message = buildTranscribeErrorMessage(
        response.statusCode,
        response.body,
      );
      await LogService.error('STT', message);
      throw SttException(message);
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
