# 基于 LLM 的实体记忆增强识别设计

## 1. 背景

当前应用已经有一条明确的识别与纠错主链路：

1. `TermPromptBuilder.build()` 在 STT 前构建提示词
2. `SttRequestContext` 把术语 / 上下文传给 STT
3. `CorrectionService.correct()` 在 STT 后进行纠错
4. `SessionGlossary` 负责会话内一致性
5. 历史编辑、词典、Context 为识别提供长期信息

这条主链路本身是对的，问题不在于“缺一套新的消歧引擎”，而在于：

- 现有系统对“实体知识”的利用还不够
- 历史编辑学到的内容更偏向 `错词 -> 正词`
- 人名、公司名、产品名、项目名这类“一个实体多个叫法”的场景没有统一建模
- Prompt 工程还不够充分，LLM 没有拿到足够好的实体上下文

因此，新方案的核心原则是：

- **不新建平行识别管线**
- **继续复用现有 `STT prompt + CorrectionService` 链路**
- **把实体知识作为 prompt 的输入材料**
- **把最终消歧交给 LLM**

---

## 2. 核心判断

### 2.1 问题本质

这类识别问题，本质不是普通术语纠错，而是“实体消歧”。

例如：

- `张三丰`
- `三丰`
- `老张`
- `接龙`

这些表面上是不同字符串，但实际可能都指向同一个实体。

同样的问题也存在于：

- 人名
- 公司名
- 产品名
- 项目名
- 系统名

所以设计目标不应只是“加强人名识别”，而应是：

**建立一套统一的实体记忆能力，让 LLM 在 STT 前后都拿到足够的实体上下文。**

### 2.2 最大原则

不要在代码里自建复杂的：

- 拼音打分引擎
- 编辑距离重排引擎
- 规则型候选融合器

这些逻辑可以保留少量轻量召回能力，但**最终判断应交给 LLM**。

代码侧更适合做的是：

- 实体召回
- prompt 压缩
- 风险控制
- 会话状态管理

---

## 3. 设计目标

### 3.1 核心目标

让系统在以下场景中显著提升识别准确率：

1. 用户改过一次后，后续近音或别称能更稳识别
2. 同一实体的全名、小名、外号、误识别可以统一归一
3. 多个相关实体同时出现时，LLM 能基于上下文自动消歧
4. 人名、公司名、产品名、项目名使用同一套机制

### 3.2 非目标

本设计不追求：

- 在代码里做最终实体判决
- 完全脱离 LLM 的纯规则消歧
- 一次性解决所有 OCR / STT / 语义理解问题

---

## 4. 统一实体模型

### 4.1 EntityMemory

建议把原先偏“人名”的设计升级为统一实体模型：

```text
EntityMemory
- id
- canonical_name
- entity_type
- enabled
- confidence
- created_at
- updated_at
```

`entity_type` 建议支持：

- `person`
- `company`
- `product`
- `project`
- `system`
- `custom`

### 4.2 EntityAlias

```text
EntityAlias
- id
- entity_id
- alias_text
- alias_type
- source
- confidence
- created_at
```

`alias_type` 建议支持：

- `full_name`
- `nickname`
- `alias`
- `misrecognition`
- `abbreviation`

其中对人名必须明确支持：

- 1 个全名
- 多个小名
- 多个外号
- 多个误识别 alias

示例：

```text
EntityMemory(person)
- canonical_name: 张三丰

EntityAlias
- 张三丰(full_name)
- 三丰(nickname)
- 老张(alias)
- 接龙(misrecognition)
```

### 4.3 EntityRelation

```text
EntityRelation
- id
- source_entity_id
- target_entity_id
- relation_type
- confidence
- source
```

示例：

- `张三丰 -> 李四娃 = 哥哥`
- `项目 Phoenix -> 公司 A = 所属项目`
- `产品 X -> 系统 Y = 子模块`

关系不一定直接展示给用户，但非常适合提供给 LLM 做消歧参考。

### 4.4 EntityEvidence

```text
EntityEvidence
- id
- entity_id
- source_type
- source_ref
- before_text
- after_text
- extracted_alias
- created_at
```

作用：

- 记录“这个 alias 是怎么学来的”
- 支持回溯、撤销、降权
- 给后续自动学习提供依据

### 4.5 Dart 与存储建议

