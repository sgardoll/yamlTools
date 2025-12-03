import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import '../theme/app_theme.dart';
import 'dart:collection';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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

  // Returns extracted widget type and friendly name
  Map<String, String> _parseWidgetInfo(String rawName, NodeType type) {
    String friendlyName = rawName;
    String widgetType = '';

    if (type == NodeType.folder &&
        rawName.startsWith('id-Scaffold') &&
        _pageDisplayNames.containsKey(rawName)) {
      final pageName = _pageDisplayNames[rawName];
      friendlyName = '$pageName'; // Show just name, debug ID handled elsewhere if needed
      widgetType = 'Page';
    } else if (rawName == 'page-widget-tree-outline') {
      friendlyName = 'Widget Tree Outline';
      widgetType = 'Folder';
    } else if (type == NodeType.file || type == NodeType.leaf) {
      final nameWithoutExt = rawName.endsWith('.yaml')
          ? rawName.substring(0, rawName.length - 5)
          : rawName;
      if (nameWithoutExt.startsWith('id-')) {
        final parts = nameWithoutExt.substring(3).split('_');
        if (parts.length >= 2) {
          widgetType = parts[0];
          friendlyName = '$widgetType'; // Just show Type, user can see ID in properties
          // If the YAML has a 'name' property, we should ideally use that.
          // But that requires parsing. We'll rely on type for now or name if parsed later.
        }
      }
    }

    // Fallbacks
    if (widgetType.isEmpty) {
      if (rawName.contains('Button')) widgetType = 'Button';
      else if (rawName.contains('Column')) widgetType = 'Column';
      else if (rawName.contains('Row')) widgetType = 'Row';
      else if (rawName.contains('Stack')) widgetType = 'Stack';
      else if (rawName.contains('Image')) widgetType = 'Image';
      else widgetType = 'Unknown';
    }

    return {'name': friendlyName, 'type': widgetType};
  }

  Map<String, dynamic> _parseNodeStatus(String filePath) {
    final content = widget.yamlFiles[filePath];
    if (content == null) return {};

    try {
      final yaml = loadYaml(content);
      if (yaml is YamlMap) {
        bool isVisible = true;
        if (yaml.containsKey('visibility')) {
          final vis = yaml['visibility'];
          if (vis == false || vis == 'false') {
            isVisible = false;
          }
        }

        bool hasBindings = _checkBindings(yaml);
        bool hasBackendQuery = yaml.containsKey('backend_query');

        // Try to get a better name if available
        String? customName;
        if (yaml['name'] != null) {
          customName = yaml['name'].toString();
        } else if (yaml['identifier'] != null && yaml['identifier'] is YamlMap) {
          customName = yaml['identifier']['name']?.toString();
        }

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

    for (String filePath in filePaths) {
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

      for (int i = 0; i < pathParts.length; i++) {
        String pathPart = pathParts[i];
        final isLeaf = (i == pathParts.length - 1);
        final originalPathPart = pathPart;

        if (pathPart == 'node' &&
            i > 0 &&
            pathParts[i - 1] == 'page-widget-tree-outline') {
          continue;
        }

        NodeType nodeType = _determineNodeType(pathPart, isLeaf);

        // Basic info
        var widgetInfo = _parseWidgetInfo(pathPart, nodeType);
        String friendlyName = widgetInfo['name']!;
        String widgetType = widgetInfo['type']!;

        // Parse detailed status if leaf/file
        bool hasBindings = false;
        bool isVisible = true;
        bool hasBackendQuery = false;

        if (isLeaf || nodeType == NodeType.file || nodeType == NodeType.leaf) {
           final status = _parseNodeStatus(filePath);
           if (status['isVisible'] != null) isVisible = status['isVisible'];
           if (status['hasBindings'] != null) hasBindings = status['hasBindings'];
           if (status['hasBackendQuery'] != null) hasBackendQuery = status['hasBackendQuery'];
           if (status['customName'] != null) {
             friendlyName = status['customName'];
             // Keep widgetType from ID parsing as it's useful for icon
           }
        }

        currentPath = currentPath.isEmpty ? originalPathPart : '$currentPath/$originalPathPart';

        TreeNode? existingNode = pathToNode[currentPath];
        if (existingNode == null) {
          final newNode = TreeNode(
            name: friendlyName,
            type: nodeType,
            filePath: isLeaf ? filePath : null,
            widgetType: widgetType,
            hasBindings: hasBindings,
            isVisible: isVisible,
            hasBackendQuery: hasBackendQuery,
          );

          currentNode.children.add(newNode);
          pathToNode[currentPath] = newNode;
          currentNode = newNode;
        } else {
          currentNode = existingNode;
        }
      }
    }

    if (_searchQuery.isNotEmpty) {
      _filterTree(_rootNode);
    }

    _sortNodes(_rootNode);
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
                    fillColor: Color(0xFF0F172A),
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

  Color _getNodeColor(TreeNode node) {
    // Specific colors based on type
    if (node.widgetType == 'Button' || node.type == NodeType.component) {
       return Color(0xFF6366F1); // Indigo/Purple
    }
    if (node.widgetType == 'Page') return Colors.grey;
    if (node.type == NodeType.action) return Colors.pinkAccent;
    if (node.type == NodeType.trigger) return Colors.yellow;

    return Colors.grey; // Structural elements are grey
  }

  Color _getTextColor(TreeNode node) {
    if (node.widgetType == 'Button' || node.type == NodeType.component || node.name.startsWith('TellUs')) {
       return Color(0xFF818CF8); // Lighter Indigo
    }
    return AppTheme.textPrimary;
  }
}
