import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yaml_generator_app/services/ai/ai_models.dart';
import 'package:yaml_generator_app/services/ai/ai_service.dart';
import 'package:yaml_generator_app/services/ai/openai_client.dart';
import 'package:yaml_generator_app/services/flutterflow_api_service.dart';
import 'package:yaml_generator_app/services/yaml_file_utils.dart';

class _FakeOpenAIClient extends OpenAIClient {
  _FakeOpenAIClient(this.fakeResponse) : super(apiKey: 'test-key');

  final Map<String, dynamic> fakeResponse;
  List<Map<String, dynamic>>? lastInput;
  String? lastModel;
  int? lastMaxOutputTokens;
  Map<String, dynamic>? lastTextConfig;

  @override
  Future<Map<String, dynamic>> respond({
    required String model,
    required List<Map<String, dynamic>> input,
    double? temperature,
    int? maxOutputTokens,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? textConfig,
  }) async {
    lastModel = model;
    lastInput = input;
    lastTextConfig = textConfig;
    lastMaxOutputTokens = maxOutputTokens;
    return fakeResponse;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterFlowApiService', () {
    test('converts file names to API keys across folders', () {
      final result = FlutterFlowApiService.convertFileNamesToKeys({
        'archive_pages/home.yaml': 'home',
        'theme/colors.yml': 'colors',
        'archive_custom_actions/auth.yaml': 'auth',
        'custom_actions/branch.yaml': 'branch',
        'pages/id-Scaffold_123/page-widget-tree-outline.yaml': 'outline',
        'complete_raw.yaml': 'raw',
      });

      expect(
        result.keys,
        containsAll([
          'page/home',
          'customAction/auth',
          'customAction/branch',
          'theme/colors',
          'page/id-Scaffold_123/page-widget-tree-outline',
          'complete_raw',
        ]),
      );
      expect(result['page/home'], 'home');
      expect(result['customAction/auth'], 'auth');
      expect(result['customAction/branch'], 'branch');
      expect(result['theme/colors'], 'colors');
      expect(
        result['page/id-Scaffold_123/page-widget-tree-outline'],
        'outline',
      );
      expect(result['complete_raw'], 'raw');
    });

    test('builds rich API exceptions with JSON bodies', () {
      final response = http.Response(
        jsonEncode({'error': 'Invalid file key', 'message': 'details'}),
        422,
      );

      final exception = FlutterFlowApiService.buildApiException(
        endpoint: 'https://api.flutterflow.io/v2/updateProjectYaml',
        response: response,
        note: 'validation failed',
      );

      expect(exception.statusCode, 422);
      expect(exception.message, 'Invalid file key');
      expect(exception.body, contains('Invalid file key'));
      expect(exception.note, 'validation failed');
    });
  });

  group('YamlFileUtils', () {
    test('infers page file path and key from YAML content', () {
      const yaml = '''
page:
  key: id-Scaffold_example
  name: Example
  widgets: []
''';

      final path = YamlFileUtils.inferFilePathFromContent(yaml);
      final key = YamlFileUtils.inferFileKeyFromContent(yaml);

      expect(path, 'page/id-Scaffold_example.yaml');
      expect(key, 'page/id-Scaffold_example');
    });

    test('does not double-append extension when key already has .yaml', () {
      const yaml = '''
page:
  key: Scaffold_hur6kpbk.yaml
  name: Example
''';

      final path = YamlFileUtils.inferFilePathFromContent(yaml);
      final key = YamlFileUtils.inferFileKeyFromContent(yaml);

      expect(path, 'page/Scaffold_hur6kpbk.yaml');
      expect(key, 'page/Scaffold_hur6kpbk');
    });

    test('auto-fixes key to match file path, stripping id- prefix', () {
      const yaml = '''
page:
  key: Scaffold_wrong
  name: Example
''';

      final result = YamlFileUtils.ensureKeyMatchesFile(
        yaml,
        'archive_page/id-Scaffold_fixed.yaml',
      );

      expect(result.changed, isTrue);
      expect(result.expectedKey, 'Scaffold_fixed');
      expect(result.content.contains('key: Scaffold_fixed'), isTrue);
    });

    test('normalizes archive_pages prefix to page for API keys', () {
      final normalized = YamlFileUtils.normalizeFilePath('archive_pages/home.yaml');

      expect(normalized.canonicalPath, 'page/home.yaml');
      expect(normalized.apiFileKey, 'page/home');
      expect(normalized.expectedYamlKey, 'home');
    });

    test('normalizes archive_custom_actions prefix to customAction', () {
      final normalized = YamlFileUtils.normalizeFilePath(
        'archive_custom_actions/id-login.yaml',
      );

      expect(normalized.canonicalPath, 'customAction/id-login.yaml');
      expect(normalized.apiFileKey, 'customAction/id-login');
      expect(normalized.expectedYamlKey, 'login');
    });

    test('infers theme and component file paths from YAML content', () {
      const themeYaml = '''
theme:
  key: theme
  name: App Theme
''';
      const componentYaml = '''
component:
  key: button_primary
  name: Primary Button
''';

      final themePath = YamlFileUtils.inferFilePathFromContent(themeYaml);
      final themeKey = YamlFileUtils.inferFileKeyFromContent(themeYaml);

      final componentPath =
          YamlFileUtils.inferFilePathFromContent(componentYaml);
      final componentKey =
          YamlFileUtils.inferFileKeyFromContent(componentYaml);

      expect(themePath, 'theme/theme.yaml');
      expect(themeKey, 'theme/theme');
      expect(componentPath, 'component/button_primary.yaml');
      expect(componentKey, 'component/button_primary');
    });
  });

  group('AIService', () {
    test('returns proposed changes with original content for known files', () async {
      final fakeClient = _FakeOpenAIClient({
        'output': [
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'text',
                'text': jsonEncode({
                  'summary': 'Update home page',
                  'modifications': [
                    {
                      'filePath': 'pages/home.yaml',
                      'newContent': 'updated content',
                      'touchedPaths': ['widgets'],
                    }
                  ],
                }),
              }
            ],
          },
        ],
      });

      final service = AIService('test-key', client: fakeClient);
      final result = await service.requestModification(
        request: AIRequest(
          userPrompt: 'Update the home page widget',
          pinnedFilePaths: ['pages/home.yaml'],
          projectFiles: {
            'pages/home.yaml': 'original content',
            'theme/colors.yaml': 'color yaml',
          },
        ),
      );

      expect(fakeClient.lastModel, 'gpt-5.1');
      expect(fakeClient.lastTextConfig, {
        'format': {'type': 'json_object'}
      });
      expect(
        fakeClient.lastInput?.last['content']?.first['text'],
        contains('pages/home.yaml'),
      );
      expect(fakeClient.lastMaxOutputTokens, 8192);

      final mod = result.modifications.single;
      expect(mod.originalContent, 'original content');
      expect(mod.isNewFile, isFalse);
      expect(mod.touchedPaths, contains('widgets'));
    });

    test('parses response when reasoning output precedes message output', () async {
      final fakeClient = _FakeOpenAIClient({
        'output': [
          {
            'id': 'rs_reasoning',
            'type': 'reasoning',
            'summary': [],
          },
          {
            'id': 'msg_result',
            'type': 'message',
            'status': 'completed',
            'content': [
              {
                'type': 'output_text',
                'text': jsonEncode({
                  'summary': 'Validation Report: Ambiguous request',
                  'modifications': [],
                }),
              }
            ],
            'role': 'assistant',
          },
        ],
      });

      final service = AIService('test-key', client: fakeClient);
      final result = await service.requestModification(
        request: AIRequest(
          userPrompt: 'Adjust padding everywhere',
          pinnedFilePaths: [],
          projectFiles: const {
            'pages/home.yaml': 'original content',
          },
        ),
      );

      expect(result.summary, contains('Validation Report'));
      expect(result.modifications, isEmpty);
    });

    test('throws when response is incomplete due to max_output_tokens', () async {
      final fakeClient = _FakeOpenAIClient({
        'status': 'incomplete',
        'incomplete_details': {'reason': 'max_output_tokens'},
        'output': [
          {
            'id': 'rs_reasoning',
            'type': 'reasoning',
            'summary': [],
          },
        ],
      });

      final service = AIService('test-key', client: fakeClient);

      expect(
        () => service.requestModification(
          request: AIRequest(
            userPrompt: 'Change padding globally',
            pinnedFilePaths: const [],
            projectFiles: const {
              'pages/home.yaml': 'original content',
            },
          ),
        ),
        throwsA(predicate((e) => e.toString().contains('max_output_tokens'))),
      );
    });

    test('includes all small files when none are pinned', () async {
      final fakeClient = _FakeOpenAIClient({
        'output': [
          {
            'id': 'msg_result',
            'type': 'message',
            'status': 'completed',
            'content': [
              {
                'type': 'output_text',
                'text': jsonEncode({
                  'summary': 'OK',
                  'modifications': [],
                }),
              }
            ],
            'role': 'assistant',
          },
        ],
      });

      final service = AIService('test-key', client: fakeClient);
      await service.requestModification(
        request: AIRequest(
          userPrompt: 'general change',
          pinnedFilePaths: const [],
          projectFiles: const {
            'pages/home.yaml': 'home content',
            'theme/colors.yaml': 'color content',
          },
        ),
      );

      final userMessage =
          fakeClient.lastInput?.last['content']?.first['text'] as String?;
      expect(userMessage, isNotNull);
      expect(userMessage, contains('File: pages/home.yaml'));
      expect(userMessage, contains('home content'));
      expect(userMessage, contains('File: theme/colors.yaml'));
      expect(userMessage, contains('color content'));
    });

    test('marks files missing from the project as new', () async {
      final fakeClient = _FakeOpenAIClient({
        'output': [
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'text',
                'text': jsonEncode({
                  'summary': 'Add a new config file',
                  'modifications': [
                    {
                      'filePath': 'config/app.yaml',
                      'newContent': 'name: demo',
                    }
                  ],
                }),
              }
            ],
          },
        ],
      });

      final service = AIService('test-key', client: fakeClient);
      final result = await service.requestModification(
        request: AIRequest(
          userPrompt: 'Add config file',
          pinnedFilePaths: [],
          projectFiles: const {
            'pages/home.yaml': 'original content',
          },
        ),
      );

      final mod = result.modifications.single;
      expect(mod.filePath, 'config/app.yaml');
      expect(mod.isNewFile, isTrue);
      expect(mod.originalContent, isEmpty);
    });
  });
}
