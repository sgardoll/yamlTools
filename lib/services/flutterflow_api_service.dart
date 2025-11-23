import 'dart:convert';
import 'package:http/http.dart' as http;

class FlutterFlowApiService {
  static const String _baseUrl = 'https://api.flutterflow.io/v2-staging';

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

    print('Updating project YAML for project: $projectId');
    print('Files to update: ${fileKeyToContent.keys.join(', ')}');
    // Debug: print the actual file key to content mapping
    fileKeyToContent.forEach((key, content) {
      print('File key: "$key" -> Content length: ${content.length} chars');
    });

    try {
      // Primary endpoint per updated FlutterFlow API docs
      final primaryUri = Uri.parse('$_baseUrl/updateProjectByYaml');
      print('Attempting YAML update via: $primaryUri (method: POST)');

      final primaryResponse = await http.post(
        primaryUri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      );

      print(
          'Primary update response status: ${primaryResponse.statusCode}');
      print('Primary update response body: ${primaryResponse.body}');

      if (primaryResponse.statusCode == 200) {
        print('Successfully updated project YAML via primary endpoint');
        return true;
      }

      // Fallback PUT endpoint for older API paths
      final fallbackPutUri = Uri.parse('$_baseUrl/projectYaml');
      print(
          'Primary endpoint failed. Trying fallback endpoint: $fallbackPutUri (method: PUT)');

      final fallbackPutResponse = await http.put(
        fallbackPutUri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      );

      print('Fallback PUT response status: ${fallbackPutResponse.statusCode}');
      print('Fallback PUT response body: ${fallbackPutResponse.body}');

      if (fallbackPutResponse.statusCode == 200) {
        print('Successfully updated project YAML via fallback PUT endpoint');
        return true;
      }

      // Legacy POST endpoint for even older API paths
      final legacyUri = Uri.parse('$_baseUrl/updateProjectYaml');
      print('Fallback PUT failed. Trying legacy endpoint: $legacyUri');

      final legacyResponse = await http.post(
        legacyUri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      );

      print('Legacy update response status: ${legacyResponse.statusCode}');
      print('Legacy update response body: ${legacyResponse.body}');

      if (legacyResponse.statusCode == 200) {
        print('Successfully updated project YAML via legacy endpoint');
        return true;
      }

      throw Exception(
        'Failed to update project YAML. Primary status: '
        '${primaryResponse.statusCode}, Fallback PUT status: '
        '${fallbackPutResponse.statusCode}, Legacy status: '
        '${legacyResponse.statusCode}. Last body: ${legacyResponse.body}',
      );
    } catch (e) {
      print('Error updating project YAML: $e');
      throw Exception('Network error while updating project YAML: $e');
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
    String fileKey = fileName;

    // Remove the "archive_" prefix if present
    if (fileKey.startsWith('archive_')) {
      fileKey = fileKey.substring(8); // Remove "archive_" (8 characters)
    }

    // Remove common YAML file extensions
    if (fileKey.endsWith('.yaml')) {
      fileKey = fileKey.substring(0, fileKey.length - 5);
    } else if (fileKey.endsWith('.yml')) {
      fileKey = fileKey.substring(0, fileKey.length - 4);
    }

    return fileKey;
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
      print('DEBUG: Converting "$fileName" -> "$fileKey"'); // Debug log
      fileKeyToContent[fileKey] = content;
    });

    return fileKeyToContent;
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
      print('  "$testCase" -> "$result"');
    }
  }
}