为了让该方案能直接落地到当前 Flutter 项目，建议把伪模型进一步对应到 Dart 与本地存储：

建议新增文件：

- `lib/models/entity_memory.dart`
- `lib/models/entity_alias.dart`
- `lib/models/entity_relation.dart`
- `lib/models/entity_evidence.dart`

建议新增 Provider / Service：

- `lib/providers/entity_provider.dart`
- `lib/services/entity_recall_service.dart`
- `lib/services/entity_prompt_composer.dart`
- `lib/services/entity_dictionary_bridge.dart`

建议新增数据库表或 settings 存储键：

- `entity_memories`
- `entity_aliases`
- `entity_relations`
- `entity_evidences`

如果初期不想引入新表，也可以先走 settings JSON 存储，但中长期建议落到独立表，原因是：

- alias 与 evidence 数量会持续增长
- 需要支持按实体类型 / 活跃度 / 时间过滤
- 后续 UI 会需要分页、检索、冲突处理

### 4.6 Dart Model 草案

以下不是最终代码，但已经足够接近当前项目里的可实现结构。

`lib/models/entity_memory.dart`

```dart
enum EntityType { person, company, product, project, system, custom }

class EntityMemory {
  final String id;
  final String canonicalName;
  final EntityType type;
  final bool enabled;
  final double confidence;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EntityMemory({
    required this.id,
    required this.canonicalName,
    required this.type,
    required this.enabled,
    required this.confidence,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'canonicalName': canonicalName,
    'type': type.name,
    'enabled': enabled,
    'confidence': confidence,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory EntityMemory.fromJson(Map<String, dynamic> json) => EntityMemory(
    id: json['id'] as String,
    canonicalName: json['canonicalName'] as String,
    type: EntityType.values.byName(json['type'] as String),
    enabled: (json['enabled'] as bool?) ?? true,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}
```

`lib/models/entity_alias.dart`

```dart
enum EntityAliasType {
  fullName,
  nickname,
  alias,
  misrecognition,
  abbreviation,
}

class EntityAlias {
  final String id;
  final String entityId;
  final String aliasText;
  final EntityAliasType aliasType;
  final String source;
  final double confidence;
  final DateTime createdAt;

  const EntityAlias({
    required this.id,
    required this.entityId,
    required this.aliasText,
    required this.aliasType,
    required this.source,
    required this.confidence,
    required this.createdAt,
  });
}
```

`lib/models/entity_relation.dart`

```dart
class EntityRelation {
  final String id;
  final String sourceEntityId;
  final String targetEntityId;
  final String relationType;
  final double confidence;
  final String source;

  const EntityRelation({
    required this.id,
    required this.sourceEntityId,
    required this.targetEntityId,
    required this.relationType,
    required this.confidence,
    required this.source,
  });
}
```

`lib/models/entity_evidence.dart`

```dart
class EntityEvidence {
  final String id;
  final String entityId;
  final String sourceType;
  final String sourceRef;
  final String beforeText;
  final String afterText;
  final String extractedAlias;
  final DateTime createdAt;

  const EntityEvidence({
    required this.id,
    required this.entityId,
    required this.sourceType,
    required this.sourceRef,
    required this.beforeText,
    required this.afterText,
    required this.extractedAlias,
    required this.createdAt,
  });
}
```

如果落 SQLite，建议列名与当前项目已有命名风格保持一致，例如：

- `canonical_name`
- `entity_type`
- `alias_text`
- `alias_type`
- `created_at`

---

## 5. 与现有链路的集成方式

### 5.1 不增加平行主链路

新方案必须嵌入现有流程：

1. `TermPromptBuilder.build()`
2. `SttRequestContext`
3. `CorrectionService.correct()`

而不是另起一套：

- `PersonPromptBuilder`
- `PersonDisambiguationService`
- `EntityPostProcessor`

如果需要新增能力，应该是：

- `EntityRecallService`
- `EntityPromptComposer`

但这两个只负责：

- 召回相关实体
- 组织实体 prompt

最终仍旧流入现有：

- STT prompt
- Correction prompt

### 5.2 集成点一：STT 前

在 `TermPromptBuilder.build()` 中新增实体段落。

当前 `SttRequestContext` 已经能携带术语和上下文，因此实体信息应作为现有上下文的一部分注入，而不是单独开接口。

