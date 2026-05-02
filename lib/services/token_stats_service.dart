import '../database/app_database.dart';

/// 持久化累计 AI 增强 token 用量。
class TokenStatsService {
  TokenStatsService._();
  static final instance = TokenStatsService._();

  static const _keyPromptTokens = 'ai_enhance_prompt_tokens';
  static const _keyCompletionTokens = 'ai_enhance_completion_tokens';

  final _db = AppDatabase.instance;

  /// 累加本次增强消耗的 token 数（语音输入）。
  Future<void> addTokens({
    required int promptTokens,
    required int completionTokens,
  }) async {
    final current = await getTokens();
    await _db.setSetting(
      _keyPromptTokens,
      (current.promptTokens + promptTokens).toString(),
    );
    await _db.setSetting(
      _keyCompletionTokens,
      (current.completionTokens + completionTokens).toString(),
    );
  }

  /// 读取累计 token 数（语音输入）。
  Future<({int promptTokens, int completionTokens})> getTokens() async {
    final p = int.tryParse(await _db.getSetting(_keyPromptTokens) ?? '') ?? 0;
    final c =
        int.tryParse(await _db.getSetting(_keyCompletionTokens) ?? '') ?? 0;
    return (promptTokens: p, completionTokens: c);
  }
}
