import 'dart:convert';
import 'package:http/http.dart' as http;

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
    Map<String, dynamic>? responseFormat,
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
    
    if (responseFormat != null) {
      body['response_format'] = responseFormat;
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
          'Failed to get response: ${response.statusCode} ${utf8.decode(response.bodyBytes)}');
    }
  }
}