### 5.3 集成点二：STT 后

在 `CorrectionService.correct()` 中，把活跃实体和关系信息拼进纠错 prompt。

重点是：

- 即使没有词典命中，只要当前存在“高相关活跃实体”，也应允许进入 LLM 纠错
- 这样 LLM 才有机会利用实体知识做消歧

这点是现有系统需要补强的关键。

### 5.4 具体文件改动清单

Phase 1-4 至少会涉及这些已有文件：

- [`/Users/richie/Documents/work/offhand/lib/services/term_prompt_builder.dart`](/Users/richie/Documents/work/offhand/lib/services/term_prompt_builder.dart)
  - 在现有术语 prompt 后追加实体段
- [`/Users/richie/Documents/work/offhand/lib/services/term_recall_service.dart`](/Users/richie/Documents/work/offhand/lib/services/term_recall_service.dart)
  - 保持术语召回职责，不直接扩成实体召回
- [`/Users/richie/Documents/work/offhand/lib/services/correction_service.dart`](/Users/richie/Documents/work/offhand/lib/services/correction_service.dart)
  - 扩展 `_buildUserMessage(...)`
  - 增加“无词典命中但有活跃实体时触发 LLM”的策略
- [`/Users/richie/Documents/work/offhand/assets/prompts/correction_prompt.md`](/Users/richie/Documents/work/offhand/assets/prompts/correction_prompt.md)
  - 增补 `#E / #ER` 协议说明和新的纠错规则
- [`/Users/richie/Documents/work/offhand/lib/screens/pages/history_page.dart`](/Users/richie/Documents/work/offhand/lib/screens/pages/history_page.dart)
  - 历史编辑后同时触发术语学习和实体学习
- [`/Users/richie/Documents/work/offhand/lib/services/dictation_term_memory_service.dart`](/Users/richie/Documents/work/offhand/lib/services/dictation_term_memory_service.dart)
  - 继续负责保守的局部替换抽取
- [`/Users/richie/Documents/work/offhand/lib/providers/settings_provider.dart`](/Users/richie/Documents/work/offhand/lib/providers/settings_provider.dart)
  - 初期可承接实体配置存储；后续可迁移到独立 Provider

---

## 6. STT Prompt 设计

### 6.1 目标

STT prompt 的目标不是做最终判定，而是提前“扶正”模型的听写方向，让模型优先往当前活跃实体靠拢。

### 6.2 推荐结构

建议在现有术语 prompt 后追加实体段落：

```text
当前活跃实体参考：
- 人名：张三丰（小名：三丰；外号：老张；常见误识别：接龙）
- 人名：李四娃（常见误识别：金雨希）
- 公司：观远数据（别称：观远）
- 产品：DataForge（缩写：DF）

实体关系参考：
- 张三丰是李四娃的哥哥
- DataForge 属于观远数据产品线
```

要求：

- 只注入当前相关的 3 到 8 个实体
- alias 只保留最有价值的几个
- 优先注入最近活跃、当前上下文相关、用户最近修正过的实体

### 6.3 召回来源

实体召回应综合以下来源：

- 词典中的高置信度实体规则
- 历史编辑学习结果
- 当前会话中已激活实体
- 当前 Context 文档
- 最近历史文本中的高频实体

### 6.4 与现有术语段的合并规则

实体段不是替代现有术语段，而是附加在其后。

建议 `TermPromptBuilder.build()` 的输出顺序固定为：

1. 现有术语保留 / 纠正规则
2. 会话内 glossary 强锚定
3. Context 摘要
4. 实体段
5. 实体关系段

原因：

- 术语规则仍然是最稳定、最便宜的约束
- 实体段更适合作为补充背景，而非顶层强约束
- 这样能最大化复用现有实现，避免 STT prompt 行为大幅漂移

建议最终形成的 STT prompt 结构类似：

```text
术语参考：
- 帆软
- DataForge

会话参考：
- 反软->帆软

上下文参考：
- 当前讨论客户交付、项目里程碑和参会成员

当前活跃实体参考：
- 人名：张三丰（小名：三丰；外号：老张；常见误识别：接龙）
- 公司：观远数据（别称：观远）

实体关系参考：
- 张三丰是李四娃的哥哥
```

### 6.5 Prompt 降级策略

实体段不是每次都必须出现。

