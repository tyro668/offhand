// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Offhand';

  @override
  String get loading => 'Loading...';

  @override
  String get generalSettings => 'General';

  @override
  String get voiceModelSettings => 'Voice Model';

  @override
  String get speakerModelSettings => 'Speaker Model';

  @override
  String get textModelSettings => 'Text Model';

  @override
  String get promptWorkshop => 'Prompt Settings';

  @override
  String get aiEnhanceHub => 'AI Enhancement';

  @override
  String get history => 'History';

  @override
  String get logs => 'Logs';

  @override
  String get about => 'About';

  @override
  String get activationMode => 'Activation Mode';

  @override
  String get tapToTalk => 'Tap Mode';

  @override
  String get tapToTalkSubtitle => 'Tap to start, tap to stop';

  @override
  String get tapToTalkDescription =>
      'Press hotkey to start recording, press again to stop';

  @override
  String get pushToTalk => 'Hold Mode';

  @override
  String get pushToTalkSubtitle => 'Hold to record, release to stop';

  @override
  String get pushToTalkDescription => 'Hold hotkey to record, release to stop';

  @override
  String get dictationHotkey => 'Dictation Hotkey';

  @override
  String get dictationHotkeyDescription =>
      'Configure the hotkey for starting and stopping voice dictation.';

  @override
  String get meetingHotkey => 'Meeting Recording Hotkey';

  @override
  String get meetingHotkeyDescription =>
      'Configure the hotkey for starting and ending meeting recording. Press once to start, press again to end.';

  @override
  String get pressKeyToSet => 'Press a key to set as hotkey';

  @override
  String get clickToChangeHotkey => 'Click to change hotkey';

  @override
  String get resetToDefault => 'Reset to Default';

  @override
  String get permissions => 'Permissions';

  @override
  String get permissionsDescription =>
      'Manage system permissions for optimal performance.';

  @override
  String get microphonePermission => 'Microphone Permission';

  @override
  String get accessibilityPermission => 'Accessibility Permission';

  @override
  String get testPermission => 'Test';

  @override
  String get permissionGranted => 'Granted';

  @override
  String get permissionDenied => 'Denied';

  @override
  String get permissionHint =>
      'Microphone permission is required for voice input. Accessibility permission is needed for text insertion.';

  @override
  String get testMicrophonePermission => 'Test Microphone Permission';

  @override
  String get testAccessibilityPermission => 'Test Accessibility Permission';

  @override
  String get fixPermissionIssues => 'Fix Permission Issues';

  @override
  String get openSoundInput => 'Open Sound Input';

  @override
  String get openMicrophonePrivacy => 'Open Microphone Privacy';

  @override
  String get openAccessibilityPrivacy => 'Open Accessibility Privacy';

  @override
  String get microphoneInput => 'Microphone Input';

  @override
  String get microphoneInputDescription =>
      'Select the microphone for dictation. Enable \'Prefer Built-in Microphone\' to prevent audio interruptions when using Bluetooth headphones.';

  @override
  String get preferBuiltInMicrophone => 'Prefer Built-in Microphone';

  @override
  String get preferBuiltInMicrophoneSubtitle =>
      'External microphones may cause latency or reduce transcription quality';

  @override
  String get currentDevice => 'Current Device';

  @override
  String get unknownDevice => 'Unknown Device';

  @override
  String get noMicrophoneDetected => 'No microphone detected';

  @override
  String get using => 'Using';

  @override
  String get minRecordingDuration => 'Minimum Recording Duration';

  @override
  String get minRecordingDurationDescription =>
      'Recordings shorter than this duration will be automatically ignored to avoid accidental triggers.';

  @override
  String get ignoreShortRecordings => 'Ignore recordings shorter than';

  @override
  String get seconds => 'seconds';

  @override
  String get language => 'Language';

  @override
  String get languageDescription => 'Select your preferred interface language.';

  @override
  String get interfaceLanguage => 'Interface Language';

  @override
  String get english => 'English';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get logsDescription => 'View and manage application log files.';

  @override
  String get logFile => 'Log File';

  @override
  String get noLogFile => 'No Log File';

  @override
  String get openLogDirectory => 'Open Log Directory';

  @override
  String get copyLogPath => 'Copy Path';

  @override
  String get logPathCopied => 'Log path copied to clipboard';

  @override
  String get tip => 'Tip';

  @override
  String get logsTip =>
      'Log files contain application runtime records for troubleshooting. If the app encounters issues, you can provide this log file to developers for analysis.';

  @override
  String get recordingStorage => 'Recording Storage';

  @override
  String get recordingStorageDescription =>
      'View and manage recording audio files.';

  @override
  String get recordingFiles => 'Recording Files';

  @override
  String get files => 'files';

  @override
  String get openRecordingFolder => 'Open Folder';

  @override
  String get copyPath => 'Copy Path';

  @override
  String get clearRecordingFiles => 'Clear Files';

  @override
  String get clearRecordingFilesConfirm =>
      'Are you sure you want to delete all recording files? This action cannot be undone.';

  @override
  String get confirm => 'Confirm';

  @override
  String get addModel => 'Add Model';

  @override
  String get addVoiceModel => 'Add Voice Model';

  @override
  String get addTextModel => 'Add Text Model';

  @override
  String get editModel => 'Edit Model';

  @override
  String get editVoiceModel => 'Edit Voice Model';

  @override
  String get editTextModel => 'Edit Text Model';

  @override
  String get deleteModel => 'Delete Model';

  @override
  String deleteModelConfirm(Object model, Object vendor) {
    return 'Are you sure you want to delete $vendor / $model?';
  }

  @override
  String confirmDeleteModel(String vendor, String model) {
    return 'Are you sure you want to delete $vendor / $model?';
  }

  @override
  String get vendor => 'Vendor';

  @override
  String get model => 'Model';

  @override
  String get endpointUrl => 'Endpoint URL';

  @override
  String get apiKey => 'API Key';

  @override
  String get selectVendor => 'Select Vendor';

  @override
  String get selectModel => 'Select Model';

  @override
  String get custom => 'Custom';

  @override
  String enterModelName(Object example) {
    return 'Enter model name, e.g., $example';
  }

  @override
  String get enterApiKey => 'Enter API Key';

  @override
  String get saveChanges => 'Save Changes';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get testingConnection => 'Testing connection...';

  @override
  String get connectionSuccess => 'Connection successful ✓';

  @override
  String get connectionFailed =>
      'Connection failed, please check configuration';

  @override
  String get inUse => 'In Use';

  @override
  String get useThisModel => 'Use This Model';

  @override
  String get currentlyInUse => 'Currently in use';

  @override
  String get noModelsAdded => 'No models added yet';

  @override
  String get addVoiceModelHint =>
      'Click the button below to add a speech recognition model';

  @override
  String get addTextModelHint =>
      'Click the button below to add a large language model';

  @override
  String get enableTextEnhancement => 'Enable Text Enhancement';

  @override
  String get textEnhancementDescription =>
      'Use AI to enhance and correct transcribed text.';

  @override
  String get prompt => 'Prompt';

  @override
  String get promptDescription =>
      'Customize the AI behavior for text enhancement.';

  @override
  String get defaultPrompt => 'Default Prompt';

  @override
  String get customPrompt => 'Custom Prompt';

  @override
  String get useCustomPrompt => 'Use Custom Prompt';

  @override
  String get agentName => 'Agent Name';

  @override
  String get enterAgentName => 'Enter agent name';

  @override
  String get current => 'Current';

  @override
  String get test => 'Test';

  @override
  String get currentSystemPrompt => 'Current System Prompt';

  @override
  String get customPromptTitle => 'Custom Prompt';

  @override
  String get enableCustomPrompt => 'Enable Custom Prompt';

  @override
  String get customPromptEnabled =>
      'Enabled: Text enhancement will use custom prompt below';

  @override
  String get customPromptDisabled =>
      'Disabled: Text enhancement will use system default prompt';

  @override
  String agentNamePlaceholder(Object agentName) {
    return 'Use $agentName as placeholder for agent name';
  }

  @override
  String get systemPrompt => 'System Prompt';

  @override
  String get saveAgentConfig => 'Save Agent Configuration';

  @override
  String get restoreDefault => 'Restore Default';

  @override
  String get testYourAgent => 'Test Your Agent';

  @override
  String get testAgentDescription =>
      'Test with current text model and agent prompt.';

  @override
  String get testInput => 'Test Input';

  @override
  String get enterTestText => 'Enter text to polish...';

  @override
  String get running => 'Running...';

  @override
  String get runTest => 'Run Test';

  @override
  String get outputResult => 'Output Result';

  @override
  String get outputWillAppearHere => 'Output will appear here';

  @override
  String get historySection => 'History';

  @override
  String get noHistory => 'No transcription history';

  @override
  String get historyHint =>
      'Use hotkey to start recording, transcription results will appear here';

  @override
  String get clearHistory => 'Clear History';

  @override
  String get clearHistoryConfirm =>
      'Are you sure you want to clear all history? This action cannot be undone.';

  @override
  String get clearAll => 'Clear All';

  @override
  String get clear => 'Clear';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get deleteHistoryItem => 'Delete';

  @override
  String get searchHistory => 'Search history...';

  @override
  String get aboutSection => 'About';

  @override
  String get appDescription =>
      'Offhand is a voice input tool that supports multiple cloud LLMs and local Whisper models, turning speech into text instantly.';

  @override
  String get appSlogan => 'Speak freely, write unbound.';

  @override
  String get version => 'Version';

  @override
  String get checkForUpdates => 'Check for Updates';

  @override
  String get openSourceLicenses => 'Open Source Licenses';

  @override
  String get required => 'Required';

  @override
  String get optional => 'Optional';

  @override
  String get networkSettings => 'Network';

  @override
  String get networkSettingsDescription =>
      'Configure the network proxy mode for the application.';

  @override
  String get systemSettings => 'System';

  @override
  String get systemSettingsDescription =>
      'Configure system-level settings such as startup behavior and network proxy.';

  @override
  String get launchAtLogin => 'Launch at Login';

  @override
  String get launchAtLoginDescription =>
      'Automatically start Offhand when you log in.';

  @override
  String get launchAtLoginFailed => 'Failed to enable launch at login';

  @override
  String get disableLaunchAtLoginFailed => 'Failed to disable launch at login';

  @override
  String get proxyConfig => 'Proxy Configuration';

  @override
  String get useSystemProxy => 'Use System Proxy';

  @override
  String get systemProxySubtitle =>
      'Requests follow the system network proxy configuration.';

  @override
  String get noProxy => 'No Proxy';

  @override
  String get noProxySubtitle =>
      'All requests connect directly without any proxy.';

  @override
  String get inputMonitoringRequired => 'Input Monitoring Required';

  @override
  String get inputMonitoringDescription =>
      'The Fn global hotkey requires enabling Offhand in \"System Settings > Privacy & Security > Input Monitoring\".';

  @override
  String get accessibilityRequired => 'Accessibility Permission Required';

  @override
  String get accessibilityDescription =>
      'To enable automatic text input, Offhand needs to be enabled in \"System Settings > Privacy & Security > Accessibility\".';

  @override
  String get later => 'Later';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get pleaseConfigureSttModel =>
      'Please configure a speech recognition model first';

  @override
  String get overlayStarting => 'Mic starting';

  @override
  String get overlayRecording => 'Recording';

  @override
  String get overlayTranscribing => 'Transcribing';

  @override
  String get overlayEnhancing => 'Enhancing';

  @override
  String get overlayTranscribeFailed => 'Transcribe failed';

  @override
  String get theme => 'Theme';

  @override
  String get themeDescription =>
      'Choose the appearance theme for the application.';

  @override
  String get themeMode => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get localModelIdleUnloadTitle => 'Local model idle unload';

  @override
  String get localModelIdleUnloadDescription =>
      'Unload local model after idle period to reduce memory usage';

  @override
  String get localModelIdleUnloadTiming => 'Release timing';

  @override
  String get off => 'Off';

  @override
  String minutesShort(int value) {
    return '$value min';
  }

  @override
  String get speakerModelTitle => 'Meeting speaker ID (3D-Speaker)';

  @override
  String get speakerModelDescription =>
      'Use local 3D-Speaker model for diarization with configurable max speakers and model path';

  @override
  String get speakerModelEnable => 'Enable 3D-Speaker';

  @override
  String get speakerModelHeaderTitle => '3D-Speaker Voice Recognition';

  @override
  String get speakerModelHeaderSubtitle =>
      'High-accuracy speaker diarization and recognition engine';

  @override
  String get speakerModelBasicSettings => 'Basic Settings';

  @override
  String get speakerModelAlgorithmParams => 'Algorithm Parameters';

  @override
  String get speakerModelManagement => 'Speaker Model Management';

  @override
  String get speakerModelImportLocal => 'Import Local Model';

  @override
  String get speakerModelSingleSpeakerMode =>
      'Single-speaker presentation mode';

  @override
  String get speakerModelSingleSpeakerModeDesc =>
      'Force all segments to one speaker label for solo talks';

  @override
  String get speakerModelMaxSpeakers => 'Max speakers';

  @override
  String get speakerModelMaxSpeakersDesc =>
      'Upper bound for speaker clusters in one meeting';

  @override
  String get speakerModelPresetTitle => 'One-click presets';

  @override
  String get speakerModelPresetConsistency => 'Consistency first';

  @override
  String get speakerModelPresetBalanced => 'Balanced';

  @override
  String get speakerModelPresetSeparation => 'Separation first';

  @override
  String get speakerModelOnlineBaseThreshold => 'Online base threshold';

  @override
  String get speakerModelOnlineBaseThresholdDesc =>
      'Lower value merges more aggressively, higher value splits more easily';

  @override
  String get speakerModelTop1Top2Margin => 'Top1-Top2 margin';

  @override
  String get speakerModelTop1Top2MarginDesc =>
      'Smaller margin accepts best match more often, improving continuity';

  @override
  String get speakerModelOfflineMergeThreshold => 'Offline merge threshold';

  @override
  String get speakerModelOfflineMergeThresholdDesc =>
      'Lower value merges clusters after meeting, higher value keeps them separate';

  @override
  String get speakerModelPathNotSet =>
      'Model path not set (default paths will be tried)';

  @override
  String get speakerModelPickModel => 'Pick model';

  @override
  String get speakerModelDownloading => 'Downloading...';

  @override
  String get speakerModelDownloadDefault => 'Download default';

  @override
  String get speakerModelDownloadSource => 'Download source';

  @override
  String get speakerModelDownloadSourceAuto => 'Auto';

  @override
  String get speakerModelDownloadSourceDirect => 'Direct only';

  @override
  String get speakerModelDownloadSourceMirror => 'Mirror only';

  @override
  String get speakerModelReady => 'Model file ready';

  @override
  String get speakerModelMissing => 'Model file not found, please re-select';

  @override
  String get speakerModelDefaultLookup =>
      'Default search: <app>/models/3d-speaker/model.onnx';

  @override
  String get speakerModelDownloaded => '3D-Speaker model downloaded';

  @override
  String get speakerModelDownloadFailed =>
      'Download failed. Check network or pick an ONNX model manually';

  @override
  String speakerModelDownloadStatusKnown(
    String downloaded,
    String total,
    String percent,
  ) {
    return 'Downloaded $downloaded / $total ($percent%)';
  }

  @override
  String speakerModelDownloadStatusUnknown(String downloaded) {
    return 'Downloaded $downloaded (total size unknown)';
  }

  @override
  String userLabel(String id) {
    return 'speaker$id';
  }

  @override
  String userIdLabel(String user) {
    return '$user';
  }

  @override
  String get dashboard => 'Dashboard';

  @override
  String get totalTranscriptions => 'Total Transcriptions';

  @override
  String get totalRecordingTime => 'Total Recording Time';

  @override
  String get totalCharacters => 'Total Characters';

  @override
  String get avgCharsPerSession => 'Avg Chars/Session';

  @override
  String get avgRecordingDuration => 'Avg Duration';

  @override
  String get today => 'Today';

  @override
  String get thisWeek => 'This Week';

  @override
  String get thisMonth => 'This Month';

  @override
  String get transcriptionCount => 'Transcriptions';

  @override
  String get recordingTime => 'Recording Time';

  @override
  String get characters => 'Characters';

  @override
  String get usageTrend => 'Usage Trend';

  @override
  String get providerDistribution => 'Provider Distribution';

  @override
  String get modelDistribution => 'Model Distribution';

  @override
  String get currentStreak => 'Current Streak';

  @override
  String streakDays(int count) {
    return '$count days';
  }

  @override
  String get lastUsed => 'Last Used';

  @override
  String get mostActiveDay => 'Most Active Day';

  @override
  String get charsPerMinute => 'Chars/Minute';

  @override
  String get efficiency => 'Efficiency';

  @override
  String get activity => 'Activity';

  @override
  String get noDataYet => 'No data yet. Start transcribing!';

  @override
  String get day => 'Day';

  @override
  String get week => 'Week';

  @override
  String get month => 'Month';

  @override
  String timeAgo(String time) {
    return '$time ago';
  }

  @override
  String get minuteShort => 'm';

  @override
  String get hourShort => 'h';

  @override
  String get secondShort => 's';

  @override
  String sessions(int count) {
    return '$count sessions';
  }

  @override
  String get enhanceTokenUsage => 'Voice Input Tokens';

  @override
  String get enhanceInputTokens => 'Input Tokens';

  @override
  String get enhanceOutputTokens => 'Output Tokens';

  @override
  String get enhanceTotalTokens => 'Total Tokens';

  @override
  String get meetingTokenUsage => 'Meeting Recording Tokens';

  @override
  String get correctionTokenUsage => 'Correction Tokens';

  @override
  String get correctionRecallEfficiency => 'Correction Recall Efficiency';

  @override
  String get correctionTotalCalls => 'Correction Calls';

  @override
  String get correctionLlmCalls => 'LLM Calls';

  @override
  String get correctionLlmRate => 'LLM Call Rate';

  @override
  String get correctionSelectedRate => 'Candidate Selection Rate';

  @override
  String get correctionChangesTitle => 'Correction Details (Latest 20)';

  @override
  String get correctionChangesExpand => 'Expand';

  @override
  String get correctionChangesCollapse => 'Collapse';

  @override
  String get correctionChangesCollapsedHint =>
      'Collapsed by default. Click Expand to view correction details.';

  @override
  String get correctionChangesEmpty =>
      'No correction details yet. Start a recording and trigger correction to see entries here.';

  @override
  String get correctionChangedTerms => 'Changed Terms';

  @override
  String get correctionBeforeText => 'Before';

  @override
  String get correctionAfterText => 'After';

  @override
  String get correctionSourceRealtime => 'Realtime';

  @override
  String get correctionSourceRetrospective => 'Retrospective';

  @override
  String get allTokenUsage => 'All Tokens Summary';

  @override
  String get retroTokenUsage => 'Retrospective Tokens';

  @override
  String get retroSectionTitle => 'Retrospective Correction';

  @override
  String get retroTotalCalls => 'Retro Calls';

  @override
  String get retroLlmCalls => 'LLM Calls';

  @override
  String get retroTextChangedCount => 'Text Changed';

  @override
  String get retroTextChangedRate => 'Change Rate';

  @override
  String get glossarySectionTitle => 'Terminology Anchoring';

  @override
  String get glossaryPins => 'New Pins';

  @override
  String get glossaryStrongPromotions => 'Strong Promotions';

  @override
  String get glossaryOverrides => 'Manual Overrides';

  @override
  String get glossaryInjections => '#R Injections';

  @override
  String get showInDock => 'Show in Dock';

  @override
  String get showInDockDescription =>
      'Show the application icon in the macOS Dock.';

  @override
  String get showInDockFailed => 'Failed to change Dock visibility';

  @override
  String get trayOpen => 'Open';

  @override
  String get trayQuit => 'Quit';

  @override
  String get recordingPathCopied => 'Recording path copied to clipboard';

  @override
  String get openFolderFailed => 'Failed to open folder';

  @override
  String get cleanupFailed => 'Cleanup failed';

  @override
  String resetHotkeyDefault(Object key) {
    return 'Reset Default ($key)';
  }

  @override
  String get vadTitle => 'Smart Silence Detection';

  @override
  String get vadDescription =>
      'Automatically detect silence during recording and stop recording after the set duration.';

  @override
  String get vadEnable => 'Enable Smart Silence Detection';

  @override
  String get vadSilenceThreshold => 'Silence Threshold';

  @override
  String get vadSilenceDuration => 'Silence Wait Duration';

  @override
  String get sceneModeTitle => 'Scene Mode';

  @override
  String get sceneModeDescription =>
      'Select the current scene. AI will adjust text formatting style accordingly.';

  @override
  String get sceneModeLabel => 'Current Scene';

  @override
  String get promptTemplates => 'Templates';

  @override
  String get promptCreateTemplate => 'Create Template';

  @override
  String get promptTemplateName => 'Template Name';

  @override
  String get promptTemplateContent => 'Template Content';

  @override
  String get promptTemplateSaved => 'Template saved';

  @override
  String get promptBuiltin => 'Built-in';

  @override
  String get promptBuiltinDefaultName => 'Default Prompt';

  @override
  String get promptBuiltinDefaultSummary =>
      'General text cleanup and readability enhancement';

  @override
  String get promptBuiltinPunctuationName => 'Punctuation Fix';

  @override
  String get promptBuiltinPunctuationSummary =>
      'Only fix sentence breaks and punctuation, keep original meaning';

  @override
  String get promptBuiltinFormalName => 'Formal Writing';

  @override
  String get promptBuiltinFormalSummary =>
      'Turn colloquial text into formal written style';

  @override
  String get promptBuiltinColloquialName => 'Colloquial Preserve';

  @override
  String get promptBuiltinColloquialSummary =>
      'Light correction while preserving natural spoken style';

  @override
  String get promptBuiltinTranslateEnName => 'Translate to English';

  @override
  String get promptBuiltinTranslateEnSummary =>
      'Translate input into natural and fluent English';

  @override
  String get promptBuiltinMeetingName => 'Meeting Minutes';

  @override
  String get promptBuiltinMeetingSummary =>
      'Organize into structured meeting-note bullet points';

  @override
  String get promptSelectHint =>
      'Select a template from the list to view details';

  @override
  String get promptPreview => 'Preview';

  @override
  String get dictionarySettings => 'Dictionary';

  @override
  String get dictionaryDescription =>
      'Set up correction and preservation rules to help AI output professional terms and fixed expressions more accurately.';

  @override
  String get dictionaryAdd => 'Add Rule';

  @override
  String get dictionaryEdit => 'Edit Rule';

  @override
  String get dictionaryOriginal => 'Original Word';

  @override
  String get dictionaryOriginalHint =>
      'Optional: specific source word to correct; leave empty to match by pinyin pattern';

  @override
  String get dictionaryCorrected => 'Correct To (optional)';

  @override
  String get dictionaryCorrectedHint =>
      'Fill to set correction target; leave empty to preserve matched words as-is';

  @override
  String get dictionaryCorrectedTip =>
      'You can use only \'Pinyin Pattern + Correct To\' for homophone correction; leave \'Correct To\' empty for preserve rules';

  @override
  String get dictionaryCategory => 'Category (optional)';

  @override
  String get dictionaryCategoryHint => 'e.g., Names, Terms, Brands';

  @override
  String get dictionaryCategoryAll => 'All';

  @override
  String get dictionaryTypeCorrection => 'Correct';

  @override
  String get dictionaryTypePreserve => 'Preserve';

  @override
  String get dictionarySearchHint =>
      'Search original/corrected/category/pinyin';

  @override
  String get dictionaryCountTotal => 'Total';

  @override
  String get dictionaryCountVisible => 'Visible';

  @override
  String get dictionaryCountEnabled => 'Enabled';

  @override
  String get dictionaryCountDisabled => 'Disabled';

  @override
  String get dictionaryFilterAll => 'All Status';

  @override
  String get dictionaryFilterEnabled => 'Enabled Only';

  @override
  String get dictionaryFilterDisabled => 'Disabled Only';

  @override
  String get dictionaryRowsPerPage => 'Rows';

  @override
  String get dictionaryPagePrev => 'Previous Page';

  @override
  String get dictionaryPageNext => 'Next Page';

  @override
  String dictionaryPageIndicator(int current, int total) {
    return 'Page $current / $total';
  }

  @override
  String dictionaryPageSummary(int from, int to, int total) {
    return 'Showing $from - $to of $total';
  }

  @override
  String get dictionaryEmpty => 'Dictionary is empty';

  @override
  String get dictionaryEmptyHint =>
      'Add correction or preservation rules to help AI output more accurately';

  @override
  String get dictionaryExportCsv => 'Export CSV';

  @override
  String get dictionaryImportCsv => 'Import CSV';

  @override
  String dictionaryExportSuccess(String path) {
    return 'CSV exported to: $path';
  }

  @override
  String dictionaryExportWithExampleSuccess(String path, String examplePath) {
    return 'CSV exported to: $path\\nExample file: $examplePath\\nTo modify this file, please import it using the example format.';
  }

  @override
  String get dictionaryExportFailed => 'Failed to export CSV';

  @override
  String dictionaryImportSuccess(int imported, int skipped, int total) {
    return 'Import completed: $imported added, $skipped skipped ($total rows)';
  }

  @override
  String get dictionaryImportInvalidFormat =>
      'Invalid CSV format: missing pinyinPattern column';

  @override
  String get dictionaryImportFailed => 'Failed to import CSV';

  @override
  String get correctionEnabled => 'Smart Correction';

  @override
  String get correctionDescription =>
      'Auto-correct homophones via pinyin matching, effective only when dictionary is non-empty';

  @override
  String get retrospectiveCorrectionEnabled => 'Retrospective Review';

  @override
  String get retrospectiveCorrectionDescription =>
      'Run one more paragraph-level correction when recording stops for better term consistency';

  @override
  String get pinyinPreview => 'Pinyin';

  @override
  String get pinyinOverride => 'Pinyin Pattern (optional)';

  @override
  String get pinyinOverrideHint =>
      'E.g. fan ruan; supports pinyin-only matching, space-separated syllables';

  @override
  String get pinyinReset => 'Reset to auto pinyin';

  @override
  String get meetingMinutes => 'Meeting Minutes';

  @override
  String get meetingNew => 'New Meeting';

  @override
  String get meetingRecording => 'Recording';

  @override
  String get meetingPaused => 'Paused';

  @override
  String get meetingCompleted => 'Completed';

  @override
  String get meetingEmpty => 'No meeting records';

  @override
  String get meetingEmptyHint =>
      'Click the button above to start a new meeting recording';

  @override
  String get meetingStarting => 'Starting meeting...';

  @override
  String get meetingTitleHint => 'Enter meeting title...';

  @override
  String get meetingPause => 'Pause';

  @override
  String get meetingResume => 'Resume';

  @override
  String get meetingStop => 'Stop';

  @override
  String get meetingListening => 'Listening...';

  @override
  String get meetingListeningHint =>
      'Audio will be automatically segmented and transcribed';

  @override
  String get meetingTranscribing => 'Transcribing';

  @override
  String get meetingEnhancing => 'Enhancing text';

  @override
  String get meetingWaitingProcess => 'Waiting to process';

  @override
  String get meetingPending => 'Pending';

  @override
  String get meetingDone => 'Done';

  @override
  String get meetingError => 'Failed';

  @override
  String get meetingSegmentError => 'Processing failed';

  @override
  String get meetingRetry => 'Retry';

  @override
  String get meetingNoContent => 'No transcription content';

  @override
  String get meetingProcessing => 'Processing remaining segments...';

  @override
  String get meetingSegments => 'Segments';

  @override
  String get meetingLongPressToEnd => 'Long press to end meeting';

  @override
  String get meetingEndingConfirm => 'Ending meeting...';

  @override
  String get meetingRecordingSegment => 'Recording...';

  @override
  String get meetingFullTranscription => 'Meeting Minutes';

  @override
  String get meetingStopConfirmTitle => 'End Meeting';

  @override
  String get meetingStopConfirm =>
      'Are you sure you want to end the current meeting recording? All recorded segments will be processed first.';

  @override
  String get meetingCancelConfirmTitle => 'Cancel Meeting';

  @override
  String get meetingCancelConfirm =>
      'Are you sure you want to cancel and discard the current meeting? This action cannot be undone.';

  @override
  String get meetingDeleteConfirmTitle => 'Delete Meeting';

  @override
  String get meetingDeleteConfirm =>
      'Are you sure you want to delete this meeting record? This action cannot be undone.';

  @override
  String get meetingDate => 'Date';

  @override
  String get meetingDuration => 'Duration';

  @override
  String get meetingTotalChars => 'Total Characters';

  @override
  String get meetingTitle => 'Meeting Title';

  @override
  String get meetingSaved => 'Saved';

  @override
  String get meetingSummary => 'Meeting Summary';

  @override
  String get meetingContent => 'Meeting Content';

  @override
  String get meetingCopyAll => 'Copy All';

  @override
  String get meetingExportText => 'Export as Text';

  @override
  String get meetingExportMarkdown => 'Export as Markdown';

  @override
  String get meetingExported => 'Exported to clipboard';

  @override
  String get meetingEmptyContent => 'Empty';

  @override
  String get meetingNotFound => 'Meeting record not found';

  @override
  String get meetingOverlayStarting => 'Meeting starting';

  @override
  String get meetingOverlayRecording => 'Meeting recording';

  @override
  String get meetingOverlayPaused => 'Meeting paused';

  @override
  String get meetingOverlayProcessing => 'Meeting processing';

  @override
  String get meetingRecordingBanner => 'Meeting recording in progress';

  @override
  String get meetingReturnToRecording => 'Return to recording';

  @override
  String get meetingSegmentView => 'Segments';

  @override
  String get meetingMergedNoteView => 'Merged Notes';

  @override
  String get meetingLiveSummaryView => 'Live Summary';

  @override
  String get meetingLiveSummaryWaiting =>
      'Waiting for enough content to generate summary...';

  @override
  String get meetingFinalizing => 'Finalizing';

  @override
  String get meetingSummaryUpdating => 'Updating summary...';

  @override
  String get meetingStreamingMerge => 'Merging...';

  @override
  String get meetingDashboardToday => 'TODAY\'S MEETINGS';

  @override
  String get meetingDashboardRecents => 'RECENTS';

  @override
  String get meetingDashboardLive => 'LIVE MEETING';

  @override
  String get meetingDashboardCancel => 'CANCEL';

  @override
  String get meetingDashboardSaveNotes => 'SAVE NOTES';

  @override
  String get meetingDetailTab => 'Meeting Details';

  @override
  String get meetingSummaryTab => 'Meeting Summary';

  @override
  String get meetingGeneratingSummary => 'Generating meeting summary...';

  @override
  String get meetingNoSummary => 'No meeting summary yet';

  @override
  String get meetingRegenerateSummary => 'Regenerate';

  @override
  String get meetingUnifyRebuild => 'Unify Rebuild';

  @override
  String get meetingUnifyRebuildTitle => 'Unify Historical Meetings';

  @override
  String get meetingUnifyRebuildConfirm =>
      'Meeting minutes and summaries will be rebuilt using the same rule as segment view (prefer enhanced text). Continue?';

  @override
  String get meetingUnifyRebuildRunning => 'Unifying historical meetings...';

  @override
  String meetingUnifyRebuildDone(int count) {
    return 'Unified rebuild complete: $count';
  }

  @override
  String meetingStatsSummary(int totalCount, int completedCount) {
    return 'Total $totalCount · Completed $completedCount';
  }

  @override
  String get meetingRecoverRecording => 'Repair Recording';

  @override
  String meetingRecoverRecordingSuccess(int count) {
    return 'Repaired $count stuck recording session(s)';
  }

  @override
  String get meetingRecoverRecordingNone => 'No stuck recording sessions found';

  @override
  String get meetingSearchHint => 'Search title/summary/content';

  @override
  String get meetingManageGroups => 'Manage Groups';

  @override
  String get meetingMoreActions => 'More Actions';

  @override
  String get meetingMoveToGroup => 'Move Group';

  @override
  String get meetingMoveToGroupTitle => 'Move to Group';

  @override
  String get meetingCreateGroupAndMove => 'Create Group and Move';

  @override
  String get meetingGroupManageTitle => 'Group Management';

  @override
  String get meetingGroupManageEmptyHint =>
      'No custom groups yet. Click the button below to create one.';

  @override
  String get meetingGroupClose => 'Close';

  @override
  String get meetingGroupCreate => 'Create Group';

  @override
  String get meetingGroupCreateTitle => 'Create Group';

  @override
  String get meetingGroupNameHint => 'Enter group name';

  @override
  String get meetingGroupRenameTitle => 'Rename Group';

  @override
  String get meetingGroupRenameHint => 'Enter new group name';

  @override
  String get meetingAllGroups => 'All';

  @override
  String get meetingUngrouped => 'Ungrouped';

  @override
  String meetingStartFailed(String error) {
    return 'Failed to start meeting: $error';
  }

  @override
  String meetingStopFailed(String error) {
    return 'Failed to stop meeting: $error';
  }

  @override
  String meetingMovedToFinalizing(String status) {
    return 'Meeting has entered $status';
  }

  @override
  String get meetingStoppingPleaseWait => 'Stopping meeting, please wait…';

  @override
  String get meetingStopping => 'Stopping meeting…';

  @override
  String get addToDictionary => 'Add to Dictionary';

  @override
  String get addedToDictionary => 'Added to dictionary';

  @override
  String get originalSttText => 'Original speech-to-text';

  @override
  String get home => 'Home';

  @override
  String get settings => 'Settings';

  @override
  String get vendorLocalModel => 'Local Model';

  @override
  String get vendorCustom => 'Custom';

  @override
  String get localModelSttHint =>
      'Local model calls whisper.cpp directly via FFI, just download the model file to use.';

  @override
  String get localSttTinyDesc =>
      'Tiny (~75MB) - Fastest, suitable for daily use';

  @override
  String get localSttBaseDesc => 'Base (~142MB) - Balanced speed and accuracy';

  @override
  String get localSttSmallDesc => 'Small (~466MB) - Higher accuracy';

  @override
  String get localModelAiHint =>
      'Local model calls llama.cpp directly via FFI. No internet required. Supports macOS and Windows.';

  @override
  String get localAiQ5Desc =>
      'Qwen2.5 0.5B Q5_K_M (~400MB) - Recommended, balanced quality and speed';

  @override
  String get localAiQ4Desc =>
      'Qwen2.5 0.5B Q4_K_M (~350MB) - Smaller and faster';

  @override
  String get localAiQwen35_2BDesc =>
      'Qwen3.5 2B Q4_K_M (~1.5GB) - Lightweight next-gen, notable quality boost';

  @override
  String get localAiQwen35_4BDesc =>
      'Qwen3.5 4B Q4_K_M (~2.7GB) - Recommended, balanced speed and quality';

  @override
  String get localAiQwen35_9BDesc =>
      'Qwen3.5 9B Q4_K_M (~5.5GB) - High quality, 16GB+ RAM recommended';

  @override
  String get download => 'Download';

  @override
  String get downloaded => 'Downloaded';

  @override
  String get customTemplateSummary => 'Custom Template';

  @override
  String get openModelDir => 'Open model file directory';
}
