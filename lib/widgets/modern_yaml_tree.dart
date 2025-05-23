import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'dart:collection';

enum NodeType {
  root,
  folder,
  collection,
  component,
  container,
  layout,
  widget,
  button,
  node,
  leaf,
  trigger,
  action,
  file,
}

class TreeNode {
  final String name;
  final NodeType type;
  final String? filePath;
  final List<TreeNode> children;

  TreeNode({
    required this.name,
    required this.type,
    this.filePath,
    List<TreeNode>? children,
  }) : children = children ?? [];
}

class ModernYamlTree extends StatefulWidget {
  final Map<String, String> yamlFiles;
  final Function(String)? onFileSelected;
  final Set<String>? expandedNodes;
  final Map<String, DateTime>? validationTimestamps;

  const ModernYamlTree({
    Key? key,
    required this.yamlFiles,
    this.onFileSelected,
    this.expandedNodes,
    this.validationTimestamps,
  }) : super(key: key);

  @override
  _ModernYamlTreeState createState() => _ModernYamlTreeState();
}

class _ModernYamlTreeState extends State<ModernYamlTree> {
  late TreeNode _rootNode;
  Set<String> _expandedNodes = {};
  String? _selectedFilePath;
  // Track processed file paths to avoid duplicates
  Set<String> _processedFiles = {};

  @override
  void initState() {
    super.initState();
    _buildTree();
    if (widget.expandedNodes != null) {
      _expandedNodes = Set.from(widget.expandedNodes!);
    }
  }

