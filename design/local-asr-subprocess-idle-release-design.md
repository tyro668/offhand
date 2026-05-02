# 本地 ASR 子进程空闲释放设计

## 1. 背景

当前本地语音转文字链路使用 sherpa-onnx / SenseVoice：

- `SttService`
  - 当 `SttProviderConfig.type == SttProviderType.senseVoice` 时路由到 `SenseVoiceSttProvider`
- `SenseVoiceSttProvider`
  - 每次转写创建 `SenseVoiceFfiService(modelPath: config.model)`
- `SenseVoiceFfiService`
  - 在主 Flutter 进程内调用 `sherpa.initBindings()`
  - 读取 WAV、重采样
  - 创建 `sherpa.OfflineRecognizer`
  - 创建 stream、decode、getResult
  - 调用 `stream.free()` 与 `recognizer.free()`

这条链路可以释放 recognizer / stream 级别的原生对象，但仍存在一个现实问题：

- sherpa-onnx、onnxruntime、动态库加载器、native allocator、线程池、mmap、内部缓存等资源可能继续留在主进程地址空间内。
- Dart / Flutter 主进程生命周期长，调用 `free()` 后 RSS 不一定明显下降。
- 用户完成一次本地 ASR 后，即使长时间不再使用，本地模型仍可能让应用保持较高内存占用。

因此仅靠主进程内 dispose / free 不足以满足“空闲后完全释放”的目标。更可靠的边界是进程边界：让本地 ASR 推理运行在子进程中，空闲超时后退出子进程，由操作系统回收该进程持有的全部 native 内存。

同时，当前应用仍保留本地文本模型能力：

- `LocalLlmService`
- `LocalLlmAiProvider`
- `AiEnhanceService` 中 `baseUrl/apiKey` 为空即认为是本地模型
- `AiModelPage` 中本地 GGUF 下载、推荐和检查逻辑
- `llamadart` 依赖
- `assets/prompts/local_model_prompt.md`

新的产品方向是：本地模型只保留语音 ASR 模型，不再支持本地文本模型。因此原“本地模型空闲自动释放”设置项需要复用到本地 ASR 子进程生命周期，而不是继续服务本地 LLM。

## 2. 目标

1. 本地 ASR 推理运行在独立子进程中。
2. 一段时间内没有新的本地 ASR 推理任务后，自动关闭子进程。
3. 子进程退出后，sherpa-onnx / onnxruntime 占用的 native 内存由 OS 完整回收。
4. 复用设置中的“本地模型空闲自动释放”配置项。
5. 本地模型能力只支持语音 ASR 模型。
6. 移除本地文本模型支持，文本增强只保留云端 / OpenAI 兼容模型。
7. 对现有 `SttService(config).transcribe(audioPath)` 调用方保持接口稳定。

## 3. 非目标

1. 不在第一阶段做实时流式 ASR。
2. 不在第一阶段支持多个本地 ASR 子进程并行推理。
3. 不改变云端 STT、纠错、AI 增强主流程。
4. 不承诺清理 OS page cache。子进程退出能释放进程 RSS / native heap / mmap 引用，但文件系统缓存由操作系统自行管理。
5. 不自动删除用户已下载的 GGUF 文本模型文件，除非后续专门提供清理入口。

## 4. 现状问题

### 4.1 主进程内 FFI 无法保证彻底释放

`SenseVoiceFfiService.transcribe()` 里虽然已经做了：

```dart
stream.free();
recognizer.free();
```

但这只释放 sherpa 暴露出来的对象。以下资源不一定会归还给 OS：

- sherpa-onnx / onnxruntime 全局初始化状态
- native library text/data segment 映射
- allocator arena
- 推理线程池
- runtime 内部缓存
- Dart FFI 绑定初始化后的常驻状态

在桌面应用里，主进程不退出，这些资源会被用户感知为“模型用完后仍占内存”。

### 4.2 现有空闲释放配置绑在本地 LLM 上

当前配置项位于：

- `SettingsProvider._localLlmIdleUnloadMinutesKey`
- `SettingsProvider.localLlmIdleUnloadMinutes`
- `SettingsProvider.setLocalLlmIdleUnloadMinutes`
- `GeneralPage._buildLocalLlmIdleUnloadSection`
- `LocalLlmService.setIdleUnloadMinutes`

这套机制的问题：

