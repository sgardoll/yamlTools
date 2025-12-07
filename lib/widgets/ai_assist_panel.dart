import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../storage/preferences_manager.dart';
import '../services/ai/ai_service.dart';
import '../services/ai/ai_models.dart';
import 'diff_view_widget.dart';

enum AIState { idle, processing, reviewing }

class AIAssistPanel extends StatefulWidget {
  final Function(ProposedChange) onApplyChanges;
  final Map<String, String> currentFiles;
  final Function() onClose;

  const AIAssistPanel({
    Key? key,
    required this.onApplyChanges,
    required this.currentFiles,
    required this.onClose,
  }) : super(key: key);

  @override
  _AIAssistPanelState createState() => _AIAssistPanelState();
}

class _AIAssistPanelState extends State<AIAssistPanel> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  AIState _state = AIState.idle;
  ProposedChange? _currentProposal;
  // Use proper set literals to avoid runtime issues in web builds
  Set<String> _pinnedFiles = <String>{};
  String? _errorMessage;
  bool _isApiKeyValid = false;
  AIService? _aiService;

  // Track which file is currently being viewed in review mode
  int _selectedModificationIndex = 0;
  // Track which modifications are selected to apply
  final Set<int> _selectedModificationIndexes = <int>{};

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    final apiKey = await PreferencesManager.getOpenAIKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      setState(() {
        _apiKeyController.text = apiKey;
        _validateApiKey(apiKey);
      });
    }
  }

  Future<void> _saveApiKey(String apiKey) async {
    await PreferencesManager.saveOpenAIKey(apiKey);
  }

  Future<void> _clearApiKey() async {
    await PreferencesManager.clearOpenAIKey();
    setState(() {
      _apiKeyController.clear();
      _aiService = null;
      _isApiKeyValid = false;
    });

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('OpenAI API key cleared'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  void _validateApiKey(String apiKey) {
    if (apiKey.trim().isNotEmpty) {
      setState(() {
        _aiService = AIService(apiKey);
        _isApiKeyValid = true;
      });
    } else {
      setState(() {
        _isApiKeyValid = false;
      });
    }
  }

  void _handleSubmit() async {
    if (_promptController.text.isEmpty || _aiService == null) return;

    setState(() {
      _state = AIState.processing;
      _errorMessage = null;
    });

    try {
      final request = AIRequest(
        userPrompt: _promptController.text,
        pinnedFilePaths: _pinnedFiles.toList(),
        projectFiles: widget.currentFiles,
      );

      final proposal = await _aiService!.requestModification(request: request);

      setState(() {
        _currentProposal = proposal;
        _state = AIState.reviewing;
        _selectedModificationIndex = 0;
        _selectedModificationIndexes
          ..clear()
          ..addAll(List<int>.generate(proposal.modifications.length, (i) => i));
      });
    } catch (e) {
      setState(() {
        _state = AIState.idle;
        _errorMessage = e.toString();
      });
    }
  }

  void _handleMerge() {
    if (_currentProposal != null) {
      // Apply only the selected file modifications
      final selectedMods = <FileModification>[];
      for (var i = 0; i < _currentProposal!.modifications.length; i++) {
        if (_selectedModificationIndexes.contains(i)) {
          selectedMods.add(_currentProposal!.modifications[i]);
        }
      }
      final filtered = ProposedChange(
        summary: _currentProposal!.summary,
        modifications: selectedMods,
      );
      widget.onApplyChanges(filtered);
      // Reset state but keep API key
      setState(() {
        _state = AIState.idle;
        _currentProposal = null;
        _promptController.clear();
        _pinnedFiles.clear();
        _selectedModificationIndexes.clear();
      });
    }
  }

  void _handleDiscard() {
    setState(() {
      _state = AIState.idle;
      _currentProposal = null;
    });
  }

  void _showContextPicker() {
    // Capture state outside the builder so it persists across setState calls
    final allFiles = widget.currentFiles.keys.toList()..sort();
    String query = '';
    // Initialize with filtered list (exclude special aggregate files)
    List<String> files = allFiles
        .where(
            (file) => file != 'complete_raw.yaml' && file != 'raw_project.yaml')
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Select Context Files'),
              content: Container(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search files...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() {
                          query = value.trim().toLowerCase();
                          files = allFiles.where((file) {
                            // Hide only special aggregate files
                            if (file == 'complete_raw.yaml' ||
                                file == 'raw_project.yaml') {
                              return false;
                            }
                            final display = file.startsWith('archive_')
                                ? file.substring('archive_'.length)
                                : file;
                            return file.toLowerCase().contains(query) ||
                                display.toLowerCase().contains(query);
                          }).toList();
                        });
                      },
                    ),
                    SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: files.length,
                        itemBuilder: (context, index) {
                          final file = files[index];
                          // Skip only special aggregate files; include archive_ files
                          if (file == 'complete_raw.yaml' ||
                              file == 'raw_project.yaml') {
                            return SizedBox.shrink();
                          }
                          final displayName = file.startsWith('archive_')
                              ? file.substring('archive_'.length)
                              : file;

                          final isSelected = _pinnedFiles.contains(file);
                          return CheckboxListTile(
                            title: Text(displayName,
                                style: TextStyle(fontSize: 13)),
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _pinnedFiles.add(file);
                                } else {
                                  _pinnedFiles.remove(file);
                                }
                              });
                              // Update the parent widget state as well
                              this.setState(() {});
                            },
                            dense: true,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 450, // Slightly wider for diff view
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          left: BorderSide(
            color: AppTheme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _isApiKeyValid ? _buildApiKeyStatusBar() : _buildApiKeySection(),
          if (_isApiKeyValid) Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text(
                "AI Assist",
                style: AppTheme.headingMedium,
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: widget.onClose,
            tooltip: 'Close AI Assist',
          ),
        ],
      ),
    );
  }

  Widget _buildApiKeySection() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OpenAI API Key',
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(),
                    hintText: "Enter your OpenAI API key to get started",
                  ),
                  obscureText: true,
                ),
              ),
              SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final apiKey = _apiKeyController.text.trim();
                  _validateApiKey(apiKey);
                  _saveApiKey(apiKey);
                },
                child: Text('Save'),
              ),
              SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _clearApiKey,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApiKeyStatusBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user, color: AppTheme.successColor, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'OpenAI key stored securely',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _isApiKeyValid = false;
              });
            },
            child: const Text('Update'),
          ),
          TextButton(
            onPressed: _clearApiKey,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_state) {
      case AIState.idle:
        return _buildInputState();
      case AIState.processing:
        return _buildProcessingState();
      case AIState.reviewing:
        return _buildReviewState();
    }
  }

  Widget _buildInputState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final promptHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight * 0.4
            : 240.0;
        final clampedPromptHeight =
            promptHeight.clamp(200.0, 420.0); // keeps a tall, scrollable input

        return SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Describe the changes you want to make:',
                  style: AppTheme.bodyMedium,
                ),
                SizedBox(height: 8),
                SizedBox(
                  height: clampedPromptHeight,
                  child: TextField(
                    controller: _promptController,
                    decoration: InputDecoration(
                      hintText:
                          'E.g., "Add a verified boolean field to the users collection" or "Change the primary color to red"',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                  ),
                ),
                SizedBox(height: 16),

                // Context Pinning
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _showContextPicker,
                      icon: Icon(Icons.playlist_add_check, size: 18),
                      label: Text('Context Files (${_pinnedFiles.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pinnedFiles.isNotEmpty
                            ? Colors.blue[100]
                            : Colors.grey[200],
                        foregroundColor: Colors.black87,
                      ),
                    ),
                    Spacer(),
                  ],
                ),

                if (_pinnedFiles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: _pinnedFiles
                          .map((f) => Chip(
                                label: Text(f, style: TextStyle(fontSize: 10)),
                                deleteIcon: Icon(Icons.close, size: 12),
                                onDeleted: () {
                                  setState(() {
                                    _pinnedFiles.remove(f);
                                  });
                                },
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                  ),

                SizedBox(height: 16),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red),
                    ),
                  ),

                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _handleSubmit,
                    icon: Icon(Icons.auto_awesome),
                    label: Text('Generate Changes'),
                    style: AppTheme.primaryButtonStyle,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProcessingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text(
            'Analyzing project structure...',
            style: AppTheme.headingSmall,
          ),
          SizedBox(height: 8),
          Text(
            'Generating YAML modifications',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewState() {
    final mods = _currentProposal!.modifications;
    final currentMod =
        mods.isNotEmpty ? mods[_selectedModificationIndex] : null;

    return Column(
      children: [
        // Summary Header
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          color: Colors.blue[50],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Assist',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
                ),
              ),
              SizedBox(height: 4),
              Text(
                _currentProposal!.summary,
                style: TextStyle(color: Colors.blue[800]),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _selectedModificationIndexes.length == mods.length &&
                        mods.isNotEmpty,
                    onChanged: (checked) {
                      setState(() {
                        _selectedModificationIndexes.clear();
                        if (checked == true) {
                          _selectedModificationIndexes.addAll(
                              List<int>.generate(mods.length, (i) => i));
                        }
                      });
                    },
                  ),
                  Text(
                    'Apply ${_selectedModificationIndexes.length}/${mods.length} files',
                    style: TextStyle(color: Colors.blue[900]),
                  ),
                ],
              ),
            ],
          ),
        ),

        // File Tabs
        if (mods.length > 1)
          Container(
            height: 40,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: mods.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedModificationIndex;
                final isChecked = _selectedModificationIndexes.contains(index);
                return InkWell(
                  onTap: () =>
                      setState(() => _selectedModificationIndex = index),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected
                              ? AppTheme.primaryColor
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      color: isSelected ? Colors.blue.withOpacity(0.05) : null,
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: isChecked,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedModificationIndexes.add(index);
                              } else {
                                _selectedModificationIndexes.remove(index);
                              }
                            });
                          },
                        ),
                        SizedBox(width: 4),
                        Text(
                          mods[index].filePath,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? AppTheme.primaryColor
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

        // Diff View
        Expanded(
          child: currentMod != null
              ? DiffViewWidget(
                  originalContent: currentMod.originalContent,
                  modifiedContent: currentMod.newContent,
                  fileName: currentMod.filePath,
                )
              : Center(child: Text("No modifications")),
        ),

        // Actions
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                offset: Offset(0, -2),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _handleDiscard,
                  child: Text('Discard'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red.withOpacity(0.5)),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _selectedModificationIndexes.isEmpty
                      ? null
                      : _handleMerge,
                  child: Text(
                    'Apply Selected as Local Edits',
                    textAlign: TextAlign.center,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
