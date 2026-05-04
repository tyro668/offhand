# Offhand 自适应语音纠错学习闭环设计

## 1. 背景

Offhand 现在已经不是单纯的“录音 -> STT -> 插入文本”链路。当前代码中已经有几块与“越用越聪明”相关的基础能力：

- `RecordingProvider` 会在每个录音分段前通过 `TermPromptBuilder` 构建 `SttRequestContext`，把术语、实体和上下文提示注入 STT。
- `SttService` 已支持携带 `SttRequestContext`，OpenAI 兼容、Gemini、Aliyun、本地 SenseVoice 链路都已经能不同程度消费 `prompt`。
- `CorrectionService` 会基于 `PinyinMatcher`、词典、会话术语、实体记忆和上下文调用 LLM 做 STT 后纠错。
- `SessionGlossary` 已能在一次录音内沉淀临时 `错词 -> 正词` 锚定，避免同一会话里反复错。
- 历史页有“同步修正”，可从用户编辑后的历史文本中提取候选，写入词典和实体记忆。
- 词典页已有待确认候选的接受、拒绝、批量处理能力。
- `CorrectionChangeLogService` 与 `CorrectionStatsService` 已经记录部分纠错变化和调用效率。

这些能力证明主方向已经正确：先用 STT 前提示降低初始错误，再用 STT 后纠错兜底，最后从用户改动中学习。当前不足是记忆来源和管理入口太多，学习闭环还偏“手动同步”和“短语候选”，缺少统一证据账本、拒绝状态、自动升级、持续评估和更明确的 UI 反馈。因此本设计聚焦于把现有能力收敛成可靠的个性化学习系统。

## 2. 目标

核心目标：

- 用户越常修正某类错词，后续相同或近似发音越容易被自动纠正。
- 用户确认过的专业词、人名、公司名、产品名、项目名和英文缩写能稳定进入 STT 前提示与 STT 后纠错。
- 用户拒绝或撤销过的记忆不会反复打扰，也不会再次被错误自动升级。
- 系统能解释“为什么这次被改成这个词”，并允许用户回滚。
- 学习能力默认本地化、可关闭、可清理，不把用户语音文本上传到额外服务做训练。

非目标：

- 不训练本地或云端 ASR 模型。
- 不把所有用户编辑自动变成强纠正规则。
- 不重写现有 `TermPromptBuilder + SttRequestContext + CorrectionService` 主链路。
- 不引入复杂的纯规则实体消歧引擎，最终语义判断仍交给现有 LLM 纠错链路。

## 3. 当前链路评估

### 3.1 已具备能力

语音输入主链路：

1. `RecordingProvider._buildSttRequestContext(...)`
2. `TermPromptBuilder.build(...)`
3. `SttService.transcribe(path, context: sttContext)`
4. `CorrectionService.correct(text)`
5. 可选 `CorrectionService.correctParagraph(...)`
6. 可选 `AiEnhanceService`
7. 写入 `Transcription`

现有长期记忆来源：

- `DictionaryEntry`：已确认的纠错和保留规则。
- `DictationTermPendingCandidate`：待用户确认的历史修正候选。
- `TermContextEntry`：从 Markdown 等外部资料导入的上下文参考。
- `EntityMemory / EntityAlias / EntityRelation / EntityEvidence`：实体记忆、别名、关系和来源证据。
- `CorrectionChangeLog`：实时和终态纠错的变化记录。

这些是当前实现里的存量能力，不应继续作为面向用户和主链路的长期分类。后续需要把它们整合成统一记忆库，只在兼容层保留旧模型。

召回和提示：

- `TermRecallService` 负责从会话 glossary、词典、外部上下文中挑选本次 STT 值得提示的术语。
- `EntityRecallService` 负责从实体记忆中挑选本次值得提示的实体。
- `TermPromptBuilder` 负责合并术语、实体和文档上下文，输出 `sttPrompt` 与纠错参考。
- `CorrectionService` 会在 `#R/#C/#E/#ER/#I` 中注入词典、上下文、实体和关系。

### 3.2 主要缺口

1. 记忆分类过多
   - 词典、待确认候选、实体、实体证据、上下文、会话锚定、纠错日志分散管理。
   - 主链路也需要从多个来源拼装 prompt 和纠错参考，后续扩展会越来越难维护。

