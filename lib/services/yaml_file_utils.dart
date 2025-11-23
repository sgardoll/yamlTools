import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

/// Helper utilities for deriving FlutterFlow-compatible file paths
/// and keys from YAML content. Centralizing this logic ensures both
/// the AI staging flow and manual editor stay in sync.
class YamlFileUtils {
  const YamlFileUtils._();

  /// Attempts to infer the canonical FlutterFlow file path (including the
  /// directory prefix and `.yaml` extension) from the provided YAML content.
  ///
  /// Returns `null` when the structure is not recognized.
  static String? inferFilePathFromContent(String yamlContent) {
    try {
      final root = loadYaml(yamlContent);
      if (root is YamlMap) {
        for (final entry in root.entries) {
          final rawKey = entry.key;
          if (rawKey == null) continue;
          final sectionKey = rawKey.toString();

          final folder = _folderForSection(sectionKey);
          if (folder == null) continue;

          final value = entry.value;
          if (value is YamlMap) {
            final keyValue = value['key'];
            if (keyValue is String && keyValue.trim().isNotEmpty) {
              final sanitizedKey = keyValue.trim();
              return '$folder/$sanitizedKey.yaml';
            }
          }
        }
      }
    } catch (error) {
      debugPrint('Failed to infer file path from YAML: $error');
    }

    return null;
  }

  /// Infers the FlutterFlow file key (the API identifier) from the YAML
  /// content by first deriving the canonical file path and then removing the
  /// extension.
  static String? inferFileKeyFromContent(String yamlContent) {
    final filePath = inferFilePathFromContent(yamlContent);
    if (filePath == null) return null;
    if (filePath.endsWith('.yaml')) {
      return filePath.substring(0, filePath.length - 5);
    }
    return filePath;
  }

  static String? _folderForSection(String sectionKey) {
    switch (sectionKey) {
      case 'page':
        return 'page';
      case 'component':
        return 'component';
      case 'collection':
        return 'collection';
      case 'theme':
        return 'theme';
      default:
        return null;
    }
  }
}