建议规则：

- `#E` 为空时：整段省略
- `#ER` 为空时：整段省略
- STT prompt 中“当前活跃实体参考”为空时：整个实体段不输出
- STT prompt 中“实体关系参考”为空时：整个关系段不输出

不要输出这种形式：

```text
#E:

#ER:
```

或：

```text
当前活跃实体参考：

实体关系参考：
```

原因：

- 空标签会污染 prompt
- 会让模型误以为还有遗漏信息
- 也会增加无意义 token

因此建议 `EntityPromptComposer` 内部采用“按段可选拼接”的方式，而不是固定模板填空

---

## 6A. EntityRecallService 量化召回规则

### 6A.1 召回目标

`EntityRecallService` 不负责最终判定，只负责从大量实体中选出少量值得进入 prompt 的候选。

### 6A.2 推荐打分信号

建议使用可解释的加权分，而不是黑盒规则。

基础分建议如下：

| 信号 | 分值 |
| --- | ---: |
| 当前会话已激活实体 | 100 |
| 当前文本直接命中某 alias | 80 |
| 当前文本命中近音 alias / misrecognition | 60 |
| 最近 10 条历史中出现过该实体 | 35 |
| 当前 Context 文档显式提到该实体 | 30 |
| 与已召回实体存在关系边 | 25 |
| 最近一次用户手工修正涉及该实体 | 20 |
| 实体被标记为高置信 | 15 |
| alias 类型为 `full_name` / `nickname` / `abbreviation` | +10 / +8 / +6 |
| alias 类型为 `misrecognition` | +4 |

扣分建议：

| 风险信号 | 分值 |
| --- | ---: |
| 实体长期未使用 | -15 |
| 仅由自动学习产生，且无人工确认 | -10 |
| alias 文本过短且歧义高 | -12 |
| 与当前上下文主题明显无关 | -20 |

### 6A.3 截断与去重

建议：

- 最终进入 STT prompt 的实体：`top 5`
- 最终进入 Correction prompt 的实体：`top 8`
- 每个实体最多保留 `3` 个 alias
- 每种 alias 类型优先保留高置信度的 1 到 2 个

去重规则：

- 同一 canonical name 只保留一个实体
- 同一 alias 只归属于一个高置信实体；冲突 alias 进入冲突池，不直接进 prompt

### 6A.4 关系扩展策略

对已经进入 top-k 的实体，可做一跳关系扩展：

- 若 A 已入选，且 A 与 B 关系强、B 近期活跃，则 B 可追加进入候选
- 最多扩展 2 个关系实体，避免 prompt 膨胀

---

## 7. Correction Prompt 设计

### 7.1 核心原则

最终消歧主要交给 `CorrectionService.correct()` 里的 LLM。

因此这里不是简单附加几个词，而是要把“实体知识”组织成 LLM 易用的结构。

### 7.2 推荐扩展协议

建议在现有 `#R / #I / #C` 基础上，引入一个新的实体段，例如：

```text
#E
张三丰 | type=person | nickname=三丰 | alias=老张 | mis=接龙
李四娃 | type=person | mis=金雨希
观远数据 | type=company | alias=观远
DataForge | type=product | alias=DF

#ER
张三丰 -> 李四娃 : 哥哥
DataForge -> 观远数据 : 产品线
```

说明：

- `#E` 只描述实体本身
- `#ER` 描述实体关系
- 保持协议紧凑，避免 prompt 过长

如果你不想继续扩协议，也可以直接把实体段写成自然语言块，但协议化更利于稳定。

### 7.3 建议的纠错指令

`CorrectionService` 的 prompt 里要显式告诉模型：

- 优先保持原句语义
- 如果某个片段像活跃实体的近音、别称或误识别，应优先还原为对应标准名
- 当多个实体同时出现时，允许结合关系与上下文共同判断
- 没有足够把握时不要强改

可以加类似要求：

```text
如果输入中的词语与活跃实体的别称、误识别或近音高度相似，优先改写为该实体的标准名。
如果没有足够证据，请保持原文，不要过度替换。
```

### 7.4 触发策略

现有系统如果过度依赖“先命中词典再纠错”，会错过大量实体消歧机会。

建议新增以下触发条件：

