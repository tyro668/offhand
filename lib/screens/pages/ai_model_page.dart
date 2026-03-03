import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../../models/ai_enhance_config.dart';
import '../../models/ai_model_entry.dart';
import '../../models/ai_vendor_preset.dart';
import '../../providers/settings_provider.dart';
import '../../services/ai_enhance_service.dart';
import '../../services/local_llm_service.dart';
import '../../widgets/model_form_widgets.dart';

class AiModelPage extends StatefulWidget {
  const AiModelPage({super.key});

  @override
  State<AiModelPage> createState() => _AiModelPageState();
}

class _AiModelPageState extends State<AiModelPage> {
  ColorScheme get _cs => Theme.of(context).colorScheme;

  static bool isLocalAiModelEntry(AiModelEntry entry) {
    return entry.vendorName == 'Local Model' || entry.vendorName == '本地模型';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final entries = settings.aiModelEntries;
    final l10n = AppLocalizations.of(context)!;

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEnableSection(settings, l10n),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAddDialog(context, settings, l10n),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.addTextModel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _cs.onSurface,
                  side: BorderSide(color: _cs.outline),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              _buildEmptyState(context, l10n)
            else
              ...entries.map(
                (entry) => _buildEntryCard(context, settings, entry, l10n),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildEnableSection(SettingsProvider settings, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Text(
            l10n.enableTextEnhancement,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _cs.onSurface,
            ),
          ),
          const Spacer(),
          Switch.adaptive(
            value: settings.aiEnhanceEnabled,
            activeTrackColor: _cs.primary,
            onChanged: (v) => settings.setAiEnhanceEnabled(v),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return EmptyStateCard(
      icon: Icons.psychology_outlined,
      title: l10n.noModelsAdded,
      subtitle: l10n.addTextModelHint,
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

    bool ok = false;
    String message = l10n.connectionFailed;

    try {
      if (isLocalAiModelEntry(entry)) {
        // 本地模型：检查模型文件和 llama-server 是否就绪
        final result = await LocalLlmService.checkAvailability(entry.model);
        ok = result.ok;
        message = ok
            ? l10n.connectionSuccess
            : '${l10n.connectionFailed}: ${result.message}';
      } else {
        debugPrint('测试连接 - URL: ${entry.baseUrl}');
        debugPrint('测试连接 - Model: ${entry.model}');
        debugPrint('测试连接 - API Key长度: ${entry.apiKey.length}');

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
        debugPrint('测试连接结果: $message');
      }
    } catch (e, stackTrace) {
      ok = false;
      message = '${l10n.connectionFailed}: ${e.toString()}';
      debugPrint('测试连接异常: $e');
      debugPrint('堆栈: $stackTrace');
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

// ==================== 添加模型对话框 ====================
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
  ColorScheme get _cs => Theme.of(context).colorScheme;

  String _localizedAiLocalDescription(LocalLlmModel model) {
    final l10n = widget.l10n;
    switch (model.fileName) {
      case 'qwen2.5-0.5b-instruct-q5_k_m.gguf':
        return l10n.localAiQ5Desc;
      case 'qwen2.5-0.5b-instruct-q4_k_m.gguf':
        return l10n.localAiQ4Desc;
      case 'Qwen3.5-2B-Q4_K_M.gguf':
        return l10n.localAiQwen35_2BDesc;
      case 'Qwen3.5-4B-Q4_K_M.gguf':
        return l10n.localAiQwen35_4BDesc;
      case 'Qwen3.5-9B-Q4_K_M.gguf':
        return l10n.localAiQwen35_9BDesc;
      default:
        return model.description;
    }
  }

  AiVendorPreset? _selectedVendor;
  AiModel? _selectedModel;
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
  Set<String> _recommendedModelFileNames = const {};
  String? _recommendationSummary;

  List<AiVendorPreset> get _vendorOptions {
    final local = <AiVendorPreset>[];
    final others = <AiVendorPreset>[];
    for (final preset in widget.presets) {
      if (preset.isLocal) {
        local.add(preset);
      } else {
        others.add(preset);
      }
    }
    return [...local, ...others];
  }

  bool get _isLocalModel => _selectedVendor?.isLocal == true;

  @override
  void initState() {
    super.initState();
    _loadRecommendation();
  }

  Future<void> _loadRecommendation() async {
    try {
      final recommendation =
          await LocalLlmService.recommendModelsForCurrentMachine();
      if (!mounted) return;
      setState(() {
        _recommendedModelFileNames = recommendation.recommendedModelFileNames;
        _recommendationSummary = recommendation.summary;
      });
    } catch (_) {}
  }

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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _isLocalModel
                    ? _buildLocalModelDialogBody(l10n)
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDialogHeader(l10n),
                            const SizedBox(height: 14),
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
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _cs.onSurface,
                    foregroundColor: _cs.onPrimary,
                    disabledBackgroundColor: _cs.outline,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    l10n.addModel,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogHeader(AppLocalizations l10n) {
    return Row(
      children: [
        Text(
          l10n.addTextModel,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _cs.onSurface,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildLocalModelDialogBody(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDialogHeader(l10n),
        const SizedBox(height: 14),
        FormFieldLabel(l10n.vendor, required: true),
        const SizedBox(height: 6),
        _buildVendorDropdown(l10n),
        const SizedBox(height: 12),
        FormFieldLabel(l10n.selectModel, required: true),
        if (_recommendationSummary != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: _cs.secondaryContainer,
            ),
            child: Row(
              children: [
                Icon(Icons.memory, size: 14, color: _cs.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _recommendationSummary!,
                    style: TextStyle(
                      fontSize: 11,
                      color: _cs.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              ...kLocalLlmModels.map((m) => _buildModelDownloadTile(m)),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelDownloadTile(LocalLlmModel model) {
    final isSelected = _selectedModel?.id == model.fileName;
    final downloaded = _modelDownloaded[model.fileName];
    final isDownloading = _downloading && isSelected;
    final isRecommended = _recommendedModelFileNames.contains(model.fileName);
    final isTopRecommended = model.fileName == 'Qwen3.5-4B-Q4_K_M.gguf';

    return FutureBuilder<bool>(
      future: downloaded != null
          ? Future.value(downloaded)
          : LocalLlmService.isModelDownloaded(model.fileName),
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
                    _selectedModel = AiModel(
                      id: model.fileName,
                      description: _localizedAiLocalDescription(model),
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
                            if (isTopRecommended)
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
                                  '最推荐',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: _cs.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else if (isRecommended)
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
                          _localizedAiLocalDescription(model),
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
                      onPressed: () => _downloadModel(model),
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

  Future<void> _downloadModel(LocalLlmModel model) async {
    setState(() {
      _downloading = true;
      _downloadProgress = 0.0;
      _downloadError = null;
      _downloadStatus = '';
      _selectedModel = AiModel(
        id: model.fileName,
        description: _localizedAiLocalDescription(model),
      );
    });
    try {
      await LocalLlmService.downloadModel(
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
      baseUrl = '';
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

    final entry = AiModelEntry(
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
    final models = _selectedVendor?.models ?? [];
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
  ColorScheme get _cs => Theme.of(context).colorScheme;

  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _baseUrlController;
  late String _vendorName;

  bool get _isLocalModel => _AiModelPageState.isLocalAiModelEntry(widget.entry);

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
      !_isLocalModel && !widget.presets.any((p) => p.name == _vendorName);

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.editTextModel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                FormFieldLabel(l10n.vendor),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      localizedVendorName(_vendorName, l10n),
                      style: TextStyle(
                        fontSize: 14,
                        color: _cs.onSurfaceVariant,
                      ),
                    ),
                  ),
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
                          hintText: 'qwen2.5-0.5b-instruct-q5_k_m.gguf',
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
                          onPressed: () => _openModelFileLocation(
                            _modelController.text.trim(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  FormFieldLabel(l10n.model),
                  const SizedBox(height: 6),
                  _buildTextField(
                    controller: _modelController,
                    hintText: l10n.model,
                  ),
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

                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cs.primary,
                      foregroundColor: _cs.onPrimary,
                      disabledBackgroundColor: _cs.outline,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      l10n.saveChanges,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openModelFileLocation(String fileName) async {
    if (fileName.isEmpty) return;
    final dir = await LocalLlmService.defaultModelDir;
    if (Platform.isWindows) {
      await Process.run('explorer', [dir]);
    } else {
      await Process.run('open', [dir]);
    }
  }

  bool get _canSubmit {
    if (_isLocalModel) {
      return _modelController.text.trim().isNotEmpty;
    }
    if (_apiKeyController.text.trim().isEmpty) return false;
    if (_modelController.text.trim().isEmpty) return false;
    if (_isCustom && _baseUrlController.text.trim().isEmpty) return false;
    return true;
  }

  void _submit() {
    final updated = AiModelEntry(
      id: widget.entry.id,
      vendorName: _vendorName,
      baseUrl: _isLocalModel
          ? ''
          : _isCustom
          ? _baseUrlController.text.trim()
          : widget.entry.baseUrl,
      model: _modelController.text.trim(),
      apiKey: _isLocalModel ? '' : _apiKeyController.text.trim(),
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
      onChanged: (_) => setState(() {}),
    );
  }
}
