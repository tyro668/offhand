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
    this.status = SegmentStatus.pending,
    this.errorMessage,
  });

  /// 获取显示文本（优先整理后文本，否则原始转写）
  String? get displayText => enhancedText ?? transcription;

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
    status: SegmentStatus.values.byName(json['status'] as String),
    errorMessage: json['errorMessage'] as String?,
  );
}
