import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../storage/preferences_manager.dart';
import '../theme/app_theme.dart';
import 'diff_view_widget.dart';

enum AIState { idle, processing, reviewing }

class AIAssistPanel extends StatefulWidget {
  final Future<void> Function(List<FileModification> modifications)
      onMergeChanges;
  final Map<String, String> currentFiles;
  final VoidCallback onClose;

  const AIAssistPanel({
    super.key,
    required this.onMergeChanges,
    required this.currentFiles,
    required this.onClose,
  });

  @override
  State<AIAssistPanel> createState() => _AIAssistPanelState();
}

class _AIAssistPanelState extends State<AIAssistPanel> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();

  AIState _state = AIState.idle;
  ProposedChange? _proposal;
  List<String> _pinnedFiles = [];
  String _progressMessage = 'Idle';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final savedKey = await PreferencesManager.getOpenAIKey();
    if (savedKey != null && savedKey.isNotEmpty) {
      setState(() {
        _apiKeyController.text = savedKey;
      });
    }
  }

  Future<void> _saveApiKey() async {
    await PreferencesManager.saveOpenAIKey(_apiKeyController.text.trim());
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _promptController.dispose();
    _promptFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    final apiKey = _apiKeyController.text.trim();
    final prompt = _promptController.text.trim();
    if (apiKey.isEmpty || prompt.isEmpty || _isSubmitting) return;

    setState(() {
      _state = AIState.processing;
      _progressMessage = 'Analyzing project structure...';
      _proposal = null;
      _isSubmitting = true;
    });

    await _saveApiKey();

    try {
      final request = AIRequest(
        userPrompt: prompt,
        pinnedFilePaths: _pinnedFiles,
        projectFiles: widget.currentFiles,
      );

      final service = AIService(apiKey: apiKey);
      setState(() {
        _progressMessage = 'Generating YAML modifications...';
      });

      final proposal = await service.requestModification(request: request);
      setState(() {
        _proposal = proposal;
        _state = AIState.reviewing;
      });
    } catch (e) {
      setState(() {
        _progressMessage = 'Error: ${e.toString()}';
        _state = AIState.idle;
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _discardProposal() {
    setState(() {
      _proposal = null;
      _state = AIState.idle;
    });
  }

  Future<void> _mergeProposal() async {
    if (_proposal == null) return;
    await widget.onMergeChanges(_proposal!.modifications);
    setState(() {
      _state = AIState.idle;
      _proposal = null;
      _promptController.clear();
    });
  }

  void _togglePinned(String path) {
    setState(() {
      if (_pinnedFiles.contains(path)) {
        _pinnedFiles.remove(path);
      } else {
        _pinnedFiles.add(path);
      }
    });
  }

  Future<void> _showPinSelector() async {
    await showDialog(
      context: context,
      builder: (context) {
        final fileList = widget.currentFiles.keys.toList()..sort();
        return AlertDialog(
          title: const Text('Pin context files'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: fileList.length,
              itemBuilder: (context, index) {
                final path = fileList[index];
                final isPinned = _pinnedFiles.contains(path);
                return CheckboxListTile(
                  value: isPinned,
                  onChanged: (_) => _togglePinned(path),
                  dense: true,
                  title: Text(
                    path,
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'OpenAI API Key',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                onSubmitted: (_) => _saveApiKey(),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _showPinSelector,
              icon: const Icon(Icons.push_pin_outlined),
              label: const Text('Pin Context'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondaryColor,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close AI Assist',
              onPressed: widget.onClose,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _pinnedFiles
              .map(
                (file) => Chip(
                  label: Text(file, overflow: TextOverflow.ellipsis),
                  onDeleted: () => _togglePinned(file),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _promptController,
          focusNode: _promptFocusNode,
          decoration: const InputDecoration(
            labelText: 'Describe the change you want',
            hintText: "e.g., Add an 'isAdmin' boolean to the Users collection",
            border: OutlineInputBorder(),
          ),
          maxLines: null,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _submitRequest,
            icon: const Icon(Icons.send),
            label: Text(_state == AIState.processing ? 'Working...' : 'Generate'),
          ),
        ),
      ],
    );
  }

  Widget _buildProcessingState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _progressMessage,
              style: AppTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewState() {
    if (_proposal == null) return const SizedBox.shrink();
    final modifications = _proposal!.modifications;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Proposed Changes',
                style: AppTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _proposal!.summary,
                style: AppTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: modifications
                    .map((m) => Chip(
                          label: Text(
                            m.filePath,
                            style: AppTheme.bodySmall,
                          ),
                          avatar: Icon(
                            m.isNewFile ? Icons.note_add : Icons.edit,
                            size: 18,
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 420,
          child: PageView.builder(
            itemCount: modifications.length,
            itemBuilder: (context, index) {
              final mod = modifications[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DiffViewWidget(
                  originalContent: mod.originalContent,
                  modifiedContent: mod.newContent,
                  fileName: mod.filePath,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _mergeProposal,
              icon: const Icon(Icons.check),
              label: const Text('Merge Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.successColor,
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _discardProposal,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Discard'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI Developer', style: AppTheme.titleMedium),
            const SizedBox(height: 12),
            _buildInputArea(),
            const SizedBox(height: 16),
            if (_state == AIState.processing) _buildProcessingState(),
            if (_state == AIState.reviewing) _buildReviewState(),
          ],
        ),
      ),
    );
  }
}
