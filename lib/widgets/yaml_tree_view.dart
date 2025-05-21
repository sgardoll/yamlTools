import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'diff_view_widget.dart';

class YamlTreeView extends StatefulWidget {
  final Map<String, String> yamlFiles;
  final Function(String, String)? onFileEdited; // Callback when file is edited
  final Map<String, String>? originalFiles; // Original files for comparison
  final Set<String>?
      expandedFiles; // Files that should be automatically expanded/selected

  const YamlTreeView({
    Key? key,
    required this.yamlFiles,
    this.onFileEdited,
    this.originalFiles,
    this.expandedFiles,
  }) : super(key: key);

  @override
  _YamlTreeViewState createState() => _YamlTreeViewState();
}

class _YamlTreeViewState extends State<YamlTreeView> {
  Map<String, bool> _expandedNodes = {};
  late TreeNode _rootNode;

  // Track the selected file and editing state
  String? _selectedFilePath;
  bool _isEditing = false;
  TextEditingController _fileController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _buildTree();
    _checkForAutoSelectFiles();
  }

  @override
  void didUpdateWidget(YamlTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.yamlFiles != widget.yamlFiles) {
      _buildTree();

      // Update selected file content if it still exists
      if (_selectedFilePath != null &&
          widget.yamlFiles.containsKey(_selectedFilePath)) {
        _fileController.text = widget.yamlFiles[_selectedFilePath]!;
      }
    }

    // Check if expanded files changed
    if (oldWidget.expandedFiles != widget.expandedFiles) {
      _checkForAutoSelectFiles();
    }
  }

  @override
  void dispose() {
    _fileController.dispose();
    super.dispose();
  }

  void _buildTree() {
    _rootNode = TreeNode(name: 'Root', type: NodeType.root);

    // Group YAML files by their pattern
    final files = widget.yamlFiles.keys.toList()
      ..sort((a, b) => a.compareTo(b));

    for (final filePath in files) {
      // Skip system files, we'll handle them separately
      if (filePath.contains('complete_raw.yaml') ||
          filePath.contains('raw_project.yaml')) {
        continue;
      }

      if (!filePath.startsWith('archive_')) continue;
      if (!filePath.endsWith('.yaml')) continue;

      // Extract path parts
      final fileName = filePath.replaceFirst('archive_', '');
      final pathParts = fileName.split('/');

      // Skip files that don't match our expected patterns
      if (pathParts.length < 2) continue;

      TreeNode currentNode = _rootNode;

      // Build the path in the tree
      for (int i = 0; i < pathParts.length; i++) {
        final part = pathParts[i];
        final isLastPart = i == pathParts.length - 1;

        // Detect node types based on path patterns
        NodeType nodeType = NodeType.folder;

        if (part.startsWith('id-') && isLastPart) {
          nodeType = NodeType.leaf;
        } else if (part.startsWith('component')) {
          nodeType = NodeType.component;
        } else if (part == 'node') {
          nodeType = NodeType.folder;
        } else if (part.startsWith('id-')) {
          if (part.contains('Container')) {
            nodeType = NodeType.container;
          } else if (part.contains('Column')) {
            nodeType = NodeType.layout;
          } else {
            nodeType = NodeType.widget;
          }
        } else if (part.startsWith('collections')) {
          nodeType = NodeType.collection;
        }

        // Find or create child node
        TreeNode? childNode = currentNode.children.firstWhere(
          (node) => node.name == part,
          orElse: () {
            final newNode = TreeNode(
              name: part,
              type: nodeType,
              filePath: isLastPart ? filePath : null,
            );
            currentNode.children.add(newNode);
            return newNode;
          },
        );

        currentNode = childNode;
      }
    }

    // Recursive sort to ensure consistent order
    _sortTreeNodes(_rootNode);
  }

  void _sortTreeNodes(TreeNode node) {
    // Sort this node's children
    node.children.sort((a, b) {
      // Put collections and components first
      if (a.type == NodeType.collection && b.type != NodeType.collection)
        return -1;
      if (a.type != NodeType.collection && b.type == NodeType.collection)
        return 1;
      if (a.type == NodeType.component && b.type != NodeType.component)
        return -1;
      if (a.type != NodeType.component && b.type == NodeType.component)
        return 1;

      // Then sort alphabetically
      return a.name.compareTo(b.name);
    });

    // Recursively sort children's children
    for (var child in node.children) {
      _sortTreeNodes(child);
    }
  }

  // Select a file and prepare the editor
  void _selectFile(String? filePath) {
    setState(() {
      _selectedFilePath = filePath;
      _isEditing = false;

      if (filePath != null && widget.yamlFiles.containsKey(filePath)) {
        _fileController.text = widget.yamlFiles[filePath]!;
      } else {
        _fileController.text = '';
      }
    });
  }

  // Apply changes to the file
  void _applyChanges() {
    if (_selectedFilePath != null && widget.onFileEdited != null) {
      widget.onFileEdited!(_selectedFilePath!, _fileController.text);
      setState(() {
        _isEditing = false;
      });
    }
  }

  // Check if a file is modified compared to original
  bool _isFileModified(String filePath) {
    return widget.originalFiles != null &&
        widget.originalFiles!.containsKey(filePath) &&
        widget.originalFiles![filePath] != widget.yamlFiles[filePath];
  }

  // Check if any files should be automatically selected
  void _checkForAutoSelectFiles() {
    if (widget.expandedFiles != null && widget.expandedFiles!.isNotEmpty) {
      // Find the first expanded file to select
      for (String filePath in widget.expandedFiles!) {
        if (widget.yamlFiles.containsKey(filePath)) {
          _selectFile(filePath);
          break; // Only select the first one
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if we have important system files to show at the top
    bool hasCompleteRaw =
        widget.yamlFiles.keys.any((f) => f.contains('complete_raw.yaml'));
    bool hasRawProject =
        widget.yamlFiles.keys.any((f) => f.contains('raw_project.yaml'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tree Title
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'YAML Structure',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),

        // System files section - hide completely since we now have buttons in the top bar
        // if (hasCompleteRaw || hasRawProject)
        //   Padding(
        //     padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        //     child: Column(
        //       crossAxisAlignment: CrossAxisAlignment.start,
        //       children: [
        //         Text(
        //           'System Files:',
        //           style: TextStyle(
        //             fontSize: 12,
        //             fontWeight: FontWeight.bold,
        //             color: Colors.grey[700],
        //           ),
        //         ),
        //         if (hasCompleteRaw)
        //           _buildCompactSystemFile(
        //               'complete_raw.yaml',
        //               widget.yamlFiles.keys
        //                   .firstWhere((f) => f.contains('complete_raw.yaml'))),
        //         if (hasRawProject)
        //           _buildCompactSystemFile(
        //               'raw_project.yaml',
        //               widget.yamlFiles.keys
        //                   .firstWhere((f) => f.contains('raw_project.yaml'))),
        //         Divider(),
        //       ],
        //     ),
        //   ),

        // Split view: Tree (top) and Editor (bottom)
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side: Tree view
              Expanded(
                flex: 2,
                child: Card(
                  margin: EdgeInsets.all(8.0),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: _buildTreeNodes(_rootNode.children),
                    ),
                  ),
                ),
              ),

              // Right side: Selected file preview/editor
              Expanded(
                flex: 3,
                child: _buildFileEditor(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper method to build compact view for system files
  Widget _buildCompactSystemFile(String displayName, String filePath) {
    String content = widget.yamlFiles[filePath] ?? '';
    bool isModified = _isFileModified(filePath);

    return Card(
      elevation: 0,
      color: Colors.grey[100],
      margin: EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: () => _selectFile(filePath),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description, size: 14, color: Colors.blue[700]),
              SizedBox(width: 4),
              Text(
                displayName,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue[700],
                ),
              ),
              SizedBox(width: 4),
              if (isModified)
                Icon(Icons.edit_document, size: 12, color: Colors.amber[800]),
            ],
          ),
        ),
      ),
    );
  }

  // Build the file editor panel
  Widget _buildFileEditor() {
    if (_selectedFilePath == null) {
      return Card(
        margin: EdgeInsets.all(8.0),
        child: Center(
          child:
              Text('Select a file from the tree to view and edit its content'),
        ),
      );
    }

    bool isModified = _isFileModified(_selectedFilePath!);

    return Card(
      margin: EdgeInsets.all(8.0),
      color: isModified ? Colors.amber[50] : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // File info header
          Container(
            padding: EdgeInsets.all(8.0),
            color: isModified ? Colors.amber[100] : Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedFilePath!.replaceFirst('archive_', ''),
                        style: TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${_fileController.text.length} characters',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                // Edit/Save buttons
                if (_isEditing) ...[
                  ElevatedButton(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.save, size: 16, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Save'),
                      ],
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      minimumSize: Size(0, 36),
                    ),
                    onPressed: _applyChanges,
                  ),
                  SizedBox(width: 8),
                  TextButton(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cancel, size: 16, color: Colors.red),
                        SizedBox(width: 4),
                        Text('Cancel'),
                      ],
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    onPressed: () {
                      setState(() {
                        _fileController.text =
                            widget.yamlFiles[_selectedFilePath]!;
                        _isEditing = false;
                      });
                    },
                  ),
                ] else ...[
                  ElevatedButton(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 16, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Edit'),
                      ],
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      minimumSize: Size(0, 36),
                    ),
                    onPressed: () {
                      setState(() {
                        _isEditing = true;
                      });
                    },
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy, size: 16, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Copy'),
                      ],
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      minimumSize: Size(0, 36),
                    ),
                    onPressed: () {
                      // Implementation for copying content
                      Clipboard.setData(
                              ClipboardData(text: _fileController.text))
                          .then((_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      });
                    },
                  ),
                ],
              ],
            ),
          ),

          // File content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _isEditing
                  ? TextField(
                      controller: _fileController,
                      maxLines: null,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Edit YAML content here...',
                      ),
                      style: TextStyle(fontFamily: 'monospace'),
                    )
                  : isModified && !_isEditing && widget.originalFiles != null
                      ? DiffViewWidget(
                          originalContent:
                              widget.originalFiles![_selectedFilePath!] ?? '',
                          modifiedContent: _fileController.text,
                          fileName:
                              _selectedFilePath!.replaceFirst('archive_', ''),
                          onClose: null, // Keep it open in the tree view
                        )
                      : GestureDetector(
                          onTap: () {
                            setState(() {
                              _isEditing = true;
                            });
                          },
                          child: Container(
                            color: Colors.transparent,
                            width: double.infinity,
                            child: SingleChildScrollView(
                              child: Text(
                                _fileController.text,
                                style: TextStyle(fontFamily: 'monospace'),
                              ),
                            ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeNodes(List<TreeNode> nodes, {int depth = 0}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: nodes.map((node) {
        final isExpanded = _expandedNodes[node.path] ?? false;
        final isSelected =
            node.filePath != null && node.filePath == _selectedFilePath;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                if (node.filePath != null) {
                  _selectFile(node.filePath);
                }

                if (node.children.isNotEmpty) {
                  setState(() {
                    _expandedNodes[node.path] = !isExpanded;
                  });
                }
              },
              child: Container(
                padding: EdgeInsets.only(
                  left: depth * 24.0,
                  top: 4.0,
                  bottom: 4.0,
                  right: 8.0,
                ),
                color: isSelected ? Colors.blue[50] : null,
                child: Row(
                  children: [
                    if (node.children.isNotEmpty)
                      Icon(
                        isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                        size: 20,
                        color: isSelected ? Colors.blue : null,
                      )
                    else
                      SizedBox(width: 20),

                    _getIconForNodeType(node.type, isSelected: isSelected),

                    SizedBox(width: 8),

                    Expanded(
                      child: Text(
                        _getDisplayName(node.name),
                        style: TextStyle(
                          fontWeight: (node.type == NodeType.leaf ||
                                  node.type == NodeType.component ||
                                  node.type == NodeType.collection ||
                                  isSelected)
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected ? Colors.blue[800] : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Show a modified indicator if applicable
                    if (node.filePath != null &&
                        _isFileModified(node.filePath!))
                      Icon(Icons.edit_document,
                          size: 16, color: Colors.amber[800]),
                  ],
                ),
              ),
            ),
            if (isExpanded && node.children.isNotEmpty)
              _buildTreeNodes(node.children, depth: depth + 1),
          ],
        );
      }).toList(),
    );
  }

  String _getDisplayName(String name) {
    // Make the display name more readable
    String displayName = name;

    // Extract name from id-* pattern
    if (name.startsWith('id-')) {
      displayName = name.substring(3);

      // Make it more readable - split on underscores and camelCase
      displayName = displayName
          .replaceAllMapped(
              RegExp(r'([a-z])([A-Z])'), (match) => '${match[1]} ${match[2]}')
          .replaceAll('_', ' ');
    }

    return displayName;
  }

  Widget _getIconForNodeType(NodeType type, {bool isSelected = false}) {
    Color? color;

    switch (type) {
      case NodeType.root:
        color = isSelected ? Colors.blue[800] : Colors.blue[700];
        return Icon(Icons.folder, color: color);
      case NodeType.folder:
        color = isSelected ? Colors.amber[800] : Colors.amber;
        return Icon(Icons.folder, color: color);
      case NodeType.component:
        color = isSelected ? Colors.purple[800] : Colors.purple;
        return Icon(Icons.widgets, color: color);
      case NodeType.container:
        color = isSelected ? Colors.teal[800] : Colors.teal;
        return Icon(Icons.check_box_outline_blank, color: color);
      case NodeType.layout:
        color = isSelected ? Colors.indigo[800] : Colors.indigo;
        return Icon(Icons.view_column, color: color);
      case NodeType.widget:
        color = isSelected ? Colors.green[800] : Colors.green;
        return Icon(Icons.style, color: color);
      case NodeType.leaf:
        color = isSelected ? Colors.blue[800] : Colors.grey;
        return Icon(Icons.description, color: color);
      case NodeType.collection:
        color = isSelected ? Colors.orange[800] : Colors.orange;
        return Icon(Icons.storage, color: color);
    }
  }
}

class TreeNode {
  final String name;
  final NodeType type;
  final String? filePath;
  final List<TreeNode> children = [];

  TreeNode({
    required this.name,
    required this.type,
    this.filePath,
  });

  String get path => filePath ?? name;
}

enum NodeType {
  root,
  folder,
  component,
  container,
  layout,
  widget,
  leaf,
  collection,
}
