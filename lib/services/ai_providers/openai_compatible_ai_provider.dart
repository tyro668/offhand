import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../log_service.dart';
import '../model_request_options.dart';
import '../network_client_service.dart';
import 'ai_provider.dart';

/// OpenAI 兼容协议的通用 AI Provider 实现。
///
/// 所有支持 OpenAI `/chat/completions` 协议的厂商都可继承此类。
/// 子类可 override [chatCompletionsUrl] / [modelsUrl] 来定制端点路径。
class OpenAiCompatibleAiProvider extends AiProvider {
  static const _defaultTimeout = Duration(seconds: 30);
  static const _defaultStreamTimeout = Duration(seconds: 60);

  OpenAiCompatibleAiProvider(super.config);

  /// `/chat/completions` 端点 URL。子类可 override。
  String get chatCompletionsUrl =>
      '${normalizeBaseUrl(config.baseUrl)}/chat/completions';

  /// `/models` 端点 URL。子类可 override。
  String get modelsUrl => '${normalizeBaseUrl(config.baseUrl)}/models';

  @override
  Future<AiEnhanceResult> enhance(String text, {Duration? timeout}) async {
    if (text.trim().isEmpty) return AiEnhanceResult(text: text);

    await LogService.info(
      'AI',
      'start enhance model=${config.model} baseUrl=${config.baseUrl} textLength=${text.length}',
    );

    final apiKeyError = apiKeyValidationMessage();
    if (apiKeyError != null) {
      await LogService.error('AI', 'api key validation failed: $apiKeyError');
      throw AiEnhanceException('AI增强失败: $apiKeyError');
    }

    final resolvedPrompt = resolvePrompt();
    final headers = buildHeaders();
    headers['Content-Type'] = 'application/json; charset=utf-8';
    final bodyMap = <String, dynamic>{
      'model': config.model,
      'temperature': 0.2,
      'messages': [
        {'role': 'system', 'content': resolvedPrompt},
        {'role': 'user', 'content': buildEnhanceUserMessage(text)},
      ],
    };
    bodyMap.addAll(buildDefaultThinkingOptions(config.model));
    final body = json.encode(bodyMap);

    final uri = Uri.parse(chatCompletionsUrl);

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw AiEnhanceException('AI增强失败: 无效的端点 URL');
    }

