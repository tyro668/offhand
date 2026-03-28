import 'package:lpinyin/lpinyin.dart';
import 'package:uuid/uuid.dart';

/// 词典条目类型
enum DictionaryEntryType {
  /// 纠正规则：将 original 替换为 corrected
  correction,

  /// 保留规则：保持 original 原样输出（不被 AI 改写）
  preserve,
}

enum DictionaryEntrySource { manual, historyEdit }

/// 词典条目 — 用于指导 AI 模型进行文字纠正和术语保留。
class DictionaryEntry {
  final String id;

  /// 原始词（语音识别可能输出的错误写法，或需要保留的正确写法）
  final String original;

  /// 纠正后的正确写法（仅 correction 类型有效）
  final String? corrected;

  /// 分类标签，如 "人名"、"术语"、"品牌" 等
  final String? category;

  /// 条目来源，区分用户手动添加与历史修正回流。
  final DictionaryEntrySource source;

  /// 是否启用
  final bool enabled;

  /// 自定义拼音覆写（处理多音字场景）
  /// 若为 null，则自动从 original 计算。格式：无声调空格分隔，如 "mo ti si"。
  final String? pinyinOverride;

  /// 拼音匹配规则（可选）。
  /// 填写后可在不依赖 original 的情况下按拼音命中文本片段。
  final String? pinyinPattern;

  final DateTime createdAt;

  const DictionaryEntry({
    required this.id,
    required this.original,
    this.corrected,
    this.category,
    this.source = DictionaryEntrySource.manual,
    this.enabled = true,
    this.pinyinOverride,
    this.pinyinPattern,
    required this.createdAt,
  });

  /// 条目类型：有 corrected 则为纠正规则，否则为保留规则
  DictionaryEntryType get type => (corrected != null && corrected!.isNotEmpty)
      ? DictionaryEntryType.correction
      : DictionaryEntryType.preserve;

  /// 标准化拼音（无声调、小写、空格分隔）。
  /// 优先使用 pinyinPattern，其次 pinyinOverride，否则自动从 original 计算。
  String get pinyinNormalized {
    if (pinyinPattern != null && pinyinPattern!.trim().isNotEmpty) {
      return _normalizePinyinPattern(pinyinPattern!);
    }
    if (pinyinOverride != null && pinyinOverride!.trim().isNotEmpty) {
      return pinyinOverride!.trim().toLowerCase();
    }
    return _computePinyin(original);
  }

  bool get hasPinyinPattern =>
      pinyinPattern != null && pinyinPattern!.trim().isNotEmpty;

  /// 自动计算文本的拼音（无声调、小写、空格分隔）。
  static String _computePinyin(String text) {
    if (text.trim().isEmpty) return '';
    try {
      return PinyinHelper.getPinyinE(
            text,
            separator: ' ',
            defPinyin: '#',
            format: PinyinFormat.WITHOUT_TONE,
          )
          .toLowerCase()
          .replaceAll('#', '')
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
    } catch (_) {
      return '';
    }
  }

  /// 获取 original 的自动拼音（用于 UI 预览）。
  String get autoPinyin => _computePinyin(original);

  static String _normalizePinyinPattern(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  factory DictionaryEntry.create({
    required String original,
    String? corrected,
    String? category,
    DictionaryEntrySource source = DictionaryEntrySource.manual,
    bool enabled = true,
    String? pinyinOverride,
    String? pinyinPattern,
  }) {
    final normalizedOriginal = original.trim();
    final normalizedPattern =
        (pinyinPattern == null || pinyinPattern.trim().isEmpty)
        ? null
        : _normalizePinyinPattern(pinyinPattern);
    return DictionaryEntry(
      id: const Uuid().v4(),
      original: normalizedOriginal,
      corrected: corrected,
      category: category,
      source: source,
      enabled: enabled,
      pinyinOverride: pinyinOverride,
      pinyinPattern: normalizedPattern,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'original': original,
    'corrected': corrected,
    'category': category,
    'source': source.name,
    'enabled': enabled,
    'pinyinOverride': pinyinOverride,
    'pinyinPattern': pinyinPattern,
    'createdAt': createdAt.toIso8601String(),
  };

  factory DictionaryEntry.fromJson(Map<String, dynamic> json) {
    // 兼容旧数据格式迁移：word → original, description → corrected
    final original =
        json['original'] as String? ?? json['word'] as String? ?? '';
    final corrected =
        json['corrected'] as String? ?? json['description'] as String?;

    return DictionaryEntry(
      id: json['id'] as String,
      original: original,
      corrected: corrected,
      category: json['category'] as String?,
      source: _parseSource(
        json['source'] as String?,
        legacyCategory: json['category'] as String?,
      ),
      enabled: json['enabled'] as bool? ?? true,
      pinyinOverride: json['pinyinOverride'] as String?,
      pinyinPattern:
          (json['pinyinPattern'] as String?)?.trim().isNotEmpty == true
          ? _normalizePinyinPattern(json['pinyinPattern'] as String)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  DictionaryEntry copyWith({
    String? original,
    String? corrected,
    String? category,
    DictionaryEntrySource? source,
    bool? enabled,
    String? pinyinOverride,
    String? pinyinPattern,
  }) {
    return DictionaryEntry(
      id: id,
      original: original ?? this.original,
      corrected: corrected ?? this.corrected,
      category: category ?? this.category,
      source: source ?? this.source,
      enabled: enabled ?? this.enabled,
      pinyinOverride: pinyinOverride ?? this.pinyinOverride,
      pinyinPattern: pinyinPattern ?? this.pinyinPattern,
      createdAt: createdAt,
    );
  }

  /// 允许将 corrected 设为 null（copyWith 无法做到）
  DictionaryEntry clearCorrected() {
    return DictionaryEntry(
      id: id,
      original: original,
      corrected: null,
      category: category,
      source: source,
      enabled: enabled,
      pinyinOverride: pinyinOverride,
      pinyinPattern: pinyinPattern,
      createdAt: createdAt,
    );
  }

  /// 允许将 pinyinOverride 设为 null
  DictionaryEntry clearPinyinOverride() {
    return DictionaryEntry(
      id: id,
      original: original,
      corrected: corrected,
      category: category,
      source: source,
      enabled: enabled,
      pinyinOverride: null,
      pinyinPattern: pinyinPattern,
      createdAt: createdAt,
    );
  }

  DictionaryEntry clearPinyinPattern() {
    return DictionaryEntry(
      id: id,
      original: original,
      corrected: corrected,
      category: category,
      source: source,
      enabled: enabled,
      pinyinOverride: pinyinOverride,
      pinyinPattern: null,
      createdAt: createdAt,
    );
  }

  static DictionaryEntrySource _parseSource(
    String? raw, {
    String? legacyCategory,
  }) {
    if ((raw ?? '').trim() == DictionaryEntrySource.historyEdit.name ||
        legacyCategory == '历史修正') {
      return DictionaryEntrySource.historyEdit;
    }
    return DictionaryEntrySource.manual;
  }
}
