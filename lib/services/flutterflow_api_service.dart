import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'yaml_file_utils.dart';

class FlutterFlowApiService {
  static const String baseUrl = 'https://api.flutterflow.io/v2';
  static final Map<String, String> _fileKeyCache = {};
  static final Map<_FileKeyScope, String> _formatPreferenceByScope = {};

  /// A structured exception to preserve rich error details from the API
  /// so the UI can present actionable feedback (path, line/col, message).
  static FlutterFlowApiException buildApiException({
    required String endpoint,
    required http.Response? response,
    String? note,
  }) {
    int? status;
    String? body;
    Map<String, dynamic>? jsonBody;
    String message = 'Unknown error';

    if (response != null) {
      status = response.statusCode;
      body = response.body;
      // Try to decode JSON to extract errors/messages
      try {
        jsonBody = body.isNotEmpty ? json.decode(body) as Map<String, dynamic> : null;
      } catch (_) {
        jsonBody = null;
      }

      // Prefer structured fields
      if (jsonBody != null) {
        message = (jsonBody['error'] ?? jsonBody['message'] ?? body ?? '').toString();
      } else {
        message = body ?? 'HTTP $status error';
      }
    }

    return FlutterFlowApiException(
      endpoint: endpoint,
      statusCode: status,
      body: body,
      message: message,
      note: note,
    );
  }

  /// Updates the YAML files in a FlutterFlow project
  ///
  /// [projectId] - The FlutterFlow project ID
  /// [apiToken] - The API token for authentication
  /// [fileKeyToContent] - A map from file key (name without extension) to YAML content
  ///
  /// Returns true if successful, throws an exception if failed
  static Future<bool> updateProjectYaml({
    required String projectId,
    required String apiToken,
    required Map<String, String> fileKeyToContent,
  }) async {
    if (projectId.isEmpty || apiToken.isEmpty) {
      throw ArgumentError('Project ID and API token cannot be empty');
    }

    if (fileKeyToContent.isEmpty) {
      throw ArgumentError('File content map cannot be empty');
    }

    final body = jsonEncode({
      'projectId': projectId,
      'fileKeyToContent': fileKeyToContent,
    });

    debugPrint('Updating project YAML for project: $projectId');
    debugPrint('Files to update: ${fileKeyToContent.keys.join(', ')}');
    // Debug: print the actual file key to content mapping
    fileKeyToContent.forEach((key, content) {
      print('File key: "$key" -> Content length: ${content.length} chars');
    });

    try {
      // Primary endpoint per updated FlutterFlow API docs
      final primaryUri = Uri.parse('$baseUrl/updateProjectByYaml');
      debugPrint('Attempting YAML update via: $primaryUri (method: POST)');

      final primaryResponse = await http.post(
        primaryUri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      );

      debugPrint('Primary update response status: ${primaryResponse.statusCode}');
      debugPrint('Primary update response body: ${primaryResponse.body}');

      if (primaryResponse.statusCode == 200) {
        debugPrint('Successfully updated project YAML via primary endpoint');
        return true;
      }

      // If the primary endpoint returns a client error (4xx), it's very likely
      // a validation error. Do NOT fall back and mask the message. Surface it.
      if (primaryResponse.statusCode >= 400 && primaryResponse.statusCode < 500) {
        throw buildApiException(
          endpoint: primaryUri.toString(),
          response: primaryResponse,
          note: 'Primary endpoint returned client error — validation likely failed.',
        );
      }

      // Fallback PUT endpoint for older API paths
      final fallbackPutUri = Uri.parse('$baseUrl/projectYaml');
      debugPrint('Primary endpoint failed. Trying fallback endpoint: $fallbackPutUri (method: PUT)');

      final fallbackPutResponse = await http.put(
        fallbackPutUri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      );

      debugPrint('Fallback PUT response status: ${fallbackPutResponse.statusCode}');
      debugPrint('Fallback PUT response body: ${fallbackPutResponse.body}');

      if (fallbackPutResponse.statusCode == 200) {
        debugPrint('Successfully updated project YAML via fallback PUT endpoint');
        return true;
      }

      if (fallbackPutResponse.statusCode >= 400 && fallbackPutResponse.statusCode < 500) {
        throw buildApiException(
          endpoint: fallbackPutUri.toString(),
          response: fallbackPutResponse,
          note: 'Fallback PUT endpoint returned client error.',
        );
      }

      // Legacy POST endpoint for even older API paths
      final legacyUri = Uri.parse('$baseUrl/updateProjectYaml');
      debugPrint('Fallback PUT failed. Trying legacy endpoint: $legacyUri');

      final legacyResponse = await http.post(
        legacyUri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      );

      debugPrint('Legacy update response status: ${legacyResponse.statusCode}');
      debugPrint('Legacy update response body: ${legacyResponse.body}');

      if (legacyResponse.statusCode == 200) {
        debugPrint('Successfully updated project YAML via legacy endpoint');
        return true;
      }

      throw buildApiException(
        endpoint: legacyUri.toString(),
        response: legacyResponse,
        note:
            'All endpoints failed. See body for the most recent error. Primary and fallback statuses were ${primaryResponse.statusCode} and ${fallbackPutResponse.statusCode}.',
      );
    } catch (e) {
      // If we already built a structured API exception, just bubble it up.
      if (e is FlutterFlowApiException) {
        debugPrint('API update failed with structured error: $e');
        rethrow;
      }

      debugPrint('Error updating project YAML (likely network): $e');
      throw FlutterFlowApiException(
        endpoint: baseUrl,
        statusCode: null,
        body: null,
        message: 'Network error while updating project YAML: $e',
        isNetworkError: true,
      );
    }
  }

