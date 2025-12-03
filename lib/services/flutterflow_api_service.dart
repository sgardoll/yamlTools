import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'yaml_file_utils.dart';

class FlutterFlowProject {
  final String id;
  final String name;

  const FlutterFlowProject({required this.id, required this.name});

  factory FlutterFlowProject.fromJson(Map<String, dynamic> json) {
    return FlutterFlowProject(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled Project',
    );
  }
}

class FlutterFlowApiService {
  static const String baseUrl = 'https://api.flutterflow.io/v2';
  static final Map<String, String> _fileKeyCache = {};
  static final Map<_FileKeyScope, String> _formatPreferenceByScope = {};
  static const Map<String, String> _folderPrefixMap = {
    'pages': 'page',
    'page': 'page',
    'archive_page': 'page',
    'archive_pages': 'page',
    'custom_actions': 'customAction',
    'custom-action': 'customAction',
    'customAction': 'customAction',
    'archive_custom_actions': 'customAction',
  };

  /// Fetches all projects accessible to the authenticated user.
  static Future<List<FlutterFlowProject>> fetchProjects({
    required String apiToken,
  }) async {
    if (apiToken.isEmpty) {
      throw ArgumentError('API token cannot be empty');
    }

    final uri = Uri.parse('$baseUrl/l/listProjects');
    debugPrint('Fetching projects via: $uri');

    http.Response? response;

    try {
      response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'project_type': 'ALL',
          'deserialize_response': true,
        }),
      );
    } catch (e) {
      throw FlutterFlowApiException(
        endpoint: '$baseUrl/l/listProjects',
        message: 'Network error while fetching projects: $e',
        isNetworkError: true,
      );
    }

    if (response.statusCode != 200) {
      throw buildApiException(
        endpoint: '$baseUrl/l/listProjects',
        response: response,
        note: 'Failed to load projects for the current user.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      throw FlutterFlowApiException(
        endpoint: '$baseUrl/l/listProjects',
        response: response,
        message: 'Invalid JSON response while loading projects: $e',
      );
    }

    List<dynamic>? entries;

    if (decoded is Map<String, dynamic>) {
      // Respect explicit failure flag if present
      if (decoded.containsKey('success') && decoded['success'] == false) {
        final reason = decoded['reason']?.toString();
        throw FlutterFlowApiException(
          endpoint: '$baseUrl/l/listProjects',
          response: response,
          message: reason?.isNotEmpty == true
              ? reason!
              : 'Project listing failed with success=false.',
        );
      }

      dynamic payload = decoded;
      if (payload['value'] != null) {
        payload = payload['value'];
      }

      // Some responses embed JSON as a string; decode if so.
      if (payload is String) {
        try {
          payload = jsonDecode(payload);
        } catch (_) {
          throw FlutterFlowApiException(
            endpoint: '$baseUrl/l/listProjects',
            response: response,
            message:
                'Unable to parse projects payload from server response (malformed JSON string).',
          );
        }
      }

      if (payload is Map<String, dynamic>) {
        if (payload['entries'] is List) {
          entries = payload['entries'] as List;
        } else if (payload['projects'] is List) {
          entries = payload['projects'] as List;
        } else if (payload['items'] is List) {
          entries = payload['items'] as List;
        }
      } else if (payload is List) {
        entries = payload;
      }
    } else if (decoded is List) {
      entries = decoded;
    }

    if (entries == null || entries.isEmpty) {
      throw FlutterFlowApiException(
        endpoint: '$baseUrl/l/listProjects',
        response: response,
        message: 'No projects returned from API.',
      );
    }

    FlutterFlowProject? _projectFromEntry(Map<String, dynamic> entry) {
      final projectData = entry['project'];
      final id = (entry['id'] ??
              entry['project_id'] ??
              entry['projectId'] ??
              (projectData is Map<String, dynamic> ? projectData['id'] : null))
          ?.toString();
      final name = (entry['name'] ??
              entry['projectName'] ??
              (projectData is Map<String, dynamic>
                  ? projectData['name']
                  : null))
          ?.toString();

      if (id == null || id.isEmpty) return null;
      return FlutterFlowProject(
        id: id,
        name: (name == null || name.isEmpty) ? 'Untitled Project' : name,
      );
    }

    return entries
        .whereType<Map<String, dynamic>>()
        .map(_projectFromEntry)
        .whereType<FlutterFlowProject>()
        .where((project) => project.id.isNotEmpty)
        .toList();
  }

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
        jsonBody =
            body.isNotEmpty ? json.decode(body) as Map<String, dynamic> : null;
      } catch (_) {
        jsonBody = null;
      }

      // Prefer structured fields
      if (jsonBody != null) {
        message = (jsonBody['error'] ??
                jsonBody['message'] ??
                jsonBody['reason'] ??
                body ??
                '')
            .toString();
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

  /// Helper method to create a base64 encoded zip from file content map
  static String _createProjectZip(Map<String, String> fileKeyToContent) {
    final archive = Archive();

    fileKeyToContent.forEach((key, content) {
      // Ensure key has .yaml extension for the zip entry
      String entryName = getFileKey(key);
      if (!entryName.toLowerCase().endsWith('.yaml') &&
          !entryName.toLowerCase().endsWith('.yml')) {
        entryName = '$entryName.yaml';
      }

      final bytes = utf8.encode(content);
      final file = ArchiveFile(entryName, bytes.length, bytes);
      archive.addFile(file);
    });

    final encoder = ZipEncoder();
    final encodedBytes = encoder.encode(archive);

    if (encodedBytes == null) {
      throw Exception('Failed to encode zip archive');
    }

    return base64Encode(encodedBytes);
  }

  /// Maps known archive/plural folder prefixes to the canonical API folder
  /// names (e.g., archive_pages/ -> page/, archive_custom_actions/ -> customAction/).
  /// When [preserveArchivePrefix] is true, an archive_ prefix is retained
  /// after mapping; otherwise it is removed.
  static String _canonicalizeFolderPrefix(String filePath,
      {bool preserveArchivePrefix = true}) {
    if (filePath.isEmpty) return filePath;

    var normalized = filePath.replaceAll('\\', '/');
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }

    final hasArchivePrefix = normalized.startsWith('archive_');
    var withoutArchive =
        hasArchivePrefix ? normalized.substring(8) : normalized;

    final firstSlash = withoutArchive.indexOf('/');
    final prefix = firstSlash == -1
        ? withoutArchive
        : withoutArchive.substring(0, firstSlash);
    final rest = firstSlash == -1 ? '' : withoutArchive.substring(firstSlash);

    final mappedPrefix = _folderPrefixMap[prefix] ?? prefix;
    final rebuilt =
        (preserveArchivePrefix && hasArchivePrefix ? 'archive_' : '') +
            mappedPrefix +
            rest;

    return rebuilt;
  }

  /// Validates the YAML files in a FlutterFlow project using the Zip approach.
  ///
  /// [projectId] - The FlutterFlow project ID
  /// [apiToken] - The API token for authentication
  /// [fileKeyToContent] - A map from file key to YAML content
  ///
  /// Returns a Map with validation results:
  /// {
  ///   'valid': bool,
  ///   'errors': List<String>,
  ///   'warnings': List<String>
  /// }
  static Future<Map<String, dynamic>> validateProjectYaml({
    required String projectId,
    required String apiToken,
    required Map<String, String> fileKeyToContent,
  }) async {
    if (projectId.isEmpty || apiToken.isEmpty) {
      throw ArgumentError('Project ID and API token cannot be empty');
    }

    final yamlContent = _createProjectZip(fileKeyToContent);

    final body = jsonEncode({
      'projectId': projectId,
      'yamlContent': yamlContent,
    });

    try {
      final uri = Uri.parse('$baseUrl/validateProjectYaml');
      debugPrint('Validating project YAML via: $uri');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      );

      debugPrint('Validation response status: ${response.statusCode}');
      debugPrint('Validation response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true) {
        return {
          'valid': true,
          'errors': <String>[],
          'warnings': <String>[],
        };
      } else {
        final reason = responseData['reason'] as String? ?? 'Validation failed';
        return {
          'valid': false,
          'errors': [reason],
          'warnings': <String>[],
        };
      }
    } catch (e) {
      debugPrint('Error validating project YAML: $e');
      throw FlutterFlowApiException(
        endpoint: baseUrl,
        message: 'Network error while validating project YAML: $e',
        isNetworkError: true,
      );
    }
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

    // Canonicalize file keys (strip extensions/archive prefixes) before zipping
    final canonical = <String, String>{};
    fileKeyToContent.forEach((rawKey, content) {
      final normalizedKey = getFileKey(rawKey);
      canonical[normalizedKey] = content;
    });

    final validationResult = await validateProjectYaml(
      projectId: projectId,
      apiToken: apiToken,
      fileKeyToContent: canonical,
    );

    if (validationResult['valid'] != true) {
      final errors =
          (validationResult['errors'] as List?)?.whereType<String>().toList() ??
              <String>[];
      final reason = errors.isNotEmpty
          ? errors.join('; ')
          : 'Validation failed before update.';

      throw FlutterFlowApiException(
        endpoint: '$baseUrl/validateProjectYaml',
        statusCode: 400,
        body: null,
        message: reason,
        note: 'Update aborted due to validation failure.',
      );
    }

    // Create Base64 Encoded Zip
    final yamlContent = _createProjectZip(canonical);

    final body = jsonEncode({
      'projectId': projectId,
      'yamlContent': yamlContent,
    });

    debugPrint('Updating project YAML for project: $projectId');
    debugPrint('Files to update: ${canonical.keys.join(', ')}');

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

      debugPrint(
          'Primary update response status: ${primaryResponse.statusCode}');
      debugPrint('Primary update response body: ${primaryResponse.body}');

      if (primaryResponse.statusCode == 200) {
        bool? successFlag;
        String? responseReason;

        try {
          final decoded = jsonDecode(primaryResponse.body);
          if (decoded is Map<String, dynamic>) {
            bool? extractSuccess(dynamic value) {
              if (value is bool) return value;
              if (value is String) {
                final lower = value.toLowerCase();
                if (lower == 'true') return true;
                if (lower == 'false') return false;
              }
              if (value is Map<String, dynamic>) {
                final direct = extractSuccess(value['success']);
                if (direct != null) return direct;
                return extractSuccess(value['value']);
              }
              return null;
            }

            String? extractReason(dynamic value) {
              if (value is Map<String, dynamic>) {
                final reason =
                    value['reason'] ?? value['message'] ?? value['error'];
                if (reason != null && reason.toString().isNotEmpty) {
                  return reason.toString();
                }
                return extractReason(value['value']);
              }
              return null;
            }

            successFlag = extractSuccess(decoded);
            responseReason = extractReason(decoded);
          }
        } catch (parseError) {
          debugPrint('Unable to parse update response JSON: $parseError');
        }

        // FlutterFlow can return HTTP 200 with success=false when it rejects the
        // update (e.g., invalid file key or schema error). Surface that instead
        // of silently treating the call as successful.
        final updateRejected = successFlag == false ||
            (successFlag != true && (responseReason?.isNotEmpty ?? false));

        if (updateRejected) {
          throw buildApiException(
            endpoint: primaryUri.toString(),
            response: primaryResponse,
            note: responseReason ??
                'Update rejected by FlutterFlow (success=false in response).',
          );
        }

        debugPrint('Successfully updated project YAML via primary endpoint');
        return true;
      }

      // If the primary endpoint returns a client error (4xx), it's very likely
      // a validation error. Surface it.
      if (primaryResponse.statusCode >= 400 &&
          primaryResponse.statusCode < 500) {
        throw buildApiException(
          endpoint: primaryUri.toString(),
          response: primaryResponse,
          note:
              'Primary endpoint returned client error — validation likely failed.',
        );
      }

      throw buildApiException(
        endpoint: primaryUri.toString(),
        response: primaryResponse,
        note: 'Update failed with status ${primaryResponse.statusCode}',
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
    final withoutArchiveWithoutExt = _stripYamlExtension(withoutArchiveWithExt);

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
    var normalized = _canonicalizeFolderPrefix(
      filePath.replaceAll('\\', '/'),
      preserveArchivePrefix: false,
    );
    // Collapse repeated extensions
    normalized = normalized.replaceFirst(
        RegExp(r'(\\.ya?ml)+$', caseSensitive: false), '.yaml');
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

  static String _normalizeForCandidates(String filePath,
      {bool canonicalizeFolders = true}) {
    var normalized = filePath.trim().replaceAll('\\', '/');
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    if (canonicalizeFolders) {
      normalized =
          _canonicalizeFolderPrefix(normalized, preserveArchivePrefix: true);
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
    final normalized = _normalizeForCandidates(
      filePath,
      canonicalizeFolders: true,
    );
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
    final preferredSignature =
        _formatPreferenceByScope[_scopeForPath(filePath)];
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
    final normalizedKey = getFileKey(fileKey);

    // Probe using the same zip-based payload we use for real validation/updates
    // to avoid false positives from the legacy fileKey/fileContent shape.
    final uri = Uri.parse('$baseUrl/validateProjectYaml');
    final yamlContent = _createProjectZip({normalizedKey: content});
    final payload =
        jsonEncode({'projectId': projectId, 'yamlContent': yamlContent});

    debugPrint('Validation probe payload for "$fileKey": $payload');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: payload,
      );

      debugPrint(
          'Validation probe response (${response.statusCode}) for "$fileKey": ${response.body}');

      // 200 = accepted (success true/false), 400 = format accepted but content invalid.
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
        final canonicalKey = getFileKey(candidate);
        debugPrint('✅ Working key found: "$canonicalKey" (from "$candidate")');
        _fileKeyCache[cacheKey] = canonicalKey;
        _rememberFormatPreference(filePath, candidate);
        return canonicalKey;
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
  final http.Response? response;
  final bool isNetworkError;

  const FlutterFlowApiException({
    required this.message,
    this.statusCode,
    this.endpoint,
    this.body,
    this.note,
    this.response,
    this.isNetworkError = false,
  });

  @override
  String toString() {
    final code = statusCode != null ? 'HTTP $statusCode' : 'No HTTP status';
    return 'FlutterFlowApiException($code, endpoint: $endpoint, message: $message)';
  }
}
