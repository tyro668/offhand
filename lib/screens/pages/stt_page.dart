import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../../models/provider_config.dart';
import '../../models/stt_model_entry.dart';
import '../../providers/settings_provider.dart';
import '../../services/sense_voice_ffi_service.dart';
import '../../services/stt_service.dart';
import '../../widgets/model_form_widgets.dart';
import '../../widgets/modern_ui.dart';

class SttPage extends StatefulWidget {
  const SttPage({super.key});

  @override
  State<SttPage> createState() => _SttPageState();
}

class _SttPageState extends State<SttPage> {
  static bool isLocalModelEntry(SttModelEntry entry) {
    return entry.vendorName == 'Local Model' ||
        entry.vendorName == '本地模型' ||
        entry.vendorName == '本地 whisper.cpp' ||
        entry.vendorName == 'whisper.cpp' ||
        entry.vendorName == 'SenseVoice' ||
        entry.vendorName == 'sensevoice' ||
        entry.vendorName == '本地 SenseVoice';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final entries = settings.sttModelEntries;
    final l10n = AppLocalizations.of(context)!;

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModernSurfaceCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ModernSectionHeader(
                    icon: Icons.settings_voice_outlined,
                    title: '语音模型列表',
                    subtitle: '新增、测试并切换当前可用的语音识别模型。',
                    compact: true,
                  ),
                  const SizedBox(height: 14),
                  ShadButton.outline(
                    onPressed: () => _showAddDialog(context, settings, l10n),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, size: 16),
                        const SizedBox(width: 8),
                        Text(l10n.addVoiceModel),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (entries.isEmpty)
                    _buildEmptyState(context, l10n)
                  else
                    ...entries.map(
                      (entry) =>
                          _buildEntryCard(context, settings, entry, l10n),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return EmptyStateCard(
      icon: Icons.mic_none_outlined,
      title: l10n.noModelsAdded,
      subtitle: l10n.addVoiceModelHint,
    );
  }

  Widget _buildEntryCard(
    BuildContext context,
    SettingsProvider settings,
    SttModelEntry entry,
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
          : () => settings.enableSttModelEntry(entry.id),
      onDelete: () => _confirmDelete(context, settings, entry, l10n),
    );
  }

  Future<void> _testConnection(
    BuildContext context,
    SttModelEntry entry,
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

    final config = SttProviderConfig(
      type: isLocalModelEntry(entry)
          ? SttProviderType.senseVoice
          : SttProviderType.cloud,
      name: entry.vendorName,
      baseUrl: entry.baseUrl,
      apiKey: entry.apiKey,
      model: entry.model,
    );

    bool ok = false;
    String message = l10n.connectionFailed;
    try {
      final stt = SttService(config);
      final result = await stt.checkAvailabilityDetailed().timeout(
        const Duration(seconds: 25),
      );
      ok = result.ok;
      message = ok
          ? l10n.connectionSuccess
          : '${l10n.connectionFailed}: ${result.message}';
    } catch (e) {
      ok = false;
      message = '${l10n.connectionFailed}: ${e.toString()}';
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
    SttModelEntry entry,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteModel),
        content: Text(l10n.deleteModelConfirm(entry.vendorName, entry.model)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              settings.removeSttModelEntry(entry.id);
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
        presets: settings.sttPresets,
        onAdd: (entry) => settings.addSttModelEntry(entry),
        l10n: l10n,
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    SettingsProvider settings,
    SttModelEntry entry,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _EditModelDialog(
        entry: entry,
        presets: settings.sttPresets,
        onSave: (updated) => settings.updateSttModelEntry(updated),
        l10n: l10n,
      ),
    );
  }
}

// ==================== 添加模型对话框 ====================
class _AddModelDialog extends StatefulWidget {
  final List<SttProviderConfig> presets;
  final ValueChanged<SttModelEntry> onAdd;
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
  ColorScheme get _cs => Theme.of(context).colorScheme;

  String _localizedSenseVoiceLocalDescription(SenseVoiceModel model) {
    return model.description;
  }

  SttProviderConfig? _selectedVendor;
  SttModel? _selectedModel;
  bool _isCustom = false;
  final _apiKeyController = TextEditingController();
  final _customBaseUrlController = TextEditingController();
  final _customModelController = TextEditingController();

  // 本地模型下载状态
  bool _downloading = false;
  double _downloadProgress = 0.0;
  String? _downloadError;
  String _downloadStatus = '';
  final Map<String, bool> _modelDownloaded = {};

