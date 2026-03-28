# 语音输入自适应术语记忆设计

## 1. 背景与目标

当前应用已经具备一条相对完整的语音处理链路：

1. STT 将音频转成原始文本
2. `CorrectionService` 结合词典与拼音匹配做术语纠错
3. `AiEnhanceService` 做文本增强
4. 用户可在历史记录中手动修改最终文本

但现在“用户改过一次，下次同类发音更准”的闭环还不完整：

- 历史编辑只会产出 `DictationTermPendingCandidate`，默认仍需人工去词典页确认
- 已确认的词典主要作用在 STT 后纠错与 AI 增强，尚未系统性反哺 STT 前提示
- `SessionGlossary` 只解决单次会话一致性，没有沉淀为跨会话长期记忆
- 会议录制复用了纠错链路，但没有把“长期术语记忆”设计成统一能力

本方案目标：

- 优先解决语音输入场景中专业术语、人名、产品名、英文缩写识别不准的问题
- 让用户对历史记录的一次修正，能够稳定影响下一次相似发音的识别结果
- 会议场景复用同一套能力，以较低成本附带获益
- 保持架构优雅：长期记忆、会话记忆、STT 提示、STT 后纠错分层清晰

不追求：

- 一步到位做全自动“自学习字典”
- 让所有修改都无审核地直接进入强规则
- 强依赖单一厂商 STT 的专有能力

## 2. 现状代码评估

### 2.1 已有基础能力

#### 语音输入链路

- [`/Users/richie/Documents/work/offhand/lib/providers/recording_provider.dart`](/Users/richie/Documents/work/offhand/lib/providers/recording_provider.dart)
  - 分段录音
  - `SttService(config).transcribe(path)`
  - `CorrectionService.correct(text)`
  - 结束后可选 `correctParagraph`
  - 可选 `AiEnhanceService`
  - 历史记录落库为 `Transcription`

#### 会议链路

- [`/Users/richie/Documents/work/offhand/lib/services/meeting_recording_service.dart`](/Users/richie/Documents/work/offhand/lib/services/meeting_recording_service.dart)
  - 每个分段执行 STT
  - 分段后使用同一 `CorrectionService`
  - 再做增强、合并、摘要

#### 词典与拼音纠错

- [`/Users/richie/Documents/work/offhand/lib/models/dictionary_entry.dart`](/Users/richie/Documents/work/offhand/lib/models/dictionary_entry.dart)
  - 支持 correction / preserve
  - 支持 `pinyinPattern`
  - 支持来源 `manual` / `historyEdit`
- [`/Users/richie/Documents/work/offhand/lib/services/pinyin_matcher.dart`](/Users/richie/Documents/work/offhand/lib/services/pinyin_matcher.dart)
  - 字面匹配
  - 拼音精确匹配
  - 拼音模糊匹配
- [`/Users/richie/Documents/work/offhand/lib/services/correction_service.dart`](/Users/richie/Documents/work/offhand/lib/services/correction_service.dart)
  - 根据命中词典构造 `#R/#C/#I`
  - 命中时才调用 LLM，成本控制合理

#### 用户修改反哺的雏形

- [`/Users/richie/Documents/work/offhand/lib/screens/pages/history_page.dart`](/Users/richie/Documents/work/offhand/lib/screens/pages/history_page.dart)
  - 用户编辑历史文本后，会调用 `DictationTermMemoryService.extractCandidates`
- [`/Users/richie/Documents/work/offhand/lib/services/dictation_term_memory_service.dart`](/Users/richie/Documents/work/offhand/lib/services/dictation_term_memory_service.dart)
  - 从 before / after 中抽取短语替换候选
- [`/Users/richie/Documents/work/offhand/lib/providers/settings_provider.dart`](/Users/richie/Documents/work/offhand/lib/providers/settings_provider.dart)
  - 候选进入 `dictationTermPendingCandidates`
  - 可接受为正式 `DictionaryEntry`

