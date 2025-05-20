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
  // TextEditingControllers for TextFields
  final _promptController = TextEditingController();
  final _projectIdController = TextEditingController();
  final _apiTokenController = TextEditingController();
  
  String? _rawFetchedYaml; // To store the raw YAML string from API
  Map<String, dynamic>? _parsedYamlMap; 
  String _generatedYamlMessage = "Enter Project ID and API Token, then click 'Fetch YAML'. Once YAML is loaded, enter a prompt and click 'Generate from Prompt'."; // Updated initial message

  @override
  void initState() {
    super.initState();
    // Listener to update button state based on prompt text
    _promptController.addListener(_updateButtonState);
  }

  void _updateButtonState() {
    setState(() {
      // This rebuilds the widget tree, updating button state
    });
  }

  @override
  void dispose() {
    _promptController.removeListener(_updateButtonState);
    _promptController.dispose();
    _projectIdController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  String _bytesToHexString(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');
  }

  // Fetches YAML from the API
  Future<void> _fetchProjectYaml() async {
    // Access text directly from controllers
    final projectId = _projectIdController.text;
    final apiToken = _apiTokenController.text;

    if (projectId.isEmpty || apiToken.isEmpty) {
      setState(() {
        _generatedYamlMessage = 'Error: Project ID and API Token cannot be empty.';
      });
      return;
    }

    setState(() {
      _generatedYamlMessage = 'Fetching YAML...';
      _rawFetchedYaml = null; 
      _parsedYamlMap = null;  
    });

    try {
      // Use projectId and apiToken from local variables
      final Uri uri = Uri.parse('https://api.flutterflow.io/v2/projectYamls?projectId=$projectId');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        try {
          // 1. Parse JSON Response
          Map<String, dynamic> jsonResponse;
          try {
            jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
          } on FormatException catch (e) {
            setState(() {
              _generatedYamlMessage = 'Error: API response is not valid JSON.\nDetails: $e';
              _rawFetchedYaml = null;
            });
            print('JSON Parsing Error: $e');
            return;
          }

          // 2. Extract and Decode Base64 String
          if (!jsonResponse.containsKey('project_yaml_bytes')) {
            setState(() {
              _generatedYamlMessage = "Error: Unexpected API response structure (missing 'project_yaml_bytes' key).";
              _rawFetchedYaml = null;
            });
            return;
          }
          
          final base64String = jsonResponse['project_yaml_bytes'];
          if (base64String is! String) {
             setState(() {
              _generatedYamlMessage = "Error: Unexpected API response data type for 'project_yaml_bytes' (expected String).";
              _rawFetchedYaml = null;
            });
            return;
          }

          List<int> zipBytes;
          try {
            zipBytes = base64Decode(base64String);
          } on FormatException catch (e) {
            setState(() {
              _generatedYamlMessage = 'Error: Failed to decode YAML data from API response (Base64 decoding failed).\nDetails: $e';
              _rawFetchedYaml = null;
            });
            print('Base64 Decoding Error: $e');
            return;
          }

          // 3. Process ZIP Bytes (existing logic moved inside this try block)
          final archive = ZipDecoder().decodeBytes(zipBytes, verify: true); // Use zipBytes here

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
                _generatedYamlMessage = 'Error: Extracted YAML file is empty or contains only whitespace.';
                _rawFetchedYaml = null; 
              });
            } else {
              _parseFetchedYaml(); 
            }
          } else {
            setState(() {
              _generatedYamlMessage = 'Error: No ".yaml" file (e.g., project.yaml) found in the downloaded ZIP archive.';
              _rawFetchedYaml = null;
            });
          }
        } on ArchiveException catch (e) {
          setState(() {
            _generatedYamlMessage = 'Error: Received corrupted or invalid YAML package (ZIP archive).\nDetails: $e';
            _rawFetchedYaml = null;
          });
          print('ArchiveException: $e');
        } catch (e) { // General catch for JSON, Base64, or ZIP processing stages
          setState(() {
            _generatedYamlMessage = 'Error processing fetched data: An unexpected error occurred.\nDetails: $e';
            _rawFetchedYaml = null;
          });
          print('Error during fetched data processing: $e');
        }
      } else {
        String errorMsg;
        switch (response.statusCode) {
          case 401:
            errorMsg = 'Error fetching YAML: Unauthorized (401). Please check your API Token.';
            break;
          case 403:
            errorMsg = 'Error fetching YAML: Forbidden (403). You may not have permission to access this project.';
            break;
          case 404:
            errorMsg = 'Error fetching YAML: Project not found (404). Please check your Project ID.';
            break;
          default:
            if (response.statusCode >= 500) {
              errorMsg = 'Error fetching YAML: Server error (${response.statusCode}). Please try again later.';
            } else {
              errorMsg = 'Error fetching YAML: Unexpected network error (${response.statusCode}). Details: ${response.body}';
            }
        }
        setState(() {
          _generatedYamlMessage = errorMsg;
        });
        print('Error fetching YAML (${response.statusCode}): ${response.body}'); // Standardized logging
      }
    } catch (e) {
      setState(() {
        _generatedYamlMessage = 'Failed to connect to the server. Please check your internet connection and try again.\nDetails: $e'; // Improved formatting
      });
      print('Exception caught during YAML fetch: $e'); // Standardized logging
    }
  }

  // Parses the fetched YAML string
  void _parseFetchedYaml() {
    // _rawFetchedYaml is already checked for null/empty in _fetchProjectYaml before calling this
    setState(() {
      _generatedYamlMessage = 'Parsing YAML...'; // Indicate parsing state
    });
    try {
      var loadedData = loadYaml(_rawFetchedYaml!);
      if (loadedData is YamlMap) {
        _parsedYamlMap = _convertYamlNode(loadedData) as Map<String, dynamic>?;
        if (_parsedYamlMap != null) {
          // Display the fetched YAML immediately
          final yamlString = _mapToYamlString(_parsedYamlMap!);
          setState(() {
            _generatedYamlMessage = 'Fetched Project YAML:\n\n$yamlString';
          });
        } else {
          _parsedYamlMap = null; // Ensure consistency
          setState(() {
            _generatedYamlMessage = 'Error: Could not convert fetched YAML to a readable map format.';
          });
        }
      } else {
        _parsedYamlMap = null; 
        setState(() {
          _generatedYamlMessage = 'Error: Fetched data is not in the expected YAML map format. It should be a structured object (key-value pairs).';
        });
      }
    } on YamlException catch (e) {
      _parsedYamlMap = null;
      setState(() {
        _generatedYamlMessage = 'Error: The fetched YAML has an invalid format and could not be read.\nDetails: $e';
      });
      print('YamlException during parsing: $e'); // Standardized logging
    } catch (e) {
      _parsedYamlMap = null;
      setState(() {
        _generatedYamlMessage = 'An unexpected error occurred while reading the YAML structure.\nDetails: $e';
      });
      print('Unexpected error during YAML parsing: $e'); // Standardized logging
    }
  }
  
  // Helper to recursively convert YamlMap/YamlList to Dart Map/List.
  // Ensures that the top-level result is correctly typed if it's a map.
  dynamic _convertYamlNode(dynamic nodeValue) { 
    if (nodeValue is YamlMap) {
      final Map<String, dynamic> newMap = {};
      nodeValue.nodes.forEach((keyNode, valueNode) { 
        String key = (keyNode is YamlScalar) ? keyNode.value.toString() : keyNode.toString();
        newMap[key] = _convertYamlNode(valueNode.value); 
      });
      return newMap;
    } else if (nodeValue is YamlList) {
      return List<dynamic>.from(nodeValue.nodes.map((itemNode) => _convertYamlNode(itemNode.value)));
    }
    return nodeValue is YamlScalar ? nodeValue.value : nodeValue;
  }

  // Custom YAML Serializer
  String _mapToYamlString(Map<String, dynamic> map) {
    return _nodeToYamlString(map, 0, false);
  }

  String _nodeToYamlString(dynamic node, int indentLevel, bool isListItemContext) {
    String indent = '  ' * indentLevel;
    StringBuffer yamlBuffer = StringBuffer();

    if (node is Map) {
      if (isListItemContext && node.isNotEmpty) { 
        // If it's a map as a list item, subsequent lines should align with the first key, not the dash.
        // The first key will be handled by the loop, adding its own indent.
        // This effectively means the map's content starts at `indentLevel` if it's a list item.
      }
      int i = 0;
      node.forEach((key, value) {
        String currentItemIndent = indent;
        if (isListItemContext && i == 0) {
          // First item of a map in a list context: `- key:`
          // The dash is handled by the list serializer part. Here we just provide `key:`
          currentItemIndent = ''; 
        } else if (isListItemContext && i > 0) {
          // Subsequent items of a map in list context: `  key:`
          currentItemIndent = '  ' * (indentLevel); // Align with the key above it.
        }
        
        yamlBuffer.write(currentItemIndent);
        yamlBuffer.write(key);
        yamlBuffer.write(': ');

        if (value is Map) {
          yamlBuffer.write('\n');
          yamlBuffer.write(_nodeToYamlString(value, indentLevel + 1, false));
        } else if (value is List) {
          yamlBuffer.write('\n');
          yamlBuffer.write(_nodeToYamlString(value, indentLevel + 1, false));
        } else {
          yamlBuffer.write(_escapeStringForYaml(value.toString()));
          if (i < node.length - 1 || isListItemContext ) yamlBuffer.write('\n');
        }
        i++;
      });
       // Remove trailing newline if it's the last line of the map and not in list context
      if (yamlBuffer.toString().endsWith('\n') && !isListItemContext && indentLevel > 0) {
         //This is too aggressive, let's rely on caller to manage last newline
      }

    } else if (node is List) {
      for (int i = 0; i < node.length; i++) {
        var item = node[i];
        yamlBuffer.write(indent);
        yamlBuffer.write('- ');
        if (item is Map) {
          // For a map in a list, the first key-value pair should be on the same line as the dash if simple,
          // or the key starts on the next line, indented. Simpler for now: start map on next line.
          // No, let's try to make it `  - key: value` if map has one simple entry
          // or `  - \n    key: value` if complex.
          // Current approach: `- \n key: value`
          // Let's adjust _nodeToYamlString for map in list context
          String mapStr = _nodeToYamlString(item, indentLevel + 1, true); // Pass true for list item context
          if (mapStr.startsWith('  ')) mapStr = mapStr.substring(2); // remove indent if map added it
          yamlBuffer.write(mapStr); // mapStr already contains newlines if multi-line
           if (!mapStr.endsWith('\n')) yamlBuffer.write('\n');

        } else if (item is List) {
          yamlBuffer.write('\n'); // Newline after '- ' for nested list
          yamlBuffer.write(_nodeToYamlString(item, indentLevel + 1, false)); // Nested list items are not direct map children
        } else {
          yamlBuffer.write(_escapeStringForYaml(item.toString()));
          if (i < node.length - 1) yamlBuffer.write('\n');
        }
      }
    } else {
      // Basic types (String, num, bool)
      yamlBuffer.write(_escapeStringForYaml(node.toString()));
    }
    return yamlBuffer.toString();
  }

  String _escapeStringForYaml(String value) {
    // Basic escaping: if string contains newline or starts/ends with space, or has ':' followed by space, quote it.
    // This is a very simplified version. For full YAML spec, more robust quoting/escaping is needed.
    if (value.contains('\n') || value.startsWith(' ') || value.endsWith(' ') || value.contains(': ')) {
      // Replace single quotes with two single quotes if using single quotes
      // Using double quotes is often safer for arbitrary strings.
      return '"${value.replaceAll('"', '\\"')}"'; 
    }
    // Check if it looks like a number, bool, or null, but should be a string
    if (value == 'true' || value == 'false' || value == 'null' || double.tryParse(value) != null) {
        // If it's one of these keywords or looks like a number but is meant to be a string, quote it.
        // This check is context-dependent; for now, we assume if it's a string type, it should be treated as such.
        // A more sophisticated type check would be needed if the original types were preserved.
    }
    return value;
  }


  // Processes the prompt and modifies the YAML (currently just project name)
  void _processPromptAndGenerateYaml() {
    if (_parsedYamlMap == null) {
      setState(() {
        // Enhanced message for this case
        _generatedYamlMessage = 'Cannot process prompt: YAML data is not available or not correctly formatted. Please fetch valid YAML first.';
      });
      return;
    }
    // Access prompt directly from controller
    final currentPrompt = _promptController.text;
    if (currentPrompt.isEmpty) {
      setState(() {
        _generatedYamlMessage = 'Error: Prompt is empty. Please enter a modification instruction.';
      });
      return;
    }
    
    // Indicate processing
    setState(() {
      _generatedYamlMessage = 'Processing prompt...';
    });

    // Delayed processing to allow UI to update with "Processing prompt..."
    Future.delayed(Duration(milliseconds: 50), () {
      final promptTrimmed = currentPrompt.trim(); // Use currentPrompt
      final promptLc = promptTrimmed.toLowerCase();
      String operationMessage = ""; // To store the primary outcome of the operation

      // Ensure _parsedYamlMap is mutable for modifications
      _parsedYamlMap = Map<String, dynamic>.from(_parsedYamlMap!);

      // 1. Set project name
      final setProjectNameMatch = RegExp(r"^set project name to\s*['\"]?(.+?)['\"]?$", caseSensitive: false).firstMatch(promptTrimmed);
      if (setProjectNameMatch != null) {
        final newName = setProjectNameMatch.group(1)!.trim();
        if (newName.isEmpty) {
          operationMessage = 'Error: New project name cannot be empty.';
        } else {
          _parsedYamlMap!['projectName'] = newName;
          operationMessage = 'Project name set to "$newName".';
        }
      }
      // 2. Create a new page
      else {
        final createPageMatch = RegExp(r"^(?:create|add) (?:a new )?page (?:named|called)?\s*['\"]?(.+?)['\"]?$", caseSensitive: false).firstMatch(promptTrimmed);
        if (createPageMatch != null) {
          final pageName = createPageMatch.group(1)!.trim();
          if (pageName.isEmpty) {
            operationMessage = 'Error: Page name cannot be empty for creation.';
          } else {
            if (!_parsedYamlMap!.containsKey('pages')) {
              _parsedYamlMap!['pages'] = [];
            }
            var pagesEntry = _parsedYamlMap!['pages'];
            if (pagesEntry is! List) {
              operationMessage = "Error: 'pages' entry exists but is not a list. Cannot add page.";
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
                operationMessage = "Error: 'pages' list contains elements that are not valid page objects (maps).";
              } else {
                _parsedYamlMap!['pages'] = typedPagesList; 
                bool pageExists = typedPagesList.any((p) => p['name']?.toString().toLowerCase() == pageName.toLowerCase());
                if (pageExists) {
                  operationMessage = 'Error: Page named "$pageName" already exists.';
                } else {
                  typedPagesList.add({'name': pageName, 'widgets': []});
                  _parsedYamlMap!['pages'] = typedPagesList; // Ensure the main map is updated
                  operationMessage = 'Page "$pageName" created successfully.';
                }
              }
            }
          }
        }
        // 3. Set page background color
        else {
          final setBgColorMatch = RegExp(r"^(?:set|change) (?:background color|bg color|background) of (?:page )?['\"](.+?)['\"] to ['\"](.+?)['\"]$", caseSensitive: false).firstMatch(promptTrimmed);
          if (setBgColorMatch != null) {
            final pageName = setBgColorMatch.group(1)!.trim();
            final colorValue = setBgColorMatch.group(2)!.trim();

            if (!_parsedYamlMap!.containsKey('pages') || _parsedYamlMap!['pages'] is! List || (_parsedYamlMap!['pages'] as List).isEmpty) {
              operationMessage = 'Error: No pages found or "pages" is not a valid list. Cannot set background color.';
            } else {
              var pagesList = _parsedYamlMap!['pages'] as List;
              int pageIndex = -1;
              Map<String, dynamic>? pageToUpdate;

              for (int i = 0; i < pagesList.length; i++) {
                  var page = pagesList[i];
                  if (page is Map && page.containsKey('name') && page['name']?.toString().toLowerCase() == pageName.toLowerCase()) {
                      pageToUpdate = Map<String, dynamic>.from(page); 
                      pageIndex = i;
                      break;
                  }
              }

              if (pageToUpdate != null && pageIndex != -1) {
                pageToUpdate['backgroundColor'] = colorValue;
                pagesList[pageIndex] = pageToUpdate; 
                _parsedYamlMap!['pages'] = pagesList; // Ensure the main map is updated
                operationMessage = 'Background color of page "$pageName" set to "$colorValue".';
              } else {
                operationMessage = 'Error: Page named "$pageName" not found.';
              }
            }
          }
          // Default: Prompt not recognized
          else {
            operationMessage = 'Prompt not recognized. Examples:\n'
                      '- Set project name to MyNewApp\n'
                      '- Create page \'UserProfile\'\n'
                      '- Add page "SettingsPage"\n'
                      '- Set background color of page "UserProfile" to "blue"';
          }
        }
      }

      // Finalize by setting the message and converting map to YAML for display
      try {
        // Use _mapToYamlString instead of JsonEncoder
        final yamlString = _mapToYamlString(_parsedYamlMap!); 
        setState(() {
          _generatedYamlMessage = '$operationMessage\n\nModified YAML:\n\n$yamlString';
        });
      } catch (e) {
        setState(() {
          // If YAML conversion fails, show the operation message and the error
          _generatedYamlMessage = '$operationMessage\n\nCould not display full structure as YAML.\nError details: $e';
        });
        print('Error converting map to YAML for display: $e');
      }
    });
  }

  // Main button handler
  void _handleFetchOrGenerate() {
    // Clear previous messages immediately for better UX, specific messages will be set by called functions
    setState(() {
       // _generatedYamlMessage = "Processing..."; // This will be quickly overwritten by more specific messages
    });

    if (_rawFetchedYaml == null || _parsedYamlMap == null) { // Ensure parsed map is also available before generating
      _fetchProjectYaml(); 
    } else {
      _processPromptAndGenerateYaml();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('YAML Generator'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _promptController, // Use controller
              decoration: InputDecoration(labelText: 'Enter your prompt (e.g., Set project name to MyApp)'),
              // onChanged removed, value accessed via _promptController.text
            ),
            SizedBox(height: 10),
            TextField(
              controller: _projectIdController, // Use controller
              decoration: InputDecoration(labelText: 'Project ID'),
              // onChanged removed
            ),
            SizedBox(height: 10),
            TextField(
              controller: _apiTokenController, // Use controller
              decoration: InputDecoration(labelText: 'API Token'),
              obscureText: true,
              // onChanged removed
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_rawFetchedYaml == null || _parsedYamlMap == null) // Fetch mode
                  ? _handleFetchOrGenerate 
                  : (_promptController.text.isNotEmpty // Generate mode: prompt must not be empty
                      ? _handleFetchOrGenerate 
                      : null), // Disable if in generate mode and prompt is empty
              child: Text(_rawFetchedYaml == null || _parsedYamlMap == null ? 'Fetch YAML' : 'Generate from Prompt'),
            ),
            SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_generatedYamlMessage), // Display messages/results here
              ),
            ),
          ],
        ),
      ),
    );
  }
}
