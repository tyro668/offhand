import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_enhance_config.dart';
import '../../models/ai_model_entry.dart';
import '../../models/ai_vendor_preset.dart';
import '../../providers/settings_provider.dart';
import '../../services/ai_enhance_service.dart';
import '../../widgets/model_form_widgets.dart';
import '../../widgets/modern_ui.dart';

class AiModelPage extends StatefulWidget {
  const AiModelPage({super.key});

  @override
  State<AiModelPage> createState() => _AiModelPageState();
}

class _AiModelPageState extends State<AiModelPage> {
  ColorScheme get _cs => Theme.of(context).colorScheme;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEnableSection(settings, l10n),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildEnableSection(SettingsProvider settings, AppLocalizations l10n) {
    return ModernSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ModernSectionHeader(
            icon: Icons.auto_awesome_outlined,
            title: l10n.enableTextEnhancement,
            subtitle: '开启后会优先使用文本模型参与增强与整理流程。',
            compact: true,
            trailing: Switch.adaptive(
              value: settings.aiEnhanceEnabled,
              activeTrackColor: _cs.primary,
              onChanged: (v) => settings.setAiEnhanceEnabled(v),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              onPressed: () => _showAddDialog(context, settings, l10n),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 16),
                  const SizedBox(width: 8),
                  Text(l10n.addTextModel),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (settings.aiModelEntries.isEmpty)
            EmptyStateCard(
              icon: Icons.psychology_outlined,
              title: l10n.noModelsAdded,
              subtitle: l10n.addTextModelHint,
            )
          else
            ...settings.aiModelEntries.map(
              (entry) => _buildEntryCard(context, settings, entry, l10n),
            ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(
    BuildContext context,
    SettingsProvider settings,
    AiModelEntry entry,
    AppLocalizations l10n,
  ) {
    return ModelEntryCard(
      vendorName: localizedVendorName(entry.vendorName, l10n),
      modelName: entry.model,
      isActive: entry.enabled,
      l10n: l10n,
      onTest: () => _testConnection(context, entry, l10n),
      onEdit: () => _showEditDialog(context, settings, entry, l10n),
      onEnable: entry.enabled
          ? null
          : () => settings.enableAiModelEntry(entry.id),
      onDelete: () => _confirmDelete(context, settings, entry, l10n),
    );
  }

  Future<void> _testConnection(
    BuildContext context,
    AiModelEntry entry,
    AppLocalizations l10n,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.testingConnection),
        duration: const Duration(seconds: 20),
        behavior: SnackBarBehavior.floating,
      ),
    );

    var ok = false;
    var message = l10n.connectionFailed;

    try {
      final config = AiEnhanceConfig(
        baseUrl: entry.baseUrl,
        apiKey: entry.apiKey,
        model: entry.model,
        prompt: AiEnhanceConfig.defaultPrompt,
        agentName: AiEnhanceConfig.defaultAgentName,
      );
      final result = await AiEnhanceService(
        config,
      ).checkAvailabilityDetailed().timeout(const Duration(seconds: 25));
      ok = result.ok;
      message = ok
          ? l10n.connectionSuccess
          : '${l10n.connectionFailed}: ${result.message}';
    } catch (e) {
      ok = false;
      message = '${l10n.connectionFailed}: $e';
    }

    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ok ? Colors.green : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    SettingsProvider settings,
    AiModelEntry entry,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteModel),
        content: Text(l10n.confirmDeleteModel(entry.vendorName, entry.model)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              settings.removeAiModelEntry(entry.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(
    BuildContext context,
    SettingsProvider settings,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _AddModelDialog(
        presets: settings.aiPresets,
        onAdd: (entry) => settings.addAiModelEntry(entry),
        l10n: l10n,
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    SettingsProvider settings,
    AiModelEntry entry,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _EditModelDialog(
        entry: entry,
        presets: settings.aiPresets,
        onSave: (updated) => settings.updateAiModelEntry(updated),
        l10n: l10n,
      ),
    );
  }
}

class _AddModelDialog extends StatefulWidget {
  final List<AiVendorPreset> presets;
  final ValueChanged<AiModelEntry> onAdd;
  final AppLocalizations l10n;

  const _AddModelDialog({
    required this.presets,
    required this.onAdd,
    required this.l10n,
  });

  @override
  State<_AddModelDialog> createState() => _AddModelDialogState();
}

class _AddModelDialogState extends State<_AddModelDialog> {
  AiVendorPreset? _selectedVendor;
  AiModel? _selectedModel;
  bool _isCustom = false;
  final _apiKeyController = TextEditingController();
  final _customBaseUrlController = TextEditingController();
  final _customModelController = TextEditingController();

  List<AiVendorPreset> get _vendorOptions => widget.presets
      .where((preset) => preset.baseUrl.trim().isNotEmpty)
      .toList();

  @override
  void dispose() {
    _apiKeyController.dispose();
    _customBaseUrlController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return ModelDialogShell(
      icon: Icons.psychology_outlined,
      title: l10n.addTextModel,
      submitLabel: l10n.addModel,
      onClose: () => Navigator.pop(context),
      onSubmit: _canSubmit ? _submit : null,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FormFieldLabel(l10n.vendor, required: true),
            const SizedBox(height: 6),
            _buildVendorDropdown(l10n),
            const SizedBox(height: 12),
            FormFieldLabel(l10n.model, required: true),
            const SizedBox(height: 6),
            if (_isCustom)
              _buildTextField(
                controller: _customModelController,
                hintText: l10n.enterModelName('gpt-4o-mini'),
              )
            else
              _buildModelDropdown(l10n),
            const SizedBox(height: 12),
            if (_isCustom) ...[
              FormFieldLabel(l10n.endpointUrl, required: true),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _customBaseUrlController,
                hintText: 'https://api.openai.com/v1',
              ),
              const SizedBox(height: 12),
            ],
            FormFieldLabel(l10n.apiKey, required: true),
            const SizedBox(height: 6),
            _buildTextField(
              controller: _apiKeyController,
              hintText: l10n.enterApiKey,
              obscureText: true,
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSubmit {
    if (_apiKeyController.text.trim().isEmpty) return false;
    if (_isCustom) {
      return _customBaseUrlController.text.trim().isNotEmpty &&
          _customModelController.text.trim().isNotEmpty;
    }
    return _selectedVendor != null && _selectedModel != null;
  }

  void _submit() {
    final vendorName = _isCustom ? 'Custom' : _selectedVendor!.name;
    final baseUrl = _isCustom
        ? _customBaseUrlController.text.trim()
        : _selectedVendor!.baseUrl;
    final model = _isCustom
        ? _customModelController.text.trim()
        : _selectedModel!.id;

    widget.onAdd(
      AiModelEntry(
        id: const Uuid().v4(),
        vendorName: vendorName,
        baseUrl: baseUrl,
        model: model,
        apiKey: _apiKeyController.text.trim(),
      ),
    );
    Navigator.pop(context);
  }

  Widget _buildVendorDropdown(AppLocalizations l10n) {
    final items = <StyledDropdownItem<String>>[
      ..._vendorOptions.map(
        (preset) => StyledDropdownItem(
          value: preset.name,
          label: localizedVendorName(preset.name, l10n),
        ),
      ),
      StyledDropdownItem(value: '__custom__', label: l10n.custom),
    ];

    final currentValue = _isCustom ? '__custom__' : _selectedVendor?.name;

    return StyledDropdown<String>(
      value: currentValue,
      hintText: l10n.selectVendor,
      items: items,
      onChanged: (value) {
        setState(() {
          if (value == '__custom__') {
            _selectedVendor = null;
            _selectedModel = null;
            _isCustom = true;
          } else {
            _selectedVendor = _vendorOptions.firstWhere((p) => p.name == value);
            _selectedModel = null;
            _isCustom = false;
          }
        });
      },
    );
  }

  Widget _buildModelDropdown(AppLocalizations l10n) {
    final models = _selectedVendor?.models ?? [];
    return StyledDropdown<String>(
      value: _selectedModel?.id,
      hintText: l10n.selectModel,
      items: models
          .map((model) => StyledDropdownItem(value: model.id, label: model.id))
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedModel = models.firstWhere((model) => model.id == value);
        });
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
  }) {
    return StyledTextField(
      controller: controller,
      hintText: hintText,
      obscureText: obscureText,
      onChanged: (_) => setState(() {}),
    );
  }
}

class _EditModelDialog extends StatefulWidget {
  final AiModelEntry entry;
  final List<AiVendorPreset> presets;
  final ValueChanged<AiModelEntry> onSave;
  final AppLocalizations l10n;

  const _EditModelDialog({
    required this.entry,
    required this.presets,
    required this.onSave,
    required this.l10n,
  });

  @override
  State<_EditModelDialog> createState() => _EditModelDialogState();
}

class _EditModelDialogState extends State<_EditModelDialog> {
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _baseUrlController;
  late final String _vendorName;

  @override
  void initState() {
    super.initState();
    _vendorName = widget.entry.vendorName;
    _apiKeyController = TextEditingController(text: widget.entry.apiKey);
    _modelController = TextEditingController(text: widget.entry.model);
    _baseUrlController = TextEditingController(text: widget.entry.baseUrl);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  bool get _isCustom =>
      !widget.presets.any((preset) => preset.name == _vendorName);

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return ModelDialogShell(
      icon: Icons.edit_outlined,
      title: l10n.editTextModel,
      submitLabel: l10n.saveChanges,
      onClose: () => Navigator.pop(context),
      onSubmit: _canSubmit ? _submit : null,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FormFieldLabel(l10n.vendor),
            const SizedBox(height: 6),
            StyledReadOnlyField(text: localizedVendorName(_vendorName, l10n)),
            const SizedBox(height: 12),
            FormFieldLabel(l10n.model),
            const SizedBox(height: 6),
            _buildTextField(controller: _modelController, hintText: l10n.model),
            const SizedBox(height: 12),
            if (_isCustom) ...[
              FormFieldLabel(l10n.endpointUrl),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _baseUrlController,
                hintText: 'https://api.openai.com/v1',
              ),
              const SizedBox(height: 12),
            ],
            FormFieldLabel(l10n.apiKey),
            const SizedBox(height: 6),
            _buildTextField(
              controller: _apiKeyController,
              hintText: l10n.enterApiKey,
              obscureText: true,
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSubmit {
    if (_apiKeyController.text.trim().isEmpty) return false;
    if (_modelController.text.trim().isEmpty) return false;
    if (_isCustom && _baseUrlController.text.trim().isEmpty) return false;
    return true;
  }

  void _submit() {
    widget.onSave(
      AiModelEntry(
        id: widget.entry.id,
        vendorName: _vendorName,
        baseUrl: _isCustom
            ? _baseUrlController.text.trim()
            : widget.entry.baseUrl,
        model: _modelController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
      ),
    );
    Navigator.pop(context);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
  }) {
    return StyledTextField(
      controller: controller,
      hintText: hintText,
      obscureText: obscureText,
      onChanged: (_) => setState(() {}),
    );
  }
}