#### 会话内记忆

- [`/Users/richie/Documents/work/offhand/lib/services/session_glossary.dart`](/Users/richie/Documents/work/offhand/lib/services/session_glossary.dart)
  - 会话内纠错命中可升级为强锚定
  - 后续纠错会自动注入 `#R`

### 2.2 当前主要缺口

1. 缺少统一的“术语记忆层”
   - 现在长期记忆在 `dictionaryEntries`
   - 待确认记忆在 `dictationTermPendingCandidates`
   - 会话记忆在 `SessionGlossary`
   - 三者关系明确但没有统一策略与状态流转

2. 缺少 STT 前提示注入
   - OpenAI STT 当前没有传 `prompt`
   - Gemini 虽然走 chat completions，但提示词是写死的
   - whisper.cpp 当前也没有传 initial prompt

3. 缺少“自动升级”的证据模型
   - 用户一次历史编辑只能得到待确认候选
   - 没有根据多次重复修正、命中频率、跨场景复现来自动提升可信度

4. 缺少“修改来源追踪”
   - `Transcription` 只有 `text/rawText`
   - 看不到本次最终文本是由 STT、纠错、增强、用户编辑中的哪一步得来
   - 不利于后续术语学习策略做精细判断

5. 缺少“短语级术语提示打包”
   - 词典可以很多，但真正应该注入给 STT / 纠错的应当是少量高相关术语
   - 目前只有 `ContextRecallService` 面向增强，尚未面向术语提示

## 3. 设计原则

1. 分层记忆
   - 长期记忆：跨会话稳定术语
   - 会话记忆：本次录音/会议内刚确认的术语
   - 待确认记忆：用户刚修过但还不够稳定的候选

2. 双阶段纠正
   - 第一阶段：STT 前提示，尽量让模型第一次就识别对
   - 第二阶段：STT 后纠错，作为跨厂商兜底

3. 保守学习
   - 不把一次整句重写直接变成强规则
   - 只学习短语级、可解释、可回滚的映射

4. 统一能力，双场景复用
   - 听写优先
   - 会议复用同一套记忆和提示构建器

5. 可观测
   - 术语从哪里来、何时生效、命中了几次、是否被用户撤销，都要可追踪

6. 支持冷启动
   - 除了“边用边学”，还要支持从外部资料提前导入术语
   - 导入的数据应能进入长期记忆或待确认区，而不是只能作为一次性提示

## 4. 核心方案

### 4.1 引入术语记忆分层模型

建议新增一个统一概念：`TermMemory`.

建议状态分为三层：

- `pending`
  - 来源于历史编辑、会议编辑、纠错回溯
  - 暂不进入强规则
- `accepted`
  - 用户已确认，进入长期词典
  - 可以参与 STT 前提示与 STT 后纠错
- `session`
  - 会话内临时锚定
  - 生命周期随录音或会议结束而失效

现有代码映射：

- `DictationTermPendingCandidate` = `pending`
- `DictionaryEntry` = `accepted`
- `SessionGlossary` = `session`

这意味着第一阶段不必推翻存量结构，而是在设计和接口层统一它们。

### 4.2 新增“术语提示构建器”

建议新增服务：

- `lib/services/term_prompt_builder.dart`

职责：

1. 输入当前场景信息
   - 当前模式：dictation / meeting
   - 当前最近文本
   - 历史记录
   - 长期词典
   - 会话 glossary

2. 输出两类提示
   - `sttPrompt`
   - `correctionReference`

输出示例：

```text
优先识别以下术语，并保持大小写与写法：
- 帆软
- FineBI
- DeepSeek
- MCP
- Function Calling
若听到相近发音，优先输出上述写法。
```

选择规则建议：