2. 学习触发不够自动
   - 用户编辑历史后，需要主动点“同步修正”。
   - 录音结束时 `SessionGlossary` 里的强锚定还没有系统性转入统一记忆库。

3. 记忆证据太薄
   - `DictationTermPendingCandidate` 只有 `confidence`、`occurrenceCount`、`sourceHistoryId`。
   - 缺少最近命中时间、最近确认/拒绝时间、来源类型、使用后的成功率、撤销次数、上下文摘要。

4. 没有可管理的拒绝状态
   - 用户拒绝候选后只是删除。
   - 同样的 `original -> corrected` 以后可能再次被抽取出来打扰用户。

5. 自动升级策略缺失
   - 多次出现的高置信记忆仍需要用户手动接受。
   - 没有“弱参与纠错参考 -> active 启用”的分级。

6. 缺少闭环评估
   - 能看到纠错调用统计，但还不能回答：
     - 哪些规则真的减少了用户修改？
     - 哪些规则经常被用户撤销？
     - STT 前提示命中后是否提升了准确率？

7. 纠错来源不够可解释
   - `Transcription` 只有 `rawText` 和最终 `text`。
   - 用户看不到一次文本变化来自 STT prompt、实时纠错、终态纠错、AI 增强还是手动编辑。

## 4. 总体方案

新增一层“统一记忆与自进化闭环”，但不改变现有主链路。架构上只保留两类数据：

1. `AdaptiveMemoryStore`：统一记忆库
   - 面向运行时和用户管理。
   - 保存所有会影响识别、纠错、增强的长期和短期知识。
   - `TermPromptBuilder`、`CorrectionService`、实体召回和上下文召回都只从这里取可用记忆。

2. `MemoryEvidenceLog`：反馈证据账本
   - 面向学习、自我进化、解释和回滚。
   - 保存用户编辑、接受、拒绝、撤销、纠错命中、prompt 注入效果等事件。
   - 只追加事件，不直接参与 prompt；由评估器定期把证据折算到统一记忆库的状态和权重。

如果必须压到一个分类，也可以把 `MemoryEvidenceLog` 作为 `AdaptiveMemoryStore` 的内部 event log。但产品和工程上建议保留这两个逻辑分类：一个管理“当前知道什么”，一个管理“为什么知道、效果如何”。

```text
用户语音
  -> STT 前提示：TermPromptBuilder + SttRequestContext
  -> STT 原文
  -> 实时纠错：CorrectionService
  -> 终态回溯纠错
  -> AI 增强
  -> 历史记录
  -> 用户确认 / 编辑 / 撤销 / 拒绝
  -> LearningFeedbackService
  -> MemoryEvidenceLog
  -> MemoryEvolutionEngine
  -> AdaptiveMemoryStore
  -> 下一次 TermPromptBuilder 与 CorrectionService
```

建议新增服务：

- `AdaptiveMemoryStore`
  - 统一读写术语、纠错、保留、实体、别名、上下文参考、会话锚定和拒绝状态。
  - 对上层提供一个查询接口：`recall(query, scene, budget)`。
- `LearningFeedbackService`
  - 统一处理用户编辑、记忆接受、记忆拒绝、纠错撤销、会话结束沉淀。
- `MemoryEvidenceLog`
  - 存储反馈事件、证据片段和规则效果事件。
- `MemoryEvolutionEngine`
  - 根据证据账本更新记忆状态、权重、置信度、冷却期和召回优先级。
- `LearningDigestService`
  - 为 UI 生成“最近学到了什么”“哪些规则表现差”“哪些记忆待处理”的摘要。

这些服务复用现有 Provider 和主链路。第一阶段可继续存到 `AppDatabase` settings JSON；当记录量明显变大后，再迁移到独立表。迁移后，旧的 `dictionaryEntries`、`dictationTermPendingCandidates`、`termContextEntries`、`entityMemories` 等键只作为兼容读取来源。

## 5. 统一记忆模型

### 5.1 两类数据边界

从长期架构看，只允许两类数据存在：

- `MemoryItem`：当前系统可管理、可召回、可用于 prompt 或纠错的知识。
- `MemoryEvent`：用户和系统产生的反馈证据，用来解释、评估和进化 `MemoryItem`。