    final effectiveTimeout = timeout ?? _defaultTimeout;
    final client = NetworkClientService.createClient();
    try {
      final response = await client
          .post(uri, headers: headers, body: body)
          .timeout(effectiveTimeout);

      await LogService.info(
        'AI',
        'enhance response status=${response.statusCode} bodyLength=${response.body.length}',
      );

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body) as Map<String, dynamic>;
        final content = extractContentFromJson(jsonBody, text);
        final usage = jsonBody['usage'] as Map<String, dynamic>?;
        final promptTokens = (usage?['prompt_tokens'] as int?) ?? 0;
        final completionTokens = (usage?['completion_tokens'] as int?) ?? 0;
        await LogService.info(
          'AI',
          'enhance success textLength=${content.length} promptTokens=$promptTokens completionTokens=$completionTokens',
        );
        return AiEnhanceResult(
          text: content,
          promptTokens: promptTokens,
          completionTokens: completionTokens,
        );
      }

      // 尝试解析错误信息
      String errorMsg = 'AI增强失败 (${response.statusCode})';
      try {
        final jsonBody = json.decode(response.body) as Map<String, dynamic>;
        final error = jsonBody['error'] as Map<String, dynamic>?;
        if (error != null) {
          errorMsg = 'AI增强失败: ${error['message'] ?? response.body}';
        } else if (jsonBody['message'] != null) {
          errorMsg = 'AI增强失败: ${jsonBody['message']}';
        }
      } catch (_) {
        errorMsg = 'AI增强失败 (${response.statusCode}): ${response.body}';
      }

      await LogService.error('AI', errorMsg);
      throw AiEnhanceException(errorMsg);
    } on TimeoutException {
      await LogService.error('AI', 'AI增强失败: 请求超时');
      throw AiEnhanceException('AI增强失败: 请求超时');
    } on SocketException catch (e) {
      await LogService.error('AI', 'AI增强失败: 网络连接错误 - ${e.message}');
      throw AiEnhanceException('AI增强失败: 网络连接错误 - ${e.message}');
    } catch (e) {
      if (e is AiEnhanceException) rethrow;
      await LogService.error('AI', 'AI增强失败: $e');
      throw AiEnhanceException('AI增强失败: $e');
    } finally {
      client.close();
    }
  }

  @override
  Stream<String> enhanceStream(String text, {Duration? timeout}) async* {
    if (text.trim().isEmpty) {
      yield text;
      return;
    }

    await LogService.info(
      'AI',
      'start streaming enhance model=${config.model} baseUrl=${config.baseUrl}',
    );

    final apiKeyError = apiKeyValidationMessage();
    if (apiKeyError != null) {
      await LogService.error('AI', 'api key validation failed: $apiKeyError');
      throw AiEnhanceException('AI增强失败: $apiKeyError');
    }

    final resolvedPrompt = resolvePrompt();

    final uri = Uri.parse(chatCompletionsUrl);

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw AiEnhanceException('AI增强失败: 无效的端点 URL');
    }

    final bodyMap = <String, dynamic>{
      'model': config.model,
      'temperature': 0.2,
      'stream': true,
      'messages': [
        {'role': 'system', 'content': resolvedPrompt},
        {'role': 'user', 'content': buildEnhanceUserMessage(text)},
      ],
    };
    bodyMap.addAll(buildDefaultThinkingOptions(config.model));

    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      final apiKey = config.apiKey.trim();
      if (apiKey.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $apiKey');
      }
      request.add(utf8.encode(json.encode(bodyMap)));

      final response = await request.close().timeout(
        timeout ?? _defaultStreamTimeout,
      );

      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        await LogService.error(
          'AI',
          'streaming enhance failed: ${response.statusCode} $body',
        );
        throw AiEnhanceException('AI增强失败 (${response.statusCode})');
      }

      // Parse SSE stream line-by-line to avoid losing events when network
      // chunks split in the middle of a JSON payload.
      await for (final rawLine
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        if (!line.startsWith('data:')) continue;

        final jsonStr = line.substring(5).trim();
        if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;

        try {
          final jsonData = json.decode(jsonStr) as Map<String, dynamic>;
          final choices = jsonData['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) continue;

          final delta = choices.first['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            yield content;
          } else if (content is List) {
            for (final part in content) {
              if (part is Map<String, dynamic>) {
                final text = part['text'];
                if (text is String && text.isNotEmpty) {
                  yield text;
                }
              }
            }
          }
        } catch (_) {
          // Skip malformed SSE data lines.
        }
      }

      await LogService.info('AI', 'streaming enhance complete');
    } on TimeoutException {
      await LogService.error('AI', 'streaming enhance timeout');
      throw AiEnhanceException('AI增强失败: 流式请求超时');
    } on SocketException catch (e) {
      await LogService.error(
        'AI',
        'streaming enhance socket error: ${e.message}',
      );
      throw AiEnhanceException('AI增强失败: 网络连接错误 - ${e.message}');
    } catch (e) {
      if (e is AiEnhanceException) rethrow;
      await LogService.error('AI', 'streaming enhance error: $e');
      throw AiEnhanceException('AI增强失败: $e');
    } finally {
      httpClient.close();
    }
  }

  @override
  Future<AiConnectionCheckResult> checkAvailabilityDetailed() async {
    await LogService.info(
      'AI',
      'checkAvailability model=${config.model} baseUrl=${config.baseUrl}',
    );

    final apiKeyError = apiKeyValidationMessage();
    if (apiKeyError != null) {
      await LogService.error('AI', 'checkAvailability failed: $apiKeyError');
      return AiConnectionCheckResult(ok: false, message: apiKeyError);
    }

    final normalizedBase = normalizeBaseUrl(config.baseUrl);
    developer.log('检查连接 - 基础URL: $normalizedBase', name: 'AiEnhanceService');

    if (!isValidBaseUrl(normalizedBase)) {
      return const AiConnectionCheckResult(ok: false, message: '端点 URL 无效');
    }

    return _checkModelsEndpoint();
  }

  Future<AiConnectionCheckResult> _checkModelsEndpoint() async {
    final uri = Uri.parse(modelsUrl);
    developer.log('检查连接 - 尝试 /models: $uri', name: 'AiEnhanceService');

    final headers = buildHeaders();
    final client = NetworkClientService.createClient();
    try {
      final stopwatch = Stopwatch()..start();
      final response = await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();

      developer.log(
        '检查连接 - /models 响应: ${response.statusCode}, 耗时: ${stopwatch.elapsedMilliseconds}ms',
        name: 'AiEnhanceService',
      );

      if (response.statusCode == 200) {
        await LogService.info('AI', '/models check success (${uri.host})');
        return AiConnectionCheckResult(ok: true, message: '连接成功 (${uri.host})');
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        try {
          final jsonBody = json.decode(response.body) as Map<String, dynamic>;
          final error = jsonBody['error'] as Map<String, dynamic>?;
          final errorMsg =
              error?['message'] as String? ??
              jsonBody['message'] as String? ??
              '认证失败';
          return AiConnectionCheckResult(
            ok: false,
            message: 'API密钥无效: $errorMsg',
          );
        } catch (_) {
          return AiConnectionCheckResult(
            ok: false,
            message: 'API密钥无效 (${response.statusCode})',
          );
        }
      }

      // 404/405 表示服务可达但不支持该端点，仍视为连接成功
      if (response.statusCode == 404 || response.statusCode == 405) {
        return AiConnectionCheckResult(ok: true, message: '连接成功 (${uri.host})');
      }

      // 其他状态码（如 429 限流），服务端可达但有问题
      // 仍然视为连接成功（能收到响应说明服务可达）
      return AiConnectionCheckResult(ok: true, message: '连接成功 (${uri.host})');
    } on TimeoutException {
      developer.log('检查连接 - /models 超时', name: 'AiEnhanceService');
      await LogService.error('AI', 'checkAvailability timeout');
      return const AiConnectionCheckResult(ok: false, message: '请求超时，请检查网络连接');
    } on SocketException catch (e) {
      await LogService.error(
        'AI',
        'checkAvailability socket error: ${e.message}',
      );
      return AiConnectionCheckResult(
        ok: false,
        message: '网络连接失败: ${e.message}\n请检查网络连接和DNS设置',
      );
    } catch (e) {
      developer.log('检查连接 - /models 异常: $e', name: 'AiEnhanceService');
      await LogService.error('AI', 'checkAvailability error: $e');
      return AiConnectionCheckResult(ok: false, message: '连接失败: $e');
    } finally {
      client.close();
    }
  }
}
