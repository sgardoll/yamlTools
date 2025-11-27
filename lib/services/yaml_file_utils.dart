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

  /// Ensures the YAML "key" field matches the expected value derived
  /// from the file path (e.g., archive_page/id-Scaffold_x.yaml -> Scaffold_x.yaml).
  /// Returns a [KeyFixResult] indicating whether a change was applied.
  static KeyFixResult ensureKeyMatchesFile(String yamlContent, String filePath) {
    final expectedKey = _expectedKeyValueFromFilePath(filePath);
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

  /// Derives the expected YAML key value from a file path by
  /// removing any archive_ prefix, keeping the basename, and
  /// stripping a leading "id-" if present.
  static String? _expectedKeyValueFromFilePath(String filePath) {
    var normalized = filePath.replaceAll('\\', '/');
    if (normalized.startsWith('archive_')) {
      normalized = normalized.substring(8);
    }
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }

    final parts = normalized.split('/');
    if (parts.isEmpty) return null;
    var base = parts.last;
    if (base.isEmpty) return null;

    if (base.startsWith('id-') && base.length > 3) {
      base = base.substring(3);
    }
    return base;
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
}
