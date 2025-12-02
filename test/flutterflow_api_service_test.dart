import 'package:flutter_test/flutter_test.dart';
import 'package:yaml_generator_app/services/flutterflow_api_service.dart';

void main() {
  group('FlutterFlowApiService', () {
    test('getFileKey should remove .yaml extension', () {
      expect(FlutterFlowApiService.getFileKey('ad-mob.yaml'), equals('ad-mob'));
      expect(
          FlutterFlowApiService.getFileKey('project.yaml'), equals('project'));
      expect(FlutterFlowApiService.getFileKey('test-file.yml'),
          equals('test-file'));
    });

    test('getFileKey should handle files without extension', () {
      expect(FlutterFlowApiService.getFileKey('ad-mob'), equals('ad-mob'));
      expect(FlutterFlowApiService.getFileKey('project'), equals('project'));
    });

    test('convertFileNamesToKeys should convert map correctly', () {
      final input = {
        'ad-mob.yaml': 'content1',
        'project.yaml': 'content2',
        'test.yml': 'content3',
        'no-extension': 'content4',
      };

      final expected = {
        'ad-mob': 'content1',
        'project': 'content2',
        'test': 'content3',
        'no-extension': 'content4',
      };

      final result = FlutterFlowApiService.convertFileNamesToKeys(input);
      expect(result, equals(expected));
    });

    test('convertFileNamesToKeys should handle empty map', () {
      final result = FlutterFlowApiService.convertFileNamesToKeys({});
      expect(result, equals({}));
    });

    test('getFileKey should strip archive prefixes and nested paths', () {
      expect(
        FlutterFlowApiService.getFileKey('archive_page/id-123.yaml'),
        equals('page/id-123'),
      );
      expect(
        FlutterFlowApiService
            .getFileKey('archive_page/id-123/page-widget-tree-outline.yaml'),
        equals('page/id-123/page-widget-tree-outline'),
      );
    });

    test(
        'buildFileKeyCandidates should prefer yaml-derived keys and include archive variants',
        () {
      const content = '''
page:
  key: id-Scaffold_hur6kpbk
  name: Home
''';

      final candidates = FlutterFlowApiService.buildFileKeyCandidates(
        filePath: 'archive_page/id-Scaffold_hur6kpbk.yaml',
        yamlContent: content,
      );

      expect(candidates.first, equals('page/id-Scaffold_hur6kpbk'));
      expect(candidates[1], equals('page/id-Scaffold_hur6kpbk.yaml'));
      expect(candidates, contains('archive_page/id-Scaffold_hur6kpbk'));
      expect(
          candidates, contains('archive_page/id-Scaffold_hur6kpbk.yaml'));
    });
  });
}
