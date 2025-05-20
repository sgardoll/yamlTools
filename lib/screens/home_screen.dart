import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // Keep for potential future JSON parts, though YAML is primary
import 'package:yaml/yaml.dart';

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
  Map<String, dynamic>? _parsedYamlMap; // To store the parsed YAML
  String _generatedYamlMessage = 'Enter Project ID and API Token to fetch YAML.'; // Display messages/results

  @override
  void dispose() {
    // Dispose controllers when the widget is removed from the widget tree
    _promptController.dispose();
    _projectIdController.dispose();
    _apiTokenController.dispose();
    super.dispose();
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
        _rawFetchedYaml = response.body;
        if (_rawFetchedYaml == null || _rawFetchedYaml!.trim().isEmpty) {
           setState(() {
            _generatedYamlMessage = 'Error: Fetched YAML is empty or whitespace.';
            _rawFetchedYaml = null; // Ensure it's null if invalid
          });
        } else {
          _parseFetchedYaml(); // Parse after fetching
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
        setState(() {
          _generatedYamlMessage = 'YAML fetched and parsed successfully. Enter a prompt and click the button again to generate/modify.';
        });
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
  dynamic _convertYamlNode(dynamic nodeValue) { // Renamed 'node' to 'nodeValue' for clarity
    if (nodeValue is YamlMap) {
      final Map<String, dynamic> newMap = {};
      nodeValue.nodes.forEach((keyNode, valueNode) { // keyNode is YamlNode, valueNode is YamlNode
        String key = (keyNode is YamlScalar) ? keyNode.value.toString() : keyNode.toString();
        newMap[key] = _convertYamlNode(valueNode.value); // Recurse on the .value of the YamlNode
      });
      return newMap;
    } else if (nodeValue is YamlList) {
      return List<dynamic>.from(nodeValue.nodes.map((itemNode) => _convertYamlNode(itemNode.value))); // Recurse on the .value of the YamlNode
    }
    // If nodeValue is YamlScalar, its .value is the actual primitive (String, num, bool).
    // If nodeValue is already a primitive (e.g. from a previous conversion), return as is.
    return nodeValue is YamlScalar ? nodeValue.value : nodeValue;
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
              // Ensure all elements in pagesEntry are Map<String, dynamic>
              List<Map<String, dynamic>> typedPagesList = [];
              bool conversionSuccess = true;
              for (var item in pagesEntry) {
                if (item is Map) {
                  typedPagesList.add(Map<String, dynamic>.from(item));
                } else {
                  // Handle case where an item is not a map, perhaps by skipping or erroring
                  // For now, let's error if structure is not as expected.
                  conversionSuccess = false;
                  break;
                }
              }

              if (!conversionSuccess) {
                operationMessage = "Error: 'pages' list contains elements that are not valid page objects (maps).";
              } else {
                 _parsedYamlMap!['pages'] = typedPagesList; // Use the correctly typed list
                bool pageExists = typedPagesList.any((p) => p['name']?.toString().toLowerCase() == pageName.toLowerCase());
                if (pageExists) {
                  operationMessage = 'Error: Page named "$pageName" already exists.';
                } else {
                  typedPagesList.add({'name': pageName, 'widgets': []});
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
                      pageToUpdate = Map<String, dynamic>.from(page); // Make it mutable
                      pageIndex = i;
                      break;
                  }
              }

              if (pageToUpdate != null && pageIndex != -1) {
                pageToUpdate['backgroundColor'] = colorValue;
                pagesList[pageIndex] = pageToUpdate; // Update the list with the modified map
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

      // Finalize by setting the message and converting map to JSON for display
      try {
        final jsonEncoder = JsonEncoder.withIndent('  ');
        final jsonString = jsonEncoder.convert(_parsedYamlMap);
        setState(() {
          _generatedYamlMessage = '$operationMessage\n\nModified YAML (displayed as JSON):\n\n$jsonString';
        });
      } catch (e) {
        setState(() {
          // If JSON conversion fails, show the operation message and the error
          _generatedYamlMessage = '$operationMessage\n\nCould not display full structure as JSON.\nError details: $e';
        });
        print('Error converting map to JSON for display: $e');
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
              onPressed: _handleFetchOrGenerate,
              child: Text(_rawFetchedYaml == null ? 'Fetch YAML' : 'Generate from Prompt'),
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