- 总量控制在 10 到 30 项
- 先选会话强锚定
- 再选近期高频 accepted 词典项
- 再选与当前上下文关键词相关的词典项
- pending 候选默认不进入 STT prompt，只在“高置信 + 多次出现”时可灰度进入 correction reference

### 4.3 STT 前提示注入

这是本方案对“识别准确率”提升最大的部分。

#### OpenAI 兼容 STT

当前 [`/Users/richie/Documents/work/offhand/lib/services/stt_providers/openai_stt_provider.dart`](/Users/richie/Documents/work/offhand/lib/services/stt_providers/openai_stt_provider.dart) 只传：

- `model`
- `response_format`
- `file`

建议新增可选参数：

- `prompt`

改造方向：

- 扩展 `SttService.transcribe(...)`
- 扩展 `SttProvider.transcribe(...)`
- 支持 `TranscriptionRequestContext`

示例：

```dart
class SttRequestContext {
  final String? prompt;
  final List<String> preferredTerms;
  final String scene; // dictation / meeting
}
```

#### Gemini STT

当前已是消息式请求，可直接把固定文案替换为动态 prompt：

- 现有固定文案：`请将这段音频准确转写为纯文本，仅返回转写结果。`
- 改为：基础指令 + 术语提示

#### whisper.cpp

当前 [`/Users/richie/Documents/work/offhand/lib/services/whisper_cpp_service.dart`](/Users/richie/Documents/work/offhand/lib/services/whisper_cpp_service.dart) 已构造 `TranscribeRequest`，但未传 initial prompt。

建议确认 `whisper_flutter_new` 是否支持：

- `prompt`
- `initialPrompt`

若支持，直接注入术语提示。
若不支持，则至少保留 STT 后纠错，不强行 fork 插件。

#### SenseVoice / 其他 provider

统一通过能力位声明：

```dart
class SttProviderCapabilities {
  final bool supportsPrompt;
  final bool supportsPreferredTerms;
}
```

这样 UI 和调用方不用依赖厂商分支硬编码。

### 4.4 STT 后纠错继续保留，但升级为“术语标准化层”

`CorrectionService` 不应被替代，而应升级定位：

- STT 前提示负责“尽量第一次识别对”
- `CorrectionService` 负责“跨 provider 的最终标准化”

建议保留现有 `#R/#C/#I` 机制，同时新增两个输入来源：

1. 会话强锚定
2. 高相关 accepted 词典项

建议新增方法：

```dart
CorrectionReferenceBundle buildReferenceBundle({
  required String rawText,
  required List<DictionaryEntry> dictionaryEntries,
  required SessionGlossary sessionGlossary,
  List<DictationTermPendingCandidate> pendingCandidates = const [],
});
```

好处：

- 让 `CorrectionService` 专注纠错
- 让“哪些术语应该参与本次纠错”从服务内逻辑剥离出来

### 4.5 用户修改后的学习闭环

建议把当前“编辑历史 -> 抽候选 -> 待确认”升级为四步闭环：

1. 用户编辑历史文本
2. 提取局部术语映射
3. 记录学习证据
4. 达到阈值后自动进入建议接受态

建议新增一张独立学习证据表，而不是只靠 pending candidate 聚合。

建议新增模型：

- `TermLearningEvent`

字段建议：

- `id`
- `sourceType`
  - `history_edit`
  - `meeting_edit`
  - `realtime_correction`
  - `retrospective_correction`
- `sourceRecordId`
- `rawSnippet`
- `beforeText`
- `afterText`
- `original`
- `corrected`
- `confidence`
- `scene`
- `provider`
- `model`
- `createdAt`

再在聚合层生成：

- `TermLearningAggregate`

字段建议：

- `original`
- `corrected`
- `eventCount`
- `uniqueSourceCount`
- `lastSeenAt`
- `avgConfidence`
- `autoPromotable`

自动升级规则建议：

- 一次编辑：进入 pending
- 2 次以上相同映射，且来自不同记录：pending 卡片置顶并标“高可信”
- 3 次以上，且平均置信度高：允许默认勾选“推荐加入词典”

