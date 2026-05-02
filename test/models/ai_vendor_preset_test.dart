import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/models/ai_vendor_preset.dart';

void main() {
  group('AiVendorPreset', () {
    test('fallbackPresets are valid', () {
      final presets = AiVendorPreset.fallbackPresets;

      expect(presets, isNotEmpty);
      for (final preset in presets) {
        expect(preset.name, isNotEmpty);
        expect(preset.baseUrl, isNotEmpty);
        expect(preset.models, isNotEmpty);
      }
    });

    test('defaultModelId uses override when set', () {
      const preset = AiVendorPreset(
        name: 'Test',
        baseUrl: 'https://example.com',
        models: [
          AiModel(id: 'model-a', description: 'A'),
          AiModel(id: 'model-b', description: 'B'),
        ],
        defaultModelIdOverride: 'model-b',
      );

      expect(preset.defaultModelId, 'model-b');
    });

    test('defaultModelId uses first model when no override', () {
      const preset = AiVendorPreset(
        name: 'Test',
        baseUrl: 'https://example.com',
        models: [
          AiModel(id: 'model-a', description: 'A'),
          AiModel(id: 'model-b', description: 'B'),
        ],
      );

      expect(preset.defaultModelId, 'model-a');
    });

    test('fromPresetJsonList parses valid data', () {
      final jsonList = [
        {
          'name': 'Custom Vendor',
          'baseUrl': 'https://api.custom.com/v1',
          'defaultModel': 'custom-model',
          'models': [
            {'id': 'custom-model', 'description': 'Custom LLM'},
            {'id': 'custom-model-2', 'description': 'Custom LLM 2'},
          ],
        },
      ];

      final presets = AiVendorPreset.fromPresetJsonList(jsonList);

      expect(presets.length, 1);
      expect(presets[0].name, 'Custom Vendor');
      expect(presets[0].baseUrl, 'https://api.custom.com/v1');
      expect(presets[0].models.length, 2);
      expect(presets[0].defaultModelId, 'custom-model');
    });

    test('fromPresetJsonList filters out invalid entries', () {
      final jsonList = [
        {'name': '', 'baseUrl': 'https://example.com', 'models': []},
        {
          'name': 'Empty Url',
          'baseUrl': '',
          'models': [
            {'id': 'm', 'description': 'd'},
          ],
        },
        {'name': 'No Models', 'baseUrl': 'https://example.com', 'models': []},
        {
          'name': 'Valid',
          'baseUrl': 'https://example.com',
          'models': [
            {'id': 'm', 'description': 'd'},
          ],
        },
      ];

      final presets = AiVendorPreset.fromPresetJsonList(jsonList);

      expect(presets.length, 1);
      expect(presets[0].name, 'Valid');
    });

    test('fromPresetJsonList handles missing defaultModel', () {
      final jsonList = [
        {
          'name': 'NoDefault',
          'baseUrl': 'https://example.com',
          'models': [
            {'id': 'first', 'description': 'desc'},
          ],
        },
      ];

      final presets = AiVendorPreset.fromPresetJsonList(jsonList);

      expect(presets[0].defaultModelId, 'first');
    });

    test('fromPresetJsonList ignores invalid defaultModel reference', () {
      final jsonList = [
        {
          'name': 'BadRef',
          'baseUrl': 'https://example.com',
          'defaultModel': 'non-existent-model',
          'models': [
            {'id': 'actual', 'description': 'desc'},
          ],
        },
      ];

      final presets = AiVendorPreset.fromPresetJsonList(jsonList);

      // defaultModel 'non-existent-model' doesn't match any model id,
      // so override should be null and first model used
      expect(presets[0].defaultModelId, 'actual');
    });

    test('fromPresetJsonList filters out local model with empty baseUrl', () {
      final jsonList = [
        {
          'name': '本地模型',
          'baseUrl': '',
          'isLocal': true,
          'models': [
            {'id': 'model.gguf', 'description': 'Local model'},
          ],
        },
      ];

      final presets = AiVendorPreset.fromPresetJsonList(jsonList);

      expect(presets, isEmpty);
    });
  });

  group('AiModel', () {
    test('fromJson parses correctly', () {
      final model = AiModel.fromJson({
        'id': 'gpt-4',
        'description': 'GPT-4 model',
      });

      expect(model.id, 'gpt-4');
      expect(model.description, 'GPT-4 model');
    });

    test('fromJson handles missing fields', () {
      final model = AiModel.fromJson({});

      expect(model.id, '');
      expect(model.description, '');
    });
  });
}
