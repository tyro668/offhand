import 'package:voicetype/services/local_asr_worker_main.dart';

Future<void> main(List<String> args) async {
  await LocalAsrWorkerMain.run();
}