默认仍不直接静默写入 accepted，除非未来加“自动学习模式”开关。

### 4.6 会话记忆与长期记忆的关系

现在 `SessionGlossary` 很适合做会话内一致性，但不应直接替代长期词典。

建议规则：

- `SessionGlossary`
  - 只影响当前录音 / 当前会议
  - 来源可以是实时纠错命中，也可以是用户在本次会话中手动确认
- `DictionaryEntry`
  - 影响所有未来会话
  - 只有用户明确接受，或达到自动学习策略门槛后才进入

建议在会话结束时执行一个“会话术语结算”动作：

- 将本次 `SessionGlossary` 中强锚定但词典尚不存在的映射，转为 pending candidates
- 让会议场景也能自然沉淀术语

这一步能补齐目前“会议附带解决即可”的要求。

### 4.7 术语相关性召回

当前 `ContextRecallService` 更偏向文本风格增强，不适合直接做术语提示召回。

建议新增：

- `TermRecallService`

职责：

- 从长期词典里找出与当前文本最相关的少量术语

召回信号建议：

1. 当前文本命中的关键词
2. 历史最近若干条文本中的实体词
3. 当前会话已经出现过的术语
4. 场景标签
   - 听写
   - 会议
   - 招聘/技术/产品等

排序分数建议：

- 会话强锚定加权最高
- 当前文本直接命中字面或拼音相近次之
- 近期历史共现再次之
- 很久以前只出现过一次的词典项最低

### 4.8 UI/交互建议

本期不建议大改页面，只做最有价值的增强。

#### 历史页

保留现有编辑交互，新增：

- 编辑完成后弹窗文案升级
  - 展示“本次将学习哪些术语”
  - 标识“仅当前会话生效 / 加入待确认 / 推荐加入词典”
- 若映射已经是 accepted
  - 不再重复入 pending
  - 给出“已存在于词典，后续会自动优先识别”

#### 词典页

pending 区增加两类标签：

- `高可信`
- `来自多次历史修正`

accepted 条目增加一个只读信息区：

- 来源：手动 / 历史修正 / 会议修正
- 命中次数
- 最近使用时间

#### 设置页

新增一个开关组即可：

- `启用术语自学习`
- `允许将已确认术语注入 STT 提示`
- `会议结束后将会话强锚定转为待确认候选`

默认建议：

- 自学习开启
- STT prompt 注入开启
- 自动接受关闭

### 4.9 外部 `.md` 批量导入能力

这是对“冷启动”和“团队已有术语资产复用”非常重要的一块。

目标：

- 允许用户从外部导入一个或多个 `.md` 文件
- 从已有产品文档、会议纪要、术语表、品牌资料中批量提取术语
- 在首次使用前就把高价值术语预热进系统

#### 为什么需要 `.md` 导入

仅靠“用户每次改一点，系统慢慢学”有两个问题：

- 冷启动太慢
- 团队往往已经有现成知识资产，例如术语表、项目说明、客户名单、产品文档

而当前应用已有：

- `DictionaryEntry`
- `DictationTermPendingCandidate`
- `TermPromptBuilder` 规划

所以最自然的做法，是让 `.md` 导入成为术语记忆层的一个新来源。

#### 导入后的目标落点

导入结果不建议只有一种落点，而是按置信度分层：

- `accepted`
  - 明确结构化术语，直接进入词典
- `pending`
  - 可能是术语，但还需要人工确认
- `reference-only`
  - 仅作为 prompt/召回参考，不直接生成纠错规则

推荐原则：

1. 明确的“错误写法 -> 正确写法”映射
   - 直接生成 `DictionaryEntry.correction`
2. 明确的标准术语、人名、产品名、英文缩写
   - 生成 `DictionaryEntry.preserve`