  /// Updates multiple YAML files in a FlutterFlow project in a single API call
  ///
  /// [projectId] - The FlutterFlow project ID
  /// [apiToken] - The API token for authentication
  /// [fileNameToContent] - A map from file names (with extensions) to YAML content
  ///
  /// Returns true if successful, throws an exception if failed
  static Future<bool> updateMultipleProjectYamls({
    required String projectId,
    required String apiToken,
    required Map<String, String> fileNameToContent,
  }) async {
    if (projectId.isEmpty || apiToken.isEmpty) {
      throw ArgumentError('Project ID and API token cannot be empty');
    }

    if (fileNameToContent.isEmpty) {
      throw ArgumentError('File content map cannot be empty');
    }

    // Convert file names to file keys
    final fileKeyToContent = convertFileNamesToKeys(fileNameToContent);

    return await updateProjectYaml(
      projectId: projectId,
      apiToken: apiToken,
      fileKeyToContent: fileKeyToContent,
    );
  }

  /// Helper method to convert file names to file keys (removes file extension)
  ///
  /// [fileName] - The file name with extension (e.g., "archive_collections/users.yaml")
  ///
  /// Returns the file key without extension and archive prefix (e.g., "collections/users")
  static String getFileKey(String fileName) {
    final normalized = _normalizeArchivePath(fileName);
    return _stripYamlExtension(normalized);
  }

  /// Builds a list of candidate file keys to try with the API.
  /// This helps when the archive path differs from what the API expects
  /// (e.g., requiring `.yaml` extension or when the YAML content encodes the key).
  static List<String> buildFileKeyCandidates({
    required String filePath,
    String? yamlContent,
  }) {
    final seen = <String>{};
    final prioritized = <String>[];
    final ordered = <String>[];

    void add(String raw, {bool prefer = false}) {
      final normalized = _normalizeForCandidates(raw);
      if (normalized.isEmpty || !seen.add(normalized)) return;
      if (prefer) {
        prioritized.add(normalized);
      } else {
        ordered.add(normalized);
      }
    }

    // Inferred key from YAML takes precedence so we preserve the schema-driven intent.
    if (yamlContent != null) {
      final inferred = YamlFileUtils.inferFileKeyFromContent(yamlContent);
      if (inferred != null && inferred.trim().isNotEmpty) {
        final normalizedInferred = _normalizeForCandidates(inferred.trim());
        add(_stripYamlExtension(normalizedInferred), prefer: true);
        add(_ensureYamlExtensionPreservingArchive(normalizedInferred),
            prefer: true);
      }
    }

    final normalizedPath = _normalizeForCandidates(filePath);
    final withExt = _ensureYamlExtensionPreservingArchive(normalizedPath);
    final withoutExt = _stripYamlExtension(withExt);

    final archivePath = _withArchivePrefix(normalizedPath);
    final archiveWithExt = _ensureYamlExtensionPreservingArchive(archivePath);
    final archiveWithoutExt = _stripYamlExtension(archiveWithExt);

    final withoutArchive = _stripArchivePrefix(normalizedPath);
    final withoutArchiveWithExt =
        _ensureYamlExtensionPreservingArchive(withoutArchive);
    final withoutArchiveWithoutExt =
        _stripYamlExtension(withoutArchiveWithExt);

    // Default probing order per empirical strategy (no extension -> extension -> archive variants).
    add(withoutExt);
    add(withExt);
    add(archiveWithExt);
    add(archiveWithoutExt);
    add(withoutArchiveWithoutExt);
    add(withoutArchiveWithExt);

    return [...prioritized, ...ordered];
  }

