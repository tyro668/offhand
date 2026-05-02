import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicetype/services/local_asr_process_manager.dart';

void main() {
  group('LocalAsrProcessManager smoke', () {
    final workerExecutable = Platform
        .environment['OFFHAND_ASR_WORKER_EXECUTABLE']
        ?.trim();
    final hasWorkerExecutable =
        workerExecutable != null && workerExecutable.isNotEmpty;

    test(
      'idle release shuts down Offhand Helper',
      () async {
        final workerFile = File(workerExecutable!);
        expect(await workerFile.exists(), isTrue);

        final manager = LocalAsrProcessManager.instance;
        addTearDown(manager.shutdownWorkerForTest);

        await manager.setIdleUnloadMinutes(1);
        final result = await manager.checkAvailability(
          modelDir: '/tmp/offhand-smoke-missing-model',
        );

        expect(result.ok, isFalse);
        expect(manager.isWorkerRunningForTest, isTrue);

        final deadline = DateTime.now().add(const Duration(seconds: 75));
        while (manager.isWorkerRunningForTest &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }

        expect(manager.isWorkerRunningForTest, isFalse);
        expect(manager.lastWorkerKillReasonForTest, isNull);
        expect(manager.lastWorkerExitCodeForTest, 0);
      },
      skip: hasWorkerExecutable
          ? false
          : 'Set OFFHAND_ASR_WORKER_EXECUTABLE to run this smoke test.',
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
