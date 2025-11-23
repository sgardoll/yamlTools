import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../storage/preferences_manager.dart';
import '../services/flutterflow_api_service.dart';

class YamlContentViewer extends StatefulWidget {
  final String? content;
  final int? characterCount;
  final bool isReadOnly;
  final Function(String)? onContentChanged;
  final Function(String)? onFileUpdated;
  final String filePath;
  final String projectId;
  // When true, indicates the parent has staged local edits (e.g., from AI)
  // and wants the editor to surface Save/Cancel immediately even if the user
  // hasn't typed yet.
  final bool hasPendingLocalEdits;

  // When true and this file is opened/selected, the editor starts in edit mode
  // so the Save/Cancel controls are visible.
  final bool startInEditMode;

  // Called when the user presses Discard while only pending local edits exist
  // (i.e., before any additional manual edits). Parent can revert the file
  // to its original content or remove the new file entirely.
  final VoidCallback? onDiscardPendingEdits;

  const YamlContentViewer({
    Key? key,
    this.content,
    this.characterCount,
    this.isReadOnly = true,
    this.onContentChanged,
    this.onFileUpdated,
    this.filePath = '',
    this.projectId = '',
    this.hasPendingLocalEdits = false,
    this.startInEditMode = false,
    this.onDiscardPendingEdits,
  }) : super(key: key);

  @override
  _YamlContentViewerState createState() => _YamlContentViewerState();
}

