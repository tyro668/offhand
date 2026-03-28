import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart' as whisper_lib;
import 'log_service.dart';

/// 可下载的模型定义
class WhisperModel {
  final String fileName;
  final String url;
  final String description;
  final int approximateSizeMB;
  final WhisperModelType modelType;

  const WhisperModel({
    required this.fileName,
    required this.url,
    required this.description,
    required this.approximateSizeMB,
    required this.modelType,
  });
}

/// 模型类型枚举，与 whisper_flutter_new 的 WhisperModel 对应
enum WhisperModelType { tiny, base, small }

/// 模型下载镜像源（按优先级排列，国内镜像优先）
const _kModelDownloadHosts = [
  'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main',
  'https://huggingface.co/ggerganov/whisper.cpp/resolve/main',
];

/// 预定义可下载模型列表
const kWhisperModels = [
  WhisperModel(
    fileName: 'ggml-tiny.bin',
    url: 'ggml-tiny.bin',
    description: 'Tiny (~75MB) - 速度最快，适合日常使用',
    approximateSizeMB: 75,
    modelType: WhisperModelType.tiny,
  ),
  WhisperModel(
    fileName: 'ggml-base.bin',
    url: 'ggml-base.bin',
    description: 'Base (~142MB) - 平衡速度与准确率',
    approximateSizeMB: 142,
    modelType: WhisperModelType.base,
  ),
  WhisperModel(
    fileName: 'ggml-small.bin',
    url: 'ggml-small.bin',
    description: 'Small (~466MB) - 更高准确率',
    approximateSizeMB: 466,
    modelType: WhisperModelType.small,
  ),
];

/// 通过 whisper_flutter_new (FFI) 调用 whisper.cpp 进行语音转文字
class WhisperCppService {
  /// 模型文件名（如 ggml-tiny.bin）
  final String modelPath;

  WhisperCppService({
    String executablePath = '',
    required this.modelPath,
  });
  // executablePath 保留参数兼容性，但 FFI 模式下不再使用

  /// 获取应用数据根目录
  static Future<String> get _appDataDir async {
    final appDir = await getApplicationSupportDirectory();
    return appDir.path;
  }

  /// 获取默认模型目录
  static Future<String> get defaultModelDir async {
    final root = await _appDataDir;
    return p.join(root, 'models');
  }

  /// 检查模型文件是否已存在
  static Future<bool> isModelDownloaded(String fileName) async {
    final dir = await defaultModelDir;
    return File(p.join(dir, fileName)).exists();
  }

  /// 获取模型文件完整路径
  static Future<String> modelFilePath(String fileName) async {
    final dir = await defaultModelDir;
    return p.join(dir, fileName);
  }

