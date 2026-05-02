import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/transcription.dart';

void main() {
  group('Transcription', () {
    final sampleTime = DateTime(2026, 2, 23, 10, 30, 0);

    test('toJson and fromJson round-trip', () {
      final item = Transcription(
        id: 'tx-001',
        text: 'Hello world',
        createdAt: sampleTime,
        duration: const Duration(seconds: 5, milliseconds: 200),
        llmProcessingDuration: const Duration(milliseconds: 3379),
        llmInputTokens: 2552,
        llmOutputTokens: 211,
        provider: 'Z.ai',
        model: 'GLM-ASR-2512',
        providerConfigJson: '{"key":"value"}',
      );

      final json = item.toJson();
      final restored = Transcription.fromJson(json);

      expect(restored.id, item.id);
      expect(restored.text, item.text);
      expect(restored.createdAt, item.createdAt);
      expect(restored.duration.inMilliseconds, item.duration.inMilliseconds);
      expect(
        restored.llmProcessingDuration?.inMilliseconds,
        item.llmProcessingDuration?.inMilliseconds,
      );
      expect(restored.llmInputTokens, item.llmInputTokens);
      expect(restored.llmOutputTokens, item.llmOutputTokens);
      expect(restored.provider, item.provider);
      expect(restored.model, item.model);
      expect(restored.providerConfigJson, item.providerConfigJson);
    });

    test('toDb and fromDb round-trip', () {
      final item = Transcription(
        id: 'tx-002',
        text: '测试中文文本',
        createdAt: sampleTime,
        duration: const Duration(seconds: 10),
        llmProcessingDuration: const Duration(milliseconds: 2945),
        llmInputTokens: 2557,
        llmOutputTokens: 178,
        provider: 'Aliyun',
        model: 'qwen3-asr-flash',
        providerConfigJson: '{}',
      );

      final dbMap = item.toDb();
      final restored = Transcription.fromDb(dbMap);

      expect(restored.id, item.id);
      expect(restored.text, item.text);
      expect(restored.createdAt, item.createdAt);
      expect(restored.duration.inMilliseconds, item.duration.inMilliseconds);
      expect(
        restored.llmProcessingDuration?.inMilliseconds,
        item.llmProcessingDuration?.inMilliseconds,
      );
      expect(restored.llmInputTokens, item.llmInputTokens);
      expect(restored.llmOutputTokens, item.llmOutputTokens);
      expect(restored.provider, item.provider);
      expect(restored.model, item.model);
      expect(restored.providerConfigJson, item.providerConfigJson);
    });

    test('toJson produces expected keys', () {
      final item = Transcription(
        id: 'tx-003',
        text: 'test',
        createdAt: sampleTime,
        duration: const Duration(milliseconds: 3500),
        provider: 'test',
        model: 'model',
        providerConfigJson: '{}',
      );

      final json = item.toJson();

      expect(json, containsPair('id', 'tx-003'));
      expect(json, containsPair('text', 'test'));
      expect(json, containsPair('createdAt', sampleTime.toIso8601String()));
      expect(json, containsPair('duration', 3500));
      expect(json, containsPair('llmProcessingDuration', null));
      expect(json, containsPair('llmInputTokens', null));
      expect(json, containsPair('llmOutputTokens', null));
      expect(json, containsPair('provider', 'test'));
      expect(json, containsPair('model', 'model'));
      expect(json, containsPair('providerConfigJson', '{}'));
    });

    test('toDb produces expected column names', () {
      final item = Transcription(
        id: 'tx-004',
        text: 'test',
        createdAt: sampleTime,
        duration: const Duration(milliseconds: 7800),
        provider: 'test',
        model: 'model',
        providerConfigJson: '{}',
      );

      final dbMap = item.toDb();

      expect(dbMap, containsPair('id', 'tx-004'));
      expect(dbMap, containsPair('text', 'test'));
      expect(dbMap, containsPair('created_at', sampleTime.toIso8601String()));
      expect(dbMap, containsPair('duration_ms', 7800));
      expect(dbMap, containsPair('llm_processing_duration_ms', null));
      expect(dbMap, containsPair('llm_input_tokens', null));
      expect(dbMap, containsPair('llm_output_tokens', null));
      expect(dbMap, containsPair('provider', 'test'));
      expect(dbMap, containsPair('model', 'model'));
      expect(dbMap, containsPair('provider_config', '{}'));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'tx-005',
        'text': 'hello',
        'createdAt': sampleTime.toIso8601String(),
        'duration': 1000,
        'provider': 'test',
      };

      final item = Transcription.fromJson(json);

      expect(item.model, '');
      expect(item.providerConfigJson, '{}');
      expect(item.llmProcessingDuration, isNull);
      expect(item.llmInputTokens, isNull);
      expect(item.llmOutputTokens, isNull);
    });

    test('fromDb handles missing optional columns', () {
      final row = {
        'id': 'tx-006',
        'text': 'hello',
        'created_at': sampleTime.toIso8601String(),
        'duration_ms': 2000,
        'provider': 'test',
        'model': null,
        'provider_config': null,
      };

      final item = Transcription.fromDb(row);

      expect(item.model, '');
      expect(item.providerConfigJson, '{}');
      expect(item.llmProcessingDuration, isNull);
      expect(item.llmInputTokens, isNull);
      expect(item.llmOutputTokens, isNull);
    });
  });
}