- 命中普通词典时，调用 LLM
- 命中活跃实体 alias 时，调用 LLM
- 未命中词典，但当前存在高置信度活跃实体且文本中出现疑似实体片段时，也调用 LLM

这样才能真正发挥实体记忆的价值。

### 7.5 `correction_prompt.md` 完整模板建议

当前 [`/Users/richie/Documents/work/offhand/assets/prompts/correction_prompt.md`](/Users/richie/Documents/work/offhand/assets/prompts/correction_prompt.md) 只定义了 `#R / #C / #I`。升级后建议改为：

```md
你是一个语音识别纠错引擎，专门修正语音转文字过程中的同音字、近音字以及实体识别错误。

## 输入格式
- #R（参考词典）：格式为"错词->正词"，多组用|分隔
- #C（历史上下文）：前几段已纠错文本，辅助理解语境
- #E（活跃实体）：当前高相关实体及其标准名、别称、误识别、小名、缩写
- #ER（实体关系）：实体之间的关系提示
- #I（待纠错文本）：ASR 原始输出

## 纠错规则
1. 优先保持 #I 的原始语义、语气和句式，不要润色
2. 对 #R 中明确给出的映射，优先按词典规则纠正
3. 如果 #I 中某个片段与 #E 中实体的别称、误识别、近音或缩写高度相似，可改为该实体的标准名
4. 可结合 #C 与 #ER 进行实体消歧，尤其是在多人名、多公司名、多产品名同时出现时
5. 若证据不足，不要强改；未能确认的词保持原样
6. 保留规则（如"Metis->Metis"）必须严格保留，不可误改
7. 输出必须只包含纠错后的正文，不要添加解释

## 输出格式
仅输出纠错后的文本，不要添加任何解释、标注或前后缀。
```

### 7.6 `CorrectionService._buildUserMessage(...)` 升级建议

当前实现是：

```text
#R: ...
#C: ...
#I: ...
```

升级后建议为：

```text
#R: ...
#C: ...
#E:
张三丰 | type=person | nickname=三丰 | alias=老张 | mis=接龙
李四娃 | type=person | mis=金雨希

#ER:
张三丰 -> 李四娃 : 哥哥

#I: ...
```

