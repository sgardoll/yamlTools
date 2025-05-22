import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../storage/preferences_manager.dart';
import 'dart:convert';

class OpenAIClient {
  final String apiKey;
  final String baseUrl;

  OpenAIClient(
      {required this.apiKey, this.baseUrl = 'https://api.openai.com/v1'});

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

    // Add file_id for file retrieval
    body['file_ids'] = ["file-FxxrDYzFyN3geZb9rt5Ay4"];

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
  final Function(String) onUpdateYaml;
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

  bool _isLoading = false;
  bool _isApiKeyValid = false;
  OpenAIClient? _openAIClient;
  List<Map<String, String>> _chatHistory = [];

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _promptController.dispose();
    _chatScrollController.dispose();
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
          "You have access to example FlutterFlow YAML files in vector storage with file ID file-FxxrDYzFyN3geZb9rt5Ay4. "
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

      // Add relevant file content as context
      String filesContext = "";
      widget.currentFiles.forEach((filename, content) {
        // Only include small files to avoid token limits
        if (content.length < 5000) {
          filesContext += "File: $filename\n$content\n\n";
        } else {
          filesContext +=
              "File: $filename (too large to include full content)\n";
        }
      });

      if (filesContext.isNotEmpty) {
        messages.add({
          'role': 'system',
          'content': "Current project files:\n$filesContext"
        });
      }

      // Add chat history (limited to last few exchanges to avoid token limits)
      final recentHistory = _chatHistory.length > 6
          ? _chatHistory.sublist(_chatHistory.length - 6)
          : _chatHistory;

      for (final message in recentHistory) {
        messages.add(message);
      }

      // Make OpenAI API call
      final response = await _openAIClient!.chat(
        model: "gpt-4o", // Using GPT-4o as specified (similar to GPT-4.1)
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
          // Ask the user if they want to apply this YAML
          _showYamlUpdateDialog(yamlContent);
          break; // Only show dialog for the first YAML block found
        }
      }
    }
  }

  void _showYamlUpdateDialog(String yamlContent) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Apply FlutterFlow YAML Changes?'),
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
                Text(
                  'Note: These changes will be added to your project as a new file that you can then upload to FlutterFlow.',
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
              widget.onUpdateYaml(yamlContent);
              Navigator.pop(context);
            },
            child: Text('Apply Changes'),
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
