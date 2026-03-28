# 跨应用语音输入的术语记忆设计

## 背景

Offhand 的核心场景不是会议纪要，而是类似 Typeless 的跨应用语音输入：

- 用户在任意应用里定位光标
- 触发快捷键开始录音
- Offhand 完成 `STT -> 纠错 -> 文本增强`
- 最终通过辅助功能把文本插入当前应用

这条链路的核心价值不是“保存一篇会议记录”，而是“在任何应用中尽可能稳定地打出正确术语”。

当前系统已经有三部分能力：

1. 实时听写主链路
   - `lib/providers/recording_provider.dart`
   - 最终结果会插入当前光标所在应用

2. 词典与纠错
   - `SettingsProvider.dictionaryEntries`
   - `PinyinMatcher`
   - `CorrectionService`
   - `SessionGlossary`

3. 历史记录
   - `Transcription`
   - `HistoryPage`

但还缺少一条关键能力：

- 用户对历史输出结果做过人工修正之后，这些修正没有回流到下一次听写中。

于是同一个术语问题会反复出现：

- 这次把“反软”手改成“帆软”
- 下次在飞书、Notion、微信、浏览器输入时，还是可能继续出现“反软”

本设计要解决的，就是“跨应用语音输入中的长期术语记忆”问题。

---

## 目标

### 功能目标

- 支持用户对历史听写结果进行编辑修正。
- 从“原始结果 -> 用户修正结果”中提取稳定的术语映射。
- 将这些映射沉淀为后续听写可复用的术语记忆。
- 让未来在任意应用中的语音输入都能受益。

### 体验目标

- 用户不需要每次都手动去词典页补规则。
- 用户做过一次修正，系统应该“越来越懂他的术语”。
- 保证谨慎，不能因为一次整句改写污染长期词典。

### 非目标

- 本期不做会议场景优先设计。
- 本期不做跨设备云同步。
- 本期不做任意复杂改写的语义理解。
- 本期不把所有编辑都自动写成正式词典。

---

## 核心问题

### 当前主链路

现有听写链路大致是：

1. `RecordingProvider.startRecording()`
2. 分段 STT
3. `CorrectionService.correct()`
4. 可选 `AiEnhanceService.enhance()`
5. `OverlayService.insertText(finalText)`
6. 结果保存为 `Transcription`

### 当前不足

问题不在“当次纠错”，而在“长期复用”：

- `SessionGlossary` 只在当前录音会话有效
- 历史记录只是回看，没有结构化修正入口
- 用户在外部应用里改过的文字，系统完全不知道
- 用户即使在历史页看到错误，也无法把修正沉淀为规则

### 结论

要解决跨应用输入的术语识别问题，必须在“历史修正 -> 长期记忆 -> 后续纠错”之间建立回流链路。

---

## 用户故事

### 用户故事 1：品牌名修正

用户说：

- `反软报表`

系统输出：

- `反软报表`

用户在目标应用里其实手动改成了：

- `帆软报表`

下一次用户至少应能在 Offhand 的历史中把这条结果改成“帆软报表”，并让系统记住：

- `反软 -> 帆软`

### 用户故事 2：英文术语规范化

用户说：

- `open api 文档`

系统输出：

- `open api 文档`

用户更希望最终统一为：

- `OpenAPI 文档`

后续再说类似内容时，系统应能稳定输出 `OpenAPI`。

### 用户故事 3：团队术语

用户团队内部经常说：

- `星阔`
- `Metis`
- `Agent 网关`

系统经过几次修正后，应逐渐积累用户自己的术语库，而不是每次重新猜。

---

## 设计原则

1. 以听写主链路为中心
   - 会议能力是旁支，跨应用输入是主干。

2. 人工修正优先级最高
   - 用户亲手改过的内容，是最高价值监督信号。

3. 长短期记忆分层
   - `SessionGlossary` 负责单次会话
   - “术语记忆库”负责跨会话

4. 保守自动化
   - 自动提取候选，但不轻易直接升级为正式规则。

5. 最大化复用现有纠错体系
   - 尽量让沉淀结果最终回到 `dictionaryEntries` 或等价生效层
   - 不再另造一套并行纠错引擎

---

## 总体方案

围绕“历史结果可编辑”增加一条回流链路：

1. 听写结果落库为 `Transcription`
2. 用户在历史页对结果做编辑
3. 保存时拿到：
   - `beforeText`
   - `afterText`
   - 可选 `rawText`
