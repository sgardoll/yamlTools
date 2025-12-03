import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import '../theme/app_theme.dart';
import 'dart:collection';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

enum NodeType {
  root,
  unsavedSection,
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

  // New fields for enhanced visualization
  final String? widgetType;
  final bool hasBindings;
  final bool isVisible;
  final bool hasBackendQuery;

  TreeNode({
    required this.name,
    required this.type,
    this.filePath,
    List<TreeNode>? children,
    this.widgetType,
    this.hasBindings = false,
    this.isVisible = true,
    this.hasBackendQuery = false,
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

  // Track previous count to auto-expand only when new unsaved files appear
  int _previousUnsavedCount = 0;

  final TextEditingController _searchController = TextEditingController();
  Map<String, String> _pageDisplayNames = {};
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();
  Map<String, String> _pageDisplayNames = {};
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();
  Map<String, String> _pageDisplayNames = {};
  String _searchQuery = '';
  bool _unsavedSectionExpanded = true;

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
    bool shouldRebuild = false;

    if (oldWidget.yamlFiles != widget.yamlFiles) {
      _extractPageNames();
      shouldRebuild = true;
    }

    // Also rebuild if timestamps change, as this affects the unsaved section
    if (oldWidget.updateTimestamps != widget.updateTimestamps ||
        oldWidget.syncTimestamps != widget.syncTimestamps) {
      shouldRebuild = true;
    }

    if (shouldRebuild) {
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

  bool _isUnsaved(String filePath) {
    if (widget.updateTimestamps == null) return false;

    final updatedAt = widget.updateTimestamps![filePath];
    if (updatedAt == null) return false;

    final syncedAt = widget.syncTimestamps != null
        ? widget.syncTimestamps![filePath]
        : null;

    // Consider dirty when there's no sync, or last local update is newer than last sync
    return syncedAt == null || updatedAt.isAfter(syncedAt);
  }

  void _buildTree() {
    _rootNode = TreeNode(name: 'Root', type: NodeType.root);

      final parts = cleanPath.split('/');
      if (parts.length >= 3 &&
          parts[0] == 'page' &&
          parts[1].startsWith('id-Scaffold')) {
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

    // Process all files from the yamlFiles map
    final List<String> filePaths = widget.yamlFiles.keys.toList()..sort();

    // 1. Build Unsaved Section
    List<TreeNode> unsavedNodes = [];
    for (String filePath in filePaths) {
      // Skip system files
      if (filePath.contains('complete_raw.yaml') ||
          filePath.contains('raw_project.yaml')) {
        continue;
      }

      if (_isUnsaved(filePath)) {
        String filename = filePath.split('/').last;
        NodeType type = _determineNodeType(filename, true);
        String friendlyName = _getFriendlyName(filename, filePath, type);

        unsavedNodes.add(TreeNode(
          name: friendlyName,
          type: type,
          filePath: filePath,
        ));
      }
    }

    if (unsavedNodes.isNotEmpty) {
      // Create unsaved section node
      final unsavedSection = TreeNode(
        name: 'Unsaved Files',
        type: NodeType.unsavedSection,
        children: unsavedNodes,
      );

      _rootNode.children.add(unsavedSection);

      // Auto-expand if first time appearing
      if (_previousUnsavedCount == 0) {
        _expandedNodes.add('${NodeType.unsavedSection}_Unsaved Files');
      }
    }

    _previousUnsavedCount = unsavedNodes.length;

    // 2. Build Regular Tree
    // Group files by path to create a tree structure
    final pathToNode = HashMap<String, TreeNode>();

        return {
          'isVisible': isVisible,
          'hasBindings': hasBindings,
          'hasBackendQuery': hasBackendQuery,
          'customName': customName,
        };
      }
    } catch (e) {
      // ignore
    }
    return {};
  }

  bool _checkBindings(dynamic node) {
    if (node is YamlMap) {
      if (node.containsKey('inputValue')) return true;
      for (var key in node.keys) {
        if (_checkBindings(node[key])) return true;
      }
    } else if (node is YamlList) {
      for (var item in node) {
        if (_checkBindings(item)) return true;
      }
    }
    return false;
  }

  void _buildTree() {
    _rootNode = TreeNode(name: 'Root', type: NodeType.root);
    _processedFiles = {};

    final List<String> filePaths = widget.yamlFiles.keys.toList()..sort();
    final pathToNode = HashMap<String, TreeNode>();
    pathToNode[''] = _rootNode;

    // Helper to check if a node matches search query
    bool matchesSearch(String name) {
      return _searchQuery.isEmpty || name.toLowerCase().contains(_searchQuery);
    }

    // Track matching nodes to ensure parents are kept
    Set<TreeNode> matchingNodes = {};

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

  bool _filterTree(TreeNode node) {
    if (node.children.isEmpty) {
      return node.name.toLowerCase().contains(_searchQuery);
    }
    node.children.removeWhere((child) => !_filterTree(child));
    bool selfMatches = node.name.toLowerCase().contains(_searchQuery);
    bool hasMatchingChildren = node.children.isNotEmpty;
    if (hasMatchingChildren) {
      String nodeIdentifier = '${node.type}_${node.name}';
      _expandedNodes.add(nodeIdentifier);
    }
    return selfMatches || hasMatchingChildren;
  }

  bool _filterTree(TreeNode node) {
    if (node.children.isEmpty) {
      return node.name.toLowerCase().contains(_searchQuery);
    }
    node.children.removeWhere((child) => !_filterTree(child));
    bool selfMatches = node.name.toLowerCase().contains(_searchQuery);
    bool hasMatchingChildren = node.children.isNotEmpty;
    if (hasMatchingChildren) {
      String nodeIdentifier = '${node.type}_${node.name}';
      _expandedNodes.add(nodeIdentifier);
    }
    return selfMatches || hasMatchingChildren;
  }

  NodeType _determineNodeType(String pathPart, bool isLeaf) {
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
    node.children.sort((a, b) {
      if (a.type != b.type) {
        // Unsaved Section comes first
        if (a.type == NodeType.unsavedSection) return -1;
        if (b.type == NodeType.unsavedSection) return 1;

        // Collections come next
        if (a.type == NodeType.collection) return -1;
        if (b.type == NodeType.collection) return 1;
        if (a.type == NodeType.component) return -1;
        if (b.type == NodeType.component) return 1;
        if (a.type == NodeType.file) return 1;
        if (b.type == NodeType.file) return -1;
      }
      return a.name.compareTo(b.name);
    });
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

  Widget _buildUnsavedSection() {
    final unsavedFiles = widget.yamlFiles.keys.where(_isFileUnsaved).toList();

    if (unsavedFiles.isEmpty) {
      return SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.05),
        border: Border(bottom: BorderSide(color: Colors.orange.withOpacity(0.2))),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () {
               setState(() {
                 _unsavedSectionExpanded = !_unsavedSectionExpanded;
               });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(
                    'Unsaved Files (${unsavedFiles.length})',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _unsavedSectionExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: Colors.orange,
                  )
                ],
              ),
            ),
          ),

          // List
          if (_unsavedSectionExpanded)
             ...unsavedFiles.map((filePath) {
               // Determine icon and name simply
               String name = filePath.split('/').last;
               // Try to find the tree node for better name?
               // Creating a temporary node might be expensive if logic is complex.
               // We'll parse quickly or just show path.
               // Let's stick to simple filename for now, or match tree node logic if possible.
               // We can re-use _parseWidgetInfo logic partially.

               return InkWell(
                 onTap: () => widget.onFileSelected?.call(filePath),
                 child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    color: filePath == _selectedFilePath
                        ? Colors.orange.withOpacity(0.1)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        const SizedBox(width: 24), // Indent to match header text
                        Icon(Icons.insert_drive_file, size: 14, color: Colors.orange.withOpacity(0.7)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              color: filePath == _selectedFilePath ? Colors.orange : AppTheme.textPrimary,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                 ),
               );
             }).toList(),

          if (_unsavedSectionExpanded)
             const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<Widget> _buildNodeChildren(TreeNode node, int depth) {
    List<Widget> widgets = [];
    if (node.type != NodeType.root) {
      widgets.add(_buildNodeWidget(node, depth));
    }

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
    bool isUnsaved = node.filePath != null && _isFileUnsaved(node.filePath!);

    IconData icon = _getNodeIcon(node);
    Color iconColor = _getNodeColor(node);
    Color textColor = _getTextColor(node);

    // Indentation and Lines
    // We create a Stack for the lines
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
            // If leaf, select it
            if (node.filePath != null) {
                widget.onFileSelected?.call(node.filePath!);
            }
            // Also toggle expansion if it has children
            if (hasChildren) {
                setState(() {
                    if (isExpanded) {
                        _expandedNodes.remove(nodeIdentifier);
                    } else {
                        _expandedNodes.add(nodeIdentifier);
                    }
                });
            }
        },
        child: Container(
          height: 32, // Fixed height for consistent lines
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withOpacity(0.1)
                : Colors.transparent,
             border: isSelected
                ? Border.all(color: AppTheme.primaryColor.withOpacity(0.3))
                : null,
          ),
          child: Stack(
            children: [
              // Vertical Guide Lines
              ...List.generate(depth, (index) {
                return Positioned(
                  left: index * 20.0 + 10, // Center of the 20px indent
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: Container(
                    color: Colors.grey.withOpacity(0.2),
                  ),
                );
              }),

              // Content
              Padding(
                padding: EdgeInsets.only(left: depth * 20.0 + 10), // Indent content
                child: Row(
                  children: [
                    // Node Icon
                    SizedBox(width: 24, child: Center(child: Icon(icon, size: 14, color: iconColor))),
                    const SizedBox(width: 8),

                    // Name
                    Expanded(
                      child: Text(
                        node.name,
                        style: AppTheme.bodyMedium.copyWith(
                          color: textColor,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Status Icons (Link, Eye, Database)
                    if (node.hasBindings) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.link, size: 12, color: Colors.tealAccent), // Link
                    ],
                    if (node.hasBackendQuery) ...[
                      const SizedBox(width: 4),
                      Icon(FontAwesomeIcons.coins, size: 10, color: Colors.amber), // Database/Coin
                    ],
                    // Visibility: If detected or explicitly false
                    if (!node.isVisible) ...[
                       const SizedBox(width: 4),
                       Icon(FontAwesomeIcons.eyeSlash, size: 10, color: Colors.grey),
                    ] else if (node.hasBindings && node.isVisible) ...[
                       // Only show eye if bound? Or just if present? Design shows Eye on 'If'.
                       // I'll show eye if specifically flagged
                       const SizedBox(width: 4),
                       Icon(FontAwesomeIcons.eye, size: 10, color: Colors.grey),
                    ],

                    const SizedBox(width: 8),

                    // Hover Actions (Add, Expand) - Always show for now
                    // Add Button
                    if (hasChildren || node.type == NodeType.layout || node.widgetType == 'Column')
                      InkWell(
                        onTap: () {
                           // Placeholder for Add Widget
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(content: Text('Add Widget to ${node.name} not implemented')),
                           );
                        },
                        child: Icon(Icons.add_box_outlined, size: 14, color: Colors.grey),
                      ),

                    const SizedBox(width: 8),

                    // Expand Arrow (Right aligned)
                    if (hasChildren)
                      InkWell(
                        onTap: () {
                           setState(() {
                              if (isExpanded) {
                                  _expandedNodes.remove(nodeIdentifier);
                              } else {
                                  _expandedNodes.add(nodeIdentifier);
                              }
                           });
                        },
                        child: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                      )
                    else
                      SizedBox(width: 16),

                     const SizedBox(width: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getNodeIcon(TreeNode node) {
    if (node.widgetType != null) {
      switch (node.widgetType) {
        case 'Page': return Icons.phone_android;
        case 'Column': return FontAwesomeIcons.tableColumns; // Vertical layout
        case 'Row': return FontAwesomeIcons.tableCells; // Horizontal layout
        case 'Stack': return Icons.layers;
        case 'Text': return Icons.text_fields;
        case 'Image': return Icons.image;
        case 'Button': return FontAwesomeIcons.gem; // Diamond as requested
        case 'Container': return Icons.check_box_outline_blank;
        case 'If': return FontAwesomeIcons.codeBranch;
        case 'Else': return FontAwesomeIcons.codeBranch;
        case 'ListView': return Icons.list;
        case 'TextField': return Icons.input;
      }
    }

    // Fallback to type
    switch (node.type) {
      case NodeType.collection: return Icons.folder;
      case NodeType.component: return FontAwesomeIcons.gem;
      case NodeType.button: return FontAwesomeIcons.gem;
      case NodeType.trigger: return Icons.electric_bolt;
      case NodeType.action: return Icons.flash_on;
      default: return Icons.insert_drive_file;
    }
  }

  IconData _getNodeIcon(NodeType type) {
    switch (type) {
      case NodeType.unsavedSection:
        return Icons.pending_actions;
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
    if (node.widgetType == 'Page') return Colors.grey;
    if (node.type == NodeType.action) return Colors.pinkAccent;
    if (node.type == NodeType.trigger) return Colors.yellow;

    return Colors.grey; // Structural elements are grey
  }

  Color _getNodeColor(NodeType type) {
    switch (type) {
      case NodeType.unsavedSection:
        return Colors.orange;
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
    return AppTheme.textPrimary;
  }
}