- 只对 `LocalLlmService` 生效。
- 本地文本模型即将移除。
- ASR 才是之后唯一的本地模型能力。
- 名称里带 `Llm`，但 UI 文案已经是“本地模型空闲自动释放”，可以迁移为更通用语义。

### 4.3 本地文本模型和本地 ASR 概念混在一起

当前“本地模型”同时出现在：

- 文本模型页：GGUF / llamadart / llama.cpp
- 语音模型页：SenseVoice / sherpa-onnx

移除本地文本模型后，需要避免以下隐患：

- `AiEnhanceService` 继续把空 `baseUrl/apiKey` 识别为本地模型。
- `AiModelPage` 继续允许新增本地模型。
- 已保存的本地文本模型配置继续被启用。
- 空闲释放配置仍调用 `LocalLlmService`。

## 5. 总体方案

新增一个本地 ASR 子进程管理层：

```text
Flutter 主进程
  RecordingProvider
    -> SttService
      -> SenseVoiceSttProvider
        -> LocalAsrProcessManager
          -> Process.start(appExecutable, ["--asr-worker"])
            -> ASR Worker 子进程
              -> SenseVoiceWorkerCore
                -> sherpa-onnx FFI
```

主进程负责：

- 请求排队
- 子进程启动
- IPC 编解码
- 超时 / 崩溃处理
- 空闲计时
- 空闲超时后关闭或 kill 子进程

子进程负责：

- 初始化 sherpa bindings
- 加载模型
- 读取音频文件
- 执行 ASR 推理
- 返回文本或错误
- 收到 shutdown 后退出

关键点：

- 子进程退出是“完全释放 native 内存”的唯一强边界。
- 每次推理结束后不立即退出，而是按“本地模型空闲自动释放”配置延迟退出。
- 如果空闲期间又有新任务，复用现有子进程，避免频繁冷启动。

## 6. 进程模型

### 6.1 子进程启动方式

优先方案：复用当前桌面应用可执行文件，增加 worker mode。

`main.dart` 改为接收 args：

```dart
Future<void> main(List<String> args) async {
  if (args.contains('--asr-worker')) {
    await LocalAsrWorkerMain.run();
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  ...
  runApp(const VoiceTypeApp());
}
```

主进程启动 worker：

```dart
Process.start(
  Platform.resolvedExecutable,
  ['--asr-worker'],
  mode: ProcessStartMode.normal,
);
```

如果 Flutter 桌面可执行文件在某个平台无法稳定以无 UI worker 方式运行，则降级为独立 sidecar worker：

- `bin/local_asr_worker.dart`
- 打包为平台可执行文件
- app bundle / exe 旁边放置 `offhand_asr_worker`

第一阶段建议先实现复用当前可执行文件，因为它最少引入打包产物；如果 macOS app activation、签名或 native library 路径出现问题，再切到 sidecar。

### 6.2 worker 启动约束

worker mode 必须满足：

- 不调用 `runApp`
- 不初始化 UI
- 不打开数据库
- 不使用 `path_provider` 解析模型目录
- 不依赖 Provider / SettingsProvider
- 只通过 IPC 收到绝对路径或已解析好的模型目录

原因：

- worker 是纯推理进程，不应携带 UI 生命周期。
- 数据库锁和主进程状态不应跨进程共享。
- 模型路径由主进程解析，避免 worker 里初始化 Flutter plugin。

## 7. IPC 协议

使用 stdout / stdin 上的 NDJSON，每行一条 JSON 消息。

选择 NDJSON 的原因：

- Dart 原生 `Process.stdin/stdout` 易处理。
- 可调试。
- 不需要额外端口和权限。
- 请求 / 响应天然带 `requestId`。

### 7.1 主进程 -> worker

#### ready 握手

worker 启动后主动输出：

```json
{"type":"ready","protocolVersion":1}
```

主进程在收到 ready 后才发送推理请求。

#### transcribe

```json
{
  "type": "transcribe",
  "requestId": "uuid",
  "modelDir": "/abs/path/to/models/sense-voice-zh-en",
  "audioPath": "/abs/path/to/audio.wav",
  "prompt": "可选术语提示",
  "language": "auto"
}
```

说明：

- `modelDir` 使用绝对路径。
- `audioPath` 使用绝对路径。
- `prompt` 保留字段，当前 SenseVoice 可能不消费，但协议上保留。
- worker 侧仍执行 WAV 读取和重采样。