4. 从差异中抽取术语候选
5. 候选先进入“术语记忆候选池”
6. 候选经过确认或累计命中后升级为长期可生效规则
7. 后续新的听写请求中，这些规则参与 `CorrectionService`

---

## 为什么不能只靠 SessionGlossary

`SessionGlossary` 已经很有价值，但它解决的是：

- 一次录音会话内的术语一致性

它不能解决：

- 今天在微信里修正过的术语，明天在浏览器里继续生效
- 不同会话之间积累用户长期用词习惯
- 基于历史修正沉淀个人化术语库

所以我们需要新增一个“跨会话术语记忆层”。

---

## 信息来源设计

对于术语记忆，输入信号可以分三类：

### A. 词典显式录入

来源：

- 用户主动在词典页新增

特点：

- 置信度最高
- 立即生效

### B. 会话内自动锚定

来源：

- `SessionGlossary.extractAndPin()`

特点：

- 仅在当前会话有效
- 适合短期一致性

### C. 历史编辑回流

来源：

- 用户对历史听写结果的人工修正

特点：

- 是本设计重点
- 介于“自动发现”和“人工确认”之间

---

## UI 设计

## Phase 1：历史结果支持编辑

当前 `HistoryPage` 只有：

- 复制
- 删除
- 查看 rawText

建议新增：

- 编辑按钮
- 保存/取消按钮

编辑对象：

- `Transcription.text`

保留只读字段：

- `rawText`
- `createdAt`
- `provider`
- `model`

### 交互建议

每条历史记录卡片支持：

1. 查看结果文本
2. 点击“编辑”
3. 修改文本
4. 点击“保存”
5. 保存后提示：
   - `已识别出 1 条术语修正候选`
   - 或 `本次修改未识别出可复用术语`

---

## 数据模型设计

### 1. 扩展 `Transcription`

当前 `Transcription` 为不可编辑模型：

- `id`
- `text`
- `rawText`
- `createdAt`
- ...

建议新增字段：

- `editedText`
  - 用户最终确认后的文本
- `lastEditedAt`
- `editSource`
  - `history_manual_edit`

或者保持 `text` 为最终值，同时新增：

- `originalText`
  - 首次生成结果

更推荐第二种结构：

- `originalText`
  - 初次生成时的最终输出
- `text`
  - 当前生效文本
- `rawText`
  - 原始 ASR / 回溯纠错输入

原因：

- 后续 diff 抽取时，需要稳定拿到“首次结果”和“当前结果”
- 避免反复编辑导致基线丢失

### 2. 新增模型：`TermMemoryCandidate`

建议新增独立候选模型，不要直接落正式词典。

字段建议：

- `id`
- `sourceType`
  - `history_edit`
- `sourceId`
  - 对应 `transcription.id`
- `original`
- `corrected`
- `confidence`
- `status`
  - `pending`
  - `accepted`
  - `rejected`
  - `auto_promoted`
- `occurrenceCount`
- `createdAt`
- `updatedAt`

### 3. 新增模型：`TermMemoryRule`

当候选真正生效时，可转成正式长期规则。

两种落地方式：

1. 直接转为 `DictionaryEntry`
2. 新建独立长期规则模型，再在运行时并入词典视图

建议优先选 1：

- 实现成本更低
- 可直接复用 `SettingsProvider.dictionaryEntries`
- `CorrectionService` 无需改主路径

---

## 抽取策略

## 输入

- `beforeText`
  - 历史记录编辑前文本
- `afterText`
  - 历史记录编辑后文本
- `rawText`
  - 可选，用于辅助判断是否为术语纠错

## 输出

- 一组候选映射：
  - `original -> corrected`

## 抽取流程

### 1. 轻量规范化

- 统一空白
- 统一连续换行
- 不改变大小写语义
- 不移除中文/英文原貌

### 2. diff 分析

找出 `beforeText` 与 `afterText` 中的局部替换片段。

只重点关注：

- 短语级替换
- 术语级替换
- 大小写规范化
- 连字符/空格形式规范化

### 3. 候选筛选

仅保留满足以下条件的替换：

- `original` 与 `corrected` 都非空
- 长度适中，建议 2~32
- 不跨多行
- 不是纯标点变化
- 不是纯 Markdown 格式变化
- 不属于大段句子重写

### 4. 候选打分

建议置信度启发式：

- 中文短术语替换：高分
- 英文术语大小写规范：中高分
- 与 `rawText` 中误识别形式接近：加分
- 与历史已有候选一致：加分
- 长句替换：降分
- 包含大量功能词：降分

### 5. 升级策略

