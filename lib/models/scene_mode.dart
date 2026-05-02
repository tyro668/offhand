/// Scene mode for context-aware AI text enhancement.
enum SceneMode {
  general,
  email,
  codeComment,
  chat;

  String get label {
    switch (this) {
      case SceneMode.general:
        return '通用';
      case SceneMode.email:
        return '邮件';
      case SceneMode.codeComment:
        return '代码注释';
      case SceneMode.chat:
        return '即时通讯';
    }
  }

  String get labelEn {
    switch (this) {
      case SceneMode.general:
        return 'General';
      case SceneMode.email:
        return 'Email';
      case SceneMode.codeComment:
        return 'Code Comment';
      case SceneMode.chat:
        return 'Chat';
    }
  }

  /// Additional prompt suffix injected into the system prompt.
  String get promptSuffix {
    switch (this) {
      case SceneMode.general:
        return '';
      case SceneMode.email:
        return '\n\n【场景模式：邮件】请将文本格式化为适合邮件的正式语气，注意措辞得体、结构清晰。如果有称呼和落款相关内容请保留。';
      case SceneMode.codeComment:
        return '\n\n【场景模式：代码注释】请将文本整理为简洁的代码注释风格。保留所有技术术语和英文变量名/函数名不翻译。使用简洁明了的表述。';
      case SceneMode.chat:
        return '\n\n【场景模式：即时通讯】保持口语化和轻松的语气，仅修正明显错误和添加必要标点。不要将文本正式化。';
    }
  }

  static SceneMode fromString(String value) {
    return SceneMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SceneMode.general,
    );
  }
}