  static String _normalizeArchivePath(String filePath) {
    var normalized = filePath.replaceAll('\\', '/');
    if (normalized.startsWith('archive_')) {
      normalized = normalized.substring(8);
    }
    // Collapse repeated extensions
    normalized = normalized.replaceFirst(RegExp(r'(\\.ya?ml)+$', caseSensitive: false), '.yaml');
    return normalized.startsWith('/') ? normalized.substring(1) : normalized;
  }

  static String _stripYamlExtension(String filePath) {
    String fileKey = filePath;

    // Remove common YAML file extensions
    if (fileKey.endsWith('.yaml')) {
      fileKey = fileKey.substring(0, fileKey.length - 5);
    } else if (fileKey.endsWith('.yml')) {
      fileKey = fileKey.substring(0, fileKey.length - 4);
    }

    return fileKey;
  }

  static String _ensureYamlExtension(String filePath) {
    final normalized = _normalizeArchivePath(filePath);
    if (normalized.endsWith('.yaml') || normalized.endsWith('.yml')) {
      return normalized;
    }
    return '$normalized.yaml';
  }

  static String _normalizeForCandidates(String filePath) {
    var normalized = filePath.trim().replaceAll('\\', '/');
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    normalized = normalized.replaceFirst(
      RegExp(r'(\\.ya?ml)+$', caseSensitive: false),
      '.yaml',
    );
    return normalized;
  }

  static String _withArchivePrefix(String filePath) {
    final normalized = _normalizeForCandidates(filePath);
    return normalized.startsWith('archive_')
        ? normalized
        : 'archive_$normalized';
  }

  static String _stripArchivePrefix(String filePath) {
    final normalized = _normalizeForCandidates(filePath);
    return normalized.startsWith('archive_')
        ? normalized.substring(8)
        : normalized;
  }

  static String _ensureYamlExtensionPreservingArchive(String filePath) {
    final normalized = _normalizeForCandidates(filePath);
    if (normalized.toLowerCase().endsWith('.yaml')) {
      return normalized;
    }
    if (normalized.toLowerCase().endsWith('.yml')) {
      return '${normalized.substring(0, normalized.length - 4)}.yaml';
    }
    return '$normalized.yaml';
  }

  static String _cacheKeyForPath(String filePath) =>
      _stripYamlExtension(_normalizeForCandidates(filePath));

  static List<String> _prioritizeCandidates(
    List<String> candidates,
    String filePath,
  ) {
    final preferredSignature = _formatPreferenceByScope[_scopeForPath(filePath)];
    if (preferredSignature == null) {
      return candidates;
    }

    final prioritized = <String>[];
    final remaining = <String>[];

    for (final candidate in candidates) {
      if (_formatSignature(candidate) == preferredSignature) {
        prioritized.add(candidate);
      } else {
        remaining.add(candidate);
      }
    }

    return [...prioritized, ...remaining];
  }

  static void _rememberFormatPreference(String filePath, String candidate) {
    final scope = _scopeForPath(filePath);
    final signature = _formatSignature(candidate);
    _formatPreferenceByScope[scope] = signature;
    debugPrint(
      'Cached preferred key format for $scope: $signature (from "$candidate")',
    );
  }

  static String _formatSignature(String candidate) {
    final normalized = _normalizeForCandidates(candidate);
    final hasArchivePrefix = normalized.startsWith('archive_');
    final hasExtension = normalized.toLowerCase().endsWith('.yaml') ||
        normalized.toLowerCase().endsWith('.yml');
    return '${hasArchivePrefix ? 'archive' : 'noArchive'}|'
        '${hasExtension ? 'ext' : 'noExt'}';
  }

  static _FileKeyScope _scopeForPath(String filePath) {
    final normalized = _normalizeForCandidates(filePath);
    return normalized.contains('/') ? _FileKeyScope.nested : _FileKeyScope.root;
  }