3. 仅在正文中高频出现、但没有清晰映射关系的词
   - 先进 pending 或 reference-only

#### 建议支持的 `.md` 形式

第一期建议支持两类格式。

第一类：结构化术语表

```md
# 术语表

- 帆软
- FineBI
- DeepSeek
- MCP
- Function Calling
```

这类内容适合导入为 preserve。

第二类：显式映射表

```md
# 语音纠正规则

- 反软 => 帆软
- 反睿 => 凡瑞
- fine bi => FineBI
- function call => Function Calling
```

这类内容适合导入为 correction。

第三类：标题 + 正文型知识文档

```md
# 客户名单

本期重点客户包括帆软、观远数据、DataFocus。

# 产品模块

报表中心、指标平台、权限域、离线计算引擎是当前重点模块。
```

这类内容不一定能直接生成 correction，但可以抽取候选标准术语。

#### 导入解析策略

建议新增：

- `lib/services/markdown_term_import_service.dart`

职责分三步：

1. Markdown 预处理
   - 去掉代码块
   - 去掉链接 URL，仅保留可见文本
   - 提取标题、列表项、表格单元格、强调文本

2. 术语抽取
   - 优先抽取列表项与表格项
   - 再抽取正文中高频实体词
   - 识别显式映射符号
     - `->`
     - `=>`
     - `→`
     - `：`

3. 分层落库
   - 明确映射的进入 correction
   - 明确标准词的进入 preserve
   - 不够稳定的进入 pending/reference-only

#### 建议新增导入来源类型

扩展 `DictionaryEntrySource` 或补充新字段：

- `markdownImport`

同时建议 `TermLearningEvent.sourceType` 增加：

- `markdown_import`

这样后续统计时可以区分：

- 用户编辑学到的
- 系统纠错学到的
- 外部文档预热导入的

#### 导入结果模型建议

建议新增：

- `MarkdownTermImportResult`

字段示例：

- `fileName`
- `acceptedCorrections`
- `acceptedPreserves`
- `pendingCandidates`
- `referenceOnlyTerms`
- `skippedItems`
- `warnings`

这样导入后 UI 能清晰反馈：

- 导入了多少条纠正规则
- 导入了多少条保留术语
- 有多少条进入待确认
- 哪些条目被跳过

#### 去重与冲突处理

导入能力一定要保守，否则很容易污染词典。

建议规则：

1. 若导入 correction 与现有 correction 完全一致
   - 跳过

2. 若导入 correction 的 `original` 已存在但 `corrected` 不同
   - 不直接覆盖
   - 进入 pending，并标记“与现有词典冲突”

3. 若导入 preserve 与现有 correction 冲突
   - 默认保留现有 correction
   - 新项进入 pending

4. 若正文里抽到非常长的短语
   - 不直接入词典
   - 只作为 reference-only 或丢弃

#### 与 STT prompt 的关系

导入的 `.md` 内容不应该“一导入就全量塞进 STT prompt”。

正确做法是：

- 导入只是进入术语记忆层
- 是否参与本次识别，由 `TermRecallService` 和 `TermPromptBuilder` 决定

也就是说：

- `.md` 负责补知识
- `TermRecallService` 负责挑选
- `TermPromptBuilder` 负责生成本次 prompt

这样即使导入了 500 条术语，也只会挑当前最相关的 10 到 30 条给识别链路。

#### UI 建议

建议在词典页增加一个导入入口：

- `导入 Markdown`

交互建议：

1. 选择一个或多个 `.md` 文件
2. 先解析，展示预览摘要
3. 用户确认后执行导入
4. 导入结果落入：
   - 已接受词典
   - 待确认候选
   - 可选的 reference-only 区域

导入预览卡片建议展示：

- 文件名
- 检测到的 correction 数
- preserve 数
- pending 数
- 冲突数

#### Phase 建议

这块能力建议插入到原来的 Phase 2 和 Phase 3 之间，作为一个独立阶段。

