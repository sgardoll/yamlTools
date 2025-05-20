import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For utf8 decoding & JSON
import 'package:yaml/yaml.dart';
import 'package:archive/archive.dart'; // For ZIP file handling

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 1. Declare ALL state fields and controllers here:
  String? _rawFetchedYaml;
  Map<String, dynamic>? _parsedYamlMap;
  String _generatedYamlMessage =
      "Enter Project ID and API Token, then click 'Fetch YAML'. Once YAML is loaded, enter a prompt and click 'Generate from Prompt'."; // Initial message
  String _operationMessage = ""; // For status messages like "Page created"

  final _projectIdController = TextEditingController();
  final _apiTokenController = TextEditingController();
  final _promptController = TextEditingController();

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
  }

  @override
  void dispose() {
    _projectIdController.dispose();
    _apiTokenController.dispose();
    _promptController.dispose();
    super.dispose();
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

    setState(() {
      _generatedYamlMessage = 'Fetching YAML...';
      _rawFetchedYaml = null;
      _parsedYamlMap = null;
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
        final String responseBody = response.body;
        print(
            'DEBUG_LOG: API Raw Response Body (first 1000 chars): ${responseBody.substring(0, responseBody.length > 1000 ? 1000 : responseBody.length)}');

        try {
          Map<String, dynamic>? jsonResponse;
          dynamic parsedJsonData;
          try {
            parsedJsonData = jsonDecode(responseBody);
            if (parsedJsonData is Map<String, dynamic>) {
              jsonResponse = parsedJsonData;
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
                    'DEBUG_LOG: Extracted project_yaml_bytes string snippet (first 100 chars): ${projectYamlBytesString.substring(0, projectYamlBytesString.length > 100 ? 100 : projectYamlBytesString.length)}');
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

              if (_rawFetchedYaml == null || _rawFetchedYaml!.trim().isEmpty) {
                setState(() {
                  _generatedYamlMessage =
                      'Error: Extracted YAML file is empty or contains only whitespace.';
                  _rawFetchedYaml = null;
                });
              } else {
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
  }

  void _parseFetchedYaml() {
    setState(() {
      _generatedYamlMessage = 'Parsing YAML...';
    });
    try {
      var loadedData = loadYaml(_rawFetchedYaml!);
      if (loadedData is YamlMap) {
        _parsedYamlMap = _convertYamlNode(loadedData) as Map<String, dynamic>?;
        if (_parsedYamlMap != null) {
          final yamlString = _mapToYamlString(_parsedYamlMap!);
          setState(() {
            _generatedYamlMessage = 'Fetched Project YAML:\n\n$yamlString';
          });
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

    setState(() {
      _generatedYamlMessage = 'Processing prompt...';
      _operationMessage = ''; // Reset operation message
    });

    Future.delayed(Duration(milliseconds: 50), () {
      _parsedYamlMap =
          Map<String, dynamic>.from(_parsedYamlMap!); // Ensure mutable

      final parsedCommand = _parseCommand(currentPrompt);

      if (parsedCommand['action'] == 'ERROR') {
        _operationMessage = parsedCommand['message'] ?? 'Error: Unknown command parsing error.';
      } else {
        final action = parsedCommand['action'] as String;
        final targetType = parsedCommand['targetType'] as String?;
        final targetName = parsedCommand['targetName'] as String?;
        final value = parsedCommand['value'];
        final options = parsedCommand['options'] as Map<String, dynamic>?;

        switch (action) {
          case 'SET':
            if (targetType == 'PROJECT_PROPERTY' && targetName == 'projectName') {
              if (value is String && value.isNotEmpty) {
                _parsedYamlMap!['projectName'] = value;
                _operationMessage = 'Project name set to "$value".';
              } else {
                _operationMessage = 'Error: New project name cannot be empty.';
              }
            } else if (targetType == 'PAGE_PROPERTY' && targetName != null && options != null) {
              final pageName = targetName; // Already unquoted by _parseCommand
              final propertyToSet = options['property'] as String?;
              final propertyValue = options['value']; // Already unquoted by _parseCommand

              if (propertyToSet == null || propertyValue == null) {
                  _operationMessage = 'Error: Invalid property settings for page.';
                  break;
              }

              if (!_parsedYamlMap!.containsKey('pages') || _parsedYamlMap!['pages'] is! List || (_parsedYamlMap!['pages'] as List).isEmpty) {
                _operationMessage = 'Error: No pages found or "pages" is not a valid list. Cannot set $propertyToSet.';
              } else {
                var pagesList = _parsedYamlMap!['pages'] as List;
                int pageIndex = -1;
                Map<String, dynamic>? pageToUpdateData;

                for (int i = 0; i < pagesList.length; i++) {
                  var page = pagesList[i];
                  if (page is Map && page.containsKey('name') && page['name']?.toString().toLowerCase() == pageName.toLowerCase()) {
                    pageToUpdateData = Map<String, dynamic>.from(page);
                    pageIndex = i;
                    break;
                  }
                }

                if (pageToUpdateData != null && pageIndex != -1) {
                  pageToUpdateData[propertyToSet] = propertyValue;
                  pagesList[pageIndex] = pageToUpdateData;
                  _parsedYamlMap!['pages'] = pagesList;
                  _operationMessage = '$propertyToSet of page "$pageName" set to "$propertyValue".';
                } else {
                  _operationMessage = 'Error: Page named "$pageName" not found.';
                }
              }
            } else if (targetType == 'THEME_COLOR' && targetName != null && value is String) {
              final colorName = targetName; // Already lowercased and unquoted by _parseCommand
              final hexValue = value; // Already unquoted by _parseCommand

              _parsedYamlMap!['theme'] ??= <String, dynamic>{};
              var themeMap = _parsedYamlMap!['theme'] as Map<String, dynamic>;
              themeMap['colors'] ??= <String, dynamic>{};
              var colorsMap = themeMap['colors'] as Map<String, dynamic>;

              colorsMap[colorName] = hexValue;
              _operationMessage = 'Theme color "$colorName" set to "$hexValue".';
            } else {
              _operationMessage = 'Error: Unrecognized "SET" command structure.';
            }
            break;
          case 'CREATE':
            if (targetType == 'PAGE' && targetName != null && targetName.isNotEmpty) {
              final pageName = targetName; // Already unquoted by _parseCommand
              if (!_parsedYamlMap!.containsKey('pages')) {
                _parsedYamlMap!['pages'] = <Map<String, dynamic>>[];
              }
              var pagesEntry = _parsedYamlMap!['pages'];

              if (pagesEntry is! List) {
                _operationMessage = "Error: 'pages' entry exists but is not a list. Cannot add page.";
              } else {
                List<Map<String, dynamic>> typedPagesList = [];
                for (var item in pagesEntry) {
                  if (item is Map) {
                    typedPagesList.add(Map<String, dynamic>.from(item));
                  } else {
                     _operationMessage = "Error: 'pages' list contains non-map elements. Cannot reliably add page.";
                     // To prevent further errors, we stop processing this command.
                     // Consider logging this state or providing a way to fix it.
                     return; 
                  }
                }
                _parsedYamlMap!['pages'] = typedPagesList; 
                bool pageExists = typedPagesList.any((p) => p['name']?.toString().toLowerCase() == pageName.toLowerCase());

                if (pageExists) {
                  _operationMessage = 'Error: Page named "$pageName" already exists.';
                } else {
                  typedPagesList.add({
                    'name': pageName,
                    'widgets': [], 
                    'backgroundColor': '#FFFFFF' 
                  });
                  _parsedYamlMap!['pages'] = typedPagesList;
                  _operationMessage = 'Page "$pageName" created successfully.';
                }
              }
            } else {
              _operationMessage = 'Error: Unrecognized "CREATE" command structure or missing page name.';
            }
            break;
          case 'ADD':
            if (targetType == 'APPBAR_TO_PAGE' && targetName != null && options != null) {
              final pageName = targetName; // Already unquoted by _parseCommand
              final templateName = options['template_name'] as String?; // Already unquoted and lowercased by _parseCommand
              final titleText = options['title_text'] as String?; // Already unquoted by _parseCommand

              if (!_parsedYamlMap!.containsKey('pages') || _parsedYamlMap!['pages'] is! List) {
                _operationMessage = 'Error: No pages list found or "pages" is not a list. Cannot add AppBar.';
                break;
              }
              var pagesList = _parsedYamlMap!['pages'] as List;
              int pageIndex = -1;
              Map<String, dynamic>? pageToUpdateData;

              for (int i = 0; i < pagesList.length; i++) {
                var page = pagesList[i];
                if (page is Map && page.containsKey('name') && page['name']?.toString().toLowerCase() == pageName.toLowerCase()) {
                  pageToUpdateData = Map<String, dynamic>.from(page);
                  pageIndex = i;
                  break;
                }
              }

              if (pageToUpdateData != null && pageIndex != -1) {
                Map<String, dynamic> newAppBar = {};
                if (templateName == 'large_header') { // Already lowercased
                  newAppBar = {
                    'templateType': 'LARGE_HEADER',
                    'backgroundColor': {'themeColor': 'PRIMARY'},
                    'elevation': 2,
                    'defaultIcon': {
                      'sizeValue': {'inputValue': 30},
                      'colorValue': {'inputValue': {'value': '4294967295'}}, // White
                      'iconDataValue': {
                        'inputValue': {
                          'codePoint': 62834,
                          'family': 'MaterialIcons',
                          'matchTextDirection': true,
                          'name': 'arrow_back_rounded'
                        }
                      }
                    },
                    'textStyle': {
                      'themeStyle': 'HEADLINE_MEDIUM',
                      'fontSizeValue': {'inputValue': 22},
                      'colorValue': {'inputValue': {'value': '4294967295'}} // White
                    }
                  };
                  // For LARGE_HEADER, an explicit title (if provided) takes precedence or can be set in its own field.
                  // FlutterFlow's actual behavior for title within LARGE_HEADER might involve specific fields in textStyle or a main title field.
                  // Here, we add/override a 'title' field for clarity if titleText is provided.
                  if (titleText != null && titleText.isNotEmpty) {
                     newAppBar['title'] = {'text': titleText};
                  } else if (!newAppBar.containsKey('title')){ // Add a default title if none from prompt and template doesn't set one
                     newAppBar['title'] = {'text': 'Title'}; // Default title for LARGE_HEADER
                  }
                } else { // Default or unknown template
                  newAppBar['backgroundColor'] = {'themeColor': 'PRIMARY'};
                  newAppBar['title'] = {'text': titleText ?? 'App Bar'}; // Use provided title or a generic default
                }
                
                // If an explicit title was given and it's NOT a large_header template (where title handling is more complex)
                // ensure the main 'title' field is set.
                if (titleText != null && titleText.isNotEmpty && templateName != 'large_header') {
                    newAppBar['title'] = {'text': titleText};
                }

                pageToUpdateData['appBar'] = newAppBar;
                pagesList[pageIndex] = pageToUpdateData;
                _parsedYamlMap!['pages'] = pagesList;
                _operationMessage = 'AppBar added to page "$pageName" ${templateName != null ? "using template '$templateName'" : ""}.';
              } else {
                _operationMessage = 'Error: Page named "$pageName" not found.';
              }
            } else {
              _operationMessage = 'Error: Unrecognized "ADD" command structure.';
            }
            break;
          default:
            _operationMessage = 'Error: Unrecognized command action.';
        }
      }

      try {
        final yamlString = _mapToYamlString(_parsedYamlMap!);
        setState(() {
          _generatedYamlMessage =
              '$_operationMessage\n\nModified YAML:\n\n$yamlString';
        });
      } catch (e) {
        setState(() {
          _generatedYamlMessage =
              '$_operationMessage\n\nCould not display full structure as YAML.\nError details: $e';
        });
        print('Error converting map to YAML for display: $e');
      }
    });
  }

  Map<String, dynamic> _parseCommand(String prompt) {
    final originalPromptTrimmed = prompt.trim(); // Use this for extracting original case values if needed before lowercasing.
    final promptLower = originalPromptTrimmed.toLowerCase();

    // Helper to unquote
    String unquote(String text) {
      text = text.trim(); 
      if ((text.startsWith("'") && text.endsWith("'")) ||
          (text.startsWith('"') && text.endsWith('"'))) {
        return text.substring(1, text.length - 1).trim(); 
      }
      return text;
    }

    // Pattern: set project name to <name>
    RegExp setProjectNameRegExp = RegExp(r'^set project name to\s+(.+)$', caseSensitive: false);
    Match? match = setProjectNameRegExp.firstMatch(originalPromptTrimmed);
    if (match != null) {
      return {
        'action': 'SET',
        'targetType': 'PROJECT_PROPERTY',
        'targetName': 'projectName', // This is fixed
        'value': unquote(match.group(1)!),
      };
    }

    // Pattern: create page <name> OR add page <name>
    RegExp createPageRegExp = RegExp(r'^(create|add)\s+page\s+(.+)$', caseSensitive: false);
    match = createPageRegExp.firstMatch(originalPromptTrimmed);
    if (match != null) {
      return {
        'action': 'CREATE',
        'targetType': 'PAGE',
        'targetName': unquote(match.group(2)!),
      };
    }

    // Pattern: set background color of page <page> to <color>
    RegExp setPageBgColorRegExp = RegExp(r'^set\s+(?:background|bg)\s+color\s+of\s+page\s+(.+?)\s+to\s+(.+)$', caseSensitive: false);
    match = setPageBgColorRegExp.firstMatch(originalPromptTrimmed);
    if (match != null) {
      return {
        'action': 'SET',
        'targetType': 'PAGE_PROPERTY',
        'targetName': unquote(match.group(1)!), // Page name
        'options': {
          'property': 'backgroundColor', 
          'value': unquote(match.group(2)!), // Color value
        }
      };
    }

    // Pattern: SET THEME_COLOR <color_name> TO <hex_value>
    RegExp setThemeColorRegExp = RegExp(r'^set\s+theme_color\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+to\s+([#a-fA-F0-9]+)$', caseSensitive: false);
    match = setThemeColorRegExp.firstMatch(originalPromptTrimmed);
    if (match != null) {
      return {
        'action': 'SET',
        'targetType': 'THEME_COLOR',
        'targetName': match.group(1)!.toLowerCase(), // color_name (e.g. primary, secondaryText) - normalized to lowercase
        'value': match.group(2)!, // hex_value (e.g. #FF00FF00 or FF00FF00) - preserve case as entered
      };
    }
    
    // Pattern: ADD APPBAR TO PAGE <page_name> [USING TEMPLATE <template_name>] [WITH TITLE <title_text>]
    // Page name can be quoted or unquoted. Template name and title can be quoted or unquoted.
    RegExp addAppBarRegExp = RegExp(
      r'^add\s+appbar\s+to\s+page\s+(' + // Start Page Name
          r'''(?:[^'\s"]+|'[^']*'|"[^"]*")''' + // Page name: unquoted, or single/double quoted
      r')' + // End Page Name
      r'(?:\s+using\s+template\s+(' + // Start Optional Template
          r'''(?:[^'\s"]+|'[^']*'|"[^"]*")''' + // Template name: unquoted, or single/double quoted
      r'))?' + // End Optional Template
      r'(?:\s+with\s+title\s+(' + // Start Optional Title
          r'''(?:[^'\s"]+|'[^']*'|"[^"]*")''' + // Title text: unquoted, or single/double quoted
      r'))?$', // End Optional Title
      caseSensitive: false);

    match = addAppBarRegExp.firstMatch(originalPromptTrimmed);
    if (match != null) {
      Map<String, dynamic> options = {};
      if (match.group(2) != null) { // template_name
        options['template_name'] = unquote(match.group(2)!).toLowerCase(); // Normalize template name to lowercase
      }
      if (match.group(3) != null) { // title_text
        options['title_text'] = unquote(match.group(3)!);
      }
      return {
        'action': 'ADD',
        'targetType': 'APPBAR_TO_PAGE',
        'targetName': unquote(match.group(1)!), // page_name
        'options': options,
      };
    }

    return {'action': 'ERROR', 'message': 'Error: Unrecognized command structure. Examples:\n'
            '- Set project name to MyNewApp\n'
            '- Create page \'UserProfile\'\n'
            '- Add page "SettingsPage"\n'
            '- Set background color of page "UserProfile" to "blue"\n'
            '- Set theme_color primary TO #FF00FF00\n'
            '- Set theme_color secondary_text TO FFCCCCCC\n'
            '- Add appbar to page HomePage using template LARGE_HEADER with title "My Home"\n'
            '- Add appbar to page SettingsPage with title "Settings"\n'
            '- Add appbar to page DashboardPage'};
  }

  Future<void> _handleFetchOrGenerate() async {
    if (_rawFetchedYaml == null || _parsedYamlMap == null) {
      await _fetchProjectYaml();
    } else {
      _processPromptAndGenerateYaml();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('FlutterFlow YAML Generator')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
                controller: _projectIdController,
                decoration: InputDecoration(labelText: 'Project ID')),
            TextField(
                controller: _apiTokenController,
                obscureText: true,
                decoration: InputDecoration(labelText: 'API Token')),
            TextField(
                controller: _promptController,
                decoration: InputDecoration(
                    labelText:
                        'Enter Prompt (e.g., "Set project name to MyApp")')),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_rawFetchedYaml == null ||
                      _parsedYamlMap == null) // Fetch Mode
                  ? (_projectIdController.text.isNotEmpty &&
                          _apiTokenController.text.isNotEmpty
                      ? _handleFetchOrGenerate
                      : null) // Enable only if creds are present
                  : (_promptController.text.isNotEmpty
                      ? _handleFetchOrGenerate
                      : null), // Generate Mode: Enable only if prompt is present
              child: Text(_rawFetchedYaml == null || _parsedYamlMap == null
                  ? 'Fetch YAML'
                  : 'Generate from Prompt'),
            ),
            SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: EdgeInsets.all(8.0),
                  color: Colors.grey[200],
                  child: Text(_generatedYamlMessage),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
