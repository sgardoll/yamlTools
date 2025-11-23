import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

class AIRequest {
  final String userPrompt;
  final List<String> pinnedFilePaths;
  final Map<String, String> projectFiles;

  AIRequest({
    required this.userPrompt,
    required this.pinnedFilePaths,
    required this.projectFiles,
  });
}

class FileModification {
  final String filePath;
  final String originalContent;
  final String newContent;
  final bool isNewFile;

  FileModification({
    required this.filePath,
    required this.originalContent,
    required this.newContent,
    required this.isNewFile,
  });
}

class ProposedChange {
  final String summary;
  final List<FileModification> modifications;

  ProposedChange({required this.summary, required this.modifications});
}

class AIService {
  final String apiKey;
  final String baseUrl;

  AIService({required this.apiKey, this.baseUrl = 'https://api.openai.com/v1'});

  Future<ProposedChange> requestModification({
    required AIRequest request,
  }) async {
    final Uri url = Uri.parse('$baseUrl/chat/completions');
    final messages = _buildMessages(request);

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4o',
        'messages': messages,
        'temperature': 0.4,
        'max_tokens': 2000,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get response: ${response.statusCode} ${response.body}');
    }

    final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        responseBody['choices'][0]['message']['content'] as String? ?? '';
    return _parseResponse(content, request.projectFiles);
  }

  List<Map<String, String>> _buildMessages(AIRequest request) {
    final systemPrompt =
        '''You are a FlutterFlow YAML Expert. You are an automated agent, not a chat bot.
Your goal is to modify existing YAML files to fulfill the user's request.

RULES:
1. RETURN ONLY JSON.
2. Do not hallucinate file paths. Use the provided file list.
3. Preserved indentation is CRITICAL.
4. When modifying a file, return the FULL file content, not just the snippet.

RESPONSE FORMAT:
{
  "summary": "Brief description of change",
  "modifications": [
    {
      "filePath": "collections/users.yaml",
      "newContent": "..."
    }
  ]
}''';

    final List<Map<String, String>> messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'system', 'content': _buildMetadataContext(request.projectFiles)},
      {
        'role': 'system',
        'content': _buildPinnedFilesContext(request.pinnedFilePaths, request.projectFiles),
      },
      {'role': 'user', 'content': request.userPrompt},
    ];

    return messages;
  }

  String _buildMetadataContext(Map<String, String> projectFiles) {
    final buffer = StringBuffer('Project file manifest with top-level keys:\n');
    projectFiles.forEach((path, content) {
      final keys = _extractTopLevelKeys(content).join(', ');
      buffer.writeln('- $path: [$keys]');
    });
    return buffer.toString();
  }

  String _buildPinnedFilesContext(
      List<String> pinnedPaths, Map<String, String> projectFiles) {
    if (pinnedPaths.isEmpty) return 'No files pinned by the user.';
    final buffer = StringBuffer('Pinned file contents (use these first):\n');
    for (final path in pinnedPaths) {
      final content = projectFiles[path];
      if (content != null) {
        buffer.writeln('FILE: $path');
        buffer.writeln(content);
        buffer.writeln('---');
      }
    }
    return buffer.toString();
  }

  List<String> _extractTopLevelKeys(String content) {
    try {
      final yaml = loadYaml(content);
      if (yaml is Map) {
        return yaml.keys.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // Ignore parse errors and fall back to empty list
    }
    return [];
  }

  ProposedChange _parseResponse(
      String content, Map<String, String> projectFiles) {
    String cleaned = content.trim();
    final fenceRegex = RegExp(r'```json\s*([\s\S]*?)\s*```');
    final fenceMatch = fenceRegex.firstMatch(cleaned);
    if (fenceMatch != null) {
      cleaned = fenceMatch.group(1) ?? cleaned;
    }

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Unable to parse AI response as JSON: $e');
    }

    final summary = parsed['summary']?.toString() ?? 'Proposed changes';
    final modificationsJson = parsed['modifications'] as List<dynamic>? ?? [];

    final modifications = modificationsJson.map((rawMod) {
      final modMap = rawMod as Map<String, dynamic>;
      final filePath = modMap['filePath']?.toString() ?? 'unknown.yaml';
      final newContent = modMap['newContent']?.toString() ?? '';
      final original = projectFiles[filePath] ?? '';
      return FileModification(
        filePath: filePath,
        originalContent: original,
        newContent: newContent,
        isNewFile: !projectFiles.containsKey(filePath),
      );
    }).toList();

    return ProposedChange(summary: summary, modifications: modifications);
  }
}
