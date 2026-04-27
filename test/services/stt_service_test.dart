import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/provider_config.dart';
import 'package:voicetype/models/stt_request_context.dart';
import 'package:voicetype/services/stt_service.dart';

void main() {
  group('SttService', () {
    group('checkAvailabilityDetailed', () {
      test('returns ok=true for 200 /models response', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((req) async {
          if (req.uri.path.endsWith('/models')) {
            req.response.statusCode = 200;
            req.response.write(
              json.encode({
                'object': 'list',
                'data': [
                  {'id': 'whisper-1'},
                ],
              }),
            );
          }
          await req.response.close();
        });

        final config = SttProviderConfig(
          type: SttProviderType.cloud,
          name: 'Test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test-key',
          model: 'whisper-1',
        );

        final result = await SttService(config).checkAvailabilityDetailed();
        expect(result.ok, isTrue);
      });

      test('returns ok=false for empty API key', () async {
        const config = SttProviderConfig(
          type: SttProviderType.cloud,
          name: 'Test',
          baseUrl: 'https://example.com/v1',
          apiKey: '',
          model: 'whisper-1',
        );

        final result = await SttService(config).checkAvailabilityDetailed();
        expect(result.ok, isFalse);
      });

      test(
        'returns ok=false for ENC: prefixed API key (decrypt failure)',
        () async {
          const config = SttProviderConfig(
            type: SttProviderType.cloud,
            name: 'Test',
            baseUrl: 'https://example.com/v1',
            apiKey: 'ENC:bad-encrypted',
            model: 'whisper-1',
          );

          final result = await SttService(config).checkAvailabilityDetailed();
          expect(result.ok, isFalse);
        },
      );

      test('returns ok=true for 404 /models (server reachable)', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((req) async {
          req.response.statusCode = 404;
          await req.response.close();
        });

        final config = SttProviderConfig(
          type: SttProviderType.cloud,
          name: 'Test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test-key',
          model: 'whisper-1',
        );

        final result = await SttService(config).checkAvailabilityDetailed();
        expect(result.ok, isTrue);
      });

      test('returns ok=false for 401 /models (auth error)', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((req) async {
          req.response.statusCode = 401;
          req.response.write(
            json.encode({
              'error': {'message': 'Invalid API key'},
            }),
          );
          await req.response.close();
        });

        final config = SttProviderConfig(
          type: SttProviderType.cloud,
          name: 'Test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'bad-key',
          model: 'whisper-1',
        );

        final result = await SttService(config).checkAvailabilityDetailed();
        expect(result.ok, isFalse);
        expect(result.message, contains('API'));
      });

      test('returns ok=false for unreachable host', () async {
        const config = SttProviderConfig(
          type: SttProviderType.cloud,
          name: 'Test',
          baseUrl: 'http://127.0.0.1:1/v1', // unlikely to have a server here
          apiKey: 'test-key',
          model: 'whisper-1',
        );

        final result = await SttService(config).checkAvailabilityDetailed();
        expect(result.ok, isFalse);
      });
    });

    group('transcribe', () {
      test('returns transcribed text for 200 response', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((req) async {
          if (req.uri.path.endsWith('/audio/transcriptions')) {
            req.response.statusCode = 200;
            req.response.write(json.encode({'text': 'Hello world'}));
          } else {
            req.response.statusCode = 404;
          }
          await req.response.close();
        });

        final config = SttProviderConfig(
          type: SttProviderType.cloud,
          name: 'Test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test-key',
          model: 'whisper-1',
        );

        // Create a temporary wav file
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/test_audio.wav');
        await tempFile.writeAsBytes([0, 0, 0, 0]); // minimal bytes
        addTearDown(() => tempFile.deleteSync());

        final result = await SttService(config).transcribe(tempFile.path);
        expect(result, 'Hello world');
      });

      test('passes prompt to OpenAI compatible transcription request', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        var capturedBody = '';
        server.listen((req) async {
          capturedBody = await utf8.decoder.bind(req).join();
          req.response.statusCode = 200;
          req.response.write(json.encode({'text': 'Hello world'}));
          await req.response.close();
        });

        final config = SttProviderConfig(
          type: SttProviderType.cloud,
          name: 'Test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test-key',
          model: 'whisper-1',
        );

        final tempFile = File('${Directory.systemTemp.path}/test_audio_prompt.wav');
        await tempFile.writeAsBytes([0, 0, 0, 0]);
        addTearDown(() => tempFile.deleteSync());

        await SttService(config).transcribe(
          tempFile.path,
          context: const SttRequestContext(
            scene: 'dictation',
            prompt: '优先识别 MCP 和 DeepSeek',
          ),
        );

        expect(capturedBody, contains('name="prompt"'));
        expect(capturedBody, contains('优先识别 MCP 和 DeepSeek'));
      });

      test(
        'aliyun fallback works when /audio/transcriptions returns 500',
        () async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          addTearDown(() => server.close(force: true));

          Map<String, dynamic>? fallbackPayload;

          server.listen((req) async {
            final path = req.uri.path;
            if (path.endsWith('/audio/transcriptions')) {
              req.response.statusCode = 500;
              req.response.write(
                json.encode({
                  'error': {'message': 'upstream unstable'},
                }),
              );
            } else if (path.endsWith('/chat/completions')) {
              final body = await utf8.decoder.bind(req).join();
              fallbackPayload = json.decode(body) as Map<String, dynamic>;
              req.response.statusCode = 200;
              req.response.write(
                json.encode({
                  'choices': [
                    {
                      'message': {'content': 'Aliyun fallback text'},
                    },
                  ],
                }),
              );
            } else {
              req.response.statusCode = 404;
            }
            await req.response.close();
          });

          final config = SttProviderConfig(
            type: SttProviderType.cloud,
            name: 'Aliyun',
            baseUrl:
                'http://127.0.0.1:${server.port}/dashscope.aliyuncs.com/compatible-mode/v1',
            apiKey: 'test-key',
            model: 'qwen3-asr-flash',
          );

          final tempFile = File(
            '${Directory.systemTemp.path}/test_audio_fallback.wav',
          );
          await tempFile.writeAsBytes([0, 0, 0, 0]);
          addTearDown(() => tempFile.deleteSync());

          final result = await SttService(config).transcribe(tempFile.path);
          expect(result, 'Aliyun fallback text');
          expect(fallbackPayload, isNotNull);
          expect(fallbackPayload!['thinking'], {'type': 'disabled'});
          expect(fallbackPayload!['enable_thinking'], isFalse);
        },
      );

      test('throws SttException for empty API key', () async {
        const config = SttProviderConfig(
          type: SttProviderType.cloud,
          name: 'Test',
          baseUrl: 'http://127.0.0.1:1/v1',
          apiKey: '',
          model: 'whisper-1',
        );

        expect(
          () => SttService(config).transcribe('/tmp/fake.wav'),
          throwsA(isA<SttException>()),
        );
      });

      test('throws SttException for non-200 response', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((req) async {
          req.response.statusCode = 500;
          req.response.write(
            json.encode({
              'error': {'message': 'Internal server error'},
            }),
          );
          await req.response.close();
        });

        final config = SttProviderConfig(
          type: SttProviderType.cloud,
          name: 'Test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test-key',
          model: 'whisper-1',
        );

        final tempFile = File('${Directory.systemTemp.path}/test_audio2.wav');
        await tempFile.writeAsBytes([0, 0, 0, 0]);
        addTearDown(() => tempFile.deleteSync());

        expect(
          () => SttService(config).transcribe(tempFile.path),
          throwsA(isA<SttException>()),
        );
      });

      test('passes prompt to Gemini compatible request text instruction', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        Map<String, dynamic>? capturedPayload;
        String capturedInstruction = '';
        server.listen((req) async {
          final body = await utf8.decoder.bind(req).join();
          capturedPayload = json.decode(body) as Map<String, dynamic>;
          final messages = capturedPayload!['messages'] as List<dynamic>;
          final content =
              (messages.first as Map<String, dynamic>)['content'] as List<dynamic>;
          capturedInstruction =
              (content.first as Map<String, dynamic>)['text'] as String? ?? '';
          req.response.statusCode = 200;
          req.response.write(
            json.encode({
              'choices': [
                {
                  'message': {'content': 'Gemini text'},
                },
              ],
            }),
          );
          await req.response.close();
        });

        final config = SttProviderConfig(
          type: SttProviderType.cloud,
          name: 'Gemini',
          baseUrl:
              'http://127.0.0.1:${server.port}/generativelanguage.googleapis.com/v1beta',
          apiKey: 'test-key',
          model: 'gemini-2.5-flash',
        );

        final tempFile = File('${Directory.systemTemp.path}/test_audio_gemini.wav');
        await tempFile.writeAsBytes([0, 0, 0, 0]);
        addTearDown(() => tempFile.deleteSync());

        final result = await SttService(config).transcribe(
          tempFile.path,
          context: const SttRequestContext(
            scene: 'meeting',
            prompt: '优先识别 帆软 和 FineBI',
          ),
        );

        expect(result, 'Gemini text');
        expect(capturedInstruction, contains('优先识别 帆软 和 FineBI'));
        expect(capturedPayload, isNotNull);
        expect(capturedPayload!['thinking'], {'type': 'disabled'});
      });
    });

    group('SttException', () {
      test('toString returns message', () {
        final exception = SttException('test error');
        expect(exception.toString(), 'test error');
        expect(exception.message, 'test error');
      });
    });
  });
}
