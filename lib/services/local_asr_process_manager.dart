import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'log_service.dart';
import 'sense_voice_ffi_service.dart';

class LocalAsrProcessManager {
  LocalAsrProcessManager._();

  static final LocalAsrProcessManager instance = LocalAsrProcessManager._();

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  Completer<void>? _readyCompleter;
  Future<void>? _starting;
  Timer? _idleTimer;
  int _idleUnloadMinutes = 3;
  int _nextRequestId = 0;
  int? _lastWorkerExitCode;
  String? _lastWorkerKillReason;

  final Map<String, _PendingAsrRequest> _pending = {};

  bool get isWorkerRunningForTest => _process != null;

  int? get lastWorkerExitCodeForTest => _lastWorkerExitCode;

  String? get lastWorkerKillReasonForTest => _lastWorkerKillReason;

  Future<void> shutdownWorkerForTest() => _shutdownWorker();

  Future<String> transcribe({
    required String modelDir,
    required String audioPath,
    String? prompt,
  }) async {
    final response = await _sendRequest({
      'type': 'transcribe',
      'modelDir': modelDir,
      'audioPath': audioPath,
      if (prompt != null && prompt.trim().isNotEmpty) 'prompt': prompt,
      'language': 'auto',
    }, timeout: const Duration(minutes: 5));

    final text = response['text']?.toString().trim() ?? '';
    if (text.isEmpty) {
      throw SenseVoiceException('SenseVoice 返回空文本');
    }
    return text;
  }

  Future<SenseVoiceCheckResult> checkAvailability({
    required String modelDir,
  }) async {
    try {
      final response = await _sendRequest({
        'type': 'checkAvailability',
        'modelDir': modelDir,
      }, timeout: const Duration(seconds: 30));
      return SenseVoiceCheckResult(
        ok: response['ok'] == true,
        message: response['message']?.toString() ?? '',
      );
    } catch (e) {
      return SenseVoiceCheckResult(ok: false, message: '检查失败: $e');
    }
  }

  Future<void> setIdleUnloadMinutes(int minutes) async {
    _idleUnloadMinutes = minutes.clamp(0, 30);
    _idleTimer?.cancel();
    if (_process != null && _pending.isEmpty) {
      _scheduleIdleRelease();
    }
  }

