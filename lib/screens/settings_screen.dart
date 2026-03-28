import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'pages/general_page.dart';
import 'pages/stt_page.dart';
import 'pages/ai_model_page.dart';
import 'pages/ai_enhance_hub_page.dart';
import 'pages/system_settings_page.dart';
import 'pages/about_page.dart';

/// 设置界面 — 自带左侧子导航栏，以弹窗形式展示。
class SettingsScreen extends StatefulWidget {
  final int initialIndex;

  const SettingsScreen({super.key, this.initialIndex = 0});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 5);
  }

  ColorScheme get _cs => Theme.of(context).colorScheme;

  List<_SettingsNavItem> _getItems(AppLocalizations l10n) => [
    _SettingsNavItem(icon: Icons.tune_outlined, label: l10n.generalSettings),
    _SettingsNavItem(icon: Icons.mic_outlined, label: l10n.voiceModelSettings),
    _SettingsNavItem(
      icon: Icons.psychology_outlined,
      label: l10n.textModelSettings,
    ),
    _SettingsNavItem(
      icon: Icons.auto_fix_high_outlined,
      label: l10n.aiEnhanceHub,
    ),
    _SettingsNavItem(icon: Icons.computer_outlined, label: l10n.systemSettings),
    _SettingsNavItem(icon: Icons.info_outline, label: l10n.about),
  ];

  Widget _buildPage() {
    return switch (_selectedIndex) {
      0 => const GeneralPage(),
      1 => const SttPage(),
      2 => const AiModelPage(),
      3 => const AiEnhanceHubPage(),
      4 => const SystemSettingsPage(),
      5 => const AboutPage(),
      _ => const SizedBox(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = _getItems(l10n);

    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            // 弹窗标题栏（含关闭按钮）
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: _cs.surface,
                border: Border(
                  bottom: BorderSide(
                    color: _cs.outlineVariant.withValues(alpha: 0.32),
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    l10n.settings,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),
            // 左侧导航 + 右侧内容
            Expanded(
              child: Row(
                children: [
                  // 设置子导航栏
                  Container(
                    width: 180,
                    decoration: BoxDecoration(
                      color: _cs.surfaceContainerLow,
                      border: Border(
                        right: BorderSide(
                          color: _cs.outlineVariant.withValues(alpha: 0.32),
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        ...List.generate(items.length, (i) {
                          final item = items[i];
                          final selected = _selectedIndex == i;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 1,
                            ),
                            child: Material(
                              color: selected
                                  ? _cs.secondaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => setState(() => _selectedIndex = i),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        item.icon,
                                        size: 16,
                                        color: selected
                                            ? _cs.onSurface
                                            : _cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          item.label,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: selected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: selected
                                                ? _cs.onSurface
                                                : _cs.onSurfaceVariant,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  // 设置内容区域
                  Expanded(
                    child: Container(
                      color: _cs.surfaceContainerLow,
                      child: _buildPage(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsNavItem {
  final IconData icon;
  final String label;
  const _SettingsNavItem({required this.icon, required this.label});
}