- `高置信 + 重复出现` -> `auto_promoted`
- `中置信` -> `pending`
- `低置信` -> 丢弃或仅记录日志

---

## 生效路径设计

### 路径 1：正式词典生效

对 `accepted/auto_promoted` 候选，转换成正式 `DictionaryEntry`：

- `type = correction`
- `original = 错词`
- `corrected = 正词`

这样后续听写时会自然进入：

- `PinyinMatcher`
- `CorrectionService`
- `AiEnhance` 后的最终规范化

### 路径 2：当前会话即时受益

如果用户是在一轮录音结束后、下一轮录音开始前完成了历史修正，也可以同步注入：

- `RecordingProvider.applySessionGlossaryOverride()`

不过这只是增强项，不是主路径。

---

## 模块改动建议

### 1. `HistoryPage`

新增：

- 历史文本编辑能力
- 保存后触发术语候选抽取

### 2. `RecordingProvider`

新增职责：

- 更新历史记录文本
- 调用“历史编辑术语抽取服务”

建议新增接口：

```dart
Future<void> updateHistoryText(
  String transcriptionId,
  String newText,
);
```

或：

```dart
Future<HistoryEditSaveResult> saveHistoryEdit({
  required String transcriptionId,
  required String beforeText,
  required String afterText,
});
```

### 3. `HistoryDb`

新增：

- 更新历史记录

例如：

```dart
Future<void> update(Transcription item)
```

### 4. 新服务：`DictationTermMemoryService`

负责：

- 计算 diff
- 提取候选
- 置信度打分
- 去重合并
- 升级为正式词典

### 5. `SettingsProvider`

新增：

- 管理“术语记忆候选”
- 将已确认候选并入 `dictionaryEntries`

---

## 与目标应用编辑行为的边界

有一个现实边界必须明确：

- 用户在微信、浏览器、文档软件里直接改字，Offhand 当前无法稳定感知这些外部编辑。

所以本设计不能假设：

- “用户在外部应用改了字，系统就自动知道”

可行路径只有两种：

1. 用户回到 Offhand 历史页修正
2. 用户手动加入词典

因此，本期重点是：

- 把 Offhand 历史页做成“用户回溯修正的承接面”

而不是监听第三方应用内的编辑事件。

---

## 风险

### 风险 1：整句改写误抽术语

例子：

- `这个方案不太行`
- `这个方案需要进一步评估`

这不是术语映射，不应进入长期记忆。

处理：

- 限制只抽短语级替换
- 长句重写直接忽略

### 风险 2：一次错误编辑污染长期词典

处理：

- 候选先进入 `pending`
- 多次出现或用户确认后再生效

### 风险 3：同一错词对应多个正词

例子：

- 某些同音词在不同业务上下文下含义不同

处理：

- 冲突候选不自动升级
- 交由用户确认

### 风险 4：词典膨胀

处理：

- 候选和正式词典分层
- 支持筛选“来源=历史修正”
- 定期清理 rejected / 长期未确认项

---

## 统计与观测

建议新增指标：

- `dictation_history_edit_total`
- `dictation_term_candidate_extracted_total`
- `dictation_term_candidate_accepted_total`
- `dictation_term_candidate_auto_promoted_total`
- `dictation_term_candidate_rejected_total`
- `dictation_term_candidate_conflict_total`

关注指标：

- 候选接受率
- 自动升级命中率
- 用户是否愿意使用历史修正入口

---

## 分阶段落地

### Phase 1：历史可编辑

- 历史页支持编辑结果文本
- 保存时做 diff 抽取
- 候选落库为 `pending`

### Phase 2：候选管理

- 在词典页显示“来源=历史修正”的候选
- 支持接受/拒绝

### Phase 3：自动升级

- 同候选多次出现时自动转为正式词典项

### Phase 4：更强主链路融合

- 在听写开始前加载长期术语记忆
- 与 `SessionGlossary`、词典形成统一术语层

---

## 验收标准

1. 用户能在历史页编辑一条听写结果并保存。
2. 若编辑中包含明确术语修正，系统能生成候选规则。
3. 用户确认后，该规则能影响下一次跨应用语音输入。
4. 同术语问题重复修正多次后，系统可自动提升其生效优先级。
5. 对整句改写、格式修改，不会产生大量错误候选。

---

## 结论

要解决 Offhand 这类跨应用语音输入工具的术语识别问题，关键不是继续优化会议纪要，而是让“历史听写结果的人工修正”变成长期可复用的术语记忆。

一句话说，就是：

- 用户每改一次，系统都应该更懂他下一次想说什么。