#### checkAvailability

```json
{
  "type": "checkAvailability",
  "requestId": "uuid",
  "modelDir": "/abs/path/to/models/sense-voice-zh-en"
}
```

#### shutdown

```json
{
  "type": "shutdown",
  "reason": "idleTimeout"
}
```

### 7.2 worker -> 主进程

#### result

```json
{
  "type": "result",
  "requestId": "uuid",
  "text": "识别结果",
  "language": "zh",
  "durationMs": 1234
}
```

#### availability

```json
{
  "type": "availability",
  "requestId": "uuid",
  "ok": true,
  "message": "SenseVoice 本地模型就绪"
}
```

#### error

```json
{
  "type": "error",
  "requestId": "uuid",
  "code": "modelNotFound",
  "message": "模型文件不存在"
}
```

#### log

```json
{
  "type": "log",
  "level": "info",
  "tag": "ASR_WORKER",
  "message": "model loaded"
}
```

主进程把 worker log 转发到 `LogService`。

## 8. 主进程组件设计

### 8.1 `LocalAsrProcessManager`

新增：

```text
lib/services/local_asr_process_manager.dart
```

职责：

- 管理单个 ASR worker 进程
- 维护请求队列
- 维护 `requestId -> Completer`
- 解析 stdout 消息
- 监听 stderr / exitCode
- 根据空闲配置启动 idle timer
- 空闲超时后优雅 shutdown，必要时 kill

核心接口：

```dart
class LocalAsrProcessManager {
  static final instance = LocalAsrProcessManager._();

  Future<String> transcribe({
    required String modelDir,
    required String audioPath,
    String? prompt,
  });

  Future<SenseVoiceCheckResult> checkAvailability({
    required String modelDir,
  });

  Future<void> setIdleUnloadMinutes(int minutes);

  Future<void> shutdown({bool force = false});
}
```

### 8.2 生命周期状态

建议状态：

```dart
enum LocalAsrWorkerState {
  stopped,
  starting,
  ready,
  busy,
  stopping,
  crashed,
}
```

状态流：

```text
stopped
  -> starting
  -> ready
  -> busy
  -> ready
  -> stopping
  -> stopped
```

异常流：

```text
starting/busy/ready
  -> crashed
  -> stopped
```

### 8.3 请求并发策略

第一阶段采用单 worker 串行推理：

- 同一时间只执行一个本地 ASR 请求。
- 新请求进入 FIFO 队列。
- 每个请求开始时取消 idle timer。
- 每个请求结束后，如果队列为空，再启动 idle timer。

原因：

- 桌面语音输入通常不会并发触发多个本地 ASR。
- 避免多个 sherpa worker 同时加载模型导致内存暴涨。
- 行为可预测。

后续如需并发，可以扩展为 worker pool，但默认最大并发仍应为 1。

### 8.4 空闲释放策略

复用设置中的“本地模型空闲自动释放”分钟数。

语义建议保持兼容：

- `0`：关闭自动释放，worker 常驻到应用退出或模型切换。
- `1 / 3 / 5 / 10`：空闲对应分钟后释放。

释放流程：

1. 请求完成。
2. 队列为空。
3. idle timer 启动。
4. idle timer 触发。
5. 主进程发送 `shutdown`。
6. worker 收到后释放当前 recognizer / stream / model cache。
7. worker `exit(0)`。
8. 主进程等待最多 2 秒。
9. 若未退出，调用 `process.kill(ProcessSignal.sigkill)`。

注意：

- 如果 timer 等待期间来了新请求，取消 timer 并复用 worker。
- 如果 worker 正在 busy，不能释放。
- 如果模型路径变化，直接停止旧 worker，再启动新 worker。

### 8.5 崩溃处理

如果 worker 异常退出：

- 当前进行中的请求返回 `SttException`
- 清空 pending completer 或按策略重试一次
- 记录 worker exitCode 和 stderr
- 下一次请求重新启动 worker

建议第一阶段不自动重试推理任务，避免重复消耗时间和产生不确定行为。只在启动阶段 ready 超时可以重启一次。

## 9. worker 组件设计

### 9.1 `LocalAsrWorkerMain`

新增：

```text
lib/services/local_asr_worker_main.dart
```

职责：

