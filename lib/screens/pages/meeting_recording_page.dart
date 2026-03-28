import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/meeting.dart';
import '../../models/provider_config.dart';
import '../../models/ai_enhance_config.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/dictionary_entry_dialog.dart';
import '../../widgets/meeting_markdown_view.dart';

/// 录制页视图模式
enum _RecordingViewMode { segments, mergedNote, liveSummary }

/// 会议录制页面
class MeetingRecordingPage extends StatefulWidget {
  final SttProviderConfig sttConfig;
  final AiEnhanceConfig? aiConfig;
  final bool aiEnhanceEnabled;
  final String dictionarySuffix;

  const MeetingRecordingPage({
    super.key,
    required this.sttConfig,
    this.aiConfig,
    this.aiEnhanceEnabled = false,
    this.dictionarySuffix = '',
  });

  @override
  State<MeetingRecordingPage> createState() => _MeetingRecordingPageState();
}

class _MeetingRecordingPageState extends State<MeetingRecordingPage>
    with SingleTickerProviderStateMixin {
  ColorScheme get _cs => Theme.of(context).colorScheme;

  final TextEditingController _titleController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isStarting = false;
  bool _autoFollowScroll = true;
  bool _isProgrammaticScrolling = false;

  static const double _followBottomThreshold = 64;

  /// 当前视图模式（默认合并纪要）
  _RecordingViewMode _viewMode = _RecordingViewMode.mergedNote;
  bool _userExplicitlyToggledView = false;

  /// 用于检测标题是否被 provider（如提前生成）更新
  String _lastKnownTitle = '';

  // 长按结束相关
  Timer? _longPressTimer;
  double _longPressProgress = 0.0;
  bool _isLongPressing = false;
  bool _isStoppingMeeting = false;
  bool _hasEverObservedRecording = false;
  bool _handledExternalStop = false;
  static const _longPressDurationMs = 1500;
  static const _longPressStepMs = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoStart();
    });
  }

  Future<void> _autoStart() async {
    final provider = context.read<MeetingProvider>();
    if (provider.isRecording) {
      _titleController.text = provider.currentMeeting?.title ?? '';
      return;
    }

    setState(() => _isStarting = true);
    try {
      final settings = context.read<SettingsProvider>();
      final meeting = await provider
          .startMeeting(
            sttConfig: widget.sttConfig,
            aiConfig: widget.aiConfig,
            aiEnhanceEnabled: widget.aiEnhanceEnabled,
            dictionarySuffix: widget.dictionarySuffix,
            pinyinMatcher: settings.correctionEffective
                ? settings.pinyinMatcher
                : null,
            correctionPrompt: settings.correctionEffective
                ? settings.correctionPrompt
                : null,
            maxReferenceEntries: settings.correctionMaxReferenceEntries,
            minCandidateScore: settings.correctionMinCandidateScore,
          )
          .timeout(const Duration(seconds: 20));
      _titleController.text = meeting.title;
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.meetingStartFailed(e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _scrollController.dispose();
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_autoFollowScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final target = _scrollController.position.maxScrollExtent;
        if ((_scrollController.position.pixels - target).abs() < 1) {
          return;
        }
        _isProgrammaticScrolling = true;
        _scrollController
            .animateTo(
              target,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            )
            .whenComplete(() {
              _isProgrammaticScrolling = false;
            });
      }
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_scrollController.hasClients || _isProgrammaticScrolling) {
      return false;
    }

    final metrics = notification.metrics;
    final distanceToBottom = metrics.maxScrollExtent - metrics.pixels;
    final isNearBottom = distanceToBottom <= _followBottomThreshold;

    if (!isNearBottom && _autoFollowScroll) {
      setState(() => _autoFollowScroll = false);
    } else if (isNearBottom && !_autoFollowScroll) {
      setState(() => _autoFollowScroll = true);
    }

    return false;
  }

  // ── 长按结束会议 ──

  void _startLongPress() {
    if (_isStoppingMeeting) return;
    setState(() {
      _isLongPressing = true;
      _longPressProgress = 0.0;
    });
    _longPressTimer = Timer.periodic(
      const Duration(milliseconds: _longPressStepMs),
      (timer) {
        setState(() {
          _longPressProgress += _longPressStepMs / _longPressDurationMs;
        });
        if (_longPressProgress >= 1.0) {
          timer.cancel();
          _confirmEndMeeting();
        }
      },
    );
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    setState(() {
      _isLongPressing = false;
      _longPressProgress = 0.0;
    });
  }

  Future<void> _confirmEndMeeting() async {
    if (_isStoppingMeeting) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _isLongPressing = false;
      _longPressProgress = 0.0;
      _isStoppingMeeting = true;
    });

    final provider = context.read<MeetingProvider>();
    if (_titleController.text.isNotEmpty && provider.currentMeeting != null) {
      await provider.updateMeetingTitle(
        provider.currentMeeting!.id,
        _titleController.text,
      );
    }

    try {
      // 使用快速停止，立即返回
      await provider.stopMeetingFast();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.meetingMovedToFinalizing(l10n.meetingFinalizing)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      // 停止后自动返回会议列表，等待后台整理完成。
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.meetingStopFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isStoppingMeeting = false);
    }
  }

  Future<void> _addToDictionary(String selectedWord) async {
    if (selectedWord.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();

    final entry = await showDictionaryEntryDialog(
      context,
      initialOriginal: selectedWord,
    );
    if (entry == null || !mounted) return;

    await settings.addDictionaryEntry(entry);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${l10n.addedToDictionary}: ${entry.original}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleExternalStop() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.meetingMovedToFinalizing(l10n.meetingFinalizing)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<MeetingProvider>();
    final isStoppingUi = _isStoppingMeeting || provider.isStoppingMeeting;

    if (provider.isRecording) {
      _hasEverObservedRecording = true;
      _handledExternalStop = false;
    } else if (_hasEverObservedRecording &&
        !isStoppingUi &&
        !_handledExternalStop) {
      _handledExternalStop = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleExternalStop();
      });
    }

    final segments = provider.currentSegments;
    final hasMergedContent =
        provider.mergedNoteContent.trim().isNotEmpty ||
        provider.isStreamingMerge;
    final effectiveViewMode =
        !_userExplicitlyToggledView &&
            _viewMode == _RecordingViewMode.mergedNote &&
            !hasMergedContent
        ? _RecordingViewMode.segments
        : _viewMode;

    // 检测 provider 中的标题变更（如提前生成的标题），同步到输入框
    final providerTitle = provider.currentMeeting?.title ?? '';
    if (providerTitle.isNotEmpty &&
        providerTitle != _lastKnownTitle &&
        providerTitle != _titleController.text) {
      _titleController.text = providerTitle;
    }
    _lastKnownTitle = providerTitle;

    if (segments.isNotEmpty) {
      _scrollToBottom();
    }

    return PopScope(
      canPop: !isStoppingUi,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isStoppingUi && mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.meetingStoppingPleaseWait),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
            ),
          );
        }
        if (didPop) {
          // 保存标题（录音在后台继续）
          if (_titleController.text.isNotEmpty &&
              provider.currentMeeting != null) {
            provider.updateMeetingTitle(
              provider.currentMeeting!.id,
              _titleController.text,
            );
          }
        }
      },
      child: Scaffold(
        backgroundColor: _cs.surfaceContainer,
        appBar: AppBar(
          backgroundColor: _cs.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: isStoppingUi ? null : () => _handleBack(provider, l10n),
          ),
          title: SizedBox(
            width: 300,
            child: TextField(
              controller: _titleController,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _cs.onSurface,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: l10n.meetingTitleHint,
                hintStyle: TextStyle(
                  color: _cs.onSurfaceVariant,
                  fontWeight: FontWeight.normal,
                ),
              ),
              onSubmitted: (value) {
                if (provider.currentMeeting != null && value.isNotEmpty) {
                  provider.updateMeetingTitle(
                    provider.currentMeeting!.id,
                    value,
                  );
                }
              },
            ),
          ),
          actions: [
            // 暂停/继续 + 长按结束会议
            if (provider.isRecording)
              GestureDetector(
                onLongPressStart: isStoppingUi
                    ? null
                    : (_) => _startLongPress(),
                onLongPressEnd: isStoppingUi ? null : (_) => _cancelLongPress(),
                onLongPressCancel: isStoppingUi
                    ? null
                    : () => _cancelLongPress(),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 长按进度环
                    if (_isLongPressing)
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          value: _longPressProgress,
                          strokeWidth: 3,
                          color: Colors.red,
                          backgroundColor: Colors.red.withValues(alpha: 0.15),
                        ),
                      ),
                    IconButton(
                      onPressed: isStoppingUi
                          ? null
                          : () {
                              if (provider.isPaused) {
                                provider.resumeMeeting();
                              } else {
                                provider.pauseMeeting();
                              }
                            },
                      icon: Icon(
                        _isLongPressing
                            ? Icons.stop_rounded
                            : provider.isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: _isLongPressing
                            ? Colors.red
                            : provider.isPaused
                            ? _cs.primaryContainer
                            : _cs.surfaceContainerHigh,
                        foregroundColor: _isLongPressing
                            ? Colors.white
                            : _cs.onSurface,
                        minimumSize: const Size(38, 38),
                        padding: const EdgeInsets.all(6),
                      ),
                      tooltip: provider.isPaused
                          ? l10n.meetingResume
                          : l10n.meetingPause,
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 4),
            // 停止会议按钮
            if (provider.isRecording)
              IconButton(
                onPressed: isStoppingUi ? null : () => _confirmEndMeeting(),
                icon: isStoppingUi
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.stop_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(38, 38),
                  padding: const EdgeInsets.all(6),
                ),
                tooltip: isStoppingUi ? l10n.meetingStopping : l10n.meetingStop,
              ),
            const SizedBox(width: 6),
            // 录音时长
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 16,
                    color: _cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(provider.recordingDuration),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: _cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            // 视图切换栏
            _buildViewToggle(l10n, effectiveViewMode),
            // 内容区域
            Expanded(
              child: _isStarting
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(l10n.meetingStarting),
                        ],
                      ),
                    )
                  : effectiveViewMode == _RecordingViewMode.liveSummary
                  ? _buildLiveSummaryArea(provider, l10n)
                  : effectiveViewMode == _RecordingViewMode.mergedNote
                  ? _buildMergedNoteArea(provider, l10n)
                  : _buildTranscriptionArea(segments, provider, l10n),
            ),
          ],
        ),
      ), // end Scaffold / PopScope child
    ); // end PopScope
  }

  /// 分段视图 / 合并纪要 / 实时摘要 切换栏
  Widget _buildViewToggle(
    AppLocalizations l10n,
    _RecordingViewMode effectiveViewMode,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _cs.surface,
        border: Border(
          bottom: BorderSide(color: _cs.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      child: Row(
        children: [
          _buildToggleButton(
            label: l10n.meetingSegmentView,
            isSelected: effectiveViewMode == _RecordingViewMode.segments,
            onTap: () => setState(() {
              _userExplicitlyToggledView = true;
              _viewMode = _RecordingViewMode.segments;
            }),
          ),
          const SizedBox(width: 8),
          _buildToggleButton(
            label: l10n.meetingMergedNoteView,
            isSelected: effectiveViewMode == _RecordingViewMode.mergedNote,
            onTap: () => setState(() {
              _userExplicitlyToggledView = true;
              _viewMode = _RecordingViewMode.mergedNote;
            }),
          ),
          const SizedBox(width: 8),
          _buildToggleButton(
            label: l10n.meetingLiveSummaryView,
            isSelected: effectiveViewMode == _RecordingViewMode.liveSummary,
            onTap: () => setState(() {
              _userExplicitlyToggledView = true;
              _viewMode = _RecordingViewMode.liveSummary;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? _cs.primaryContainer.withValues(alpha: 0.7)
              : _cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? _cs.primary.withValues(alpha: 0.3)
                : _cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? _cs.onPrimaryContainer : _cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 合并纪要展示区域
  Widget _buildMergedNoteArea(MeetingProvider provider, AppLocalizations l10n) {
    final content = provider.mergedNoteContent;
    final isStreaming = provider.isStreamingMerge;

    if (content.isEmpty && !isStreaming) {
      return Center(
        child: Text(
          l10n.meetingNoContent,
          style: TextStyle(fontSize: 14, color: _cs.outline),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 流式加载指示器
            if (isStreaming)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _cs.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.meetingStreamingMerge,
                      style: TextStyle(fontSize: 13, color: _cs.primary),
                    ),
                  ],
                ),
              ),
            MeetingMarkdownView(
              markdown: content,
              selectable: true,
              density: MeetingMarkdownDensity.regular,
              onAddToDictionary: _addToDictionary,
            ),
          ],
        ),
      ),
    );
  }

  /// 实时摘要展示区域
  Widget _buildLiveSummaryArea(
    MeetingProvider provider,
    AppLocalizations l10n,
  ) {
    final summary = provider.incrementalSummary;
    final isUpdating = provider.isUpdatingIncrementalSummary;

    if (summary.isEmpty && !isUpdating) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 40, color: _cs.outline),
            const SizedBox(height: 12),
            Text(
              l10n.meetingLiveSummaryWaiting,
              style: TextStyle(fontSize: 14, color: _cs.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUpdating)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _cs.tertiary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.meetingSummaryUpdating,
                      style: TextStyle(fontSize: 13, color: _cs.tertiary),
                    ),
                  ],
                ),
              ),
            MeetingMarkdownView(
              markdown: summary,
              selectable: true,
              density: MeetingMarkdownDensity.regular,
              onAddToDictionary: _addToDictionary,
            ),
          ],
        ),
      ),
    );
  }

  /// 实时转写文字滚动区域
  Widget _buildTranscriptionArea(
    List<MeetingSegment> segments,
    MeetingProvider provider,
    AppLocalizations l10n,
  ) {
    if (segments.isEmpty && !provider.isPaused) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _WaveformIndicator(amplitudeStream: provider.amplitudeStream),
            const SizedBox(height: 16),
            Text(
              l10n.meetingListening,
              style: TextStyle(fontSize: 15, color: _cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.meetingListeningHint,
              style: TextStyle(fontSize: 13, color: _cs.outline),
            ),
          ],
        ),
      );
    }

    final showRecordingIndicator = provider.isRecording && !provider.isPaused;

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < segments.length; i++) ...[
              if (_shouldShowTimestamp(i)) _buildTimeAnchor(segments[i]),
              _buildSegmentText(segments[i], l10n),
            ],
            if (showRecordingIndicator) _buildRecordingIndicator(l10n),
          ],
        ),
      ),
    );
  }

  bool _shouldShowTimestamp(int index) {
    if (index == 0) return true;
    return index % 3 == 0;
  }

  Widget _buildTimeAnchor(MeetingSegment segment) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        segment.formattedTimestamp,
        style: TextStyle(
          fontSize: 11,
          color: _cs.outline,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildSegmentText(MeetingSegment segment, AppLocalizations l10n) {
    final isTranscribing =
        segment.status == SegmentStatus.pending ||
        segment.status == SegmentStatus.transcribing;
    final isEnhancing = segment.status == SegmentStatus.enhancing;

    if (segment.status == SegmentStatus.error) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                segment.errorMessage ?? l10n.meetingSegmentError,
                style: const TextStyle(fontSize: 13, color: Colors.red),
              ),
            ),
            InkWell(
              onTap: () =>
                  context.read<MeetingProvider>().retrySegment(segment),
              child: Text(
                l10n.meetingRetry,
                style: TextStyle(
                  fontSize: 13,
                  color: _cs.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isTranscribing || isEnhancing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: isEnhancing ? Colors.purple : _cs.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isEnhancing ? l10n.meetingEnhancing : l10n.meetingTranscribing,
              style: TextStyle(
                fontSize: 13,
                color: isEnhancing ? Colors.purple : _cs.primary,
              ),
            ),
          ],
        ),
      );
    }

    final text = (segment.displayText ?? '').trim();
    if (text.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          l10n.meetingNoContent,
          style: TextStyle(
            fontSize: 13,
            color: _cs.outline,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(
        text,
        style: TextStyle(fontSize: 14, color: _cs.onSurface, height: 1.6),
      ),
    );
  }

  /// 正在录音的脉冲指示器
  Widget _buildRecordingIndicator(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          _PulsingDot(color: Colors.red),
          const SizedBox(width: 8),
          Text(
            l10n.meetingRecordingSegment,
            style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _handleBack(MeetingProvider provider, AppLocalizations l10n) {
    if (_isStoppingMeeting || provider.isStoppingMeeting) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.meetingStoppingPleaseWait),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    // 保存标题
    if (_titleController.text.isNotEmpty && provider.currentMeeting != null) {
      provider.updateMeetingTitle(
        provider.currentMeeting!.id,
        _titleController.text,
      );
    }
    // 直接返回列表，录音在后台继续
    Navigator.pop(context);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}

/// 录音波形指示器
class _WaveformIndicator extends StatefulWidget {
  final Stream<double> amplitudeStream;

  const _WaveformIndicator({required this.amplitudeStream});

  @override
  State<_WaveformIndicator> createState() => _WaveformIndicatorState();
}

class _WaveformIndicatorState extends State<_WaveformIndicator> {
  double _level = 0.0;
  StreamSubscription<double>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.amplitudeStream.listen((level) {
      if (mounted) setState(() => _level = level);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(7, (i) {
        final height = 8.0 + (_level * 32.0 * (1.0 - (i - 3).abs() / 4.0));
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 4,
          height: height.clamp(4.0, 40.0),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.6 + _level * 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

/// 红点闪烁动画
class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color.withValues(
              alpha: 0.4 + _controller.value * 0.6,
            ),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