class _YamlContentViewerState extends State<YamlContentViewer> {
  late TextEditingController _textController;
  bool _isEditing = false;
  bool _isCopied = false;
  bool _isValidating = false;
  bool _isUpdating = false;
  bool _hasUnsavedChanges = false; // Track unsaved changes
  String? _validationError;
  bool _isValid = true;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.content ?? '');
    // Listen for changes to track unsaved changes
    _textController.addListener(_onTextChanged);
    // If we have pending local edits, surface edit mode immediately
    if (widget.startInEditMode) {
      _isEditing = true;
    }
  }

  @override
  void didUpdateWidget(YamlContentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _textController.text = widget.content ?? '';
      // Reset validation state and unsaved changes when content changes externally
      setState(() {
        _validationError = null;
        _isValid = true;
        _hasUnsavedChanges = false;
      });
    }

    // When switching files, respect the desired initial mode
    if (oldWidget.filePath != widget.filePath) {
      setState(() {
        _isEditing = widget.startInEditMode;
      });
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Check if content has changed from the original
    final hasChanges = _textController.text != (widget.content ?? '');
    if (hasChanges != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
        // Clear validation error when user starts typing
        if (hasChanges && _validationError != null) {
          _validationError = null;
          _isValid = true;
        }
      });
    }
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
          _validationError =
              '🔑 API token missing. Please set your FlutterFlow API token in settings.';
        });
        return;
      }

      // Extract file key from the file path using the same method as update
      final fileKey = FlutterFlowApiService.getFileKey(widget.filePath);

      debugPrint('Validating file: ${widget.filePath} -> key: "$fileKey"');

      // Create request payload
      final requestBody = json.encode({
        'projectId': widget.projectId,
        'fileKey': fileKey,
        'fileContent': content,
      });

      // For web, we're using a CORS proxy initialized in index.html
      final apiUrl =
          'https://api.flutterflow.io/v2-staging/validateProjectYaml';
      debugPrint('Sending validation request to: $apiUrl');

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

      debugPrint('Validation response status: ${response.statusCode}');
      debugPrint('Validation response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _isValid = true;
            _validationError = null;
          });
        } else {
          final errorMsg = (data['error'] ?? data['message'] ?? 'Invalid YAML format').toString();
          setState(() {
            _isValid = false;
            _validationError = _formatValidationMessage(errorMsg);
          });
        }
      } else if (response.statusCode == 400) {
        // Parse detailed validation errors
        try {
          final errorData = json.decode(response.body);
          final combined = [
            if (errorData['error'] != null) errorData['error'].toString(),
            if (errorData['message'] != null) errorData['message'].toString(),
          ].where((e) => e.trim().isNotEmpty).join('\n');
          setState(() {
            _isValid = false;
            _validationError = _formatValidationMessage(
              combined.isEmpty ? response.body : combined,
            );
          });
        } catch (e) {
          setState(() {
            _isValid = false;
            _validationError = _formatValidationMessage(
                'Validation failed (HTTP ${response.statusCode}): ${response.body}');
          });
        }
      } else if (response.statusCode == 401) {
        setState(() {
          _isValid = false;
          _validationError =
              '🔑 Authentication failed. Please check your API token.';
        });
      } else if (response.statusCode == 403) {
        setState(() {
          _isValid = false;
          _validationError =
              '🚫 Access denied. Check your API token permissions.';
        });
      } else {
        setState(() {
          _isValid = false;
          _validationError =
              '🌐 Server error (${response.statusCode}). Try again later.';
        });
      }
    } catch (e) {
      debugPrint('Validation error: $e');
      setState(() {
        _isValid = false;
        _validationError =
            '🌐 Network error: Unable to connect to FlutterFlow API. Check your internet connection.';
      });
    } finally {
      setState(() {
        _isValidating = false;
      });
    }
  }

  // Update file via FlutterFlow API after successful validation
  Future<void> _updateFileViaApi(String content) async {
    // Skip update if project ID is empty
    if (widget.projectId.isEmpty) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      // Get the API token from storage
      final apiToken = await PreferencesManager.getApiKey();
      if (apiToken == null || apiToken.isEmpty) {
        debugPrint('API token not found for update');
        setState(() {
          _validationError =
              '🔑 API token missing for update. Please set your FlutterFlow API token.';
          _isValid = false;
        });
        return;
      }

      // Convert the file path to the format expected by the API
      final fileKey = FlutterFlowApiService.getFileKey(widget.filePath);
      final fileKeyToContent = {fileKey: content};

      print('Updating file via API: ${widget.filePath} -> key: "$fileKey"');

      // Call the FlutterFlow API
      await FlutterFlowApiService.updateProjectYaml(
        projectId: widget.projectId,
        apiToken: apiToken,
        fileKeyToContent: fileKeyToContent,
      );

      print('Successfully updated file via API: ${widget.filePath}');

      // Clear any previous errors on successful update
      setState(() {
        _validationError = null;
        _isValid = true;
      });

      // Notify that the file was updated via API
      if (widget.onFileUpdated != null) {
        widget.onFileUpdated!(widget.filePath);
      }
    } catch (e) {
      debugPrint('Error updating file via API: $e');

      // Parse the error message for better user communication
      String userFriendlyError;
      final errorString = e.toString();

      if (e is FlutterFlowApiException) {
        final status = e.statusCode;
        if (e.isNetworkError) {
          userFriendlyError = '🌐 Network Error: Unable to reach FlutterFlow servers. Check your internet connection.';
        } else if (status != null && status >= 400 && status < 500) {
          final bodyText = (e.body ?? e.message);
          userFriendlyError = _formatValidationMessage(bodyText);
        } else if (status == 401) {
          userFriendlyError = '🔑 Authentication Error: Invalid API token. Please check your credentials.';
        } else if (status == 403) {
          userFriendlyError = '🚫 Permission Error: Your API token doesn\'t have write access to this project.';
        } else if (status == 404) {
          userFriendlyError = '🔍 Project Not Found: Check your project ID or API token.';
        } else {
          userFriendlyError = '⚠️ Update Failed (${e.statusCode ?? 'unknown'}): ${e.message}';
        }
      } else if (errorString.contains('400')) {
        // Parse specific 400 errors
        if (errorString.contains('Expected int or stringified int')) {
          userFriendlyError = '🔢 YAML Error: Expected a number or quoted number. Check your YAML syntax for numeric values.';
        } else if (errorString.contains('Invalid file key')) {
          userFriendlyError = '🗂️ File Error: Invalid file path for FlutterFlow. This file may not be supported.';
        } else {
          userFriendlyError = _formatValidationMessage(errorString);
        }
      } else if (errorString.contains('401')) {
        userFriendlyError = '🔑 Authentication Error: Invalid API token. Please check your credentials.';
      } else if (errorString.contains('403')) {
        userFriendlyError = '🚫 Permission Error: Your API token doesn\'t have write access to this project.';
      } else if (errorString.contains('404')) {
        userFriendlyError = '🔍 Project Not Found: Check your project ID or API token.';
      } else if (errorString.contains('Network error') || errorString.contains('Connection')) {
        userFriendlyError = '🌐 Network Error: Unable to reach FlutterFlow servers. Check your internet connection.';
      } else {
        userFriendlyError = '⚠️ Update Failed: $errorString';
      }

      setState(() {
        _validationError = userFriendlyError;
        _isValid = false;
      });
    } finally {
      setState(() {
        _isUpdating = false;
      });
    }
  }

  // Save changes and exit edit mode
  Future<void> _saveChanges() async {
    // Allow saving when either the user has typed changes OR there are
    // pending local edits staged by the parent (e.g., AI applied changes).
    if (!_hasUnsavedChanges && !widget.hasPendingLocalEdits) return;

    final currentContent = _textController.text;

    // Validate first if we have a project ID
    if (widget.projectId.isNotEmpty) {
      await _validateYaml(currentContent);
      // Don't save if validation failed
      if (!_isValid) return;
    }

    // Call the content changed callback to save locally
    if (widget.onContentChanged != null) {
      widget.onContentChanged!(currentContent);
    }

    // If validation passed and we have project credentials, update via API
    if (_isValid && widget.projectId.isNotEmpty) {
      await _updateFileViaApi(currentContent);
    }

    // Mark as saved and exit edit mode
    setState(() {
      _hasUnsavedChanges = false;
      _isEditing = false;
    });
  }

    // Discard changes and exit edit mode
  void _discardChanges() {
    // If we only have pending local edits (no manual typing), let parent
    // revert the local edits to the original version.
    if (widget.hasPendingLocalEdits && !_hasUnsavedChanges) {
      widget.onDiscardPendingEdits?.call();
      setState(() {
        _hasUnsavedChanges = false;
        _isEditing = false;
      });
      return;
    }

    // Otherwise, revert to the last provided content from parent
    setState(() {
      _textController.text = widget.content ?? '';
      _hasUnsavedChanges = false;
      _isEditing = false;
    });
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
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.1),
                border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: AppTheme.errorColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Error Details',
                          style: TextStyle(
                            color: AppTheme.errorColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    child: Text(
                      _validationError!,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
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
        border: Border(
          bottom: BorderSide(color: AppTheme.dividerColor, width: 1),
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Column(
        children: [
          // First row - File info and main actions
          Row(
            children: [
              // File info section
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Icon(
                      Icons.description,
                      size: 18,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.filePath.isNotEmpty
                            ? widget.filePath.split('/').last
                            : 'YAML Content',
                        style: AppTheme.headingSmall.copyWith(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Character count (flexible)
              if (widget.characterCount != null)
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(4),
                      border:
                          Border.all(color: AppTheme.dividerColor, width: 1),
                    ),
                    child: Text(
                      '${widget.characterCount} chars',
                      style: AppTheme.bodySmall.copyWith(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Second row - Action buttons (wrapped for overflow)
          if (!widget.isReadOnly && widget.content != null)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                // Copy button
                _buildActionButton(
                  icon: _isCopied ? Icons.check : Icons.copy,
                  label: _isCopied ? 'Copied' : 'Copy',
                  onPressed: _copyToClipboard,
                  color:
                      _isCopied ? AppTheme.validColor : AppTheme.textSecondary,
                ),

                // Save/Discard buttons when editing with unsaved changes OR when
                // the parent indicates there are pending local edits to confirm
                if (_isEditing && (_hasUnsavedChanges || widget.hasPendingLocalEdits)) ...[
                  _buildActionButton(
                    icon: Icons.close,
                    label: 'Discard',
                    onPressed: _discardChanges,
                    color: AppTheme.errorColor,
                  ),
                  _buildActionButton(
                    icon: _isValidating || _isUpdating
                        ? Icons.hourglass_empty
                        : Icons.save,
                    label: _isValidating
                        ? 'Validating...'
                        : _isUpdating
                            ? 'Saving...'
                            : 'Save',
                    onPressed: (_isValidating || _isUpdating)
                        ? null
                        : () => _saveChanges(),
                    color: AppTheme.successColor,
                  ),
                ],

                // Edit toggle button (or Cancel if editing without changes)
                _buildActionButton(
                  icon: _isEditing ? Icons.cancel : Icons.edit,
                  label: _isEditing ? 'Cancel' : 'Edit',
                  onPressed: _isEditing ? _exitEditMode : _enterEditMode,
                  color:
                      _isEditing ? AppTheme.errorColor : AppTheme.primaryColor,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    final isDisabled = onPressed == null;
    final effectiveColor = isDisabled ? color.withOpacity(0.4) : color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: effectiveColor.withOpacity(0.3), width: 1),
            color: isDisabled ? AppTheme.surfaceColor.withOpacity(0.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: effectiveColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTheme.captionLarge.copyWith(
                  color: effectiveColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
            style: AppTheme.monospace.copyWith(
              color: AppTheme.textPrimary, // Use theme's white text
            ),
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
        style: AppTheme.monospace.copyWith(
          color: AppTheme.textPrimary, // Use theme's white text
        ),
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          filled: true,
          fillColor: AppTheme.surfaceColor, // Dark surface color
          border: OutlineInputBorder(
            borderSide: BorderSide(color: AppTheme.dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppTheme.dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          contentPadding: const EdgeInsets.all(12),
          hintText: 'Enter YAML content...',
          hintStyle: TextStyle(color: AppTheme.textMuted),
        ),
      ),
    );
  }

  void _copyToClipboard() {
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
  }

  void _toggleEdit() {
    setState(() {
      _isEditing = !_isEditing;
    });
  }

  void _exitEditMode() {
    setState(() {
      _isEditing = false;
    });
  }

  void _enterEditMode() {
    setState(() {
      _isEditing = true;
    });
  }

  // Format server validation errors like:
  // "theme/color-scheme: (1:1): Unknown field name 'colors'"
  // into a friendly, actionable message.
  String _formatValidationMessage(String raw) {
    final text = raw.trim();
    final pattern = RegExp(r'^(.*?):\s*\((\d+):(\d+)\)\s*:\s*(.*)$');
    final match = pattern.firstMatch(text);
    if (match != null) {
      final path = match.group(1)!.trim();
      final line = match.group(2);
      final col = match.group(3);
      final detail = match.group(4)!.trim();
      return [
        '❌ YAML Validation Failed',
        '• Location: $path (line $line, col $col)',
        '• Details: $detail',
        '💡 Tip: Open the section "$path" and fix the highlighted key/value, then press Save again.',
      ].join('\n');
    }

    // Fallback: try to extract only line/col
    final lc = RegExp(r'\((\d+):(\d+)\)').firstMatch(text);
    if (lc != null) {
      final line = lc.group(1);
      final col = lc.group(2);
      final after = text.contains('):') ? text.split('):').last.trim() : '';
      return [
        '❌ YAML Validation Failed',
        '• Location: line $line, col $col',
        if (after.isNotEmpty) '• Details: $after',
        '💡 Tip: Check indentation, quotes, and key names at this position.',
      ].join('\n');
    }

    // Default: show raw with a clean prefix
    return '❌ Update Failed: $text';
  }
}
