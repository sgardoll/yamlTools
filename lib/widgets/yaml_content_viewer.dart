import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../storage/preferences_manager.dart';

class YamlContentViewer extends StatefulWidget {
  final String? content;
  final int? characterCount;
  final bool isReadOnly;
  final Function(String)? onContentChanged;
  final String filePath;
  final String projectId;

  const YamlContentViewer({
    Key? key,
    this.content,
    this.characterCount,
    this.isReadOnly = true,
    this.onContentChanged,
    this.filePath = '',
    this.projectId = '',
  }) : super(key: key);

  @override
  _YamlContentViewerState createState() => _YamlContentViewerState();
}

class _YamlContentViewerState extends State<YamlContentViewer> {
  late TextEditingController _textController;
  bool _isEditing = false;
  bool _isCopied = false;
  bool _isValidating = false;
  String? _validationError;
  bool _isValid = true;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.content ?? '');
  }

  @override
  void didUpdateWidget(YamlContentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _textController.text = widget.content ?? '';
      // Reset validation state when content changes
      setState(() {
        _validationError = null;
        _isValid = true;
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // Validate YAML content with the API
  Future<void> _validateYaml(String content) async {
    // Skip validation if project ID is empty
    if (widget.projectId.isEmpty) {
      return;
    }

    setState(() {
      _isValidating = true;
      _validationError = null;
    });

    try {
      // Get the API token from storage
      final apiToken = await PreferencesManager.getApiKey();
      if (apiToken == null || apiToken.isEmpty) {
        setState(() {
          _isValid = false;
          _validationError = 'API token not found. Please set your API token.';
        });
        return;
      }

      // Extract file key from the file path
      String fileKey = widget.filePath;
      if (fileKey.contains('/')) {
        fileKey = fileKey.split('/').last;
      }
      if (fileKey.endsWith('.yaml')) {
        fileKey = fileKey.substring(0, fileKey.length - 5);
      }
      if (fileKey.startsWith('archive_')) {
        fileKey = fileKey.substring(8);
      }

      // Create request payload
      final requestBody = json.encode({
        'projectId': widget.projectId,
        'fileKey': fileKey,
        'fileContent': content,
      });

      // For web, we're using a CORS proxy initialized in index.html
      final apiUrl =
          'https://api.flutterflow.io/v2-staging/validateProjectYaml';
      print('Sending validation request to: $apiUrl');

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // Add cache control to prevent caching issues
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
        body: requestBody,
      );

      print('Validation response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _isValid = true;
            _validationError = null;
          });
        } else {
          setState(() {
            _isValid = false;
            _validationError = data['error'] ?? 'Invalid YAML format';
          });
        }
      } else {
        print('Error response body: ${response.body}');
        setState(() {
          _isValid = false;
          _validationError =
              'Validation failed: Server error ${response.statusCode}';
        });
      }
    } catch (e) {
      print('Validation error: $e');
      setState(() {
        _isValid = false;
        _validationError = 'Validation error: $e';
      });
    } finally {
      setState(() {
        _isValidating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _validationError != null
              ? AppTheme.errorColor
              : (_isValid
                  ? AppTheme.successColor.withOpacity(0.3)
                  : AppTheme.dividerColor),
          width: _validationError != null ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with controls
          _buildHeader(),

          // Validation error display
          if (_validationError != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.errorColor.withOpacity(0.1),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: AppTheme.errorColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _validationError!,
                      style:
                          TextStyle(color: AppTheme.errorColor, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Content area
          Expanded(
            child: _isEditing ? _buildEditor() : _buildViewer(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          // Character count indicator
          if (widget.characterCount != null)
            Text(
              '${widget.characterCount} characters',
              style: AppTheme.bodySmall,
            ),

          const Spacer(),

          // Validation status indicator
          if (_isValidating)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Validating',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else if (_validationError != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      color: AppTheme.errorColor, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'Invalid',
                    style: TextStyle(
                      color: AppTheme.errorColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else if (_isValid &&
              widget.content != null &&
              widget.content!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      color: AppTheme.successColor, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'Valid',
                    style: TextStyle(
                      color: AppTheme.successColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(width: 8),

          // Edit button (if not in read-only mode)
          if (!widget.isReadOnly && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit, color: AppTheme.primaryColor),
              tooltip: 'Edit',
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),

          // Save button (when editing)
          if (_isEditing)
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final newContent = _textController.text;

                    // First validate the YAML
                    await _validateYaml(newContent);

                    // Only save if valid or if we have no project ID to validate against
                    if (_isValid || widget.projectId.isEmpty) {
                      if (widget.onContentChanged != null) {
                        widget.onContentChanged!(newContent);
                      }
                      setState(() {
                        _isEditing = false;
                      });
                    }
                  },
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  child: const Text('Cancel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                  ),
                  onPressed: () {
                    // Reset to original content
                    _textController.text = widget.content ?? '';
                    setState(() {
                      _isEditing = false;
                    });
                  },
                ),
              ],
            ),

          // Copy button
          if (!_isEditing)
            IconButton(
              icon: Icon(
                _isCopied ? Icons.check : Icons.copy,
                color:
                    _isCopied ? AppTheme.successColor : AppTheme.primaryColor,
              ),
              tooltip: 'Copy to clipboard',
              onPressed: () {
                final content = widget.content ?? '';
                Clipboard.setData(ClipboardData(text: content));
                setState(() {
                  _isCopied = true;
                });
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() {
                      _isCopied = false;
                    });
                  }
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildViewer() {
    final content = widget.content ?? '';

    if (content.isEmpty) {
      return const Center(
        child: Text(
          'No content to display',
          style: AppTheme.bodyMedium,
        ),
      );
    }

    return GestureDetector(
      // Make content editable when clicked if not in read-only mode
      onTap: widget.isReadOnly
          ? null
          : () {
              setState(() {
                _isEditing = true;
              });
            },
      child: Container(
        padding: const EdgeInsets.all(16),
        color: AppTheme.backgroundColor,
        child: SingleChildScrollView(
          child: Text(
            content,
            style: AppTheme.monospace,
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.backgroundColor,
      child: TextField(
        controller: _textController,
        style: AppTheme.monospace,
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          filled: true,
          fillColor: AppTheme.backgroundColor.withOpacity(0.7),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: AppTheme.dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppTheme.dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppTheme.primaryColor),
            borderRadius: BorderRadius.circular(4),
          ),
          contentPadding: const EdgeInsets.all(12),
          hintText: 'Enter YAML content...',
          hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
        ),
      ),
    );
  }
}
