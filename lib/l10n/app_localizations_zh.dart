// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '释手';

  @override
  String get loading => '加载中...';

  @override
  String get generalSettings => '通用设置';

  @override
  String get voiceModelSettings => '语音模型';

  @override
  String get textModelSettings => '文本模型';

  @override
  String get promptWorkshop => '提示词设置';

  @override
  String get aiEnhanceHub => '智能增强';

  @override
  String get history => '转写档案';

  @override
  String get historyContextApplied => '用于上下文';

  @override
  String get historyContextSkipped => '不用于上下文';

  @override
  String get historyContextCount => '上下文档案';

  @override
  String get logs => '日志';

  @override
  String get about => '关于';

  @override
  String get activationMode => '激活模式';

  @override
  String get tapToTalk => '点击模式';

  @override
  String get tapToTalkSubtitle => '点击开始，点击停止';

  @override
  String get tapToTalkDescription => '按快捷键开始录音，再次按下停止录音';

  @override
  String get pushToTalk => '按住模式';

  @override
  String get pushToTalkSubtitle => '按住录音，松开停止';

  @override
  String get pushToTalkDescription => '按住快捷键录音，松开停止录音';

  @override
  String get dictationHotkey => '听写快捷键';

  @override
  String get dictationHotkeyDescription => '配置用于开始和停止语音听写的按键。';

  @override
  String get pressKeyToSet => '按下要设置为快捷键的按键';

  @override
  String get clickToChangeHotkey => '点击更改快捷键';

  @override
  String get resetToDefault => '恢复默认';

  @override
  String get permissions => '权限设置';

  @override
  String get permissionsDescription => '管理系统权限以获取最佳性能功能。';

  @override
  String get microphonePermission => '麦克风权限';

  @override
  String get accessibilityPermission => '辅助功能权限';

  @override
  String get testPermission => '测试';

  @override
  String get permissionGranted => '已授权';

  @override
  String get permissionDenied => '未授权';

  @override
  String get permissionHint => '麦克风权限用于语音输入，辅助功能权限用于文本插入。';

  @override
  String get testMicrophonePermission => '测试麦克风权限';

  @override
  String get testAccessibilityPermission => '测试辅助功能权限';

  @override
  String get fixPermissionIssues => '修复权限问题';

  @override
  String get openSoundInput => '打开声音输入';

  @override
  String get openMicrophonePrivacy => '打开麦克风隐私';

  @override
  String get openAccessibilityPrivacy => '打开辅助功能隐私';

  @override
  String get microphoneInput => '麦克风输入';

  @override
  String get microphoneInputDescription =>
      '选择用于听写的麦克风。启用「优先使用内置麦克风」可防止使用蓝牙耳机时音频中断。';

  @override
  String get preferBuiltInMicrophone => '优先使用内置麦克风';

  @override
  String get preferBuiltInMicrophoneSubtitle => '外置麦克风可能导致延迟或降低转录质量';

  @override
  String get currentDevice => '当前设备';

  @override
  String get unknownDevice => '未知设备';

  @override
  String get noMicrophoneDetected => '未检测到麦克风';

  @override
  String get using => '正在使用';

  @override
  String get minRecordingDuration => '最短录音时长';

  @override
  String get minRecordingDurationDescription => '录音时长低于此值时将自动忽略，避免误触产生无效输入。';

  @override
  String get ignoreShortRecordings => '忽略短于此时长的录音';

  @override
  String get seconds => '秒';

  @override
  String get language => '语言';

  @override
  String get languageDescription => '选择您偏好的界面语言。';

  @override
  String get interfaceLanguage => '界面语言';

  @override
  String get english => 'English';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get logsDescription => '查看和管理应用程序日志文件。';

  @override
  String get logFile => '日志文件';

  @override
  String get noLogFile => '无日志文件';

  @override
  String get openLogDirectory => '打开日志文件夹';

  @override
  String get copyLogPath => '复制路径';

  @override
  String get logPathCopied => '日志路径已复制到剪贴板';

  @override
  String get tip => '提示';

  @override
  String get logsTip => '日志文件包含应用程序的运行记录，可用于排查问题。如果应用出现异常，可以将此日志文件提供给开发者进行分析。';

  @override
  String get recordingStorage => '录音文件存储';

  @override
  String get recordingStorageDescription => '查看和管理录音音频文件的存储位置。';

  @override
  String get recordingFiles => '录音文件';

  @override
  String get files => '个文件';

  @override
  String get openRecordingFolder => '打开文件夹';

  @override
  String get copyPath => '复制路径';

  @override
  String get clearRecordingFiles => '清理文件';

  @override
  String get clearRecordingFilesConfirm => '确定要删除所有录音文件吗？此操作不可撤销。';

  @override
  String get confirm => '确定';

  @override
  String get addModel => '添加模型';

  @override
  String get addVoiceModel => '添加语音模型';

  @override
  String get addTextModel => '添加文本模型';

  @override
  String get editModel => '编辑模型';

  @override
  String get editVoiceModel => '编辑语音模型';

  @override
  String get editTextModel => '编辑文本模型';

  @override
  String get deleteModel => '删除模型';

  @override
  String deleteModelConfirm(Object model, Object vendor) {
    return '确定要删除 $vendor / $model 吗？';
  }

  @override
  String confirmDeleteModel(String vendor, String model) {
    return '确定要删除 $vendor / $model 吗？';
  }

  @override
  String get vendor => '服务商';

  @override
  String get model => '模型';

  @override
  String get endpointUrl => '端点 URL';

  @override
  String get apiKey => 'API 密钥';

  @override
  String get selectVendor => '选择服务商';

  @override
  String get selectModel => '选择模型';

  @override
  String get custom => '自定义';

  @override
  String enterModelName(Object example) {
    return '输入模型名称，如 $example';
  }

  @override
  String get enterApiKey => '输入 API 密钥';

  @override
  String get saveChanges => '保存修改';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get testConnection => '测试连接';

  @override
  String get testingConnection => '正在测试连接...';

  @override
  String get connectionSuccess => '连接成功 ✓';

  @override
  String get connectionFailed => '连接失败，请检查配置';

  @override
  String get inUse => '使用中';

  @override
  String get useThisModel => '使用此模型';

  @override
  String get currentlyInUse => '当前正在使用';

  @override
  String get noModelsAdded => '暂未添加模型';

  @override
  String get addVoiceModelHint => '点击下方按钮添加一个语音识别模型';

  @override
  String get addTextModelHint => '点击下方按钮添加一个大语言模型';

  @override
  String get enableTextEnhancement => '启用文本增强';

  @override
  String get textEnhancementDescription => '使用 AI 增强和修正转录的文本。';

  @override
  String get prompt => '提示词';

  @override
  String get promptDescription => '自定义 AI 文本增强的行为。';

  @override
  String get defaultPrompt => '默认提示词';

  @override
  String get customPrompt => '自定义提示词';

  @override
  String get useCustomPrompt => '使用自定义提示词';

  @override
  String get agentName => '助手名称';

  @override
  String get enterAgentName => '输入助手名称';

  @override
  String get current => '当前';

  @override
  String get test => '测试';

  @override
  String get currentSystemPrompt => '当前系统智能体提示词';

  @override
  String get customPromptTitle => '自定义智能体提示词';

  @override
  String get enableCustomPrompt => '启用自定义提示词';

  @override
  String get customPromptEnabled => '已启用：文本整理将使用下方自定义提示词';

  @override
  String get customPromptDisabled => '已关闭：文本整理将使用系统默认提示词';

  @override
  String agentNamePlaceholder(Object agentName) {
    return '使用 $agentName 作为智能体名称占位符';
  }

  @override
  String get systemPrompt => '系统提示词';

  @override
  String get saveAgentConfig => '保存智能体配置';

  @override
  String get restoreDefault => '恢复默认';

  @override
  String get testYourAgent => '测试您的智能体';

  @override
  String get testAgentDescription => '使用当前文本模型与智能体提示词进行测试。';

  @override
  String get testInput => '测试输入';

  @override
  String get enterTestText => '输入一段需要润色的文本...';

  @override
  String get running => '运行中...';

  @override
  String get runTest => '运行测试';

  @override
  String get outputResult => '输出结果';

  @override
  String get outputWillAppearHere => '输出结果将显示在这里';

  @override
  String get historySection => '转写档案';

  @override
  String get noHistory => '暂无转写档案';

  @override
  String get historyHint => '使用快捷键开始录音，增强后的转写结果将归档在这里';

  @override
  String get clearHistory => '清空转写档案';

  @override
  String get clearHistoryConfirm => '确定要删除所有转写档案吗？此操作不可撤销。';

  @override
  String get clearAll => '清空全部';

  @override
  String get clear => '清空';

  @override
  String get copy => '复制';

  @override
  String get copied => '已复制';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get deleteHistoryItem => '删除';

  @override
  String get searchHistory => '搜索转写档案...';

  @override
  String get aboutSection => '关于';

  @override
  String get appDescription =>
      '释手是一款语音输入工具，支持多种云端大模型和基于 sherpa-onnx 的本地 ASR 模型，让所想即所写。';

  @override
  String get appSlogan => '言之所至，释手而书。';

  @override
  String get version => '版本';

  @override
  String get checkForUpdates => '检查更新';

  @override
  String get openSourceLicenses => '开源许可证';

  @override
  String get required => '必填';

  @override
  String get optional => '选填';

  @override
  String get networkSettings => '网络设置';

  @override
  String get networkSettingsDescription => '配置应用的网络代理模式。';

  @override
  String get systemSettings => '系统设置';

  @override
  String get systemSettingsDescription => '配置系统级设置，如开机启动和网络代理。';

  @override
  String get launchAtLogin => '开机启动';

  @override
  String get launchAtLoginDescription => '登录系统时自动启动 释手。';

  @override
  String get launchAtLoginFailed => '启用开机启动失败';

  @override
  String get disableLaunchAtLoginFailed => '关闭开机启动失败';

  @override
  String get proxyConfig => '代理配置';

  @override
  String get useSystemProxy => '使用系统代理';

  @override
  String get systemProxySubtitle => '请求遵循系统网络代理配置。';

  @override
  String get noProxy => '不使用代理';

  @override
  String get noProxySubtitle => '所有请求直连，不走任何代理。';

  @override
  String get inputMonitoringRequired => '需要输入监控权限';

  @override
  String get inputMonitoringDescription =>
      'Fn 全局快捷键需要在「系统设置 > 隐私与安全性 > 输入监控」中勾选 释手。';

  @override
  String get accessibilityRequired => '需要辅助功能权限';

  @override
  String get accessibilityDescription =>
      '为实现自动输入，需要在「系统设置 > 隐私与安全性 > 辅助功能」中勾选 释手。';

  @override
  String get later => '稍后';

  @override
  String get openSettings => '打开设置';

  @override
  String get pleaseConfigureSttModel => '请先配置语音转换模型';

  @override
  String get overlayStarting => '麦克风启动中';

  @override
  String get overlayRecording => '录音中';

  @override
  String get overlayTranscribing => '语音转换中';

  @override
  String get overlayEnhancing => '文字整理中';

  @override
  String get overlayTranscribeFailed => '语音转录失败';

  @override
  String get theme => '外观';

  @override
  String get themeDescription => '选择应用的外观主题。';

  @override
  String get themeMode => '外观模式';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get localModelIdleUnloadTitle => '本地模型空闲自动释放';

  @override
  String get localModelIdleUnloadDescription => '长时间不使用时自动卸载模型，降低内存占用';

  @override
  String get localModelIdleUnloadTiming => '释放时机';

  @override
  String get off => '关闭';

  @override
  String minutesShort(int value) {
    return '$value 分钟';
  }

  @override
  String userLabel(String id) {
    return '说话人$id';
  }

  @override
  String userIdLabel(String user) {
    return '$user';
  }

  @override
  String get dashboard => '仪表盘';

  @override
  String get totalTranscriptions => '总转录次数';

  @override
  String get totalRecordingTime => '总录音时长';

  @override
  String get totalCharacters => '总字数';

  @override
  String get avgCharsPerSession => '平均每次字数';

  @override
  String get avgRecordingDuration => '平均录音时长';

  @override
  String get today => '今日';

  @override
  String get thisWeek => '本周';

  @override
  String get thisMonth => '本月';

  @override
  String get transcriptionCount => '转录次数';

  @override
  String get recordingTime => '录音时长';

  @override
  String get characters => '字数';

  @override
  String get usageTrend => '使用趋势';

  @override
  String get providerDistribution => '服务商分布';

  @override
  String get modelDistribution => '模型分布';

  @override
  String get currentStreak => '连续使用天数';

  @override
  String streakDays(int count) {
    return '$count 天';
  }

  @override
  String get lastUsed => '最近使用';

  @override
  String get mostActiveDay => '最活跃的一天';

  @override
  String get charsPerMinute => '每分钟字数';

  @override
  String get efficiency => '效率';

  @override
  String get activity => '活跃度';

  @override
  String get noDataYet => '暂无数据，开始转录吧！';

  @override
  String get day => '日';

  @override
  String get week => '周';

  @override
  String get month => '月';

  @override
  String timeAgo(String time) {
    return '$time前';
  }

  @override
  String get minuteShort => '分';

  @override
  String get hourShort => '时';

  @override
  String get secondShort => '秒';

  @override
  String sessions(int count) {
    return '$count 次';
  }

  @override
  String get enhanceTokenUsage => '语音输入 Token 用量';

  @override
  String get enhanceInputTokens => '输入 Token';

  @override
  String get enhanceOutputTokens => '输出 Token';

  @override
  String get enhanceTotalTokens => '总 Token';

  @override
  String get correctionTokenUsage => '纠错 Token 用量';

  @override
  String get correctionRecallEfficiency => '纠错召回效率';

  @override
  String get correctionTotalCalls => '纠错调用次数';

  @override
  String get correctionLlmCalls => 'LLM 调用次数';

  @override
  String get correctionLlmRate => 'LLM 调用率';

  @override
  String get correctionSelectedRate => '候选入选率';

  @override
  String get correctionChangesTitle => '纠错明细（最近 20 条）';

  @override
  String get correctionChangesExpand => '展开查看';

  @override
  String get correctionChangesCollapse => '收起明细';

  @override
  String get correctionChangesCollapsedHint => '默认折叠，点击“展开查看”可查看纠错明细。';

  @override
  String get correctionChangesEmpty => '暂无纠错明细，开始一次录音并触发纠错后会显示在这里。';

  @override
  String get correctionChangedTerms => '纠正词条';

  @override
  String get correctionBeforeText => '纠错前';

  @override
  String get correctionAfterText => '纠错后';

  @override
  String get correctionSourceRealtime => '实时';

  @override
  String get correctionSourceRetrospective => '终态回溯';

  @override
  String get allTokenUsage => '全部 Token 汇总';

  @override
  String get retroTokenUsage => '终态回溯 Token 用量';

  @override
  String get retroSectionTitle => '终态回溯统计';

  @override
  String get retroTotalCalls => '回溯次数';

  @override
  String get retroLlmCalls => 'LLM 调用次数';

  @override
  String get retroTextChangedCount => '文本变更次数';

  @override
  String get retroTextChangedRate => '文本变更率';

  @override
  String get glossarySectionTitle => '术语锚定统计';

  @override
  String get glossaryPins => '新增锚定';

  @override
  String get glossaryStrongPromotions => '强锚定升级';

  @override
  String get glossaryOverrides => '手动覆盖';

  @override
  String get glossaryInjections => '注入 #R 次数';

  @override
  String get showInDock => '在 Dock 中显示';

  @override
  String get showInDockDescription => '控制应用程序图标是否显示在 Dock 上。';

  @override
  String get showInDockFailed => '修改 Dock 显示状态失败';

  @override
  String get trayOpen => '打开';

  @override
  String get trayQuit => '退出';

  @override
  String get recordingPathCopied => '录音路径已复制到剪贴板';

  @override
  String get openFolderFailed => '打开文件夹失败';

  @override
  String get cleanupFailed => '清理失败';

  @override
  String resetHotkeyDefault(Object key) {
    return '恢复默认（$key）';
  }

  @override
  String get vadTitle => '智能静音检测';

  @override
  String get vadDescription => '录音时自动检测沉默，超过设定时间后自动停止录音并开始转录。';

  @override
  String get vadEnable => '启用智能静音检测';

  @override
  String get vadSilenceThreshold => '静音阈值';

  @override
  String get vadSilenceDuration => '静音等待时长';

  @override
  String get sceneModeTitle => '场景模式';

  @override
  String get sceneModeDescription => '选择当前场景，AI 将根据场景调整文本规整的风格和格式。';

  @override
  String get sceneModeLabel => '当前场景';

  @override
  String get promptTemplates => '模板列表';

  @override
  String get promptCreateTemplate => '创建模板';

  @override
  String get promptTemplateName => '模板名称';

  @override
  String get promptTemplateContent => '模板内容';

  @override
  String get promptTemplateSaved => '模板已保存';

  @override
  String get promptBuiltin => '内置';

  @override
  String get promptBuiltinDefaultName => '默认提示词';

  @override
  String get promptBuiltinDefaultSummary => '通用文本规整与可读性优化';

  @override
  String get promptBuiltinPunctuationName => '标点修正';

  @override
  String get promptBuiltinPunctuationSummary => '仅修正断句与标点，不改原意';

  @override
  String get promptBuiltinFormalName => '正式文书';

  @override
  String get promptBuiltinFormalSummary => '将口语文本调整为正式书面语';

  @override
  String get promptBuiltinColloquialName => '口语化保留';

  @override
  String get promptBuiltinColloquialSummary => '轻度纠错并保留自然口语风格';

  @override
  String get promptBuiltinTranslateEnName => '翻译为英文';

  @override
  String get promptBuiltinTranslateEnSummary => '将输入翻译为自然流畅英文';

  @override
  String get promptSelectHint => '从左侧选择一个模板查看详情';

  @override
  String get promptPreview => '预览';

  @override
  String get dictionarySettings => '记忆库';

  @override
  String get dictionaryDescription => '设置词语纠正和保留规则，帮助 AI 更准确地输出专业术语和固定用语。';

  @override
  String get dictionaryAdd => '添加规则';

  @override
  String get dictionaryEdit => '编辑规则';

  @override
  String get dictionaryOriginal => '原始词';

  @override
  String get dictionaryOriginalHint => '可选：直接指定要纠正的原始词；留空时按拼音规则匹配';

  @override
  String get dictionaryCorrected => '纠正为（选填）';

  @override
  String get dictionaryCorrectedHint => '填写表示纠正目标；留空表示保留命中的词不改写';

  @override
  String get dictionaryCorrectedTip => '可仅填写“自定义拼音 + 纠正为”实现同音纠正；若“纠正为”留空则为保留规则';

  @override
  String get dictionaryCategory => '分类（选填）';

  @override
  String get dictionaryCategoryHint => '如：人名、术语、品牌';

  @override
  String get dictionaryCategoryAll => '全部';

  @override
  String get dictionaryTypeCorrection => '纠正';

  @override
  String get dictionaryTypePreserve => '保留';

  @override
  String get dictionarySearchHint => '搜索原词/纠正词/分类/拼音';

  @override
  String get dictionaryCountTotal => '总条目';

  @override
  String get dictionaryCountVisible => '当前显示';

  @override
  String get dictionaryCountEnabled => '已启用';

  @override
  String get dictionaryCountDisabled => '已禁用';

  @override
  String get dictionaryFilterAll => '全部状态';

  @override
  String get dictionaryFilterEnabled => '仅启用';

  @override
  String get dictionaryFilterDisabled => '仅禁用';

  @override
  String get dictionaryRowsPerPage => '每页';

  @override
  String get dictionaryPagePrev => '上一页';

  @override
  String get dictionaryPageNext => '下一页';

  @override
  String dictionaryPageIndicator(int current, int total) {
    return '第 $current / $total 页';
  }

  @override
  String dictionaryPageSummary(int from, int to, int total) {
    return '显示 $from - $to / 共 $total';
  }

  @override
  String get dictionaryEmpty => '词典为空';

  @override
  String get dictionaryEmptyHint => '添加纠正或保留规则，帮助 AI 更准确地输出';

  @override
  String get dictionaryExportCsv => '导出 CSV';

  @override
  String get dictionaryImportCsv => '导入 CSV';

  @override
  String dictionaryExportSuccess(String path) {
    return 'CSV 已导出到：$path';
  }

  @override
  String dictionaryExportWithExampleSuccess(String path, String examplePath) {
    return 'CSV 已导出到：$path\\n示例文件：$examplePath\\n用于修改此文件，请按示例文件格式导入。';
  }

  @override
  String get dictionaryExportFailed => '导出 CSV 失败';

  @override
  String dictionaryImportSuccess(int imported, int skipped, int total) {
    return '导入完成：新增 $imported 条，跳过 $skipped 条（共 $total 行）';
  }

  @override
  String get dictionaryImportInvalidFormat => 'CSV 格式无效：缺少 pinyinPattern 列';

  @override
  String get dictionaryImportFailed => '导入 CSV 失败';

  @override
  String get correctionEnabled => '智能纠错';

  @override
  String get correctionDescription => '基于拼音匹配自动纠正同音字，仅在词典非空时生效';

  @override
  String get retrospectiveCorrectionEnabled => '终态回溯复核';

  @override
  String get retrospectiveCorrectionDescription => '停止录音后对整段文本再纠错一次，提升术语一致性';

  @override
  String get textProcessing => '文本处理';

  @override
  String get textProcessingDescription => '控制识别后的纠错与上下文增强。';

  @override
  String get historyContextEnabled => '历史上下文优化';

  @override
  String get historyContextEnabledDescription => '参考最近相关历史，增强续写和上下文连贯性。';

  @override
  String get contextTab => '上下文';

  @override
  String get contextImportMarkdown => '导入 Markdown';

  @override
  String get contextSearchHint => '搜索术语、别名、来源';

  @override
  String get contextEmpty => '暂无上下文';

  @override
  String get contextCanPromote => '可提升为词典';

  @override
  String get contextPromoteToDictionary => '提升到词典';

  @override
  String get contextTypeCorrectionHint => '纠错提示';

  @override
  String get contextTypePreserveHint => '保留提示';

  @override
  String get contextTypeReference => '参考';

  @override
  String get contextImportDialogTitle => '导入 Markdown';

  @override
  String get contextImportFailed => 'Markdown 导入失败';

  @override
  String get contextImportPreviewTitle => '导入预览';

  @override
  String get contextPromoteUnavailable => '该条目当前不能提升为词典规则';

  @override
  String contextCount(int count) {
    return '共 $count 条';
  }

  @override
  String contextSelectedCount(int count) {
    return '已选 $count 条';
  }

  @override
  String get contextSelectAll => '全选';

  @override
  String get contextDeleteSelected => '批量删除';

  @override
  String contextDeleteSelectedSuccess(int count) {
    return '已删除 $count 条上下文';
  }

  @override
  String get contextContentEmpty => '内容为空';

  @override
  String contextAliasLabel(String value) {
    return '别名/误识别: $value';
  }

  @override
  String contextSourceLabel(String value) {
    return '来源: $value';
  }

  @override
  String contextDeleteSuccess(String term) {
    return '已删除 $term';
  }

  @override
  String contextPromoteSuccess(String term) {
    return '已将 $term 提升到词典';
  }

  @override
  String contextImportSuccess(
    int contextCount,
    int correctionCount,
    int preserveCount,
    int referenceCount,
  ) {
    return '导入完成：上下文 $contextCount 条，纠错 $correctionCount 条，保留 $preserveCount 条，参考 $referenceCount 条';
  }

  @override
  String contextImportPreviewSummary(
    int fileCount,
    int contextCount,
    int correctionCount,
    int preserveCount,
    int referenceCount,
    int skippedCount,
  ) {
    return '共 $fileCount 个文件，上下文 $contextCount 条，纠错 $correctionCount 条，保留 $preserveCount 条，参考 $referenceCount 条，跳过 $skippedCount 条';
  }

  @override
  String contextImportPreviewItemSummary(
    int contextCount,
    int correctionCount,
    int preserveCount,
    int referenceCount,
    int skippedCount,
  ) {
    return '上下文 $contextCount 条，纠错 $correctionCount 条，保留 $preserveCount 条，参考 $referenceCount 条，跳过 $skippedCount 条';
  }

  @override
  String get pinyinPreview => '拼音';

  @override
  String get pinyinOverride => '拼音规则（选填）';

  @override
  String get pinyinOverrideHint => '如 fan ruan，支持仅拼音匹配；空格分隔多音节';

  @override
  String get pinyinReset => '恢复自动拼音';

  @override
  String get addToDictionary => '加入提示词词典';

  @override
  String get addedToDictionary => '已加入词典';

  @override
  String get originalSttText => '原始语音识别文本';

  @override
  String get home => '首页';

  @override
  String get workspaceLabel => '工作区';

  @override
  String get settings => '设置';

  @override
  String get vendorLocalModel => '本地模型';

  @override
  String get vendorCustom => '自定义';

  @override
  String get localModelSttHint => '本地模型通过 sherpa-onnx 在本机运行，只需下载 ONNX 模型文件即可使用';

  @override
  String get localSttTinyDesc => 'Tiny (~75MB) - 速度最快，适合日常使用';

  @override
  String get localSttBaseDesc => 'Base (~142MB) - 平衡速度与准确率';

  @override
  String get localSttSmallDesc => 'Small (~466MB) - 更高准确率';

  @override
  String get download => '下载';

  @override
  String get downloaded => '已下载';

  @override
  String get customTemplateSummary => '自定义模板';

  @override
  String get openModelDir => '打开模型文件所在目录';
}