  /// 下载模型文件，自动尝试多个镜像源，通过 onProgress 回调报告进度 (0.0 ~ 1.0)
  static Future<void> downloadModel(
    WhisperModel model, {
    required void Function(double progress) onProgress,
    void Function(String message)? onStatus,
  }) async {
    final dir = await defaultModelDir;
    await Directory(dir).create(recursive: true);
    final filePath = p.join(dir, model.fileName);
    final tmpPath = '$filePath.tmp';

    String? lastError;

    for (var i = 0; i < _kModelDownloadHosts.length; i++) {
      final host = _kModelDownloadHosts[i];
      final url = '$host/${model.fileName}';
      final hostLabel = Uri.parse(host).host;

      await LogService.info('WHISPER_CPP', 'trying mirror ${i + 1}/${_kModelDownloadHosts.length}: $url');
      onStatus?.call('正在连接 $hostLabel ...');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);

      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close().timeout(const Duration(seconds: 30));

        if (response.statusCode != 200) {
          await response.drain<void>();
          lastError = 'HTTP ${response.statusCode} from $hostLabel';
          await LogService.info('WHISPER_CPP', 'mirror $hostLabel failed: $lastError');
          client.close();
          continue;
        }

        onStatus?.call('正在从 $hostLabel 下载...');
        final totalBytes = response.contentLength;
        var receivedBytes = 0;
        final sink = File(tmpPath).openWrite();
        var lastProgressTime = DateTime.now();

        try {
          await for (final chunk in response) {
            sink.add(chunk);
            receivedBytes += chunk.length;

            // 检测下载是否卡住（30秒无新数据视为超时）
            final now = DateTime.now();
            if (now.difference(lastProgressTime).inSeconds > 30 && receivedBytes > 0) {
              throw TimeoutException('下载停滞超过30秒');
            }
            lastProgressTime = now;

            if (totalBytes > 0) {
              onProgress(receivedBytes / totalBytes);
            }
          }
          await sink.flush();
          await sink.close();
        } catch (e) {
          await sink.close();
          try { await File(tmpPath).delete(); } catch (_) {}
          lastError = '$hostLabel: $e';
          await LogService.info('WHISPER_CPP', 'download from $hostLabel interrupted: $e');
          client.close();
          continue;
        }

        // 下载完成，重命名
        await File(tmpPath).rename(filePath);
        await LogService.info('WHISPER_CPP', 'download complete from $hostLabel: $filePath ($receivedBytes bytes)');
        client.close();
        return; // 成功，退出
      } on TimeoutException {
        lastError = '$hostLabel 连接超时';
        await LogService.info('WHISPER_CPP', 'mirror $hostLabel timeout');
        client.close();
        continue;
      } on SocketException catch (e) {
        lastError = '$hostLabel 网络错误: ${e.message}';
        await LogService.info('WHISPER_CPP', 'mirror $hostLabel socket error: ${e.message}');
        client.close();
        continue;
      } catch (e) {
        lastError = '$hostLabel: $e';
        await LogService.info('WHISPER_CPP', 'mirror $hostLabel error: $e');
        client.close();
        continue;
      }
    }

    // 所有镜像都失败
    try { await File(tmpPath).delete(); } catch (_) {}
    throw WhisperCppException('所有下载源均失败，请检查网络连接\n最后错误: $lastError');
  }

  /// 删除已下载的模型文件
  static Future<void> deleteModel(String fileName) async {
    final dir = await defaultModelDir;
    final file = File(p.join(dir, fileName));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 将模型文件名映射到 whisper_flutter_new 的 WhisperModel 枚举
  static whisper_lib.WhisperModel _toLibraryModel(String fileName) {
    switch (fileName) {
      case 'ggml-tiny.bin':
        return whisper_lib.WhisperModel.tiny;
      case 'ggml-base.bin':
        return whisper_lib.WhisperModel.base;
      case 'ggml-small.bin':
        return whisper_lib.WhisperModel.small;
      default:
        return whisper_lib.WhisperModel.none;
    }
  }

  /// 解析模型完整路径
  Future<String> _resolveModelPath() async {
    if (p.isAbsolute(modelPath)) return modelPath;
    final dir = await defaultModelDir;
    return p.join(dir, modelPath);
  }

  /// 转录音频文件，返回识别文本（通过 FFI 调用 whisper.cpp）
  Future<String> transcribe(String audioPath, {String? prompt}) async {
    final resolvedModel = await _resolveModelPath();

    await LogService.info(
      'WHISPER_CPP',
      'transcribe (FFI) model=$resolvedModel audio=$audioPath prompt=${(prompt ?? '').trim().isNotEmpty}',
    );

    if (!await File(resolvedModel).exists()) {
      throw WhisperCppException(
        '模型文件不存在: $resolvedModel\n'
        '请在设置中下载语音识别模型',
      );
    }

    if (!await File(audioPath).exists()) {
      throw WhisperCppException('音频文件不存在: $audioPath');
    }

    // 确保音频为 wav 格式
    final wavPath = await _convertToWav16k(audioPath);

    try {
      final libraryModel = _toLibraryModel(modelPath);
      final modelDir = await defaultModelDir;

      final whisper = whisper_lib.Whisper(
        model: libraryModel,
        modelDir: libraryModel == whisper_lib.WhisperModel.none ? p.dirname(resolvedModel) : modelDir,
      );

      final response = await whisper.transcribe(
        transcribeRequest: whisper_lib.TranscribeRequest(
          audio: wavPath,
          isNoTimestamps: true,
          language: 'zh',
        ),
      );

      final text = response.text.trim();
      await LogService.info(
        'WHISPER_CPP',
        'transcribe result: ${text.length > 100 ? text.substring(0, 100) : text}',
      );
      return text;
    } catch (e) {
      await LogService.error('WHISPER_CPP', 'transcribe failed: $e');
      if (e is WhisperCppException) rethrow;
      throw WhisperCppException('语音识别失败: $e');
    } finally {
      if (wavPath != audioPath) {
        File(wavPath).delete().ignore();
      }
    }
  }

  /// 使用 ffmpeg 将音频转换为 whisper.cpp 要求的 16kHz 单声道 WAV
  Future<String> _convertToWav16k(String inputPath) async {
    if (inputPath.endsWith('.wav')) {
      return inputPath;
    }

    final outputPath = '${inputPath}_16k.wav';

    try {
      final result = await Process.run('ffmpeg', [
        '-y',
        '-i', inputPath,
        '-ar', '16000',
        '-ac', '1',
        '-c:a', 'pcm_s16le',
        outputPath,
      ]).timeout(const Duration(seconds: 30));

      if (result.exitCode == 0 && await File(outputPath).exists()) {
        return outputPath;
      }
    } catch (_) {
      await LogService.info('WHISPER_CPP', 'ffmpeg not available, using original audio file');
    }

    return inputPath;
  }

  /// 检查本地模型是否可用
  Future<WhisperCppCheckResult> checkAvailability() async {
    try {
      final resolvedModel = await _resolveModelPath();
      if (!await File(resolvedModel).exists()) {
        return WhisperCppCheckResult(
          ok: false,
          message: '模型文件不存在: $resolvedModel\n请在设置中下载语音识别模型',
        );
      }

      return WhisperCppCheckResult(
        ok: true,
        message: '本地模型就绪 (模型: $resolvedModel)',
      );
    } on WhisperCppException catch (e) {
      return WhisperCppCheckResult(ok: false, message: e.message);
    } catch (e) {
      return WhisperCppCheckResult(ok: false, message: '检查失败: $e');
    }
  }
}

class WhisperCppCheckResult {
  final bool ok;
  final String message;
  const WhisperCppCheckResult({required this.ok, required this.message});
}

class WhisperCppException implements Exception {
  final String message;
  WhisperCppException(this.message);

  @override
  String toString() => message;
}
