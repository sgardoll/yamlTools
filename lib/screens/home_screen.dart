import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For utf8 decoding & JSON
import 'package:yaml/yaml.dart';
import 'package:archive/archive.dart'; // For ZIP file handling
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../storage/preferences_manager.dart';
import '../widgets/recent_projects_widget.dart';
import '../widgets/yaml_tree_view.dart'; // Import our new tree view widget
import '../widgets/diff_view_widget.dart'; // Import our diff view widget

// Import web-specific functionality with fallback
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as web; // This will only compile on web

// We're not using conditional imports

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  bool _showExportView = true; // Default to export view
  bool _isOutputExpanded = false; // For expandable output section
  bool _hasModifications = false; // Track if modifications have been made
  bool _showRecentProjects = false; // Whether to show recent projects panel
  bool _collapseCredentials =
      false; // Whether to collapse credentials after fetch

  // Track which files are expanded
  Set<String> _expandedFiles = {};

  final _projectIdController = TextEditingController();
  final _apiTokenController = TextEditingController();

  // Project name for display in recent projects list
  String _projectName = "";

  // Add a new state field to track which view is active
  int _selectedViewIndex =
      1; // 0: export view, 1: tree view (changed to default to tree view)

  // Add a new state field for loading indicator
  bool _isLoading = false;

  // Helper to convert bytes to hex
  String _bytesToHexString(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');
  }

  // Helper to safely call setState only if widget is still mounted
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) setState(fn);
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

  // Handle selecting a project from recent projects list
  void _handleProjectSelected(String projectId) {
    setState(() {
      _projectIdController.text = projectId;
      _showRecentProjects = false;
    });
  }

  // Apply changes to a file and update modification tracking
  void _applyFileChanges(String fileName, String newContent) {
    // Only update if content has actually changed
    if (_exportedFiles[fileName] != newContent) {
      setState(() {
        // If this is first modification, backup the original
        if (!_originalFiles.containsKey(fileName)) {
          _originalFiles[fileName] = _exportedFiles[fileName]!;
        }

        // Update file content
        _exportedFiles[fileName] = newContent;
        _changedFiles[fileName] = newContent;
        _hasModifications = true;

        // Update the message to indicate a manual edit was made
        _operationMessage = 'File "$fileName" manually edited.';
        _generatedYamlMessage =
            '$_operationMessage\n\nThe file has been updated.';
      });
    }
  }

  // Helper to auto-expand important files
  void _autoExpandImportantFiles() {
    _expandedFiles.clear();

    // Only expand complete_raw.yaml automatically
    if (_exportedFiles.containsKey('complete_raw.yaml')) {
      _expandedFiles.add('complete_raw.yaml');
    }
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
      _hasModifications = false; // Reset modification state for fresh fetch
      _expandedFiles.clear(); // Clear expanded files state
      _collapseCredentials = true; // Collapse credentials after fetch
    });

    // Declare decodedZipBytes at a higher scope level
    List<int>? decodedZipBytes;

    try {
      final Uri uri = Uri.parse(
          'https://api.flutterflow.io/v2/projectYamls?projectId=$projectId');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
        },
      );
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
            setState(() {
              _generatedYamlMessage =
                  'Error: API response is not valid JSON.\nDetails: $e';
              _rawFetchedYaml = null;
            });
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
                if (projectYamlBytesString.endsWith('=='))
                  paddingChars = 2;
                else if (projectYamlBytesString.endsWith('=')) paddingChars = 1;
                print(
                    'DEBUG_LOG: project_yaml_bytes padding characters: $paddingChars');
              } else {
                print(
                    'DEBUG_LOG: project_yaml_bytes key within "value" object is not a String or is null. Actual type: ${projectYamlBytesField?.runtimeType}');
                if (mounted) {
                  setState(() {
                    _generatedYamlMessage =
                        'Error: Unexpected data type for project YAML content in API response.';
                    _rawFetchedYaml = null;
                  });
                }
                return;
              }
            } else {
              print(
                  'DEBUG_LOG: "value" key not found in JSON response, or it is not a Map. Actual type: ${valueField?.runtimeType}');
              if (mounted) {
                setState(() {
                  _generatedYamlMessage =
                      'Error: Unexpected API response structure (missing or invalid "value" object).';
                  _rawFetchedYaml = null;
                });
              }
              return;
            }

            // Proceed only if projectYamlBytesString was successfully extracted and is not empty
            if (projectYamlBytesString == null ||
                projectYamlBytesString.isEmpty) {
              print(
                  'DEBUG_LOG: project_yaml_bytes string is null or empty after attempted extraction.');
              if (mounted) {
                setState(() {
                  // Avoid overwriting more specific messages if they were already set
                  if (_generatedYamlMessage.startsWith("Fetching YAML...")) {
                    _generatedYamlMessage =
                        "Error: Failed to extract YAML content string from API response.";
                  }
                  _rawFetchedYaml = null;
                });
              }
              return;
            }

            // 2. Extract and Decode Base64 String (using projectYamlBytesString)
            try {
              decodedZipBytes = base64Decode(
                  projectYamlBytesString); // Use the extracted and validated string
            } on FormatException catch (e) {
              setState(() {
                _generatedYamlMessage =
                    'Error: Failed to decode YAML data from API response (Base64 decoding failed).\nDetails: $e';
                _rawFetchedYaml = null;
              });
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
                setState(() {
                  _generatedYamlMessage =
                      'Error: Extracted YAML file is empty or contains only whitespace.';
                  _rawFetchedYaml = null;
                });
              } else {
                // Store the raw YAML directly - don't rely on parsing
                _exportedFiles['complete_raw.yaml'] = _rawFetchedYaml!;
                _parseFetchedYaml();
              }
            } else {
              setState(() {
                _generatedYamlMessage =
                    'Error: No ".yaml" file (e.g., project.yaml) found in the downloaded ZIP archive.';
                _rawFetchedYaml = null;
              });
            }
          } else {
            print('DEBUG_LOG: Parsed JSON is not a Map.');
            setState(() {
              _generatedYamlMessage =
                  'Error: API response format is not a valid JSON object.';
              _rawFetchedYaml = null;
            });
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
          setStateIfMounted(() {
            _generatedYamlMessage = userErrorMessage;
          });
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
        setState(() {
          _generatedYamlMessage = errorMsg;
        });
        print('Error fetching YAML (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false; // Set loading to false on error
        _generatedYamlMessage =
            'Failed to connect to the server. Please check your internet connection and try again.\nDetails: $e';
      });
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
          setState(() {
            _generatedYamlMessage =
                'Error: Could not convert fetched YAML to a readable map format.';
          });
        }
      } else {
        _parsedYamlMap = null;
        setState(() {
          _generatedYamlMessage =
              'Error: Fetched data is not in the expected YAML map format. It should be a structured object (key-value pairs).';
        });
      }
    } on YamlException catch (e) {
      _parsedYamlMap = null;
      setState(() {
        _generatedYamlMessage =
            'Error: The fetched YAML has an invalid format and could not be read.\nDetails: $e';
      });
      print('YamlException during parsing: $e');
    } catch (e) {
      _parsedYamlMap = null;
      setState(() {
        _generatedYamlMessage =
            'An unexpected error occurred while reading the YAML structure.\nDetails: $e';
      });
      print('Unexpected error during YAML parsing: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine if we have credentials filled in
    bool hasCredentials = _projectIdController.text.isNotEmpty &&
        _apiTokenController.text.isNotEmpty;
    bool hasYaml = _exportedFiles.isNotEmpty || _parsedYamlMap != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('FlutterFlow YAML Tools'),
        actions: [
          if (hasYaml)
            IconButton(
              icon: Icon(Icons.refresh, color: Colors.blue),
              tooltip: 'Reload YAML',
              onPressed: hasCredentials ? _fetchProjectYaml : null,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Recent Projects Panel (conditionally shown)
            if (_showRecentProjects)
              Expanded(
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Recent Projects',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey),
                              onPressed: () {
                                setState(() {
                                  _showRecentProjects = false;
                                });
                              },
                            ),
                          ],
                        ),
                        const Divider(),
                        Expanded(
                          child: RecentProjectsWidget(
                            onProjectSelected: _handleProjectSelected,
                            showHeader: false, // Don't show duplicate header
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_collapseCredentials && hasYaml)
              // Collapsed Credentials (Small button to expand)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.account_circle, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              'Project: ${_projectIdController.text}',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      // Add system file buttons here
                      if (_exportedFiles.keys
                          .any((f) => f.contains('complete_raw.yaml')))
                        _buildTopBarSystemFileButton(
                          'complete_raw.yaml',
                          _exportedFiles.keys.firstWhere(
                              (f) => f.contains('complete_raw.yaml')),
                        ),
                      if (_exportedFiles.keys
                          .any((f) => f.contains('raw_project.yaml')))
                        _buildTopBarSystemFileButton(
                          'raw_project.yaml',
                          _exportedFiles.keys.firstWhere(
                              (f) => f.contains('raw_project.yaml')),
                        ),
                      SizedBox(width: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            icon: Icon(
                              Icons.edit,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: Text(
                              'Edit',
                              style: TextStyle(
                                fontSize: 12,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              elevation: 3,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 0),
                              minimumSize: Size(0, 32),
                            ),
                            onPressed: () {
                              setState(() {
                                _collapseCredentials = false;
                              });
                            },
                          ),
                          SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: Icon(
                              Icons.history,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: Text(
                              'Recent',
                              style: TextStyle(
                                fontSize: 12,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              elevation: 3,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 0),
                              minimumSize: Size(0, 32),
                            ),
                            onPressed: () {
                              setState(() {
                                _showRecentProjects = true;
                              });
                            },
                          ),
                          SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: Icon(
                              Icons.refresh,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: Text(
                              'Reload',
                              style: TextStyle(
                                fontSize: 12,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              elevation: 3,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 0),
                              minimumSize: Size(0, 32),
                            ),
                            onPressed:
                                hasCredentials ? _fetchProjectYaml : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              // Authentication Section (Full form)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('FlutterFlow Credentials',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          ElevatedButton.icon(
                            icon: Icon(
                              Icons.history,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: Text(
                              'Recent',
                              style: TextStyle(
                                fontSize: 12,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              elevation: 3,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 0),
                              minimumSize: Size(0, 32),
                            ),
                            onPressed: () {
                              setState(() {
                                _showRecentProjects = true;
                              });
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      TextField(
                          controller: _projectIdController,
                          decoration: InputDecoration(labelText: 'Project ID')),
                      TextField(
                          controller: _apiTokenController,
                          obscureText: true,
                          decoration: InputDecoration(labelText: 'API Token')),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: hasCredentials && !_isLoading
                                  ? _fetchProjectYaml
                                  : null,
                              child: _isLoading
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text('Fetching...'),
                                      ],
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.download,
                                            color: Colors.white),
                                        SizedBox(width: 8),
                                        Text('Fetch YAML'),
                                      ],
                                    ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          if (hasYaml) ...[
                            SizedBox(width: 8),
                            IconButton(
                              icon: Icon(Icons.arrow_upward),
                              tooltip: 'Collapse',
                              onPressed: () {
                                setState(() {
                                  _collapseCredentials = true;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // Add view selection UI when files are available
            if (_exportedFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Row(
                  children: [
                    Text('View Mode: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Edited Files'),
                      selected: _selectedViewIndex == 0,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedViewIndex = 0);
                      },
                    ),
                    SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Tree View'),
                      selected: _selectedViewIndex == 1,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedViewIndex = 1);
                      },
                    ),
                  ],
                ),
              ),

            // Files display section
            if (hasYaml)
              Expanded(
                child: _selectedViewIndex == 0
                    ? _buildExportFilesView() // Show edited files view
                    : _buildTreeView(), // Show tree view with integrated file editor
              ),
          ],
        ),
      ),
    );
  }

  // New method to build the tree view
  Widget _buildTreeView() {
    return YamlTreeView(
      yamlFiles: _exportedFiles,
      onFileEdited: (String filePath, String newContent) {
        // When a file is edited in the tree view, update it
        _applyFileChanges(filePath, newContent);
      },
      originalFiles: _originalFiles,
      expandedFiles: _expandedFiles, // Pass the expanded files set
    );
  }

  // Existing method renamed for clarity
  Widget _buildFlatFileListView() {
    // Use changedFiles if modifications were made, otherwise use exportedFiles
    Map<String, String> filesToShow =
        _hasModifications ? _changedFiles : _exportedFiles;

    // Filter out system files that we're now showing in the top bar
    Map<String, String> filteredFiles = Map.from(filesToShow);
    filteredFiles.removeWhere((key, value) =>
        key.contains('complete_raw.yaml') || key.contains('raw_project.yaml'));

    // Make sure our key files are shown first
    List<String> orderedKeys = filteredFiles.keys.toList();

    // Add modified_yaml.yaml first if it exists
    if (_hasModifications) {
      orderedKeys.sort((a, b) {
        // Give priority to the modified_yaml.yaml file
        if (a == 'modified_yaml.yaml') return -1;
        if (b == 'modified_yaml.yaml') return 1;
        if (a == 'raw_output.yaml') return -1;
        if (b == 'raw_output.yaml') return 1;
        return a.compareTo(b);
      });
    } else {
      orderedKeys.sort((a, b) {
        // Show archive files first
        if (a.startsWith('archive_') && !b.startsWith('archive_')) return -1;
        if (!a.startsWith('archive_') && b.startsWith('archive_')) return 1;
        return a.compareTo(b);
      });
    }

    // Count modified files for the badge
    int modifiedFilesCount = 0;
    for (var fileName in orderedKeys) {
      String content = filesToShow[fileName] ?? '';

      // Check if file is modified
      if (_originalFiles.containsKey(fileName) &&
          _originalFiles[fileName] != content) {
        modifiedFilesCount++;
      }
    }

    String statusMessage = "Found ${orderedKeys.length} files";

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(statusMessage),
        ),
        Expanded(
          child: filesToShow.isEmpty
              ? Center(
                  child: Text(
                      'No YAML files available. ${_parsedYamlMap != null ? "Enter a prompt to make changes." : ""}'),
                )
              : ListView.builder(
                  itemCount: orderedKeys.length,
                  itemBuilder: (context, index) {
                    String fileName = orderedKeys[index];

                    // Skip compact treatment for system files since they're now in the top bar
                    // if (fileName.contains('complete_raw.yaml') ||
                    //     fileName.contains('raw_project.yaml')) {
                    //   return _buildCompactFileCard(
                    //       fileName, filesToShow[fileName] ?? '');
                    // }

                    String fileContent = filesToShow[fileName] ?? '';
                    bool isExpanded = _expandedFiles.contains(fileName);

                    // Debug file sizes
                    print(
                        'DEBUG: File "$fileName" size: ${fileContent.length} chars');

                    // Determine if file was deleted
                    bool isDeleted = fileContent ==
                        "# This file was removed in the latest changes";

                    // Highlight the complete raw file
                    bool isCompleteRaw = fileName.contains('complete_raw.yaml');

                    // Highlight archive files
                    bool isArchiveFile = fileName.startsWith('archive_');

                    // Prepare or get a TextEditingController for this file if needed
                    if (!_fileControllers.containsKey(fileName)) {
                      _fileControllers[fileName] =
                          TextEditingController(text: fileContent);
                    }

                    bool isEditing = _fileEditModes[fileName] == true;
                    bool wasModified = _originalFiles.containsKey(fileName) &&
                        _originalFiles[fileName] != fileContent;

                    // Get background color based on file type and modified status
                    Color? bgColor;

                    if (wasModified) {
                      bgColor = Colors.yellow[50]; // Highlight modified files
                    } else if (isCompleteRaw) {
                      bgColor = Colors.blue[50]; // Highlight complete raw file
                    } else if (isArchiveFile) {
                      bgColor =
                          Colors.grey[50]; // Subtle highlight for archive files
                    }

                    return Card(
                      color: bgColor,
                      margin: EdgeInsets.all(4.0),
                      child: ExpansionTile(
                        key: Key(
                            fileName), // Use a key to maintain expansion state
                        initiallyExpanded: isExpanded,
                        onExpansionChanged: (expanded) {
                          setState(() {
                            if (expanded) {
                              _expandedFiles.add(fileName);
                            } else {
                              _expandedFiles.remove(fileName);
                            }
                          });
                        },
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                fileName,
                                style: TextStyle(
                                  fontWeight: wasModified || isCompleteRaw
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (wasModified)
                              Chip(
                                label: Text('Modified'),
                                backgroundColor: Colors.yellow[100],
                                labelStyle: TextStyle(fontSize: 10),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${fileContent.length} characters',
                          style: TextStyle(fontSize: 12),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: isEditing
                                ? Column(
                                    children: [
                                      TextField(
                                        controller: _fileControllers[fileName],
                                        maxLines: null,
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        style:
                                            TextStyle(fontFamily: 'monospace'),
                                      ),
                                      SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: [
                                          ElevatedButton.icon(
                                            icon: Icon(Icons.save,
                                                size: 16, color: Colors.white),
                                            label: Text('Save'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                            ),
                                            onPressed: () {
                                              _applyFileChanges(
                                                  fileName,
                                                  _fileControllers[fileName]!
                                                      .text);
                                              setState(() {
                                                _fileEditModes[fileName] =
                                                    false;
                                              });
                                            },
                                          ),
                                          TextButton.icon(
                                            icon: Icon(Icons.cancel,
                                                size: 16, color: Colors.red),
                                            label: Text('Cancel'),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.red,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _fileEditModes[fileName] =
                                                    false;
                                                _fileControllers[fileName]!
                                                        .text =
                                                    filesToShow[fileName] ?? '';
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : GestureDetector(
                                    onTap: () {
                                      // Enter edit mode when text is clicked
                                      setState(() {
                                        _fileEditModes[fileName] = true;
                                        _fileControllers[fileName]!.text =
                                            fileContent;
                                      });
                                    },
                                    child: Container(
                                      color: Colors
                                          .transparent, // Makes the entire area tappable
                                      width: double.infinity,
                                      child: SingleChildScrollView(
                                        child: Text(
                                          fileContent,
                                          style: TextStyle(
                                              fontFamily: 'monospace'),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Existing method for the export files view
  Widget _buildExportFilesView() {
    // Use changedFiles if modifications were made, otherwise use exportedFiles
    Map<String, String> filesToShow =
        _hasModifications ? _changedFiles : _exportedFiles;

    // Filter out system files that we're now showing in the top bar
    Map<String, String> filteredFiles = Map.from(filesToShow);
    filteredFiles.removeWhere((key, value) =>
        key.contains('complete_raw.yaml') || key.contains('raw_project.yaml'));

    // Make sure our key files are shown first
    List<String> orderedKeys = filteredFiles.keys.toList();

    // Add modified_yaml.yaml first if it exists
    if (_hasModifications) {
      orderedKeys.sort((a, b) {
        // Give priority to the modified_yaml.yaml file
        if (a == 'modified_yaml.yaml') return -1;
        if (b == 'modified_yaml.yaml') return 1;
        if (a == 'raw_output.yaml') return -1;
        if (b == 'raw_output.yaml') return 1;
        return a.compareTo(b);
      });
    } else {
      orderedKeys.sort((a, b) {
        // Show archive files first
        if (a.startsWith('archive_') && !b.startsWith('archive_')) return -1;
        if (!a.startsWith('archive_') && b.startsWith('archive_')) return 1;
        return a.compareTo(b);
      });
    }

    // Count modified files for the badge
    int modifiedFilesCount = 0;
    for (var fileName in orderedKeys) {
      String content = filesToShow[fileName] ?? '';
      print('DEBUG: Available file: $fileName (${content.length} chars)');

      // Check if file is modified
      if (_originalFiles.containsKey(fileName) &&
          _originalFiles[fileName] != content) {
        modifiedFilesCount++;
      }
    }

    String statusMessage = "Found ${orderedKeys.length} files";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Row(
              children: [
                Text(_hasModifications ? 'Changed Files' : 'Export Files',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (modifiedFilesCount > 0)
                  Container(
                    margin: EdgeInsets.only(left: 8),
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$modifiedFilesCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: 8),
            Text(statusMessage,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            Spacer(),
          ],
        ),
        SizedBox(height: 8),
        Expanded(
          child: filesToShow.isEmpty
              ? Center(
                  child: Text(
                      'No YAML files available. ${_parsedYamlMap != null ? "Enter a prompt to make changes." : ""}'),
                )
              : ListView.builder(
                  itemCount: orderedKeys.length,
                  itemBuilder: (context, index) {
                    String fileName = orderedKeys[index];

                    // Skip compact treatment for system files since they're now in the top bar
                    // if (fileName.contains('complete_raw.yaml') ||
                    //     fileName.contains('raw_project.yaml')) {
                    //   return _buildCompactFileCard(
                    //       fileName, filesToShow[fileName] ?? '');
                    // }

                    String fileContent = filesToShow[fileName] ?? '';
                    bool isExpanded = _expandedFiles.contains(fileName);

                    // Debug file sizes
                    print(
                        'DEBUG: File "$fileName" size: ${fileContent.length} chars');

                    // Determine if file was deleted
                    bool isDeleted = fileContent ==
                        "# This file was removed in the latest changes";

                    // Highlight the complete raw file
                    bool isCompleteRaw = fileName.contains('complete_raw.yaml');

                    // Highlight archive files
                    bool isArchiveFile = fileName.startsWith('archive_');

                    // Prepare or get a TextEditingController for this file if needed
                    if (!_fileControllers.containsKey(fileName)) {
                      _fileControllers[fileName] =
                          TextEditingController(text: fileContent);
                    }

                    bool isEditing = _fileEditModes[fileName] == true;
                    bool wasModified = _originalFiles.containsKey(fileName) &&
                        _originalFiles[fileName] != fileContent;

                    // Get background color based on file type and modified status
                    Color? bgColor;
                    if (isDeleted) {
                      bgColor = Colors.red[50];
                    } else if (wasModified) {
                      bgColor = Colors.amber[50]; // Modified files are amber
                    } else if (isArchiveFile) {
                      bgColor = Colors.green[50];
                    } else if (isCompleteRaw) {
                      bgColor = Colors.blue[50];
                    }

                    return Card(
                      margin: EdgeInsets.only(bottom: 16),
                      // Highlight based on file type and status
                      color: bgColor,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedFiles.remove(fileName);
                                } else {
                                  _expandedFiles.add(fileName);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(
                                          isExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: wasModified
                                              ? Colors.amber[800]
                                              : (isArchiveFile
                                                  ? Colors.green[800]
                                                  : (isCompleteRaw
                                                      ? Colors.blue[800]
                                                      : null)),
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  isArchiveFile
                                                      ? fileName.replaceFirst(
                                                          'archive_', '')
                                                      : fileName,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: isDeleted
                                                        ? Colors.red
                                                        : (wasModified
                                                            ? Colors.amber[800]
                                                            : (isArchiveFile
                                                                ? Colors
                                                                    .green[800]
                                                                : (isCompleteRaw
                                                                    ? Colors
                                                                        .blue[800]
                                                                    : null))),
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Text(
                                                ' (${fileContent.length} chars)',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              if (wasModified)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 4.0),
                                                  child: Icon(
                                                    Icons.edit_document,
                                                    size: 16,
                                                    color: Colors.amber[800],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      // Allow editing for all files when expanded
                                      if (isExpanded)
                                        isEditing
                                            ? ElevatedButton.icon(
                                                icon: Icon(Icons.save,
                                                    size: 16,
                                                    color: Colors.white),
                                                label: Text('Save'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                  foregroundColor: Colors.white,
                                                ),
                                                onPressed: () {
                                                  _applyFileChanges(
                                                      fileName,
                                                      _fileControllers[
                                                              fileName]!
                                                          .text);
                                                  setState(() {
                                                    _fileEditModes[fileName] =
                                                        false;
                                                  });
                                                },
                                              )
                                            : ElevatedButton.icon(
                                                icon: Icon(
                                                  Icons.edit,
                                                  size: 16,
                                                  color: Colors.white,
                                                ),
                                                label: Text(
                                                  'Edit',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.blue,
                                                  foregroundColor: Colors.white,
                                                  elevation: 3,
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 0),
                                                  minimumSize: Size(0, 32),
                                                ),
                                                onPressed: () {
                                                  // Enter edit mode
                                                  setState(() {
                                                    _fileEditModes[fileName] =
                                                        true;
                                                    _fileControllers[fileName]!
                                                        .text = fileContent;
                                                  });
                                                },
                                              ),
                                      // Copy button
                                      ElevatedButton.icon(
                                        icon: Icon(Icons.copy,
                                            size: 16, color: Colors.white),
                                        label: Text('Copy',
                                            style: TextStyle(fontSize: 12)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 0),
                                          minimumSize: Size(0, 32),
                                        ),
                                        onPressed: () {
                                          _fallbackClipboardCopy(
                                              context, fileName, fileContent);
                                        },
                                      ),
                                      SizedBox(width: 8),
                                      // Make View button more prominent
                                      ElevatedButton.icon(
                                        icon: Icon(Icons.visibility,
                                            size: 16, color: Colors.white),
                                        label: Text('View',
                                            style: TextStyle(fontSize: 12)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 0),
                                          minimumSize: Size(0, 32),
                                        ),
                                        onPressed: () {
                                          // Switch to tree view and select this file
                                          setState(() {
                                            _selectedViewIndex =
                                                1; // Switch to tree view
                                            _expandedFiles.add(
                                                fileName); // Mark as expanded
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isExpanded) ...[
                            Divider(height: 1),
                            Container(
                              // More flexible height based on content
                              constraints: BoxConstraints(
                                minHeight: 150,
                                maxHeight: 300,
                              ),
                              padding: EdgeInsets.all(8.0),
                              color: isDeleted
                                  ? Colors.red[50]
                                  : (wasModified
                                      ? Colors.amber[50]
                                      : (isArchiveFile
                                          ? Colors.green[50]
                                          : (isCompleteRaw
                                              ? Colors.blue[50]
                                              : Colors.grey[50]))),
                              child: isEditing
                                  ? TextField(
                                      controller: _fileControllers[fileName],
                                      maxLines: null,
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        hintText: 'Edit YAML content...',
                                      ),
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 14,
                                      ),
                                    )
                                  : wasModified
                                      ? DiffViewWidget(
                                          originalContent:
                                              _originalFiles[fileName] ?? '',
                                          modifiedContent: fileContent,
                                          fileName: fileName,
                                          onClose: () {
                                            setState(() {
                                              _expandedFiles.remove(fileName);
                                            });
                                          },
                                        )
                                      : GestureDetector(
                                          onTap: () {
                                            // Enter edit mode when text is clicked
                                            setState(() {
                                              _fileEditModes[fileName] = true;
                                              _fileControllers[fileName]!.text =
                                                  fileContent;
                                            });
                                          },
                                          child: Container(
                                            color: Colors
                                                .transparent, // Makes the entire area tappable
                                            width: double.infinity,
                                            child: SingleChildScrollView(
                                              child: Text(
                                                fileContent,
                                                style: TextStyle(
                                                    fontFamily: 'monospace'),
                                              ),
                                            ),
                                          ),
                                        ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
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

    setState(() {
      _showExportView = true;
    });

    // Auto-expand important files after they're loaded
    _autoExpandImportantFiles();
  }

  // Toggle between export view and normal view
  void _toggleExportView() {
    setState(() {
      _showExportView = !_showExportView;
    });
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

  // New method to build a compact file card for important system files
  Widget _buildCompactFileCard(String fileName, String content) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.description, size: 16, color: Colors.blue[800]),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                fileName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.blue[800],
                ),
              ),
            ),
            Text(
              '${content.length} chars',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            SizedBox(width: 8),
            ElevatedButton(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy, size: 16, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Copy', style: TextStyle(fontSize: 12)),
                ],
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: Size(0, 32),
              ),
              onPressed: () {
                _fallbackClipboardCopy(context, fileName, content);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Add new helper method for system file buttons in the top bar
  Widget _buildTopBarSystemFileButton(String displayName, String filePath) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ElevatedButton.icon(
        icon: Icon(
          Icons.description,
          size: 16,
          color: Colors.white,
        ),
        label: Text(
          displayName.replaceAll('.yaml', ''),
          style: TextStyle(
            fontSize: 12,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 3,
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          minimumSize: Size(0, 32),
        ),
        onPressed: () {
          // Switch to tree view and select this file
          setState(() {
            _selectedViewIndex = 1; // Switch to tree view
            _expandedFiles.add(filePath); // Mark as expanded
          });
        },
      ),
    );
  }
}
