# 会议润色文本编辑回流到纠错记忆的设计

## 背景

当前会议链路已经具备两项相邻但尚未打通的能力：

1. 会议转写与润色
   - 分段文本会经过 `STT -> CorrectionService -> AI Enhance`，最终沉淀到 `MeetingSegment.transcription / enhancedText`。
   - 会议结束后会生成 `MeetingRecord.fullTranscription` 和 `summary`。

2. 会议详情页人工编辑
   - 用户已经可以在会议详情页直接编辑完整文稿，并保存到 `MeetingRecord.fullTranscription`。
   - 相关入口已存在：
     - `lib/screens/pages/meeting_detail_page.dart`
     - `lib/providers/meeting_provider.dart` 中的 `updateMeetingFullTranscription()`

但目前人工编辑后的内容只停留在“这一次会议的最终文稿”，没有回流到后续会话的纠错链路中。结果是：

- 用户今天把“反软”改成“帆软”，明天新的录音里仍可能再次出现“反软”；
- 编辑行为没有沉淀成术语资产；
- 系统已有的 `SessionGlossary`、词典、拼音召回机制没有吃到这部分高价值监督信号。

本设计的目标，是让“会议润色文本的人工修正”成为后续录音和会议中的可复用纠错记忆。

---

## 目标

### 功能目标

- 支持用户继续编辑会议润色后的完整文稿。
- 在用户保存编辑后，自动从“保存前文本”和“保存后文本”中抽取可复用的词语/术语修正规则。
- 将这些规则沉淀为后续可复用的纠错知识，参与未来录音/会议的术语修正。
- 用户可以查看、确认、关闭或删除这些由历史编辑生成的规则。

### 非目标

- 本期不做全文级版本管理系统。
- 本期不试图从任意复杂段落改写中完美还原所有编辑意图。
- 本期不直接修改原始分段音频或重新对齐时间戳。
- 本期不将“所有编辑差异”都自动升格为强规则，仍需做保守筛选。

---

## 现状

### 已有能力

- 词典持久化与纠错入口：
  - `SettingsProvider.dictionaryEntries`
  - `PinyinMatcher`
  - `CorrectionService`
- 会话级短期记忆：
  - `SessionGlossary`
  - 适合单次录音中保持术语一致性
- 会议详情页编辑：
  - `MeetingDetailPage._saveDetail()`
  - `MeetingProvider.updateMeetingFullTranscription()`

### 缺失能力

- 无“用户编辑差异”的结构化存储；
- 无“从历史编辑提炼词语修正规则”的服务；
- 无“由历史编辑生成的规则”的置信度/来源管理；
- 无“自动抽取后待确认”的交互；
- 无“将历史编辑记忆注入未来纠错链路”的统一入口。

---

## 用户故事

### 用户故事 1

用户在会议详情中把：

- `反软报表做得不错`

改成：

- `帆软报表做得不错`

保存后，系统识别出一条候选修正规则：

- `反软 -> 帆软`

以后再次录音时，系统优先把“反软”纠正成“帆软”。

### 用户故事 2

用户把：

- `open api`

改成：

- `OpenAPI`

系统识别为规范化修正，并在后续文本中维持统一大小写。

### 用户故事 3

用户做的是整句重写，而不是术语修正，例如：

- `这个方案不太行`

改成：

- `这个方案需要进一步评估`

系统不应贸然抽取出低质量词典规则。

---

## 设计原则

1. 保守抽取
   - 宁可少抽，不要误抽。

2. 来源可追踪
   - 每条自动生成的规则都要能追溯到哪次会议、哪次保存。

3. 人工可控
   - 用户能看到、关闭、删除、合并自动生成规则。

4. 分层记忆
   - 会话短期记忆继续由 `SessionGlossary` 承担；
   - 跨会议长期记忆由新的“编辑纠错记忆”承担。

5. 与现有词典兼容
   - 优先复用现有 `DictionaryEntry`、`CorrectionService`、`PinyinMatcher` 机制，避免并行两套纠错系统。

---

## 总体方案

保存会议全文编辑时，引入一条新链路：

1. 用户编辑 `fullTranscription`
2. 保存前拿到旧文本 `before`
3. 保存后拿到新文本 `after`
4. 对 `before/after` 做差异分析
5. 从差异中提取“候选术语修正规则”
6. 将候选规则写入“编辑纠错记忆”
7. 经过自动置信度判定和用户确认后，转成可生效词典项
8. 后续录音/会议纠错时，统一参与 `CorrectionService`

---

