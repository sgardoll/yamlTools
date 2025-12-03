import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
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
  final Map<String, DateTime>? syncTimestamps;
  final Map<String, DateTime>? updateTimestamps;

  const ModernYamlTree({
    Key? key,
    required this.yamlFiles,
    this.onFileSelected,
    this.expandedNodes,
    this.validationTimestamps,
    this.syncTimestamps,
    this.updateTimestamps,
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

  final TextEditingController _searchController = TextEditingController();
  Map<String, String> _pageDisplayNames = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _extractPageNames();
    _buildTree();
    if (widget.expandedNodes != null) {
      _expandedNodes = Set.from(widget.expandedNodes!);
    }
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _buildTree();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ModernYamlTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.yamlFiles != widget.yamlFiles) {
      _extractPageNames();
      _buildTree();
    }
    if (oldWidget.expandedNodes != widget.expandedNodes) {
      if (widget.expandedNodes != null) {
        _expandedNodes = Set.from(widget.expandedNodes!);
      }
    }
  }

  void _extractPageNames() {
    _pageDisplayNames.clear();
    widget.yamlFiles.forEach((path, content) {
      String cleanPath = path;
      if (path.startsWith('archive_')) {
        cleanPath = path.replaceFirst('archive_', '');
      }

      // Look for page definition files: page/id-Scaffold_XXX/id-Scaffold_XXX.yaml
      final parts = cleanPath.split('/');
      // Expected structure: [page, id-Scaffold_XXX, id-Scaffold_XXX.yaml]
      if (parts.length >= 3 &&
          parts[0] == 'page' &&
          parts[1].startsWith('id-Scaffold')) {
        // Check if this is the main file for the page folder
        final folderName = parts[1];
        final fileName = parts.last;
        final simpleFileName = fileName.endsWith('.yaml')
            ? fileName.substring(0, fileName.length - 5)
            : fileName;

        if (folderName == simpleFileName) {
          try {
            final yaml = loadYaml(content);
            if (yaml is YamlMap && yaml['name'] != null) {
              _pageDisplayNames[folderName] = yaml['name'].toString();
            }
          } catch (e) {
            // ignore parse errors
          }
        }
      }
    });
  }

  String _getFriendlyName(String rawName, String? fullPath, NodeType type) {
    if (type == NodeType.folder &&
        rawName.startsWith('id-Scaffold') &&
        _pageDisplayNames.containsKey(rawName)) {
      final pageName = _pageDisplayNames[rawName];
      return '$pageName ($rawName)';
    }

    if (rawName == 'page-widget-tree-outline') {
      return 'Widget Tree Outline';
    }

    // Specific file mappings
    if (rawName == 'admob.yaml') return 'AdMob';
    if (rawName == 'app-details.yaml') return 'App Details';
    if (rawName == 'app_bar.yaml') return 'App Bar';
    if (rawName == 'folders.yaml') return 'Folders';
    if (rawName == 'nav_bar.yaml') return 'Nav Bar';
    if (rawName == 'material_theme_settings.yaml')
      return 'Material Theme Settings';
    if (rawName == 'environment_settings.yaml') return 'Environment Settings';

    // Widget files: id-Type_Hash.yaml -> Type (Type_Hash)
    if (type == NodeType.file || type == NodeType.leaf) {
      final nameWithoutExt = rawName.endsWith('.yaml')
          ? rawName.substring(0, rawName.length - 5)
          : rawName;
      if (nameWithoutExt.startsWith('id-')) {
        final parts = nameWithoutExt.substring(3).split('_');
        if (parts.length >= 2) {
          final widgetType = parts[0];
          return '$widgetType (${nameWithoutExt.substring(3)})';
        }
      }
    }

    return rawName;
  }

  void _buildTree() {
    _rootNode = TreeNode(name: 'Root', type: NodeType.root);
    _processedFiles = {}; // Reset processed files

    // Also track display names to avoid duplicates in the tree
    Set<String> processedDisplayNames = {};

    // Process all files from the yamlFiles map
    final List<String> filePaths = widget.yamlFiles.keys.toList()..sort();

    // Group files by path to create a tree structure
    final pathToNode = HashMap<String, TreeNode>();

    // Root node is already created
    pathToNode[''] = _rootNode;

    // Helper to check if a node matches search query
    bool matchesSearch(String name) {
      return _searchQuery.isEmpty || name.toLowerCase().contains(_searchQuery);
    }

    // Track matching nodes to ensure parents are kept
    Set<TreeNode> matchingNodes = {};

    // Temporary storage for built nodes to apply search filtering later
    // Actually, it's easier to build the full tree and then prune or just
    // only add nodes that match (and their ancestors).
    // Let's modify the build process to build full structure but with friendly names,
    // and then we can maybe filter visualization or just filter during build.

    // Given the structure, we need to handle "skipping" nodes (like 'node' folder).
    // This is easier if we process path parts carefully.

    for (String filePath in filePaths) {
      // Skip system files
      if (filePath.contains('complete_raw.yaml') ||
          filePath.contains('raw_project.yaml')) {
        continue;
      }

      List<String> pathParts = [];
      String cleanFilePath = filePath;

      if (filePath.startsWith('archive_')) {
        cleanFilePath = filePath.replaceFirst('archive_', '');
        pathParts = cleanFilePath.split('/');
      } else {
        pathParts = filePath.split('/');
      }

      TreeNode currentNode = _rootNode;
      String currentPath = '';

      // We need to look ahead/behind to handle "skipping" folders
      // For "page-widget-tree-outline/node/...", we want to skip "node".

      for (int i = 0; i < pathParts.length; i++) {
        String pathPart = pathParts[i];
        final isLeaf = (i == pathParts.length - 1);
        final originalPathPart = pathPart; // Keep raw for path reconstruction

        // Special handling: Skip 'node' folder if parent was 'page-widget-tree-outline'
        // To do this, we need to know the PREVIOUS part was 'page-widget-tree-outline'.
        if (pathPart == 'node' &&
            i > 0 &&
            pathParts[i - 1] == 'page-widget-tree-outline') {
          // Skip this part, don't update currentPath, just continue loop
          // But we need to make sure the NEXT iteration continues from the SAME currentNode
          continue;
        }

        // Configuration Files handling
        // If we have "configuration_files" folder or similar, we might want to rename it.
        // Assuming "configuration_files" is literal in the path.

        String friendlyName = _getFriendlyName(
          pathPart,
          filePath,
          _determineNodeType(pathPart, isLeaf),
        );

        // Update current path key for the map (using raw names to keep uniqueness in map)
        // But if we skipped a part, we effectively collapsed the structure.
        // The map key should arguably represent the logical structure.
        // Let's append the raw part to currentPath unless skipped.
        currentPath =
            currentPath.isEmpty ? originalPathPart : '$currentPath/$originalPathPart';

        // Check if node exists
        TreeNode? existingNode = pathToNode[currentPath];
        if (existingNode == null) {
          final nodeType = _determineNodeType(pathPart, isLeaf);
          final newNode = TreeNode(
            name: friendlyName,
            type: nodeType,
            filePath: isLeaf ? filePath : null,
          );

          currentNode.children.add(newNode);
          pathToNode[currentPath] = newNode;
          currentNode = newNode;
        } else {
          currentNode = existingNode;
        }
      }
    }

    // After building tree, apply search filtering if needed
    if (_searchQuery.isNotEmpty) {
      _filterTree(_rootNode);
    }

    // Process nodes to ensure they're properly ordered
    _sortNodes(_rootNode);
  }

  // Returns true if this node or any child matches the search
  bool _filterTree(TreeNode node) {
    if (node.children.isEmpty) {
      // Leaf node: check name
      return node.name.toLowerCase().contains(_searchQuery);
    }

    // Folder node: check children
    // Remove children that don't match
    node.children.removeWhere((child) => !_filterTree(child));

    // If folder itself matches, we might want to keep it even if children don't?
    // Usually in file trees, if folder matches, show it. If child matches, show folder.
    bool selfMatches = node.name.toLowerCase().contains(_searchQuery);
    bool hasMatchingChildren = node.children.isNotEmpty;

    if (hasMatchingChildren) {
      // If we have matching children, we should expand this node
      String nodeIdentifier = '${node.type}_${node.name}';
      _expandedNodes.add(nodeIdentifier);
    }

    return selfMatches || hasMatchingChildren;
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
          // Header with title and search
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              border: Border(
                bottom: BorderSide(color: AppTheme.dividerColor, width: 1),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.settings,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Project Configuration',
                      style: AppTheme.headingSmall.copyWith(fontSize: 16),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
                const SizedBox(height: 12),
                // Search bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search files...',
                    hintStyle: TextStyle(
                      color: AppTheme.textSecondary.withOpacity(0.5),
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    filled: true,
                    fillColor: Color(0xFF0F172A), // Darker background for input
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
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

    // Check if this file was recently synced (updated on FlutterFlow)
    bool isSynced = node.filePath != null &&
        widget.syncTimestamps != null &&
        widget.syncTimestamps!.containsKey(node.filePath!);

    // Check if this file has local edits that are not synced yet
    bool isEditedNotSynced = false;
    if (node.filePath != null && widget.updateTimestamps != null) {
      final updatedAt = widget.updateTimestamps![node.filePath!];
      if (updatedAt != null) {
        final syncedAt = widget.syncTimestamps != null
            ? widget.syncTimestamps![node.filePath!]
            : null;
        // Consider dirty when there's no sync, or last local update is newer than last sync
        isEditedNotSynced = syncedAt == null || updatedAt.isAfter(syncedAt);
      }
    }

    // Check if this is an AI-generated file
    bool isAIGenerated = node.filePath?.startsWith('ai_generated_') ?? false;

    // Get the icon based on node type
    IconData icon = _getNodeIcon(node.type);
    Color iconColor = _getNodeColor(node.type);

    // Special styling for AI-generated files
    if (isAIGenerated) {
      iconColor = Color(0xFFEC4899); // Pink color for AI files
      icon = Icons.auto_awesome; // AI icon
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (hasChildren) {
            setState(() {
              if (isExpanded) {
                _expandedNodes.remove(nodeIdentifier);
              } else {
                _expandedNodes.add(nodeIdentifier);
              }
            });
          }

          // Always call file selection for leaf nodes or when clicking on files
          if (node.filePath != null) {
            widget.onFileSelected?.call(node.filePath!);
          }
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: isSelected
                ? Border.all(color: AppTheme.primaryColor.withOpacity(0.3))
                : null,
          ),
          child: Row(
            children: [
              // Indentation
              SizedBox(width: depth * 16.0),

              // Expand/collapse indicator for folders
              if (hasChildren)
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 16,
                  color: AppTheme.textSecondary,
                )
              else
                SizedBox(width: 16),

              const SizedBox(width: 4),

              // File/folder icon
              Icon(
                icon,
                size: 16,
                color: iconColor,
              ),

              const SizedBox(width: 8),

              // File/folder name
              Expanded(
                child: Text(
                  node.name,
                  style: AppTheme.bodyMedium.copyWith(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.textPrimary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Status indicators
              ..._buildStatusIndicators(
                isSynced: isSynced,
                isAIGenerated: isAIGenerated,
                isValidated: isValidated,
                isEditedNotSynced: isEditedNotSynced,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStatusIndicators({
    required bool isSynced,
    required bool isAIGenerated,
    required bool isValidated,
    required bool isEditedNotSynced,
  }) {
    final List<Widget> indicators = [];

    if (isSynced) {
      indicators.add(
        Container(
          margin: const EdgeInsets.only(left: 4),
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: AppTheme.successColor,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check,
            size: 10,
            color: Colors.white,
          ),
        ),
      );
    }

    if (isAIGenerated) {
      indicators.add(
        Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFEC4899).withOpacity(0.2),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFFEC4899), width: 1),
          ),
          child: const Text(
            'AI',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: Color(0xFFEC4899),
            ),
          ),
        ),
      );
    } else if (isEditedNotSynced) {
      // Show an explicit "Unsaved" badge when there are local edits not yet synced
      indicators.add(
        Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.orange, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.pending_actions, size: 10, color: Colors.orange),
              SizedBox(width: 3),
              Text(
                'Unsaved',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (isValidated) {
      indicators.add(
        Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.validColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: AppTheme.validColor, width: 1),
          ),
          child: Icon(
            Icons.verified,
            size: 10,
            color: AppTheme.validColor,
          ),
        ),
      );
    }

    return indicators;
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
