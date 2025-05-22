import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Manager for storing and retrieving application preferences
class PreferencesManager {
  static const String _apiKeyKey = 'api_key';
  static const String _openAIApiKeyKey = 'openai_api_key';
  static const String _recentProjectsKey = 'recent_projects';
  static const int _maxRecentProjects = 10;

  /// Saves the API key to persistent storage
  static Future<bool> saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(_apiKeyKey, apiKey);
  }

  /// Retrieves the stored API key
  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }

  /// Saves the OpenAI API key to persistent storage
  static Future<bool> saveOpenAIKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(_openAIApiKeyKey, apiKey);
  }

  /// Retrieves the stored OpenAI API key
  static Future<String?> getOpenAIKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_openAIApiKeyKey);
  }

  /// Project entry for recent projects list
  static Map<String, dynamic> createProjectEntry(
      String projectId, String projectName) {
    return {
      'id': projectId,
      'name': projectName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Adds a project to the recent projects list
  static Future<bool> addRecentProject(
      String projectId, String projectName) async {
    final prefs = await SharedPreferences.getInstance();

    // Get current projects list
    final List<Map<String, dynamic>> recentProjects = await getRecentProjects();

    // Check if project already exists
    final existingIndex =
        recentProjects.indexWhere((p) => p['id'] == projectId);
    if (existingIndex >= 0) {
      // Remove existing entry to re-add at top with updated timestamp
      recentProjects.removeAt(existingIndex);
    }

    // Add the new project at the beginning
    recentProjects.insert(0, createProjectEntry(projectId, projectName));

    // Limit to max number of recent projects
    while (recentProjects.length > _maxRecentProjects) {
      recentProjects.removeLast();
    }

    // Save to preferences
    final jsonString = jsonEncode(recentProjects);
    return prefs.setString(_recentProjectsKey, jsonString);
  }

  /// Retrieves the list of recent projects
  static Future<List<Map<String, dynamic>>> getRecentProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_recentProjectsKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error decoding recent projects: $e');
      return [];
    }
  }

  /// Removes a project from the recent projects list
  static Future<bool> removeRecentProject(String projectId) async {
    final prefs = await SharedPreferences.getInstance();

    final List<Map<String, dynamic>> recentProjects = await getRecentProjects();
    recentProjects.removeWhere((p) => p['id'] == projectId);

    final jsonString = jsonEncode(recentProjects);
    return prefs.setString(_recentProjectsKey, jsonString);
  }

  /// Clears all recent projects
  static Future<bool> clearRecentProjects() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.remove(_recentProjectsKey);
  }
}