## 数据模型设计

### 新增模型：`MeetingEditCorrectionCandidate`

建议新增一个独立模型，用于承接“从历史编辑抽取出的候选规则”，而不是直接写进 `DictionaryEntry`。

建议字段：

- `id`
- `meetingId`
- `sourceType`
  - 固定值：`meeting_full_transcription_edit`
- `beforeText`
- `afterText`
- `original`
  - 候选错误词
- `corrected`
  - 候选修正词
- `confidence`
  - 0~1
- `status`
  - `pending`
  - `accepted`
  - `rejected`
  - `auto_promoted`
- `occurrenceCount`
  - 同规则累计出现次数
- `createdAt`
- `updatedAt`

### 新增存储

短期方案建议先复用 `settings` 表，以 JSON 列表方式持久化，类似：

- `meeting_edit_correction_candidates_v1`

中期如果候选量明显增长，再单独建表。

原因：

- 当前项目已有多个轻量配置/统计走 `settings` 表；
- 本设计先以低改造成本落地；
- 候选规则规模前期通常较小。

---

## 抽取策略

### 输入

- `before`: 保存前的会议完整文稿
- `after`: 保存后的会议完整文稿

### 输出

- 一组候选映射：`original -> corrected`

### 抽取步骤

#### 1. 文本规范化

对 `before` 和 `after` 先做轻量规范化：

- 统一空白字符
- 去掉多余 Markdown 包裹噪声
- 保留大小写与中文原文

注意：

- 不能做过强归一化，否则会丢失用户真正修正的差异。

#### 2. 差异分段

对 `before/after` 做最小编辑距离或基于 diff-match-patch 的文本 diff，拿到替换片段集合。

我们只关注：

- `replace` 类型差异

忽略：

- 大段插入
- 大段删除
- 整句重排

#### 3. 候选筛选

仅保留满足以下条件的替换片段：

- `original` 与 `corrected` 都非空
- 长度在合理范围内
  - 建议 2~24 字符
- 不包含换行
- 不属于纯标点变化
- 不属于纯格式变化
  - 如 `-`、`#`、列表缩进
- 优先保留“短语级替换”而非整句替换

#### 4. 候选打分

建议给每条候选一个启发式置信度：

- 长度接近：加分
- 中文词/术语：加分
- 英文大小写规范化：中等加分
- 与已有词典/历史候选重复：加分
- 出现在业务上下文中多次：加分
- 整句重写中的孤立片段：降分
- 替换跨度过长：降分

#### 5. 自动升级规则

候选规则不直接默认生效，按以下策略推进：

- 高置信 + 多次重复命中：`auto_promoted`
- 中置信：`pending`
- 低置信：仅记录日志，不入候选池

---

## 生效策略

### 方案分层

#### A. 候选层

仅记录，不立即影响纠错。

适用于：

- 第一次出现
- 置信度一般
- 编辑跨度较大

#### B. 已确认层

转化为正式 `DictionaryEntry`，参与现有纠错链路。

来源：

- 用户手动确认
- 或系统自动升级

#### C. 会话层

当用户在当前录音期间做了相关编辑，也可以同步注入当前 `SessionGlossary`，让同一会话剩余内容立即受益。

说明：

- 若会议已结束，则只进入长期词典；
- 若会议仍处于录制/整理中，可额外调用 `applySessionGlossaryOverride()`。

---

## 与现有模块的集成

### 1. `MeetingDetailPage`

当前保存入口：

- `MeetingDetailPage._saveDetail()`

改造建议：

- 保存时不再只调用 `updateMeetingFullTranscription(meetingId, text)`
- 改为传入：
  - `meetingId`
  - `beforeText`
  - `afterText`

例如新增：

- `MeetingProvider.saveMeetingFullTranscriptionEdit(...)`

### 2. `MeetingProvider`

新增职责：

- 持久化编辑后的 `fullTranscription`
- 调用“编辑差异抽取服务”
- 写入候选规则
- 根据条件转为 `DictionaryEntry`
- 刷新页面状态

### 3. 新服务：`MeetingEditCorrectionService`

建议新增服务，职责单一：

- 计算 diff
- 提取候选规则
- 去重合并
- 置信度评估
- 决定 `pending/auto_promoted`

建议接口：

```dart
class MeetingEditCorrectionService {
  Future<MeetingEditExtractionResult> extractCandidates({
    required String meetingId,
    required String beforeText,
    required String afterText,
  });
}
```

### 4. `SettingsProvider`

新增管理能力：

