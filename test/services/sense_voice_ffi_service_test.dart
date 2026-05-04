import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/services/sense_voice_ffi_service.dart';

void main() {
  group('SenseVoice model catalog', () {
    test('includes int8 and full precision local download options', () {
      final models = {
        for (final model in kSenseVoiceModels) model.fileName: model,
      };

      expect(models, contains('sense-voice-zh-en'));
      expect(models, contains('sense-voice-zh-en-fp32'));
      expect(models['sense-voice-zh-en']!.modelFileName, 'model.int8.onnx');
      expect(models['sense-voice-zh-en-fp32']!.modelFileName, 'model.onnx');
      expect(
        models['sense-voice-zh-en-fp32']!.approximateSizeMB,
        greaterThan(800),
      );
    });

    test('each catalog item has download hosts and required files', () {
      for (final model in kSenseVoiceModels) {
        expect(model.hosts, isNotEmpty);
        expect(model.requiredFileNames, contains('tokens.txt'));
        expect(model.requiredFileNames, contains(model.modelFileName));
      }
    });
  });
}