其他概念都应降级为 `MemoryItem` 的字段或 `MemoryEvent` 的事件类型，而不是新的记忆库：

- 待确认候选 = `MemoryItem.status = pending`
- 正式词典 = `MemoryItem.status = active`
- 会话锚定 = `MemoryItem.scope = session`
- 外部资料 = `MemoryItem.kind = reference`
- 实体和别名 = `MemoryItem.kind = entity`
- 拒绝记忆 = `MemoryItem.status = suppressed` 加一条 `reject` 事件
- 纠错统计 = 多条 `MemoryEvent` 聚合后的 `MemoryItem.stats`

### 5.2 MemoryItem

`MemoryItem` 是唯一运行时记忆实体。它既能表达传统词典，也能表达实体和上下文参考。

```text
MemoryItem
- id
- kind                        // correction / preserve / entity / reference
- status                      // pending / weak_active / active / suppressed / archived
- scope                       // session / user / imported
- original                    // STT 常见错词、别名、触发表达；可空
- canonical                   // 正确写法、实体主名、保留词；可空
- aliases                     // 多个别名或误识别写法
- content                     // reference 类型的上下文正文或摘要
- category
- source                      // manual / history_edit / session / markdown / system
                              // 持久化只存稳定来源代码，UI 通过 i18n 显示本地化来源名
- confidence                  // 置信度，来自证据聚合
- strength                    // 召回权重，来自效果反馈
- cooldown_until              // suppressed 后的冷却期
- first_seen_at
- last_seen_at
- last_used_at
- created_at
- updated_at
- stats
  - evidence_count
  - positive_count
  - negative_count
  - prompt_injection_count
  - correction_hit_count
  - user_kept_count
  - user_reverted_count
  - rejected_count
```

`kind` 只代表行为，不是管理入口。UI 不再分“词典、候选、实体、上下文”四套页面，而是在“记忆库”里用筛选器查看：

- 纠错规则：`kind = correction`
- 保留写法：`kind = preserve`
- 实体名称：`kind = entity`
- 参考上下文：`kind = reference`

### 5.3 MemoryEvent

`MemoryEvent` 是自我进化的原始材料。它不直接进入 prompt，必须经 `MemoryEvolutionEngine` 聚合后影响 `MemoryItem`。

```text
MemoryEvent
- id
- memory_id                   // 可空，新候选还没合并时为空
- event_type                  // observe / accept / reject / revert / prompt_injected / correction_hit / user_kept / user_edited / archive
- source_type                 // history_edit / session_glossary / correction_log / prompt_trace / manual
- source_ref                  // transcriptionId / sessionId / correctionLogId / promptTraceId
- original
- canonical
- before_text_excerpt
- after_text_excerpt
- raw_text_excerpt
- confidence_delta
- strength_delta
- created_at
```

关键事件：

- `observe`：系统观察到一次可能有价值的修正。
- `accept`：用户确认加入记忆库。
- `reject`：用户拒绝候选或永久忽略。
- `revert`：用户把系统改动撤回。
- `prompt_injected`：某条记忆进入了 STT prompt。
- `correction_hit`：某条记忆被纠错链路命中。
- `user_kept`：系统改动在后续编辑中被保留。
- `user_edited`：系统改动后又被用户编辑。

### 5.4 旧模型到统一模型的映射

迁移规则：

```text
DictionaryEntry(correction)
  -> MemoryItem(kind=correction, status=active, scope=user)

DictionaryEntry(preserve)
  -> MemoryItem(kind=preserve, status=active, scope=user)

DictationTermPendingCandidate
  -> MemoryItem(kind=correction, status=pending, scope=user)

SessionGlossary.TermPin
  -> MemoryItem(kind=correction, status=weak_active, scope=session)

TermContextEntry(reference)
  -> MemoryItem(kind=reference, status=active, scope=imported)

TermContextEntry(correctionHint)
  -> MemoryItem(kind=correction, status=pending 或 active, scope=imported)

EntityMemory + EntityAlias
  -> MemoryItem(kind=entity, status=active, aliases=[...], scope=user)

EntityRelation
  -> MemoryEvent(event_type=observe, source_type=entity_relation)
  或 MemoryItem.content 中的关系摘要

EntityEvidence
  -> MemoryEvent(event_type=observe, source_type=history_edit)

CorrectionChangeLog
  -> MemoryEvent(event_type=correction_hit / observe)
```