- 加载/保存“编辑纠错候选”
- 将 `accepted/auto_promoted` 候选转换为 `DictionaryEntry`
- 去重规则统一走这里

### 5. `CorrectionService`

不建议直接修改主逻辑，只需要让“已确认候选”最终并入 `dictionaryEntries` 即可。

这样可以复用：

- `PinyinMatcher`
- `#R` 构建
- `SessionGlossary`
- 统计埋点

---

## UI 设计

### 最小可行版本

先不做复杂新页面，采用以下交互：

1. 用户在会议详情页保存全文编辑
2. 若识别出候选术语，弹出轻提示：
   - `已从本次修改中识别出 2 条术语修正规则`
3. 在词典页增加一个分组或筛选：
   - `来源：历史编辑`
   - `状态：待确认`

### 推荐增强版本

增加“编辑修正建议”弹窗：

- 左侧显示候选 `original`
- 右侧显示 `corrected`
- 展示来源会议标题和时间
- 每条支持：
  - 接受
  - 忽略
  - 编辑后接受

这样可以显著降低误抽带来的风险。

---

## 去重与合并策略

候选规则与已有词典存在重叠时，按以下规则处理：

1. 已有完全相同 `original -> corrected`
   - 仅增加 `occurrenceCount`

2. 已有相同 `original` 但 `corrected` 不同
   - 不自动覆盖
   - 标记为冲突候选，状态保持 `pending`

3. 已有 `preserve` 规则冲突
   - 禁止自动升级
   - 交给用户确认

---

## 风险与处理

### 风险 1：整句重写误抽成术语规则

处理：

- 仅抽取短语级替换
- 大跨度改写降权或丢弃

### 风险 2：一次错误编辑污染长期词典

处理：

- 默认 `pending`
- 多次重复或用户确认后再生效

### 风险 3：过多候选导致词典膨胀

处理：

- 候选和正式词典分层
- 定期清理 `rejected` / 长期未确认项

### 风险 4：用户修改的是语义，而不是术语

处理：

- 抽取服务只关注局部替换
- 不把大段重写视为术语知识

---

## 埋点与观测

建议新增统计项：

- `meeting_edit_save_total`
- `meeting_edit_candidate_extracted_total`
- `meeting_edit_candidate_auto_promoted_total`
- `meeting_edit_candidate_accepted_total`
- `meeting_edit_candidate_rejected_total`
- `meeting_edit_candidate_conflict_total`

用于评估：

- 候选抽取质量
- 用户接受率
- 自动升级准确度

---

## 分阶段落地

### Phase 1：基础回流

- 新增候选模型与存储
- 保存会议全文时执行 diff 抽取
- 候选进入 `pending`
- 词典页可查看并手动确认

### Phase 2：自动升级

- 增加 `occurrenceCount`
- 重复命中后自动升级为正式词典
- 冲突检测与去重

### Phase 3：会话即时受益

- 录制中会议的编辑修正可同步注入 `SessionGlossary`
- 同次会议后续内容即时受益

### Phase 4：更强抽取

- 引入更稳健的 token 级 diff
- 区分术语修正、大小写规范化、品牌名统一等类型

---

## 建议新增文件

- `lib/models/meeting_edit_correction_candidate.dart`
- `lib/services/meeting_edit_correction_service.dart`
- `lib/services/meeting_edit_correction_store.dart`

可选：

- `lib/models/meeting_edit_change_set.dart`

---

## 建议改动点

- `lib/screens/pages/meeting_detail_page.dart`
  - 保存全文编辑时传 `before/after`

- `lib/providers/meeting_provider.dart`
  - 新增 `saveMeetingFullTranscriptionEdit()`

- `lib/providers/settings_provider.dart`
  - 管理候选规则与正式词典融合

- `lib/screens/pages/dictionary_page.dart`
  - 展示“历史编辑来源”与“待确认”候选

---

## 验收标准

1. 用户编辑会议全文并保存后，若存在明确术语修正，系统能生成候选规则。
2. 用户确认候选后，该规则会参与后续录音/会议纠错。
3. 同一个错误词多次被修正时，系统可自动提升其生效优先级。
4. 对整句改写、格式改动、Markdown 调整，不会大量产生错误候选。
5. 不破坏现有词典、`CorrectionService`、`SessionGlossary` 主链路。

---

## 一句话总结

这项设计本质上是在现有“会议可编辑”和“词典纠错”之间补上一条“用户监督信号回流链路”，把一次次人工修正，沉淀成后续录音持续受益的术语记忆。
