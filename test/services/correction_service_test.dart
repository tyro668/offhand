import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/ai_enhance_config.dart';
import 'package:voicetype/models/dictionary_entry.dart';
import 'package:voicetype/models/entity_alias.dart';
import 'package:voicetype/models/entity_memory.dart';
import 'package:voicetype/models/entity_relation.dart';
import 'package:voicetype/services/correction_context.dart';
import 'package:voicetype/services/correction_service.dart';
import 'package:voicetype/services/pinyin_matcher.dart';
import 'package:voicetype/services/session_entity_state.dart';
import 'package:voicetype/services/session_glossary.dart';

void main() {
  group('CorrectionService', () {
    late PinyinMatcher matcher;
    late CorrectionContext context;
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      matcher = PinyinMatcher();
      context = CorrectionContext();

      // Start a local mock server
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://localhost:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    /// Helper to create mock LLM server that echoes back a fixed response
    void setupMockServer(String responseText) {
      server.listen((request) async {
        final responseJson = json.encode({
          'choices': [
            {
              'message': {'content': responseText},
            },
          ],
          'usage': {'prompt_tokens': 50, 'completion_tokens': 20},
        });
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(responseJson);
        await request.response.close();
      });
    }

    test('returns original text when no dictionary matches', () async {
      matcher.buildIndex([]); // empty dictionary

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      final result = await service.correct('今天天气不错');
      expect(result.text, '今天天气不错');
      expect(result.llmInvoked, isFalse);
      expect(result.totalTokens, 0);
    });

    test('returns original text for empty input', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      final result = await service.correct('');
      expect(result.text, '');
      expect(result.llmInvoked, isFalse);
    });

    test('calls LLM when dictionary match found', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);

      setupMockServer('今天用了Metis做报表');

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      final result = await service.correct('今天用了墨提斯做报表');
      expect(result.text, '今天用了墨提斯做报表');
      expect(result.llmInvoked, isTrue);
      expect(result.promptTokens, 50);
      expect(result.completionTokens, 20);
    });

    test(
      'calls LLM when entity context exists without dictionary hits',
      () async {
        matcher.buildIndex([]);
        final zhang = EntityMemory.create(
          canonicalName: '张三丰',
          type: EntityType.person,
        );
        final li = EntityMemory.create(
          canonicalName: '李四娃',
          type: EntityType.person,
        );
        final sessionEntityState = SessionEntityState()
          ..activate(entityId: zhang.id, canonicalName: '张三丰', alias: '接龙');

        String capturedUserMessage = '';
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          final payload = json.decode(body) as Map<String, dynamic>;
          final messages = payload['messages'] as List<dynamic>? ?? [];
          capturedUserMessage = messages.isNotEmpty
              ? (messages.last as Map<String, dynamic>)['content'] as String? ??
                    ''
              : '';
          final responseJson = json.encode({
            'choices': [
              {
                'message': {'content': '快走，张三丰啊，李四娃马上出来了。'},
              },
            ],
            'usage': {'prompt_tokens': 60, 'completion_tokens': 12},
          });
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(responseJson);
          await request.response.close();
        });

        final service = CorrectionService(
          matcher: matcher,
          context: context,
          aiConfig: AiEnhanceConfig(
            agentName: 'test',
            baseUrl: baseUrl,
            apiKey: 'test-key',
            model: 'test-model',
            prompt: '',
          ),
          correctionPrompt: '纠错 prompt',
          entityMemories: [zhang, li],
          entityAliases: [
            EntityAlias.create(
              entityId: zhang.id,
              aliasText: '接龙',
              aliasType: EntityAliasType.misrecognition,
            ),
            EntityAlias.create(
              entityId: li.id,
              aliasText: '金雨希',
              aliasType: EntityAliasType.misrecognition,
            ),
          ],
          entityRelations: [
            EntityRelation.create(
              sourceEntityId: zhang.id,
              targetEntityId: li.id,
              relationType: '哥哥',
            ),
          ],
          sessionEntityState: sessionEntityState,
        );

        final result = await service.correct('快走，接龙啊，金雨希马上出来了。');
        expect(result.llmInvoked, isTrue);
        expect(result.text, '快走，张三丰啊，李四娃马上出来了。');
        expect(capturedUserMessage, contains('#E:'));
        expect(capturedUserMessage, contains('张三丰 | type=person'));
        expect(capturedUserMessage, contains('#ER:'));
        expect(capturedUserMessage, contains('张三丰 -> 李四娃 : 哥哥'));
      },
    );

    test('calls LLM when only pinyinPattern rule matches', () async {
      matcher.buildIndex([
        DictionaryEntry.create(
          original: '',
          corrected: 'Metis',
          pinyinPattern: 'mo ti si',
        ),
      ]);

      setupMockServer('今天用了Metis做报表');

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      final result = await service.correct('今天用了莫提斯做报表');
      expect(result.text, '今天用了Metis做报表');
      expect(result.llmInvoked, isTrue);
      expect(result.totalTokens, greaterThan(0));
    });

    test('literal match outranks pinyin-only rule when both match', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '莫提斯', corrected: '模型A'),
        DictionaryEntry.create(
          original: '',
          corrected: '模型B',
          pinyinPattern: 'mo ti si',
        ),
      ]);

      String capturedReference = '';
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final payload = json.decode(body) as Map<String, dynamic>;
        final messages = payload['messages'] as List<dynamic>? ?? [];
        final userMessage = messages.isNotEmpty
            ? (messages.last as Map<String, dynamic>)['content'] as String? ??
                  ''
            : '';
        for (final line in userMessage.split('\n')) {
          if (line.startsWith('#R: ')) {
            capturedReference = line.substring(4).trim();
            break;
          }
        }

        final responseJson = json.encode({
          'choices': [
            {
              'message': {'content': '模型A已生效'},
            },
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
        });
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(responseJson);
        await request.response.close();
      });

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
        maxReferenceEntries: 1,
        minCandidateScore: 0,
      );

      final result = await service.correct('莫提斯已经接入');
      expect(result.llmInvoked, isTrue);
      expect(capturedReference, contains('莫提斯->模型A'));
      expect(capturedReference, isNot(contains('莫提斯->模型B')));
    });

    test(
      'normalizes homophonic Chinese variants via one canonical pinyin alias rule',
      () async {
        matcher.buildIndex([
          DictionaryEntry.create(original: '好数连', corrected: 'hao shu lian'),
        ]);

        setupMockServer('好数联和好树练以及号书练都在这里');

        final service = CorrectionService(
          matcher: matcher,
          context: context,
          aiConfig: AiEnhanceConfig(
            agentName: 'test',
            baseUrl: baseUrl,
            apiKey: 'test-key',
            model: 'test-model',
            prompt: '',
          ),
          correctionPrompt: '纠错 prompt',
          maxReferenceEntries: 12,
          minCandidateScore: 0.1,
        );

        final result = await service.correct('好数联和好树练以及号书练都在这里');
        expect(result.text, '好数连和好数连以及好数连都在这里');
      },
    );

    test('context is updated after correction', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);

      setupMockServer('Metis数据');

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      await service.correct('墨提斯数据');
      expect(context.hasContext, isTrue);
      expect(context.segmentCount, 1);
    });

    test('falls back to original text on LLM failure', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);

      // Server returns error
      server.listen((request) async {
        request.response
          ..statusCode = 500
          ..write('Internal Server Error');
        await request.response.close();
      });

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      final result = await service.correct('墨提斯数据');
      // Should fall back to original text
      expect(result.text, '墨提斯数据');
      expect(result.llmInvoked, isFalse);
    });

    test(
      'uses local normalization fallback on LLM failure for homophones',
      () async {
        matcher.buildIndex([
          DictionaryEntry.create(original: '好数连', corrected: 'hao shu lian'),
          DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
        ]);

        server.listen((request) async {
          request.response
            ..statusCode = 500
            ..write('Internal Server Error');
          await request.response.close();
        });

        final service = CorrectionService(
          matcher: matcher,
          context: context,
          aiConfig: AiEnhanceConfig(
            agentName: 'test',
            baseUrl: baseUrl,
            apiKey: 'test-key',
            model: 'test-model',
            prompt: '',
          ),
          correctionPrompt: '纠错 prompt',
        );

        final input = '好数联这个产品跟墨提斯的其他产品不太一样，它是一个底层数据治理工具。';
        final result = await service.correct(input);
        expect(result.text, '好数连这个产品跟墨提斯的其他产品不太一样，它是一个底层数据治理工具。');
        expect(result.llmInvoked, isFalse);
      },
    );

    test('limits #R references by maxReferenceEntries', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '兴阔', corrected: '星阔'),
        DictionaryEntry.create(original: '蓝乔', corrected: '蓝桥'),
        DictionaryEntry.create(original: '云凡', corrected: '云帆'),
      ]);

      String capturedReference = '';
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final payload = json.decode(body) as Map<String, dynamic>;
        final messages = payload['messages'] as List<dynamic>? ?? [];
        final userMessage = messages.isNotEmpty
            ? (messages.last as Map<String, dynamic>)['content'] as String? ??
                  ''
            : '';
        for (final line in userMessage.split('\n')) {
          if (line.startsWith('#R: ')) {
            capturedReference = line.substring(4).trim();
            break;
          }
        }

        final responseJson = json.encode({
          'choices': [
            {
              'message': {'content': '星阔和蓝桥都在开会'},
            },
          ],
          'usage': {'prompt_tokens': 12, 'completion_tokens': 6},
        });
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(responseJson);
        await request.response.close();
      });

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
        maxReferenceEntries: 1,
        minCandidateScore: 0,
      );

      final result = await service.correct('兴阔和蓝乔都在开会');
      expect(result.llmInvoked, isTrue);
      expect(capturedReference, isNotEmpty);
      final refs = capturedReference
          .split('|')
          .where((e) => e.isNotEmpty)
          .toList();
      expect(refs.length, 1);
    });

    test('regression samples: 12 boundary cases', () async {
      final dictionaries = <DictionaryEntry>[
        DictionaryEntry.create(original: '兴阔', corrected: '星阔'),
        DictionaryEntry.create(original: '蓝乔', corrected: '蓝桥'),
        DictionaryEntry.create(original: '云凡', corrected: '云帆'),
        DictionaryEntry.create(original: '云凡平台', corrected: '云帆平台'),
        DictionaryEntry.create(original: '星阔', corrected: 'XingKuo'),
        DictionaryEntry.create(original: 'xing kuo', corrected: '星阔'),
        DictionaryEntry.create(original: 'xing-kuo', corrected: '星阔'),
        DictionaryEntry.create(original: 'xingkuo', corrected: '星阔'),
        DictionaryEntry.create(original: 'sdk', corrected: 'SDK'),
        DictionaryEntry.create(original: 'SDK'),
        DictionaryEntry.create(original: 'OpenAPI'),
        DictionaryEntry.create(original: 'Metis'),
      ];
      matcher.buildIndex(dictionaries);

      final cases = <Map<String, dynamic>>[
        {
          'input': '兴阔今年发布了新产品。',
          'model': '星阔今年发布了新产品。',
          'expected': '星阔今年发布了新产品。',
        },
        {
          'input': '蓝乔的报表系统很稳定。',
          'model': '蓝桥的报表系统很稳定。',
          'expected': '蓝桥的报表系统很稳定。',
        },
        {
          'input': '云凡平台支持实时同步。',
          'model': '云帆平台支持实时同步。',
          'expected': '云帆平台支持实时同步。',
        },
        {
          'input': 'XingKuo 的数据中心上线了。',
          'model': 'XingKuo的数据中心上线了。',
          'expected': '星阔的数据中心上线了。',
        },
        {
          'input': 'xing kuo 本周完成迁移。',
          'model': '星阔本周完成迁移。',
          'expected': '星阔本周完成迁移。',
        },
        {
          'input': 'xing-kuo 报表性能提升明显。',
          'model': '星阔报表性能提升明显。',
          'expected': '星阔报表性能提升明显。',
        },
        {
          'input': '兴阔和蓝乔都在做云凡项目。',
          'model': '星阔和蓝桥都在做云帆项目。',
          'expected': '星阔和蓝桥都在做云帆项目。',
        },
        {
          'input': '今天在 Metis 上跑了任务。',
          'model': '今天在 Metis 上跑了任务。',
          'expected': '今天在 Metis 上跑了任务。',
        },
        {
          'input': 'openapi 文档需要更新。',
          'model': 'OpenAPI 文档需要更新。',
          'expected': 'OpenAPI 文档需要更新。',
        },
        {'input': '库存还有多少？', 'model': '库存还有多少？', 'expected': '库存还有多少？'},
        {
          'input': '公园里有一座蓝色的小桥。',
          'model': '公园里有一座蓝色的小桥。',
          'expected': '公园里有一座蓝色的小桥。',
        },
        {
          'input': 'xing kuo sdk 今天发版。',
          'model': '星阔 SDK 今天发版。',
          'expected': '星阔 SDK 今天发版。',
        },
      ];

      final modelByInput = <String, String>{
        for (final item in cases)
          item['input'] as String: item['model'] as String,
      };

      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final payload = json.decode(body) as Map<String, dynamic>;
        final messages = payload['messages'] as List<dynamic>? ?? [];
        final userMessage = messages.isNotEmpty
            ? (messages.last as Map<String, dynamic>)['content'] as String? ??
                  ''
            : '';
        String input = '';
        for (final line in userMessage.split('\n')) {
          if (line.startsWith('#I: ')) {
            input = line.substring(4).trim();
            break;
          }
        }

        final content = modelByInput[input] ?? input;

        final responseJson = json.encode({
          'choices': [
            {
              'message': {'content': content},
            },
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
        });
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(responseJson);
        await request.response.close();
      });

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
        maxReferenceEntries: 15,
        minCandidateScore: 0,
      );

      for (final item in cases) {
        final result = await service.correct(item['input'] as String);
        expect(result.text, item['expected']);
      }
    });
  });

  group('CorrectionService.correctParagraph', () {
    late PinyinMatcher matcher;
    late CorrectionContext context;
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      matcher = PinyinMatcher();
      context = CorrectionContext();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://localhost:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    void setupMockServer(String responseText) {
      server.listen((request) async {
        final responseJson = json.encode({
          'choices': [
            {
              'message': {'content': responseText},
            },
          ],
          'usage': {'prompt_tokens': 30, 'completion_tokens': 15},
        });
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(responseJson);
        await request.response.close();
      });
    }

    test('returns original text for empty input', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      final result = await service.correctParagraph('');
      expect(result.text, '');
      expect(result.llmInvoked, isFalse);
    });

    test('skips LLM when no dictionary matches', () async {
      matcher.buildIndex([]);

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      final result = await service.correctParagraph('今天天气不错');
      expect(result.text, '今天天气不错');
      expect(result.llmInvoked, isFalse);
    });

    test('calls LLM for paragraph correction', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);

      setupMockServer('段落中提到了Metis平台和其他产品');

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      final result = await service.correctParagraph('段落中提到了墨提斯平台和其他产品');
      expect(result.llmInvoked, isTrue);
      expect(result.totalTokens, greaterThan(0));
    });

    test('does not update context window', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);

      setupMockServer('Metis数据平台是核心');

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      // correctParagraph should NOT update context
      await service.correctParagraph('墨提斯数据平台是核心');
      expect(context.hasContext, isFalse);
      expect(context.segmentCount, 0);
    });

    test('uses previousParagraph as context when provided', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);

      String capturedContext = '';
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final payload = json.decode(body) as Map<String, dynamic>;
        final messages = payload['messages'] as List<dynamic>? ?? [];
        final userMessage = messages.isNotEmpty
            ? (messages.last as Map<String, dynamic>)['content'] as String? ??
                  ''
            : '';
        for (final line in userMessage.split('\n')) {
          if (line.startsWith('#C: ')) {
            capturedContext = line.substring(4).trim();
            break;
          }
        }

        final responseJson = json.encode({
          'choices': [
            {
              'message': {'content': 'Metis结果'},
            },
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
        });
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(responseJson);
        await request.response.close();
      });

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      await service.correctParagraph('墨提斯很好用', previousParagraph: '上一段的内容');
      expect(capturedContext, '上一段的内容');
    });

    test('falls back to original text on LLM error', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);

      server.listen((request) async {
        request.response
          ..statusCode = 500
          ..write('Internal Server Error');
        await request.response.close();
      });

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
      );

      final result = await service.correctParagraph('墨提斯数据');
      expect(result.text, '墨提斯数据');
      expect(result.llmInvoked, isFalse);
    });
  });

  group('CorrectionService with SessionGlossary', () {
    late PinyinMatcher matcher;
    late CorrectionContext context;
    late SessionGlossary glossary;
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      matcher = PinyinMatcher();
      context = CorrectionContext();
      glossary = SessionGlossary();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://localhost:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('injects strong glossary entries into #R', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);

      // Pre-populate glossary with a strong entry
      glossary.override('反软', '帆软');

      String capturedReference = '';
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final payload = json.decode(body) as Map<String, dynamic>;
        final messages = payload['messages'] as List<dynamic>? ?? [];
        final userMessage = messages.isNotEmpty
            ? (messages.last as Map<String, dynamic>)['content'] as String? ??
                  ''
            : '';
        for (final line in userMessage.split('\n')) {
          if (line.startsWith('#R: ')) {
            capturedReference = line.substring(4).trim();
            break;
          }
        }

        final responseJson = json.encode({
          'choices': [
            {
              'message': {'content': 'Metis和帆软都是好产品'},
            },
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
        });
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(responseJson);
        await request.response.close();
      });

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
        sessionGlossary: glossary,
      );

      await service.correct('墨提斯和反软都是好产品');
      // Glossary strong entry should be injected
      expect(capturedReference, contains('反软->帆软'));
      // Dictionary entry should also be present
      expect(capturedReference, contains('墨提斯'));
    });

    test('does not inject weak glossary entries into #R', () async {
      matcher.buildIndex([
        DictionaryEntry.create(original: '墨提斯', corrected: 'Metis'),
      ]);

      // Only one pin — weak entry
      glossary.pin('反软', '帆软');

      String capturedReference = '';
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final payload = json.decode(body) as Map<String, dynamic>;
        final messages = payload['messages'] as List<dynamic>? ?? [];
        final userMessage = messages.isNotEmpty
            ? (messages.last as Map<String, dynamic>)['content'] as String? ??
                  ''
            : '';
        for (final line in userMessage.split('\n')) {
          if (line.startsWith('#R: ')) {
            capturedReference = line.substring(4).trim();
            break;
          }
        }

        final responseJson = json.encode({
          'choices': [
            {
              'message': {'content': 'Metis是好产品'},
            },
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
        });
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(responseJson);
        await request.response.close();
      });

      final service = CorrectionService(
        matcher: matcher,
        context: context,
        aiConfig: AiEnhanceConfig(
          agentName: 'test',
          baseUrl: baseUrl,
          apiKey: 'test-key',
          model: 'test-model',
          prompt: '',
        ),
        correctionPrompt: '纠错 prompt',
        sessionGlossary: glossary,
      );

      await service.correct('墨提斯是好产品');
      // Should NOT contain 反软->帆软 since it's weak
      expect(capturedReference, isNot(contains('反软->帆软')));
    });
  });
}