第一阶段不需要立刻删除旧模型。实现上可以先建 `AdaptiveMemoryRepository` 作为 facade：

- 读取时合并旧数据并输出 `MemoryItem` 列表。
- 写入新学习结果时优先写新模型。
- 接受候选时继续同步写 `DictionaryEntry`，保证现有 `PinyinMatcher` 和页面不坏。
- 等 UI 和召回链路都切到 `MemoryItem` 后，再做存储迁移。

### 5.5 记忆状态

统一状态只保留五个：

```text
pending      待确认，不进入 STT prompt，只在 UI 展示
weak_active  弱激活，可低权重参与 STT 后纠错，不进入 STT prompt
active       正式启用，可进入 STT prompt 和 STT 后纠错
suppressed   被拒绝或冷却，不参与召回，避免重复打扰
archived     归档，仅保留审计和回滚
```

状态转换：

```text
observe enough positive evidence
  pending -> weak_active

user accepts or auto-promote is enabled and evaluator approves
  weak_active -> active

user rejects
  pending/weak_active -> suppressed

user reverts active result repeatedly
  active -> weak_active 或 suppressed

user deletes
  any -> archived
```

### 5.6 记忆评分

每条 `MemoryItem` 都有两个核心分数：

- `confidence`：这条记忆是否正确。
- `strength`：这条记忆是否值得本次召回。

`confidence` 由证据决定：

- 用户确认、重复历史编辑、纠错后被保留会提升。
- 用户拒绝、撤销、冲突候选会降低。

`strength` 由场景和近期效果决定：

- 当前文本、最近历史、会话状态、实体关系、外部上下文命中会提升。
- 近期未命中、prompt 注入后无效果、被撤销会降低。

`TermPromptBuilder` 只关心最终排序后的召回结果，不关心来源来自旧词典还是实体库。

## 6. 学习和自我进化策略

### 6.1 学习来源

所有来源都先进入 `MemoryEvent`，再由 `MemoryEvolutionEngine` 合并或更新 `MemoryItem`。

1. 手动历史编辑
   - 当前已经支持，从 `rawText` 和编辑后 `text` 比较。
   - 改进点：保存为 `MemoryEvent(event_type=observe, source_type=history_edit)`，再合并进 `MemoryItem`。

2. 会话强锚定
   - 录音结束时扫描 `SessionGlossary.strongEntries`。
   - 若统一记忆库不存在同样映射，写入 `MemoryItem(kind=correction, status=weak_active, scope=session)`。

3. 纠错日志
   - 从 `CorrectionChangeLog.terms` 中读取 `observed/original/corrected`。
   - 只有满足局部短语、长度、非标点、非整句改写条件时才生成证据。
   - 纠错日志来源默认不直接生成 `active`，最多生成 `weak_active`。

4. 外部资料导入
   - Markdown 或手动导入不再直接变成多套上下文库。
   - 统一写入 `MemoryItem(kind=reference 或 correction/preserve, scope=imported)`。

5. 实体学习
   - 人名、公司名、产品名、项目名都写入 `MemoryItem(kind=entity)`。
   - 别名和误识别写入 `aliases`，不再单独管理一套实体别名库。

### 6.2 记忆合并

统一合并 key：

```text
kind + "|" + normalize(original) + "|" + normalize(canonical)
```

合并时更新：

- `stats.evidence_count += 1`
- `stats.positive_count += 1`
- `confidence = max(oldConfidence, eventConfidence)`
- `last_seen_at = now`
- `source` 合并或保留最高优先级来源
- 对实体类记忆合并 `aliases`
- 对 reference 类记忆合并来源摘要，不复制长文

如果同一 original 对应多个 canonical：

- 不自动覆盖 `active` 记忆。
- 新冲突项进入 `pending`，并标记 conflict。
- UI 让用户选择保留哪个，或全部忽略。

### 6.3 自动升级

自动升级必须保守，分两级：

第一级：`pending -> weak_active`

条件：

- `stats.evidence_count >= 2`
- `confidence >= 0.75`
- 未处于 `suppressed` 冷却期
- `original != canonical`
- 不是单字
- 不是整句差异
- 不与现有 `active` 记忆冲突

