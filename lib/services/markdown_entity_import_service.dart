import '../models/entity_memory.dart';

class MarkdownEntityImportCandidate {
  final String canonicalName;
  final EntityType type;
  final List<String> aliases;

  const MarkdownEntityImportCandidate({
    required this.canonicalName,
    required this.type,
    required this.aliases,
  });
}

class MarkdownEntityImportService {
  const MarkdownEntityImportService();

  List<MarkdownEntityImportCandidate> parse(String markdown) {
    final seen = <String>{};
    final results = <MarkdownEntityImportCandidate>[];
    EntityType? sectionType;
    for (final rawLine in markdown.replaceAll('\r\n', '\n').split('\n')) {
      final kind = _classifyLine(rawLine);
      if (kind == _MarkdownLineKind.heading) {
        sectionType = _inferSectionType(rawLine.trim());
        continue;
      }
      if (kind == _MarkdownLineKind.empty || kind == _MarkdownLineKind.prose) {
        continue;
      }

      var line = rawLine.trim();
      if (line.isEmpty) continue;
      if (kind == _MarkdownLineKind.listItem) {
        line = line.replaceFirst(RegExp(r'^[>\-\*\d\.\s]+'), '').trim();
      }
      line = line.replaceAll('`', '').trim();
      if (line.isEmpty) continue;

      final candidate = _parseLine(line, forcedType: sectionType);
      if (candidate == null) continue;
      final key = candidate.canonicalName.toLowerCase();
      if (!seen.add(key)) continue;
      results.add(candidate);
    }
    return results;
  }

  _MarkdownLineKind _classifyLine(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return _MarkdownLineKind.empty;
    if (line.startsWith('#')) return _MarkdownLineKind.heading;
    if (RegExp(r'^(\-|\*|\d+\.)\s+').hasMatch(line)) {
      return _MarkdownLineKind.listItem;
    }
    if (_looksLikeStandaloneCandidate(line)) {
      return _MarkdownLineKind.plainCandidate;
    }
    return _MarkdownLineKind.prose;
  }

  MarkdownEntityImportCandidate? _parseLine(
    String line, {
    EntityType? forcedType,
  }) {
    final aliasMatch = RegExp(
      r'^(.+?)[（(](?:别名|alias)[:：]\s*([^)）]+)[)）]$',
      caseSensitive: false,
    ).firstMatch(line);
    if (aliasMatch != null) {
      final canonical = aliasMatch.group(1)!.trim();
      final aliases = aliasMatch
          .group(2)!
          .split(RegExp(r'[、,，/]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      if (_looksLikeEntity(canonical)) {
        return MarkdownEntityImportCandidate(
          canonicalName: canonical,
          type: forcedType ?? _inferType(canonical),
          aliases: aliases,
        );
      }
    }

    if (!_looksLikeEntity(line)) return null;
    return MarkdownEntityImportCandidate(
      canonicalName: line,
      type: forcedType ?? _inferType(line),
      aliases: const [],
    );
  }

  EntityType? _inferSectionType(String headingLine) {
    final line = headingLine.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    if (line.isEmpty) return null;
    if (RegExp(r'(参会|人员|成员|同学|嘉宾|老师)').hasMatch(line)) {
      return EntityType.person;
    }
    if (RegExp(r'(公司|客户|厂商|组织)').hasMatch(line)) {
      return EntityType.company;
    }
    if (RegExp(r'(产品)').hasMatch(line)) {
      return EntityType.product;
    }
    if (RegExp(r'(系统|平台)').hasMatch(line)) {
      return EntityType.system;
    }
    if (RegExp(r'(项目)').hasMatch(line)) {
      return EntityType.project;
    }
    return null;
  }

  bool _looksLikeEntity(String text) {
    final value = text.trim();
    if (value.length < 2 || value.length > 24) return false;
    if (value.contains(' ') && value.split(RegExp(r'\s+')).length > 3) {
      return false;
    }
    if (RegExp(r'^[\u4e00-\u9fff]{2,8}$').hasMatch(value)) return true;
    if (RegExp(r'^[A-Z][A-Za-z0-9\-_]{1,}$').hasMatch(value)) return true;
    if (RegExp(r'(公司|集团|科技|数据|系统|项目)$').hasMatch(value)) return true;
    return false;
  }

  bool _looksLikeStandaloneCandidate(String text) {
    final value = text.trim();
    if (value.isEmpty || value.length > 36) return false;
    if (RegExp(r'[。！？；;：:]').hasMatch(value)) return false;
    if (value.contains('，') || value.contains(',')) return false;
    if (RegExp(r'\s').hasMatch(value) &&
        value.split(RegExp(r'\s+')).length > 3) {
      return false;
    }
    if (RegExp(r'(讨论|继续|梳理|方案|会议纪要|说明|背景|需求)').hasMatch(value)) {
      return false;
    }
    return _looksLikeEntity(value);
  }

  EntityType _inferType(String canonical) {
    if (RegExp(r'(公司|集团|科技|数据)$').hasMatch(canonical)) {
      return EntityType.company;
    }
    if (RegExp(r'(系统)$').hasMatch(canonical)) {
      return EntityType.system;
    }
    if (RegExp(r'(项目)$').hasMatch(canonical)) {
      return EntityType.project;
    }
    if (RegExp(r'^[A-Z][A-Za-z0-9\-_]{1,}$').hasMatch(canonical)) {
      return EntityType.product;
    }
    if (RegExp(r'^[\u4e00-\u9fff]{2,4}$').hasMatch(canonical)) {
      return EntityType.person;
    }
    return EntityType.custom;
  }
}

enum _MarkdownLineKind { empty, heading, listItem, plainCandidate, prose }
