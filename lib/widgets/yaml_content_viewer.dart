import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../storage/preferences_manager.dart';
import '../services/flutterflow_api_service.dart';
import '../services/yaml_file_utils.dart';

class YamlContentViewer extends StatefulWidget {
  final String? content;
  final int? characterCount;
  final bool isReadOnly;
  final Function(String)? onContentChanged;
  final Function(String)? onFileUpdated;
  final void Function(String oldPath, String newPath)? onFileRenamed;
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
    this.onFileRenamed,
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
  late TextEditingController _findController;
  late TextEditingController _replaceController;
  final FocusNode _editorFocusNode = FocusNode();
  bool _isEditing = false;
  bool _isCopied = false;
  bool _isValidating = false;
  bool _isUpdating = false;
  bool _hasUnsavedChanges = false; // Track unsaved changes
  String? _validationError;
  bool _isValid = true;
  String? _lastValidatedFileKey;
  // Controllers for scrollable error/details and viewer to avoid overflow
  final ScrollController _errorVController = ScrollController();
  final ScrollController _errorHController = ScrollController();
  final ScrollController _viewerVController = ScrollController();
  final ScrollController _viewerHController = ScrollController();

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.content ?? '');
    _findController = TextEditingController();
    _replaceController = TextEditingController();
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
        _lastValidatedFileKey = null;
      });
    }

    // When switching files, respect the desired initial mode
    if (oldWidget.filePath != widget.filePath) {
      setState(() {
        _isEditing = widget.startInEditMode;
        _lastValidatedFileKey = null;
        _findController.clear();
        _replaceController.clear();
      });
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _editorFocusNode.dispose();
    _errorVController.dispose();
    _errorHController.dispose();
    _viewerVController.dispose();
    _viewerHController.dispose();
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

      // Auto-fix YAML key based on file path before sending.
      final fixed =
          YamlFileUtils.ensureKeyMatchesFile(content, widget.filePath);
      if (fixed.changed) {
        content = fixed.content;
        _textController.text = content;
        debugPrint(
            'Auto-corrected YAML key from "${fixed.previousKey}" to "${fixed.expectedKey}" for ${widget.filePath}');
      }

      // Empirically resolve the file key by probing validation endpoint candidates
      final fileKey = await FlutterFlowApiService.resolveFileKey(
        projectId: widget.projectId,
        apiToken: apiToken,
        filePath: widget.filePath,
        yamlContent: content,
      );

      if (fileKey == null) {
        setState(() {
          _isValid = false;
          _validationError =
              '❌ File key resolution failed\n'
              '• File: ${widget.filePath}\n'
              '• This file is not recognized by FlutterFlow.\n'
              '💡 Tip: This file may not be directly editable via the API.\n'
              '  Try editing the parent file instead (e.g., page-widget-tree-outline.yaml).';
        });
        return;
      }

      debugPrint('Validating file: ${widget.filePath} -> resolved key: "$fileKey"');

      debugPrint('Sending validation request for key "$fileKey" using Zip approach');

      try {
        final result = await FlutterFlowApiService.validateProjectYaml(
          projectId: widget.projectId,
          apiToken: apiToken,
          fileKeyToContent: {fileKey: content},
        );

        if (result['valid'] == true) {
          setState(() {
            _isValid = true;
            _validationError = null;
            _lastValidatedFileKey = fileKey;
          });
        } else {
          final errors = (result['errors'] as List?)?.cast<String>() ?? [];
          final errorMsg = errors.isNotEmpty ? errors.join('\n') : 'Validation failed';

          setState(() {
            _isValid = false;
            _validationError = _formatValidationMessage(
              errorMsg,
              yamlContent: content,
              currentFilePath: widget.filePath,
            );
          });
        }
      } catch (e) {
        if (e is FlutterFlowApiException && e.statusCode != null && e.statusCode! >= 400 && e.statusCode! < 500) {
           final bodyText = (e.body ?? e.message);
           final formatted = _formatValidationMessage(
             bodyText,
             yamlContent: content,
             currentFilePath: widget.filePath,
           );

           setState(() {
             _isValid = false;
             // If we can format it nicely (e.g. line/col error), do so.
             // Otherwise show the raw message from the API.
             if (_isFormattedValidationMessage(bodyText, formatted)) {
               _validationError = formatted;
             } else {
               _validationError = e.message.isNotEmpty ? e.message : 'Validation failed with status ${e.statusCode}';
             }
           });
           return;
        }
        rethrow;
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

    String effectiveFilePath = widget.filePath;
    String? attemptedFileKey;

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

      final inferredPath = YamlFileUtils.inferFilePathFromContent(content);
      if (inferredPath != null && inferredPath != widget.filePath) {
        debugPrint(
            'Detected mismatch between file path and YAML key. Renaming "${widget.filePath}" -> "$inferredPath" before upload.');
        widget.onFileRenamed?.call(widget.filePath, inferredPath);
        effectiveFilePath = inferredPath;
      }

      // Auto-fix YAML key based on file path before upload.
      final fixed =
          YamlFileUtils.ensureKeyMatchesFile(content, effectiveFilePath);
      if (fixed.changed) {
        content = fixed.content;
        _textController.text = content;
        debugPrint(
            'Auto-corrected YAML key from "${fixed.previousKey}" to "${fixed.expectedKey}" for $effectiveFilePath');
      }

      // Empirically resolve the file key by probing validation endpoint candidates
      // If we have a previously validated key, try to use it; otherwise resolve fresh
      String? fileKey = _lastValidatedFileKey;

      if (fileKey == null) {
        fileKey = await FlutterFlowApiService.resolveFileKey(
          projectId: widget.projectId,
          apiToken: apiToken,
          filePath: effectiveFilePath,
          yamlContent: content,
        );
      }

      if (fileKey == null) {
        throw FlutterFlowApiException(
          message:
              'File key resolution failed: This file is not recognized by FlutterFlow.\n'
              'File: $effectiveFilePath\n'
              'This file may not be directly editable via the API. Try editing the parent file instead.',
          endpoint: FlutterFlowApiService.baseUrl,
        );
      }

      attemptedFileKey = fileKey;
      debugPrint('Updating file via API: $effectiveFilePath -> key: "$fileKey"');

      // Call the FlutterFlow API with the resolved file key
      await FlutterFlowApiService.updateProjectYaml(
        projectId: widget.projectId,
        apiToken: apiToken,
        fileKeyToContent: {fileKey: content},
      );

      // Success, record the key
      _lastValidatedFileKey = fileKey;

      print('Successfully updated file via API: $effectiveFilePath');

      // Clear any previous errors on successful update
      setState(() {
        _validationError = null;
        _isValid = true;
      });

      // Notify that the file was updated via API
      if (widget.onFileUpdated != null) {
        widget.onFileUpdated!(effectiveFilePath);
      }
    } catch (e) {
      debugPrint('Error updating file via API: $e');

      // Parse the error message for better user communication
      String userFriendlyError;
      final errorString = e.toString();

      if (e is FlutterFlowApiException) {
        final status = e.statusCode;
        if (e.isNetworkError) {
          userFriendlyError =
              '🌐 Network Error: Unable to reach FlutterFlow servers. Check your internet connection.';
        } else if (status != null && status >= 400 && status < 500) {
          final bodyText = (e.body ?? e.message);
          final formatted = _formatValidationMessage(
            bodyText,
            yamlContent: content,
            currentFilePath: effectiveFilePath,
          );

          // Use the specialized validation formatter when it provides
          // location details. Otherwise, use the API message directly
          // without adding technical details like endpoint/status.
          if (_isFormattedValidationMessage(bodyText, formatted)) {
            userFriendlyError = formatted;
          } else {
            userFriendlyError = e.message.isNotEmpty ? e.message : 'Update failed with status $status';
          }
        } else {
          userFriendlyError = _composeUpdateErrorMessage(
            filePath: effectiveFilePath,
            attemptedFileKey: attemptedFileKey,
            exception: e,
            yamlContent: content,
          );
        }
      } else if (errorString.contains('400')) {
        // Parse specific 400 errors
        if (errorString.contains('Expected int or stringified int')) {
          userFriendlyError =
              '🔢 YAML Error: Expected a number or quoted number. Check your YAML syntax for numeric values.';
        } else if (errorString.contains('Invalid file key')) {
          userFriendlyError =
              '🗂️ File Error: Invalid file path for FlutterFlow. This file may not be supported.';
        } else {
          userFriendlyError = _formatValidationMessage(
            errorString,
            yamlContent: content,
            currentFilePath: effectiveFilePath,
          );
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

  String _composeUpdateErrorMessage({
    required String filePath,
    required String? attemptedFileKey,
    required FlutterFlowApiException exception,
    required String yamlContent,
  }) {
    final lines = <String>['❌ Update Failed'];
    lines.add('• File: $filePath');
    if (attemptedFileKey != null && attemptedFileKey.isNotEmpty) {
      lines.add('• API key sent: $attemptedFileKey');
    }
    if (exception.statusCode != null) {
      lines.add('• HTTP status: ${exception.statusCode}');
    }
    if (exception.endpoint != null && exception.endpoint!.isNotEmpty) {
      lines.add('• Endpoint: ${exception.endpoint}');
    }
    if (exception.note != null && exception.note!.isNotEmpty) {
      lines.add('• Note: ${exception.note}');
    }
    if (exception.message.isNotEmpty) {
      lines.add('• Message: ${exception.message}');
    }
    if (exception.body != null &&
        exception.body!.isNotEmpty &&
        exception.body != exception.message) {
      lines.add('• Response body: ${exception.body}');
    }

    final inferredPath = YamlFileUtils.inferFilePathFromContent(yamlContent);
    final inferredKey = YamlFileUtils.inferFileKeyFromContent(yamlContent);
    final rawBody = exception.body ?? '';
    final message = exception.message;
    final isInvalidFileKey = message.contains('Invalid file key') ||
        rawBody.contains('Invalid file key');

    if (isInvalidFileKey && inferredKey != null) {
      lines.add('• Expected key (from YAML key field): $inferredKey');
      if (inferredPath != null) {
        lines.add('• Suggested file path: $inferredPath');
      }
      lines.addAll([
        'How to fix:',
        '• Ensure the YAML "key" field matches the file name you are editing.',
        '• For new pages, store the file as "page/<page-key>.yaml" and add the entry to app-details.yaml and folders.yaml before syncing.',
      ]);
    }

    final failedSection = _extractFailedSection(exception);
    // Only add the generic "open the section" tip when there are other
    // actionable hints. If it would be the only tip, skip it (users found it
    // unhelpful in isolation).
    if (failedSection != null) {
      final hasActionables = lines.any((l) =>
          l.contains('🔧') ||
          l.startsWith('How to fix:') ||
          l.contains('Suggested file path:') ||
          l.contains('Expected key (from YAML key field)'));

      if (hasActionables) {
        lines.add(
          '💡 Tip: Open the section "$failedSection" and fix the highlighted key/value, then press Save again.',
        );
      }
    }

    return lines.join('\n');
  }

  bool _looksLikeKeyMismatchError(String text) {
    final lower = text.toLowerCase();
    return lower.contains('cannot change the key') ||
        lower.contains('invalid file key') ||
        lower.contains('file key mismatch');
  }

  bool _isFormattedValidationMessage(String original, String formatted) {
    final trimmed = original.trim();
    final defaultMessage = '❌ Update Failed: $trimmed';
    return formatted != defaultMessage;
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

  void _showSearchMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
    } else {
      debugPrint(message);
    }
  }

  void _handleFindNext() {
    final query = _findController.text;
    if (query.isEmpty) {
      _showSearchMessage('Enter text to find.');
      return;
    }

    final content = _textController.text;
    if (content.isEmpty) {
      _showSearchMessage('No YAML content loaded.');
      return;
    }

    final startIndex =
        _textController.selection.isValid ? _textController.selection.end : 0;
    final matchIndex = _findNextIndex(content, query, startIndex);

    if (matchIndex == -1) {
      _showSearchMessage('No matches for "$query".');
      return;
    }

    _selectMatch(matchIndex, query.length);
  }

  void _handleReplaceCurrent() {
    final query = _findController.text;
    if (query.isEmpty) {
      _showSearchMessage('Enter text to find.');
      return;
    }

    final content = _textController.text;
    if (content.isEmpty) {
      _showSearchMessage('No YAML content loaded.');
      return;
    }

    final selection = _textController.selection;
    final hasSelection = selection.isValid &&
        selection.start >= 0 &&
        selection.end <= content.length &&
        selection.start != selection.end;
    final selectionMatches = hasSelection &&
        content.substring(selection.start, selection.end) == query;

    if (!selectionMatches) {
      _handleFindNext();
      return;
    }

    final replacement = _replaceController.text;
    final newText =
        content.replaceRange(selection.start, selection.end, replacement);
    final newCaret = selection.start + replacement.length;

    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCaret),
    );
    _editorFocusNode.requestFocus();

    _showSearchMessage('Replaced 1 occurrence.');
    _handleFindNext();
  }

  void _handleReplaceAll() {
    final query = _findController.text;
    if (query.isEmpty) {
      _showSearchMessage('Enter text to find.');
      return;
    }

    final content = _textController.text;
    if (content.isEmpty) {
      _showSearchMessage('No YAML content loaded.');
      return;
    }

    final matches = RegExp(RegExp.escape(query)).allMatches(content).toList();
    if (matches.isEmpty) {
      _showSearchMessage('No matches for "$query".');
      return;
    }

    final replacement = _replaceController.text;
    final newText = content.replaceAll(query, replacement);

    _textController.value = TextEditingValue(
      text: newText,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _editorFocusNode.requestFocus();

    final count = matches.length;
    _showSearchMessage(
        'Replaced $count ${count == 1 ? 'occurrence' : 'occurrences'}.');
  }

  int _findNextIndex(String text, String query, int startIndex) {
    final safeStart =
        startIndex.clamp(0, text.isEmpty ? 0 : text.length).toInt();
    final forwardMatch = text.indexOf(query, safeStart);
    if (forwardMatch != -1) return forwardMatch;
    if (safeStart == 0) return -1;
    return text.indexOf(query);
  }

  void _selectMatch(int start, int length) {
    final end = (start + length).clamp(0, _textController.text.length);
    _textController.value = _textController.value.copyWith(
      selection: TextSelection(baseOffset: start, extentOffset: end),
    );
    _editorFocusNode.requestFocus();
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

          // Validation error display (capped height + scroll to avoid overflow)
          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withOpacity(0.1),
                  border:
                      Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
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
                    ),
                    // Scrollable error body with both vertical and horizontal scroll
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final maxErrorHeight =
                            MediaQuery.of(context).size.height * 0.4;
                        return ConstrainedBox(
                          constraints: BoxConstraints(
                            // Cap height so it never pushes content off-screen
                            maxHeight: maxErrorHeight,
                          ),
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            decoration: BoxDecoration(
                              color: AppTheme.backgroundColor,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.dividerColor),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Scrollbar(
                                controller: _errorVController,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _errorVController,
                                  padding: const EdgeInsets.all(12),
                                  child: Scrollbar(
                                    controller: _errorHController,
                                    thumbVisibility: false,
                                    notificationPredicate: (notif) =>
                                        notif.metrics.axis == Axis.horizontal,
                                    child: SingleChildScrollView(
                                      controller: _errorHController,
                                      scrollDirection: Axis.horizontal,
                                      child: SelectableText(
                                        _validationError!,
                                        style: TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 14,
                                          fontFamily: 'monospace',
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
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
                if (_isEditing &&
                    (_hasUnsavedChanges || widget.hasPendingLocalEdits)) ...[
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
          if (!widget.isReadOnly && _isEditing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildFindReplaceBar(),
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

  Widget _buildFindReplaceBar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildFindReplaceField(
          controller: _findController,
          label: 'Find',
          hint: 'Search within file',
          icon: Icons.search,
          onSubmitted: (_) => _handleFindNext(),
        ),
        _buildFindReplaceField(
          controller: _replaceController,
          label: 'Replace',
          hint: 'Replacement text',
          icon: Icons.find_replace,
          onSubmitted: (_) => _handleReplaceCurrent(),
        ),
        _buildFindReplaceButton(
          icon: Icons.search,
          label: 'Find next',
          onPressed: _handleFindNext,
        ),
        _buildFindReplaceButton(
          icon: Icons.swap_horiz,
          label: 'Replace',
          onPressed: _handleReplaceCurrent,
        ),
        _buildFindReplaceButton(
          icon: Icons.auto_fix_high,
          label: 'Replace all',
          onPressed: _handleReplaceAll,
        ),
      ],
    );
  }

  Widget _buildFindReplaceField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    void Function(String)? onSubmitted,
  }) {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: controller,
        style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 16, color: AppTheme.textSecondary),
          filled: true,
          fillColor: AppTheme.backgroundColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: AppTheme.dividerColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: AppTheme.dividerColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
          ),
          hintStyle: AppTheme.bodySmall,
          labelStyle: AppTheme.captionLarge,
        ),
      ),
    );
  }

  Widget _buildFindReplaceButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.primaryColor.withOpacity(0.35)),
            color: AppTheme.surfaceColor,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 6),
              Text(
                label,
                style:
                    AppTheme.captionLarge.copyWith(color: AppTheme.textPrimary),
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
        child: Scrollbar(
          controller: _viewerVController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _viewerVController,
            child: Scrollbar(
              controller: _viewerHController,
              thumbVisibility: false,
              notificationPredicate: (notif) =>
                  notif.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _viewerHController,
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  content,
                  style: AppTheme.monospace.copyWith(
                    color: AppTheme.textPrimary, // Use theme's white text
                  ),
                ),
              ),
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
        focusNode: _editorFocusNode,
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
  String _formatValidationMessage(
    String raw, {
    String? yamlContent,
    String? currentFilePath,
  }) {
    final text = raw.trim();
    final pattern = RegExp(r'^(.*?):\s*\((\d+):(\d+)\)\s*:\s*(.*)$');
    final match = pattern.firstMatch(text);
    if (match != null) {
      final rawLocation = match.group(1)!.trim();
      final line = int.tryParse(match.group(2) ?? '');
      final col = int.tryParse(match.group(3) ?? '');
      final detail = match.group(4)!.trim();
      final normalizedLocation = _normalizeValidationLocation(
        rawLocation,
        fallback: currentFilePath,
      );
      final fixHint = _buildFixHint(detail, normalizedLocation);
      final snippet = (yamlContent != null && line != null && col != null)
          ? _buildContextSnippet(yamlContent, line, col)
          : null;

      final segments = <String>[
        '❌ YAML Validation Failed',
        if (normalizedLocation != null && normalizedLocation.isNotEmpty)
          '• File: $normalizedLocation',
        '• Line/col: ${line ?? '?'}:${col ?? '?'}',
        '• Problem: $detail',
        if (fixHint != null) fixHint,
        if (snippet != null) '📄 Context:\n$snippet',
      ];

      return segments.join('\n');
    }

    // Fallback: try to extract only line/col
    final lc = RegExp(r'\((\d+):(\d+)\)').firstMatch(text);
    if (lc != null) {
      final line = lc.group(1);
      final col = lc.group(2);
      final after = text.contains('):') ? text.split('):').last.trim() : '';
      final fixHint = _buildFixHint(after, currentFilePath);
      final snippet = (yamlContent != null && line != null && col != null)
          ? _buildContextSnippet(
              yamlContent,
              int.tryParse(line) ?? 0,
              int.tryParse(col) ?? 0,
            )
          : null;
      return [
        '❌ YAML Validation Failed',
        '• Location: line $line, col $col',
        if (after.isNotEmpty) '• Details: $after',
        if (fixHint != null) fixHint,
        '💡 Tip: Check indentation, quotes, and key names at this position.',
        if (snippet != null) '📄 Context:\n$snippet',
      ].join('\n');
    }

    // Default: show raw with a clean prefix
    return [
      '❌ Update Failed: $text',
      if (currentFilePath != null && currentFilePath.isNotEmpty)
        'File: $currentFilePath',
    ].join('\n');
  }

  String? _normalizeValidationLocation(String raw, {String? fallback}) {
    final cleaned = raw
        .replaceFirst(RegExp(r'^Failed to update project:\s*'), '')
        .replaceFirst(RegExp(r'^Validation failed for file:\s*'), '')
        .trim();

    if (cleaned.isNotEmpty) {
      return cleaned;
    }

    if (fallback == null) {
      return null;
    }

    final trimmed = fallback.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _buildFixHint(String detail, String? location) {
    final target =
        (location == null || location.isEmpty) ? 'this file' : location;

    final unknownFieldMatch =
        RegExp(r"Unknown field name '([^']+)'", caseSensitive: false)
            .firstMatch(detail);
    if (unknownFieldMatch != null) {
      final field = unknownFieldMatch.group(1);
      return '🔧 Fix: FlutterFlow does not recognize the "$field" key in $target. Compare this file with an exported copy from FlutterFlow and rename or remove that key before saving.';
    }

    final missingFieldMatch =
        RegExp(r"Missing required field '([^']+)'", caseSensitive: false)
            .firstMatch(detail);
    if (missingFieldMatch != null) {
      final field = missingFieldMatch.group(1);
      return '🔧 Fix: Add the required "$field" field to $target. Copy the default structure from FlutterFlow or another working file to ensure all mandatory fields are present.';
    }

    if (_looksLikeKeyMismatchError(detail)) {
      final match = RegExp(r'Cannot change the key "([^"]+)" to "([^"]+)"')
          .firstMatch(detail);
      final fromKey = match?.group(1);
      final toKey = match?.group(2);
      if (fromKey != null && toKey != null) {
        return '🔧 Fix: FlutterFlow requires the YAML "key" field to stay "$fromKey". Update the file so its "key" value matches "$fromKey" (not "$toKey"), then try again.';
      }
      return '🔧 Fix: FlutterFlow requires the YAML "key" field to remain unchanged. Revert the "key" value to the one from your export and try again.';
    }

    if (detail.toLowerCase().contains('duplicate key')) {
      return '🔧 Fix: Remove one of the duplicate keys in $target. YAML files must only declare each key once at the same indentation level.';
    }

    if (detail.toLowerCase().contains('expected') &&
        detail.toLowerCase().contains('but got')) {
      return '🔧 Fix: Update the value at $target to match the expected data type. For example, wrap strings in quotes and ensure numbers are not quoted unless required.';
    }

    return null;
  }

  String _buildContextSnippet(String yamlContent, int line, int column) {
    if (line <= 0) {
      return yamlContent.split('\n').take(5).join('\n');
    }

    final lines = yamlContent.split('\n');
    final targetIndex = line - 1;
    if (targetIndex < 0 || targetIndex >= lines.length) {
      return lines.take(5).join('\n');
    }
    final start = targetIndex - 2 < 0 ? 0 : targetIndex - 2;
    final endExclusive =
        (targetIndex + 3) >= lines.length ? lines.length : targetIndex + 3;
    final buffer = StringBuffer();

    for (var i = start; i < endExclusive; i++) {
      final lineNo = (i + 1).toString().padLeft(4);
      buffer.writeln('$lineNo | ${lines[i]}');
      if (i == targetIndex) {
        final lineLength = lines[i].length;
        final effectiveColumn = column.clamp(1, lineLength + 1).toInt();
        final caretPosition =
            effectiveColumn <= 1 ? '' : ' ' * (effectiveColumn - 1);
        buffer.writeln('     | ${caretPosition}^');
      }
    }

    return buffer.toString().trimRight();
  }

  String? _extractFailedSection(FlutterFlowApiException exception) {
    final candidates = {
      exception.message,
      exception.body,
      exception.note,
    };

    for (final raw in candidates) {
      final value = raw?.trim();
      if (value == null || value.isEmpty) continue;

      final match =
          RegExp(r'Failed to update project:\s*([^\n]+)').firstMatch(value);
      if (match != null) {
        return match.group(1)?.trim();
      }
    }

    return null;
  }

  List<String> _extractValidationErrors(Map<String, dynamic> data) {
    final errors = <String>[];
    final direct = data['validationErrors'];
    final nested = data['value'] is Map<String, dynamic>
        ? (data['value'] as Map<String, dynamic>)['validationErrors']
        : null;

    void collect(dynamic source) {
      if (source is List) {
        for (final entry in source) {
          if (entry is Map && entry['message'] != null) {
            errors.add(entry['message'].toString());
          } else if (entry is String) {
            errors.add(entry);
          }
        }
      }
    }

    collect(direct);
    collect(nested);

    return errors;
  }

  String? _preferredNonExtensionCandidate(List<String> candidates) {
    for (final c in candidates) {
      if (!c.endsWith('.yaml') && !c.endsWith('.yml')) {
        return c;
      }
    }
    return null;
  }

  String? _firstKeyMismatch(List<String> messages) {
    for (final m in messages) {
      if (_looksLikeKeyMismatchError(m)) {
        final match = RegExp(r'Cannot change the key "([^"]+)" to "([^"]+)"')
            .firstMatch(m);
        final fromKey = match?.group(1);
        final toKey = match?.group(2);
        if (fromKey != null && toKey != null) {
          return '❌ YAML Validation Failed\n• Key mismatch: expected "$fromKey" but received "$toKey".\n🔧 Fix: Set the YAML "key" field to "$fromKey" and try again.';
        }
        return '❌ YAML Validation Failed\n• Key mismatch detected. Please revert the YAML "key" field to the value from your export and try again.';
      }
    }
    return null;
  }
}
