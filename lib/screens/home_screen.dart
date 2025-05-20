import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For utf8 decoding & JSON
import 'package:yaml/yaml.dart';
import 'package:archive/archive.dart'; // For ZIP file handling
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../storage/preferences_manager.dart';
import '../widgets/recent_projects_widget.dart';

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
  final _promptController = TextEditingController();

  // Project name for display in recent projects list
  String _projectName = "";

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
    _promptController.addListener(() => setState(() {}));

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
    _promptController.dispose();

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

    // Always expand the combined file if it exists
    if (_exportedFiles.containsKey('ALL_CONTENT_COMBINED.yaml')) {
      _expandedFiles.add('ALL_CONTENT_COMBINED.yaml');
      print(
          'DEBUG: Auto-expanded ALL_CONTENT_COMBINED.yaml with ${_exportedFiles['ALL_CONTENT_COMBINED.yaml']?.length ?? 0} chars');
    }

    // And also expand complete_raw.yaml
    if (_exportedFiles.containsKey('complete_raw.yaml')) {
      _expandedFiles.add('complete_raw.yaml');
    }

    // Find the largest archive files to expand
    List<MapEntry<String, String>> archiveEntries = _exportedFiles.entries
        .where((entry) => entry.key.startsWith('archive_'))
        .toList();

    // Sort by content length (largest first)
    archiveEntries.sort((a, b) => b.value.length.compareTo(a.value.length));

    // Only expand the largest 1-2 archive files
    List<String> largestFiles =
        archiveEntries.take(2).map((entry) => entry.key).toList();

    if (largestFiles.isNotEmpty) {
      _expandedFiles.addAll(largestFiles);
      print(
          'DEBUG: Auto-expanded ${largestFiles.length} largest archive files:');
      for (String fileName in largestFiles) {
        print(
            'DEBUG: - $fileName (${_exportedFiles[fileName]?.length ?? 0} chars)');
      }
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
        _generatedYamlMessage =
            'Failed to connect to the server. Please check your internet connection and try again.\nDetails: $e';
      });
      print('Exception caught during YAML fetch: $e');
    }

    // Add a call to prepare files for export after successful fetch
    if (_parsedYamlMap != null) {
      _prepareFilesForExport();
    }
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

  void _processPromptAndGenerateYaml() {
    if (_parsedYamlMap == null) {
      setState(() {
        _generatedYamlMessage =
            'Cannot process prompt: YAML data is not available or not correctly formatted. Please fetch valid YAML first.';
      });
      return;
    }
    final currentPrompt = _promptController.text;
    if (currentPrompt.isEmpty) {
      setState(() {
        _generatedYamlMessage =
            'Error: Prompt is empty. Please enter a modification instruction.';
      });
      return;
    }

    // Backup all archive files before modifications
    Map<String, String> archiveBackup = {};
    _exportedFiles.forEach((key, value) {
      if (key.startsWith('archive_')) {
        archiveBackup[key] = value;
      }
    });

    // Also backup the combined content
    String? combinedContentBackup = _exportedFiles['ALL_CONTENT_COMBINED.yaml'];

    // Find and backup the largest file for later restoration
    String largestContent = "";
    String largestFileName = "";
    archiveBackup.forEach((key, value) {
      if (value.length > largestContent.length) {
        largestContent = value;
        largestFileName = key;
      }
    });

    if (largestContent.isNotEmpty) {
      print(
          'DEBUG: Backed up largest file ($largestFileName) with ${largestContent.length} chars');
    }

    // Store a copy of the existing files before modification
    Map<String, String> preModificationFiles =
        Map<String, String>.from(_exportedFiles);

    setState(() {
      _generatedYamlMessage = 'Processing prompt...';
      _operationMessage = ''; // Reset operation message
      _hasModifications =
          true; // Set flag to indicate modifications are being made

      // Clear changed files to start fresh
      _changedFiles.clear();
    });

    Future.delayed(Duration(milliseconds: 50), () {
      final promptTrimmed = currentPrompt.trim().toLowerCase();

      // Use string manipulation instead of RegExp for better reliability
      bool isSetProjectName = promptTrimmed.startsWith('set project name to');
      bool isCreatePage = promptTrimmed.startsWith('create page') ||
          promptTrimmed.startsWith('add page');
      bool isSetBgColor = promptTrimmed.contains('background color') &&
          promptTrimmed.contains(' to ');

      // New command types
      bool isDeletePage = promptTrimmed.startsWith('delete page') ||
          promptTrimmed.startsWith('remove page');
      bool isAddWidget = promptTrimmed.startsWith('add widget') &&
          promptTrimmed.contains(' to page ');
      bool isSetThemeColor = promptTrimmed.startsWith('set theme color') &&
          promptTrimmed.contains(' to ');
      bool isSetAppTitle = promptTrimmed.startsWith('set app title to');

      _parsedYamlMap =
          Map<String, dynamic>.from(_parsedYamlMap!); // Ensure mutable

      if (isSetProjectName) {
        final newName =
            promptTrimmed.substring('set project name to'.length).trim();
        if (newName.isEmpty) {
          _operationMessage = 'Error: New project name cannot be empty.';
        } else {
          _parsedYamlMap!['projectName'] = newName;
          _operationMessage = 'Project name set to "$newName".';
        }
      } else if (isCreatePage) {
        String pageName = '';
        if (promptTrimmed.startsWith('create page')) {
          pageName = promptTrimmed.substring('create page'.length).trim();
        } else {
          // add page
          pageName = promptTrimmed.substring('add page'.length).trim();
        }

        // Remove quotes if present
        if ((pageName.startsWith("'") && pageName.endsWith("'")) ||
            (pageName.startsWith('"') && pageName.endsWith('"'))) {
          pageName = pageName.substring(1, pageName.length - 1);
        }

        if (pageName.isEmpty) {
          _operationMessage = 'Error: Page name cannot be empty for creation.';
        } else {
          if (!_parsedYamlMap!.containsKey('pages')) {
            _parsedYamlMap!['pages'] = [];
          }
          var pagesEntry = _parsedYamlMap!['pages'];
          if (pagesEntry is! List) {
            _operationMessage =
                "Error: 'pages' entry exists but is not a list. Cannot add page.";
          } else {
            List<Map<String, dynamic>> typedPagesList = [];
            bool conversionSuccess = true;
            for (var item in pagesEntry) {
              if (item is Map) {
                typedPagesList.add(Map<String, dynamic>.from(item));
              } else {
                conversionSuccess = false;
                break;
              }
            }
            if (!conversionSuccess) {
              _operationMessage =
                  "Error: 'pages' list contains elements that are not valid page objects (maps).";
            } else {
              _parsedYamlMap!['pages'] = typedPagesList;
              bool pageExists = typedPagesList.any((p) =>
                  p['name']?.toString().toLowerCase() ==
                  pageName.toLowerCase());
              if (pageExists) {
                _operationMessage =
                    'Error: Page named "$pageName" already exists.';
              } else {
                typedPagesList.add({'name': pageName, 'widgets': []});
                _parsedYamlMap!['pages'] = typedPagesList;
                _operationMessage = 'Page "$pageName" created successfully.';
              }
            }
          }
        }
      } else if (isSetBgColor) {
        String pageName = '';
        String colorValue = '';

        try {
          // Extract page name - assuming format "background color of PAGE to COLOR"
          if (promptTrimmed.contains("background color of ")) {
            pageName = promptTrimmed
                .split("background color of ")[1]
                .split(" to ")[0]
                .trim();
            colorValue = promptTrimmed.split(" to ")[1].trim();
          }
          // Also handle "bg color of PAGE to COLOR" format
          else if (promptTrimmed.contains("bg color of ")) {
            pageName =
                promptTrimmed.split("bg color of ")[1].split(" to ")[0].trim();
            colorValue = promptTrimmed.split(" to ")[1].trim();
          }

          // Remove quotes if present
          if ((pageName.startsWith("'") && pageName.endsWith("'")) ||
              (pageName.startsWith('"') && pageName.endsWith('"'))) {
            pageName = pageName.substring(1, pageName.length - 1);
          }

          if ((colorValue.startsWith("'") && colorValue.endsWith("'")) ||
              (colorValue.startsWith('"') && colorValue.endsWith('"'))) {
            colorValue = colorValue.substring(1, colorValue.length - 1);
          }
        } catch (e) {
          _operationMessage =
              'Error parsing background color command. Format should be: "set background color of PAGE to COLOR"';
          return;
        }

        if (!_parsedYamlMap!.containsKey('pages') ||
            _parsedYamlMap!['pages'] is! List ||
            (_parsedYamlMap!['pages'] as List).isEmpty) {
          _operationMessage =
              'Error: No pages found or "pages" is not a valid list. Cannot set background color.';
        } else {
          var pagesList = _parsedYamlMap!['pages'] as List;
          int pageIndex = -1;
          Map<String, dynamic>? pageToUpdate;
          for (int i = 0; i < pagesList.length; i++) {
            var page = pagesList[i];
            if (page is Map &&
                page.containsKey('name') &&
                page['name']?.toString().toLowerCase() ==
                    pageName.toLowerCase()) {
              pageToUpdate = Map<String, dynamic>.from(page);
              pageIndex = i;
              break;
            }
          }
          if (pageToUpdate != null && pageIndex != -1) {
            pageToUpdate['backgroundColor'] = colorValue;
            pagesList[pageIndex] = pageToUpdate;
            _parsedYamlMap!['pages'] = pagesList;
            _operationMessage =
                'Background color of page "$pageName" set to "$colorValue".';
          } else {
            _operationMessage = 'Error: Page named "$pageName" not found.';
          }
        }
      }
      // New command handlers
      else if (isDeletePage) {
        String pageName = '';
        if (promptTrimmed.startsWith('delete page')) {
          pageName = promptTrimmed.substring('delete page'.length).trim();
        } else {
          // remove page
          pageName = promptTrimmed.substring('remove page'.length).trim();
        }

        // Remove quotes if present
        if ((pageName.startsWith("'") && pageName.endsWith("'")) ||
            (pageName.startsWith('"') && pageName.endsWith('"'))) {
          pageName = pageName.substring(1, pageName.length - 1);
        }

        if (pageName.isEmpty) {
          _operationMessage = 'Error: Page name cannot be empty for deletion.';
        } else if (!_parsedYamlMap!.containsKey('pages') ||
            _parsedYamlMap!['pages'] is! List ||
            (_parsedYamlMap!['pages'] as List).isEmpty) {
          _operationMessage =
              'Error: No pages found or "pages" is not a valid list. Cannot delete page.';
        } else {
          var pagesList = _parsedYamlMap!['pages'] as List;
          int pageIndexToDelete = -1;

          for (int i = 0; i < pagesList.length; i++) {
            var page = pagesList[i];
            if (page is Map &&
                page.containsKey('name') &&
                page['name']?.toString().toLowerCase() ==
                    pageName.toLowerCase()) {
              pageIndexToDelete = i;
              break;
            }
          }

          if (pageIndexToDelete != -1) {
            pagesList.removeAt(pageIndexToDelete);
            _parsedYamlMap!['pages'] = pagesList;
            _operationMessage = 'Page "$pageName" deleted successfully.';
          } else {
            _operationMessage = 'Error: Page named "$pageName" not found.';
          }
        }
      } else if (isAddWidget) {
        try {
          // Format: "add widget TYPE with PROPERTIES to page PAGENAME"
          // Example: "add widget button with text:Click me,color:blue to page homepage"

          // First get the widget part and page name part
          var parts = promptTrimmed.split(' to page ');
          if (parts.length != 2) {
            throw Exception('Invalid format');
          }

          String pageName = parts[1].trim();
          // Remove quotes if present
          if ((pageName.startsWith("'") && pageName.endsWith("'")) ||
              (pageName.startsWith('"') && pageName.endsWith('"'))) {
            pageName = pageName.substring(1, pageName.length - 1);
          }

          // Now parse the widget part
          var widgetPart = parts[0].substring('add widget '.length);
          var widgetTypeParts = widgetPart.split(' with ');
          String widgetType = widgetTypeParts[0].trim();
          Map<String, String> properties = {};

          // If there are properties, parse them
          if (widgetTypeParts.length > 1) {
            var propertiesList = widgetTypeParts[1].split(',');
            for (var property in propertiesList) {
              var keyValue = property.split(':');
              if (keyValue.length == 2) {
                properties[keyValue[0].trim()] = keyValue[1].trim();
              }
            }
          }

          // Find the page to add the widget to
          if (!_parsedYamlMap!.containsKey('pages') ||
              _parsedYamlMap!['pages'] is! List ||
              (_parsedYamlMap!['pages'] as List).isEmpty) {
            _operationMessage =
                'Error: No pages found or "pages" is not a valid list. Cannot add widget.';
            return;
          }

          var pagesList = _parsedYamlMap!['pages'] as List;
          int pageIndex = -1;
          Map<String, dynamic>? pageToUpdate;

          for (int i = 0; i < pagesList.length; i++) {
            var page = pagesList[i];
            if (page is Map &&
                page.containsKey('name') &&
                page['name']?.toString().toLowerCase() ==
                    pageName.toLowerCase()) {
              pageToUpdate = Map<String, dynamic>.from(page);
              pageIndex = i;
              break;
            }
          }

          if (pageToUpdate != null && pageIndex != -1) {
            // Make sure widgets list exists
            if (!pageToUpdate.containsKey('widgets')) {
              pageToUpdate['widgets'] = [];
            }

            // Create the widget object
            Map<String, dynamic> widgetObject = {
              'type': widgetType,
              'properties': properties
            };

            // Add a unique id for the widget
            widgetObject['id'] =
                'widget_${DateTime.now().millisecondsSinceEpoch}';

            // Add the widget to the page
            List widgetsList = pageToUpdate['widgets'] as List;
            widgetsList.add(widgetObject);
            pageToUpdate['widgets'] = widgetsList;

            // Update the page in the pages list
            pagesList[pageIndex] = pageToUpdate;
            _parsedYamlMap!['pages'] = pagesList;

            _operationMessage =
                'Added "$widgetType" widget to page "$pageName" with ${properties.length} properties.';
          } else {
            _operationMessage = 'Error: Page named "$pageName" not found.';
          }
        } catch (e) {
          _operationMessage =
              'Error parsing add widget command. Format should be: "add widget TYPE with PROP1:VALUE1,PROP2:VALUE2 to page PAGENAME"';
        }
      } else if (isSetThemeColor) {
        try {
          // Format: "set theme color PRIMARY to #FF0000"
          String colorType = '';
          String colorValue = '';

          // Extract color type and value
          var parts = promptTrimmed.split(' to ');
          if (parts.length != 2) {
            throw Exception('Invalid format');
          }

          colorValue = parts[1].trim();
          // Remove quotes if present
          if ((colorValue.startsWith("'") && colorValue.endsWith("'")) ||
              (colorValue.startsWith('"') && colorValue.endsWith('"'))) {
            colorValue = colorValue.substring(1, colorValue.length - 1);
          }

          colorType = parts[0].substring('set theme color '.length).trim();

          // Make sure theme object exists
          if (!_parsedYamlMap!.containsKey('theme')) {
            _parsedYamlMap!['theme'] = {};
          }

          var theme = _parsedYamlMap!['theme'];
          if (theme is! Map) {
            _parsedYamlMap!['theme'] = {};
            theme = _parsedYamlMap!['theme'];
          }

          // Update the appropriate theme color
          Map<String, dynamic> themeMap = Map<String, dynamic>.from(theme);

          switch (colorType) {
            case 'primary':
              themeMap['primaryColor'] = colorValue;
              break;
            case 'secondary':
              themeMap['secondaryColor'] = colorValue;
              break;
            case 'background':
              themeMap['backgroundColor'] = colorValue;
              break;
            case 'text':
              themeMap['textColor'] = colorValue;
              break;
            default:
              themeMap[colorType + 'Color'] = colorValue;
          }

          _parsedYamlMap!['theme'] = themeMap;
          _operationMessage = 'Theme $colorType color set to "$colorValue".';
        } catch (e) {
          _operationMessage =
              'Error parsing theme color command. Format should be: "set theme color TYPE to COLOR"';
        }
      } else if (isSetAppTitle) {
        final newTitle =
            promptTrimmed.substring('set app title to'.length).trim();
        if (newTitle.isEmpty) {
          _operationMessage = 'Error: New app title cannot be empty.';
        } else {
          // Make sure app metadata exists
          if (!_parsedYamlMap!.containsKey('appInfo')) {
            _parsedYamlMap!['appInfo'] = {};
          }

          var appInfo = _parsedYamlMap!['appInfo'];
          if (appInfo is! Map) {
            _parsedYamlMap!['appInfo'] = {};
            appInfo = _parsedYamlMap!['appInfo'];
          }

          Map<String, dynamic> appInfoMap = Map<String, dynamic>.from(appInfo);
          appInfoMap['title'] = newTitle;
          _parsedYamlMap!['appInfo'] = appInfoMap;

          _operationMessage = 'App title set to "$newTitle".';
        }
      } else {
        _operationMessage = 'Prompt not recognized. Examples:\n'
            '- Set project name to MyNewApp\n'
            '- Create page \'UserProfile\'\n'
            '- Add page "SettingsPage"\n'
            '- Set background color of page "UserProfile" to "blue"\n'
            '- Delete page "OldPage"\n'
            '- Add widget button with text:Click me,color:blue to page homepage\n'
            '- Set theme color primary to "#FF5722"\n'
            '- Set app title to "My Awesome App"';
      }

      try {
        final yamlString = _mapToYamlString(_parsedYamlMap!);

        // Clear the changed files before adding new ones
        _changedFiles.clear();

        setState(() {
          _generatedYamlMessage =
              '$_operationMessage\n\nModified YAML:\n\n$yamlString';

          // Also save the current state for potential export
          Map<String, String> currentFiles =
              Map<String, String>.from(_exportedFiles);
          _exportedFiles.clear(); // Clear existing files before regenerating

          // Restore archive files from backup (but don't show them in changed files)
          archiveBackup.forEach((key, value) {
            _exportedFiles[key] = value;
          });

          // Restore combined content
          if (combinedContentBackup != null &&
              combinedContentBackup.isNotEmpty) {
            _exportedFiles['ALL_CONTENT_COMBINED.yaml'] = combinedContentBackup;
            print(
                'DEBUG: Restored combined file with ${combinedContentBackup.length} chars');
          }

          // Store the largest content in raw_project.yaml and complete_raw.yaml
          if (largestContent.isNotEmpty) {
            _exportedFiles['complete_raw.yaml'] = largestContent;
            _exportedFiles['raw_project.yaml'] = largestContent;
            print(
                'DEBUG: Restored largest content to raw files (${largestContent.length} chars)');
          }

          // Add the modified content as separate files and mark them as changed ONLY
          _exportedFiles['modified_yaml.yaml'] = yamlString;
          _changedFiles['modified_yaml.yaml'] = yamlString;

          _exportedFiles['raw_output.yaml'] = yamlString;
          _changedFiles['raw_output.yaml'] = yamlString;

          // Show header file with modification information
          String headerContent = 'YAML MODIFICATION: $currentPrompt\n\n';
          headerContent += 'Applied on ${DateTime.now()}\n';
          headerContent += '-----------------------------------\n\n';
          headerContent += yamlString;

          _exportedFiles['modification_details.yaml'] = headerContent;
          _changedFiles['modification_details.yaml'] = headerContent;

          print(
              'DEBUG: Added modified YAML files with ${yamlString.length} chars each');

          // Log the file sizes after restoration
          print('DEBUG: Files shown after modification:');
          _changedFiles.forEach((key, value) {
            print('DEBUG: - $key: ${value.length} chars');
          });
        });

        // Make sure _hasModifications is set to ensure we show changed files
        setState(() {
          _hasModifications = true;
        });

        // Auto-expand modified files
        _expandedFiles.clear();
        _expandedFiles.add('modification_details.yaml');
        _expandedFiles.add('modified_yaml.yaml');

        // Debug information
        print("Changed files count: ${_changedFiles.length}");
        print(
            "Files shown after modification: ${_changedFiles.keys.join(', ')}");
      } catch (e) {
        setState(() {
          _generatedYamlMessage =
              '$_operationMessage\n\nCould not display full structure as YAML.\nError details: $e';
        });
        print('Error converting map to YAML for display: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    bool hasCredentials = _projectIdController.text.isNotEmpty &&
        _apiTokenController.text.isNotEmpty;
    bool hasYaml = _parsedYamlMap != null;

    return Scaffold(
      appBar: AppBar(title: Text('FlutterFlow YAML Generator')),
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
                              icon: const Icon(Icons.close),
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
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit, size: 18),
                            tooltip: 'Edit credentials',
                            onPressed: () {
                              setState(() {
                                _collapseCredentials = false;
                              });
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.history, size: 18),
                            tooltip: 'Recent projects',
                            onPressed: () {
                              setState(() {
                                _showRecentProjects = true;
                              });
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.refresh, size: 18),
                            tooltip: 'Reload',
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
                            icon: const Icon(Icons.history, size: 16),
                            label: const Text('Recent'),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
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
                              onPressed:
                                  hasCredentials ? _fetchProjectYaml : null,
                              child: Text('Fetch YAML'),
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

            SizedBox(height: 16),

            // Prompt Section - Only show after YAML is loaded
            if (hasYaml)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Modify YAML',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      TextField(
                          controller: _promptController,
                          decoration: InputDecoration(
                              labelText:
                                  'Enter Prompt (e.g., "Set project name to MyApp")')),
                      SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _promptController.text.isNotEmpty
                            ? _processPromptAndGenerateYaml
                            : null,
                        child: Text('Generate from Prompt'),
                      ),
                    ],
                  ),
                ),
              ),

            if (hasYaml) SizedBox(height: 16),

            // Expandable Raw Output Section - Only show after YAML is loaded AND if there's an error
            if (hasYaml &&
                (_generatedYamlMessage.contains('Error:') ||
                    _generatedYamlMessage.contains('Failed')))
              Card(
                child: Column(
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isOutputExpanded = !_isOutputExpanded;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Icon(
                                _isOutputExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'Error Details',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red),
                            ),
                            Spacer(),
                            if (_isOutputExpanded)
                              ElevatedButton.icon(
                                icon: Icon(Icons.copy, size: 16),
                                label: Text('Copy Error'),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(
                                      text: _generatedYamlMessage));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Error details copied to clipboard'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_isOutputExpanded)
                      Container(
                        // Increased height for better visibility
                        height: 300,
                        padding: EdgeInsets.all(8.0),
                        color: Colors.red[50],
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _generatedYamlMessage,
                            style: TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            // Files Section - Only show after YAML is loaded
            if (hasYaml)
              Expanded(
                child: _buildExportFilesView(),
              ),
          ],
        ),
      ),
    );
  }

  // Build the export files view
  Widget _buildExportFilesView() {
    // Use changedFiles if modifications were made, otherwise use exportedFiles
    Map<String, String> filesToShow =
        _hasModifications ? _changedFiles : _exportedFiles;

    // Make sure our key files are shown first
    List<String> orderedKeys = filesToShow.keys.toList();

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
        // Then show complete raw
        if (a.contains('complete_raw.yaml')) return -1;
        if (b.contains('complete_raw.yaml')) return 1;
        if (a.contains('raw_project.yaml')) return -1;
        if (b.contains('raw_project.yaml')) return 1;
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

                    String fileContent = filesToShow[fileName] ?? '';
                    bool isExpanded = _expandedFiles.contains(fileName);

                    // Debug file sizes
                    print(
                        'DEBUG: File "$fileName" size: ${fileContent.length} chars');

                    // Determine if file was deleted
                    bool isDeleted = fileContent ==
                        "# This file was removed in the latest changes";

                    // Highlight the complete raw file
                    bool isCompleteRaw =
                        fileName.contains('complete_raw.yaml') ||
                            fileName.contains('ALL_CONTENT_COMBINED');

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
                                        IconButton(
                                          icon: Icon(
                                            isEditing ? Icons.save : Icons.edit,
                                            size: 18,
                                            color: isEditing
                                                ? Colors.green[600]
                                                : null,
                                          ),
                                          tooltip: isEditing
                                              ? 'Save changes'
                                              : 'Edit file',
                                          onPressed: () {
                                            if (isEditing) {
                                              // Get updated content
                                              String newContent =
                                                  _fileControllers[fileName]!
                                                      .text;

                                              // Apply changes using our helper method
                                              _applyFileChanges(
                                                  fileName, newContent);

                                              // Exit edit mode
                                              setState(() {
                                                _fileEditModes[fileName] =
                                                    false;
                                              });
                                            } else {
                                              // Enter edit mode
                                              setState(() {
                                                _fileEditModes[fileName] = true;
                                                _fileControllers[fileName]!
                                                    .text = fileContent;
                                              });
                                            }
                                          },
                                        ),
                                      // Copy button
                                      IconButton(
                                        icon: Icon(Icons.copy, size: 18),
                                        tooltip: 'Copy content',
                                        onPressed: () {
                                          _fallbackClipboardCopy(
                                              context, fileName, fileContent);
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
                                  : InkWell(
                                      onTap: () {
                                        // Enter edit mode when text is clicked
                                        setState(() {
                                          _fileEditModes[fileName] = true;
                                          _fileControllers[fileName]!.text =
                                              fileContent;
                                        });
                                      },
                                      child: SingleChildScrollView(
                                        child: SelectableText(
                                          fileContent,
                                          style: TextStyle(
                                              fontFamily: 'monospace'),
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

  Future<void> _handleFetchOrGenerate() async {
    if (_rawFetchedYaml == null || _parsedYamlMap == null) {
      await _fetchProjectYaml();
    } else {
      _processPromptAndGenerateYaml();
    }
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

      if (_exportedFiles.containsKey('ALL_CONTENT_COMBINED.yaml') &&
          _exportedFiles['ALL_CONTENT_COMBINED.yaml']!.isNotEmpty) {
        print(
            'DEBUG: No archive files found, preserving existing ALL_CONTENT_COMBINED.yaml content');
        archiveFiles['preserved_combined'] =
            _exportedFiles['ALL_CONTENT_COMBINED.yaml']!;
      }
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

    // Add the combined all-in-one file if we have content to combine
    String combinedString = combinedContent.toString();
    if (combinedString.isNotEmpty) {
      _exportedFiles['ALL_CONTENT_COMBINED.yaml'] = combinedString;
      print(
          'DEBUG: Created ALL_CONTENT_COMBINED.yaml with ${combinedString.length} chars');

      // Also make this the "complete_raw.yaml" file
      _exportedFiles['complete_raw.yaml'] = combinedString;
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
}
