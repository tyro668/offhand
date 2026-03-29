import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/entity_alias.dart';
import '../../models/entity_memory.dart';
import '../../providers/settings_provider.dart';
import '../../services/markdown_entity_import_service.dart';

class EntityPage extends StatefulWidget {
  final bool embedded;

  const EntityPage({super.key, this.embedded = false});

  @override
  State<EntityPage> createState() => _EntityPageState();
}

class _EntityPageState extends State<EntityPage> {
  static const MarkdownEntityImportService _importService =
      MarkdownEntityImportService();

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final search = _searchCtrl.text.trim().toLowerCase();
    final entities =
        settings.entityMemories
            .where((entity) {
              if (search.isEmpty) return true;
              if (entity.canonicalName.toLowerCase().contains(search))
                return true;
              return settings
                  .aliasesForEntity(entity.id)
                  .any(
                    (alias) => alias.aliasText.toLowerCase().contains(search),
                  );
            })
            .toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 960;
            final searchBox = SizedBox(
              width: compact ? double.infinity : 280,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索实体或别名',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            );
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _importMarkdown,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('导入 Markdown'),
                ),
                FilledButton.icon(
                  onPressed: _showAddEntityDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新增实体'),
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [searchBox, const SizedBox(height: 12), actions],
              );
            }
            return Row(children: [searchBox, const Spacer(), actions]);
          },
        ),
        const SizedBox(height: 16),
        Expanded(
          child: entities.isEmpty
              ? Center(
                  child: Text('暂无实体', style: TextStyle(color: cs.outline)),
                )
              : ListView.separated(
                  itemCount: entities.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final entity = entities[index];
                    final aliases = settings.aliasesForEntity(entity.id)
                      ..sort((a, b) => a.aliasText.compareTo(b.aliasText));
                    return _buildEntityCard(cs, settings, entity, aliases);
                  },
                ),
        ),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: content,
    );
  }

  Widget _buildEntityCard(
    ColorScheme cs,
    SettingsProvider settings,
    EntityMemory entity,
    List<EntityAlias> aliases,
  ) {
    final latestEvidence = settings.latestEvidenceForEntity(entity.id);
    final recentTime = latestEvidence?.createdAt ?? entity.updatedAt;
    final meta = <String>[
      _typeLabel(entity.type),
      '${aliases.length} 个别名',
      entity.enabled ? '已启用' : '已停用',
      '最近使用 ${_formatTime(recentTime)}',
      if (latestEvidence != null)
        '来源 ${_sourceLabel(latestEvidence.sourceType)}',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showEntityDetailDialog(entity.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entity.canonicalName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta.join(' · '),
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _showEntityDetailDialog(entity.id),
                  tooltip: '编辑实体',
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: () => settings.deleteEntity(entity.id),
                  tooltip: '删除实体',
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (aliases.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: aliases
                    .map((alias) {
                      return Chip(
                        label: Text(
                          '${alias.aliasText} · ${_aliasLabel(alias.aliasType)}',
                        ),
                        onDeleted: alias.aliasType == EntityAliasType.fullName
                            ? null
                            : () => settings.deleteEntityAlias(alias.id),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showAddEntityDialog() async {
    final nameCtrl = TextEditingController();
    final aliasCtrl = TextEditingController();
    EntityType type = EntityType.person;
    try {
      final created = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setState) {
              return AlertDialog(
                title: const Text('新增实体'),
                content: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: '标准名',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<EntityType>(
                        value: type,
                        decoration: const InputDecoration(
                          labelText: '类型',
                          border: OutlineInputBorder(),
                        ),
                        items: EntityType.values
                            .map((value) {
                              return DropdownMenuItem(
                                value: value,
                                child: Text(_typeLabel(value)),
                              );
                            })
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => type = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: aliasCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: '别名（逗号或换行分隔）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('保存'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (created != true || !mounted) return;
      final aliases = aliasCtrl.text
          .split(RegExp(r'[\n,，、]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      await context.read<SettingsProvider>().addManualEntity(
        canonicalName: nameCtrl.text.trim(),
        type: type,
        aliases: aliases,
      );
    } finally {
      nameCtrl.dispose();
      aliasCtrl.dispose();
    }
  }

  Future<void> _showEntityDetailDialog(String entityId) async {
    final settings = context.read<SettingsProvider>();
    EntityMemory? currentEntity;
    for (final item in settings.entityMemories) {
      if (item.id == entityId) {
        currentEntity = item;
        break;
      }
    }
    if (currentEntity == null) return;

    final canonicalCtrl = TextEditingController(
      text: currentEntity!.canonicalName,
    );
    final aliasCtrl = TextEditingController();
    var type = currentEntity!.type;
    var enabled = currentEntity!.enabled;
    var highConfidence = currentEntity!.confidence >= 0.95;
    EntityAliasType aliasType = EntityAliasType.alias;
    var aliases = settings.aliasesForEntity(entityId)
      ..sort((a, b) => a.aliasText.compareTo(b.aliasText));
    var evidences = settings.evidencesForEntity(entityId).take(5).toList();

    void refreshSnapshot() {
      final freshSettings = context.read<SettingsProvider>();
      EntityMemory? nextEntity;
      for (final item in freshSettings.entityMemories) {
        if (item.id == entityId) {
          nextEntity = item;
          break;
        }
      }
      currentEntity = nextEntity;
      aliases = freshSettings.aliasesForEntity(entityId)
        ..sort((a, b) => a.aliasText.compareTo(b.aliasText));
      evidences = freshSettings.evidencesForEntity(entityId).take(5).toList();
    }

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (ctx, setState) {
              if (currentEntity == null) {
                return AlertDialog(
                  title: const Text('实体不存在'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭'),
                    ),
                  ],
                );
              }

              return AlertDialog(
                title: const Text('实体详情'),
                content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: canonicalCtrl,
                          decoration: const InputDecoration(
                            labelText: '标准名',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<EntityType>(
                          value: type,
                          decoration: const InputDecoration(
                            labelText: '类型',
                            border: OutlineInputBorder(),
                          ),
                          items: EntityType.values
                              .map((value) {
                                return DropdownMenuItem(
                                  value: value,
                                  child: Text(_typeLabel(value)),
                                );
                              })
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => type = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: enabled,
                          title: const Text('启用实体'),
                          onChanged: (value) {
                            setState(() => enabled = value);
                          },
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: highConfidence,
                          title: const Text('高置信'),
                          onChanged: (value) {
                            setState(() => highConfidence = value);
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Alias',
                          style: Theme.of(ctx).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: aliases
                              .map((alias) {
                                return Chip(
                                  label: Text(
                                    '${alias.aliasText} · ${_aliasLabel(alias.aliasType)}',
                                  ),
                                  onDeleted:
                                      alias.aliasType ==
                                          EntityAliasType.fullName
                                      ? null
                                      : () async {
                                          await context
                                              .read<SettingsProvider>()
                                              .deleteEntityAlias(alias.id);
                                          refreshSnapshot();
                                          if (!ctx.mounted) return;
                                          setState(() {});
                                        },
                                );
                              })
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: aliasCtrl,
                                decoration: const InputDecoration(
                                  labelText: '新增别名',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 140,
                              child: DropdownButtonFormField<EntityAliasType>(
                                value: aliasType,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '类型',
                                  border: OutlineInputBorder(),
                                ),
                                items: EntityAliasType.values
                                    .map((value) {
                                      return DropdownMenuItem(
                                        value: value,
                                        child: Text(_aliasLabel(value)),
                                      );
                                    })
                                    .toList(growable: false),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => aliasType = value);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final alias = aliasCtrl.text.trim();
                              if (alias.isEmpty || currentEntity == null)
                                return;
                              final provider = context.read<SettingsProvider>();
                              await provider.addOrMergeEntityAlias(
                                entityId: currentEntity!.id,
                                aliasText: alias,
                                aliasType: aliasType,
                                source: 'manual',
                                confidence: highConfidence ? 0.95 : 0.85,
                              );
                              await provider.addEntityEvidence(
                                entityId: currentEntity!.id,
                                sourceType: 'manual',
                                sourceRef: 'entity-detail',
                                beforeText: alias,
                                afterText: canonicalCtrl.text.trim(),
                                extractedAlias: alias,
                              );
                              aliasCtrl.clear();
                              refreshSnapshot();
                              if (!ctx.mounted) return;
                              setState(() {});
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加别名'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Evidence',
                          style: Theme.of(ctx).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (evidences.isEmpty)
                          Text(
                            '暂无 evidence',
                            style: TextStyle(color: Theme.of(ctx).hintColor),
                          )
                        else
                          Column(
                            children: evidences
                                .map((evidence) {
                                  return Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Theme.of(
                                          ctx,
                                        ).colorScheme.outlineVariant,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_sourceLabel(evidence.sourceType)} · ${_formatTime(evidence.createdAt)}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'alias: ${evidence.extractedAlias}',
                                        ),
                                        if (evidence.afterText.isNotEmpty)
                                          Text(
                                            'canonical: ${evidence.afterText}',
                                          ),
                                      ],
                                    ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('关闭'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      if (currentEntity == null) return;
                      final updated = await context
                          .read<SettingsProvider>()
                          .updateEntityMemory(
                            entityId: currentEntity!.id,
                            canonicalName: canonicalCtrl.text.trim(),
                            type: type,
                            enabled: enabled,
                            confidence: highConfidence ? 0.98 : 0.85,
                          );
                      currentEntity = updated;
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                    },
                    child: const Text('保存'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      canonicalCtrl.dispose();
      aliasCtrl.dispose();
    }
  }

  Future<void> _importMarkdown() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['md', 'txt'],
      withData: true,
    );
    final file = (result == null || result.files.isEmpty)
        ? null
        : result.files.first;
    if (file == null) return;
    final content = file.bytes != null
        ? utf8.decode(file.bytes!, allowMalformed: true)
        : await File(file.path!).readAsString();
    final candidates = _importService.parse(content);
    final settings = context.read<SettingsProvider>();
    for (final candidate in candidates) {
      await settings.addManualEntity(
        canonicalName: candidate.canonicalName,
        type: candidate.type,
        aliases: candidate.aliases,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已导入 ${candidates.length} 个实体'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _typeLabel(EntityType type) {
    switch (type) {
      case EntityType.person:
        return '人名';
      case EntityType.company:
        return '公司';
      case EntityType.product:
        return '产品';
      case EntityType.project:
        return '项目';
      case EntityType.system:
        return '系统';
      case EntityType.custom:
        return '自定义';
    }
  }

  String _aliasLabel(EntityAliasType type) {
    switch (type) {
      case EntityAliasType.fullName:
        return '全名';
      case EntityAliasType.nickname:
        return '小名';
      case EntityAliasType.alias:
        return '别称';
      case EntityAliasType.misrecognition:
        return '误识别';
      case EntityAliasType.abbreviation:
        return '缩写';
    }
  }

  String _sourceLabel(String sourceType) {
    switch (sourceType) {
      case 'history-edit':
        return '历史修正';
      case 'manual':
        return '手动';
      case 'entity-memory':
        return '实体学习';
      default:
        return sourceType;
    }
  }

  String _formatTime(DateTime value) {
    return DateFormat('MM-dd HH:mm').format(value);
  }
}
