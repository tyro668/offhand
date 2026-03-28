import '../../models/stt_request_context.dart';
import '../log_service.dart';
import '../sense_voice_ffi_service.dart';
import 'stt_provider.dart';

class SenseVoiceSttProvider extends SttProvider {
  SenseVoiceSttProvider(super.config);

  @override
  Future<String> transcribe(
    String audioPath, {
    SttRequestContext? context,
  }) async {
    await LogService.info(
      'STT',
      'start sensevoice transcribe model=${config.model} file=$audioPath',
    );

    final service = SenseVoiceFfiService(modelPath: config.model);
    try {
      return await service.transcribe(audioPath, prompt: context?.prompt);
    } on SenseVoiceException catch (e) {
      throw SttException(e.message);
    }
  }

  @override
  Future<SttConnectionCheckResult> checkAvailabilityDetailed() async {
    await LogService.info(
      'STT',
      'checkAvailability sensevoice model=${config.model}',
    );

    final service = SenseVoiceFfiService(modelPath: config.model);
    final result = await service.checkAvailability();
    return SttConnectionCheckResult(ok: result.ok, message: result.message);
  }
}
