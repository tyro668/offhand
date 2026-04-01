import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/provider_config.dart';

void main() {
  group('SttProviderConfig', () {
    test('toJson and fromJson round-trip', () {
      const config = SttProviderConfig(
        type: SttProviderType.cloud,
        name: 'Z.ai',
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        apiKey: 'test-key',
        model: 'GLM-ASR-2512',
      );

      final json = config.toJson();
      final restored = SttProviderConfig.fromJson(json);

      expect(restored.type, config.type);
      expect(restored.name, config.name);
      expect(restored.baseUrl, config.baseUrl);
      expect(restored.apiKey, config.apiKey);
      expect(restored.model, config.model);
    });

    test('copyWith creates modified copy', () {
      const original = SttProviderConfig(
        type: SttProviderType.cloud,
        name: 'Test',
        baseUrl: 'https://example.com',
        apiKey: 'key1',
        model: 'model1',
      );

      final modified = original.copyWith(apiKey: 'key2', model: 'model2');

      expect(modified.type, original.type);
      expect(modified.name, original.name);
      expect(modified.baseUrl, original.baseUrl);
      expect(modified.apiKey, 'key2');
      expect(modified.model, 'model2');
      expect(modified.availableModels, original.availableModels);
    });

    test('fallbackPresets are valid', () {
      final presets = SttProviderConfig.fallbackPresets;

      expect(presets, isNotEmpty);
      for (final preset in presets) {
        expect(preset.name, isNotEmpty);
        // 本地 sherpa-onnx 类型的 baseUrl 可以为空。
        if (preset.type != SttProviderType.senseVoice) {
          expect(preset.baseUrl, isNotEmpty);
        }
        expect(preset.model, isNotEmpty);
        expect(preset.availableModels, isNotEmpty);
      }
    });

    test('fromPresetJsonList parses valid input', () {
      final jsonList = [
        {
          'name': 'Custom',
          'baseUrl': 'https://custom.example.com/v1',
          'type': 'cloud',
          'defaultModel': 'custom-model',
          'models': [
            {'id': 'custom-model', 'description': 'A custom model'},
          ],
        },
      ];

      final presets = SttProviderConfig.fromPresetJsonList(jsonList);

      expect(presets.length, 1);
      expect(presets[0].name, 'Custom');
      expect(presets[0].baseUrl, 'https://custom.example.com/v1');
      expect(presets[0].model, 'custom-model');
      expect(presets[0].availableModels.length, 1);
      expect(presets[0].availableModels[0].id, 'custom-model');
    });

    test('fromPresetJsonList filters out invalid entries', () {
      final jsonList = [
        {'name': '', 'baseUrl': 'https://example.com', 'defaultModel': 'm'},
        {'name': 'Valid', 'baseUrl': '', 'defaultModel': 'm'},
        {
          'name': 'Good',
          'baseUrl': 'https://example.com',
          'defaultModel': 'model',
          'models': [
            {'id': 'model', 'description': 'desc'},
          ],
        },
      ];

      final presets = SttProviderConfig.fromPresetJsonList(jsonList);

      expect(presets.length, 1);
      expect(presets[0].name, 'Good');
    });

    test('fromPresetJsonList with whisper type falls back to cloud', () {
      final jsonList = [
        {
          'name': 'Local Whisper',
          'baseUrl': 'http://localhost:8080/v1',
          'type': 'whisper',
          'defaultModel': 'whisper-1',
          'models': [
            {'id': 'whisper-1', 'description': 'Whisper'},
          ],
        },
      ];

      final presets = SttProviderConfig.fromPresetJsonList(jsonList);

      expect(presets[0].type, SttProviderType.cloud);
    });
  });

  group('SttModel', () {
    test('fromJson parses correctly', () {
      final model = SttModel.fromJson({
        'id': 'test-model',
        'description': 'A test model',
      });

      expect(model.id, 'test-model');
      expect(model.description, 'A test model');
    });

    test('fromJson handles missing fields', () {
      final model = SttModel.fromJson({});

      expect(model.id, '');
      expect(model.description, '');
    });
  });
}
