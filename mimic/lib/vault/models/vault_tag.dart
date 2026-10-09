// lib/vault/models/vault_tag.dart

/// Helper and presets for Smart Vault File Locator tags.
class VaultTags {
  /// Default recommended tag presets for one-tap categorization.
  static const List<String> presets = [
    '#ID',
    '#Receipt',
    '#Work',
    '#Important',
    '#Family',
    '#Finance',
    '#Personal',
    '#Favorite',
  ];

  /// Normalizes a tag string: removes extra whitespace and ensures leading '#'.
  static String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final withoutHash = trimmed.replaceFirst(RegExp(r'^#+'), '').trim();
    if (withoutHash.isEmpty) return '';
    return '#${withoutHash.replaceAll(RegExp(r'\s+'), '_')}';
  }

  /// Parses a comma-separated or whitespace-separated string into a list of normalized tags.
  static List<String> parseList(dynamic source) {
    if (source == null) return const [];
    if (source is List) {
      return source
          .map((e) => normalize(e.toString()))
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList();
    }
    if (source is String) {
      if (source.trim().isEmpty) return const [];
      return source
          .split(RegExp(r'[,;\s]+'))
          .map((e) => normalize(e))
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList();
    }
    return const [];
  }
}
