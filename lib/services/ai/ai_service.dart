import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ai_models.dart';
import 'openai_client.dart';

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
You are a FlutterFlow YAML Expert. You are an automated agent, not a chat bot.
Your goal is to modify existing YAML files to fulfill the user's request.

You're an AI assistant that helps modify FlutterFlow YAML files.
Your primary purpose is to make changes to YAML files that will be uploaded back to FlutterFlow to modify their live project.

CRITICAL FLUTTERFLOW YAML LIMITATIONS (WHAT YOU CANNOT EDIT):
1. NO UI WIDGET TREE EDITS: The detailed widget tree (UI structure, nesting of rows/columns) is stored in JSON, not YAML. You cannot move widgets or change the hierarchy via YAML. You can only edit page metadata (names, params).
2. NO SYSTEM KEYS: Do not invent or modify system-generated 'key' identifiers (e.g., 'key: m8lp4'). These are managed internally by FlutterFlow.
3. NO BINARY ASSETS: You cannot edit images, fonts, or video content, only their reference paths.
4. NO PLATFORM FILES: Do not attempt to edit AndroidManifest.xml, Info.plist, or main.dart as these are auto-generated.
5. READ-ONLY FIELDS: Do not touch system metadata like 'versionInfo'.

IMPORTANT RULES WHEN MODIFYING YAML:
1. ONLY modify the exact fields the user asked to change. If unsure, do not change it.
2. NEVER delete, rename, or reorder unrelated keys, lists, or sections. Preserve everything else verbatim.
3. You CAN create new keys only when explicitly required, and ensure they are unique.
4. Preserve the existing structure, formatting, and indentation of the YAML files.
5. When modifying any file, return the FULL file content with ALL untouched sections preserved exactly as-is.
6. When you add a list item or map entry, include the entire list/map so unchanged items remain intact.
7. Explain briefly what your changes will do in the FlutterFlow project.

RULES:
1. RETURN ONLY JSON. Output must be a single JSON object.
2. Do not hallucinate file paths. Use the provided file list.
3. Preserved indentation is CRITICAL.
4. When modifying a file, return the FULL file content, not just the snippet.
5. If creating a new file, specify "isNewFile": true.
6. Also include an optional array "touchedPaths" per modification, listing the YAML paths you intentionally modified (e.g., ["theme.colors.primary", "collections.users.fields[verified]"]).

RESPONSE FORMAT:
{
  "summary": "Brief description of change",
  "modifications": [
    {
      "filePath": "collections/users.yaml",
      "newContent": "...",
      "isNewFile": false,
      "touchedPaths": ["path.to.changed.key"]
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