- 监听 stdin 行
- 解析 IPC 请求
- 调用 `SenseVoiceWorkerCore`
- 输出响应 JSON
- 处理 shutdown

### 9.2 `SenseVoiceWorkerCore`

建议把当前 `SenseVoiceFfiService` 中真正的推理逻辑拆出：

```text
lib/services/sense_voice_worker_core.dart
```

职责：

- 初始化 sherpa bindings
- 验证模型文件
- 读取 WAV
- 重采样
- 创建 `OfflineRecognizer`
- 执行 decode
- 获取结果
- 释放 recognizer / stream

`SenseVoiceFfiService` 后续变为主进程 facade：

- 模型下载
- 模型路径解析
- 调用 `LocalAsrProcessManager`
- checkAvailability 走 worker

这样下载逻辑仍留在主进程，推理逻辑移动到 worker。

### 9.3 模型缓存策略

worker 内部可以缓存当前模型的 recognizer 或只缓存 bindings。

建议第一阶段：

- 每次请求创建 recognizer。
- 每次请求结束 `free()`。
- worker 存活期间允许 native runtime 保持内部缓存。
- 空闲超时通过进程退出回收所有缓存。

这样实现简单，且已经满足核心目标。

后续优化：

- worker 内缓存 recognizer，避免连续请求重复构造。
- 模型切换时释放旧 recognizer。
- 空闲释放仍以进程退出为最终边界。

## 10. 设置项迁移设计

### 10.1 存储 key

当前 key：

```dart
static const _localLlmIdleUnloadMinutesKey =
    'local_llm_idle_unload_minutes';
```

为了复用现有配置并减少迁移成本，建议：

- 第一阶段继续读取旧 key。
- 代码中新增语义化常量：

```dart
static const _localModelIdleUnloadMinutesKey =
    'local_llm_idle_unload_minutes'; // backward compatible
```

后续如必须改 key，可增加一次迁移：

- 读取 `local_model_idle_unload_minutes`
- 如果不存在，读取旧 `local_llm_idle_unload_minutes`
- 写入新 key
- 删除旧 key

第一阶段不建议改存储 key，避免用户设置丢失。

### 10.2 Provider 命名

建议保留旧 getter 一段时间作为兼容别名，但 UI 和新代码使用新命名：

```dart
int get localModelIdleUnloadMinutes => _localModelIdleUnloadMinutes;

@Deprecated('Use localModelIdleUnloadMinutes')
int get localLlmIdleUnloadMinutes => localModelIdleUnloadMinutes;

Future<void> setLocalModelIdleUnloadMinutes(int minutes) async {
  _localModelIdleUnloadMinutes = minutes.clamp(0, 30);
  await _saveSetting(_localModelIdleUnloadMinutesKey, ...);
  await LocalAsrProcessManager.instance.setIdleUnloadMinutes(...);
  notifyListeners();
}
```

旧方法可先保留转发：

```dart
Future<void> setLocalLlmIdleUnloadMinutes(int minutes) =>
    setLocalModelIdleUnloadMinutes(minutes);
```

等相关页面都迁移后再删除旧命名。

### 10.3 UI 文案

当前 UI 文案已经是通用的“本地模型空闲自动释放”，无需大改。

建议描述更新为：

- 标题：`本地模型空闲自动释放`
- 描述：`本地 ASR 推理结束后一段时间未使用时，退出推理子进程以释放内存`
- 释放时机：保留现有下拉

英文：

- `Local model idle unload`
- `Exit the local ASR worker after an idle period to release native memory`

## 11. 移除本地文本模型支持

### 11.1 删除或停用范围

需要移除的能力：

- 本地 GGUF 模型下载
- 本地 GGUF 推荐
- `llamadart` 推理
- `LocalLlmAiProvider`
- `AiEnhanceService` 中的本地模型路由
- AI 文本模型页中的本地模型入口

建议删除或改造以下模块：

- `lib/services/local_llm_service.dart`
- `lib/services/ai_providers/local_llm_ai_provider.dart`
- `simple/local_llm_service.dart`
- `full/local_llm_service.dart`
- `assets/prompts/local_model_prompt.md`
- `pubspec.yaml` 中 `llamadart`
- `pubspec.yaml` 中 `assets/prompts/local_model_prompt.md`
- `AiVendorPreset.fallbackPresets` 中 `Local Model`
- `assets/presets/models.json` 的 `ai` 本地模型配置
- `AiModelPage` 中所有 `isLocal`、本地模型下载、推荐、路径展示逻辑

