import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sense_voice_worker_service.dart';

class LocalAsrWorkerMain {
  static Future<void> run() async {
    await _send({'type': 'ready', 'protocolVersion': 1});

    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      await _handleLine(line);
    }
  }

  static Future<void> _handleLine(String line) async {
    Map<String, dynamic> message;
    try {
      final decoded = json.decode(line);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('message is not a JSON object');
      }
      message = decoded;
    } catch (e) {
      stderr.writeln('invalid request: $e');
      return;
    }

    final type = message['type']?.toString();
    if (type == 'shutdown') {
      await _send({'type': 'shutdownAck'});
      exit(0);
    }

    final requestId = message['requestId']?.toString() ?? '';
    if (requestId.isEmpty) {
      await _send({'type': 'error', 'message': '缺少 requestId'});
      return;
    }

    try {
      switch (type) {
        case 'transcribe':
          await _transcribe(requestId, message);
          return;
        case 'checkAvailability':
          await _checkAvailability(requestId, message);
          return;
        default:
          await _send({
            'type': 'error',
            'requestId': requestId,
            'message': '未知本地 ASR worker 请求: $type',
          });
      }
    } catch (e, stackTrace) {
      stderr.writeln('request failed: $e');
      stderr.writeln(stackTrace);
      await _send({
        'type': 'error',
        'requestId': requestId,
        'message': e.toString(),
      });
    }
  }

  static Future<void> _transcribe(
    String requestId,
    Map<String, dynamic> message,
  ) async {
    final modelDir = message['modelDir']?.toString() ?? '';
    final audioPath = message['audioPath']?.toString() ?? '';
    final prompt = message['prompt']?.toString();

    final service = SenseVoiceWorkerService(modelPath: modelDir);
    final text = await service.transcribe(audioPath, prompt: prompt);
    await _send({'type': 'result', 'requestId': requestId, 'text': text});
  }

  static Future<void> _checkAvailability(
    String requestId,
    Map<String, dynamic> message,
  ) async {
    final modelDir = message['modelDir']?.toString() ?? '';
    final service = SenseVoiceWorkerService(modelPath: modelDir);
    final result = await service.checkAvailability();
    await _send({
      'type': 'availability',
      'requestId': requestId,
      'ok': result.ok,
      'message': result.message,
    });
  }

  static Future<void> _send(Map<String, dynamic> message) async {
    stdout.writeln(json.encode(message));
    await stdout.flush();
  }
}
