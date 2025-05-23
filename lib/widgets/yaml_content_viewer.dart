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

  const YamlContentViewer({
    Key? key,
    this.content,
    this.characterCount,
    this.isReadOnly = true,
    this.onContentChanged,
    this.onFileUpdated,
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

      print('Validating file: ${widget.filePath} -> key: "$fileKey"');

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
      print('Validation response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _isValid = true;
            _validationError = null;
          });
        } else {
          final errorMsg = data['error'] ?? 'Invalid YAML format';
          setState(() {
            _isValid = false;
            _validationError = '❌ Validation Error: $errorMsg';
          });
        }
      } else if (response.statusCode == 400) {
        // Parse detailed validation errors
        try {
          final errorData = json.decode(response.body);
          String detailedError = 'YAML Validation Failed:\n';

          if (errorData['error'] != null) {
            detailedError += '• ${errorData['error']}\n';
          }
          if (errorData['message'] != null) {
            detailedError += '• ${errorData['message']}\n';
          }

          setState(() {
            _isValid = false;
            _validationError = detailedError.trim();
          });
        } catch (e) {
          setState(() {
            _isValid = false;
            _validationError =
                '❌ Validation failed (HTTP ${response.statusCode}): ${response.body}';
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
      print('Validation error: $e');
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
        print('API token not found for update');
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
      print('Error updating file via API: $e');

      // Parse the error message for better user communication
      String userFriendlyError;
      String errorString = e.toString();

      if (errorString.contains('400')) {
        // Parse specific 400 errors
        if (errorString.contains('Expected int or stringified int')) {
          userFriendlyError =
              '🔢 YAML Error: Expected a number or quoted number. Check your YAML syntax for numeric values.';
        } else if (errorString.contains('Invalid file key')) {
          userFriendlyError =
              '🗂️ File Error: Invalid file path for FlutterFlow. This file may not be supported.';
        } else if (errorString.contains('(')) {
          // Try to extract line/column info: "(2:3)"
          final lineColMatch =
              RegExp(r'\((\d+):(\d+)\)').firstMatch(errorString);
          if (lineColMatch != null) {
            final line = lineColMatch.group(1);
            final col = lineColMatch.group(2);
            userFriendlyError =
                '📍 YAML Syntax Error at Line $line, Column $col:\n';

            if (errorString.contains('Expected int')) {
              userFriendlyError += '• Expected a number or quoted number\n';
            } else if (errorString.contains('mapping')) {
              userFriendlyError +=
                  '• YAML structure error - check indentation\n';
            } else {
              userFriendlyError += '• Invalid YAML syntax\n';
            }
            userFriendlyError +=
                '💡 Tip: Check quotes, indentation, and data types';
          } else {
            userFriendlyError = '❌ YAML Update Error: $errorString';
          }
        } else {
          userFriendlyError =
              '❌ Update Failed: Invalid YAML format. Check your syntax.';
        }
      } else if (errorString.contains('401')) {
        userFriendlyError =
            '🔑 Authentication Error: Invalid API token. Please check your credentials.';
      } else if (errorString.contains('403')) {
        userFriendlyError =
            '🚫 Permission Error: Your API token doesn\'t have write access to this project.';
      } else if (errorString.contains('404')) {
        userFriendlyError =
            '🔍 Project Not Found: Check your project ID or API token.';
      } else if (errorString.contains('Network error') ||
          errorString.contains('Connection')) {
        userFriendlyError =
            '🌐 Network Error: Unable to reach FlutterFlow servers. Check your internet connection.';
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
    if (!_hasUnsavedChanges) return;

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
    setState(() {
      _textController.text = widget.content ?? '';
      _hasUnsavedChanges = false;
      _isEditing = false;
      _validationError = null;
      _isValid = true;
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
      child: Row(
        children: [
          // File info section
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.description,
                  size: 18,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.filePath.isNotEmpty ? widget.filePath : 'YAML Content',
                  style: AppTheme.headingSmall.copyWith(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: 8),
                if (widget.characterCount != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration:
                        AppTheme.statusBadgeDecoration(AppTheme.textMuted),
                    child: Text(
                      '${widget.characterCount} chars',
                      style: AppTheme.captionLarge.copyWith(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Status and action buttons
          Row(
            children: [
              // Validation status indicator
              if (_isValidating)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration:
                      AppTheme.statusBadgeDecoration(AppTheme.infoColor),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppTheme.infoColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Validating',
                        style: AppTheme.captionLarge.copyWith(
                          color: AppTheme.infoColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_isUpdating)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration:
                      AppTheme.statusBadgeDecoration(AppTheme.updatedColor),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.updatedColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Updating',
                        style: AppTheme.captionLarge.copyWith(
                          color: AppTheme.updatedColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_validationError != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration:
                      AppTheme.statusBadgeDecoration(AppTheme.errorColor),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: AppTheme.errorColor,
                        size: 12,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Invalid',
                        style: AppTheme.captionLarge.copyWith(
                          color: AppTheme.errorColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_isValid &&
                  widget.content != null &&
                  widget.content!.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration:
                      AppTheme.statusBadgeDecoration(AppTheme.validColor),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: AppTheme.validColor,
                        size: 12,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Valid',
                        style: AppTheme.captionLarge.copyWith(
                          color: AppTheme.validColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // Action buttons
              if (!widget.isReadOnly && widget.content != null) ...[
                const SizedBox(width: 12),

                // Copy button
                _buildActionButton(
                  icon: _isCopied ? Icons.check : Icons.copy,
                  label: _isCopied ? 'Copied' : 'Copy',
                  onPressed: _copyToClipboard,
                  color:
                      _isCopied ? AppTheme.validColor : AppTheme.textSecondary,
                ),

                const SizedBox(width: 8),

                // Save/Discard buttons when editing with unsaved changes
                if (_isEditing && _hasUnsavedChanges) ...[
                  _buildActionButton(
                    icon: Icons.close,
                    label: 'Discard',
                    onPressed: _discardChanges,
                    color: AppTheme.errorColor,
                  ),
                  const SizedBox(width: 8),
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
                  const SizedBox(width: 8),
                ],

                // Edit toggle button (or Cancel if editing without changes)
                _buildActionButton(
                  icon: _isEditing
                      ? (_hasUnsavedChanges ? Icons.edit : Icons.visibility)
                      : Icons.edit,
                  label: _isEditing
                      ? (_hasUnsavedChanges ? 'Editing' : 'View')
                      : 'Edit',
                  onPressed: _isEditing && !_hasUnsavedChanges
                      ? _toggleEdit
                      : _isEditing && _hasUnsavedChanges
                          ? null // Disable when editing with unsaved changes
                          : _toggleEdit,
                  color: _isEditing
                      ? (_hasUnsavedChanges
                          ? AppTheme.warningColor
                          : AppTheme.primaryColor)
                      : AppTheme.textSecondary,
                ),
              ],
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
}
