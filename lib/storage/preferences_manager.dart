import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manager for storing and retrieving application preferences
class PreferencesManager {
  static const String _apiKeyKey = 'api_key';
  static const String _openAIApiKeyKey = 'openai_api_key';
  static const String _recentProjectsKey = 'recent_projects';
  static const String _yamlSourceUrlKey = 'yaml_source_url';
  static const int _maxRecentProjects = 10;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// Saves the API key to persistent storage
  static Future<bool> saveApiKey(String apiKey) async {
    try {
      await _secureStorage.write(key: _apiKeyKey, value: apiKey);
      return true;
    } catch (e) {
      debugPrint('Failed to save API key securely: $e');
      return false;
    }
  }

  /// Retrieves the stored API key
  static Future<String?> getApiKey() async {
    try {
      final secureValue = await _secureStorage.read(key: _apiKeyKey);
      if (secureValue != null && secureValue.isNotEmpty) {
        return secureValue;
      }

      // Migrate any legacy value stored in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final legacyValue = prefs.getString(_apiKeyKey);
      if (legacyValue != null && legacyValue.isNotEmpty) {
        await _secureStorage.write(key: _apiKeyKey, value: legacyValue);
        await prefs.remove(_apiKeyKey);
        return legacyValue;
      }
    } catch (e) {
      debugPrint('Failed to read API key securely: $e');
    }
    return null;
  }

  /// Saves the OpenAI API key to persistent storage
  static Future<bool> saveOpenAIKey(String apiKey) async {
    try {
      await _secureStorage.write(key: _openAIApiKeyKey, value: apiKey);
      return true;
    } catch (e) {
      debugPrint('Failed to save OpenAI key securely: $e');
      return false;
    }
  }

  /// Retrieves the stored OpenAI API key
  static Future<String?> getOpenAIKey() async {
    try {
      final secureValue = await _secureStorage.read(key: _openAIApiKeyKey);
      if (secureValue != null && secureValue.isNotEmpty) {
        return secureValue;
      }

      // Migrate any legacy value stored in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final legacyValue = prefs.getString(_openAIApiKeyKey);
      if (legacyValue != null && legacyValue.isNotEmpty) {
        await _secureStorage.write(
          key: _openAIApiKeyKey,
          value: legacyValue,
        );
        await prefs.remove(_openAIApiKeyKey);
        return legacyValue;
      }
    } catch (e) {
      debugPrint('Failed to read OpenAI key securely: $e');
    }
    return null;
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

  /// Saves the YAML source URL to persistent storage
  static Future<bool> saveYamlSourceUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(_yamlSourceUrlKey, url);
  }

  /// Retrieves the stored YAML source URL
  static Future<String?> getYamlSourceUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_yamlSourceUrlKey);
  }

  /// Clears only the FlutterFlow API key.
  static Future<void> clearApiKey() async {
    await _secureStorage.delete(key: _apiKeyKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyKey);
  }

  /// Clears only the OpenAI API key.
  static Future<void> clearOpenAIKey() async {
    await _secureStorage.delete(key: _openAIApiKeyKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_openAIApiKeyKey);
  }

  /// Clears all persisted credentials (FlutterFlow + OpenAI) from secure and legacy storage.
  static Future<void> clearCredentials() async {
    try {
      await _secureStorage.delete(key: _apiKeyKey);
      await _secureStorage.delete(key: _openAIApiKeyKey);
    } catch (e) {
      debugPrint('Failed to clear secure credentials: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyKey);
    await prefs.remove(_openAIApiKeyKey);
  }
}
