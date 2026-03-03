/// 会议记录状态枚举
enum MeetingStatus {
  recording, // 录制中
  paused, // 已暂停
  finalizing, // 会议整理中（后台处理中）
  completed, // 已完成
}

/// 会议分段状态枚举
enum SegmentStatus {
  pending, // 等待处理
  transcribing, // 语音转文字中
  enhancing, // AI 文字整理中
  done, // 已完成
  error, // 处理失败
}

/// 会议记录主模型
class MeetingRecord {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  MeetingStatus status;
  String? summary;
  Duration totalDuration;

  /// 会议结束后合并的完整文稿
  String? fullTranscription;

  MeetingRecord({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.status = MeetingStatus.recording,
    this.summary,
    this.totalDuration = Duration.zero,
    this.fullTranscription,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.name,
    'summary': summary,
    'totalDuration': totalDuration.inMilliseconds,
    'fullTranscription': fullTranscription,
  };

  factory MeetingRecord.fromJson(Map<String, dynamic> json) => MeetingRecord(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    status: MeetingStatus.values.byName(json['status'] as String),
    summary: json['summary'] as String?,
    totalDuration: Duration(milliseconds: json['totalDuration'] as int),
    fullTranscription: json['fullTranscription'] as String?,
  );

  /// 格式化总时长为 HH:mm:ss
  String get formattedDuration {
    final h = totalDuration.inHours;
    final m = totalDuration.inMinutes.remainder(60);
    final s = totalDuration.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// 会议录音分段模型
class MeetingSegment {
  final String id;
  final String meetingId;
  final int segmentIndex;
  final DateTime startTime;
  final Duration duration;
  final String? audioFilePath;
  String? transcription;
  String? enhancedText;
  String? speakerId;
  double? speakerConfidence;
  SegmentStatus status;
  String? errorMessage;

  MeetingSegment({
    required this.id,
    required this.meetingId,
    required this.segmentIndex,
    required this.startTime,
    required this.duration,
    this.audioFilePath,
    this.transcription,
    this.enhancedText,
    this.speakerId,
    this.speakerConfidence,
    this.status = SegmentStatus.pending,
    this.errorMessage,
  });

  /// 获取显示文本（优先整理后文本，否则原始转写）
  String? get displayText => enhancedText ?? transcription;

  String? get detectedSpeakerId {
    final explicit = normalizeSpeakerId(speakerId);
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final fromDisplay = _extractSpeakerPrefix(displayText ?? '');
    return fromDisplay;
  }

  String get displayTextWithoutSpeaker {
    final text = (displayText ?? '').trim();
    return _stripSpeakerPrefix(text).trim();
  }

  String get displayTextWithSpeaker {
    final text = displayTextWithoutSpeaker;
    if (text.isEmpty) return '';
    final spk = detectedSpeakerId;
    if (spk == null || spk.isEmpty) return text;
    return '$spk: $text';
  }

  static String speakerLabel(
    String? speakerId, {
    required String Function(String index) userFormatter,
  }) {
    final normalized = normalizeSpeakerId(speakerId);
    if (normalized == null) return '';
    final indexMatch = RegExp(
      r'^(?:speaker|讲话人|s)\s*(\d+)$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (indexMatch == null) return normalized;
    final idx = indexMatch.group(1)!;
    return userFormatter(idx);
  }

  static String withSpeakerPrefix(String text, String speakerId) {
    final cleanText = _stripSpeakerPrefix(text).trim();
    if (cleanText.isEmpty) return cleanText;
    final cleanSpeaker = normalizeSpeakerId(speakerId) ?? '';
    if (cleanSpeaker.isEmpty) return cleanText;
    return '$cleanSpeaker: $cleanText';
  }

  static String? normalizeSpeakerId(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;

    final speakerMatch = RegExp(
      r'^(?:Speaker|讲话人|S)\s*(\d+)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (speakerMatch != null) {
      final idx = speakerMatch.group(1)!;
      return 'speaker$idx';
    }
    return value;
  }

  static String? _extractSpeakerPrefix(String text) {
    final match = RegExp(
      r'^\s*((?:Speaker|讲话人|S)\s*\d+)\s*[:：]\s*',
      caseSensitive: false,
    ).firstMatch(text);
    return normalizeSpeakerId(match?.group(1));
  }

  static String _stripSpeakerPrefix(String text) {
    return text.replaceFirst(
      RegExp(r'^\s*((?:Speaker|讲话人|S)\s*\d+)\s*[:：]\s*', caseSensitive: false),
      '',
    );
  }

  /// 格式化时间戳
  String get formattedTimestamp {
    final h = startTime.hour.toString().padLeft(2, '0');
    final m = startTime.minute.toString().padLeft(2, '0');
    final s = startTime.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// 格式化分段内偏移时间
  String get formattedOffset {
    final totalSeconds = duration.inSeconds;
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'meetingId': meetingId,
    'segmentIndex': segmentIndex,
    'startTime': startTime.toIso8601String(),
    'duration': duration.inMilliseconds,
    'audioFilePath': audioFilePath,
    'transcription': transcription,
    'enhancedText': enhancedText,
    'speakerId': speakerId,
    'speakerConfidence': speakerConfidence,
    'status': status.name,
    'errorMessage': errorMessage,
  };

  factory MeetingSegment.fromJson(Map<String, dynamic> json) => MeetingSegment(
    id: json['id'] as String,
    meetingId: json['meetingId'] as String,
    segmentIndex: json['segmentIndex'] as int,
    startTime: DateTime.parse(json['startTime'] as String),
    duration: Duration(milliseconds: json['duration'] as int),
    audioFilePath: json['audioFilePath'] as String?,
    transcription: json['transcription'] as String?,
    enhancedText: json['enhancedText'] as String?,
    speakerId: json['speakerId'] as String?,
    speakerConfidence: (json['speakerConfidence'] as num?)?.toDouble(),
    status: SegmentStatus.values.byName(json['status'] as String),
    errorMessage: json['errorMessage'] as String?,
  );
}