具体落点在 [`/Users/richie/Documents/work/offhand/lib/services/correction_service.dart#L389`](\/Users/richie/Documents/work/offhand/lib/services/correction_service.dart#L389)。

### 7.6A 为空时的 userMessage 退化形式

当没有实体信息时，`CorrectionService` 应继续退化为当前稳定模式：

```text
#R: ...
#C: ...
#I: ...
```

当只有实体、没有关系时：

```text
#R: ...
#C: ...
#E:
张三丰 | type=person | nickname=三丰 | mis=接龙
#I: ...
```

当实体和关系都存在时，才输出完整：

```text
#R: ...
#C: ...
#E:
...
#ER:
...
#I: ...
```

这能保证：

- 老场景不回退
- 新场景按需增强
- prompt 长度稳定可控

### 7.7 `EntityDictionaryBridge` 设计

对于已经被确认的高置信 `misrecognition`，不应每次都依赖 LLM。

建议新增 `EntityDictionaryBridge`，负责把一部分 alias 自动桥接成普通词典规则：

- `misrecognition -> canonical_name`
- `abbreviation -> canonical_name`
- 必要时 `alias -> canonical_name`

桥接收益：

- 复用现有 [`/Users/richie/Documents/work/offhand/lib/services/pinyin_matcher.dart`](\/Users/richie/Documents/work/offhand/lib/services/pinyin_matcher.dart) 通道
- 对“已知误识别”可以零额外思考直接命中
- 让 LLM 专注处理真正有歧义的场景

桥接条件建议：

- alias 已被人工确认，或至少命中 2 次以上
- alias 与 canonical name 的对应关系稳定
- alias 不在高冲突词表中

不建议桥接的情况：

- 普通外号过于通用，如“老张”“小王”
- 容易和常见名词冲突
- 仍处于低置信观察阶段

---

## 8. 学习机制

### 8.1 从历史编辑中学习

历史编辑是最高价值信号之一。

当用户修改历史记录时，应同时做两件事：

1. 继续走原有 `错词 -> 正词` 规则沉淀
2. 尝试提取“实体 alias 学习”

例如：

- 原文：`接龙马上出来了`
- 修改后：`张三丰马上出来了`

可学习为：

- `张三丰` 是一个 `person` 实体
- `接龙` 是它的 `misrecognition` 或 `alias`

### 8.2 学习原则

不是所有修改都应该自动学习成实体。

建议：

- 用户显式标注为实体：直接高置信学习
- 命中典型实体模式：自动学习为中置信
- 只是整句改写、语义润色：不学习

### 8.3 人名特殊要求

对人名场景，必须支持：

- 全名
- 小名
- 外号
- 多个误识别

并且 UI 上要允许用户明确指定 alias 类型，避免把“小名”误当“误识别”。

### 8.4 与 `DictationTermMemoryService` 的分流规则

历史编辑后的学习不应只有一条路径，而应分流成两条：

1. 术语规则学习
2. 实体 alias 学习

建议分流逻辑如下：

#### 进入术语规则学习

满足任一条件即可：

- 替换片段明显是专业术语 / 产品词 / 英文缩写
- 替换片段更适合表达“写法纠正”而不是“实体归一”
- 当前编辑没有足够实体信号

对应现有能力：

- 继续使用 [`/Users/richie/Documents/work/offhand/lib/services/dictation_term_memory_service.dart`](\/Users/richie/Documents/work/offhand/lib/services/dictation_term_memory_service.dart)
- 继续沉淀 `DictionaryEntry`

#### 进入实体 alias 学习

满足任一条件即可：

- 替换后的文本命中已知实体标准名
- 用户显式标记“作为实体学习”
- 替换后的文本符合人名 / 公司名 / 产品名典型模式
- 当前上下文里该词已作为活跃实体存在

对应新增能力：

- 创建或更新 `EntityMemory`
- 把原词记为 `EntityAlias`
- 写入 `EntityEvidence`

#### 同时进入两条路径

当 alias 已非常稳定时，可以两边都走：

- 实体层保留语义归属
- 词典层保留快速纠错入口

典型例子：

- `反软 -> 帆软`
- `接龙 -> 张三丰`
- `DF -> DataForge`

#### 明确不学习

以下情况两边都不应学习：

- 整句重写
- 语气润色
- 补全缺失信息
- 非局部改动且证据不足

### 8.5 推荐的桥接顺序

建议历史编辑后的执行顺序为：

1. `DictationTermMemoryService.extractCandidates(...)`
2. `EntityLearningService.extractEntityCandidates(...)`
3. 若命中高置信实体 alias，则触发 `EntityDictionaryBridge`
4. 写入词典 / 实体库 / evidence
5. 更新会话内 glossary 与实体激活状态

### 8.6 SessionEntityState 设计

建议不要直接把实体状态塞进现有 [`/Users/richie/Documents/work/offhand/lib/services/session_glossary.dart`](/Users/richie/Documents/work/offhand/lib/services/session_glossary.dart)，而是新增独立的 `SessionEntityState`。

原因：

- `SessionGlossary` 的职责是“错词 -> 正词”的会话锚定
- 实体状态的职责是“哪些实体当前活跃、哪些 alias 刚被确认、哪些关系当前应优先考虑”
- 两者虽然相关，但数据结构与更新规则不同

建议新增：

- `lib/services/session_entity_state.dart`

结构示例：

```dart
class SessionEntityActivation {
  final String entityId;
  final String canonicalName;
  final double score;
  final DateTime lastActivatedAt;
  final Set<String> recentAliases;

  const SessionEntityActivation({
    required this.entityId,
    required this.canonicalName,
    required this.score,
    required this.lastActivatedAt,
    required this.recentAliases,
  });
}

class SessionEntityState {
  final Map<String, SessionEntityActivation> _activations = {};

  void activate({
    required String entityId,
    required String canonicalName,
    required String alias,
    double score = 1.0,
  }) { ... }

  List<SessionEntityActivation> topActivations({int limit = 8}) { ... }

  void decay() { ... }

  void reset() { ... }
}
```

与 `SessionGlossary` 的对接方式：

- 历史编辑学习成功时：
  - `SessionGlossary.override(original, corrected)`
  - `SessionEntityState.activate(entityId, canonicalName, alias)`
- LLM 成功把某 alias 改成标准名时：
  - 若能映射到实体，则同步激活实体
- 新会话开始时：
  - `SessionGlossary.reset()`
  - `SessionEntityState.reset()`

简化理解：

- `SessionGlossary` 解决“这一串字该怎么改”
- `SessionEntityState` 解决“当前大家在说谁 / 哪个公司 / 哪个产品”

---

## 9. Context 的作用

Context 不应再承担“抽词典规则”的职责，而应作为实体召回的背景源。

例如导入一份 Markdown：

- 会议参与人名单
- 项目成员说明
- 客户名单
- 产品说明文档

系统不必把其中每个词都拆成规则，但可以：

- 抽取候选实体
- 提升实体召回分
- 在 prompt 中作为背景参考

也就是说：

- 词典负责规则
- EntityMemory 负责实体
- Context 负责背景

---

## 10. 风险分析

### 10.1 Prompt 膨胀

这是最大风险之一。

如果把所有实体都塞进 prompt，会导致：

- token 浪费
- LLM 注意力分散
- 错误实体误召回

控制策略：

- 只保留 top-k 活跃实体
- 每个实体只保留少量高价值 alias
- 长关系链不注入

### 10.2 误召回

如果错误召回了不相关实体，LLM 可能把普通词误改成实体名。

控制策略：

- 召回必须结合最近历史、当前会话、Context 相关性
- 低置信实体不进入 prompt
- prompt 中明确要求“证据不足时不改”

### 10.3 自动学习污染

历史编辑如果被过度自动学习，会污染实体库。

控制策略：

- 保留 evidence
- 新 alias 先低权重
- 支持撤销、删除、降权
- 支持用户手工确认 alias 类型

### 10.4 与词典规则冲突

实体 alias 和普通词典规则可能冲突。

例如某个词既是专业术语，也可能是某人的外号。

控制策略：

- `CorrectionService` prompt 中同时提供词典和实体信息
- 要求 LLM 结合上下文判定
- 对冲突项保留来源和置信度

---

## 11. UI 建议

### 11.1 独立实体管理页

建议不要只做“人物页”，而是做统一的“实体”页。

每条实体至少展示：

- 标准名
- 类型
- alias 数量
- 最近命中时间
- 来源

### 11.2 实体详情

每个实体支持：

- 编辑标准名
- 添加小名
- 添加外号
- 添加误识别
- 添加缩写
- 查看 evidence
- 删除 alias

### 11.3 历史编辑入口

历史记录页可以补一个轻量入口：

- `作为实体学习`

用户可以指定：

- 实体类型
- alias 类型
- 是否立即提升为高置信

### 11.4 批量录入与导入

为了降低维护成本，实体页还应支持：

- 逗号分隔快速创建 alias
- 从 Markdown / TXT 批量导入实体候选
- 从会议参与人名单批量创建 `person`
- 从产品说明中批量创建 `product / system`

导入后不应直接全部桥接为词典，而应先进入实体库，再根据置信度决定是否桥接。

---

## 11A. 端到端调用示例

下面给出一条完整 trace，说明这套方案如何真正嵌入现有链路。

### 11A.1 初始状态

实体库中已有：

- `张三丰`
  - `三丰(nickname)`
  - `老张(alias)`
  - `接龙(misrecognition)`
- `李四娃`
  - `金雨希(misrecognition)`

关系：

- `张三丰 -> 李四娃 = 哥哥`

词典桥接中已有：

- `接龙 -> 张三丰`
- `金雨希 -> 李四娃`

当前会话里最近一句为：

- `刚刚张三丰已经到了，李四娃还在路上。`

### 11A.2 新的 ASR 输出

ASR 返回：

```text
快走，接龙啊，金雨希马上出来了。
```

### 11A.3 召回阶段

`EntityRecallService` 根据以下信号打分：

- `张三丰`：会话激活 + 命中 alias `接龙` + 与 `李四娃` 有关系
- `李四娃`：会话激活 + 命中 misrecognition `金雨希`

最终进入 prompt 的实体：

- `张三丰`
- `李四娃`

### 11A.4 STT Prompt 组装

`TermPromptBuilder.build()` 输出的相关部分为：

```text
术语参考：
- 张三丰
- 李四娃

会话参考：
- 接龙->张三丰
- 金雨希->李四娃

当前活跃实体参考：
- 人名：张三丰（小名：三丰；外号：老张；常见误识别：接龙）
- 人名：李四娃（常见误识别：金雨希）

实体关系参考：
- 张三丰是李四娃的哥哥
```

### 11A.5 Correction Prompt 组装

若 STT 后仍输出原句，`CorrectionService._buildUserMessage(...)` 生成：

```text
#R: 接龙->张三丰|金雨希->李四娃
#C: 刚刚张三丰已经到了，李四娃还在路上。
#E:
张三丰 | type=person | nickname=三丰 | alias=老张 | mis=接龙
李四娃 | type=person | mis=金雨希
#ER:
张三丰 -> 李四娃 : 哥哥
#I: 快走，接龙啊，金雨希马上出来了。
```

### 11A.6 LLM 输出

LLM 目标输出应为：

```text
快走，张三丰啊，李四娃马上出来了。
```

### 11A.7 会话状态更新

纠错成功后：

- `SessionGlossary` 继续维持：
  - `接龙 -> 张三丰`
  - `金雨希 -> 李四娃`
- `SessionEntityState` 激活：
  - `张三丰`
  - `李四娃`

若后续继续出现：

- `老张`
- `三丰`

则会优先继续召回 `张三丰`，形成会话内稳定一致性。

---

## 12. Phase 规划

### Phase 1：实体模型与存储

目标：

- 引入 `EntityMemory / EntityAlias / EntityRelation / EntityEvidence`
- 支持人名的全名、小名、外号、误识别
- 同时支持公司名、产品名、项目名

### Phase 2：历史编辑学习

目标：

- 从历史编辑中学习实体 alias
- 保留 evidence
- 与当前词典规则共存

涉及文件：

- [`/Users/richie/Documents/work/offhand/lib/screens/pages/history_page.dart`](/Users/richie/Documents/work/offhand/lib/screens/pages/history_page.dart)
- [`/Users/richie/Documents/work/offhand/lib/services/dictation_term_memory_service.dart`](/Users/richie/Documents/work/offhand/lib/services/dictation_term_memory_service.dart)
- `lib/services/entity_learning_service.dart`
- `lib/services/entity_dictionary_bridge.dart`

### Phase 3：STT Prompt 实体注入

目标：

- 在 `TermPromptBuilder.build()` 中注入活跃实体段
- 控制 top-k 与 token 预算

涉及文件：

- [`/Users/richie/Documents/work/offhand/lib/services/term_prompt_builder.dart`](/Users/richie/Documents/work/offhand/lib/services/term_prompt_builder.dart)
- `lib/services/entity_recall_service.dart`
- `lib/services/entity_prompt_composer.dart`

### Phase 4：Correction Prompt 实体增强

目标：

- 在 `CorrectionService.correct()` 中注入 `#E / #ER`
- 支持“无词典命中但有活跃实体”时触发 LLM

涉及文件：

- [`/Users/richie/Documents/work/offhand/lib/services/correction_service.dart`](/Users/richie/Documents/work/offhand/lib/services/correction_service.dart)
- [`/Users/richie/Documents/work/offhand/assets/prompts/correction_prompt.md`](/Users/richie/Documents/work/offhand/assets/prompts/correction_prompt.md)

### Phase 5：UI 与风险控制

目标：

- 实体管理页
- alias 审核 / 撤销 / 降权
- 冲突项处理

涉及文件：

- `lib/screens/pages/entity_page.dart`
- `lib/screens/pages/entity_detail_page.dart`
- `lib/providers/entity_provider.dart`

---

## 13. 成功标准

以下指标应显著改善：

1. 用户改过一次 `接龙 -> 张三丰`，后续再次出现时更稳识别
2. `张三丰 / 三丰 / 老张 / 接龙` 能被统一归一到同一实体
3. `张三丰` 与 `李四娃` 同时出现时，LLM 能结合关系做更稳定纠错
4. 公司名、产品名、项目名也能复用同一套机制
5. 在不明显增加误改率的前提下，实体相关场景识别准确率提升

---

## 14. 结论

这项能力的关键，不是写一套更复杂的代码型消歧器，而是：

- 建好统一实体记忆
- 把实体知识正确注入现有 prompt 链路
- 让 LLM 负责最终消歧

其中对人名必须明确支持：

- 1 个全名
- 多个小名
- 多个外号
- 多个误识别 alias

但整体设计不应只停留在人名，而应扩展为统一的实体识别增强能力。
