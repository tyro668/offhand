import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'log_service.dart';

/// SenseVoice 模型描述（ONNX 格式，目录包含 model.int8.onnx + tokens.txt）
class SenseVoiceModel {
  final String fileName; // 模型目录名
  final String description;
  final int approximateSizeMB;

  const SenseVoiceModel({
    required this.fileName,
    required this.description,
    required this.approximateSizeMB,
  });
}

/// 模型目录内需要下载的文件
const _kModelFiles = [
  _ModelFileSpec(name: 'model.int8.onnx', isLarge: true),
  _ModelFileSpec(name: 'tokens.txt', isLarge: false),
];

class _ModelFileSpec {
  final String name;
  final bool isLarge;
  const _ModelFileSpec({required this.name, required this.isLarge});
}

/// 下载源（优先使用镜像）
const _kModelHosts = [
  'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main',
  'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main',
];

const kSenseVoiceModels = [
  SenseVoiceModel(
    fileName: 'sense-voice-zh-en',
    description: 'SenseVoice 多语种 INT8 (~250MB) - 中/英/日/韩/粤',
    approximateSizeMB: 250,
  ),
];

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class SenseVoiceFfiService {
  final String modelPath;

  SenseVoiceFfiService({required this.modelPath});

  static bool _bindingsInitialized = false;

  static Future<String> get _appDataDir async {
    final appDir = await getApplicationSupportDirectory();
    return appDir.path;
  }

  static Future<String> get defaultModelDir async {
    final root = await _appDataDir;
    return p.join(root, 'models');
  }

  /// 检查模型目录内是否包含所有必需文件
  static Future<bool> isModelDownloaded(String fileName) async {
    final dir = await defaultModelDir;
    final modelDir = p.join(dir, fileName);
    for (final spec in _kModelFiles) {
      if (!await File(p.join(modelDir, spec.name)).exists()) return false;
    }
    return true;
  }

  static Future<String> modelFilePath(String fileName) async {
    final dir = await defaultModelDir;
    return p.join(dir, fileName);
  }

  // ---- 下载 ----

  static Future<void> downloadModel(
    SenseVoiceModel model, {
    required void Function(double progress) onProgress,
    void Function(String message)? onStatus,
  }) async {
    final dir = await defaultModelDir;
    final modelDir = p.join(dir, model.fileName);
    await Directory(modelDir).create(recursive: true);

    // large 文件占 95% 进度，small 文件占 5%
    final largeCount = _kModelFiles.where((f) => f.isLarge).length;
    final smallCount = _kModelFiles.length - largeCount;
    final largeWeight = smallCount > 0 ? 0.95 / largeCount : 1.0 / largeCount;
    final smallWeight = largeCount > 0 ? 0.05 / smallCount : 1.0 / smallCount;

    var cumulativeProgress = 0.0;

    for (final spec in _kModelFiles) {
      final filePath = p.join(modelDir, spec.name);

      if (await File(filePath).exists()) {
        final w = spec.isLarge ? largeWeight : smallWeight;
        cumulativeProgress += w;
        onProgress(cumulativeProgress.clamp(0.0, 1.0));
        continue;
      }

      onStatus?.call('正在下载 ${spec.name} ...');
      final w = spec.isLarge ? largeWeight : smallWeight;
      final base = cumulativeProgress;

      await _downloadFileWithMirrors(
        spec.name,
        filePath,
        onProgress: (p) {
          onProgress((base + w * p).clamp(0.0, 1.0));
        },
        onStatus: onStatus,
      );

      cumulativeProgress += w;
      onProgress(cumulativeProgress.clamp(0.0, 1.0));
    }

    onProgress(1.0);
  }

  static Future<void> _downloadFileWithMirrors(
    String fileName,
    String destPath, {
    required void Function(double progress) onProgress,
    void Function(String message)? onStatus,
  }) async {
    final tmpPath = '$destPath.tmp';
    String? lastError;

    for (var i = 0; i < _kModelHosts.length; i++) {
      final host = _kModelHosts[i];
      final url = '$host/$fileName';
      final hostLabel = Uri.parse(host).host;

      await LogService.info(
        'SENSEVOICE',
        'trying mirror ${i + 1}/${_kModelHosts.length}: $url',
      );
      onStatus?.call('正在连接 $hostLabel ...');

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);

      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );

        if (response.statusCode != 200 &&
            response.statusCode != 302 &&
            response.statusCode != 307) {
          await response.drain<void>();
          lastError = 'HTTP ${response.statusCode} from $hostLabel';
          client.close();
          continue;
        }

        // 处理重定向
        if (response.statusCode == 302 || response.statusCode == 307) {
          final redirectUrl = response.headers.value('location');
          if (redirectUrl != null) {
            await response.drain<void>();
            final req2 = await client.getUrl(Uri.parse(redirectUrl));
            final resp2 = await req2.close().timeout(
              const Duration(seconds: 30),
            );
            if (resp2.statusCode != 200) {
              await resp2.drain<void>();
              lastError = 'HTTP ${resp2.statusCode} from redirect';
              client.close();
              continue;
            }
            await _saveResponse(resp2, tmpPath, onProgress);
            client.close();
            await File(tmpPath).rename(destPath);
            await LogService.info('SENSEVOICE', 'download complete: $destPath');
            return;
          }
        }

        onStatus?.call('正在从 $hostLabel 下载 $fileName ...');
        await _saveResponse(response, tmpPath, onProgress);
        client.close();
        await File(tmpPath).rename(destPath);

        await LogService.info('SENSEVOICE', 'download complete: $destPath');
        return;
      } on TimeoutException {
        lastError = '$hostLabel 连接超时';
        client.close();
        continue;
      } on SocketException catch (e) {
        lastError = '$hostLabel 网络错误: ${e.message}';
        client.close();
        continue;
      } catch (e) {
        lastError = '$hostLabel: $e';
        client.close();
        continue;
      }
    }

    try {
      await File(tmpPath).delete();
    } catch (_) {}
    throw SenseVoiceException('下载 $fileName 失败，请检查网络连接\n最后错误: $lastError');
  }

  static Future<void> _saveResponse(
    HttpClientResponse response,
    String tmpPath,
    void Function(double progress) onProgress,
  ) async {
    final totalBytes = response.contentLength;
    var receivedBytes = 0;
    final sink = File(tmpPath).openWrite();

    try {
      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress(receivedBytes / totalBytes);
        }
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close();
      try {
        await File(tmpPath).delete();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> deleteModel(String fileName) async {
    final dir = await defaultModelDir;
    final modelDir = Directory(p.join(dir, fileName));
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
  }

  // ---- 推理 ----

  Future<String> _resolveModelDir() async {
    if (p.isAbsolute(modelPath) && await Directory(modelPath).exists()) {
      return modelPath;
    }
    final dir = await defaultModelDir;
    return p.join(dir, modelPath);
  }

  /// 使用 sherpa-onnx 进行语音转文字
  Future<String> transcribe(String audioPath, {String? prompt}) async {
    final modelDir = await _resolveModelDir();

    await LogService.info(
      'SENSEVOICE',
      'transcribe (sherpa-onnx) modelDir=$modelDir audio=$audioPath prompt=${(prompt ?? '').trim().isNotEmpty}',
    );

    final modelFile = p.join(modelDir, 'model.int8.onnx');
    final tokensFile = p.join(modelDir, 'tokens.txt');

    if (!await File(modelFile).exists()) {
      throw SenseVoiceException('模型文件不存在: $modelFile\n请在设置中下载 SenseVoice 模型');
    }

    if (!await File(tokensFile).exists()) {
      throw SenseVoiceException(
        'tokens 文件不存在: $tokensFile\n请在设置中重新下载 SenseVoice 模型',
      );
    }

    if (!await File(audioPath).exists()) {
      throw SenseVoiceException('音频文件不存在: $audioPath');
    }

    try {
      // 初始化 sherpa-onnx bindings（仅一次）
      if (!_bindingsInitialized) {
        sherpa.initBindings();
        _bindingsInitialized = true;
      }

      // ---- 使用纯 Dart 读取 WAV（兼容 WAVE_FORMAT_EXTENSIBLE / JUNK chunk 等非标格式）----
      final wavResult = await _readWavDart(audioPath);
      var samples = wavResult.$1;
      final fileSampleRate = wavResult.$2;

      await LogService.info(
        'SENSEVOICE',
        'readWavDart done: samples=${samples.length}, sampleRate=$fileSampleRate',
      );

      if (samples.isEmpty) {
        throw SenseVoiceException('读取音频失败（samples=0）\n文件路径: $audioPath');
      }

      // 如果采样率不是 16 kHz，进行重采样
      const targetRate = 16000;
      if (fileSampleRate != targetRate) {
        await LogService.info(
          'SENSEVOICE',
          'resampling from $fileSampleRate Hz to $targetRate Hz',
        );
        samples = _resample(samples, fileSampleRate, targetRate);
      }

      // 构造离线识别配置 — 模型目录需使用 ASCII 安全路径
      final safeModelDir = await _ensureAsciiDir(modelDir);
      final safeModelFile = p.join(safeModelDir, 'model.int8.onnx');
      final safeTokensFile = p.join(safeModelDir, 'tokens.txt');

      final config = sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(
            model: safeModelFile,
            language: 'auto',
            useInverseTextNormalization: true,
          ),
          tokens: safeTokensFile,
          numThreads: 4,
          debug: false,
        ),
      );

      // 创建识别器
      final recognizer = sherpa.OfflineRecognizer(config);
      final stream = recognizer.createStream();

      // 输入音频并解码
      stream.acceptWaveform(samples: samples, sampleRate: targetRate);
      recognizer.decode(stream);

      // 取结果
      final result = recognizer.getResult(stream);
      final text = result.text.trim();

      // 释放原生资源
      stream.free();
      recognizer.free();

      // 清理模型目录软链
      if (safeModelDir != modelDir) {
        Link(safeModelDir).delete().ignore();
      }

      if (text.isEmpty) {
        throw SenseVoiceException('SenseVoice 返回空文本');
      }

      await LogService.info(
        'SENSEVOICE',
        'transcribe result (lang=${result.lang}, emotion=${result.emotion}): '
            '${text.length > 100 ? text.substring(0, 100) : text}',
      );

      return text;
    } catch (e) {
      await LogService.error('SENSEVOICE', 'transcribe failed: $e');
      if (e is SenseVoiceException) rethrow;
      throw SenseVoiceException('SenseVoice 转写失败: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 纯 Dart WAV 读取 — 兼容 WAVE_FORMAT_EXTENSIBLE (0xFFFE) 及 JUNK 等非标 chunk
  // ---------------------------------------------------------------------------

  /// 读取 WAV 文件，返回 (单声道 Float32List 样本, 采样率)。
  /// 支持标准 PCM (0x0001)、IEEE Float (0x0003) 及 WAVE_FORMAT_EXTENSIBLE (0xFFFE)。
  static Future<(Float32List, int)> _readWavDart(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    if (bytes.length < 44) {
      throw SenseVoiceException('WAV 文件过小 (${bytes.length} bytes)');
    }

    final data = ByteData.sublistView(bytes);

    // 验证 RIFF / WAVE 签名
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') {
      throw SenseVoiceException('不是有效的 WAV 文件 (header: $riff / $wave)');
    }

    int offset = 12;
    int? sampleRate;
    int? numChannels;
    int? bitsPerSample;
    int? audioFormat; // 1=PCM, 3=IEEE Float
    Float32List? samples;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (chunkId == 'fmt ') {
        if (chunkSize < 16) {
          throw SenseVoiceException('WAV: fmt chunk 过短 ($chunkSize)');
        }
        audioFormat = data.getUint16(offset, Endian.little);
        numChannels = data.getUint16(offset + 2, Endian.little);
        sampleRate = data.getUint32(offset + 4, Endian.little);
        // offset+8: byteRate, offset+12: blockAlign
        bitsPerSample = data.getUint16(offset + 14, Endian.little);

        // WAVE_FORMAT_EXTENSIBLE: 真实格式藏在 SubFormat GUID 的前 2 字节
        if (audioFormat == 0xFFFE && chunkSize >= 40) {
          final subFormat = data.getUint16(offset + 24, Endian.little);
          audioFormat = subFormat; // 1=PCM, 3=IEEE Float
          final validBits = data.getUint16(offset + 18, Endian.little);
          if (validBits > 0 && validBits <= 32) bitsPerSample = validBits;
        }

        await LogService.info(
          'SENSEVOICE',
          'WAV fmt: format=$audioFormat ch=$numChannels '
              'rate=$sampleRate bits=$bitsPerSample',
        );
      } else if (chunkId == 'data') {
        if (audioFormat == null ||
            sampleRate == null ||
            numChannels == null ||
            bitsPerSample == null) {
          throw SenseVoiceException('WAV: data chunk 在 fmt chunk 之前');
        }

        if (audioFormat != 1 && audioFormat != 3) {
          throw SenseVoiceException(
            'WAV: 不支持的音频格式 0x${audioFormat.toRadixString(16)} '
            '(仅支持 PCM / IEEE Float)',
          );
        }

        final bytesPerSample = bitsPerSample ~/ 8;
        final frameSize = bytesPerSample * numChannels;
        final totalFrames = chunkSize ~/ frameSize;
        samples = Float32List(totalFrames);

        var readOffset = offset;
        for (var i = 0; i < totalFrames; i++) {
          if (readOffset + bytesPerSample > bytes.length) break;

          if (audioFormat == 3 && bitsPerSample == 32) {
            // IEEE Float 32
            samples[i] = data.getFloat32(readOffset, Endian.little);
          } else if (bitsPerSample == 16) {
            final s = data.getInt16(readOffset, Endian.little);
            samples[i] = s / 32768.0;
          } else if (bitsPerSample == 32) {
            final s = data.getInt32(readOffset, Endian.little);
            samples[i] = s / 2147483648.0;
          } else if (bitsPerSample == 24) {
            // 24-bit little-endian signed
            final b0 = bytes[readOffset];
            final b1 = bytes[readOffset + 1];
            final b2 = bytes[readOffset + 2];
            var s = b0 | (b1 << 8) | (b2 << 16);
            if (s >= 0x800000) s -= 0x1000000; // sign extend
            samples[i] = s / 8388608.0;
          } else if (bitsPerSample == 8) {
            samples[i] = (bytes[readOffset] - 128) / 128.0;
          }

          readOffset += frameSize; // 跳过所有通道（只取第一个通道）
        }
        break; // 已读取 data chunk
      }

      // 跳到下一个 chunk（chunk 按 word 对齐）
      offset += chunkSize;
      if (chunkSize.isOdd) offset++;
    }

    if (samples == null || sampleRate == null) {
      throw SenseVoiceException('WAV: 未找到有效的音频数据');
    }

    return (samples, sampleRate);
  }

  /// 线性插值重采样
  static Float32List _resample(Float32List input, int srcRate, int dstRate) {
    if (srcRate == dstRate) return input;
    final ratio = srcRate / dstRate;
    final outputLength = (input.length / ratio).floor();
    final output = Float32List(outputLength);
    for (var i = 0; i < outputLength; i++) {
      final srcPos = i * ratio;
      final srcIndex = srcPos.floor();
      final frac = srcPos - srcIndex;
      if (srcIndex + 1 < input.length) {
        output[i] = input[srcIndex] * (1 - frac) + input[srcIndex + 1] * frac;
      } else if (srcIndex < input.length) {
        output[i] = input[srcIndex];
      }
    }
    return output;
  }

  /// 如果路径含有非 ASCII 字符，将目录软链到临时 ASCII 路径。
  static Future<String> _ensureAsciiDir(String dirPath) async {
    final isAscii = dirPath.codeUnits.every((c) => c >= 0x20 && c <= 0x7E);
    if (isAscii) return dirPath;

    final tmpDir = Directory.systemTemp;
    final safeName = 'sherpa_model_${DateTime.now().millisecondsSinceEpoch}';
    final safePath = p.join(tmpDir.path, safeName);

    // 创建符号链接，避免复制 200+MB 模型文件
    final link = Link(safePath);
    if (await link.exists()) {
      await link.delete();
    }
    await link.create(dirPath);
    return safePath;
  }

  // ---- 状态检查 ----

  Future<SenseVoiceCheckResult> checkAvailability() async {
    try {
      final modelDir = await _resolveModelDir();
      final modelFile = p.join(modelDir, 'model.int8.onnx');
      final tokensFile = p.join(modelDir, 'tokens.txt');

      if (!await File(modelFile).exists()) {
        return SenseVoiceCheckResult(
          ok: false,
          message: '模型文件不存在: $modelFile\n请在设置中下载 SenseVoice 模型',
        );
      }

      if (!await File(tokensFile).exists()) {
        return SenseVoiceCheckResult(
          ok: false,
          message: 'tokens 文件不存在\n请重新下载模型',
        );
      }

      // 验证原生库可用
      if (!_bindingsInitialized) {
        sherpa.initBindings();
        _bindingsInitialized = true;
      }

      return SenseVoiceCheckResult(
        ok: true,
        message: 'SenseVoice 本地模型就绪 (模型: $modelDir)',
      );
    } on SenseVoiceException catch (e) {
      return SenseVoiceCheckResult(ok: false, message: e.message);
    } catch (e) {
      return SenseVoiceCheckResult(ok: false, message: '检查失败: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Result / Exception
// ---------------------------------------------------------------------------

class SenseVoiceCheckResult {
  final bool ok;
  final String message;

  const SenseVoiceCheckResult({required this.ok, required this.message});
}

class SenseVoiceException implements Exception {
  final String message;

  SenseVoiceException(this.message);

  @override
  String toString() => message;
}
