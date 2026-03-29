import '../models/entity_alias.dart';

class EntityDictionaryBridge {
  const EntityDictionaryBridge();

  bool shouldBridge({
    required EntityAliasType aliasType,
    required String aliasText,
    required String canonicalName,
    required double confidence,
  }) {
    final alias = aliasText.trim();
    final canonical = canonicalName.trim();
    if (alias.isEmpty || canonical.isEmpty || alias == canonical) return false;
    if (confidence < 0.75) return false;

    switch (aliasType) {
      case EntityAliasType.misrecognition:
        return alias.length >= 2;
      case EntityAliasType.abbreviation:
        return alias.length >= 2;
      case EntityAliasType.alias:
        return !_isHighlyAmbiguousAlias(alias) && confidence >= 0.9;
      case EntityAliasType.fullName:
      case EntityAliasType.nickname:
        return false;
    }
  }

  bool _isHighlyAmbiguousAlias(String text) {
    final normalized = text.trim();
    if (normalized.length <= 2) return true;
    const ambiguous = {'老张', '小王', '老板', '客户', '系统'};
    return ambiguous.contains(normalized);
  }
}