  List<SttProviderConfig> get _vendorOptions {
    final local = <SttProviderConfig>[];
    final others = <SttProviderConfig>[];
    for (final preset in widget.presets) {
      if (preset.type == SttProviderType.senseVoice) {
        local.add(preset);
      } else {
        others.add(preset);
      }
    }
    return [...local, ...others];
  }

  bool get _isLocalModel => _selectedVendor?.type == SttProviderType.senseVoice;

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
      icon: Icons.mic_outlined,
      title: l10n.addVoiceModel,
      submitLabel: l10n.addModel,
      onClose: () => Navigator.pop(context),
      onSubmit: _canSubmit ? _submit : null,
      child: _isLocalModel
          ? _buildLocalModelDialogBody(l10n)
          : SingleChildScrollView(
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
                      hintText: l10n.enterModelName('whisper-1'),
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

  Widget _buildLocalModelDialogBody(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormFieldLabel(l10n.vendor, required: true),
        const SizedBox(height: 6),
        _buildVendorDropdown(l10n),
        const SizedBox(height: 12),
        FormFieldLabel(l10n.selectModel, required: true),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildSectionLabel('Sherpa-ONNX'),
              ...kSenseVoiceModels.map(
                (m) => _buildSenseVoiceModelDownloadTile(m),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSenseVoiceModelDownloadTile(SenseVoiceModel model) {
    final isSelected = _selectedModel?.id == model.fileName;
    final downloaded = _modelDownloaded[model.fileName];
    final isDownloading = _downloading && isSelected;

    return FutureBuilder<bool>(
      future: downloaded != null
          ? Future.value(downloaded)
          : SenseVoiceFfiService.isModelDownloaded(model.fileName),
      builder: (context, snapshot) {
        final exists = snapshot.data ?? downloaded ?? false;
        if (snapshot.hasData && _modelDownloaded[model.fileName] == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _modelDownloaded[model.fileName] = exists);
            }
          });
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? _cs.primary : _cs.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: exists
                ? () => setState(() {
                    _selectedModel = SttModel(
                      id: model.fileName,
                      description: _localizedSenseVoiceLocalDescription(model),
                    );
                  })
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: isSelected
                        ? _cs.primary
                        : exists
                        ? _cs.outline
                        : _cs.outline.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                model.fileName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _cs.onSurface,
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _cs.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '推荐',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _cs.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _localizedSenseVoiceLocalDescription(model),
                          style: TextStyle(
                            fontSize: 11,
                            color: _cs.onSurfaceVariant,
                          ),
                        ),
                        if (isDownloading) ...[
                          const SizedBox(height: 6),
                          if (_downloadStatus.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                _downloadStatus,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _downloadProgress,
                              minHeight: 4,
                              backgroundColor: _cs.surfaceContainerHighest,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: _cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (_downloadError != null && isSelected) ...[
                          const SizedBox(height: 4),
                          Text(
                            _downloadError!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (exists)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 14,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.l10n.downloaded,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isDownloading)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _cs.primary,
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => _downloadSenseVoiceModel(model),
                      icon: const Icon(Icons.download, size: 16),
                      label: Text(
                        widget.l10n.download,
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadSenseVoiceModel(SenseVoiceModel model) async {
    setState(() {
      _downloading = true;
      _downloadProgress = 0.0;
      _downloadError = null;
      _downloadStatus = '';
      _selectedModel = SttModel(
        id: model.fileName,
        description: _localizedSenseVoiceLocalDescription(model),
      );
    });

    try {
      await SenseVoiceFfiService.downloadModel(
        model,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress);
          }
        },
        onStatus: (message) {
          if (mounted) {
            setState(() => _downloadStatus = message);
          }
        },
      );
      if (mounted) {
        setState(() {
          _downloading = false;
          _modelDownloaded[model.fileName] = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadError = e.toString();
        });
      }
    }
  }

  bool get _canSubmit {
    if (_downloading) return false;
    if (_isLocalModel) {
      return _selectedModel != null &&
          (_modelDownloaded[_selectedModel!.id] == true);
    }
    if (_apiKeyController.text.trim().isEmpty) return false;
    if (_isCustom) {
      return _customBaseUrlController.text.trim().isNotEmpty &&
          _customModelController.text.trim().isNotEmpty;
    }
    return _selectedModel != null;
  }

  void _submit() {
    final String vendorName;
    final String baseUrl;
    final String model;

    if (_isLocalModel) {
      vendorName = _selectedVendor!.name;
      baseUrl = ''; // FFI 模式不需要路径
      model = _selectedModel!.id;
    } else if (_isCustom) {
      vendorName = 'Custom';
      baseUrl = _customBaseUrlController.text.trim();
      model = _customModelController.text.trim();
    } else {
      vendorName = _selectedVendor!.name;
      baseUrl = _selectedVendor!.baseUrl;
      model = _selectedModel!.id;
    }

    final entry = SttModelEntry(
      id: const Uuid().v4(),
      vendorName: vendorName,
      baseUrl: baseUrl,
      model: model,
      apiKey: _isLocalModel ? '' : _apiKeyController.text.trim(),
    );
    widget.onAdd(entry);
    Navigator.pop(context);
  }

  Widget _buildVendorDropdown(AppLocalizations l10n) {
    final items = <StyledDropdownItem<String>>[
      ..._vendorOptions.map(
        (p) => StyledDropdownItem(
          value: p.name,
          label: localizedVendorName(p.name, l10n),
        ),
      ),
      StyledDropdownItem(value: '__custom__', label: l10n.custom),
    ];

    String? currentValue;
    if (_isCustom) {
      currentValue = '__custom__';
    } else if (_selectedVendor != null) {
      currentValue = _selectedVendor!.name;
    }

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
    final models = _selectedVendor?.availableModels ?? [];
    return StyledDropdown<String>(
      value: _selectedModel?.id,
      hintText: l10n.selectModel,
      items: models
          .map((m) => StyledDropdownItem(value: m.id, label: m.id))
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedModel = models.firstWhere((m) => m.id == value);
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

// ==================== 编辑模型对话框 ====================
class _EditModelDialog extends StatefulWidget {
  final SttModelEntry entry;
  final List<SttProviderConfig> presets;
  final ValueChanged<SttModelEntry> onSave;
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
  ColorScheme get _cs => Theme.of(context).colorScheme;

  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.entry.apiKey);
    _baseUrlController = TextEditingController(text: widget.entry.baseUrl);
    _modelController = TextEditingController(text: widget.entry.model);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  bool get _isLocalModel => _SttPageState.isLocalModelEntry(widget.entry);

  bool get _isSenseVoiceModel => SttProviderConfig.isSenseVoiceModel(
    widget.entry.model.isNotEmpty
        ? widget.entry.model
        : _modelController.text.trim(),
  );

  bool get _isCustom =>
      !_isLocalModel &&
      !widget.presets.any((p) => p.name == widget.entry.vendorName);

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return ModelDialogShell(
      icon: Icons.edit_outlined,
      title: l10n.editVoiceModel,
      submitLabel: l10n.saveChanges,
      onClose: () => Navigator.pop(context),
      onSubmit: _submit,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FormFieldLabel(l10n.vendor),
            const SizedBox(height: 6),
            StyledReadOnlyField(
              text: localizedVendorName(widget.entry.vendorName, widget.l10n),
            ),
            const SizedBox(height: 12),
            if (_isLocalModel) ...[
              FormFieldLabel(l10n.model, required: true),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _modelController,
                      hintText: _isSenseVoiceModel
                          ? 'sense-voice-zh-en'
                          : 'sense-voice-zh-en',
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: l10n.openModelDir,
                    child: IconButton(
                      icon: Icon(
                        Icons.folder_open,
                        size: 20,
                        color: _cs.onSurfaceVariant,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      onPressed: () =>
                          _openModelFileLocation(_modelController.text.trim()),
                    ),
                  ),
                ],
              ),
            ] else ...[
              if (_isCustom) ...[
                FormFieldLabel(l10n.endpointUrl, required: true),
                const SizedBox(height: 6),
                _buildTextField(
                  controller: _baseUrlController,
                  hintText: 'https://api.example.com/v1',
                ),
                const SizedBox(height: 12),
              ],
              FormFieldLabel(l10n.model, required: true),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _modelController,
                hintText: l10n.enterModelName('whisper-1'),
              ),
              const SizedBox(height: 12),
              FormFieldLabel(l10n.apiKey, required: true),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _apiKeyController,
                hintText: l10n.enterApiKey,
                obscureText: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openModelFileLocation(String fileName) async {
    if (fileName.isEmpty) return;
    final dir = await SenseVoiceFfiService.defaultModelDir;
    if (Platform.isWindows) {
      await Process.run('explorer', [dir]);
    } else {
      await Process.run('open', [dir]);
    }
  }

  void _submit() {
    final updated = SttModelEntry(
      id: widget.entry.id,
      vendorName: widget.entry.vendorName,
      baseUrl: _isLocalModel || _isCustom
          ? _baseUrlController.text.trim()
          : widget.entry.baseUrl,
      model: _modelController.text.trim(),
      apiKey: _isLocalModel ? '' : _apiKeyController.text.trim(),
      enabled: widget.entry.enabled,
    );
    widget.onSave(updated);
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
    );
  }
}
