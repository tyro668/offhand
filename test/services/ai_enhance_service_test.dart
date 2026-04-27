import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/ai_enhance_config.dart';
import 'package:voicetype/services/ai_enhance_service.dart';

void main() {
  group('AiEnhanceService', () {
    group('enhance', () {
      test('returns enhanced text for 200 response', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((req) async {
          if (req.uri.path.endsWith('/chat/completions')) {
            req.response.statusCode = 200;
            req.response.headers.contentType = ContentType.json;
            req.response.write(
              json.encode({
                'choices': [
                  {
                    'message': {'content': 'Enhanced text here'},
                  },
                ],
              }),
            );
          }
          await req.response.close();
        });

        final config = AiEnhanceConfig(
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test-key',
          model: 'test-model',
          prompt: 'Fix my text',
          agentName: 'Agent',
        );

        final result = await AiEnhanceService(config).enhance('raw text');
        expect(result.text, 'Enhanced text here');
      });

      test('returns original text when input is empty', () async {
        const config = AiEnhanceConfig(
          baseUrl: 'https://example.com/v1',
          apiKey: 'test-key',
          model: 'test-model',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        final result = await AiEnhanceService(config).enhance('');
        expect(result.text, '');
      });

      test('returns original text when input is whitespace only', () async {
        const config = AiEnhanceConfig(
          baseUrl: 'https://example.com/v1',
          apiKey: 'test-key',
          model: 'test-model',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        final result = await AiEnhanceService(config).enhance('   ');
        expect(result.text, '   ');
      });

      test('throws AiEnhanceException for empty API key', () async {
        const config = AiEnhanceConfig(
          baseUrl: 'https://example.com/v1',
          apiKey: '',
          model: 'test-model',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        expect(
          () => AiEnhanceService(config).enhance('text'),
          throwsA(isA<AiEnhanceException>()),
        );
      });

      test('throws AiEnhanceException for ENC: API key', () async {
        const config = AiEnhanceConfig(
          baseUrl: 'https://example.com/v1',
          apiKey: 'ENC:bad',
          model: 'test-model',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        expect(
          () => AiEnhanceService(config).enhance('text'),
          throwsA(isA<AiEnhanceException>()),
        );
      });

      test('throws AiEnhanceException for invalid URL scheme', () async {
        const config = AiEnhanceConfig(
          baseUrl: 'ftp://example.com/v1',
          apiKey: 'test-key',
          model: 'test-model',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        expect(
          () => AiEnhanceService(config).enhance('text'),
          throwsA(isA<AiEnhanceException>()),
        );
      });

      test('throws AiEnhanceException for non-200 response', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((req) async {
          req.response.statusCode = 500;
          req.response.write(
            json.encode({
              'error': {'message': 'Server error'},
            }),
          );
          await req.response.close();
        });

        final config = AiEnhanceConfig(
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test-key',
          model: 'test-model',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        expect(
          () => AiEnhanceService(config).enhance('text'),
          throwsA(isA<AiEnhanceException>()),
        );
      });

      test('replaces {agentName} in prompt', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        String? receivedBody;
        server.listen((req) async {
          if (req.uri.path.endsWith('/chat/completions')) {
            receivedBody = await utf8.decoder.bind(req).join();
            req.response.statusCode = 200;
            req.response.headers.contentType = ContentType.json;
            req.response.write(
              json.encode({
                'choices': [
                  {
                    'message': {'content': 'result'},
                  },
                ],
              }),
            );
          }
          await req.response.close();
        });

        final config = AiEnhanceConfig(
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test-key',
          model: 'test-model',
          prompt: 'You are {agentName}, a helpful assistant',
          agentName: 'MyBot',
        );

        await AiEnhanceService(config).enhance('hello');

        expect(receivedBody, isNotNull);
        final body = json.decode(receivedBody!) as Map<String, dynamic>;
        final messages = body['messages'] as List;
        final systemMsg = messages[0] as Map<String, dynamic>;
        expect(systemMsg['content'], 'You are MyBot, a helpful assistant');
      });

      test('sends default thinking control in chat completions body', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        Map<String, dynamic>? payload;
        server.listen((req) async {
          if (req.uri.path.endsWith('/chat/completions')) {
            final body = await utf8.decoder.bind(req).join();
            payload = json.decode(body) as Map<String, dynamic>;
            req.response.statusCode = 200;
            req.response.headers.contentType = ContentType.json;
            req.response.write(
              json.encode({
                'choices': [
                  {
                    'message': {'content': 'result'},
                  },
                ],
              }),
            );
          }
          await req.response.close();
        });

        final config = AiEnhanceConfig(
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test-key',
          model: 'qwen3.5-plus',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        await AiEnhanceService(config).enhance('hello');

        expect(payload, isNotNull);
        expect(payload!['thinking'], {'type': 'disabled'});
        expect(payload!['enable_thinking'], isFalse);
      });
    });

    group('checkAvailabilityDetailed', () {
      test('returns ok=true for 200 /models response', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((req) async {
          req.response.statusCode = 200;
          req.response.write(
            json.encode({
              'object': 'list',
              'data': [
                {'id': 'model-1'},
              ],
            }),
          );
          await req.response.close();
        });

        final config = AiEnhanceConfig(
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test-key',
          model: 'model-1',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        final result = await AiEnhanceService(
          config,
        ).checkAvailabilityDetailed();
        expect(result.ok, isTrue);
      });

      test('returns ok=false for empty API key', () async {
        const config = AiEnhanceConfig(
          baseUrl: 'https://example.com/v1',
          apiKey: '',
          model: 'test-model',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        final result = await AiEnhanceService(
          config,
        ).checkAvailabilityDetailed();
        expect(result.ok, isFalse);
      });

      test('returns ok=false for invalid URL', () async {
        const config = AiEnhanceConfig(
          baseUrl: 'not-a-url',
          apiKey: 'test-key',
          model: 'test-model',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        final result = await AiEnhanceService(
          config,
        ).checkAvailabilityDetailed();
        expect(result.ok, isFalse);
      });

      test('returns ok=false for 401 /models (auth error)', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((req) async {
          req.response.statusCode = 401;
          req.response.write(
            json.encode({
              'error': {'message': 'Unauthorized'},
            }),
          );
          await req.response.close();
        });

        final config = AiEnhanceConfig(
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'bad-key',
          model: 'test-model',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        final result = await AiEnhanceService(
          config,
        ).checkAvailabilityDetailed();
        expect(result.ok, isFalse);
        expect(result.message, contains('API'));
      });

      test('returns ok=true for 404 /models (server reachable)', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((req) async {
          req.response.statusCode = 404;
          await req.response.close();
        });

        final config = AiEnhanceConfig(
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test-key',
          model: 'test-model',
          prompt: 'Fix',
          agentName: 'Agent',
        );

        final result = await AiEnhanceService(
          config,
        ).checkAvailabilityDetailed();
        expect(result.ok, isTrue);
      });
    });

    group('AiEnhanceException', () {
      test('toString returns message', () {
        final exception = AiEnhanceException('test error');
        expect(exception.toString(), 'test error');
        expect(exception.message, 'test error');
      });
    });
  });
}