### 11.2 `AiEnhanceService` 路由调整

当前逻辑：

```dart
bool get _isLocalModel =>
    config.baseUrl.trim().isEmpty && config.apiKey.trim().isEmpty;

if (_isLocalModel) {
  return LocalLlmAiProvider(config);
}
```

调整后：

- 不再把空 `baseUrl/apiKey` 视为本地模型。
- 文本模型必须有 baseUrl。
- 如果配置为空，返回明确错误。

建议：

```dart
if (config.baseUrl.trim().isEmpty) {
  throw AiEnhanceException('请先配置文本模型服务地址');
}
```

或在 `checkAvailabilityDetailed()` 返回：

```dart
AiConnectionCheckResult(ok: false, message: '文本模型服务地址未配置')
```

### 11.3 已保存本地文本模型配置迁移

用户可能已经保存了本地文本模型条目。

迁移策略：

1. `SettingsProvider.load()` 读取 `_aiModelEntriesKey` 后过滤本地文本模型：
   - `vendorName == 'Local Model'`
   - `vendorName == '本地模型'`
   - `baseUrl.trim().isEmpty && apiKey.trim().isEmpty`
2. 如果当前启用条目被移除：
   - 启用第一条非本地文本模型；或
   - 如果没有可用文本模型，则关闭 `aiEnhanceEnabled`
3. 保存清理后的 `_aiModelEntries`
4. 记录日志：`removed local text model entries`

不自动删除本地 GGUF 文件：

- 这些文件可能较大，但自动删除用户文件风险高。
- 可以在后续“存储管理”中提供手动清理。

## 12. 文件结构建议

新增：

```text
lib/services/local_asr_process_manager.dart
lib/services/local_asr_ipc.dart
lib/services/local_asr_worker_main.dart
lib/services/sense_voice_worker_core.dart
test/services/local_asr_ipc_test.dart
test/services/local_asr_process_manager_test.dart
```

改造：

```text
lib/main.dart
lib/services/sense_voice_ffi_service.dart
lib/services/stt_providers/sense_voice_stt_provider.dart
lib/providers/settings_provider.dart
lib/screens/pages/general_page.dart
lib/screens/pages/ai_model_page.dart
lib/services/ai_enhance_service.dart
lib/models/ai_vendor_preset.dart
assets/presets/models.json
pubspec.yaml
```

删除：

```text
lib/services/local_llm_service.dart
lib/services/ai_providers/local_llm_ai_provider.dart
assets/prompts/local_model_prompt.md
```

是否删除 `simple/local_llm_service.dart`、`full/local_llm_service.dart` 取决于它们是否仍作为开发样例保留。若没有测试或文档引用，建议一并删除，避免“本地文本模型仍受支持”的误解。

## 13. 推理流程

### 13.1 首次本地 ASR

```text
用户录音结束
  -> RecordingProvider.stopAndTranscribe()
  -> SttService(config).transcribe(audioPath)
  -> SenseVoiceSttProvider.transcribe()
  -> SenseVoiceFfiService.transcribe()
  -> LocalAsrProcessManager.transcribe()
  -> worker 不存在，启动 worker
  -> 等待 ready
  -> 发送 transcribe 请求
  -> worker 初始化 sherpa bindings
  -> worker 读取 wav / 重采样 / decode
  -> worker 返回 result
  -> 主进程完成 Future
  -> 启动 idle timer
```

### 13.2 空闲期内再次 ASR

```text
新请求到来
  -> 取消 idle timer
  -> 复用 ready worker
  -> 发送 transcribe
  -> 返回 result
  -> 重新启动 idle timer
```

### 13.3 空闲超时释放

```text
idle timer 触发
  -> 发送 shutdown
  -> worker exit(0)
  -> 主进程清理 process/stdin/stdout/subscriptions
  -> 状态变为 stopped
  -> sherpa native 内存随进程退出释放
```

### 13.4 worker 卡死

```text
发送 shutdown
  -> 2 秒未退出
  -> process.kill()
  -> 状态变为 stopped
  -> 记录 warn
```

## 14. 超时策略

建议默认：

- worker ready 超时：10 秒
- 单次 ASR 推理超时：按音频时长动态计算
  - `max(60s, audioDuration * 4)`
  - 第一阶段可先使用固定 120 秒
