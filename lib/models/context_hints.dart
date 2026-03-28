class ContextHints {
  final String? recentTopic;
  final String? recentStyle;
  final List<String> relatedEntities;
  final List<String> referenceTexts;

  const ContextHints({
    this.recentTopic,
    this.recentStyle,
    this.relatedEntities = const [],
    this.referenceTexts = const [],
  });

  bool get hasContent =>
      (recentTopic != null && recentTopic!.trim().isNotEmpty) ||
      (recentStyle != null && recentStyle!.trim().isNotEmpty) ||
      relatedEntities.isNotEmpty ||
      referenceTexts.isNotEmpty;

  String toPromptSuffix() {
    if (!hasContent) return '';
    final buffer = StringBuffer('\n\n【最近输入上下文】');
    if (recentTopic != null && recentTopic!.trim().isNotEmpty) {
      buffer.write('\n- 最近主题：${recentTopic!.trim()}');
    }
    if (recentStyle != null && recentStyle!.trim().isNotEmpty) {
      buffer.write('\n- 最近表达风格：${recentStyle!.trim()}');
    }
    if (relatedEntities.isNotEmpty) {
      buffer.write('\n- 最近提到的对象：${relatedEntities.join('、')}');
    }
    if (referenceTexts.isNotEmpty) {
      buffer.write('\n- 参考表达：');
      for (var i = 0; i < referenceTexts.length; i++) {
        buffer.write('\n  ${i + 1}. ${referenceTexts[i]}');
      }
    }
    buffer.write('\n请在不改变用户原意的前提下，尽量保持与上述上下文一致的主题延续性和表达风格。');
    return buffer.toString();
  }
}
