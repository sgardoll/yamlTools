import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For utf8 decoding & JSON
import 'package:yaml/yaml.dart';
import 'package:archive/archive.dart'; // For ZIP file handling
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../storage/preferences_manager.dart';
import '../widgets/recent_projects_widget.dart';
import '../widgets/app_header.dart';
import '../widgets/project_header.dart';
import '../widgets/yaml_content_viewer.dart';
import '../widgets/modern_yaml_tree.dart';
import '../widgets/ai_assist_panel.dart'; // Import the new AI Assist panel
import '../services/ai/ai_models.dart'; // Import AI models
import '../services/flutterflow_api_service.dart'; // Import FlutterFlow API service
import '../services/yaml_file_utils.dart';
import '../theme/app_theme.dart';
// import '../services/validation_service.dart'; // File doesn't exist
// import '../services/yaml_service.dart'; // File doesn't exist
// import '../services/yaml_comparison_service.dart'; // File doesn't exist
// import '../widgets/export_files_view.dart'; // File doesn't exist
// Import web-specific functionality conditionally
import '../web_file_download.dart'
    if (dart.library.io) '../no_op_file_download.dart' as file_download;

// We're not using conditional imports

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Path to the hero image shown on the load screen. Upload your image to
  // Dreamflow's Assets panel and name or place it at this path.
  // Intro logo shown above the "Load FlutterFlow Project" title on the home screen
  static const String _heroImagePath = 'assets/images/intro_logo.png';
  static const String _flutterFlowDocsUrl =
      'https://docs.flutterflow.io/api-and-integrations/flutterflow-api';
  static const String _apiBaseUrl = FlutterFlowApiService.baseUrl;
  // 1. Declare ALL state fields and controllers here:
  String? _rawFetchedYaml;
  Map<String, dynamic>? _parsedYamlMap;
  String _generatedYamlMessage =
      "Enter Project ID and API Token, then click 'Fetch YAML'."; // Initial message
  String _operationMessage = ""; // For status messages like "Page created"

  // Map to store separate YAML files for export
  Map<String, String> _exportedFiles = {};
  Map<String, String> _originalFiles =
      {}; // Store original files for comparison
  Map<String, String> _changedFiles = {}; // Store only changed files
  Map<String, TextEditingController> _fileControllers =
      {}; // For editing YAML files
  Map<String, bool> _fileEditModes = {}; // Track which files are in edit mode
  Map<String, DateTime> _fileValidationTimestamps =
      {}; // Track when files were validated successfully
  Map<String, DateTime> _fileUpdateTimestamps =
      {}; // Track when files were updated/saved locally
  Map<String, DateTime> _fileSyncTimestamps =
      {}; // Track when files were successfully synced to FlutterFlow

  bool _isOutputExpanded = false; // For expandable output section
  bool _hasModifications = false; // Track if modifications have been made
  bool _showRecentProjects = false; // Whether to show recent projects panel
  bool _collapseCredentials =
      false; // Whether to collapse credentials after fetch

  // New state variable for AI Assist panel
  bool _showAIAssist = false;

  // Track which files are expanded
  Set<String> _expandedFiles = {};

  final _projectIdController = TextEditingController();
  final _apiTokenController = TextEditingController();

  // Project name for display in recent projects list
  String _projectName = "";

  // Add a new state field for loading indicator
  bool _isLoading = false;

  // Add a new state field for selected file path
  String? _selectedFilePath;

  // Helper to convert bytes to hex
  String _bytesToHexString(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');
  }

  // Helper to safely call setState only if widget is still mounted
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // Determine if a file has local edits that haven't been synced to FlutterFlow
  bool _hasPendingLocalEdits(String filePath) {
    final updateTs = _fileUpdateTimestamps[filePath];
    if (updateTs == null) return false;
    final syncTs = _fileSyncTimestamps[filePath];
    // Pending when no sync yet, or the last sync is older than last update
    return syncTs == null || syncTs.isBefore(updateTs);
  }

  // Revert local edits for a file back to its original content
  void _revertLocalEdits(String filePath) {
    setState(() {
      if (_originalFiles.containsKey(filePath)) {
        // Restore original content
        _exportedFiles[filePath] = _originalFiles[filePath]!;
      } else {
        // If this was a newly created file, remove it entirely
        _exportedFiles.remove(filePath);
        _changedFiles.remove(filePath);
      }

      // Clear timestamps associated with local edits
      _fileUpdateTimestamps.remove(filePath);
      _fileValidationTimestamps.remove(filePath);
      // Do not clear sync timestamps for files that had previous successful syncs

      // Update operation message
      _operationMessage = 'Discarded local edits for "$filePath".';
      _generatedYamlMessage =
          'Local edits for "$filePath" were discarded. The file has been restored to its previous state.';

      // If file was removed, clear the selection gracefully
      if (!_exportedFiles.containsKey(filePath)) {
        _selectedFilePath = null;
      }
    });
  }

  void _handleYamlFetchError(String message, {bool clearRawContent = false}) {
    final messageWithDocs =
        '$message\n\nNeed help? Review the FlutterFlow API docs: $_flutterFlowDocsUrl';

    setStateIfMounted(() {
      _generatedYamlMessage = messageWithDocs;
      if (clearRawContent) {
        _rawFetchedYaml = null;
        _parsedYamlMap = null;
      }
    });

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(messageWithDocs),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Copy Link',
            textColor: AppTheme.primaryColor,
            onPressed: () {
              Clipboard.setData(
                const ClipboardData(text: _flutterFlowDocsUrl),
              );
              if (!mounted) {
                return;
              }
              final confirmationMessenger = ScaffoldMessenger.of(context);
              confirmationMessenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('Documentation link copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
            },
          ),
        ),
      );
  }

  // Helper to convert YamlMap/YamlList to Dart Map/List
  dynamic _convertYamlNode(dynamic node) {
    if (node is YamlMap) {
      final map = <String, dynamic>{};
      node.nodes.forEach((key, value) {
        if (key is YamlScalar) {
          map[key.value.toString()] = _convertYamlNode(value.value);
        }
      });
      return map;
    } else if (node is YamlList) {
      final list = <dynamic>[];
      for (final value_node in node.nodes) {
        list.add(_convertYamlNode(value_node.value));
      }
      return list;
    }
    return node is YamlScalar ? node.value : node;
  }

  // Helper to escape strings for YAML
  String _escapeStringForYaml(String value) {
    if (value.contains(': ') ||
        value.contains('\n') ||
        value.contains('\r') ||
        value.startsWith(' ') ||
        value.endsWith(' ') ||
        ['true', 'false', 'null'].contains(value.toLowerCase()) ||
        (double.tryParse(value) != null &&
            !value.contains(RegExp(r'[a-zA-Z]'))) ||
        (int.tryParse(value) != null && !value.contains(RegExp(r'[a-zA-Z]')))) {
      return "'${value.replaceAll("'", "''")}'";
    }
    return value;
  }

  // Helper to serialize Dart Map to YAML string
  String _nodeToYamlString(
      dynamic node, int indentLevel, bool isListItemContext) {
    String indent = '  ' * indentLevel;
    StringBuffer buffer = StringBuffer();

    if (node is Map) {
      if (node.isEmpty) return isListItemContext ? '' : '{}';

      if (isListItemContext) {
        bool first = true;
        node.forEach((key, value) {
          String keyString = _escapeStringForYaml(key.toString());
          if (first) {
            buffer.write('$keyString: ');
            String valueString = _nodeToYamlString(value, indentLevel, false);
            buffer.write(valueString);
            first = false;
          } else {
            // For maps as list items, subsequent keys are indented relative to the list item's indent level.
            // The '  ' * indentLevel for the map itself is handled by the list context.
            // We need one more level of indent for these subsequent keys.
            buffer.write('\n${'  ' * indentLevel}$keyString: ');
            String valueString = _nodeToYamlString(value, indentLevel, false);
            buffer.write(valueString);
          }
        });
      } else {
        // Standard map serialization
        node.forEach((key, value) {
          buffer.write('$indent${_escapeStringForYaml(key.toString())}: ');
          if (value is Map && value.isNotEmpty ||
              value is List && value.isNotEmpty) {
            buffer.write('\n');
            buffer.write(_nodeToYamlString(value, indentLevel + 1, false));
          } else {
            buffer.write(_nodeToYamlString(value, indentLevel + 1, false));
          }
          buffer.write('\n');
        });
      }
      return buffer.toString().trimRight();
    } else if (node is List) {
      if (node.isEmpty)
        return isListItemContext ? (indentLevel == 0 ? '[]' : '') : '[]';
      for (int i = 0; i < node.length; i++) {
        var item = node[i];
        buffer.write('$indent- ');
        // When passing a map as a list item, indentLevel for its content should be the list's indentLevel + 1.
        // The _nodeToYamlString for map (when isListItemContext is true) should handle the alignment of the first key.
        String itemString = _nodeToYamlString(item, indentLevel + 1, true);
        buffer.write(itemString);
        if (i < node.length - 1) buffer.write('\n');
      }
      return buffer.toString();
    } else if (node is String) {
      // For very large strings, log their size to debug possible truncation
      if (node.length > 1000) {
        print('DEBUG: Large string value with length ${node.length}');
      }
      return _escapeStringForYaml(node);
    } else if (node == null) {
      return 'null';
    }
    return node.toString();
  }

  String _mapToYamlString(Map<String, dynamic> map) {
    if (map.isEmpty) return '{}';
    return _nodeToYamlString(map, 0, false).trim();
  }

  // Perform a non-destructive merge: keep original keys/sections unless explicitly changed.
  String _nonDestructiveYamlMergeString(
      String originalYaml, String modifiedYaml) {
    try {
      final originalDoc = loadYaml(originalYaml);
      final modifiedDoc = loadYaml(modifiedYaml);

      final original = _convertYamlNode(originalDoc);
      final modified = _convertYamlNode(modifiedDoc);

      final merged = _nonDestructiveMergeNodes(original, modified);

      if (merged is Map<String, dynamic>) {
        return _mapToYamlString(merged);
      } else if (merged is List) {
        // Rare top-level list case
        final mapWrapper = {'root': merged};
        final yaml = _mapToYamlString(mapWrapper);
        // Strip the 'root:' wrapper
        return yaml.replaceFirst(RegExp(r'^root:\s*\n?'), '');
      } else if (merged is String) {
        return merged;
      } else {
        return modifiedYaml; // Fallback
      }
    } catch (e) {
      debugPrint('Non-destructive merge failed: $e');
      return modifiedYaml;
    }
  }

  dynamic _nonDestructiveMergeNodes(dynamic original, dynamic modified) {
    if (modified == null) return original;

    // Map vs Map: deep merge, preserving missing keys from original
    if (original is Map && modified is Map) {
      final result = <String, dynamic>{};
      // Add all modified keys first
      for (final entry in modified.entries) {
        final key = entry.key.toString();
        final modVal = entry.value;
        final origVal = original.containsKey(key) ? original[key] : null;
        result[key] = _nonDestructiveMergeNodes(origVal, modVal);
      }
      // Bring back any keys missing from modified
      for (final entry in original.entries) {
        final key = entry.key.toString();
        if (!result.containsKey(key)) {
          result[key] = entry.value;
        }
      }
      return result;
    }

    // List vs List: try to merge by stable id ('key' or 'id') else prefer modified
    if (original is List && modified is List) {
      Map<String, dynamic>? _indexById(List list) {
        final out = <String, dynamic>{};
        for (final item in list) {
          if (item is Map) {
            final id = (item['key'] ?? item['id']);
            if (id is String && id.isNotEmpty) {
              out[id] = item;
            } else {
              return null; // Not consistently identifiable
            }
          } else {
            return null;
          }
        }
        return out;
      }

      final oIndex = _indexById(original);
      final mIndex = _indexById(modified);
      if (oIndex != null && mIndex != null) {
        final resultList = <dynamic>[];
        // Preserve order given by modified, merging with original elements when same id
        for (final id in mIndex.keys) {
          final modItem = mIndex[id];
          final origItem = oIndex[id];
          resultList.add(_nonDestructiveMergeNodes(origItem, modItem));
        }
        // Append any original items not present in modified to avoid accidental deletions
        for (final id in oIndex.keys) {
          if (!mIndex.containsKey(id)) {
            resultList.add(oIndex[id]);
          }
        }
        return resultList;
      }
      // Fallback: prefer modified list as the intentional source of truth
      return modified;
    }

    // Prefer modified scalar when present
    return modified;
  }

  @override
  void initState() {
    super.initState();
    _projectIdController.addListener(() => setState(() {}));
    _apiTokenController.addListener(() => setState(() {}));

    // Load saved API token
    _loadSavedApiToken();
  }

  // Load API token from shared preferences
  Future<void> _loadSavedApiToken() async {
    final savedApiToken = await PreferencesManager.getApiKey();
    if (savedApiToken != null && savedApiToken.isNotEmpty) {
      setState(() {
        _apiTokenController.text = savedApiToken;
      });
    }
  }

  @override
  void dispose() {
    _projectIdController.dispose();
    _apiTokenController.dispose();

    // Dispose of all file content controllers
    _fileControllers.forEach((fileName, controller) {
      controller.dispose();
    });

    super.dispose();
  }

  // Save API token to shared preferences
  Future<void> _saveApiToken() async {
    final apiToken = _apiTokenController.text;
    if (apiToken.isNotEmpty) {
      await PreferencesManager.saveApiKey(apiToken);
    }
  }

  Future<void> _clearStoredCredentials() async {
    await PreferencesManager.clearCredentials();
    if (!mounted) return;

    setState(() {
      _apiTokenController.clear();
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Stored credentials cleared'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  // Handle selecting a project from recent projects list
  void _handleProjectSelected(String projectId) async {
    // Load the saved API token
    final savedApiToken = await PreferencesManager.getApiKey();

    setState(() {
      _projectIdController.text = projectId;
      if (savedApiToken != null && savedApiToken.isNotEmpty) {
        _apiTokenController.text = savedApiToken;
      }
      _showRecentProjects = false;
    });
  }

  // Apply changes to a file and update modification tracking
  Future<void> _applyFileChanges(String fileName, String newContent,
      {bool validated = false, String? messageOverride}) async {
    final sanitizedName = _normalizeFilePath(fileName);
    String effectiveName = sanitizedName;

    // If the sanitized name differs, move state over to avoid duplicate entries.
    if (sanitizedName != fileName) {
      effectiveName = _renameFileAcrossState(fileName, sanitizedName);
    }

    final contentChanged = _exportedFiles[effectiveName] != newContent;

    setState(() {
      if (contentChanged) {
        // If this is first modification and the file existed before, backup the original
        if (!_originalFiles.containsKey(effectiveName) &&
            _exportedFiles.containsKey(effectiveName)) {
          _originalFiles[effectiveName] = _exportedFiles[effectiveName]!;
        }

        // Update file content
        _exportedFiles[effectiveName] = newContent;
        _changedFiles[effectiveName] = newContent;
        _hasModifications = true;

        // Always track local update timestamp when file content changes
        _fileUpdateTimestamps[effectiveName] = DateTime.now();

        // Update the message to indicate a manual edit was made
        if (messageOverride != null && messageOverride.isNotEmpty) {
          _operationMessage = messageOverride;
          _generatedYamlMessage = messageOverride;
        } else {
          _operationMessage = 'File "$effectiveName" manually edited.';
          _generatedYamlMessage =
              '$_operationMessage\n\nThe file has been updated.';
        }
      }

      // Track validation timestamp when explicitly validated
      if (validated) {
        _fileValidationTimestamps[effectiveName] = DateTime.now();
        if (!contentChanged &&
            (messageOverride == null || messageOverride.isEmpty)) {
          _operationMessage = 'File "$effectiveName" validated.';
          _generatedYamlMessage = '$_operationMessage\n\nValidation passed.';
        }
      }
    });

    // Note: API update is handled by YamlContentViewer after successful validation
  }

  // Helper to auto-expand important files
  void _autoExpandImportantFiles() {
    _expandedFiles.clear();

    // Only expand complete_raw.yaml automatically
    if (_exportedFiles.containsKey('complete_raw.yaml')) {
      _expandedFiles.add('complete_raw.yaml');
    }
  }

  // Build the fallback logo shown when a custom asset is not available.
  Widget _buildFallbackLogo() {
    return Stack(
      children: [
        // FlutterFlow-style logo design
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        Positioned(
          top: 20,
          left: 32,
          child: Container(
            width: 20,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Positioned(
          top: 36,
          left: 16,
          child: Container(
            width: 32,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Central "F" for FlutterFlow
        const Center(
          child: Text(
            'F',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // Build the hero logo container that tries to render a custom asset first,
  // and falls back to a styled placeholder if the asset is missing.
  Widget _buildHeroLogo() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1F2937)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.2),
            offset: const Offset(0, 4),
            blurRadius: 8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.asset(
          _heroImagePath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildFallbackLogo();
          },
        ),
      ),
    );
  }

  Widget _buildSyncedTickIndicator() {
    return Tooltip(
      message: 'Recently synced to FlutterFlow',
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: AppTheme.successColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppTheme.successColor.withOpacity(0.35),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: const Icon(
          Icons.check,
          size: 10,
          color: Colors.white,
        ),
      ),
    );
  }

  Future<void> _fetchProjectYaml() async {
    final projectId = _projectIdController.text;
    final apiToken = _apiTokenController.text;

    if (projectId.isEmpty || apiToken.isEmpty) {
      setState(() {
        _generatedYamlMessage =
            'Error: Project ID and API Token cannot be empty.';
      });
      return;
    }

    // Save API token for future use
    await _saveApiToken();

    setState(() {
      _isLoading = true; // Set loading to true when fetch starts
      _generatedYamlMessage = 'Fetching YAML...';
      _rawFetchedYaml = null;
      _parsedYamlMap = null;
      _exportedFiles.clear();
      _originalFiles.clear();
      _changedFiles.clear();
      _fileControllers.clear(); // Clear any existing file editors
      _fileEditModes.clear();
      _fileValidationTimestamps.clear(); // Clear validation timestamps
      _fileUpdateTimestamps.clear(); // Clear update timestamps
      _fileSyncTimestamps.clear(); // Clear sync timestamps
      _hasModifications = false; // Reset modification state for fresh fetch
      _expandedFiles.clear(); // Clear expanded files state
      _collapseCredentials = true; // Collapse credentials after fetch
    });

    // Declare decodedZipBytes at a higher scope level
    List<int>? decodedZipBytes;

    try {
      final apiUrl = '$_apiBaseUrl/projectYamls?projectId=$projectId';
      print('Fetching YAML from: $apiUrl');

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // Add cache control to prevent caching issues
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      );

      print('YAML fetch response status: ${response.statusCode}');

      final String? contentLengthHeader = response.headers['content-length'];
      print(
          'DEBUG_LOG: API Response Header Content-Length: $contentLengthHeader');
      print(
          'DEBUG_LOG: Actual response.bodyBytes.length: ${response.bodyBytes.length}');
      if (contentLengthHeader != null) {
        final int? parsedContentLength = int.tryParse(contentLengthHeader);
        if (parsedContentLength != null &&
            parsedContentLength != response.bodyBytes.length) {
          print(
              'DEBUG_LOG: WARNING - Mismatch between Content-Length header ($parsedContentLength) and actual received bytes (${response.bodyBytes.length}). Possible JSON truncation.');
        }
      }

      if (response.statusCode == 200) {
        // Save API token and add project to recent projects
        await _saveApiToken();

        // Try to extract project name from response for better display in recent projects
        _projectName = 'Project $projectId'; // Default name using ID

        // Add to recent projects
        await PreferencesManager.addRecentProject(projectId, _projectName);

        final String responseBody = response.body;
        print(
            'DEBUG_LOG: API Raw Response Body (first 2000 chars): ${responseBody.substring(0, responseBody.length > 2000 ? 2000 : responseBody.length)}');

        try {
          Map<String, dynamic>? jsonResponse;
          dynamic parsedJsonData;
          try {
            parsedJsonData = jsonDecode(responseBody);
            if (parsedJsonData is Map<String, dynamic>) {
              jsonResponse = parsedJsonData;

              // Try to extract a better project name if available in the response
              if (jsonResponse.containsKey('project_name')) {
                _projectName = jsonResponse['project_name'] ?? _projectName;
                // Update the project in recent projects with better name
                await PreferencesManager.addRecentProject(
                    projectId, _projectName);
              }
            }
          } on FormatException catch (e) {
            _handleYamlFetchError(
              'Error: API response is not valid JSON.\nDetails: $e',
              clearRawContent: true,
            );
            print('JSON Parsing Error: $e');
            return;
          }

          print('DEBUG_LOG: Parsed JSON type: ${parsedJsonData.runtimeType}');

          if (jsonResponse != null) {
            // New (correct) way to access nested key:
            dynamic valueField = jsonResponse['value'];
            String? projectYamlBytesString;

            if (valueField is Map<String, dynamic>) {
              print('DEBUG_LOG: "value" field is a Map.');
              dynamic projectYamlBytesField = valueField['project_yaml_bytes'];
              if (projectYamlBytesField is String) {
                projectYamlBytesString = projectYamlBytesField;
                print(
                    'DEBUG_LOG: Extracted project_yaml_bytes string length: ${projectYamlBytesString.length}');
                print(
                    'DEBUG_LOG: Extracted project_yaml_bytes string snippet (first 500 chars): ${projectYamlBytesString.substring(0, projectYamlBytesString.length > 500 ? 500 : projectYamlBytesString.length)}');
                print(
                    'DEBUG_LOG: project_yaml_bytes length is multiple of 4: ${projectYamlBytesString.length % 4 == 0}');
                int paddingChars = 0;
                if (projectYamlBytesString.endsWith('==')) {
                  paddingChars = 2;
                } else if (projectYamlBytesString.endsWith('=')) {
                  paddingChars = 1;
                }
                print(
                    'DEBUG_LOG: project_yaml_bytes padding characters: $paddingChars');
              } else {
                print(
                    'DEBUG_LOG: project_yaml_bytes key within "value" object is not a String or is null. Actual type: ${projectYamlBytesField?.runtimeType}');
                if (mounted) {
                  _handleYamlFetchError(
                    'Error: Unexpected data type for project YAML content in API response.',
                    clearRawContent: true,
                  );
                }
                return;
              }
            } else {
              print(
                  'DEBUG_LOG: "value" key not found in JSON response, or it is not a Map. Actual type: ${valueField?.runtimeType}');
              if (mounted) {
                _handleYamlFetchError(
                  'Error: Unexpected API response structure (missing or invalid "value" object).',
                  clearRawContent: true,
                );
              }
              return;
            }

            // Proceed only if projectYamlBytesString was successfully extracted and is not empty
            if (projectYamlBytesString == null ||
                projectYamlBytesString.isEmpty) {
              print(
                  'DEBUG_LOG: project_yaml_bytes string is null or empty after attempted extraction.');
              if (mounted) {
                if (_generatedYamlMessage.startsWith('Fetching YAML...')) {
                  _handleYamlFetchError(
                    'Error: Failed to extract YAML content string from API response.',
                    clearRawContent: true,
                  );
                } else {
                  setStateIfMounted(() {
                    _rawFetchedYaml = null;
                    _parsedYamlMap = null;
                  });
                }
              }
              return;
            }

            // 2. Extract and Decode Base64 String (using projectYamlBytesString)
            try {
              decodedZipBytes = base64Decode(
                  projectYamlBytesString); // Use the extracted and validated string
            } on FormatException catch (e) {
              _handleYamlFetchError(
                'Error: Failed to decode YAML data from API response (Base64 decoding failed).\nDetails: $e',
                clearRawContent: true,
              );
              print('Base64 Decoding Error: $e');
              return;
            }

            print(
                'DEBUG_LOG: Decoded ZIP Bytes Length: ${decodedZipBytes?.length}');
            List<int> snippet = decodedZipBytes?.take(32).toList() ?? [];
            print(
                'DEBUG_LOG: Decoded ZIP Bytes Snippet (Hex, first 32 bytes): ${_bytesToHexString(snippet)}');

            final archive =
                ZipDecoder().decodeBytes(decodedZipBytes!, verify: true);

            print('DEBUG: Archive contains ${archive.files.length} files');

            // Direct approach: extract ALL files from the archive
            for (final file in archive.files) {
              if (file.isFile) {
                print(
                    'DEBUG: Found file in archive: ${file.name} (${file.size} bytes)');

                try {
                  // Extract and decode the file content
                  final fileData = file.content as List<int>;
                  final fileContent =
                      utf8.decode(fileData, allowMalformed: true);

                  // Store the raw content directly
                  _exportedFiles['archive_${file.name}'] = fileContent;

                  // Keep track of the largest YAML file to use as our main content
                  if (file.name.endsWith('.yaml') &&
                      ((_rawFetchedYaml == null) ||
                          (fileContent.length > _rawFetchedYaml!.length))) {
                    _rawFetchedYaml = fileContent;
                    print(
                        'DEBUG: Using larger YAML from archive: ${file.name} (${fileContent.length} chars)');
                  }
                } catch (e) {
                  print('DEBUG: Error extracting file ${file.name}: $e');
                }
              }
            }

            // Find a YAML file if we haven't already
            ArchiveFile? yamlFile;
            for (final file in archive.files) {
              if (file.name == 'project.yaml' && file.isFile) {
                yamlFile = file;
                break;
              }
            }
            if (yamlFile == null) {
              for (final file in archive.files) {
                if (file.name.endsWith('.yaml') && file.isFile) {
                  yamlFile = file;
                  break;
                }
              }
            }

            if (yamlFile != null) {
              final fileData = yamlFile.content as List<int>;
              _rawFetchedYaml = utf8.decode(fileData, allowMalformed: true);
              print(
                  'DEBUG: Original raw YAML file size: ${_rawFetchedYaml?.length ?? 0} chars');

              if (_rawFetchedYaml == null || _rawFetchedYaml!.trim().isEmpty) {
                _handleYamlFetchError(
                  'Error: Extracted YAML file is empty or contains only whitespace.',
                  clearRawContent: true,
                );
              } else {
                // Store the raw YAML directly - don't rely on parsing
                _exportedFiles['complete_raw.yaml'] = _rawFetchedYaml!;
                _parseFetchedYaml();
              }
            } else {
              _handleYamlFetchError(
                'Error: No ".yaml" file (e.g., project.yaml) found in the downloaded ZIP archive.',
                clearRawContent: true,
              );
            }
          } else {
            print('DEBUG_LOG: Parsed JSON is not a Map.');
            _handleYamlFetchError(
              'Error: API response format is not a valid JSON object.',
              clearRawContent: true,
            );
            return;
          }
        } on ArchiveException catch (e) {
          print('ArchiveException: $e');
          if (decodedZipBytes != null) {
            print(
                'DEBUG_LOG: ArchiveException caught (${e.message}). Attempting decode with verify: false for diagnostics...');
            try {
              final archiveNoValidation =
                  ZipDecoder().decodeBytes(decodedZipBytes!, verify: false);
              print(
                  'DEBUG_LOG: ZIP decoding with verify: false succeeded. Archive contains ${archiveNoValidation.numberOfFiles()} files.');
              // Optionally, log file names:
              // print('DEBUG_LOG: Files found (verify: false): ${archiveNoValidation.files.map((f) => f.name).join(', ')}');
            } catch (eNoValidation) {
              print(
                  'DEBUG_LOG: ZIP decoding with verify: false also failed: $eNoValidation');
            }
          }
          // Update the user message logic
          String userErrorMessage =
              'Error: Could not read the fetched YAML package (ArchiveException: ${e.message}).';
          if (e.message
              .contains('Could not find End of Central Directory Record')) {
            userErrorMessage =
                'Error: The fetched YAML package starts correctly but appears to be incomplete or corrupted, as the End of Central Directory Record could not be found. This usually means the data is truncated. Please check the data source or try again.';
          }
          _handleYamlFetchError(
            userErrorMessage,
            clearRawContent: true,
          );
        }
      } else {
        String errorMsg;
        switch (response.statusCode) {
          case 401:
            errorMsg =
                'Error fetching YAML: Unauthorized (401). Please check your API Token.';
            break;
          case 403:
            errorMsg =
                'Error fetching YAML: Forbidden (403). You may not have permission to access this project.';
            break;
          case 404:
            errorMsg =
                'Error fetching YAML: Project not found (404). Please check your Project ID.';
            break;
          default:
            if (response.statusCode >= 500) {
              errorMsg =
                  'Error fetching YAML: Server error (${response.statusCode}). Please try again later.';
            } else {
              errorMsg =
                  'Error fetching YAML: Unexpected network error (${response.statusCode}). Details: ${response.body}';
            }
        }
        _handleYamlFetchError(
          errorMsg,
          clearRawContent: true,
        );
        print('Error fetching YAML (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      setStateIfMounted(() {
        _isLoading = false; // Set loading to false on error
      });
      _handleYamlFetchError(
        'Failed to connect to the server. Please check your internet connection and try again.\nDetails: $e',
        clearRawContent: true,
      );
      print('Exception caught during YAML fetch: $e');
      return;
    }

    // Add a call to prepare files for export after successful fetch
    if (_parsedYamlMap != null) {
      _prepareFilesForExport();
    }

    setState(() {
      _isLoading = false; // Set loading to false when fetch completes
      _expandedFiles.clear(); // Don't auto-expand any files
    });
  }

  void _parseFetchedYaml() {
    setState(() {
      _generatedYamlMessage = 'Parsing YAML...';
    });
    try {
      print(
          'DEBUG: Raw YAML length before parsing: ${_rawFetchedYaml?.length}');

      var loadedData = loadYaml(_rawFetchedYaml!);
      print('DEBUG: Loaded YAML type: ${loadedData.runtimeType}');

      if (loadedData is YamlMap) {
        _parsedYamlMap = _convertYamlNode(loadedData) as Map<String, dynamic>?;
        print(
            'DEBUG: Parsed YAML into map with ${_parsedYamlMap?.length} top-level keys');

        if (_parsedYamlMap != null) {
          // Log the top-level keys for debugging
          print('DEBUG: Top-level keys: ${_parsedYamlMap!.keys.join(', ')}');

          // Try to generate a string version
          try {
            final yamlString = _mapToYamlString(_parsedYamlMap!);
            print('DEBUG: Generated YAML string length: ${yamlString.length}');
            setState(() {
              _generatedYamlMessage = 'Fetched Project YAML:\n\n$yamlString';
            });

            // Now that we've successfully parsed the YAML, auto-expand important files
            _autoExpandImportantFiles();
          } catch (e) {
            print('DEBUG: Error generating YAML string: $e');
            setState(() {
              _generatedYamlMessage =
                  'Successfully parsed YAML but encountered an error displaying it.\nThe files will still be available for export.';
            });
          }
        } else {
          _parsedYamlMap = null;
          _handleYamlFetchError(
            'Error: Could not convert fetched YAML to a readable map format.',
          );
        }
      } else {
        _parsedYamlMap = null;
        _handleYamlFetchError(
          'Error: Fetched data is not in the expected YAML map format. It should be a structured object (key-value pairs).',
        );
      }
    } on YamlException catch (e) {
      _parsedYamlMap = null;
      _handleYamlFetchError(
        'Error: The fetched YAML has an invalid format and could not be read.\nDetails: $e',
      );
      print('YamlException during parsing: $e');
    } catch (e) {
      _parsedYamlMap = null;
      _handleYamlFetchError(
        'An unexpected error occurred while reading the YAML structure.\nDetails: $e',
      );
      print('Unexpected error during YAML parsing: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine if we have credentials filled in
    bool hasCredentials = _projectIdController.text.isNotEmpty &&
        _apiTokenController.text.isNotEmpty;
    bool hasYaml = _exportedFiles.isNotEmpty || _parsedYamlMap != null;

    String projectDisplayName = _projectIdController.text.isNotEmpty
        ? (_projectName.isNotEmpty ? _projectName : _projectIdController.text)
        : "No Project Loaded";

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Custom app header
                  AppHeader(
                    // Hide "New Project" on the home screen when no YAML is loaded
                    onNewProject: hasYaml ? _handleNewProject : null,
                    onReload: hasCredentials ? _fetchProjectYaml : null,
                    onAIAssist: _handleAIAssist,
                    showOnlyNewProject: !hasYaml,
                  ),

                  // Project header if we have YAML loaded
                  if (hasYaml)
                    ProjectHeader(
                      projectName: projectDisplayName,
                    ),

                  // Main content area
                  Expanded(
                    child: !hasYaml
                        ? _buildLoadProjectUI()
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Left panel - Tree or Files list
                                Expanded(
                                  flex: 2,
                                  child: ModernYamlTree(
                                    yamlFiles: _exportedFiles,
                                    onFileSelected: (filePath) {
                                      setState(() {
                                        _selectedFilePath = filePath;
                                      });
                                    },
                                    expandedNodes: _expandedFiles,
                                    validationTimestamps:
                                        _fileValidationTimestamps,
                                    syncTimestamps: _fileSyncTimestamps,
                                    updateTimestamps: _fileUpdateTimestamps,
                                  ),
                                ),

                                const SizedBox(width: 16),

                                // Right panel - YAML Content
                                Expanded(
                                  flex: 3,
                                  child: YamlContentViewer(
                                    content: _selectedFilePath != null
                                        ? _exportedFiles[_selectedFilePath]
                                        : _rawFetchedYaml,
                                    characterCount: _selectedFilePath != null
                                        ? _exportedFiles[_selectedFilePath]
                                            ?.length
                                        : _rawFetchedYaml?.length,
                                    isReadOnly: false,
                                    filePath: _selectedFilePath ?? '',
                                    projectId: _projectIdController.text,
                                    // Show Save/Cancel immediately when a file
                                    // has pending local edits (Unsaved)
                                    hasPendingLocalEdits:
                                        _selectedFilePath != null
                                            ? _hasPendingLocalEdits(
                                                _selectedFilePath!)
                                            : false,
                                    startInEditMode: _selectedFilePath != null
                                        ? _hasPendingLocalEdits(
                                            _selectedFilePath!)
                                        : false,
                                    onDiscardPendingEdits:
                                        _selectedFilePath != null
                                            ? () => _revertLocalEdits(
                                                _selectedFilePath!)
                                            : null,
                                    onContentChanged: _selectedFilePath != null
                                        ? (content) async {
                                            // Content has been validated successfully in YamlContentViewer
                                            await _applyFileChanges(
                                              _selectedFilePath!,
                                              content,
                                              validated: true,
                                            );
                                          }
                                        : null,
                                    onFileRenamed: _handleFileRenamed,
                                    onFileUpdated: _selectedFilePath != null
                                        ? (filePath) {
                                            // Update sync timestamp when file is successfully updated via API
                                            setState(() {
                                              _fileSyncTimestamps[filePath] =
                                                  DateTime.now();
                                              _operationMessage =
                                                  'File "$filePath" saved and synced to FlutterFlow.';
                                              _generatedYamlMessage =
                                                  '$_operationMessage\n\nThe file has been updated in your FlutterFlow project.';
                                            });
                                          }
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
            // Add AI Assist panel
            if (_showAIAssist)
              AIAssistPanel(
                onApplyChanges: _applyAIChanges,
                currentFiles: _exportedFiles,
                onClose: _handleAIAssist,
              ),
          ],
        ),
      ),
    );
  }

  // Widget to display when no project is loaded
  Widget _buildLoadProjectUI() {
    // Determine if we have credentials filled in
    bool hasCredentials = _projectIdController.text.isNotEmpty &&
        _apiTokenController.text.isNotEmpty;

    return Container(
      color: AppTheme.backgroundColor,
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: AppTheme.cardDecoration,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header section
                Column(
                  children: [
                    _buildHeroLogo(),
                    const SizedBox(height: 16),
                    Text(
                      'Load FlutterFlow Project',
                      style: AppTheme.headingLarge.copyWith(fontSize: 28),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your project credentials to get started',
                      style: AppTheme.bodyLarge.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Form section
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Project ID field
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Project ID',
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _projectIdController,
                          decoration: AppTheme.inputDecoration(
                            hintText: 'Enter your FlutterFlow project ID',
                            prefixIcon: const Icon(Icons.folder_outlined),
                          ),
                          style: AppTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // API Token field
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'API Token',
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _apiTokenController,
                          decoration: AppTheme.inputDecoration(
                            hintText: 'Enter your FlutterFlow API token',
                            prefixIcon: const Icon(Icons.key),
                          ),
                          style: AppTheme.bodyMedium,
                          obscureText: true,
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _isLoading ? null : _clearStoredCredentials,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear API & AI tokens'),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Fetch button
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: hasCredentials && !_isLoading
                            ? _fetchProjectYaml
                            : null,
                        icon: _isLoading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.download, size: 18),
                        label: Text(_isLoading ? 'Loading...' : 'Fetch YAML'),
                        style: AppTheme.primaryButtonStyle.copyWith(
                          minimumSize: MaterialStateProperty.all(
                              Size(double.infinity, 48)),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Recent projects section
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.history,
                          size: 18,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Recent Projects',
                          style: AppTheme.headingSmall.copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 180, // Reduced height to prevent overflow
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: AppTheme.dividerColor, width: 1),
                      ),
                      child: RecentProjectsWidget(
                        onProjectSelected: _handleProjectSelected,
                        showHeader: false,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper to export YAML to multiple files
  void _prepareFilesForExport() {
    if (_parsedYamlMap == null && _exportedFiles.isEmpty) return;

    // First log all original sizes for debugging
    print('DEBUG: Original export files:');
    _exportedFiles.forEach((key, value) {
      print('DEBUG: - $key: ${value.length} chars');
    });

    // If we're in modification mode and there are no archive files, don't try to process them
    if (_hasModifications &&
        !_exportedFiles.keys.any((key) => key.startsWith('archive_'))) {
      print(
          'DEBUG: In modification mode with no archive files, skipping file regeneration');

      // Just make sure the _changedFiles are populated
      _changedFiles.clear();
      _changedFiles = Map<String, String>.from(_exportedFiles);
      return;
    }

    // Store archive files in a temporary map to preserve them
    Map<String, String> archiveFiles = {};
    _exportedFiles.forEach((key, value) {
      if (key.startsWith('archive_')) {
        archiveFiles[key] = value;
      }
    });

    // If no archive files are found but we have existing content in specific files, preserve it
    if (archiveFiles.isEmpty) {
      if (_exportedFiles.containsKey('complete_raw.yaml') &&
          _exportedFiles['complete_raw.yaml']!.isNotEmpty) {
        print(
            'DEBUG: No archive files found, preserving existing complete_raw.yaml content');
        archiveFiles['preserved_complete_raw'] =
            _exportedFiles['complete_raw.yaml']!;
      }

      // We no longer need to preserve ALL_CONTENT_COMBINED.yaml
    }

    // Create a combined file with all content
    StringBuffer combinedContent = StringBuffer();
    int totalLength = 0;
    for (var entry in archiveFiles.entries) {
      combinedContent
          .writeln('# FILE: ${entry.key} (${entry.value.length} chars)');
      combinedContent.writeln(entry.value);
      combinedContent.writeln('#--------------------');
      totalLength += entry.value.length;
    }

    // Find the largest file content
    String largestFileName = '';
    String largestContent = '';
    for (var entry in archiveFiles.entries) {
      if (entry.value.length > largestContent.length) {
        largestContent = entry.value;
        largestFileName = entry.key;
      }
    }

    print(
        'DEBUG: Largest archive file is $largestFileName with ${largestContent.length} chars');

    // Now clear the export files (except archive files)
    Map<String, String> nonArchiveFiles = {};
    _exportedFiles.forEach((key, value) {
      if (!key.startsWith('archive_')) {
        nonArchiveFiles[key] = value;
      }
    });

    _exportedFiles.clear();

    // First add back all archive files
    archiveFiles.forEach((key, value) {
      _exportedFiles[key] = value;
    });

    // Add the content to complete_raw.yaml
    String combinedString = combinedContent.toString();
    if (combinedString.isNotEmpty) {
      // Only create complete_raw.yaml, no need for ALL_CONTENT_COMBINED.yaml
      _exportedFiles['complete_raw.yaml'] = combinedString;
      print(
          'DEBUG: Created complete_raw.yaml with ${combinedString.length} chars');
    }

    // And make the largest individual file the raw_project.yaml
    if (largestContent.isNotEmpty) {
      _exportedFiles['raw_project.yaml'] = largestContent;
      print(
          'DEBUG: Set raw_project.yaml to largest file content (${largestContent.length} chars)');
    } else if (_rawFetchedYaml != null) {
      _exportedFiles['raw_project.yaml'] = _rawFetchedYaml!;
      print(
          'DEBUG: Used _rawFetchedYaml for raw_project.yaml (${_rawFetchedYaml!.length} chars)');
    }

    // Add back non-archive files
    nonArchiveFiles.forEach((key, value) {
      if (key != 'complete_raw.yaml' && key != 'raw_project.yaml') {
        _exportedFiles[key] = value;
      }
    });

    // Log the file sizes after regeneration
    print('DEBUG: File sizes after regeneration:');
    _exportedFiles.forEach((key, value) {
      print('DEBUG: - $key: ${value.length} chars');
    });

    // If this is the first load, save as original files
    if (_originalFiles.isEmpty && !_hasModifications) {
      _originalFiles = Map<String, String>.from(_exportedFiles);
      _changedFiles = Map<String, String>.from(_exportedFiles);
    } else if (_hasModifications) {
      // Compare with original files to determine which have changed
      _changedFiles.clear();

      // First add all archive files to changedFiles
      _exportedFiles.forEach((fileName, content) {
        if (fileName.startsWith('archive_')) {
          _changedFiles[fileName] = content;
        }
      });

      // Make sure raw files are always included
      if (_exportedFiles.containsKey('complete_raw.yaml')) {
        _changedFiles['complete_raw.yaml'] =
            _exportedFiles['complete_raw.yaml']!;
      }
      if (_exportedFiles.containsKey('raw_project.yaml')) {
        _changedFiles['raw_project.yaml'] = _exportedFiles['raw_project.yaml']!;
      }

      // First check if we have originalFiles to compare against
      if (_originalFiles.isEmpty) {
        // If no original files are stored (shouldn't happen), treat all as changed
        _exportedFiles.forEach((fileName, content) {
          if (!fileName.startsWith('archive_') &&
              !fileName.contains('raw_project.yaml') &&
              !fileName.contains('complete_raw.yaml')) {
            _changedFiles[fileName] = content;
          }
        });
        print("No original files to compare against. Treating all as changed.");
      } else {
        // Compare each file with its original version
        _exportedFiles.forEach((fileName, content) {
          // Skip archive and raw files as they've already been added
          if (fileName.startsWith('archive_') ||
              fileName.contains('raw_project.yaml') ||
              fileName.contains('complete_raw.yaml')) {
            return;
          }

          if (!_originalFiles.containsKey(fileName)) {
            // New file
            _changedFiles[fileName] = content;
            print("New file detected: $fileName");
          } else if (_originalFiles[fileName] != content) {
            // Changed file
            _changedFiles[fileName] = content;
            print("Modified file detected: $fileName");
          }
        });

        // Check for deleted files
        _originalFiles.forEach((fileName, content) {
          if (!_exportedFiles.containsKey(fileName) &&
              !fileName.startsWith('archive_') &&
              !fileName.contains('raw_project.yaml') &&
              !fileName.contains('complete_raw.yaml')) {
            _changedFiles[fileName] =
                "# This file was removed in the latest changes";
            print("Deleted file detected: $fileName");
          }
        });

        // If no changes were detected but _hasModifications is true,
        // something might be wrong with our comparison logic
        if (_changedFiles.isEmpty && _hasModifications) {
          print(
              "Warning: _hasModifications is true but no changes detected in files!");
          // Force at least the raw project file to show as changed
          if (_exportedFiles.containsKey('raw_project.yaml')) {
            _changedFiles['raw_project.yaml'] =
                _exportedFiles['raw_project.yaml']!;
          } else {
            // Fall back to the full project file
            _changedFiles['full_project.yaml'] =
                _exportedFiles['full_project.yaml']!;
          }
        }
      }
    }

    print(
        "Original files: ${_originalFiles.length}, Export files: ${_exportedFiles.length}, Changed files: ${_changedFiles.length}");

    // Auto-expand important files after they're loaded
    _autoExpandImportantFiles();
  }

  // Helper method to use Flutter's clipboard
  void _fallbackClipboardCopy(
      BuildContext context, String fileName, String fileContent) {
    Clipboard.setData(ClipboardData(text: fileContent)).then((_) {
      print('DEBUG: Flutter clipboard data set successfully');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '$fileName copied to clipboard (${fileContent.length} chars)'),
          duration: Duration(seconds: 2),
        ),
      );
    }).catchError((error) {
      print('DEBUG: Error setting clipboard data: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error copying to clipboard: $error'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    });
  }

  // Handler for New Project button
  void _handleNewProject() {
    setState(() {
      _projectIdController.clear();
      _apiTokenController.clear();
      _rawFetchedYaml = null;
      _parsedYamlMap = null;
      _generatedYamlMessage =
          "Enter Project ID and API Token, then click 'Fetch YAML'.";
      _operationMessage = "";
      _exportedFiles.clear();
      _originalFiles.clear();
      _changedFiles.clear();
      _fileControllers.clear();
      _fileEditModes.clear();
      _fileValidationTimestamps.clear(); // Clear validation timestamps
      _fileUpdateTimestamps.clear(); // Clear update timestamps
      _fileSyncTimestamps.clear(); // Clear sync timestamps
      _hasModifications = false;
    });
  }

  // Handler for Recent Projects button
  void _handleRecentProjects() async {
    // Load the saved API token
    final savedApiToken = await PreferencesManager.getApiKey();

    setState(() {
      if (savedApiToken != null && savedApiToken.isNotEmpty) {
        _apiTokenController.text = savedApiToken;
      }
      _showRecentProjects = true;
    });
  }

  // Handler for AI Assist button
  void _handleAIAssist() {
    setState(() {
      _showAIAssist = !_showAIAssist;
    });
  }

  // Method to handle AI-generated YAML updates
  Future<void> _applyAIChanges(ProposedChange change) async {
    setState(() {
      _generatedYamlMessage = change.summary;
      _operationMessage = "Applied AI changes: ${change.summary}";
    });

    for (var mod in change.modifications) {
      if (!mod.isNewFile && _exportedFiles.containsKey(mod.filePath)) {
        final base = mod.originalContent.isNotEmpty
            ? mod.originalContent
            : _exportedFiles[mod.filePath] ?? '';
        final merged = _nonDestructiveYamlMergeString(base, mod.newContent);
        await _updateYamlFromAI(merged, existingFile: mod.filePath);
      } else {
        await _updateYamlFromAI(mod.newContent,
            existingFile: mod.isNewFile ? null : mod.filePath);
      }
    }

    // Notify user to review and save each file to validate & sync
    try {
      final appliedFiles = change.modifications
          .map((m) => m.filePath)
          .toSet()
          .whereType<String>()
          .toList();
      final fileCount = appliedFiles.length;
      if (mounted && fileCount > 0) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Staged $fileCount file${fileCount == 1 ? '' : 's'} as local edits. Select each file and press Save to validate and sync to FlutterFlow.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
      }
    } catch (_) {}
  }

  Future<void> _updateYamlFromAI(String yamlContent,
      {String? existingFile}) async {
    if (yamlContent.isEmpty) return;

    final inferredPath = YamlFileUtils.inferFilePathFromContent(yamlContent);

    if (existingFile != null && _exportedFiles.containsKey(existingFile)) {
      String targetPath = existingFile;

      if (inferredPath != null && inferredPath != existingFile) {
        setState(() {
          targetPath = _renameFileAcrossState(existingFile, inferredPath);
        });
      }

      // Stage the change first so timestamps are set and the tree shows Unsaved immediately
      await _applyFileChanges(
        targetPath,
        yamlContent,
        validated: false,
        messageOverride:
            'AI-generated changes applied to "$targetPath". Review the changes and click Save to upload to FlutterFlow.',
      );

      // Now update selection and controllers for editing UI
      setState(() {
        _expandedFiles.add(targetPath);
        _selectedFilePath = targetPath;
        final controller =
            _fileControllers[targetPath] ?? TextEditingController();
        controller.text = yamlContent;
        _fileControllers[targetPath] = controller;
      });
    } else {
      // Create a new file with AI-generated content
      final rawDesiredPath = inferredPath ?? _generateTemporaryAiFileName();
      final filePath = _ensureUniqueFilePath(rawDesiredPath);

      // Stage the new file first so Unsaved indicator appears immediately
      await _applyFileChanges(
        filePath,
        yamlContent,
        validated: false,
        messageOverride:
            'AI-generated YAML file "$filePath" created. Review and click Save to upload to FlutterFlow.',
      );

      // Then set selection and editor state
      setState(() {
        _expandedFiles.add(filePath);
        _selectedFilePath = filePath;
        _fileControllers[filePath] = TextEditingController(text: yamlContent);
      });
    }
  }

  String _generateTemporaryAiFileName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'ai_generated_$timestamp.yaml';
  }

  String _normalizeFilePath(String path) {
    final trimmed = path.trim();
    final deduped = _dedupeYamlExtension(trimmed);
    if (deduped.isEmpty) {
      return 'ai_generated_${DateTime.now().millisecondsSinceEpoch}.yaml';
    }
    return deduped.endsWith('.yaml') ? deduped : '$deduped.yaml';
  }

  String _ensureUniqueFilePath(String desiredPath, {String? excludePath}) {
    String candidate = _normalizeFilePath(desiredPath);
    candidate = _dedupeYamlExtension(candidate);
    if (!_exportedFiles.containsKey(candidate) || candidate == excludePath) {
      return candidate;
    }

    final base = candidate.endsWith('.yaml')
        ? candidate.substring(0, candidate.length - 5)
        : candidate;
    int counter = 1;
    String attempt;
    do {
      attempt = '${base}_$counter.yaml';
      counter++;
    } while (_exportedFiles.containsKey(attempt) && attempt != excludePath);

    return attempt;
  }

  String _dedupeYamlExtension(String path) {
    // Collapse repeated ".yaml" suffixes into a single ".yaml"
    return path.replaceFirst(RegExp(r'(\\.yaml)+$'), '.yaml');
  }

  String _renameFileAcrossState(String oldPath, String desiredNewPath) {
    final newPath = _ensureUniqueFilePath(desiredNewPath, excludePath: oldPath);
    if (newPath == oldPath) {
      return oldPath;
    }

    V? moveEntry<V>(Map<String, V> map) {
      if (!map.containsKey(oldPath)) return null;
      final value = map.remove(oldPath);
      if (value != null) {
        map[newPath] = value;
      }
      return value;
    }

    moveEntry(_exportedFiles);
    moveEntry(_originalFiles);
    moveEntry(_changedFiles);
    moveEntry(_fileControllers);
    moveEntry(_fileValidationTimestamps);
    moveEntry(_fileUpdateTimestamps);
    moveEntry(_fileSyncTimestamps);

    if (_expandedFiles.remove(oldPath)) {
      _expandedFiles.add(newPath);
    }

    if (_selectedFilePath == oldPath) {
      _selectedFilePath = newPath;
    }

    return newPath;
  }

  void _handleFileRenamed(String oldPath, String newPath) {
    if (oldPath == newPath) return;

    setState(() {
      final resolvedPath = _renameFileAcrossState(oldPath, newPath);
      if (resolvedPath != oldPath) {
        _operationMessage =
            'Updated file path to "$resolvedPath" to match FlutterFlow requirements.';
        _generatedYamlMessage =
            '$_operationMessage\n\nReview the file and press Save to validate again if needed.';
      }
    });
  }

  // Helper method for consistent button styling
  ButtonStyle _getFileButtonStyle({Color? backgroundColor}) {
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor ?? AppTheme.surfaceColor,
      foregroundColor: Colors.white,
      textStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      elevation: 0,
      shadowColor: Colors.transparent,
      minimumSize: const Size(0, 28),
    );
  }
}