- shutdown 等待：2 秒

超时后：

- 当前请求返回 `SttException`
- worker 进程 kill
- 下一次请求重新启动 worker

## 15. 日志与可观测性

主进程日志 tag：

- `LOCAL_ASR_MANAGER`
- `ASR_WORKER`
- `SENSEVOICE`

建议记录：

- worker start / ready / exit
- pid
- 启动耗时
- 每次请求 requestId
- 模型目录
- 音频路径 basename / 音频时长
- 推理耗时
- idle timer 设置
- idle shutdown 是否成功
- worker crash exitCode

可选内存观测：

- macOS：通过 `ps -o rss= -p <pid>`
- Windows：后续可用 platform channel 或 powershell 查询

第一阶段不需要 UI 展示内存，只写日志即可。

## 16. 平台打包注意事项

### 16.1 macOS

风险：

- `Platform.resolvedExecutable --asr-worker` 可能仍激活 app 或与 Info.plist 行为相关。
- 子进程需要能找到 sherpa-onnx native library。
- 沙盒 / 签名 / notarization 可能要求 worker 可执行文件同样签名。

策略：

1. worker mode 必须在 `main()` 最早期返回，不进入 Flutter UI。
2. 如果 native library resolution 失败，主进程启动时传入必要环境变量。
3. 如果复用 app executable 不稳定，改为 sidecar worker，放入 `Contents/MacOS/offhand_asr_worker` 并签名。

### 16.2 Windows

风险：

- DLL 搜索路径。
- `Process.kill` 对子进程树处理。
- 控制台窗口闪烁。

策略：

1. `ProcessStartMode.normal` + 无 console worker。
2. worker 可执行文件与 DLL 放在同一目录，或主进程设置 PATH。
3. 若复用 Flutter exe 出现窗口闪烁，改 sidecar console subsystem / windows subsystem worker。

## 17. 测试计划

### 17.1 单元测试

`local_asr_ipc_test.dart`

- request encode/decode
- response encode/decode
- error encode/decode
- 非法 JSON 忽略或报错

`local_asr_process_manager_test.dart`

使用 fake worker Dart 脚本：

- 启动后发送 ready
- 收到 transcribe 返回 result
- 收到 shutdown 正常退出
- 模拟 crash
- 模拟 ready 超时
- 验证 idle timer 到期后发送 shutdown
- 验证新请求会取消 idle timer

### 17.2 现有测试调整

- STT service test：SenseVoice provider 可 mock manager。
- Settings provider test：空闲释放配置应调用 ASR manager，而不是 LocalLlmService。
- AI model page test：不再出现本地文本模型入口。
- AiEnhanceService test：空 baseUrl 不再进入 local provider。

### 17.3 手工验证

macOS：

1. 下载 SenseVoice 模型。
2. 选择本地 ASR。
3. 设置“本地模型空闲自动释放”为 1 分钟。
4. 完成一次本地转写。
5. 观察 worker 进程存在，RSS 上升。
6. 1 分钟无新请求。
7. worker 进程退出。
8. 主应用 RSS 明显低于主进程内 FFI 方案。
9. 再次转写，worker 重新启动并成功。

Windows：

1. 重复上述流程。
2. 额外观察是否有窗口闪烁。
3. 检查 DLL 查找是否正常。

## 18. 分阶段实施

### 阶段 1：移除本地文本模型支持

目标：

- 消除本地 LLM 与本地 ASR 的概念混淆。
- 空闲释放配置不再绑定 `LocalLlmService`。

任务：

1. 删除 `LocalLlmAiProvider` 路由。
2. `AiEnhanceService` 不再识别空配置为本地模型。
3. 移除 `AiVendorPreset` / `assets/presets/models.json` 的本地文本模型。
4. 简化 `AiModelPage`，删除 GGUF 下载与推荐。
5. 清理 `SettingsProvider` 中本地文本模型条目。
6. 移除 `llamadart` 和 `local_model_prompt.md`。

### 阶段 2：抽离 SenseVoice 推理核心

目标：

- 让推理逻辑可在 worker 中调用。

任务：

1. 创建 `SenseVoiceWorkerCore`。
2. 从 `SenseVoiceFfiService` 迁移 WAV 读取、重采样、sherpa decode。
3. `SenseVoiceFfiService` 保留下载、路径解析、对外 facade。
4. 保持现有主进程内调用暂时可用，方便中间态测试。