效果：

- 可进入 `CorrectionService` 的低权重 `#R` 参考。
- 不进入 STT prompt，避免 STT 初始输出被未确认规则污染。
- UI 显示为“已临时参与纠错，可确认启用”。

第二级：`weak_active -> active`

默认不完全自动执行，建议先做“建议自动启用”：

- `stats.evidence_count >= 3`
- `stats.positive_count >= 3`
- `stats.negative_count == 0`
- 最近 7 天至少出现 2 次
- 没有被用户撤销
- 同一 original 没有多个 canonical 冲突

产品策略：

- 默认在记忆库展示“一键确认高可信记忆”。
- 设置里提供“高可信记忆自动启用”开关，默认关闭。
- 开启后仅对非敏感、非冲突、高置信记忆自动启用，并在历史中可撤销。

### 6.4 降权和撤销

以下行为应增加负证据：

- 用户拒绝 pending 记忆。
- 用户把已纠错文本改回原词。
- 用户删除、禁用或归档 active 记忆。
- 纠错后马上被用户编辑为第三种写法。

降权规则：

- `stats.user_reverted_count >= 2`：给出停用建议。
- `stats.user_reverted_count >= 3` 且 `stats.user_kept_count == 0`：自动降为 `weak_active` 或 `suppressed`。
- 用户显式拒绝后把对应 `MemoryItem.status` 置为 `suppressed`，并写入 `MemoryEvent(event_type=reject)`。

### 6.5 统一召回

所有运行时召回都走一个接口：

```text
AdaptiveMemoryStore.recall(
  scene,
  currentText,
  recentHistory,
  sessionState,
  maxItems,
)
```

返回结果再由不同消费者转换：

- STT prompt：只使用 `status=active`，并优先使用 `kind=correction/preserve/entity/reference` 中高 `strength` 项。
- STT 后纠错：可使用 `status=active` 和少量 `weak_active`，但 `weak_active` 必须标注为低权重参考。
- AI 增强：使用 `active` 的 preserve、entity、reference，并限制正文长度。
- UI：展示全部状态，但默认隐藏 `archived`。

## 7. 链路改造

### 7.1 录音开始

维持现有流程：

- `MainScreen._configureCorrection(...)` 注入当前可召回的记忆项。
- `RecordingProvider` 重置 `CorrectionContext`、`SessionGlossary`、`SessionEntityState`。

新增：

- 为本次录音生成 `learningSessionId`。
- `LearningFeedbackService.startSession(...)` 记录本次使用的 provider、model、scene、记忆库版本摘要。

### 7.2 分段转写

现有：

- `_buildSttRequestContext(...)` 构建 STT prompt。
- `SttService.transcribe(...)` 执行 STT。
- `CorrectionService.correct(...)` 纠错并写入 `SessionGlossary`。

新增：

- `SttRequestContext` 增加只读追踪字段：

```text
- promptTraceId
- includedMemoryItemIds
- includedWeakMemoryItemIds
- memorySnapshotVersion
```

这些字段不传给 provider，只用于本地统计和解释。

### 7.3 录音结束

现有：

- 等待所有分段完成。
- 可选终态回溯纠错。
- 可选 AI 增强。
- 写入历史记录。

新增：

- `LearningFeedbackService.flushSession(...)`
  - 把 `SessionGlossary.strongEntries` 写为 `MemoryEvent`。
  - 将高置信会话锚定合并为 `MemoryItem(status=weak_active, scope=session)`。
  - 更新本次 prompt 中记忆项的 `prompt_injection_count`。
  - 记录最终 `Transcription.id` 和本次学习 session 的关系。

### 7.4 用户编辑历史

当前历史页有“同步修正”，建议拆成两个层次：

1. 保存编辑时自动记录证据
   - 用户保存历史编辑后，立即调用 `LearningFeedbackService.recordHistoryEdit(...)`。
   - 只生成 `MemoryEvent` 和 `MemoryItem(status=pending)`，不强制启用。

2. 用户手动同步时批量确认
   - “同步修正”保留，但语义变成“批量处理高可信记忆”。
   - 对 `stats.evidence_count >= 2` 或 `confidence >= 0.8` 的记忆优先展示。

### 7.5 记忆接受 / 拒绝