### Phase 2.5：外部知识预热导入

目标：让团队已有的 Markdown 资料直接转化为术语资产，降低冷启动成本。

内容：

1. 新增 `MarkdownTermImportService`
2. 支持导入单个或多个 `.md`
3. 支持列表、表格、显式映射的解析
4. 导入结果按 accepted / pending / reference-only 分层
5. 词典页增加导入入口与结果预览

收益：

- 新项目可快速预热术语
- 专业领域词汇不必等用户逐条修正
- 团队已有文档资产可以直接复用

## 5. 数据与接口设计

### 5.1 建议新增实体

#### `TermLearningEvent`

建议路径：

- `lib/models/term_learning_event.dart`
- `lib/database/term_learning_event_entity.dart`

用途：

- 保留每次学习证据，支持统计和回滚

#### `SttRequestContext`

建议路径：

- `lib/models/stt_request_context.dart`

```dart
class SttRequestContext {
  final String scene;
  final String? prompt;
  final List<String> preferredTerms;
  final List<String> preserveTerms;
}
```

#### `TermPromptBundle`

建议路径：

- `lib/models/term_prompt_bundle.dart`

```dart
class TermPromptBundle {
  final String sttPrompt;
  final List<String> preferredTerms;
  final List<String> correctionReferences;
}
```

#### `MarkdownTermImportResult`

建议路径：

- `lib/models/markdown_term_import_result.dart`

```dart
class MarkdownTermImportResult {
  final String fileName;
  final List<DictionaryEntry> acceptedEntries;
  final List<DictationTermPendingCandidate> pendingCandidates;
  final List<String> referenceOnlyTerms;
  final List<String> warnings;
}
```

### 5.2 建议新增服务

- `TermPromptBuilder`
- `TermRecallService`
- `TermLearningService`
- `MarkdownTermImportService`

职责划分：

- `TermLearningService`
  - 记录学习事件
  - 聚合证据
  - 生成 pending candidate
- `TermRecallService`
  - 对 accepted/session 记忆做相关性召回
- `TermPromptBuilder`
  - 把召回结果拼装成 STT prompt 与纠错参考
- `MarkdownTermImportService`
  - 解析外部 `.md`
  - 抽取术语与映射
  - 生成 accepted / pending / reference-only 三类结果

### 5.3 现有接口改造建议

#### `SttService`

从：

```dart
Future<String> transcribe(String audioPath)
```

改为：

```dart
Future<String> transcribe(
  String audioPath, {
  SttRequestContext? context,
})
```

#### `SttProvider`

同步扩展为：

```dart
Future<String> transcribe(
  String audioPath, {
  SttRequestContext? context,
})
```

#### `RecordingProvider`

在 `_runSegmentWorker` 和 `_stopAndTranscribeInBackground` 中：

- 先基于当前会话 + 长期词典构建 `TermPromptBundle`
- 再调用 `SttService.transcribe(..., context: ...)`

#### `MeetingRecordingService`

在 `_processSegment` 中做同样注入，复用统一 builder。

## 6. 推荐落地顺序

### Phase 1：最小可见收益

目标：先让“已确认术语”真正提升下一次识别准确率。

内容：

1. 新增 `SttRequestContext`
2. 改造 `SttService` / `SttProvider`
3. 新增 `TermPromptBuilder`
4. 将 accepted dictionary + session glossary 注入 STT prompt
5. 听写链路先接入
6. 会议链路复用

收益：

- 不需要大改数据库
- 代码改动集中
- 对专业术语识别最直接

### Phase 2：把学习闭环补齐

目标：让用户修改不只是“留下一个候选”，而是形成可统计的学习证据。

内容：

1. 新增 `TermLearningEvent`
2. 历史编辑时记录 learning event
3. 会议编辑也记录 learning event
4. pending candidate 增加聚合统计
5. 词典页显示“高可信 / 多次修正”

