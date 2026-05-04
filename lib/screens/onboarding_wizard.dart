import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../models/ai_model_entry.dart';
import '../models/ai_vendor_preset.dart';
import '../models/provider_config.dart';
import '../models/stt_model_entry.dart';
import '../providers/settings_provider.dart';
import '../widgets/model_form_widgets.dart';

class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({super.key});

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  static const _customValue = '__custom__';

  final _uuid = const Uuid();
  final _hotkeyFocusNode = FocusNode();
  final _sttApiKeyController = TextEditingController();
  final _sttCustomBaseUrlController = TextEditingController();
  final _sttCustomModelController = TextEditingController();
  final _aiApiKeyController = TextEditingController();
  final _aiCustomBaseUrlController = TextEditingController();
  final _aiCustomModelController = TextEditingController();

  int _step = 0;
  bool _initialized = false;
  bool _listeningHotkey = false;
  bool _sttCustom = false;
  bool _aiCustom = false;
  bool _textEnhancementEnabled = false;
  SttProviderConfig? _selectedSttVendor;
  SttModel? _selectedSttModel;
  AiVendorPreset? _selectedAiVendor;
  AiModel? _selectedAiModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final settings = context.read<SettingsProvider>();
    _selectedSttVendor = _initialSttVendor(settings);
    _selectedSttModel = _initialSttModel(_selectedSttVendor);
    _selectedAiVendor = _initialAiVendor(settings);
    _selectedAiModel = _initialAiModel(_selectedAiVendor);
    _textEnhancementEnabled =
        settings.aiEnhanceEnabled || settings.activeAiModelEntry != null;
    _initialized = true;
  }

  @override
  void dispose() {
    _hotkeyFocusNode.dispose();
    _sttApiKeyController.dispose();
    _sttCustomBaseUrlController.dispose();
    _sttCustomModelController.dispose();
    _aiApiKeyController.dispose();
    _aiCustomBaseUrlController.dispose();
    _aiCustomModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: size.height * 0.86,
        ),
        child: Container(
          color: cs.surface,
          child: Column(
            children: [
              _buildHeader(l10n, cs),
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.7),
              ),
              _buildStepper(l10n, cs),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _buildStepContent(l10n, cs),
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.7),
              ),
              _buildFooter(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune_outlined, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.onboardingTitle,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper(AppLocalizations l10n, ColorScheme cs) {
    final steps = [
      (Icons.keyboard_command_key_outlined, l10n.onboardingShortcutStep),
      (Icons.settings_voice_outlined, l10n.onboardingVoiceStep),
      (Icons.auto_awesome_outlined, l10n.onboardingTextStep),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
      child: Row(
        children: List.generate(steps.length, (index) {
          final selected = index == _step;
          final completed = index < _step;
          final color = selected || completed
              ? cs.primary
              : cs.onSurfaceVariant;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == steps.length - 1 ? 0 : 10,
              ),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? cs.primary.withValues(alpha: 0.09)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: selected
                        ? cs.primary.withValues(alpha: 0.30)
                        : cs.outlineVariant.withValues(alpha: 0.34),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      completed ? Icons.check_circle_outline : steps[index].$1,
                      size: 17,
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        steps[index].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(AppLocalizations l10n, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: switch (_step) {
        0 => _buildHotkeyStep(l10n, cs),
        1 => _buildSttStep(l10n),
        2 => _buildAiStep(l10n),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _buildHotkeyStep(AppLocalizations l10n, ColorScheme cs) {
    final settings = context.watch<SettingsProvider>();
    return _StepPanel(
      icon: Icons.keyboard_command_key_outlined,
      title: l10n.onboardingShortcutTitle,
      children: [
        Row(
          children: [
            Expanded(
              child: _ActivationChoiceCard(
                icon: Icons.touch_app_outlined,
                title: l10n.tapToTalk,
                subtitle: l10n.tapToTalkSubtitle,
                selected: settings.activationMode == ActivationMode.tapToTalk,
                onTap: () =>
                    settings.setActivationMode(ActivationMode.tapToTalk),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActivationChoiceCard(
                icon: Icons.pan_tool_outlined,
                title: l10n.pushToTalk,
                subtitle: l10n.pushToTalkSubtitle,
                selected: settings.activationMode == ActivationMode.pushToTalk,
                onTap: () =>
                    settings.setActivationMode(ActivationMode.pushToTalk),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        KeyboardListener(
          focusNode: _hotkeyFocusNode,
          onKeyEvent: _listeningHotkey
              ? (event) {
                  if (event is! KeyDownEvent) return;
                  if (SettingsProvider.isModifierKey(event.logicalKey)) return;
                  settings.setHotkey(event.logicalKey);
                  setState(() => _listeningHotkey = false);
                }
              : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() => _listeningHotkey = true);
              _hotkeyFocusNode.requestFocus();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _listeningHotkey ? cs.primary : cs.outlineVariant,
                  width: _listeningHotkey ? 1.6 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _listeningHotkey ? '...' : settings.hotkeyLabel,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.onboardingCurrentHotkey,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _listeningHotkey
                              ? l10n.pressKeyToSet
                              : l10n.clickToChangeHotkey,
                          style: TextStyle(
                            fontSize: 13,
                            color: _listeningHotkey
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => settings.resetHotkey(),
                    icon: const Icon(Icons.restore, size: 16),
                    label: Text(
                      l10n.resetHotkeyDefault(
                        defaultTargetPlatform == TargetPlatform.windows
                            ? 'F2'
                            : 'Fn',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSttStep(AppLocalizations l10n) {
    final settings = context.watch<SettingsProvider>();
    final active = settings.activeSttModelEntry;
    return _StepPanel(
      icon: Icons.settings_voice_outlined,
      title: l10n.onboardingVoiceTitle,
      children: [
        _StatusStrip(
          icon: Icons.mic_outlined,
          label: l10n.onboardingCurrentVoiceModel,
          value: active == null
              ? l10n.onboardingNotConfigured
              : '${localizedVendorName(active.vendorName, l10n)} / ${active.model}',
          configured: active != null,
        ),
        const SizedBox(height: 14),
        _buildSttModelForm(settings, l10n),
      ],
    );
  }

  Widget _buildSttModelForm(SettingsProvider settings, AppLocalizations l10n) {
    final vendorItems = [
      ...settings.sttPresets.map(
        (preset) => StyledDropdownItem(
          value: preset.name,
          label: localizedVendorName(preset.name, l10n),
        ),
      ),
      StyledDropdownItem(value: _customValue, label: l10n.custom),
    ];
    final vendorValue = _sttCustom ? _customValue : _selectedSttVendor?.name;
    final isLocal =
        !_sttCustom && _selectedSttVendor?.type == SttProviderType.senseVoice;

    return _FormCard(
      children: [
        FormFieldLabel(l10n.vendor, required: true),
        const SizedBox(height: 6),
        StyledDropdown<String>(
          value: vendorValue,
          hintText: l10n.selectVendor,
          items: vendorItems,
          onChanged: (value) {
            setState(() {
              if (value == _customValue) {
                _sttCustom = true;
                _selectedSttVendor = null;
                _selectedSttModel = null;
              } else {
                _sttCustom = false;
                _selectedSttVendor = settings.sttPresets.firstWhere(
                  (preset) => preset.name == value,
                );
                _selectedSttModel = _initialSttModel(_selectedSttVendor);
              }
            });
          },
        ),
        const SizedBox(height: 14),
        if (_sttCustom) ...[
          FormFieldLabel(l10n.endpointUrl, required: true),
          const SizedBox(height: 6),
          StyledTextField(
            controller: _sttCustomBaseUrlController,
            hintText: 'https://api.example.com/v1',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          FormFieldLabel(l10n.model, required: true),
          const SizedBox(height: 6),
          StyledTextField(
            controller: _sttCustomModelController,
            hintText: l10n.enterModelName('gpt-4o-transcribe'),
            onChanged: (_) => setState(() {}),
          ),
        ] else ...[
          FormFieldLabel(l10n.model, required: true),
          const SizedBox(height: 6),
          StyledDropdown<String>(
            value: _selectedSttModel?.id,
            hintText: l10n.selectModel,
            items: (_selectedSttVendor?.availableModels ?? [])
                .map(
                  (model) =>
                      StyledDropdownItem(value: model.id, label: model.id),
                )
                .toList(),
            onChanged: (value) {
              final models = _selectedSttVendor?.availableModels ?? [];
              setState(() {
                _selectedSttModel = models.firstWhere(
                  (model) => model.id == value,
                );
              });
            },
          ),
        ],
        if (!isLocal) ...[
          const SizedBox(height: 14),
          FormFieldLabel(l10n.apiKey, required: true),
          const SizedBox(height: 6),
          StyledTextField(
            controller: _sttApiKeyController,
            hintText: l10n.enterApiKey,
            obscureText: true,
            onChanged: (_) => setState(() {}),
          ),
        ] else ...[
          const SizedBox(height: 12),
          _InlineNotice(
            icon: Icons.download_outlined,
            text: l10n.onboardingLocalModelNotice,
          ),
        ],
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _canSaveSttModel ? () => _saveSttModel(l10n) : null,
            icon: const Icon(Icons.check_circle_outline, size: 17),
            label: Text(l10n.onboardingSaveVoiceModel),
          ),
        ),
      ],
    );
  }

  Widget _buildAiStep(AppLocalizations l10n) {
    final settings = context.watch<SettingsProvider>();
    final active = settings.activeAiModelEntry;
    return _StepPanel(
      icon: Icons.auto_awesome_outlined,
      title: l10n.onboardingTextTitle,
      children: [
        _StatusStrip(
          icon: Icons.psychology_outlined,
          label: l10n.onboardingCurrentTextModel,
          value: active == null
              ? l10n.onboardingNotConfigured
              : '${localizedVendorName(active.vendorName, l10n)} / ${active.model}',
          configured: active != null,
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: _textEnhancementEnabled,
          title: Text(
            l10n.onboardingEnableTextEnhancement,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onChanged: (value) => setState(() => _textEnhancementEnabled = value),
        ),
        const SizedBox(height: 12),
        _buildAiModelForm(settings, l10n),
      ],
    );
  }

  Widget _buildAiModelForm(SettingsProvider settings, AppLocalizations l10n) {
    final vendorItems = [
      ...settings.aiPresets.map(
        (preset) => StyledDropdownItem(
          value: preset.name,
          label: localizedVendorName(preset.name, l10n),
        ),
      ),
      StyledDropdownItem(value: _customValue, label: l10n.custom),
    ];
    final vendorValue = _aiCustom ? _customValue : _selectedAiVendor?.name;

    return _FormCard(
      children: [
        FormFieldLabel(l10n.vendor, required: true),
        const SizedBox(height: 6),
        StyledDropdown<String>(
          value: vendorValue,
          hintText: l10n.selectVendor,
          items: vendorItems,
          onChanged: (value) {
            setState(() {
              if (value == _customValue) {
                _aiCustom = true;
                _selectedAiVendor = null;
                _selectedAiModel = null;
              } else {
                _aiCustom = false;
                _selectedAiVendor = settings.aiPresets.firstWhere(
                  (preset) => preset.name == value,
                );
                _selectedAiModel = _initialAiModel(_selectedAiVendor);
              }
            });
          },
        ),
        const SizedBox(height: 14),
        if (_aiCustom) ...[
          FormFieldLabel(l10n.endpointUrl, required: true),
          const SizedBox(height: 6),
          StyledTextField(
            controller: _aiCustomBaseUrlController,
            hintText: 'https://api.openai.com/v1',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          FormFieldLabel(l10n.model, required: true),
          const SizedBox(height: 6),
          StyledTextField(
            controller: _aiCustomModelController,
            hintText: l10n.enterModelName('gpt-5-mini'),
            onChanged: (_) => setState(() {}),
          ),
        ] else ...[
          FormFieldLabel(l10n.model, required: true),
          const SizedBox(height: 6),
          StyledDropdown<String>(
            value: _selectedAiModel?.id,
            hintText: l10n.selectModel,
            items: (_selectedAiVendor?.models ?? [])
                .map(
                  (model) =>
                      StyledDropdownItem(value: model.id, label: model.id),
                )
                .toList(),
            onChanged: (value) {
              final models = _selectedAiVendor?.models ?? [];
              setState(() {
                _selectedAiModel = models.firstWhere(
                  (model) => model.id == value,
                );
              });
            },
          ),
        ],
        const SizedBox(height: 14),
        FormFieldLabel(l10n.apiKey, required: true),
        const SizedBox(height: 6),
        StyledTextField(
          controller: _aiApiKeyController,
          hintText: l10n.enterApiKey,
          obscureText: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _canSaveAiModel ? () => _saveAiModel(l10n) : null,
            icon: const Icon(Icons.check_circle_outline, size: 17),
            label: Text(l10n.onboardingSaveTextModel),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      child: Row(
        children: [
          TextButton(
            onPressed: () => _finish(),
            child: Text(l10n.onboardingSkipForNow),
          ),
          const Spacer(),
          if (_step > 0)
            TextButton.icon(
              onPressed: () => setState(() => _step -= 1),
              icon: const Icon(Icons.arrow_back, size: 17),
              label: Text(l10n.onboardingBack),
            ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _step == 2
                ? () => _finish()
                : () => setState(() => _step += 1),
            icon: Icon(_step == 2 ? Icons.done : Icons.arrow_forward, size: 17),
            label: Text(
              _step == 2 ? l10n.onboardingComplete : l10n.onboardingNext,
            ),
          ),
        ],
      ),
    );
  }

  SttProviderConfig? _initialSttVendor(SettingsProvider settings) {
    final active = settings.activeSttModelEntry;
    if (active != null) {
      for (final preset in settings.sttPresets) {
        if (preset.name == active.vendorName) return preset;
      }
    }
    if (settings.sttPresets.isEmpty) return null;
    return settings.sttPresets.first;
  }

  SttModel? _initialSttModel(SttProviderConfig? vendor) {
    if (vendor == null || vendor.availableModels.isEmpty) return null;
    final defaultModel = vendor.model;
    for (final model in vendor.availableModels) {
      if (model.id == defaultModel) return model;
    }
    return vendor.availableModels.first;
  }

  AiVendorPreset? _initialAiVendor(SettingsProvider settings) {
    final active = settings.activeAiModelEntry;
    if (active != null) {
      for (final preset in settings.aiPresets) {
        if (preset.name == active.vendorName) return preset;
      }
    }
    if (settings.aiPresets.isEmpty) return null;
    return settings.aiPresets.first;
  }

  AiModel? _initialAiModel(AiVendorPreset? vendor) {
    if (vendor == null || vendor.models.isEmpty) return null;
    for (final model in vendor.models) {
      if (model.id == vendor.defaultModelId) return model;
    }
    return vendor.models.first;
  }

  bool get _canSaveSttModel {
    if (_sttCustom) {
      return _sttCustomBaseUrlController.text.trim().isNotEmpty &&
          _sttCustomModelController.text.trim().isNotEmpty &&
          _sttApiKeyController.text.trim().isNotEmpty;
    }
    final isLocal = _selectedSttVendor?.type == SttProviderType.senseVoice;
    if (_selectedSttVendor == null || _selectedSttModel == null) return false;
    if (isLocal) return true;
    return _sttApiKeyController.text.trim().isNotEmpty;
  }

  bool get _canSaveAiModel {
    if (_aiApiKeyController.text.trim().isEmpty) return false;
    if (_aiCustom) {
      return _aiCustomBaseUrlController.text.trim().isNotEmpty &&
          _aiCustomModelController.text.trim().isNotEmpty;
    }
    return _selectedAiVendor != null && _selectedAiModel != null;
  }

  Future<void> _saveSttModel(AppLocalizations l10n) async {
    if (!_canSaveSttModel) return;
    final settings = context.read<SettingsProvider>();
    final id = _uuid.v4();
    final isLocal =
        !_sttCustom && _selectedSttVendor?.type == SttProviderType.senseVoice;
    final entry = SttModelEntry(
      id: id,
      vendorName: _sttCustom ? 'Custom' : _selectedSttVendor!.name,
      baseUrl: isLocal
          ? ''
          : (_sttCustom
                ? _sttCustomBaseUrlController.text.trim()
                : _selectedSttVendor!.baseUrl),
      model: _sttCustom
          ? _sttCustomModelController.text.trim()
          : _selectedSttModel!.id,
      apiKey: isLocal ? '' : _sttApiKeyController.text.trim(),
    );
    await settings.addSttModelEntry(entry);
    await settings.enableSttModelEntry(id);
    _showSaved(l10n);
  }

  Future<void> _saveAiModel(AppLocalizations l10n) async {
    if (!_canSaveAiModel) return;
    final settings = context.read<SettingsProvider>();
    final id = _uuid.v4();
    final entry = AiModelEntry(
      id: id,
      vendorName: _aiCustom ? 'Custom' : _selectedAiVendor!.name,
      baseUrl: _aiCustom
          ? _aiCustomBaseUrlController.text.trim()
          : _selectedAiVendor!.baseUrl,
      model: _aiCustom
          ? _aiCustomModelController.text.trim()
          : _selectedAiModel!.id,
      apiKey: _aiApiKeyController.text.trim(),
    );
    await settings.addAiModelEntry(entry);
    await settings.enableAiModelEntry(id);
    await settings.setAiEnhanceEnabled(_textEnhancementEnabled);
    _showSaved(l10n);
  }

  Future<void> _finish() async {
    final settings = context.read<SettingsProvider>();
    if (settings.activeAiModelEntry != null) {
      await settings.setAiEnhanceEnabled(_textEnhancementEnabled);
    }
    await settings.setOnboardingCompleted(true);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _showSaved(AppLocalizations l10n) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.onboardingModelSaved),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _StepPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _StepPanel({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: cs.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

class _ActivationChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ActivationChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.08)
              : cs.surfaceContainerHighest.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, size: 18, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final List<Widget> children;

  const _FormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool configured;

  const _StatusStrip({
    required this.icon,
    required this.label,
    required this.value,
    required this.configured,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: configured
            ? cs.primary.withValues(alpha: 0.08)
            : cs.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: configured
              ? cs.primary.withValues(alpha: 0.20)
              : cs.error.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: configured ? cs.primary : cs.error),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: configured ? cs.primary : cs.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InlineNotice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: cs.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: cs.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