接受：

- 将 `MemoryItem.status` 更新为 `active`。
- 写入 `MemoryEvent(event_type=accept)`。
- 兼容期内继续同步写 `DictionaryEntry` 或实体旧模型，保证现有 `PinyinMatcher` 和页面不坏。
- 立即调用 `RecordingProvider.applySessionGlossaryOverride(...)`，让当前会话立刻生效。

拒绝：

- 将 `MemoryItem.status` 更新为 `suppressed`，必要时设置 `cooldown_until`。
- 写入 `MemoryEvent(event_type=reject)`。
- 不再删除证据，避免同样错误反复被重新学习。

## 8. UI 改进

### 8.1 历史页

每条历史记录增加轻量状态：

- `已由纠错修正`
- `已由 AI 增强`
- `已人工修正`
- `已贡献学习记忆`

编辑保存后：

- 不要求用户立刻跳去记忆库页。
- 显示短提示：`已记录 1 条可学习修正，确认后将用于后续听写。`

### 8.2 记忆库页

把现有词典页、待确认候选页、实体页、上下文页收敛成一个“记忆库”管理入口。默认按状态分组，按类型筛选。

待确认记忆增加字段：

- 证据次数
- 最近出现时间
- 来源类型（展示层必须通过 i18n 从稳定来源代码映射，不直接显示代码）
- 是否临时参与纠错
- 是否与现有规则冲突
- 是否被拒绝过

记忆操作：

- 确认启用
- 临时启用
- 忽略 90 天
- 永久忽略
- 合并到已有记忆
- 改为实体、纠错、保留或参考类型

### 8.3 Dashboard

新增“学习效果”区域：

- 本周新学到的术语数
- 待确认记忆数
- 高可信记忆数
- 被抑制记忆数
- active 记忆命中次数
- 用户撤销率最高的规则
- STT prompt 注入次数与纠错命中次数

### 8.4 解释与回滚

在历史记录或纠错日志中提供“为什么这样改”：

```text
反软 -> 帆软
原因：命中 active 记忆，来源：历史修正，已被确认 3 次
参与阶段：STT 后实时纠错
```

回滚动作：

- 仅回滚本条历史文本。
- 将对应 `MemoryItem` 降为 `weak_active`、`suppressed` 或 `archived`。
- 写入 `MemoryEvent(event_type=revert)`。

## 9. 隐私与安全

原则：

- 所有学习记忆默认存本地。
- 不上传用户历史文本到额外训练服务。
- 传给 STT / LLM 的内容只限本次请求所需的少量召回片段。
- 外部上下文文档进入 prompt 前必须经过长度截断。
- 用户可以一键清空：
  - 统一记忆库
  - 反馈证据账本
  - archived 记忆
  - suppressed 记忆

敏感内容处理：

- 对于超长句、整段文本、包含明显隐私结构的文本，不自动生成 active 记忆。
- `MemoryEvent` 中的 `before_text_excerpt/after_text_excerpt/raw_text_excerpt` 可只保留摘要或局部窗口。
- 设置中提供“保存学习证据原文”开关，默认可以只保存局部上下文。

## 10. 实施计划

### M1：低风险闭环

- 新增 `MemoryItem`、`MemoryEvent`、`AdaptiveMemoryRepository`。
- 新增 `LearningFeedbackService`。
- 用户保存历史编辑时自动写入 `MemoryEvent` 和 `MemoryItem(status=pending)`。
- 录音结束时把 `SessionGlossary.strongEntries` 写入 `MemoryEvent`，并合并到统一记忆库。
- 拒绝操作统一表现为 `MemoryItem.status=suppressed`，学习前先过滤 suppressed key。
- 记忆库页展示“被拒绝过 / 证据次数 / 最近出现时间”。

验收：

- 用户修正同一错词两次后，同一 `MemoryItem.stats.evidence_count` 能累计。
- 用户拒绝记忆后，同样映射不会马上再次出现。
- 会话内重复纠错能在录音结束后进入统一记忆库。

### M2：统一召回与效果统计