收益：

- 产品上更像“系统真的在学”
- 为后续自动推荐接受打基础

### Phase 3：策略优化

目标：降低 prompt 污染，提升术语命中率。

内容：

1. 新增 `TermRecallService`
2. 按上下文只召回高相关术语
3. 会话结束时把 glossary 强锚定转 pending
4. 增加命中率与学习效果统计

收益：

- 更稳
- 更省 token
- 会议场景收益明显

### Phase 2.5：外部 Markdown 术语导入

目标：支持从团队已有文档中批量预热术语系统。

内容：

1. 新增 `MarkdownTermImportService`
2. 支持 `.md` 文件选择与解析预览
3. 支持列表、表格、显式映射解析
4. 支持导入到 accepted / pending / reference-only
5. 与 `TermRecallService` 打通，让导入术语参与后续识别

收益：

- 更适合企业/团队冷启动
- 新行业、新客户场景切换更快
- 术语积累不再只依赖人工逐条修正

## 7. 风险与应对

### 风险 1：错误术语被学进去

应对：

- 默认 pending，不自动 accepted
- 一次整句大改不直接入规则
- 仅学习短语级映射
- 提供 reject / disable / rollback

### 风险 2：prompt 过长，反而影响识别

应对：

- 严格限制注入术语数量
- 只注入高相关、高频、高置信术语
- accepted 全量不直接塞给 STT

### 风险 3：不同 provider 对 prompt 支持差异大

应对：

- Provider capability 声明化
- 支持 prompt 的走 STT 前增强
- 不支持的继续依赖 `CorrectionService`

### 风险 4：会议术语和听写术语相互污染

应对：

- 统一长期词典，但会话召回按场景加权
- learning event 保留 scene 字段
- 后续可按场景做过滤

### 风险 5：Markdown 文档正文噪声太大，导入后污染词典

应对：

- 结构化内容优先，正文抽取保守
- 明确映射才直接入 correction
- 普通正文高频词默认先进 pending 或 reference-only
- 导入前展示预览，导入后允许批量回滚

## 8. 结论

最优雅、也最贴合当前代码的路线，不是重写识别系统，而是在现有架构上补齐三层能力：

1. `TermLearningService`
   - 负责把“用户修改”变成结构化学习证据

2. `TermPromptBuilder`
   - 负责把长期记忆与会话记忆转成 STT prompt

3. `TermRecallService`
   - 负责只挑当前最相关的术语参与识别与纠错

4. `MarkdownTermImportService`
   - 负责把外部 `.md` 文档转成可复用的术语资产

这样做的结果是：

- 语音输入能先通过 STT prompt 提前变准
- 即便 STT 没识别对，后面还有 `CorrectionService` 兜底
- 用户在历史中改过一次，系统会先记住，再逐步学会
- 团队已有 Markdown 文档也能直接转成术语资产，解决冷启动
- 会议场景几乎零额外架构成本就能获得同样收益

## 9. 本仓库建议的首批实施点

如果按投入产出比排序，我建议先做这 6 个点：

1. 扩展 `SttService.transcribe` 支持 `SttRequestContext`
2. 给 OpenAI / Gemini provider 接入术语 prompt
3. 新增 `TermPromptBuilder`，先只消费 accepted dictionary + session glossary
4. 听写链路在 STT 前注入术语 prompt
5. 会议分段链路复用同一 builder
6. 会话结束时把 `SessionGlossary` 强锚定转成 pending candidate
7. 增加 Markdown 导入入口，支持团队术语预热

这 6 个点完成后，产品体验上就已经能明显感受到：

- 改过一次的专业术语，下一次更容易对
- 同一次会议里术语会越来越稳定
- 词典不再只是“事后纠错”，而开始参与“事前识别”
- 新项目可以先导入 `.md` 资料，再开始用，避免冷启动阶段识别很差
