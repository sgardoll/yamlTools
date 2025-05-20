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
  String _generatedYamlMessage = "Enter Project ID and API Token, then click 'Fetch YAML'. Once YAML is loaded, enter a prompt and click 'Generate from Prompt'."; // Initial message
  String _operationMessage = ""; // For status messages like "Page created"

  final _projectIdController = TextEditingController();
  final _apiTokenController = TextEditingController();
  final _promptController = TextEditingController();

  // Helper to convert bytes to hex
  String _bytesToHexString(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');
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
     if (value.contains(': ') || value.contains('\n') || value.contains('\r') ||
         value.startsWith(' ') || value.endsWith(' ') ||
         ['true', 'false', 'null'].contains(value.toLowerCase()) ||
         (double.tryParse(value) != null && !value.contains(RegExp(r'[a-zA-Z]'))) || 
         (int.tryParse(value) != null && !value.contains(RegExp(r'[a-zA-Z]'))) ) {
       return "'${value.replaceAll("'", "''")}'";
     }
     return value; 
   }

  // Helper to serialize Dart Map to YAML string
  String _nodeToYamlString(dynamic node, int indentLevel, bool isListItemContext) {
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
           if (value is Map && value.isNotEmpty || value is List && value.isNotEmpty) {
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
       if (node.isEmpty) return isListItemContext ? (indentLevel == 0 ? '[]' : '') : '[]';
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
      final Uri uri = Uri.parse('https://api.flutterflow.io/v2/projectYamls?projectId=$projectId');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final String responseBody = response.body;
        print('DEBUG_LOG: API Raw Response Body (first 1000 chars): ${responseBody.substring(0, responseBody.length > 1000 ? 1000 : responseBody.length)}');

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
              _generatedYamlMessage = 'Error: API response is not valid JSON.\nDetails: $e';
              _rawFetchedYaml = null;
            });
            print('JSON Parsing Error: $e');
            return;
          }

          print('DEBUG_LOG: Parsed JSON type: ${parsedJsonData.runtimeType}');

          if (jsonResponse != null) {
            final String? projectYamlBytesString = jsonResponse['project_yaml_bytes'] as String?;
            if (projectYamlBytesString != null) {
              print('DEBUG_LOG: Extracted project_yaml_bytes string length: ${projectYamlBytesString.length}');
              print('DEBUG_LOG: Extracted project_yaml_bytes string snippet (first 100 chars): ${projectYamlBytesString.substring(0, projectYamlBytesString.length > 100 ? 100 : projectYamlBytesString.length)}');
            } else {
              print('DEBUG_LOG: project_yaml_bytes key not found or not a string.');
              setState(() {
                _generatedYamlMessage = "Error: API response missing 'project_yaml_bytes' or it's not a string.";
                _rawFetchedYaml = null;
              });
              return;
            }

            List<int> decodedZipBytes;
            try {
              decodedZipBytes = base64Decode(projectYamlBytesString);
            } on FormatException catch (e) {
              setState(() {
                _generatedYamlMessage = 'Error: Failed to decode YAML data from API response (Base64 decoding failed).\nDetails: $e';
                _rawFetchedYaml = null;
              });
              print('Base64 Decoding Error: $e');
              return;
            }
            
            print('DEBUG_LOG: Decoded ZIP Bytes Length: ${decodedZipBytes.length}');
            List<int> snippet = decodedZipBytes.take(32).toList();
            print('DEBUG_LOG: Decoded ZIP Bytes Snippet (Hex, first 32 bytes): ${_bytesToHexString(snippet)}');
            
            final archive = ZipDecoder().decodeBytes(decodedZipBytes, verify: true);

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
          } else { 
            print('DEBUG_LOG: Parsed JSON is not a Map.');
            setState(() {
              _generatedYamlMessage = 'Error: API response format is not a valid JSON object.';
              _rawFetchedYaml = null;
            });
            return;
          }
        } on ArchiveException catch (e) {
          setState(() {
            _generatedYamlMessage = 'Error: Received corrupted or invalid YAML package (ZIP archive).\nDetails: $e';
            _rawFetchedYaml = null;
          });
          print('ArchiveException: $e');
        } catch (e) { 
          setState(() {
            _generatedYamlMessage = 'Error processing fetched data: An unexpected error occurred.\nDetails: $e';
            _rawFetchedYaml = null;
          });
          print('Error during fetched data processing: $e');
        }
      } else {
        String errorMsg;
        switch (response.statusCode) {
          case 401: errorMsg = 'Error fetching YAML: Unauthorized (401). Please check your API Token.'; break;
          case 403: errorMsg = 'Error fetching YAML: Forbidden (403). You may not have permission to access this project.'; break;
          case 404: errorMsg = 'Error fetching YAML: Project not found (404). Please check your Project ID.'; break;
          default:
            if (response.statusCode >= 500) {
              errorMsg = 'Error fetching YAML: Server error (${response.statusCode}). Please try again later.';
            } else {
              errorMsg = 'Error fetching YAML: Unexpected network error (${response.statusCode}). Details: ${response.body}';
            }
        }
        setState(() { _generatedYamlMessage = errorMsg; });
        print('Error fetching YAML (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      setState(() {
        _generatedYamlMessage = 'Failed to connect to the server. Please check your internet connection and try again.\nDetails: $e';
      });
      print('Exception caught during YAML fetch: $e');
    }
  }

  void _parseFetchedYaml() {
    setState(() { _generatedYamlMessage = 'Parsing YAML...'; });
    try {
      var loadedData = loadYaml(_rawFetchedYaml!);
      if (loadedData is YamlMap) {
        _parsedYamlMap = _convertYamlNode(loadedData) as Map<String, dynamic>?;
        if (_parsedYamlMap != null) {
          final yamlString = _mapToYamlString(_parsedYamlMap!);
          setState(() { _generatedYamlMessage = 'Fetched Project YAML:\n\n$yamlString'; });
        } else {
          _parsedYamlMap = null; 
          setState(() { _generatedYamlMessage = 'Error: Could not convert fetched YAML to a readable map format.'; });
        }
      } else {
        _parsedYamlMap = null; 
        setState(() { _generatedYamlMessage = 'Error: Fetched data is not in the expected YAML map format. It should be a structured object (key-value pairs).'; });
      }
    } on YamlException catch (e) {
      _parsedYamlMap = null;
      setState(() { _generatedYamlMessage = 'Error: The fetched YAML has an invalid format and could not be read.\nDetails: $e'; });
      print('YamlException during parsing: $e');
    } catch (e) {
      _parsedYamlMap = null;
      setState(() { _generatedYamlMessage = 'An unexpected error occurred while reading the YAML structure.\nDetails: $e'; });
      print('Unexpected error during YAML parsing: $e');
    }
  }

  void _processPromptAndGenerateYaml() {
    if (_parsedYamlMap == null) {
      setState(() { _generatedYamlMessage = 'Cannot process prompt: YAML data is not available or not correctly formatted. Please fetch valid YAML first.'; });
      return;
    }
    final currentPrompt = _promptController.text;
    if (currentPrompt.isEmpty) {
      setState(() { _generatedYamlMessage = 'Error: Prompt is empty. Please enter a modification instruction.'; });
      return;
    }
    
    setState(() { 
      _generatedYamlMessage = 'Processing prompt...'; 
      _operationMessage = ''; // Reset operation message
    });

    Future.delayed(Duration(milliseconds: 50), () {
      final promptTrimmed = currentPrompt.trim();
      // RegExp definitions are placed inside the method as per template's implication,
      // though they could be static final fields of the class for efficiency.
      final setProjectNameMatch = RegExp(r"^set project name to\s*['\"]?(.+?)['\"]?$", caseSensitive: false).firstMatch(promptTrimmed);
      final createPageMatch = RegExp(r"^(?:create|add) (?:a new )?page (?:named|called)?\s*['\"]?(.+?)['\"]?$", caseSensitive: false).firstMatch(promptTrimmed);
      final setBgColorMatch = RegExp(r"^(?:set|change) (?:background color|bg color|background) of (?:page )?['\"](.+?)['\"] to ['\"](.+?)['\"]$", caseSensitive: false).firstMatch(promptTrimmed);

      _parsedYamlMap = Map<String, dynamic>.from(_parsedYamlMap!); // Ensure mutable

      if (setProjectNameMatch != null) {
        final newName = setProjectNameMatch.group(1)!.trim();
        if (newName.isEmpty) {
          _operationMessage = 'Error: New project name cannot be empty.';
        } else {
          _parsedYamlMap!['projectName'] = newName;
          _operationMessage = 'Project name set to "$newName".';
        }
      }
      else if (createPageMatch != null) {
        final pageName = createPageMatch.group(1)!.trim();
        if (pageName.isEmpty) {
          _operationMessage = 'Error: Page name cannot be empty for creation.';
        } else {
          if (!_parsedYamlMap!.containsKey('pages')) {
            _parsedYamlMap!['pages'] = [];
          }
          var pagesEntry = _parsedYamlMap!['pages'];
          if (pagesEntry is! List) {
            _operationMessage = "Error: 'pages' entry exists but is not a list. Cannot add page.";
          } else {
            List<Map<String, dynamic>> typedPagesList = [];
            bool conversionSuccess = true;
            for (var item in pagesEntry) {
              if (item is Map) {
                typedPagesList.add(Map<String, dynamic>.from(item));
              } else {
                conversionSuccess = false; break;
              }
            }
            if (!conversionSuccess) {
              _operationMessage = "Error: 'pages' list contains elements that are not valid page objects (maps).";
            } else {
              _parsedYamlMap!['pages'] = typedPagesList; 
              bool pageExists = typedPagesList.any((p) => p['name']?.toString().toLowerCase() == pageName.toLowerCase());
              if (pageExists) {
                _operationMessage = 'Error: Page named "$pageName" already exists.';
              } else {
                typedPagesList.add({'name': pageName, 'widgets': []});
                _parsedYamlMap!['pages'] = typedPagesList;
                _operationMessage = 'Page "$pageName" created successfully.';
              }
            }
          }
        }
      }
      else if (setBgColorMatch != null) {
        final pageName = setBgColorMatch.group(1)!.trim();
        final colorValue = setBgColorMatch.group(2)!.trim();
        if (!_parsedYamlMap!.containsKey('pages') || _parsedYamlMap!['pages'] is! List || (_parsedYamlMap!['pages'] as List).isEmpty) {
          _operationMessage = 'Error: No pages found or "pages" is not a valid list. Cannot set background color.';
        } else {
          var pagesList = _parsedYamlMap!['pages'] as List;
          int pageIndex = -1;
          Map<String, dynamic>? pageToUpdate;
          for (int i = 0; i < pagesList.length; i++) {
              var page = pagesList[i];
              if (page is Map && page.containsKey('name') && page['name']?.toString().toLowerCase() == pageName.toLowerCase()) {
                  pageToUpdate = Map<String, dynamic>.from(page); 
                  pageIndex = i; break;
              }
          }
          if (pageToUpdate != null && pageIndex != -1) {
            pageToUpdate['backgroundColor'] = colorValue;
            pagesList[pageIndex] = pageToUpdate; 
            _parsedYamlMap!['pages'] = pagesList;
            _operationMessage = 'Background color of page "$pageName" set to "$colorValue".';
          } else {
            _operationMessage = 'Error: Page named "$pageName" not found.';
          }
        }
      }
      else {
        _operationMessage = 'Prompt not recognized. Examples:\n'
                  '- Set project name to MyNewApp\n'
                  '- Create page \'UserProfile\'\n'
                  '- Add page "SettingsPage"\n'
                  '- Set background color of page "UserProfile" to "blue"';
      }

      try {
        final yamlString = _mapToYamlString(_parsedYamlMap!); 
        setState(() { _generatedYamlMessage = '$_operationMessage\n\nModified YAML:\n\n$yamlString'; });
      } catch (e) {
        setState(() { _generatedYamlMessage = '$_operationMessage\n\nCould not display full structure as YAML.\nError details: $e'; });
        print('Error converting map to YAML for display: $e');
      }
    });
  }
  
  Future<void> _handleFetchOrGenerate() async { 
    // Removed the setState for "Processing..." as individual methods set their own status.
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
            TextField(controller: _projectIdController, decoration: InputDecoration(labelText: 'Project ID')),
            TextField(controller: _apiTokenController, obscureText: true, decoration: InputDecoration(labelText: 'API Token')),
            TextField(controller: _promptController, decoration: InputDecoration(labelText: 'Enter Prompt (e.g., "Set project name to MyApp")')),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_rawFetchedYaml == null || _parsedYamlMap == null) // Fetch Mode
                         ? (_projectIdController.text.isNotEmpty && _apiTokenController.text.isNotEmpty ? _handleFetchOrGenerate : null) // Enable only if creds are present
                         : (_promptController.text.isNotEmpty ? _handleFetchOrGenerate : null), // Generate Mode: Enable only if prompt is present
              child: Text(_rawFetchedYaml == null || _parsedYamlMap == null ? 'Fetch YAML' : 'Generate from Prompt'),
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
