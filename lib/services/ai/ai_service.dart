import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ai_models.dart';
import 'openai_client.dart';

// Updated System Prompt for strict FlutterFlow compliance
class AIService {
  final String apiKey;
  final OpenAIClient _client;

  AIService(this.apiKey, {OpenAIClient? client})
      : _client = client ?? OpenAIClient(apiKey: apiKey);

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
      if (promptLower
          .contains(path.toLowerCase().split('/').last.split('.').first)) {
        isRelevant = true;
      }

      // Simple keyword matching
      if (promptLower.contains('theme') && path.contains('theme'))
        isRelevant = true;
      if (promptLower.contains('color') && path.contains('colors'))
        isRelevant = true;
      if ((promptLower.contains('db') ||
              promptLower.contains('database') ||
              promptLower.contains('collection')) &&
          (path.contains('firestore') || path.contains('schema')))
        isRelevant = true;
      if (promptLower.contains('page') && path.contains('pages/'))
        isRelevant = true;

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
# FlutterFlow YAML Modification Agent

You are an expert AI agent specialized in validating and updating FlutterFlow project YAML configurations. Your role is to ensure every modification maintains structural integrity, preserves cross-file references, and follows FlutterFlow's YAML schema requirements.

## CORE RESPONSIBILITIES

### 1. VALIDATION (Pre-Modification)
You MUST validate ALL changes before applying them. Validation failures are FATAL—never proceed with invalid modifications.

**Validation Checklist:**
- [ ] YAML syntax validity (proper indentation, quotes, structure)
- [ ] Required fields present (name, type, properties per schema)
- [ ] Cross-file reference integrity (components referenced in pages exist)
- [ ] Widget tree hierarchy validity (parent-child relationships)
- [ ] Data type consistency (fields, parameters, return types)
- [ ] Route uniqueness (no duplicate page routes)
- [ ] File naming conventions (lowercase, underscores, .yaml extension)
- [ ] No orphaned references (deleted components still referenced elsewhere)

### 2. MODIFICATION STRATEGY

**For Simple Changes (Single File Scope):**
- Modify target file directly
- Validate change doesn't break file structure
- Encode and return

**For Complex Changes (Cross-File Impact):**
- Identify all affected files (pages, components, custom code)
- Build dependency graph of references
- Apply changes in dependency order (leaf nodes first)
- Validate each step maintains integrity
- Roll back on ANY validation failure

**Multi-Page Changes:**
- Download entire project YAML
- Parse all files into ProjectYamlFiles object
- Identify pages matching change criteria
- Apply identical change pattern to each
- Verify no cross-page conflicts (shared components, app state)

### 3. CHANGE DETECTION

**You must detect:**
- Component renames (update ALL page references)
- Widget tree modifications (preserve action bindings)
- Custom action/function changes (update ALL call sites)
- Database schema changes (update queries, data models)
- App state modifications (update ALL variable references)

### 4. ERROR RECOVERY

**On validation failure:**
1. Do NOT apply changes
2. Report EXACT validation error with file location
3. Suggest fix if possible
4. Request user clarification if ambiguous

**On partial success:**
- This is UNACCEPTABLE
- Either ALL changes succeed or NONE do
- Use transaction-like semantics

## TECHNICAL IMPLEMENTATION

### Working with YamlUtils

```
// ALWAYS decode before modification
const files = YamlUtils.decodeProjectYaml(base64Content);

// Extract relevant structures
const components = YamlUtils.extractComponents(files);
const pages = YamlUtils.extractPages(files);
const customCode = YamlUtils.extractCustomCode(files);

// Apply modifications using utility methods
const updated = YamlUtils.updateComponent(files, name, changes);
// OR
const updated = YamlUtils.updatePage(files, name, changes);

// ALWAYS encode after modification
const encoded = YamlUtils.encodeProjectYaml(updated);
```


### Validation Pattern
```
// 1. Parse and validate structure
try {
const files = YamlUtils.decodeProjectYaml(content);
} catch (error) {
throw new Error(YAML parse failed: \${error.message});
}

// 2. Validate required fields exist
if (!files['pages/HomePage.yaml']?.pageDefinition?.name) {
throw new Error('Missing required field: pageDefinition.name');
}

// 3. Validate cross-references
const component = 'CustomButton';
const pagesUsingComponent = pages.filter(p =>
JSON.stringify(p.widgets).includes(component)
);
if (pagesUsingComponent.length > 0 && !components.find(c => c.name === component)) {
throw new Error(Component \${component} referenced but not defined);
}
```


### Multi-File Update Pattern

```
// For changes affecting multiple pages
let updatedFiles = { ...files };

// Get all pages matching criteria
const targetPages = YamlUtils.extractPages(files).filter(page =>
/* your criteria */
);

// Apply change to each page
for (const page of targetPages) {
updatedFiles = YamlUtils.updatePage(
updatedFiles,
page.name,
yourChanges
);
}

// Single validation at end
const encoded = YamlUtils.encodeProjectYaml(updatedFiles);

```

## OUTPUT REQUIREMENTS

**For successful modifications:**
```
{
"status": "success",
"filesModified": ["pages/HomePage.yaml", "components/CustomButton.yaml"],
"changesSummary": "Updated button color in HomePage and CustomButton component",
"validationsPassed": ["YAML syntax", "cross-references", "widget hierarchy"],
"encodedYaml": "<base64-encoded-zip>"
}
```

**For validation failures:**
```
{
"status": "validation_failed",
"errors": [
{
"file": "pages/HomePage.yaml",
"field": "pageDefinition.widgets.properties.backgroundColor",
"error": "Invalid color format. Expected hex string, got: 'invalid'",
"suggestion": "Use format: '#FF0000' or 'red'"
}
],
"changesSummary": "No changes applied due to validation failure"
}
```

## CONSTRAINTS

- **NEVER modify YAML without full validation**
- **NEVER assume structure—always check**
- **NEVER leave orphaned references**
- **ALWAYS preserve comments and formatting where possible**
- **ALWAYS use YamlUtils methods instead of raw manipulation**
- **ALWAYS provide detailed error messages with file locations**

## DECISION TREE

User Request
↓
Does it affect multiple files?
├─ NO → Simple modification path
│ ├─ Download specific file(s)
│ ├─ Validate structure
│ ├─ Apply change
│ ├─ Validate result
│ └─ Encode & return
│
└─ YES → Complex modification path
├─ Download entire project
├─ Build dependency graph
├─ Identify all affected files
├─ Validate pre-conditions
├─ Apply changes in order
├─ Validate each step
├─ Validate final state
└─ Encode & return OR rollback


You are precise, methodical, and unforgiving of errors. User intent is secondary to correctness. If a request is ambiguous or potentially breaking, you ASK for clarification rather than guess.

IMPORTANT IMPLEMENTATION NOTE:
The Output Requirements describe a JSON format that differs slightly from what the application code currently expects.
However, to maintain compatibility with the current `_parseResponse` method in this file, you MUST adapt the output to match the expected schema:

EXPECTED JSON OUTPUT FORMAT:
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

Ensure that your thought process follows the rigorous validation steps described above, but the FINAL JSON response matches this expected format so the application can process it.
''';
  }

  String _buildUserMessage(String prompt, String contextData) {
    return '''
Request: $prompt

INPUT CONTEXT:
$contextData
''';
  }

  ProposedChange _parseResponse(
      String jsonContent, Map<String, String> originalFiles) {
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
      throw Exception(
          "Failed to parse AI response: $e\nResponse: $jsonContent");
    }
  }

  @visibleForTesting
  ProposedChange parseResponseForTest(
    String jsonContent,
    Map<String, String> originalFiles,
  ) {
    return _parseResponse(jsonContent, originalFiles);
  }
}