- `TermPromptBuilder` 改为从 `AdaptiveMemoryStore.recall(...)` 获取记忆。
- `CorrectionService` 改为消费统一召回结果，而不是分别消费词典、实体、上下文。
- 支持把 `weak_active` 记忆放入低权重纠错参考，但不进入 STT prompt。
- `CorrectionChangeLogService` 或新事件记录器写入 `MemoryEvent(event_type=correction_hit)`。
- Dashboard 展示基础学习效果。

验收：

- 多次出现但未确认的记忆可参与 STT 后纠错。
- active 记忆的命中、保留、撤销可以统计。
- weak_active 记忆不会污染 STT prompt。

### M3：高可信自动建议

- 新增 `MemoryEvolutionEngine` 的定时或触发式评估。
- 自动识别高可信 `MemoryItem`，展示“一键确认高可信记忆”。
- 设置中增加“高可信记忆自动启用”开关，默认关闭。
- 加入冲突检测和停用建议。

验收：

- 高频、高置信、无负反馈记忆会被标记为建议确认。
- 用户开启自动启用后，仅满足严格条件的记忆会自动变为 active。
- 用户撤销过的记忆会被降权或建议停用。

### M4：解释与回滚

- `SttRequestContext` 增加本地 trace 字段。
- 每条历史记录关联最近一次 prompt trace、纠错日志和规则来源。
- UI 支持查看“为什么这样改”。
- UI 支持按记忆项回滚、降级、suppressed 或 archived。

验收：

- 用户能看到一次纠错涉及的规则和来源。
- 用户能从历史记录直接停用错误记忆。
- 停用后下一次转写不再使用该记忆。

## 11. 测试计划

单元测试：

- `DictationTermMemoryService`：局部短语抽取、整句改写过滤、suppressed 过滤。
- `AdaptiveMemoryRepository`：旧模型合并、读写兼容、状态过滤。
- `LearningFeedbackService`：历史编辑、会话结束、纠错日志三类来源的事件写入和记忆合并。
- `MemoryEvolutionEngine`：pending、weak_active、active、suppressed、archived 状态转换。
- `TermPromptBuilder`：weak_active 只进入纠错参考，不进入 STT prompt。
- `SettingsProvider`：记忆接受、拒绝、合并、迁移兼容旧数据。

集成测试：

- 用户录音两次都把“反软”改为“帆软”，第三次对应记忆进入 weak_active。
- 用户确认“反软 -> 帆软”后，对应记忆变为 active，下一次 STT prompt 包含“帆软”，纠错 `#R` 包含映射。
- 用户拒绝“开会 -> 开胃”后，对应记忆变为 suppressed，同样映射不再出现。
- 用户禁用记忆后，该记忆不再进入 prompt 和纠错参考。

人工验收场景：

- 专业术语：`FineBI`、`MCP`、`Function Calling`。
- 中文近音：`反软 -> 帆软`、`墨提斯 -> Metis`。
- 人名实体：误识别别名进入 `MemoryItem(kind=entity)` 后，后续同上下文能纠正。
- 冲突记忆：同一个错词对应两个不同正词时不会自动升级。

## 12. 风险与控制

风险：自动学习错误规则，越用越偏。

控制：

- 默认不自动变为 active。
- 弱激活只参与 STT 后纠错，不参与 STT 前提示。
- suppressed 和撤销统计优先级高于正向证据。

风险：prompt 越来越长，成本和延迟上升。

控制：

- `AdaptiveMemoryStore.recall(...)` 继续限制召回数量。
- 按当前文本、最近历史、会话状态和规则效果排序。
- 低效或被撤销的记忆降权。

风险：用户不知道系统学了什么。

控制：

- 历史页提示新记忆。
- 记忆库页集中处理 pending、weak_active、suppressed 和 active 记忆。
- Dashboard 展示学习效果。
- 每条纠错可解释、可回滚。

风险：隐私数据被过度保存。

控制：

- 学习证据默认只存局部上下文。
- 提供清理入口。
- 不新增训练上传链路。

## 13. 推荐优先级

建议先做 M1 和 M2。它们改动小、收益直接，并且完全复用现有架构：

- M1 先把分散数据统一投影成 `MemoryItem` / `MemoryEvent`。
- M2 再让主链路从统一记忆库召回，而不是分别读词典、实体、上下文。

M3 和 M4 再解决“自动启用”和“可解释回滚”。这两个阶段涉及产品信任和 UI 复杂度，应该在有足够统计后再开放。