### 阶段 3：实现 worker mode 与 IPC

目标：

- 子进程能独立执行 transcribe。

任务：

1. 新增 `local_asr_ipc.dart`。
2. 新增 `local_asr_worker_main.dart`。
3. `main.dart` 支持 `--asr-worker`。
4. worker 启动后输出 ready。
5. worker 支持 transcribe / checkAvailability / shutdown。

### 阶段 4：接入 `LocalAsrProcessManager`

目标：

- 主流程正式通过子进程执行本地 ASR。

任务：

1. 新增 `LocalAsrProcessManager`。
2. `SenseVoiceFfiService.transcribe()` 改为调用 manager。
3. `SenseVoiceFfiService.checkAvailability()` 改为调用 manager。
4. 实现队列、ready 超时、请求超时、crash 处理。

### 阶段 5：空闲释放配置迁移

目标：

- 复用设置项控制 ASR worker 生命周期。

任务：

1. `SettingsProvider.load()` 调用 `LocalAsrProcessManager.setIdleUnloadMinutes()`。
2. 新增 `localModelIdleUnloadMinutes` 命名。
3. UI 文案改为 ASR worker 语义。
4. 删除 `LocalLlmService.setIdleUnloadMinutes()` 调用。

### 阶段 6：平台打包与内存验证

目标：

- 验证 macOS / Windows 真实发布包可用。

任务：

1. macOS release 构建验证 worker 启动。
2. Windows release 构建验证 worker 启动。
3. 验证 native library 路径。
4. 验证 idle timeout 后 worker 退出。
5. 记录 RSS 前后对比。

## 19. 风险与应对

### 风险 1：复用 Flutter app executable 启动 worker 不稳定

表现：

- macOS dock 激活
- 多开主窗口
- Flutter engine 初始化失败

应对：

- worker flag 必须在 `WidgetsFlutterBinding.ensureInitialized()` 前处理。
- 如仍不稳定，切换 sidecar worker。

### 风险 2：worker 找不到 sherpa native library

表现：

- `sherpa.initBindings()` 抛错

应对：

- 主进程传递 native library search path。
- sidecar worker 与 native libs 放同目录。
- 打包脚本增加校验。

### 风险 3：请求期间 worker 崩溃

表现：

- stdout 断开
- exitCode 非 0

应对：

- 当前请求失败并提示用户。
- 下次请求重新拉起。
- 记录 stderr。

### 风险 4：频繁启动 worker 导致首次响应慢

应对：

- 默认 3 分钟空闲释放。
- 用户可设置 5 / 10 分钟。
- `0` 关闭自动释放，适合内存充足且追求速度的用户。

### 风险 5：删除本地文本模型影响已有用户配置

应对：

- 自动过滤本地文本模型配置。
- 若没有云端文本模型，自动关闭文本增强。
- 不删除已下载文件。
- 文案明确“本地模型仅用于语音识别”。

## 20. 推荐优先级

建议优先实现：

1. 移除本地文本模型支持。
2. 建立 worker IPC 协议和 fake worker 测试。
3. 让 SenseVoice 通过 worker 完成一次真实转写。
4. 接入空闲释放配置。
5. 做 release 包内存验证。

不建议先做：

- 多 worker 并发。
- 流式本地 ASR。
- UI 内存图表。
- 自动删除旧 GGUF 文件。

## 21. 验收标准

功能验收：

- 本地 ASR 转写成功。
- 云端 STT 不受影响。
- 文本增强云端模型不受影响。
- 本地文本模型入口不可见。
- 已保存本地文本模型不会继续被调用。

内存验收：

- 本地 ASR 推理完成后，worker 进程仍保留到 idle timeout。
- idle timeout 后 worker 进程退出。
- worker 退出后，其 RSS 完全释放。
- 主进程 RSS 不再长期持有 sherpa-onnx 模型级内存。

稳定性验收：

- 连续多次转写可复用 worker。
- 空闲释放后再次转写可重新启动 worker。
- worker 崩溃时用户得到明确错误。
- app 退出时 worker 不残留。

配置验收：

- “本地模型空闲自动释放”仍使用用户原有分钟数。
- 选 0 时不自动释放。
- 选 1 / 3 / 5 / 10 时按对应空闲时间退出 worker。

