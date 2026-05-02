import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class SenseVoiceWorkerService {
  SenseVoiceWorkerService({required this.modelPath});

  final String modelPath;

  static bool _bindingsInitialized = false;

  Future<String> transcribe(String audioPath, {String? prompt}) async {
    final modelDir = _resolveModelDir();

    _logInfo(
      'transcribe modelDir=$modelDir audio=$audioPath prompt=${(prompt ?? '').trim().isNotEmpty}',
    );

    final modelFile = p.join(modelDir, 'model.int8.onnx');
    final tokensFile = p.join(modelDir, 'tokens.txt');

    if (!await File(modelFile).exists()) {
      throw SenseVoiceWorkerException(
        '模型文件不存在: $modelFile\n请在设置中下载 SenseVoice 模型',
      );
    }

    if (!await File(tokensFile).exists()) {
      throw SenseVoiceWorkerException(
        'tokens 文件不存在: $tokensFile\n请在设置中重新下载 SenseVoice 模型',
      );
    }

    if (!await File(audioPath).exists()) {
      throw SenseVoiceWorkerException('音频文件不存在: $audioPath');
    }

    try {
      _ensureBindingsInitialized();

      final wavResult = await _readWavDart(audioPath);
      var samples = wavResult.$1;
      final fileSampleRate = wavResult.$2;

      _logInfo(
        'readWavDart done: samples=${samples.length}, sampleRate=$fileSampleRate',
      );

      if (samples.isEmpty) {
        throw SenseVoiceWorkerException('读取音频失败（samples=0）\n文件路径: $audioPath');
      }

      const targetRate = 16000;
      if (fileSampleRate != targetRate) {
        _logInfo('resampling from $fileSampleRate Hz to $targetRate Hz');
        samples = _resample(samples, fileSampleRate, targetRate);
      }

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

      final recognizer = sherpa.OfflineRecognizer(config);
      final stream = recognizer.createStream();

      stream.acceptWaveform(samples: samples, sampleRate: targetRate);
      recognizer.decode(stream);

      final result = recognizer.getResult(stream);
      final text = result.text.trim();

      stream.free();
      recognizer.free();

      if (safeModelDir != modelDir) {
        Link(safeModelDir).delete().ignore();
      }

      if (text.isEmpty) {
        throw SenseVoiceWorkerException('SenseVoice 返回空文本');
      }

      _logInfo(
        'transcribe result (lang=${result.lang}, emotion=${result.emotion}): '
        '${text.length > 100 ? text.substring(0, 100) : text}',
      );

      return text;
    } catch (e) {
      _logError('transcribe failed: $e');
      if (e is SenseVoiceWorkerException) rethrow;
      throw SenseVoiceWorkerException('SenseVoice 转写失败: $e');
    }
  }

  Future<SenseVoiceWorkerCheckResult> checkAvailability() async {
    try {
      final modelDir = _resolveModelDir();
      final modelFile = p.join(modelDir, 'model.int8.onnx');
      final tokensFile = p.join(modelDir, 'tokens.txt');

      if (!await File(modelFile).exists()) {
        return SenseVoiceWorkerCheckResult(
          ok: false,
          message: '模型文件不存在: $modelFile\n请在设置中下载 SenseVoice 模型',
        );
      }

      if (!await File(tokensFile).exists()) {
        return const SenseVoiceWorkerCheckResult(
          ok: false,
          message: 'tokens 文件不存在\n请重新下载模型',
        );
      }

      _ensureBindingsInitialized();

      return SenseVoiceWorkerCheckResult(
        ok: true,
        message: 'SenseVoice 本地模型就绪 (模型: $modelDir)',
      );
    } on SenseVoiceWorkerException catch (e) {
      return SenseVoiceWorkerCheckResult(ok: false, message: e.message);
    } catch (e) {
      return SenseVoiceWorkerCheckResult(ok: false, message: '检查失败: $e');
    }
  }

  String _resolveModelDir() {
    if (p.isAbsolute(modelPath)) {
      return modelPath;
    }
    return p.normalize(p.absolute(modelPath));
  }

  static void _ensureBindingsInitialized() {
    if (_bindingsInitialized) return;

    final libraryDir = _resolveSherpaLibraryDirectory();
    if (libraryDir == null) {
      sherpa.initBindings();
    } else {
      sherpa.initBindings(libraryDir);
    }
    _bindingsInitialized = true;
  }

  static String? _resolveSherpaLibraryDirectory() {
    final override = Platform.environment['OFFHAND_SHERPA_LIBRARY_DIR']?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }

    if (!Platform.isMacOS) {
      return null;
    }

    final executable = File(Platform.resolvedExecutable);
    final candidates = <String>[
      p.normalize(p.join(executable.parent.path, '..', 'lib')),
      p.normalize(p.join(executable.parent.path, '..', '..', 'Frameworks')),
      p.normalize(
        p.join(executable.parent.path, '..', '..', '..', 'Frameworks'),
      ),
      p.normalize(
        p.join(executable.parent.path, '..', '..', '..', '..', 'Frameworks'),
      ),
    ];

    for (final candidate in candidates) {
      if (File(p.join(candidate, 'libsherpa-onnx-c-api.dylib')).existsSync()) {
        return candidate;
      }
    }

    return null;
  }

  static Future<(Float32List, int)> _readWavDart(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    if (bytes.length < 44) {
      throw SenseVoiceWorkerException('WAV 文件过小 (${bytes.length} bytes)');
    }

    final data = ByteData.sublistView(bytes);

    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') {
      throw SenseVoiceWorkerException('不是有效的 WAV 文件 (header: $riff / $wave)');
    }

    var offset = 12;
    int? sampleRate;
    int? numChannels;
    int? bitsPerSample;
    int? audioFormat;
    Float32List? samples;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (chunkId == 'fmt ') {
        if (chunkSize < 16) {
          throw SenseVoiceWorkerException('WAV: fmt chunk 过短 ($chunkSize)');
        }
        audioFormat = data.getUint16(offset, Endian.little);
        numChannels = data.getUint16(offset + 2, Endian.little);
        sampleRate = data.getUint32(offset + 4, Endian.little);
        bitsPerSample = data.getUint16(offset + 14, Endian.little);

        if (audioFormat == 0xFFFE && chunkSize >= 40) {
          final subFormat = data.getUint16(offset + 24, Endian.little);
          audioFormat = subFormat;
          final validBits = data.getUint16(offset + 18, Endian.little);
          if (validBits > 0 && validBits <= 32) {
            bitsPerSample = validBits;
          }
        }

        _logInfo(
          'WAV fmt: format=$audioFormat ch=$numChannels '
          'rate=$sampleRate bits=$bitsPerSample',
        );
      } else if (chunkId == 'data') {
        if (audioFormat == null ||
            sampleRate == null ||
            numChannels == null ||
            bitsPerSample == null) {
          throw SenseVoiceWorkerException('WAV: data chunk 在 fmt chunk 之前');
        }

        if (audioFormat != 1 && audioFormat != 3) {
          throw SenseVoiceWorkerException(
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
            samples[i] = data.getFloat32(readOffset, Endian.little);
          } else if (bitsPerSample == 16) {
            final s = data.getInt16(readOffset, Endian.little);
            samples[i] = s / 32768.0;
          } else if (bitsPerSample == 32) {
            final s = data.getInt32(readOffset, Endian.little);
            samples[i] = s / 2147483648.0;
          } else if (bitsPerSample == 24) {
            final b0 = bytes[readOffset];
            final b1 = bytes[readOffset + 1];
            final b2 = bytes[readOffset + 2];
            var s = b0 | (b1 << 8) | (b2 << 16);
            if (s >= 0x800000) s -= 0x1000000;
            samples[i] = s / 8388608.0;
          } else if (bitsPerSample == 8) {
            samples[i] = (bytes[readOffset] - 128) / 128.0;
          }

          readOffset += frameSize;
        }
        break;
      }

      offset += chunkSize;
      if (chunkSize.isOdd) offset++;
    }

    if (samples == null || sampleRate == null) {
      throw SenseVoiceWorkerException('WAV: 未找到有效的音频数据');
    }

    return (samples, sampleRate);
  }

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

  static Future<String> _ensureAsciiDir(String dirPath) async {
    final isAscii = dirPath.codeUnits.every((c) => c >= 0x20 && c <= 0x7E);
    if (isAscii) return dirPath;

    final tmpDir = Directory.systemTemp;
    final safeName = 'sherpa_model_${DateTime.now().millisecondsSinceEpoch}';
    final safePath = p.join(tmpDir.path, safeName);

    final link = Link(safePath);
    if (await link.exists()) {
      await link.delete();
    }
    await link.create(dirPath);
    return safePath;
  }

  static void _logInfo(String message) {
    stderr.writeln('[INFO][SENSEVOICE] $message');
  }

  static void _logError(String message) {
    stderr.writeln('[ERROR][SENSEVOICE] $message');
  }
}

class SenseVoiceWorkerCheckResult {
  const SenseVoiceWorkerCheckResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

class SenseVoiceWorkerException implements Exception {
  SenseVoiceWorkerException(this.message);

  final String message;

  @override
  String toString() => message;
}
