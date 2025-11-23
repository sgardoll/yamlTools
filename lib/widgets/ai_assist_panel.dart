import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../storage/preferences_manager.dart';
import '../theme/app_theme.dart';
import 'diff_view_widget.dart';

enum AIState { idle, processing, reviewing }

class AIAssistPanel extends StatefulWidget {
  final Future<void> Function(List<FileModification>) onApplyChanges;
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
  final Set<String> _pinnedFiles = {};

  AIService? _aiService;
  bool _isApiKeyValid = false;
  AIState _state = AIState.idle;
  ProposedChange? _proposal;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _promptController.dispose();
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

  void _validateApiKey(String apiKey) {
    if (apiKey.trim().isNotEmpty) {
      setState(() {
        _aiService = AIService(apiKey: apiKey.trim());
        _isApiKeyValid = true;
      });
    } else {
      setState(() {
        _aiService = null;
        _isApiKeyValid = false;
      });
    }
  }

  Future<void> _handleSubmit() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || !_isApiKeyValid || _aiService == null) {
      return;
    }

    setState(() {
      _state = AIState.processing;
      _errorMessage = null;
      _proposal = null;
    });

    try {
      final proposal = await _aiService!.requestModification(
        request: AIRequest(
          userPrompt: prompt,
          pinnedFilePaths: _pinnedFiles.toList(),
          projectFiles: widget.currentFiles,
        ),
      );

      setState(() {
        _proposal = proposal;
        _state = AIState.reviewing;
      });
    } catch (e) {
      setState(() {
        _state = AIState.idle;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _mergeProposal() async {
    if (_proposal == null) return;
    await widget.onApplyChanges(_proposal!.modifications);
    setState(() {
      _state = AIState.idle;
      _proposal = null;
      _promptController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('AI changes merged into local state'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _discardProposal() {
    setState(() {
      _proposal = null;
      _state = AIState.idle;
    });
  }

  Widget _buildContextPinning() {
    final files = widget.currentFiles.keys.toList()..sort();
    return ExpansionTile(
      title: Text(
        'Pin context files (${_pinnedFiles.length})',
        style: AppTheme.bodyMedium,
      ),
      children: [
        SizedBox(
          height: 200,
          child: Scrollbar(
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                final path = files[index];
                return CheckboxListTile(
                  dense: true,
                  title: Text(
                    path,
                    style: AppTheme.bodySmall,
                  ),
                  value: _pinnedFiles.contains(path),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _pinnedFiles.add(path);
                      } else {
                        _pinnedFiles.remove(path);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIdleState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildApiKeySection(),
        const SizedBox(height: 8),
        Text(
          'Describe the change you want. The AI will propose structured YAML updates with an interactive diff.',
          style: AppTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _buildContextPinning(),
        const SizedBox(height: 12),
        TextField(
          controller: _promptController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "e.g. 'Add a new isAdmin boolean to Users collection'",
          ),
          maxLines: 3,
          minLines: 1,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _handleSubmit,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Generate Proposal'),
          ),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
      ],
    );
  }

  Widget _buildProcessingState() {
    return Column(
      children: [
        const SizedBox(height: 16),
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          'Analyzing project structure...',
          style: AppTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Generating YAML modifications...',
          style: AppTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildReviewState() {
    if (_proposal == null) {
      return const SizedBox.shrink();
    }
    final modifications = _proposal!.modifications;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProposalSummary(_proposal!),
        const SizedBox(height: 12),
        Expanded(
          child: DefaultTabController(
            length: modifications.length,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  labelColor: AppTheme.primaryColor,
                  tabs: [
                    for (final mod in modifications)
                      Tab(text: mod.filePath.split('/').last),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final mod in modifications)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: DiffViewWidget(
                            originalContent: mod.originalContent,
                            modifiedContent: mod.newContent,
                            fileName: mod.filePath,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _mergeProposal,
              icon: const Icon(Icons.check),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              label: const Text('Merge Changes'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _discardProposal,
              icon: const Icon(Icons.close),
              label: const Text('Discard'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProposalSummary(ProposedChange proposal) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Proposed Changes',
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(proposal.summary, style: AppTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final mod in proposal.modifications)
                Chip(
                  label: Text(
                    mod.filePath,
                    style: AppTheme.bodySmall,
                  ),
                  backgroundColor:
                      mod.isNewFile ? Colors.orange[50] : Colors.green[50],
                ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildApiKeySection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OpenAI API Key',
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Enter your OpenAI API key',
                  ),
                  onChanged: _validateApiKey,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final apiKey = _apiKeyController.text.trim();
                  _validateApiKey(apiKey);
                  _saveApiKey(apiKey);
                },
                child: const Text('Save'),
              ),
            ],
          ),
          if (!_isApiKeyValid && _apiKeyController.text.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(
                'Please enter a valid API key',
                style: TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 480,
      color: AppTheme.backgroundColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'AI Developer',
                style: AppTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              )
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: () {
                switch (_state) {
                  case AIState.idle:
                    return _buildIdleState();
                  case AIState.processing:
                    return _buildProcessingState();
                  case AIState.reviewing:
                    return _buildReviewState();
                }
              }(),
            ),
          ),
        ],
      ),
    );
  }
}
