import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../storage/preferences_manager.dart';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:yaml/yaml.dart';

class OpenAIClient {
  final String apiKey;
  final String baseUrl;

  OpenAIClient(
      {required this.apiKey, this.baseUrl = '@https://api.openai.com/v1'});

  Future<Map<String, dynamic>> chat({
    required String model,
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
  }) async {
    final Uri url = Uri.parse('$baseUrl/chat/completions');

    final Map<String, dynamic> body = {
      'model': model,
      'messages': messages,
    };

    if (temperature != null) {
      body['temperature'] = temperature;
    }

    if (maxTokens != null) {
      body['max_tokens'] = maxTokens;
    }

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to get response: ${response.statusCode} ${response.body}');
    }
  }
}

class AIAssistPanel extends StatefulWidget {
  final Function(String, {String? existingFile}) onUpdateYaml;
  final Map<String, String> currentFiles;
  final Function() onClose;

  const AIAssistPanel({
    Key? key,
    required this.onUpdateYaml,
    required this.currentFiles,
    required this.onClose,
  }) : super(key: key);

  @override
  _AIAssistPanelState createState() => _AIAssistPanelState();
}

class _AIAssistPanelState extends State<AIAssistPanel> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final TextEditingController _yamlSourceController = TextEditingController();

  bool _isLoading = false;
  bool _isApiKeyValid = false;
  OpenAIClient? _openAIClient;
  List<Map<String, String>> _chatHistory = [];

  // Add a list of YAML examples
  List<String> _yamlExamples = [];
  // Add a flag to track if external examples are being loaded
  bool _isLoadingExamples = false;
  // Track the external source URL
  String? _externalSourceUrl;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
    _loadSavedYamlSource();
    // Load example YAML files
    _loadYamlExamples();
  }

  // Method to load YAML examples
  void _loadYamlExamples() {
    // Get examples from the current files being displayed
    setState(() {
      _yamlExamples = [];
      widget.currentFiles.forEach((filename, content) {
        // Only use small to medium sized YAML files as examples
        if (content.length > 100 &&
            content.length < 3000 &&
            filename.endsWith('.yaml')) {
          _yamlExamples.add("Example: $filename\n$content");

          // Limit to 5 examples to avoid token limits
          if (_yamlExamples.length >= 5) return;
        }
      });
    });
  }

  @override
  void didUpdateWidget(AIAssistPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload examples when the files change
    if (oldWidget.currentFiles != widget.currentFiles) {
      _loadYamlExamples();
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _promptController.dispose();
    _chatScrollController.dispose();
    _yamlSourceController.dispose();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    final apiKey = await PreferencesManager.getOpenAIKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      setState(() {
        _apiKeyController.text = apiKey;
        _validateApiKey(apiKey);
      });
    }
  }

  Future<void> _saveApiKey(String apiKey) async {
    await PreferencesManager.saveOpenAIKey(apiKey);
  }

  void _validateApiKey(String apiKey) {
    if (apiKey.trim().isNotEmpty) {
      try {
        _openAIClient = OpenAIClient(apiKey: apiKey);
        setState(() {
          _isApiKeyValid = true;
        });
      } catch (e) {
        setState(() {
          _isApiKeyValid = false;
        });
      }
    } else {
      setState(() {
        _isApiKeyValid = false;
      });
    }
  }

  Future<void> _sendPrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || !_isApiKeyValid) return;

    setState(() {
      _isLoading = true;
      _chatHistory.add({'role': 'user', 'content': prompt});
      _promptController.clear();
    });

    // Scroll to bottom after adding user message
    _scrollToBottom();

    try {
      // Construct system message with context about FlutterFlow YAML
      final systemMessage =
          "You're an AI assistant that helps modify FlutterFlow YAML files. "
          "Your primary purpose is to make changes to YAML files that will be uploaded back to FlutterFlow to modify their live project. "
          "IMPORTANT RULES WHEN MODIFYING YAML:\n"
          "1. DO NOT change any existing keys in the YAML structure\n"
          "2. You CAN create new keys, but ensure they are unique\n"
          "3. Preserve the existing structure and format of the YAML files\n"
          "4. When suggesting changes, always provide a complete valid YAML snippet that can be directly applied\n"
          "5. Explain what your changes will do in the FlutterFlow project";

      // Build the conversation messages
      final messages = [
        {'role': 'system', 'content': systemMessage},
      ];

      // Add YAML examples to the context if available, with token limit considerations
      if (_yamlExamples.isNotEmpty) {
        // Limit to 3 examples max when sending to API to avoid context overflow
        final limitedExamples = _yamlExamples.length > 3
            ? _yamlExamples.sublist(0, 3)
            : _yamlExamples;
        final examplesContent =
            "Here are some example FlutterFlow YAML files to help understand the structure:\n\n" +
                limitedExamples.join("\n\n---\n\n");
        messages.add({'role': 'system', 'content': examplesContent});
      }

      // Add project context with token conservation
      Map<String, String> limitedCurrentFiles = {};
      int totalContextSize = 0;

      // First pass: Include only small files
      widget.currentFiles.forEach((filename, content) {
        if (content.length < 1000 && totalContextSize < 40000) {
          limitedCurrentFiles[filename] = content;
          totalContextSize += content.length;
        }
      });

      // Only if we have token budget remaining, add medium-sized files
      if (totalContextSize < 40000) {
        widget.currentFiles.forEach((filename, content) {
          if (!limitedCurrentFiles.containsKey(filename) &&
              content.length >= 1000 &&
              content.length < 3000 &&
              totalContextSize + content.length < 40000) {
            limitedCurrentFiles[filename] = content;
            totalContextSize += content.length;
          }
        });
      }

      // Build the context message with limited files
      if (limitedCurrentFiles.isNotEmpty) {
        String filesContext = "";
        limitedCurrentFiles.forEach((filename, content) {
          filesContext += "File: $filename\n$content\n\n";
        });

        messages.add({
          'role': 'system',
          'content': "Current project files (limited selection):\n$filesContext"
        });
      }

      // Add chat history (limited to last few exchanges to avoid token limits)
      final recentHistory = _chatHistory.length > 4
          ? _chatHistory.sublist(_chatHistory.length - 4)
          : _chatHistory;

      for (final message in recentHistory) {
        messages.add(message);
      }

      // Make OpenAI API call
      final response = await _openAIClient!.chat(
        model: "gpt-4o", // Using GPT-4o as specified
        messages: messages,
        temperature: 0.7,
        maxTokens: 2000,
      );

      // Extract the assistant's response
      final assistantMessage =
          response['choices'][0]['message']['content'] as String;

      setState(() {
        _chatHistory.add({'role': 'assistant', 'content': assistantMessage});
        _isLoading = false;
      });

      // Scroll to bottom after receiving response
      _scrollToBottom();

      // Check if the assistant's message contains YAML code that should be applied
      _checkForYamlUpdates(assistantMessage);
    } catch (e) {
      setState(() {
        _chatHistory
            .add({'role': 'assistant', 'content': 'Error: ${e.toString()}'});
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _checkForYamlUpdates(String message) {
    // Look for code blocks containing YAML - match both ```yaml and ```flutterflow blocks
    final yamlCodeBlockRegex =
        RegExp(r'```(?:yaml|flutterflow)\n([\s\S]*?)\n```');
    final matches = yamlCodeBlockRegex.allMatches(message);

    for (final match in matches) {
      if (match.groupCount >= 1) {
        final yamlContent = match.group(1);
        if (yamlContent != null && yamlContent.trim().isNotEmpty) {
          // Try to identify which file this should modify
          _identifyAndShowUpdateDialog(yamlContent);
          break; // Only show dialog for the first YAML block found
        }
      }
    }
  }

  // New method to identify target file for YAML updates
  void _identifyAndShowUpdateDialog(String yamlContent) {
    try {
      // Try to parse the YAML to detect its structure
      final parsedYaml = loadYaml(yamlContent);

      // List of potential target files based on content similarity
      List<String> potentialTargets = [];
      String? bestMatch;
      double bestMatchScore = 0;

      // Check each file to find a potential match
      widget.currentFiles.forEach((fileName, content) {
        if (fileName.endsWith('.yaml')) {
          try {
            // Simple similarity check based on key presence
            final existingYaml = loadYaml(content);
            if (existingYaml is Map && parsedYaml is Map) {
              // Count matching top-level keys to determine similarity
              int matchingKeys = 0;
              int totalKeys = 0;

              parsedYaml.keys.forEach((key) {
                totalKeys++;
                if (existingYaml.containsKey(key)) {
                  matchingKeys++;
                }
              });

              // Calculate a similarity score (0.0 - 1.0)
              double similarityScore =
                  totalKeys > 0 ? matchingKeys / totalKeys : 0;

              // Consider files with at least 30% similarity as potential targets
              if (similarityScore >= 0.3) {
                potentialTargets.add(fileName);

                // Track the best match
                if (similarityScore > bestMatchScore) {
                  bestMatchScore = similarityScore;
                  bestMatch = fileName;
                }
              }
            }
          } catch (e) {
            // Ignore parsing errors for existing files
            print('Error parsing existing file $fileName: $e');
          }
        }
      });

      // Show dialog with file selection options
      _showYamlUpdateDialog(yamlContent, potentialTargets, bestMatch);
    } catch (e) {
      // If parsing fails, just show the standard dialog without file suggestions
      _showYamlUpdateDialog(yamlContent, [], null);
      print('Error parsing YAML for file identification: $e');
    }
  }

  void _showYamlUpdateDialog(
      String yamlContent, List<String> potentialTargets, String? bestMatch) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Apply FlutterFlow YAML Changes'),
        content: Container(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'The AI has suggested the following changes to your FlutterFlow project:'),
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    yamlContent,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // Add file selection for updating existing files
                if (potentialTargets.isNotEmpty) ...[
                  Text(
                    'Select the file to update:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  ...potentialTargets
                      .map(
                        (fileName) => RadioListTile<String>(
                          title: Text(fileName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: fileName == bestMatch
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              )),
                          value: fileName,
                          groupValue: bestMatch,
                          onChanged: (value) {
                            Navigator.pop(context);
                            if (value != null) {
                              // Show confirmation dialog for the selected file
                              _confirmFileUpdate(yamlContent, value);
                            }
                          },
                          dense: true,
                          selected: fileName == bestMatch,
                        ),
                      )
                      .toList(),
                  Divider(),
                ],

                Text(
                  potentialTargets.isEmpty
                      ? 'These changes will be added as a new file in your project.'
                      : 'Or create a new file with these changes:',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Create a new file if no existing file is selected
              widget.onUpdateYaml(yamlContent);
              Navigator.pop(context);
            },
            child: Text('Create New File'),
          ),
        ],
      ),
    );
  }

  // New method to confirm updating an existing file
  void _confirmFileUpdate(String yamlContent, String fileName) {
    final existingContent = widget.currentFiles[fileName] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Update to $fileName'),
        content: Container(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              Text(
                  'This will replace the existing file with the AI-generated content.'),
              SizedBox(height: 16),
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      TabBar(
                        tabs: [
                          Tab(text: 'Current'),
                          Tab(text: 'New Version'),
                        ],
                        labelColor: Colors.blue,
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // Current file content
                            SingleChildScrollView(
                              child: Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black12,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  existingContent,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            // New content
                            SingleChildScrollView(
                              child: Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black12,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  yamlContent,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Update the existing file
              widget.onUpdateYaml(yamlContent, existingFile: fileName);
              Navigator.pop(context);
            },
            child: Text('Update File'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    Future.delayed(Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Method to fetch YAML examples from a URL
  Future<void> _fetchExternalYamlExamples(String url) async {
    if (url.isEmpty) return;

    setState(() {
      _isLoadingExamples = true;
      _chatHistory.add({
        'role': 'assistant',
        'content': 'Fetching and processing YAML examples from $url...'
      });
    });

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        // Store the URL for future reference
        _externalSourceUrl = url;
        await PreferencesManager.saveYamlSourceUrl(url);

        // Process the ZIP file
        try {
          // Decode the bytes as a zip file
          final bytes = response.bodyBytes;
          final archive = ZipDecoder().decodeBytes(bytes);

          // This will store our examples
          _yamlExamples = [];
          int examplesCount = 0;
          int projectsProcessed = 0;
          int totalTokens = 0; // Track estimated token count

          // Rough token estimation: 1 token ~= 4 characters for English text
          const int MAX_TOKENS = 20000; // Set a conservative max tokens limit
          const int MAX_EXAMPLES = 5; // Reduce max examples from 10 to 5
          const int MAX_FILE_SIZE =
              2000; // Reduce max file size for safer limits

          // Process each file in the main archive
          for (final file in archive) {
            if (!file.isFile || !file.name.endsWith('.zip')) continue;

            try {
              // Each file is itself a zip file containing project YAML
              final projectBytes = file.content as List<int>;
              final projectArchive = ZipDecoder().decodeBytes(projectBytes);
              projectsProcessed++;

              // Extract YAML examples from this project
              for (final projectFile in projectArchive) {
                if (projectFile.isFile &&
                    projectFile.name.endsWith('.yaml') &&
                    projectFile.size > 100 &&
                    projectFile.size < MAX_FILE_SIZE) {
                  // Stricter file size limit

                  // Extract the file content
                  final fileData = projectFile.content as List<int>;
                  final fileContent =
                      utf8.decode(fileData, allowMalformed: true);

                  // Calculate estimated tokens for this content
                  int estimatedTokens = (fileContent.length / 4).ceil() +
                      50; // Add buffer for metadata

                  // Check if adding this would exceed our token budget
                  if (totalTokens + estimatedTokens > MAX_TOKENS) {
                    print('Token limit reached. Stopping example collection.');
                    break;
                  }

                  // Truncate very long content if needed (rare case)
                  String processedContent = fileContent;
                  if (fileContent.length > MAX_FILE_SIZE * 2) {
                    processedContent = fileContent.substring(0, MAX_FILE_SIZE) +
                        "\n\n... (content truncated for brevity) ...\n\n" +
                        fileContent.substring(fileContent.length - 500);
                  }

                  // Add as an example
                  _yamlExamples
                      .add("Example: ${projectFile.name}\n$processedContent");
                  examplesCount++;
                  totalTokens += estimatedTokens;

                  // Log token usage
                  print(
                      'Added example ${projectFile.name}, tokens: $estimatedTokens, total: $totalTokens');

                  // Limit to max examples
                  if (examplesCount >= MAX_EXAMPLES) break;
                }
              }

              // If we've collected enough examples, stop processing more projects
              if (examplesCount >= MAX_EXAMPLES || totalTokens > MAX_TOKENS)
                break;
            } catch (e) {
              print('Error processing project ZIP ${file.name}: $e');
            }
          }

          setState(() {
            _isLoadingExamples = false;
            _chatHistory.add({
              'role': 'assistant',
              'content':
                  'Successfully loaded $examplesCount YAML examples (est. $totalTokens tokens) from $projectsProcessed projects.'
            });
          });
        } catch (e) {
          throw Exception('Failed to process ZIP file: ${e.toString()}');
        }
      } else {
        throw Exception('Failed to load YAML examples: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoadingExamples = false;
        _chatHistory.add({
          'role': 'assistant',
          'content': 'Error loading external YAML examples: ${e.toString()}'
        });
      });
      _scrollToBottom();
    }
  }

  // Load saved YAML source URL
  Future<void> _loadSavedYamlSource() async {
    final savedUrl = await PreferencesManager.getYamlSourceUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _yamlSourceController.text = savedUrl;
      _fetchExternalYamlExamples(savedUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          left: BorderSide(
            color: AppTheme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildApiKeySection(),
          _buildYamlSourceSection(),
          if (_isApiKeyValid) _buildChatSection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'FlutterFlow YAML Assistant',
            style: AppTheme.headingMedium,
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: widget.onClose,
            tooltip: 'Close AI Assist',
          ),
        ],
      ),
    );
  }

  Widget _buildApiKeySection() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OpenAI API Key',
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    hintText: 'Enter your OpenAI API key',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  obscureText: true,
                ),
              ),
              SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final apiKey = _apiKeyController.text.trim();
                  _validateApiKey(apiKey);
                  _saveApiKey(apiKey);
                },
                child: Text('Save'),
              ),
            ],
          ),
          if (!_isApiKeyValid && _apiKeyController.text.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Please enter a valid OpenAI API key',
                style: TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildYamlSourceSection() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'External YAML Examples Source (Optional)',
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _yamlSourceController,
                  decoration: InputDecoration(
                    hintText: 'Enter URL to YAML examples',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              _isLoadingExamples
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ElevatedButton(
                      onPressed: () {
                        final url = _yamlSourceController.text.trim();
                        if (url.isNotEmpty) {
                          _fetchExternalYamlExamples(url);
                        }
                      },
                      child: Text('Load'),
                    ),
            ],
          ),
          if (_externalSourceUrl != null)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'External examples loaded from: $_externalSourceUrl',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatSection() {
    return Expanded(
      child: Column(
        children: [
          Divider(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Create and modify FlutterFlow YAML configurations',
              style: AppTheme.bodyMedium,
            ),
          ),
          SizedBox(height: 8),
          Expanded(
            child: _buildChatHistory(),
          ),
          _buildPromptInput(),
        ],
      ),
    );
  }

  Widget _buildChatHistory() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: ListView.builder(
        controller: _chatScrollController,
        padding: EdgeInsets.all(16),
        itemCount: _chatHistory.length,
        itemBuilder: (context, index) {
          final message = _chatHistory[index];
          final isUser = message['role'] == 'user';

          return Container(
            margin: EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isUser ? AppTheme.primaryColor : Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      isUser ? Icons.person : Icons.smart_toy,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppTheme.primaryColor.withOpacity(0.1)
                          : Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      message['content'] ?? '',
                      style: AppTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPromptInput() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promptController,
              decoration: InputDecoration(
                hintText:
                    'Describe the changes you want to make to your FlutterFlow project...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              maxLines: 3,
              minLines: 1,
              onSubmitted: (_) => _sendPrompt(),
            ),
          ),
          SizedBox(width: 8),
          IconButton(
            icon: _isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.send),
            onPressed: _isLoading ? null : _sendPrompt,
            tooltip: 'Send message',
          ),
        ],
      ),
    );
  }
}
