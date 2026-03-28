import '../../models/stt_request_context.dart';
import '../log_service.dart';
import '../whisper_cpp_service.dart';
import 'stt_provider.dart';

/// 本地 WhisperCpp FFI STT Provider。
///
/// 通过 whisper.cpp 可执行文件进行本地语音转录。
class WhisperCppSttProvider extends SttProvider {
  WhisperCppSttProvider(super.config);

  @override
  Future<String> transcribe(
    String audioPath, {
    SttRequestContext? context,
  }) async {
    await LogService.info(
      'STT',
      'start whisper.cpp transcribe exec=${config.baseUrl} model=${config.model} file=$audioPath',
    );
    final service = WhisperCppService(
      executablePath: config.baseUrl,
      modelPath: config.model,
    );
    try {
      return await service.transcribe(audioPath, prompt: context?.prompt);
    } on WhisperCppException catch (e) {
      throw SttException(e.message);
    }
  }

  @override
  Future<SttConnectionCheckResult> checkAvailabilityDetailed() async {
    await LogService.info(
      'STT',
      'checkAvailability whisperCpp exec=${config.baseUrl} model=${config.model}',
    );
    final service = WhisperCppService(
      executablePath: config.baseUrl,
      modelPath: config.model,
    );
    final result = await service.checkAvailability();
    return SttConnectionCheckResult(ok: result.ok, message: result.message);
  }
}
