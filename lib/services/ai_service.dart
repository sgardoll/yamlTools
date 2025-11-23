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
    final contextFiles = _selectContextFiles(request);
    final systemPrompt = _buildSystemPrompt(request, contextFiles);

    final response = await _chat(
      model: 'gpt-4o',
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': request.userPrompt},
      ],
    );

    final content =
        (response['choices']?[0]?['message']?['content'] as String?) ?? '';
    if (content.isEmpty) {
      throw Exception('No content returned from AI service');
    }

    return _parseResponse(content, request.projectFiles);
  }

  Future<Map<String, dynamic>> _chat({
    required String model,
    required List<Map<String, String>> messages,
  }) async {
    final url = Uri.parse('$baseUrl/chat/completions');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': 0.4,
        'max_tokens': 1500,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to reach AI service: ${response.statusCode} ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Map<String, String> _selectContextFiles(AIRequest request) {
    final selected = <String, String>{};
    final maxBudget = 12000;
    int budget = 0;

    void tryAddFile(String path) {
      if (selected.containsKey(path)) return;
      final content = request.projectFiles[path];
      if (content == null) return;
      if (budget + content.length > maxBudget) return;
      selected[path] = content;
      budget += content.length;
    }

    for (final pinned in request.pinnedFilePaths) {
      tryAddFile(pinned);
    }

    final prompt = request.userPrompt.toLowerCase();
    bool mentionsAny(List<String> keywords) =>
        keywords.any((keyword) => prompt.contains(keyword.toLowerCase()));

    if (mentionsAny(['login', 'auth'])) {
      for (final path in request.projectFiles.keys) {
        if (path.contains('login') || path.contains('auth')) {
          tryAddFile(path);
        }
      }
    }

    if (mentionsAny(['database', 'schema', 'field', 'collection'])) {
      for (final path in request.projectFiles.keys) {
        if (path.contains('firestore') ||
            path.contains('schema') ||
            path.contains('collection')) {
          tryAddFile(path);
        }
      }
    }

    if (mentionsAny(['theme', 'color'])) {
      for (final path in request.projectFiles.keys) {
        if (path.contains('theme') || path.contains('color')) {
          tryAddFile(path);
        }
      }
    }

    final sortedEntries = request.projectFiles.entries.toList()
      ..sort((a, b) => a.value.length.compareTo(b.value.length));

    for (final entry in sortedEntries) {
      if (budget >= maxBudget) break;
      tryAddFile(entry.key);
    }

    return selected;
  }

  String _buildSystemPrompt(
    AIRequest request,
    Map<String, String> contextFiles,
  ) {
    final buffer = StringBuffer();
    buffer.writeln(
        'You are a FlutterFlow YAML Expert. You are an automated agent, not a chat bot.');
    buffer.writeln(
        "Your goal is to modify existing YAML files to fulfill the user's request.");
    buffer.writeln('RULES:');
    buffer.writeln('1. RETURN ONLY JSON.');
    buffer.writeln('2. Do not hallucinate file paths. Use the provided file list.');
    buffer.writeln('3. Preserved indentation is CRITICAL.');
    buffer.writeln('4. When modifying a file, return the FULL file content, not just the snippet.');
    buffer.writeln('5. Only touch YAML files the user can sync back to FlutterFlow.');

    buffer.writeln('\nINPUT CONTEXT:');
    buffer.writeln(_buildMetadataIndex(request.projectFiles));

    if (contextFiles.isNotEmpty) {
      buffer.writeln('FULL CONTENT OF PINNED/RELEVANT FILES:');
      contextFiles.forEach((path, content) {
        buffer.writeln('--- FILE: $path');
        buffer.writeln(content);
      });
    }

    buffer.writeln('\nRESPONSE FORMAT:');
    buffer.writeln('{');
    buffer.writeln('  "summary": "Brief description of change",');
    buffer.writeln('  "modifications": [');
    buffer.writeln('    {');
    buffer.writeln('      "filePath": "collections/users.yaml",');
    buffer.writeln('      "newContent": "..."');
    buffer.writeln('    }');
    buffer.writeln('  ]');
    buffer.writeln('}');

    return buffer.toString();
  }

  String _buildMetadataIndex(Map<String, String> files) {
    final buffer = StringBuffer('FILE METADATA INDEX:\n');
    for (final entry in files.entries) {
      buffer.writeln('${entry.key}: ${_topLevelKeys(entry.value).join(', ')}');
    }
    return buffer.toString();
  }

  List<String> _topLevelKeys(String content) {
    try {
      final node = loadYaml(content);
      if (node is YamlMap) {
        return node.keys.map((key) => key.toString()).toList();
      }
    } catch (_) {
      return [];
    }
    return [];
  }

  ProposedChange _parseResponse(
    String rawContent,
    Map<String, String> projectFiles,
  ) {
    String content = rawContent.trim();
    if (content.startsWith('```')) {
      final fenceIndex = content.indexOf('\n');
      if (fenceIndex != -1) {
        content = content.substring(fenceIndex + 1);
      }
      if (content.endsWith('```')) {
        content = content.substring(0, content.length - 3);
      }
    }

    Map<String, dynamic> jsonMap;
    try {
      jsonMap = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('AI response was not valid JSON: $e');
    }

    final summary = jsonMap['summary']?.toString() ?? 'AI-generated proposal';
    final List<dynamic> modsJson = jsonMap['modifications'] as List<dynamic>? ?? [];

    if (modsJson.isEmpty) {
      throw Exception('AI response did not include any modifications');
    }

    final mods = modsJson.map((mod) {
      final map = mod as Map<String, dynamic>;
      final filePath = map['filePath']?.toString() ?? '';
      final newContent = map['newContent']?.toString() ?? '';
      final originalContent = projectFiles[filePath] ?? '';
      final isNewFile = !projectFiles.containsKey(filePath);
      if (filePath.isEmpty || newContent.isEmpty) {
        throw Exception('AI response missing filePath or newContent');
      }
      return FileModification(
        filePath: filePath,
        originalContent: originalContent,
        newContent: newContent,
        isNewFile: isNewFile,
      );
    }).toList();

    return ProposedChange(summary: summary, modifications: mods);
  }
}
