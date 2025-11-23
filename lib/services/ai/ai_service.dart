import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ai_models.dart';
import 'openai_client.dart';

// Updated System Prompt for strict FlutterFlow compliance
class AIService {
  final String apiKey;
  late final OpenAIClient _client;

  AIService(this.apiKey) {
    _client = OpenAIClient(apiKey: apiKey);
  }

  Future<ProposedChange> requestModification({
    required AIRequest request,
  }) async {
    // 1. Prepare Context
    final contextData = _prepareContext(request);

    // 2. Construct Messages
    final messages = [
      {
        'role': 'system',
        'content': _buildSystemPrompt(),
      },
      {
        'role': 'user',
        'content': _buildUserMessage(request.userPrompt, contextData),
      }
    ];

    try {
      // 3. Call OpenAI
      final response = await _client.chat(
        model: "gpt-4o",
        messages: messages,
        temperature: 0.1, // Low temperature for deterministic code generation
        maxTokens: 4000,
        responseFormat: {"type": "json_object"},
      );

      final content = response['choices'][0]['message']['content'] as String;
      
      // 4. Parse Response
      return _parseResponse(content, request.projectFiles);
    } catch (e) {
      debugPrint("AI Service Error: $e");
      rethrow;
    }
  }

  String _prepareContext(AIRequest request) {
    final buffer = StringBuffer();
    
    // Always add pinned files
    for (final path in request.pinnedFilePaths) {
      if (request.projectFiles.containsKey(path)) {
        buffer.writeln("File: $path");
        buffer.writeln("```yaml");
        buffer.writeln(request.projectFiles[path]);
        buffer.writeln("```");
        buffer.writeln("");
      }
    }

    // Heuristic selection (simple version)
    // Add file names for context
    buffer.writeln("Available Files:");
    for (final path in request.projectFiles.keys) {
      buffer.writeln("- $path");
    }

    // Identify potentially relevant files based on keywords if not pinned
    // This is a simplified heuristic. In a real app, this would be more robust.
    final promptLower = request.userPrompt.toLowerCase();
    
    request.projectFiles.forEach((path, content) {
      if (request.pinnedFilePaths.contains(path)) return; // Already added

      bool isRelevant = false;
      
      // Check for direct filename mention
      if (promptLower.contains(path.toLowerCase().split('/').last.split('.').first)) {
        isRelevant = true;
      }
      
      // Simple keyword matching
      if (promptLower.contains('theme') && path.contains('theme')) isRelevant = true;
      if (promptLower.contains('color') && path.contains('colors')) isRelevant = true;
      if ((promptLower.contains('db') || promptLower.contains('database') || promptLower.contains('collection')) && 
          (path.contains('firestore') || path.contains('schema'))) isRelevant = true;
      if (promptLower.contains('page') && path.contains('pages/')) isRelevant = true;

      // Add if relevant and small enough (simple token management)
      if (isRelevant && content.length < 10000) {
         buffer.writeln("File: $path");
         buffer.writeln("```yaml");
         buffer.writeln(content);
         buffer.writeln("```");
         buffer.writeln("");
      }
    });

    return buffer.toString();
  }

  String _buildSystemPrompt() {
    return '''
You are a FlutterFlow Project API YAML Expert.
Modify the provided YAML files to fulfill the user's request, strictly adhering to the FlutterFlow Project API schema.

STRICT GUIDELINES:
1. **PRESERVE EVERYTHING**: Return the **FULL** file content. Do not delete or modify ANY content (keys, comments, order) unless explicitly requested.
2. **STRICT SCHEMA**: Follow the existing patterns exactly.
   - Use `inputValue` wrappers (e.g., `fontSizeValue: { inputValue: 12 }`).
   - Use `themeColor` references (e.g., `colorValue: { inputValue: { themeColor: PRIMARY } }`).
3. **IDENTIFIERS**:
   - `key`: IMMUTABLE system ID. **NEVER CHANGE**.
   - `name`: Display name. Mutable.
4. **NO UI EDITS**: Widget trees are JSON. Do not attempt to restructure UI via YAML.

RESPONSE FORMAT (JSON ONLY):
{
  "summary": "Brief description",
  "modifications": [
    {
      "filePath": "exact/file/path.yaml",
      "newContent": "<FULL_UPDATED_YAML_CONTENT>",
      "isNewFile": false,
      "touchedPaths": ["modified.path"]
    }
  ]
}
''';
  }

  String _buildUserMessage(String prompt, String contextData) {
    return '''
Request: $prompt

INPUT CONTEXT:
$contextData
''';
  }

  ProposedChange _parseResponse(String jsonContent, Map<String, String> originalFiles) {
    try {
      final Map<String, dynamic> json = jsonDecode(jsonContent);
      
      // Enrich with original content
      if (json['modifications'] != null) {
        for (var mod in json['modifications']) {
          String path = mod['filePath'];
          // Ensure we don't overwrite originalContent if it's already there (though the API likely doesn't send it)
          if (originalFiles.containsKey(path)) {
            mod['originalContent'] = originalFiles[path];
          } else {
             mod['originalContent'] = ''; // New file or not found
             mod['isNewFile'] = true;
          }
        }
      }
      
      return ProposedChange.fromJson(json);
    } catch (e) {
      throw Exception("Failed to parse AI response: $e\nResponse: $jsonContent");
    }
  }
}
