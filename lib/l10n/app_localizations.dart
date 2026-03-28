import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// The title of the application
  ///
  /// In en, this message translates to:
  /// **'Offhand'**
  String get appTitle;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @generalSettings.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalSettings;

  /// No description provided for @voiceModelSettings.
  ///
  /// In en, this message translates to:
  /// **'Voice Model'**
  String get voiceModelSettings;

  /// No description provided for @textModelSettings.
  ///
  /// In en, this message translates to:
  /// **'Text Model'**
  String get textModelSettings;

  /// No description provided for @promptWorkshop.
  ///
  /// In en, this message translates to:
  /// **'Prompt Settings'**
  String get promptWorkshop;

  /// No description provided for @aiEnhanceHub.
  ///
  /// In en, this message translates to:
  /// **'AI Enhancement'**
  String get aiEnhanceHub;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @logs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logs;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @activationMode.
  ///
  /// In en, this message translates to:
  /// **'Activation Mode'**
  String get activationMode;

  /// No description provided for @tapToTalk.
  ///
  /// In en, this message translates to:
  /// **'Tap Mode'**
  String get tapToTalk;

  /// No description provided for @tapToTalkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap to start, tap to stop'**
  String get tapToTalkSubtitle;

  /// No description provided for @tapToTalkDescription.
  ///
  /// In en, this message translates to:
  /// **'Press hotkey to start recording, press again to stop'**
  String get tapToTalkDescription;

  /// No description provided for @pushToTalk.
  ///
  /// In en, this message translates to:
  /// **'Hold Mode'**
  String get pushToTalk;

  /// No description provided for @pushToTalkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hold to record, release to stop'**
  String get pushToTalkSubtitle;

  /// No description provided for @pushToTalkDescription.
  ///
  /// In en, this message translates to:
  /// **'Hold hotkey to record, release to stop'**
  String get pushToTalkDescription;

  /// No description provided for @dictationHotkey.
  ///
  /// In en, this message translates to:
  /// **'Dictation Hotkey'**
  String get dictationHotkey;

  /// No description provided for @dictationHotkeyDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure the hotkey for starting and stopping voice dictation.'**
  String get dictationHotkeyDescription;

  /// No description provided for @meetingHotkey.
  ///
  /// In en, this message translates to:
  /// **'Meeting Recording Hotkey'**
  String get meetingHotkey;

  /// No description provided for @meetingHotkeyDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure the hotkey for starting and ending meeting recording. Press once to start, press again to end.'**
  String get meetingHotkeyDescription;

  /// No description provided for @pressKeyToSet.
  ///
  /// In en, this message translates to:
  /// **'Press a key to set as hotkey'**
  String get pressKeyToSet;

  /// No description provided for @clickToChangeHotkey.
  ///
  /// In en, this message translates to:
  /// **'Click to change hotkey'**
  String get clickToChangeHotkey;

  /// No description provided for @resetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to Default'**
  String get resetToDefault;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// No description provided for @permissionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage system permissions for optimal performance.'**
  String get permissionsDescription;

  /// No description provided for @microphonePermission.
  ///
  /// In en, this message translates to:
  /// **'Microphone Permission'**
  String get microphonePermission;

  /// No description provided for @accessibilityPermission.
  ///
  /// In en, this message translates to:
  /// **'Accessibility Permission'**
  String get accessibilityPermission;

  /// No description provided for @testPermission.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get testPermission;

  /// No description provided for @permissionGranted.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get permissionGranted;

  /// No description provided for @permissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get permissionDenied;

  /// No description provided for @permissionHint.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required for voice input. Accessibility permission is needed for text insertion.'**
  String get permissionHint;

  /// No description provided for @testMicrophonePermission.
  ///
  /// In en, this message translates to:
  /// **'Test Microphone Permission'**
  String get testMicrophonePermission;

  /// No description provided for @testAccessibilityPermission.
  ///
  /// In en, this message translates to:
  /// **'Test Accessibility Permission'**
  String get testAccessibilityPermission;

  /// No description provided for @fixPermissionIssues.
  ///
  /// In en, this message translates to:
  /// **'Fix Permission Issues'**
  String get fixPermissionIssues;

  /// No description provided for @openSoundInput.
  ///
  /// In en, this message translates to:
  /// **'Open Sound Input'**
  String get openSoundInput;

  /// No description provided for @openMicrophonePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Open Microphone Privacy'**
  String get openMicrophonePrivacy;

  /// No description provided for @openAccessibilityPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Open Accessibility Privacy'**
  String get openAccessibilityPrivacy;

  /// No description provided for @microphoneInput.
  ///
  /// In en, this message translates to:
  /// **'Microphone Input'**
  String get microphoneInput;

  /// No description provided for @microphoneInputDescription.
  ///
  /// In en, this message translates to:
  /// **'Select the microphone for dictation. Enable \'Prefer Built-in Microphone\' to prevent audio interruptions when using Bluetooth headphones.'**
  String get microphoneInputDescription;

  /// No description provided for @preferBuiltInMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Prefer Built-in Microphone'**
  String get preferBuiltInMicrophone;

  /// No description provided for @preferBuiltInMicrophoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'External microphones may cause latency or reduce transcription quality'**
  String get preferBuiltInMicrophoneSubtitle;

  /// No description provided for @currentDevice.
  ///
  /// In en, this message translates to:
  /// **'Current Device'**
  String get currentDevice;

  /// No description provided for @unknownDevice.
  ///
  /// In en, this message translates to:
  /// **'Unknown Device'**
  String get unknownDevice;

  /// No description provided for @noMicrophoneDetected.
  ///
  /// In en, this message translates to:
  /// **'No microphone detected'**
  String get noMicrophoneDetected;

  /// No description provided for @using.
  ///
  /// In en, this message translates to:
  /// **'Using'**
  String get using;

  /// No description provided for @minRecordingDuration.
  ///
  /// In en, this message translates to:
  /// **'Minimum Recording Duration'**
  String get minRecordingDuration;

  /// No description provided for @minRecordingDurationDescription.
  ///
  /// In en, this message translates to:
  /// **'Recordings shorter than this duration will be automatically ignored to avoid accidental triggers.'**
  String get minRecordingDurationDescription;

  /// No description provided for @ignoreShortRecordings.
  ///
  /// In en, this message translates to:
  /// **'Ignore recordings shorter than'**
  String get ignoreShortRecordings;

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'seconds'**
  String get seconds;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageDescription.
  ///
  /// In en, this message translates to:
  /// **'Select your preferred interface language.'**
  String get languageDescription;

  /// No description provided for @interfaceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Interface Language'**
  String get interfaceLanguage;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @simplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get simplifiedChinese;

  /// No description provided for @logsDescription.
  ///
  /// In en, this message translates to:
  /// **'View and manage application log files.'**
  String get logsDescription;

  /// No description provided for @logFile.
  ///
  /// In en, this message translates to:
  /// **'Log File'**
  String get logFile;

  /// No description provided for @noLogFile.
  ///
  /// In en, this message translates to:
  /// **'No Log File'**
  String get noLogFile;

  /// No description provided for @openLogDirectory.
  ///
  /// In en, this message translates to:
  /// **'Open Log Directory'**
  String get openLogDirectory;

  /// No description provided for @copyLogPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Path'**
  String get copyLogPath;

  /// No description provided for @logPathCopied.
  ///
  /// In en, this message translates to:
  /// **'Log path copied to clipboard'**
  String get logPathCopied;

  /// No description provided for @tip.
  ///
  /// In en, this message translates to:
  /// **'Tip'**
  String get tip;

  /// No description provided for @logsTip.
  ///
  /// In en, this message translates to:
  /// **'Log files contain application runtime records for troubleshooting. If the app encounters issues, you can provide this log file to developers for analysis.'**
  String get logsTip;

  /// No description provided for @recordingStorage.
  ///
  /// In en, this message translates to:
  /// **'Recording Storage'**
  String get recordingStorage;

  /// No description provided for @recordingStorageDescription.
  ///
  /// In en, this message translates to:
  /// **'View and manage recording audio files.'**
  String get recordingStorageDescription;

  /// No description provided for @recordingFiles.
  ///
  /// In en, this message translates to:
  /// **'Recording Files'**
  String get recordingFiles;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'files'**
  String get files;

  /// No description provided for @openRecordingFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get openRecordingFolder;

  /// No description provided for @copyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Path'**
  String get copyPath;

  /// No description provided for @clearRecordingFiles.
  ///
  /// In en, this message translates to:
  /// **'Clear Files'**
  String get clearRecordingFiles;

  /// No description provided for @clearRecordingFilesConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all recording files? This action cannot be undone.'**
  String get clearRecordingFilesConfirm;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @addModel.
  ///
  /// In en, this message translates to:
  /// **'Add Model'**
  String get addModel;

  /// No description provided for @addVoiceModel.
  ///
  /// In en, this message translates to:
  /// **'Add Voice Model'**
  String get addVoiceModel;

  /// No description provided for @addTextModel.
  ///
  /// In en, this message translates to:
  /// **'Add Text Model'**
  String get addTextModel;

  /// No description provided for @editModel.
  ///
  /// In en, this message translates to:
  /// **'Edit Model'**
  String get editModel;

  /// No description provided for @editVoiceModel.
  ///
  /// In en, this message translates to:
  /// **'Edit Voice Model'**
  String get editVoiceModel;

  /// No description provided for @editTextModel.
  ///
  /// In en, this message translates to:
  /// **'Edit Text Model'**
  String get editTextModel;

  /// No description provided for @deleteModel.
  ///
  /// In en, this message translates to:
  /// **'Delete Model'**
  String get deleteModel;

  /// No description provided for @deleteModelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {vendor} / {model}?'**
  String deleteModelConfirm(Object model, Object vendor);

  /// Confirmation message for deleting a model
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {vendor} / {model}?'**
  String confirmDeleteModel(String vendor, String model);

  /// No description provided for @vendor.
  ///
  /// In en, this message translates to:
  /// **'Vendor'**
  String get vendor;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @endpointUrl.
  ///
  /// In en, this message translates to:
  /// **'Endpoint URL'**
  String get endpointUrl;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKey;

  /// No description provided for @selectVendor.
  ///
  /// In en, this message translates to:
  /// **'Select Vendor'**
  String get selectVendor;

  /// No description provided for @selectModel.
  ///
  /// In en, this message translates to:
  /// **'Select Model'**
  String get selectModel;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @enterModelName.
  ///
  /// In en, this message translates to:
  /// **'Enter model name, e.g., {example}'**
  String enterModelName(Object example);

  /// No description provided for @enterApiKey.
  ///
  /// In en, this message translates to:
  /// **'Enter API Key'**
  String get enterApiKey;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get testConnection;

  /// No description provided for @testingConnection.
  ///
  /// In en, this message translates to:
  /// **'Testing connection...'**
  String get testingConnection;

  /// No description provided for @connectionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection successful ✓'**
  String get connectionSuccess;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed, please check configuration'**
  String get connectionFailed;

  /// No description provided for @inUse.
  ///
  /// In en, this message translates to:
  /// **'In Use'**
  String get inUse;

  /// No description provided for @useThisModel.
  ///
  /// In en, this message translates to:
  /// **'Use This Model'**
  String get useThisModel;

  /// No description provided for @currentlyInUse.
  ///
  /// In en, this message translates to:
  /// **'Currently in use'**
  String get currentlyInUse;

  /// No description provided for @noModelsAdded.
  ///
  /// In en, this message translates to:
  /// **'No models added yet'**
  String get noModelsAdded;

  /// No description provided for @addVoiceModelHint.
  ///
  /// In en, this message translates to:
  /// **'Click the button below to add a speech recognition model'**
  String get addVoiceModelHint;

  /// No description provided for @addTextModelHint.
  ///
  /// In en, this message translates to:
  /// **'Click the button below to add a large language model'**
  String get addTextModelHint;

  /// No description provided for @enableTextEnhancement.
  ///
  /// In en, this message translates to:
  /// **'Enable Text Enhancement'**
  String get enableTextEnhancement;

  /// No description provided for @textEnhancementDescription.
  ///
  /// In en, this message translates to:
  /// **'Use AI to enhance and correct transcribed text.'**
  String get textEnhancementDescription;

  /// No description provided for @prompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get prompt;

  /// No description provided for @promptDescription.
  ///
  /// In en, this message translates to:
  /// **'Customize the AI behavior for text enhancement.'**
  String get promptDescription;

  /// No description provided for @defaultPrompt.
  ///
  /// In en, this message translates to:
  /// **'Default Prompt'**
  String get defaultPrompt;

  /// No description provided for @customPrompt.
  ///
  /// In en, this message translates to:
  /// **'Custom Prompt'**
  String get customPrompt;

  /// No description provided for @useCustomPrompt.
  ///
  /// In en, this message translates to:
  /// **'Use Custom Prompt'**
  String get useCustomPrompt;

  /// No description provided for @agentName.
  ///
  /// In en, this message translates to:
  /// **'Agent Name'**
  String get agentName;

  /// No description provided for @enterAgentName.
  ///
  /// In en, this message translates to:
  /// **'Enter agent name'**
  String get enterAgentName;

  /// No description provided for @current.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get current;

  /// No description provided for @test.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get test;

  /// No description provided for @currentSystemPrompt.
  ///
  /// In en, this message translates to:
  /// **'Current System Prompt'**
  String get currentSystemPrompt;

  /// No description provided for @customPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom Prompt'**
  String get customPromptTitle;

  /// No description provided for @enableCustomPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enable Custom Prompt'**
  String get enableCustomPrompt;

  /// No description provided for @customPromptEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled: Text enhancement will use custom prompt below'**
  String get customPromptEnabled;

  /// No description provided for @customPromptDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled: Text enhancement will use system default prompt'**
  String get customPromptDisabled;

  /// No description provided for @agentNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Use {agentName} as placeholder for agent name'**
  String agentNamePlaceholder(Object agentName);

  /// No description provided for @systemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System Prompt'**
  String get systemPrompt;

  /// No description provided for @saveAgentConfig.
  ///
  /// In en, this message translates to:
  /// **'Save Agent Configuration'**
  String get saveAgentConfig;

  /// No description provided for @restoreDefault.
  ///
  /// In en, this message translates to:
  /// **'Restore Default'**
  String get restoreDefault;

  /// No description provided for @testYourAgent.
  ///
  /// In en, this message translates to:
  /// **'Test Your Agent'**
  String get testYourAgent;

  /// No description provided for @testAgentDescription.
  ///
  /// In en, this message translates to:
  /// **'Test with current text model and agent prompt.'**
  String get testAgentDescription;

  /// No description provided for @testInput.
  ///
  /// In en, this message translates to:
  /// **'Test Input'**
  String get testInput;

  /// No description provided for @enterTestText.
  ///
  /// In en, this message translates to:
  /// **'Enter text to polish...'**
  String get enterTestText;

  /// No description provided for @running.
  ///
  /// In en, this message translates to:
  /// **'Running...'**
  String get running;

  /// No description provided for @runTest.
  ///
  /// In en, this message translates to:
  /// **'Run Test'**
  String get runTest;

  /// No description provided for @outputResult.
  ///
  /// In en, this message translates to:
  /// **'Output Result'**
  String get outputResult;

  /// No description provided for @outputWillAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Output will appear here'**
  String get outputWillAppearHere;

  /// No description provided for @historySection.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historySection;

  /// No description provided for @noHistory.
  ///
  /// In en, this message translates to:
  /// **'No transcription history'**
  String get noHistory;

  /// No description provided for @historyHint.
  ///
  /// In en, this message translates to:
  /// **'Use hotkey to start recording, transcription results will appear here'**
  String get historyHint;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistory;

  /// No description provided for @clearHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all history? This action cannot be undone.'**
  String get clearHistoryConfirm;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clearAll;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @deleteHistoryItem.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteHistoryItem;

  /// No description provided for @searchHistory.
  ///
  /// In en, this message translates to:
  /// **'Search history...'**
  String get searchHistory;

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutSection;

  /// No description provided for @appDescription.
  ///
  /// In en, this message translates to:
  /// **'Offhand is a voice input tool that supports multiple cloud LLMs and local Whisper models, turning speech into text instantly.'**
  String get appDescription;

  /// No description provided for @appSlogan.
  ///
  /// In en, this message translates to:
  /// **'Speak freely, write unbound.'**
  String get appSlogan;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get checkForUpdates;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get openSourceLicenses;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @networkSettings.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get networkSettings;

  /// No description provided for @networkSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure the network proxy mode for the application.'**
  String get networkSettingsDescription;

  /// No description provided for @systemSettings.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemSettings;

  /// No description provided for @systemSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure system-level settings such as startup behavior and network proxy.'**
  String get systemSettingsDescription;

  /// No description provided for @launchAtLogin.
  ///
  /// In en, this message translates to:
  /// **'Launch at Login'**
  String get launchAtLogin;

  /// No description provided for @launchAtLoginDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically start Offhand when you log in.'**
  String get launchAtLoginDescription;

  /// No description provided for @launchAtLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to enable launch at login'**
  String get launchAtLoginFailed;

  /// No description provided for @disableLaunchAtLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to disable launch at login'**
  String get disableLaunchAtLoginFailed;

  /// No description provided for @proxyConfig.
  ///
  /// In en, this message translates to:
  /// **'Proxy Configuration'**
  String get proxyConfig;

  /// No description provided for @useSystemProxy.
  ///
  /// In en, this message translates to:
  /// **'Use System Proxy'**
  String get useSystemProxy;

  /// No description provided for @systemProxySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Requests follow the system network proxy configuration.'**
  String get systemProxySubtitle;

  /// No description provided for @noProxy.
  ///
  /// In en, this message translates to:
  /// **'No Proxy'**
  String get noProxy;

  /// No description provided for @noProxySubtitle.
  ///
  /// In en, this message translates to:
  /// **'All requests connect directly without any proxy.'**
  String get noProxySubtitle;

  /// No description provided for @inputMonitoringRequired.
  ///
  /// In en, this message translates to:
  /// **'Input Monitoring Required'**
  String get inputMonitoringRequired;

  /// No description provided for @inputMonitoringDescription.
  ///
  /// In en, this message translates to:
  /// **'The Fn global hotkey requires enabling Offhand in \"System Settings > Privacy & Security > Input Monitoring\".'**
  String get inputMonitoringDescription;

  /// No description provided for @accessibilityRequired.
  ///
  /// In en, this message translates to:
  /// **'Accessibility Permission Required'**
  String get accessibilityRequired;

  /// No description provided for @accessibilityDescription.
  ///
  /// In en, this message translates to:
  /// **'To enable automatic text input, Offhand needs to be enabled in \"System Settings > Privacy & Security > Accessibility\".'**
  String get accessibilityDescription;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// No description provided for @pleaseConfigureSttModel.
  ///
  /// In en, this message translates to:
  /// **'Please configure a speech recognition model first'**
  String get pleaseConfigureSttModel;

  /// No description provided for @overlayStarting.
  ///
  /// In en, this message translates to:
  /// **'Mic starting'**
  String get overlayStarting;

  /// No description provided for @overlayRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get overlayRecording;

  /// No description provided for @overlayTranscribing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing'**
  String get overlayTranscribing;

  /// No description provided for @overlayEnhancing.
  ///
  /// In en, this message translates to:
  /// **'Enhancing'**
  String get overlayEnhancing;

  /// No description provided for @overlayTranscribeFailed.
  ///
  /// In en, this message translates to:
  /// **'Transcribe failed'**
  String get overlayTranscribeFailed;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the appearance theme for the application.'**
  String get themeDescription;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get themeMode;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @localModelIdleUnloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Local model idle unload'**
  String get localModelIdleUnloadTitle;

  /// No description provided for @localModelIdleUnloadDescription.
  ///
  /// In en, this message translates to:
  /// **'Unload local model after idle period to reduce memory usage'**
  String get localModelIdleUnloadDescription;

  /// No description provided for @localModelIdleUnloadTiming.
  ///
  /// In en, this message translates to:
  /// **'Release timing'**
  String get localModelIdleUnloadTiming;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{value} min'**
  String minutesShort(int value);

  /// No description provided for @userLabel.
  ///
  /// In en, this message translates to:
  /// **'speaker{id}'**
  String userLabel(String id);

  /// No description provided for @userIdLabel.
  ///
  /// In en, this message translates to:
  /// **'{user}'**
  String userIdLabel(String user);

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @totalTranscriptions.
  ///
  /// In en, this message translates to:
  /// **'Total Transcriptions'**
  String get totalTranscriptions;

  /// No description provided for @totalRecordingTime.
  ///
  /// In en, this message translates to:
  /// **'Total Recording Time'**
  String get totalRecordingTime;

  /// No description provided for @totalCharacters.
  ///
  /// In en, this message translates to:
  /// **'Total Characters'**
  String get totalCharacters;

  /// No description provided for @avgCharsPerSession.
  ///
  /// In en, this message translates to:
  /// **'Avg Chars/Session'**
  String get avgCharsPerSession;

  /// No description provided for @avgRecordingDuration.
  ///
  /// In en, this message translates to:
  /// **'Avg Duration'**
  String get avgRecordingDuration;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get thisMonth;

  /// No description provided for @transcriptionCount.
  ///
  /// In en, this message translates to:
  /// **'Transcriptions'**
  String get transcriptionCount;

  /// No description provided for @recordingTime.
  ///
  /// In en, this message translates to:
  /// **'Recording Time'**
  String get recordingTime;

  /// No description provided for @characters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get characters;

  /// No description provided for @usageTrend.
  ///
  /// In en, this message translates to:
  /// **'Usage Trend'**
  String get usageTrend;

  /// No description provided for @providerDistribution.
  ///
  /// In en, this message translates to:
  /// **'Provider Distribution'**
  String get providerDistribution;

  /// No description provided for @modelDistribution.
  ///
  /// In en, this message translates to:
  /// **'Model Distribution'**
  String get modelDistribution;

  /// No description provided for @currentStreak.
  ///
  /// In en, this message translates to:
  /// **'Current Streak'**
  String get currentStreak;

  /// No description provided for @streakDays.
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String streakDays(int count);

  /// No description provided for @lastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last Used'**
  String get lastUsed;

  /// No description provided for @mostActiveDay.
  ///
  /// In en, this message translates to:
  /// **'Most Active Day'**
  String get mostActiveDay;

  /// No description provided for @charsPerMinute.
  ///
  /// In en, this message translates to:
  /// **'Chars/Minute'**
  String get charsPerMinute;

  /// No description provided for @efficiency.
  ///
  /// In en, this message translates to:
  /// **'Efficiency'**
  String get efficiency;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @noDataYet.
  ///
  /// In en, this message translates to:
  /// **'No data yet. Start transcribing!'**
  String get noDataYet;

  /// No description provided for @day.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get day;

  /// No description provided for @week.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get week;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get month;

  /// No description provided for @timeAgo.
  ///
  /// In en, this message translates to:
  /// **'{time} ago'**
  String timeAgo(String time);

  /// No description provided for @minuteShort.
  ///
  /// In en, this message translates to:
  /// **'m'**
  String get minuteShort;

  /// No description provided for @hourShort.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get hourShort;

  /// No description provided for @secondShort.
  ///
  /// In en, this message translates to:
  /// **'s'**
  String get secondShort;

  /// No description provided for @sessions.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions'**
  String sessions(int count);

  /// No description provided for @enhanceTokenUsage.
  ///
  /// In en, this message translates to:
  /// **'Voice Input Tokens'**
  String get enhanceTokenUsage;

  /// No description provided for @enhanceInputTokens.
  ///
  /// In en, this message translates to:
  /// **'Input Tokens'**
  String get enhanceInputTokens;

  /// No description provided for @enhanceOutputTokens.
  ///
  /// In en, this message translates to:
  /// **'Output Tokens'**
  String get enhanceOutputTokens;

  /// No description provided for @enhanceTotalTokens.
  ///
  /// In en, this message translates to:
  /// **'Total Tokens'**
  String get enhanceTotalTokens;

  /// No description provided for @meetingTokenUsage.
  ///
  /// In en, this message translates to:
  /// **'Meeting Recording Tokens'**
  String get meetingTokenUsage;

  /// No description provided for @correctionTokenUsage.
  ///
  /// In en, this message translates to:
  /// **'Correction Tokens'**
  String get correctionTokenUsage;

  /// No description provided for @correctionRecallEfficiency.
  ///
  /// In en, this message translates to:
  /// **'Correction Recall Efficiency'**
  String get correctionRecallEfficiency;

  /// No description provided for @correctionTotalCalls.
  ///
  /// In en, this message translates to:
  /// **'Correction Calls'**
  String get correctionTotalCalls;

  /// No description provided for @correctionLlmCalls.
  ///
  /// In en, this message translates to:
  /// **'LLM Calls'**
  String get correctionLlmCalls;

  /// No description provided for @correctionLlmRate.
  ///
  /// In en, this message translates to:
  /// **'LLM Call Rate'**
  String get correctionLlmRate;

  /// No description provided for @correctionSelectedRate.
  ///
  /// In en, this message translates to:
  /// **'Candidate Selection Rate'**
  String get correctionSelectedRate;

  /// No description provided for @correctionChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Correction Details (Latest 20)'**
  String get correctionChangesTitle;

  /// No description provided for @correctionChangesExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get correctionChangesExpand;

  /// No description provided for @correctionChangesCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get correctionChangesCollapse;

  /// No description provided for @correctionChangesCollapsedHint.
  ///
  /// In en, this message translates to:
  /// **'Collapsed by default. Click Expand to view correction details.'**
  String get correctionChangesCollapsedHint;

  /// No description provided for @correctionChangesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No correction details yet. Start a recording and trigger correction to see entries here.'**
  String get correctionChangesEmpty;

  /// No description provided for @correctionChangedTerms.
  ///
  /// In en, this message translates to:
  /// **'Changed Terms'**
  String get correctionChangedTerms;

  /// No description provided for @correctionBeforeText.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get correctionBeforeText;

  /// No description provided for @correctionAfterText.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get correctionAfterText;

  /// No description provided for @correctionSourceRealtime.
  ///
  /// In en, this message translates to:
  /// **'Realtime'**
  String get correctionSourceRealtime;

  /// No description provided for @correctionSourceRetrospective.
  ///
  /// In en, this message translates to:
  /// **'Retrospective'**
  String get correctionSourceRetrospective;

  /// No description provided for @allTokenUsage.
  ///
  /// In en, this message translates to:
  /// **'All Tokens Summary'**
  String get allTokenUsage;

  /// No description provided for @retroTokenUsage.
  ///
  /// In en, this message translates to:
  /// **'Retrospective Tokens'**
  String get retroTokenUsage;

  /// No description provided for @retroSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Retrospective Correction'**
  String get retroSectionTitle;

  /// No description provided for @retroTotalCalls.
  ///
  /// In en, this message translates to:
  /// **'Retro Calls'**
  String get retroTotalCalls;

  /// No description provided for @retroLlmCalls.
  ///
  /// In en, this message translates to:
  /// **'LLM Calls'**
  String get retroLlmCalls;

  /// No description provided for @retroTextChangedCount.
  ///
  /// In en, this message translates to:
  /// **'Text Changed'**
  String get retroTextChangedCount;

  /// No description provided for @retroTextChangedRate.
  ///
  /// In en, this message translates to:
  /// **'Change Rate'**
  String get retroTextChangedRate;

  /// No description provided for @glossarySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Terminology Anchoring'**
  String get glossarySectionTitle;

  /// No description provided for @glossaryPins.
  ///
  /// In en, this message translates to:
  /// **'New Pins'**
  String get glossaryPins;

  /// No description provided for @glossaryStrongPromotions.
  ///
  /// In en, this message translates to:
  /// **'Strong Promotions'**
  String get glossaryStrongPromotions;

  /// No description provided for @glossaryOverrides.
  ///
  /// In en, this message translates to:
  /// **'Manual Overrides'**
  String get glossaryOverrides;

  /// No description provided for @glossaryInjections.
  ///
  /// In en, this message translates to:
  /// **'#R Injections'**
  String get glossaryInjections;

  /// No description provided for @showInDock.
  ///
  /// In en, this message translates to:
  /// **'Show in Dock'**
  String get showInDock;

  /// No description provided for @showInDockDescription.
  ///
  /// In en, this message translates to:
  /// **'Show the application icon in the macOS Dock.'**
  String get showInDockDescription;

  /// No description provided for @showInDockFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to change Dock visibility'**
  String get showInDockFailed;

  /// No description provided for @trayOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get trayOpen;

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get trayQuit;

  /// No description provided for @recordingPathCopied.
  ///
  /// In en, this message translates to:
  /// **'Recording path copied to clipboard'**
  String get recordingPathCopied;

  /// No description provided for @openFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open folder'**
  String get openFolderFailed;

  /// No description provided for @cleanupFailed.
  ///
  /// In en, this message translates to:
  /// **'Cleanup failed'**
  String get cleanupFailed;

  /// No description provided for @resetHotkeyDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset Default ({key})'**
  String resetHotkeyDefault(Object key);

  /// No description provided for @vadTitle.
  ///
  /// In en, this message translates to:
  /// **'Smart Silence Detection'**
  String get vadTitle;

  /// No description provided for @vadDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically detect silence during recording and stop recording after the set duration.'**
  String get vadDescription;

  /// No description provided for @vadEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable Smart Silence Detection'**
  String get vadEnable;

  /// No description provided for @vadSilenceThreshold.
  ///
  /// In en, this message translates to:
  /// **'Silence Threshold'**
  String get vadSilenceThreshold;

  /// No description provided for @vadSilenceDuration.
  ///
  /// In en, this message translates to:
  /// **'Silence Wait Duration'**
  String get vadSilenceDuration;

  /// No description provided for @sceneModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Scene Mode'**
  String get sceneModeTitle;

  /// No description provided for @sceneModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Select the current scene. AI will adjust text formatting style accordingly.'**
  String get sceneModeDescription;

  /// No description provided for @sceneModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Current Scene'**
  String get sceneModeLabel;

  /// No description provided for @promptTemplates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get promptTemplates;

  /// No description provided for @promptCreateTemplate.
  ///
  /// In en, this message translates to:
  /// **'Create Template'**
  String get promptCreateTemplate;

  /// No description provided for @promptTemplateName.
  ///
  /// In en, this message translates to:
  /// **'Template Name'**
  String get promptTemplateName;

  /// No description provided for @promptTemplateContent.
  ///
  /// In en, this message translates to:
  /// **'Template Content'**
  String get promptTemplateContent;

  /// No description provided for @promptTemplateSaved.
  ///
  /// In en, this message translates to:
  /// **'Template saved'**
  String get promptTemplateSaved;

  /// No description provided for @promptBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get promptBuiltin;

  /// No description provided for @promptBuiltinDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Default Prompt'**
  String get promptBuiltinDefaultName;

  /// No description provided for @promptBuiltinDefaultSummary.
  ///
  /// In en, this message translates to:
  /// **'General text cleanup and readability enhancement'**
  String get promptBuiltinDefaultSummary;

  /// No description provided for @promptBuiltinPunctuationName.
  ///
  /// In en, this message translates to:
  /// **'Punctuation Fix'**
  String get promptBuiltinPunctuationName;

  /// No description provided for @promptBuiltinPunctuationSummary.
  ///
  /// In en, this message translates to:
  /// **'Only fix sentence breaks and punctuation, keep original meaning'**
  String get promptBuiltinPunctuationSummary;

  /// No description provided for @promptBuiltinFormalName.
  ///
  /// In en, this message translates to:
  /// **'Formal Writing'**
  String get promptBuiltinFormalName;

  /// No description provided for @promptBuiltinFormalSummary.
  ///
  /// In en, this message translates to:
  /// **'Turn colloquial text into formal written style'**
  String get promptBuiltinFormalSummary;

  /// No description provided for @promptBuiltinColloquialName.
  ///
  /// In en, this message translates to:
  /// **'Colloquial Preserve'**
  String get promptBuiltinColloquialName;

  /// No description provided for @promptBuiltinColloquialSummary.
  ///
  /// In en, this message translates to:
  /// **'Light correction while preserving natural spoken style'**
  String get promptBuiltinColloquialSummary;

  /// No description provided for @promptBuiltinTranslateEnName.
  ///
  /// In en, this message translates to:
  /// **'Translate to English'**
  String get promptBuiltinTranslateEnName;

  /// No description provided for @promptBuiltinTranslateEnSummary.
  ///
  /// In en, this message translates to:
  /// **'Translate input into natural and fluent English'**
  String get promptBuiltinTranslateEnSummary;

  /// No description provided for @promptBuiltinMeetingName.
  ///
  /// In en, this message translates to:
  /// **'Meeting Minutes'**
  String get promptBuiltinMeetingName;

  /// No description provided for @promptBuiltinMeetingSummary.
  ///
  /// In en, this message translates to:
  /// **'Organize into structured meeting-note bullet points'**
  String get promptBuiltinMeetingSummary;

  /// No description provided for @promptSelectHint.
  ///
  /// In en, this message translates to:
  /// **'Select a template from the list to view details'**
  String get promptSelectHint;

  /// No description provided for @promptPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get promptPreview;

  /// No description provided for @dictionarySettings.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get dictionarySettings;

  /// No description provided for @dictionaryDescription.
  ///
  /// In en, this message translates to:
  /// **'Set up correction and preservation rules to help AI output professional terms and fixed expressions more accurately.'**
  String get dictionaryDescription;

  /// No description provided for @dictionaryAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Rule'**
  String get dictionaryAdd;

  /// No description provided for @dictionaryEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Rule'**
  String get dictionaryEdit;

  /// No description provided for @dictionaryOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original Word'**
  String get dictionaryOriginal;

  /// No description provided for @dictionaryOriginalHint.
  ///
  /// In en, this message translates to:
  /// **'Optional: specific source word to correct; leave empty to match by pinyin pattern'**
  String get dictionaryOriginalHint;

  /// No description provided for @dictionaryCorrected.
  ///
  /// In en, this message translates to:
  /// **'Correct To (optional)'**
  String get dictionaryCorrected;

  /// No description provided for @dictionaryCorrectedHint.
  ///
  /// In en, this message translates to:
  /// **'Fill to set correction target; leave empty to preserve matched words as-is'**
  String get dictionaryCorrectedHint;

  /// No description provided for @dictionaryCorrectedTip.
  ///
  /// In en, this message translates to:
  /// **'You can use only \'Pinyin Pattern + Correct To\' for homophone correction; leave \'Correct To\' empty for preserve rules'**
  String get dictionaryCorrectedTip;

  /// No description provided for @dictionaryCategory.
  ///
  /// In en, this message translates to:
  /// **'Category (optional)'**
  String get dictionaryCategory;

  /// No description provided for @dictionaryCategoryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Names, Terms, Brands'**
  String get dictionaryCategoryHint;

  /// No description provided for @dictionaryCategoryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get dictionaryCategoryAll;

  /// No description provided for @dictionaryTypeCorrection.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get dictionaryTypeCorrection;

  /// No description provided for @dictionaryTypePreserve.
  ///
  /// In en, this message translates to:
  /// **'Preserve'**
  String get dictionaryTypePreserve;

  /// No description provided for @dictionarySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search original/corrected/category/pinyin'**
  String get dictionarySearchHint;

  /// No description provided for @dictionaryCountTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get dictionaryCountTotal;

  /// No description provided for @dictionaryCountVisible.
  ///
  /// In en, this message translates to:
  /// **'Visible'**
  String get dictionaryCountVisible;

  /// No description provided for @dictionaryCountEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get dictionaryCountEnabled;

  /// No description provided for @dictionaryCountDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get dictionaryCountDisabled;

  /// No description provided for @dictionaryFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All Status'**
  String get dictionaryFilterAll;

  /// No description provided for @dictionaryFilterEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled Only'**
  String get dictionaryFilterEnabled;

  /// No description provided for @dictionaryFilterDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled Only'**
  String get dictionaryFilterDisabled;

  /// No description provided for @dictionaryRowsPerPage.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get dictionaryRowsPerPage;

  /// No description provided for @dictionaryPagePrev.
  ///
  /// In en, this message translates to:
  /// **'Previous Page'**
  String get dictionaryPagePrev;

  /// No description provided for @dictionaryPageNext.
  ///
  /// In en, this message translates to:
  /// **'Next Page'**
  String get dictionaryPageNext;

  /// No description provided for @dictionaryPageIndicator.
  ///
  /// In en, this message translates to:
  /// **'Page {current} / {total}'**
  String dictionaryPageIndicator(int current, int total);

  /// No description provided for @dictionaryPageSummary.
  ///
  /// In en, this message translates to:
  /// **'Showing {from} - {to} of {total}'**
  String dictionaryPageSummary(int from, int to, int total);

  /// No description provided for @dictionaryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Dictionary is empty'**
  String get dictionaryEmpty;

  /// No description provided for @dictionaryEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add correction or preservation rules to help AI output more accurately'**
  String get dictionaryEmptyHint;

  /// No description provided for @dictionaryExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get dictionaryExportCsv;

  /// No description provided for @dictionaryImportCsv.
  ///
  /// In en, this message translates to:
  /// **'Import CSV'**
  String get dictionaryImportCsv;

  /// No description provided for @dictionaryExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'CSV exported to: {path}'**
  String dictionaryExportSuccess(String path);

  /// No description provided for @dictionaryExportWithExampleSuccess.
  ///
  /// In en, this message translates to:
  /// **'CSV exported to: {path}\\nExample file: {examplePath}\\nTo modify this file, please import it using the example format.'**
  String dictionaryExportWithExampleSuccess(String path, String examplePath);

  /// No description provided for @dictionaryExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to export CSV'**
  String get dictionaryExportFailed;

  /// No description provided for @dictionaryImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Import completed: {imported} added, {skipped} skipped ({total} rows)'**
  String dictionaryImportSuccess(int imported, int skipped, int total);

  /// No description provided for @dictionaryImportInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid CSV format: missing pinyinPattern column'**
  String get dictionaryImportInvalidFormat;

  /// No description provided for @dictionaryImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import CSV'**
  String get dictionaryImportFailed;

  /// No description provided for @correctionEnabled.
  ///
  /// In en, this message translates to:
  /// **'Smart Correction'**
  String get correctionEnabled;

  /// No description provided for @correctionDescription.
  ///
  /// In en, this message translates to:
  /// **'Auto-correct homophones via pinyin matching, effective only when dictionary is non-empty'**
  String get correctionDescription;

  /// No description provided for @retrospectiveCorrectionEnabled.
  ///
  /// In en, this message translates to:
  /// **'Retrospective Review'**
  String get retrospectiveCorrectionEnabled;

  /// No description provided for @retrospectiveCorrectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Run one more paragraph-level correction when recording stops for better term consistency'**
  String get retrospectiveCorrectionDescription;

  /// No description provided for @textProcessing.
  ///
  /// In en, this message translates to:
  /// **'Text Processing'**
  String get textProcessing;

  /// No description provided for @textProcessingDescription.
  ///
  /// In en, this message translates to:
  /// **'Control correction and context enhancement after transcription.'**
  String get textProcessingDescription;

  /// No description provided for @historyContextEnabled.
  ///
  /// In en, this message translates to:
  /// **'History Context Enhancement'**
  String get historyContextEnabled;

  /// No description provided for @historyContextEnabledDescription.
  ///
  /// In en, this message translates to:
  /// **'Use recent related history to improve continuation and context coherence.'**
  String get historyContextEnabledDescription;

  /// No description provided for @contextTab.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get contextTab;

  /// No description provided for @contextImportMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Import Markdown'**
  String get contextImportMarkdown;

  /// No description provided for @contextSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search terms, aliases, sources'**
  String get contextSearchHint;

  /// No description provided for @contextEmpty.
  ///
  /// In en, this message translates to:
  /// **'No context'**
  String get contextEmpty;

  /// No description provided for @contextCanPromote.
  ///
  /// In en, this message translates to:
  /// **'Promotable'**
  String get contextCanPromote;

  /// No description provided for @contextPromoteToDictionary.
  ///
  /// In en, this message translates to:
  /// **'Promote'**
  String get contextPromoteToDictionary;

  /// No description provided for @contextTypeCorrectionHint.
  ///
  /// In en, this message translates to:
  /// **'Correction Hint'**
  String get contextTypeCorrectionHint;

  /// No description provided for @contextTypePreserveHint.
  ///
  /// In en, this message translates to:
  /// **'Preserve Hint'**
  String get contextTypePreserveHint;

  /// No description provided for @contextTypeReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get contextTypeReference;

  /// No description provided for @contextImportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Markdown'**
  String get contextImportDialogTitle;

  /// No description provided for @contextImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import Markdown'**
  String get contextImportFailed;

  /// No description provided for @contextImportPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Preview'**
  String get contextImportPreviewTitle;

  /// No description provided for @contextPromoteUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This entry cannot be promoted to the dictionary'**
  String get contextPromoteUnavailable;

  /// No description provided for @contextCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String contextCount(int count);

  /// No description provided for @contextSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String contextSelectedCount(int count);

  /// No description provided for @contextSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get contextSelectAll;

  /// No description provided for @contextDeleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete selected'**
  String get contextDeleteSelected;

  /// No description provided for @contextDeleteSelectedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} context items'**
  String contextDeleteSelectedSuccess(int count);

  /// No description provided for @contextContentEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty content'**
  String get contextContentEmpty;

  /// No description provided for @contextAliasLabel.
  ///
  /// In en, this message translates to:
  /// **'Alias / Misheard: {value}'**
  String contextAliasLabel(String value);

  /// No description provided for @contextSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source: {value}'**
  String contextSourceLabel(String value);

  /// No description provided for @contextDeleteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Deleted {term}'**
  String contextDeleteSuccess(String term);

  /// No description provided for @contextPromoteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Promoted {term} to dictionary'**
  String contextPromoteSuccess(String term);

  /// No description provided for @contextImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Import complete: context {contextCount}, correction {correctionCount}, preserve {preserveCount}, reference {referenceCount}'**
  String contextImportSuccess(
    int contextCount,
    int correctionCount,
    int preserveCount,
    int referenceCount,
  );

  /// No description provided for @contextImportPreviewSummary.
  ///
  /// In en, this message translates to:
  /// **'{fileCount} files, context {contextCount}, correction {correctionCount}, preserve {preserveCount}, reference {referenceCount}, skipped {skippedCount}'**
  String contextImportPreviewSummary(
    int fileCount,
    int contextCount,
    int correctionCount,
    int preserveCount,
    int referenceCount,
    int skippedCount,
  );

  /// No description provided for @contextImportPreviewItemSummary.
  ///
  /// In en, this message translates to:
  /// **'Context {contextCount}, correction {correctionCount}, preserve {preserveCount}, reference {referenceCount}, skipped {skippedCount}'**
  String contextImportPreviewItemSummary(
    int contextCount,
    int correctionCount,
    int preserveCount,
    int referenceCount,
    int skippedCount,
  );

  /// No description provided for @pinyinPreview.
  ///
  /// In en, this message translates to:
  /// **'Pinyin'**
  String get pinyinPreview;

  /// No description provided for @pinyinOverride.
  ///
  /// In en, this message translates to:
  /// **'Pinyin Pattern (optional)'**
  String get pinyinOverride;

  /// No description provided for @pinyinOverrideHint.
  ///
  /// In en, this message translates to:
  /// **'E.g. fan ruan; supports pinyin-only matching, space-separated syllables'**
  String get pinyinOverrideHint;

  /// No description provided for @pinyinReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to auto pinyin'**
  String get pinyinReset;

  /// No description provided for @meetingMinutes.
  ///
  /// In en, this message translates to:
  /// **'Meeting Minutes'**
  String get meetingMinutes;

  /// No description provided for @meetingNew.
  ///
  /// In en, this message translates to:
  /// **'New Meeting'**
  String get meetingNew;

  /// No description provided for @meetingRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get meetingRecording;

  /// No description provided for @meetingPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get meetingPaused;

  /// No description provided for @meetingCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get meetingCompleted;

  /// No description provided for @meetingEmpty.
  ///
  /// In en, this message translates to:
  /// **'No meeting records'**
  String get meetingEmpty;

  /// No description provided for @meetingEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Click the button above to start a new meeting recording'**
  String get meetingEmptyHint;

  /// No description provided for @meetingStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting meeting...'**
  String get meetingStarting;

  /// No description provided for @meetingTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Enter meeting title...'**
  String get meetingTitleHint;

  /// No description provided for @meetingPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get meetingPause;

  /// No description provided for @meetingResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get meetingResume;

  /// No description provided for @meetingStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get meetingStop;

  /// No description provided for @meetingListening.
  ///
  /// In en, this message translates to:
  /// **'Listening...'**
  String get meetingListening;

  /// No description provided for @meetingListeningHint.
  ///
  /// In en, this message translates to:
  /// **'Audio will be automatically segmented and transcribed'**
  String get meetingListeningHint;

  /// No description provided for @meetingTranscribing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing'**
  String get meetingTranscribing;

  /// No description provided for @meetingEnhancing.
  ///
  /// In en, this message translates to:
  /// **'Enhancing text'**
  String get meetingEnhancing;

  /// No description provided for @meetingWaitingProcess.
  ///
  /// In en, this message translates to:
  /// **'Waiting to process'**
  String get meetingWaitingProcess;

  /// No description provided for @meetingPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get meetingPending;

  /// No description provided for @meetingDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get meetingDone;

  /// No description provided for @meetingError.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get meetingError;

  /// No description provided for @meetingSegmentError.
  ///
  /// In en, this message translates to:
  /// **'Processing failed'**
  String get meetingSegmentError;

  /// No description provided for @meetingRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get meetingRetry;

  /// No description provided for @meetingNoContent.
  ///
  /// In en, this message translates to:
  /// **'No transcription content'**
  String get meetingNoContent;

  /// No description provided for @meetingProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing remaining segments...'**
  String get meetingProcessing;

  /// No description provided for @meetingSegments.
  ///
  /// In en, this message translates to:
  /// **'Segments'**
  String get meetingSegments;

  /// No description provided for @meetingLongPressToEnd.
  ///
  /// In en, this message translates to:
  /// **'Long press to end meeting'**
  String get meetingLongPressToEnd;

  /// No description provided for @meetingEndingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Ending meeting...'**
  String get meetingEndingConfirm;

  /// No description provided for @meetingRecordingSegment.
  ///
  /// In en, this message translates to:
  /// **'Recording...'**
  String get meetingRecordingSegment;

  /// No description provided for @meetingFullTranscription.
  ///
  /// In en, this message translates to:
  /// **'Meeting Minutes'**
  String get meetingFullTranscription;

  /// No description provided for @meetingStopConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'End Meeting'**
  String get meetingStopConfirmTitle;

  /// No description provided for @meetingStopConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to end the current meeting recording? All recorded segments will be processed first.'**
  String get meetingStopConfirm;

  /// No description provided for @meetingCancelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel Meeting'**
  String get meetingCancelConfirmTitle;

  /// No description provided for @meetingCancelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to cancel and discard the current meeting? This action cannot be undone.'**
  String get meetingCancelConfirm;

  /// No description provided for @meetingDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Meeting'**
  String get meetingDeleteConfirmTitle;

  /// No description provided for @meetingDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this meeting record? This action cannot be undone.'**
  String get meetingDeleteConfirm;

  /// No description provided for @meetingDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get meetingDate;

  /// No description provided for @meetingDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get meetingDuration;

  /// No description provided for @meetingTotalChars.
  ///
  /// In en, this message translates to:
  /// **'Total Characters'**
  String get meetingTotalChars;

  /// No description provided for @meetingTitle.
  ///
  /// In en, this message translates to:
  /// **'Meeting Title'**
  String get meetingTitle;

  /// No description provided for @meetingSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get meetingSaved;

  /// No description provided for @meetingSummary.
  ///
  /// In en, this message translates to:
  /// **'Meeting Summary'**
  String get meetingSummary;

  /// No description provided for @meetingContent.
  ///
  /// In en, this message translates to:
  /// **'Meeting Content'**
  String get meetingContent;

  /// No description provided for @meetingCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy All'**
  String get meetingCopyAll;

  /// No description provided for @meetingExportText.
  ///
  /// In en, this message translates to:
  /// **'Export as Text'**
  String get meetingExportText;

  /// No description provided for @meetingExportMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Export as Markdown'**
  String get meetingExportMarkdown;

  /// No description provided for @meetingExported.
  ///
  /// In en, this message translates to:
  /// **'Exported to clipboard'**
  String get meetingExported;

  /// No description provided for @meetingEmptyContent.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get meetingEmptyContent;

  /// No description provided for @meetingNotFound.
  ///
  /// In en, this message translates to:
  /// **'Meeting record not found'**
  String get meetingNotFound;

  /// No description provided for @meetingOverlayStarting.
  ///
  /// In en, this message translates to:
  /// **'Meeting starting'**
  String get meetingOverlayStarting;

  /// No description provided for @meetingOverlayRecording.
  ///
  /// In en, this message translates to:
  /// **'Meeting recording'**
  String get meetingOverlayRecording;

  /// No description provided for @meetingOverlayPaused.
  ///
  /// In en, this message translates to:
  /// **'Meeting paused'**
  String get meetingOverlayPaused;

  /// No description provided for @meetingOverlayProcessing.
  ///
  /// In en, this message translates to:
  /// **'Meeting processing'**
  String get meetingOverlayProcessing;

  /// No description provided for @meetingRecordingBanner.
  ///
  /// In en, this message translates to:
  /// **'Meeting recording in progress'**
  String get meetingRecordingBanner;

  /// No description provided for @meetingReturnToRecording.
  ///
  /// In en, this message translates to:
  /// **'Return to recording'**
  String get meetingReturnToRecording;

  /// No description provided for @meetingSegmentView.
  ///
  /// In en, this message translates to:
  /// **'Segments'**
  String get meetingSegmentView;

  /// No description provided for @meetingMergedNoteView.
  ///
  /// In en, this message translates to:
  /// **'Merged Notes'**
  String get meetingMergedNoteView;

  /// No description provided for @meetingLiveSummaryView.
  ///
  /// In en, this message translates to:
  /// **'Live Summary'**
  String get meetingLiveSummaryView;

  /// No description provided for @meetingLiveSummaryWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for enough content to generate summary...'**
  String get meetingLiveSummaryWaiting;

  /// No description provided for @meetingFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Finalizing'**
  String get meetingFinalizing;

  /// No description provided for @meetingSummaryUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating summary...'**
  String get meetingSummaryUpdating;

  /// No description provided for @meetingStreamingMerge.
  ///
  /// In en, this message translates to:
  /// **'Merging...'**
  String get meetingStreamingMerge;

  /// No description provided for @meetingDashboardToday.
  ///
  /// In en, this message translates to:
  /// **'TODAY\'S MEETINGS'**
  String get meetingDashboardToday;

  /// No description provided for @meetingDashboardRecents.
  ///
  /// In en, this message translates to:
  /// **'RECENTS'**
  String get meetingDashboardRecents;

  /// No description provided for @meetingDashboardLive.
  ///
  /// In en, this message translates to:
  /// **'LIVE MEETING'**
  String get meetingDashboardLive;

  /// No description provided for @meetingDashboardCancel.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get meetingDashboardCancel;

  /// No description provided for @meetingDashboardSaveNotes.
  ///
  /// In en, this message translates to:
  /// **'SAVE NOTES'**
  String get meetingDashboardSaveNotes;

  /// No description provided for @meetingDetailTab.
  ///
  /// In en, this message translates to:
  /// **'Meeting Details'**
  String get meetingDetailTab;

  /// No description provided for @meetingSummaryTab.
  ///
  /// In en, this message translates to:
  /// **'Meeting Summary'**
  String get meetingSummaryTab;

  /// No description provided for @meetingGeneratingSummary.
  ///
  /// In en, this message translates to:
  /// **'Generating meeting summary...'**
  String get meetingGeneratingSummary;

  /// No description provided for @meetingNoSummary.
  ///
  /// In en, this message translates to:
  /// **'No meeting summary yet'**
  String get meetingNoSummary;

  /// No description provided for @meetingRegenerateSummary.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get meetingRegenerateSummary;

  /// No description provided for @meetingUnifyRebuild.
  ///
  /// In en, this message translates to:
  /// **'Unify Rebuild'**
  String get meetingUnifyRebuild;

  /// No description provided for @meetingUnifyRebuildTitle.
  ///
  /// In en, this message translates to:
  /// **'Unify Historical Meetings'**
  String get meetingUnifyRebuildTitle;

  /// No description provided for @meetingUnifyRebuildConfirm.
  ///
  /// In en, this message translates to:
  /// **'Meeting minutes and summaries will be rebuilt using the same rule as segment view (prefer enhanced text). Continue?'**
  String get meetingUnifyRebuildConfirm;

  /// No description provided for @meetingUnifyRebuildRunning.
  ///
  /// In en, this message translates to:
  /// **'Unifying historical meetings...'**
  String get meetingUnifyRebuildRunning;

  /// No description provided for @meetingUnifyRebuildDone.
  ///
  /// In en, this message translates to:
  /// **'Unified rebuild complete: {count}'**
  String meetingUnifyRebuildDone(int count);

  /// No description provided for @meetingStatsSummary.
  ///
  /// In en, this message translates to:
  /// **'Total {totalCount} · Completed {completedCount}'**
  String meetingStatsSummary(int totalCount, int completedCount);

  /// No description provided for @meetingRecoverRecording.
  ///
  /// In en, this message translates to:
  /// **'Repair Recording'**
  String get meetingRecoverRecording;

  /// No description provided for @meetingRecoverRecordingSuccess.
  ///
  /// In en, this message translates to:
  /// **'Repaired {count} stuck recording session(s)'**
  String meetingRecoverRecordingSuccess(int count);

  /// No description provided for @meetingRecoverRecordingNone.
  ///
  /// In en, this message translates to:
  /// **'No stuck recording sessions found'**
  String get meetingRecoverRecordingNone;

  /// No description provided for @meetingSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search title/summary/content'**
  String get meetingSearchHint;

  /// No description provided for @meetingManageGroups.
  ///
  /// In en, this message translates to:
  /// **'Manage Groups'**
  String get meetingManageGroups;

  /// No description provided for @meetingMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More Actions'**
  String get meetingMoreActions;

  /// No description provided for @meetingMoveToGroup.
  ///
  /// In en, this message translates to:
  /// **'Move Group'**
  String get meetingMoveToGroup;

  /// No description provided for @meetingMoveToGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to Group'**
  String get meetingMoveToGroupTitle;

  /// No description provided for @meetingCreateGroupAndMove.
  ///
  /// In en, this message translates to:
  /// **'Create Group and Move'**
  String get meetingCreateGroupAndMove;

  /// No description provided for @meetingGroupManageTitle.
  ///
  /// In en, this message translates to:
  /// **'Group Management'**
  String get meetingGroupManageTitle;

  /// No description provided for @meetingGroupManageEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No custom groups yet. Click the button below to create one.'**
  String get meetingGroupManageEmptyHint;

  /// No description provided for @meetingGroupClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get meetingGroupClose;

  /// No description provided for @meetingGroupCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get meetingGroupCreate;

  /// No description provided for @meetingGroupCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get meetingGroupCreateTitle;

  /// No description provided for @meetingGroupNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter group name'**
  String get meetingGroupNameHint;

  /// No description provided for @meetingGroupRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename Group'**
  String get meetingGroupRenameTitle;

  /// No description provided for @meetingGroupRenameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter new group name'**
  String get meetingGroupRenameHint;

  /// No description provided for @meetingAllGroups.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get meetingAllGroups;

  /// No description provided for @meetingUngrouped.
  ///
  /// In en, this message translates to:
  /// **'Ungrouped'**
  String get meetingUngrouped;

  /// No description provided for @meetingStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start meeting: {error}'**
  String meetingStartFailed(String error);

  /// No description provided for @meetingStopFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to stop meeting: {error}'**
  String meetingStopFailed(String error);

  /// No description provided for @meetingMovedToFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Meeting has entered {status}'**
  String meetingMovedToFinalizing(String status);

  /// No description provided for @meetingStoppingPleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Stopping meeting, please wait…'**
  String get meetingStoppingPleaseWait;

  /// No description provided for @meetingStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping meeting…'**
  String get meetingStopping;

  /// No description provided for @addToDictionary.
  ///
  /// In en, this message translates to:
  /// **'Add to Dictionary'**
  String get addToDictionary;

  /// No description provided for @addedToDictionary.
  ///
  /// In en, this message translates to:
  /// **'Added to dictionary'**
  String get addedToDictionary;

  /// No description provided for @originalSttText.
  ///
  /// In en, this message translates to:
  /// **'Original speech-to-text'**
  String get originalSttText;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @vendorLocalModel.
  ///
  /// In en, this message translates to:
  /// **'Local Model'**
  String get vendorLocalModel;

  /// No description provided for @vendorCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get vendorCustom;

  /// No description provided for @localModelSttHint.
  ///
  /// In en, this message translates to:
  /// **'Local model calls whisper.cpp directly via FFI, just download the model file to use.'**
  String get localModelSttHint;

  /// No description provided for @localSttTinyDesc.
  ///
  /// In en, this message translates to:
  /// **'Tiny (~75MB) - Fastest, suitable for daily use'**
  String get localSttTinyDesc;

  /// No description provided for @localSttBaseDesc.
  ///
  /// In en, this message translates to:
  /// **'Base (~142MB) - Balanced speed and accuracy'**
  String get localSttBaseDesc;

  /// No description provided for @localSttSmallDesc.
  ///
  /// In en, this message translates to:
  /// **'Small (~466MB) - Higher accuracy'**
  String get localSttSmallDesc;

  /// No description provided for @localModelAiHint.
  ///
  /// In en, this message translates to:
  /// **'Local model calls llama.cpp directly via FFI. No internet required. Supports macOS and Windows.'**
  String get localModelAiHint;

  /// No description provided for @localAiQ5Desc.
  ///
  /// In en, this message translates to:
  /// **'Qwen2.5 0.5B Q5_K_M (~400MB) - Recommended, balanced quality and speed'**
  String get localAiQ5Desc;

  /// No description provided for @localAiQ4Desc.
  ///
  /// In en, this message translates to:
  /// **'Qwen2.5 0.5B Q4_K_M (~350MB) - Smaller and faster'**
  String get localAiQ4Desc;

  /// No description provided for @localAiQwen35_2BDesc.
  ///
  /// In en, this message translates to:
  /// **'Qwen3.5 2B Q4_K_M (~1.5GB) - Lightweight next-gen, notable quality boost'**
  String get localAiQwen35_2BDesc;

  /// No description provided for @localAiQwen35_4BDesc.
  ///
  /// In en, this message translates to:
  /// **'Qwen3.5 4B Q4_K_M (~2.7GB) - Recommended, balanced speed and quality'**
  String get localAiQwen35_4BDesc;

  /// No description provided for @localAiQwen35_9BDesc.
  ///
  /// In en, this message translates to:
  /// **'Qwen3.5 9B Q4_K_M (~5.5GB) - High quality, 16GB+ RAM recommended'**
  String get localAiQwen35_9BDesc;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloaded;

  /// No description provided for @customTemplateSummary.
  ///
  /// In en, this message translates to:
  /// **'Custom Template'**
  String get customTemplateSummary;

  /// No description provided for @openModelDir.
  ///
  /// In en, this message translates to:
  /// **'Open model file directory'**
  String get openModelDir;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