  static Future<bool> _testFileKey({
    required String projectId,
    required String apiToken,
    required String fileKey,
    required String content,
  }) async {
    final uri = Uri.parse('$baseUrl/validateProjectYaml');
    final payload = {
      'projectId': projectId,
      'fileKey': fileKey,
      'fileContent': content,
    };

    debugPrint('Validation probe payload for "$fileKey": ${jsonEncode(payload)}');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );

      debugPrint(
          'Validation probe response (${response.statusCode}) for "$fileKey": ${response.body}');

      // 200 = accepted, 400 = format accepted but content invalid.
      return response.statusCode == 200 || response.statusCode == 400;
    } catch (e) {
      debugPrint('Validation probe threw for "$fileKey": $e');
      return false;
    }
  }

  /// Converts a map of file names to content into a map of file keys to content
  ///
  /// [fileNameToContent] - Map from file names (with extensions) to content
  ///
  /// Returns a map from file keys (without extensions) to content
  static Map<String, String> convertFileNamesToKeys(
      Map<String, String> fileNameToContent) {
    final Map<String, String> fileKeyToContent = {};

    fileNameToContent.forEach((fileName, content) {
      final fileKey = getFileKey(fileName);
      debugPrint('DEBUG: Converting "$fileName" -> "$fileKey"'); // Debug log
      fileKeyToContent[fileKey] = content;
    });

    return fileKeyToContent;
  }

  /// Resolves a local file path to its FlutterFlow file key by empirically
  /// probing candidate formats against the validation endpoint. This avoids
  /// listPartitionedFileNames entirely.
  static Future<String?> resolveFileKey({
    required String projectId,
    required String apiToken,
    required String filePath,
    String? yamlContent,
  }) async {
    return resolveFileKeyEmpirical(
      projectId: projectId,
      apiToken: apiToken,
      filePath: filePath,
      yamlContent: yamlContent,
    );
  }

  /// NEW APPROACH: probe candidate file keys until the validation endpoint
  /// accepts the format (HTTP 200 or 400). Logs every attempt with payload
  /// and response for visibility.
  static Future<String?> resolveFileKeyEmpirical({
    required String projectId,
    required String apiToken,
    required String filePath,
    String? yamlContent,
  }) async {
    final cacheKey = _cacheKeyForPath(filePath);
    final cached = _fileKeyCache[cacheKey];
    if (cached != null) {
      debugPrint('Using cached file key for "$filePath": "$cached"');
      return cached;
    }

    final candidates = _prioritizeCandidates(
      buildFileKeyCandidates(filePath: filePath, yamlContent: yamlContent),
      filePath,
    );

    debugPrint('Testing ${candidates.length} candidate keys for: $filePath');

    for (final candidate in candidates) {
      debugPrint('Testing candidate: "$candidate"');

      final works = await _testFileKey(
        projectId: projectId,
        apiToken: apiToken,
        fileKey: candidate,
        content: yamlContent ?? '',
      );

      if (works) {
        debugPrint('✅ Working key found: "$candidate"');
        _fileKeyCache[cacheKey] = candidate;
        _rememberFormatPreference(filePath, candidate);
        return candidate;
      } else {
        debugPrint('❌ Key failed: "$candidate"');
      }
    }

    debugPrint('No working file key found for: $filePath');
    return null;
  }

  /// Test method to verify file key conversion (for debugging)
  static void testFileKeyConversion() {
    final testCases = [
      'archive_collections/users.yaml',
      'archive_components/my-component.yaml',
      'complete_raw.yaml',
      'raw_project.yaml',
      'project.yaml',
      'archive_pages/home-page.yaml',
    ];

    print('Testing file key conversions:');
    for (final testCase in testCases) {
      final result = getFileKey(testCase);
      debugPrint('  "$testCase" -> "$result"');
    }
  }
}

enum _FileKeyScope { root, nested }

class FlutterFlowApiException implements Exception {
  final int? statusCode;
  final String message;
  final String? endpoint;
  final String? body;
  final String? note;
  final bool isNetworkError;

  const FlutterFlowApiException({
    required this.message,
    this.statusCode,
    this.endpoint,
    this.body,
    this.note,
    this.isNetworkError = false,
  });

  @override
  String toString() {
    final code = statusCode != null ? 'HTTP $statusCode' : 'No HTTP status';
    return 'FlutterFlowApiException($code, endpoint: $endpoint, message: $message)';
  }
}
