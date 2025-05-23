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
          _validationError = 'API token not found for update';
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
      // Show the update error in the UI
      setState(() {
        _validationError =
            'Update failed: ${e.toString().contains('Invalid file key') ? 'Invalid file key for FlutterFlow' : 'Network error'}';
        _isValid = false;
      });
    } finally {
      setState(() {
        _isUpdating = false;
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
          else if (_isUpdating)
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
                    'Updating',
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

          const SizedBox(width: 12),

          // Edit button (if not in read-only mode)
          if (!widget.isReadOnly && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit,
                  color: AppTheme.primaryColor, size: 16),
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
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                  onPressed: (_isValidating || _isUpdating)
                      ? null
                      : () async {
                          final newContent = _textController.text;

                          // First validate the YAML
                          await _validateYaml(newContent);

                          // If validation is successful, proceed with local save and API update
                          if (_isValid || widget.projectId.isEmpty) {
                            // Update local content first
                            if (widget.onContentChanged != null) {
                              widget.onContentChanged!(newContent);
                            }

                            // If we have a project ID, automatically update via API
                            if (widget.projectId.isNotEmpty) {
                              await _updateFileViaApi(newContent);
                            }

                            setState(() {
                              _isEditing = false;
                            });
                          }
                        },
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  child: const Text('Cancel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: (_isValidating || _isUpdating)
                      ? null
                      : () {
                          // Reset to original content
                          _textController.text = widget.content ?? '';
                          setState(() {
                            _isEditing = false;
                          });
                        },
                ),
              ],
            ),

          // Add spacing between edit buttons and copy button
          if (_isEditing) const SizedBox(width: 16),

          // Copy button
          if (!_isEditing)
            IconButton(
              icon: Icon(
                _isCopied ? Icons.check : Icons.copy,
                color:
                    _isCopied ? AppTheme.successColor : AppTheme.primaryColor,
                size: 16,
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
        color: Colors.grey[50], // Light background for better readability
        child: SingleChildScrollView(
          child: Text(
            content,
            style: AppTheme.monospace.copyWith(
              color: Colors.black87, // Dark text for visibility
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50], // Match the viewer background
      child: TextField(
        controller: _textController,
        style: AppTheme.monospace.copyWith(
          color: Colors.black87, // Explicit dark text
        ),
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white, // White background for the text field
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey[400]!),
            borderRadius: BorderRadius.circular(4),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey[400]!),
            borderRadius: BorderRadius.circular(4),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          contentPadding: const EdgeInsets.all(12),
          hintText: 'Enter YAML content...',
          hintStyle: TextStyle(color: Colors.grey[600]),
        ),
      ),
    );
  }
}
