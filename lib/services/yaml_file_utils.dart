import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

/// Helper utilities for deriving FlutterFlow-compatible file paths
/// and keys from YAML content. Centralizing this logic ensures both
/// the AI staging flow and manual editor stay in sync.
class YamlFileUtils {
  const YamlFileUtils._();

  static const Map<String, String> _folderPrefixMap = {
    'pages': 'page',
    'page': 'page',
    'archive_pages': 'page',
    'archive_page': 'page',
    'custom_actions': 'customAction',
    'custom-action': 'customAction',
    'customAction': 'customAction',
    'archive_custom_actions': 'customAction',
  };

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
              final hasExtension = sanitizedKey.endsWith('.yaml') || sanitizedKey.endsWith('.yml');
              final pathKey = hasExtension ? sanitizedKey : '$sanitizedKey.yaml';
              return '$folder/$pathKey';
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
    if (filePath.endsWith('.yml')) {
      return filePath.substring(0, filePath.length - 4);
    }
    return filePath;
  }

  /// Ensures the YAML "key" field matches the expected value derived
  /// from the file path (e.g., archive_page/id-Scaffold_x.yaml -> Scaffold_x).
  /// Returns a [KeyFixResult] indicating whether a change was applied.
  static KeyFixResult ensureKeyMatchesFile(String yamlContent, String filePath) {
    final expectedKey = normalizeFilePath(filePath).expectedYamlKey;
    if (expectedKey == null || expectedKey.isEmpty) {
      return KeyFixResult(
        content: yamlContent,
        changed: false,
        expectedKey: null,
        previousKey: null,
      );
    }

    try {
      final root = loadYaml(yamlContent);
      if (root is! YamlMap || root.isEmpty) {
        return KeyFixResult(
          content: yamlContent,
          changed: false,
          expectedKey: expectedKey,
          previousKey: null,
        );
      }

      for (final entry in root.entries) {
        final value = entry.value;
        if (value is YamlMap && value.containsKey('key')) {
          final currentKey = value['key']?.toString();
          if (currentKey == expectedKey) {
            return KeyFixResult(
              content: yamlContent,
              changed: false,
              expectedKey: expectedKey,
              previousKey: currentKey,
            );
          }

          // Replace the first "key:" line while preserving indentation.
          final keyLine = RegExp(r'^(\s*)key\s*:\s*.*$', multiLine: true);
          final match = keyLine.firstMatch(yamlContent);
          if (match != null) {
            final indent = match.group(1) ?? '';
            final updated = yamlContent.replaceFirst(
              keyLine,
              '$indent' 'key: $expectedKey',
            );
            return KeyFixResult(
              content: updated,
              changed: true,
              expectedKey: expectedKey,
              previousKey: currentKey,
            );
          }
        }
      }
    } catch (error) {
      debugPrint('Failed to auto-fix YAML key for $filePath: $error');
    }

    return KeyFixResult(
      content: yamlContent,
      changed: false,
      expectedKey: expectedKey,
      previousKey: null,
    );
  }

  /// Normalizes a file path for state/APIs and derives related keys.
  ///
  /// - Removes leading "archive_" prefix (once)
  /// - Converts backslashes to slashes
  /// - Removes duplicate ".yaml"/".yml" suffixes, ensures a single ".yaml"
  /// - Removes a leading slash
  ///
  /// Returns [NormalizedPath] containing:
  /// - canonicalPath: normalized path with one ".yaml"
  /// - apiFileKey: canonical path without extension
  /// - expectedYamlKey: basename without extension, leading "id-" stripped
  static NormalizedPath normalizeFilePath(String rawPath) {
    String path = rawPath.trim();
    path = path.replaceAll('\\', '/');
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    if (path.startsWith('archive_')) {
      path = path.substring(8);
    }
    path = _canonicalizeFolderPrefix(path);

    // Ensure only one extension at the end
    path = path.replaceFirst(RegExp(r'(\\.ya?ml)+$', caseSensitive: false), '.yaml');
    if (!path.toLowerCase().endsWith('.yaml')) {
      path = '$path.yaml';
    }

    final apiFileKey = path.substring(0, path.length - 5);
    final parts = path.split('/');
    final baseName = parts.isNotEmpty ? parts.last : path;
    var expectedKey = baseName.endsWith('.yaml')
        ? baseName.substring(0, baseName.length - 5)
        : baseName;
    if (expectedKey.startsWith('id-') && expectedKey.length > 3) {
      expectedKey = expectedKey.substring(3);
    }

    return NormalizedPath(
      canonicalPath: path,
      apiFileKey: apiFileKey,
      expectedYamlKey: expectedKey,
    );
  }

  static String _canonicalizeFolderPrefix(String path) {
    if (path.isEmpty) return path;

    final firstSlash = path.indexOf('/');
    final prefix =
        firstSlash == -1 ? path : path.substring(0, firstSlash);
    final rest = firstSlash == -1 ? '' : path.substring(firstSlash);
    final mapped = _folderPrefixMap[prefix] ?? prefix;
    return '$mapped$rest';
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

class KeyFixResult {
  final String content;
  final bool changed;
  final String? expectedKey;
  final String? previousKey;

  const KeyFixResult({
    required this.content,
    required this.changed,
    this.expectedKey,
    this.previousKey,
  });

  KeyFixResult copyWith({
    String? content,
    bool? changed,
    String? expectedKey,
    String? previousKey,
  }) {
    return KeyFixResult(
      content: content ?? this.content,
      changed: changed ?? this.changed,
      expectedKey: expectedKey ?? this.expectedKey,
      previousKey: previousKey ?? this.previousKey,
    );
  }
}

class NormalizedPath {
  final String canonicalPath;
  final String apiFileKey;
  final String expectedYamlKey;

  const NormalizedPath({
    required this.canonicalPath,
    required this.apiFileKey,
    required this.expectedYamlKey,
  });
}