  @override
  void didUpdateWidget(ModernYamlTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.yamlFiles != widget.yamlFiles) {
      _buildTree();
    }
    if (oldWidget.expandedNodes != widget.expandedNodes) {
      if (widget.expandedNodes != null) {
        _expandedNodes = Set.from(widget.expandedNodes!);
      }
    }
  }

  void _buildTree() {
    _rootNode = TreeNode(name: 'Root', type: NodeType.root);
    _processedFiles = {}; // Reset processed files

    // Also track display names to avoid duplicates in the tree
    Set<String> processedDisplayNames = {};

    // Process all files from the yamlFiles map
    final List<String> filePaths = widget.yamlFiles.keys.toList()
      ..sort(); // Sort for consistent display order

    // Group files by path to create a tree structure
    final pathToNode = HashMap<String, TreeNode>();

    // Root node is already created
    pathToNode[''] = _rootNode;

    // First pass: Process hierarchical files (those with paths)
    for (String filePath in filePaths) {
      // Skip if we've already processed this file
      if (_processedFiles.contains(filePath)) continue;

      // Skip system files, we'll process them separately
      if (filePath.contains('complete_raw.yaml') ||
          filePath.contains('raw_project.yaml')) {
        continue;
      }

      // Mark as processed
      _processedFiles.add(filePath);

      // Split the path into components
      List<String> pathParts = [];

      // Special handling for archive files
      if (filePath.startsWith('archive_')) {
        // Remove the 'archive_' prefix for display
        String cleanPath = filePath.replaceFirst('archive_', '');
        pathParts = cleanPath.split('/');
      } else {
        pathParts = filePath.split('/');
      }

      // Skip empty paths and process hierarchical files (files with path components)
      if (pathParts.length > 1 ||
          (pathParts.length == 1 && !pathParts[0].endsWith('.yaml'))) {
        // Build path incrementally to create the tree
        String currentPath = '';
        TreeNode parentNode = _rootNode;

        for (int i = 0; i < pathParts.length; i++) {
          String part = pathParts[i];
          String newPath = currentPath.isEmpty ? part : '$currentPath/$part';

          // Skip if empty
          if (part.isEmpty) continue;

          // If node for this path doesn't exist yet, create it
          if (!pathToNode.containsKey(newPath)) {
            // Determine the node type based on path and position
            NodeType nodeType =
                _determineNodeType(part, i == pathParts.length - 1);

            // Create the new node
            TreeNode newNode = TreeNode(
              name: part,
              type: nodeType,
              filePath: i == pathParts.length - 1
                  ? filePath
                  : null, // Only leaf nodes have file paths
            );

            // Add to parent's children
            parentNode.children.add(newNode);

            // Store in map for future reference
            pathToNode[newPath] = newNode;
          }

          // Update parent for next iteration
          parentNode = pathToNode[newPath]!;
          currentPath = newPath;
        }
      }
    }

    // Second pass: Add top-level YAML files
    for (String filePath in filePaths) {
      // Skip non-YAML files and already processed files
      if (!filePath.endsWith('.yaml') ||
          (filePath.contains('/') && filePath.split('/').length > 1) ||
          filePath.contains('complete_raw.yaml') ||
          filePath.contains('raw_project.yaml') ||
          _processedFiles.contains(filePath)) {
        continue;
      }

      String displayName = filePath;
      if (filePath.startsWith('archive_')) {
        displayName = filePath.replaceFirst('archive_', '');
      }

      // Skip if we already processed a file with this display name
      if (processedDisplayNames.contains(displayName)) continue;

      // Mark as processed
      _processedFiles.add(filePath);
      processedDisplayNames.add(displayName);

      TreeNode fileNode = TreeNode(
        name: displayName,
        type: NodeType.file,
        filePath: filePath,
      );

      _rootNode.children.add(fileNode);
    }

    // Process nodes to ensure they're properly ordered
    _sortNodes(_rootNode);
  }

  NodeType _determineNodeType(String pathPart, bool isLeaf) {
    // Determine node type based on path part naming patterns
    if (pathPart.startsWith('id-') && isLeaf) {
      return NodeType.leaf;
    } else if (pathPart.endsWith('.yaml')) {
      return NodeType.file;
    } else if (pathPart.startsWith('component')) {
      return NodeType.component;
    } else if (pathPart == 'collections' || pathPart == 'collection') {
      return NodeType.collection;
    } else if (pathPart == 'node') {
      return NodeType.node;
    } else if (pathPart.contains('Button')) {
      return NodeType.button;
    } else if (pathPart.contains('Container')) {
      return NodeType.container;
    } else if (pathPart.contains('trigger_actions')) {
      return NodeType.trigger;
    } else if (pathPart.toUpperCase() == 'ON TAP') {
      return NodeType.action;
    } else if (pathPart == 'action') {
      return NodeType.action;
    } else if (isLeaf) {
      return NodeType.file;
    } else {
      return NodeType.folder;
    }
  }

  void _sortNodes(TreeNode node) {
    // Sort children by type and then by name
    node.children.sort((a, b) {
      // First by type
      if (a.type != b.type) {
        // Collections come first
        if (a.type == NodeType.collection) return -1;
        if (b.type == NodeType.collection) return 1;

        // Components come next
        if (a.type == NodeType.component) return -1;
        if (b.type == NodeType.component) return 1;

        // Files come last
        if (a.type == NodeType.file) return 1;
        if (b.type == NodeType.file) return -1;
      }

      // Then by name
      return a.name.compareTo(b.name);
    });

    // Recursively sort children
    for (var child in node.children) {
      _sortNodes(child);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with title
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              border: Border(
                bottom: BorderSide(color: AppTheme.dividerColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Project Files',
                  style: AppTheme.headingSmall.copyWith(fontSize: 16),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration:
                      AppTheme.statusBadgeDecoration(AppTheme.textMuted),
                  child: Text(
                    '${widget.yamlFiles.length}',
                    style: AppTheme.captionLarge.copyWith(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Tree content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _buildNodeChildren(_rootNode, 0),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNodeChildren(TreeNode node, int depth) {
    List<Widget> widgets = [];

    // Skip the root node itself, but show its children
    if (node.type != NodeType.root) {
      widgets.add(_buildNodeWidget(node, depth));
    }

    // Add children if this node is expanded
    String nodeIdentifier = '${node.type}_${node.name}';
    if (_expandedNodes.contains(nodeIdentifier) || node.type == NodeType.root) {
      for (var child in node.children) {
        widgets.addAll(_buildNodeChildren(child, depth + 1));
      }
    }

    return widgets;
  }

  Widget _buildNodeWidget(TreeNode node, int depth) {
    String nodeIdentifier = '${node.type}_${node.name}';
    bool isExpanded = _expandedNodes.contains(nodeIdentifier);
    bool isSelected = node.filePath == _selectedFilePath;
    bool hasChildren = node.children.isNotEmpty;

    // Check if this file has been validated recently
    bool isValidated = node.filePath != null &&
        widget.validationTimestamps != null &&
        widget.validationTimestamps!.containsKey(node.filePath!);

    // Get the icon based on node type
    IconData icon = _getNodeIcon(node.type);
    Color iconColor = _getNodeColor(node.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            if (hasChildren) {
              if (isExpanded) {
                _expandedNodes.remove(nodeIdentifier);
              } else {
                _expandedNodes.add(nodeIdentifier);
              }
            }

            if (node.filePath != null) {
              _selectedFilePath = node.filePath;
              if (widget.onFileSelected != null) {
                widget.onFileSelected!(node.filePath!);
              }
            }
          });
        },
        hoverColor: AppTheme.primaryColor.withOpacity(0.05),
        child: Container(
          padding: EdgeInsets.only(
            left: 12.0 + (depth * 16.0),
            right: 12.0,
            top: 6.0,
            bottom: 6.0,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withOpacity(0.1)
                : Colors.transparent,
            border: isSelected
                ? Border(
                    left: BorderSide(
                      color: AppTheme.primaryColor,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              // Expansion indicator for folders
              SizedBox(
                width: 16,
                height: 16,
                child: hasChildren
                    ? Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 16,
                        color: AppTheme.textSecondary,
                      )
                    : null,
              ),
              const SizedBox(width: 8),

              // Node icon
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppTheme.primaryColor : iconColor,
              ),
              const SizedBox(width: 8),

              // Node name and status
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        node.name,
                        style: AppTheme.bodyMedium.copyWith(
                          color: isSelected
                              ? AppTheme.primaryColor
                              : AppTheme.textPrimary,
                          fontWeight: isSelected || hasChildren
                              ? FontWeight.w600
                              : FontWeight.w400,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Status indicators
                    if (isValidated) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration:
                            AppTheme.statusBadgeDecoration(AppTheme.validColor),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 10,
                              color: AppTheme.validColor,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Valid',
                              style: AppTheme.captionSmall.copyWith(
                                color: AppTheme.validColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Child count badge for folders
                    if (hasChildren) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration:
                            AppTheme.statusBadgeDecoration(AppTheme.textMuted),
                        child: Text(
                          '${node.children.length}',
                          style: AppTheme.captionSmall.copyWith(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getNodeIcon(NodeType type) {
    switch (type) {
      case NodeType.collection:
        return Icons.folder;
      case NodeType.component:
        return Icons.web_asset;
      case NodeType.container:
        return Icons.view_compact;
      case NodeType.layout:
        return Icons.view_column;
      case NodeType.widget:
        return Icons.widgets;
      case NodeType.button:
        return Icons.smart_button;
      case NodeType.node:
        return Icons.circle;
      case NodeType.leaf:
        return Icons.description;
      case NodeType.trigger:
        return Icons.electric_bolt;
      case NodeType.action:
        return Icons.flash_on;
      case NodeType.file:
        return Icons.insert_drive_file;
      case NodeType.folder:
      case NodeType.root:
      default:
        return Icons.folder;
    }
  }

  Color _getNodeColor(NodeType type) {
    switch (type) {
      case NodeType.collection:
        return Colors.amber;
      case NodeType.component:
        return Colors.purple;
      case NodeType.container:
        return Colors.blue;
      case NodeType.widget:
        return Colors.orange;
      case NodeType.button:
        return Colors.green;
      case NodeType.trigger:
        return Colors.yellow;
      case NodeType.action:
        return Colors.pink;
      case NodeType.file:
        return AppTheme.textSecondary;
      default:
        return AppTheme.textPrimary;
    }
  }
}