  Future<Map<String, dynamic>> _sendRequest(
    Map<String, dynamic> request, {
    required Duration timeout,
  }) async {
    _idleTimer?.cancel();
    await _ensureStarted();

    final process = _process;
    if (process == null) {
      throw SenseVoiceException('本地 ASR worker 未启动');
    }

    final requestId = (++_nextRequestId).toString();
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = _PendingAsrRequest(completer);

    try {
      process.stdin.writeln(json.encode({...request, 'requestId': requestId}));
      await process.stdin.flush();
    } catch (e) {
      _pending.remove(requestId);
      _killWorker('write failed: $e');
      throw SenseVoiceException('无法发送本地 ASR 请求: $e');
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(requestId);
        _killWorker('request timeout');
        throw TimeoutException('本地 ASR 请求超时', timeout);
      },
    );
  }

  Future<void> _ensureStarted() async {
    final ready = _readyCompleter;
    if (_process != null && ready != null && ready.isCompleted) {
      return;
    }

    final starting = _starting;
    if (starting != null) {
      await starting;
      return;
    }

    final future = _startWorker();
    _starting = future;
    try {
      await future;
    } finally {
      _starting = null;
    }
  }

  Future<void> _startWorker() async {
    final workerExecutable = await _resolveWorkerExecutable();
    final workerEnvironment = _resolveWorkerEnvironment(workerExecutable);
    await LogService.info(
      'LOCAL_ASR',
      'starting ASR worker executable=$workerExecutable',
    );

    final process = await Process.start(
      workerExecutable,
      ['--asr-worker'],
      environment: workerEnvironment,
      mode: ProcessStartMode.normal,
    );

    _process = process;
    _readyCompleter = Completer<void>();
    _lastWorkerExitCode = null;
    _lastWorkerKillReason = null;

    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleWorkerLine,
          onError: (Object e, StackTrace stackTrace) {
            _failAllPending('ASR worker stdout 读取失败: $e');
          },
        );

    _stderrSubscription = process.stderr.listen((bytes) {
      final message = utf8.decode(bytes, allowMalformed: true).trim();
      if (message.isNotEmpty) {
        LogService.warn('LOCAL_ASR', 'worker stderr: $message').ignore();
      }
    });

    process.exitCode.then((code) {
      LogService.info('LOCAL_ASR', 'ASR worker exited code=$code').ignore();
      _handleWorkerExit(process, code);
    });

    try {
      await _readyCompleter!.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _killWorker('ready timeout');
      throw SenseVoiceException('本地 ASR worker 启动超时');
    }
  }

  Future<String> _resolveWorkerExecutable() async {
    final override = Platform.environment['OFFHAND_ASR_WORKER_EXECUTABLE']
        ?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }

    if (!Platform.isMacOS) {
      return Platform.resolvedExecutable;
    }

    final executable = File(Platform.resolvedExecutable);
    final helperExecutable = File(
      [
        executable.parent.parent.path,
        'Helpers',
        'Offhand Helper',
        'bin',
        'Offhand Helper',
      ].join(Platform.pathSeparator),
    );
    if (await helperExecutable.exists()) {
      return helperExecutable.path;
    }

    throw SenseVoiceException(
      'Offhand Helper 后台服务未找到: ${helperExecutable.path}',
    );
  }

  Map<String, String>? _resolveWorkerEnvironment(String workerExecutable) {
    if (!Platform.isMacOS) {
      return null;
    }

    final executable = File(workerExecutable);
    final candidates = <String>[
      [executable.parent.path, '..', 'lib'].join(Platform.pathSeparator),
      [
        executable.parent.path,
        '..',
        '..',
        '..',
        'Frameworks',
      ].join(Platform.pathSeparator),
    ];

    for (final candidate in candidates) {
      final library = File(
        [candidate, 'libsherpa-onnx-c-api.dylib'].join(Platform.pathSeparator),
      );
      if (library.existsSync()) {
        return {'OFFHAND_SHERPA_LIBRARY_DIR': library.parent.path};
      }
    }

    return null;
  }

  void _handleWorkerLine(String line) {
    Map<String, dynamic> message;
    try {
      final decoded = json.decode(line);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('message is not a JSON object');
      }
      message = decoded;
    } catch (e) {
      LogService.warn(
        'LOCAL_ASR',
        'invalid worker output: $line ($e)',
      ).ignore();
      return;
    }

    final type = message['type']?.toString();
    if (type == 'ready') {
      final ready = _readyCompleter;
      if (ready != null && !ready.isCompleted) {
        ready.complete();
      }
      return;
    }

    final requestId = message['requestId']?.toString();
    if (requestId == null) return;

    final pending = _pending.remove(requestId);
    if (pending == null) return;

    if (type == 'error') {
      final error = message['message']?.toString() ?? '本地 ASR worker 失败';
      pending.completer.completeError(SenseVoiceException(error));
    } else {
      pending.completer.complete(message);
    }

    if (_pending.isEmpty) {
      _scheduleIdleRelease();
    }
  }

  void _handleWorkerExit(Process process, int code) {
    if (!identical(_process, process)) return;

    _lastWorkerExitCode = code;
    _process = null;
    _readyCompleter = null;
    _idleTimer?.cancel();
    _stdoutSubscription?.cancel().ignore();
    _stderrSubscription?.cancel().ignore();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    if (_pending.isNotEmpty) {
      _failAllPending('本地 ASR worker 已退出 (code=$code)');
    }
  }

  void _scheduleIdleRelease() {
    _idleTimer?.cancel();
    if (_idleUnloadMinutes <= 0 || _process == null || _pending.isNotEmpty) {
      return;
    }

    _idleTimer = Timer(Duration(minutes: _idleUnloadMinutes), () {
      if (_pending.isEmpty) {
        _shutdownWorker().ignore();
      }
    });
  }

  Future<void> _shutdownWorker() async {
    final process = _process;
    if (process == null) return;

    await LogService.info(
      'LOCAL_ASR',
      'idle timeout reached, shutting down ASR worker',
    );

    try {
      process.stdin.writeln(json.encode({'type': 'shutdown'}));
      await process.stdin.flush();
    } catch (_) {
      _killWorker('shutdown write failed');
      return;
    }

    await Future<void>.delayed(const Duration(seconds: 2));
    if (identical(_process, process)) {
      _killWorker('shutdown timeout');
    }
  }

  void _killWorker(String reason) {
    final process = _process;
    if (process == null) return;

    LogService.warn('LOCAL_ASR', 'killing ASR worker: $reason').ignore();
    _lastWorkerKillReason = reason;
    process.kill();
    _process = null;
    _readyCompleter = null;
    _idleTimer?.cancel();
    _stdoutSubscription?.cancel().ignore();
    _stderrSubscription?.cancel().ignore();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _failAllPending('本地 ASR worker 已停止: $reason');
  }

  void _failAllPending(String message) {
    final pending = List<_PendingAsrRequest>.from(_pending.values);
    _pending.clear();
    for (final request in pending) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(SenseVoiceException(message));
      }
    }
  }
}

class _PendingAsrRequest {
  final Completer<Map<String, dynamic>> completer;

  _PendingAsrRequest(this.completer);
}
