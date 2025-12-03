import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:yaml/yaml.dart';

import '../theme/app_theme.dart';

enum NodeType {
  root,
  aiAssistSection,
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
  final Map<String, DateTime>? aiTouchedTimestamps;

  const ModernYamlTree({
    Key? key,
    required this.yamlFiles,
    this.onFileSelected,
    this.expandedNodes,
    this.validationTimestamps,
    this.syncTimestamps,
    this.updateTimestamps,
    this.aiTouchedTimestamps,
  }) : super(key: key);

  @override
  _ModernYamlTreeState createState() => _ModernYamlTreeState();
}

class _ModernYamlTreeState extends State<ModernYamlTree> {
  late TreeNode _rootNode;
  Set<String> _expandedNodes = {};
  String? _selectedFilePath;
  int _previousUnsavedCount = 0;
  int _previousAiTouchedCount = 0;

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
    bool shouldRebuild = false;

    if (oldWidget.yamlFiles != widget.yamlFiles) {
      _extractPageNames();
      shouldRebuild = true;
    }

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
          } catch (_) {}
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

    if (rawName == 'admob.yaml') return 'AdMob';
    if (rawName == 'app-details.yaml') return 'App Details';
    if (rawName == 'app_bar.yaml') return 'App Bar';
    if (rawName == 'folders.yaml') return 'Folders';
    if (rawName == 'nav_bar.yaml') return 'Nav Bar';
    if (rawName == 'material_theme_settings.yaml') {
      return 'Material Theme Settings';
    }
    if (rawName == 'environment_settings.yaml') {
      return 'Environment Settings';
    }

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

    return syncedAt == null || updatedAt.isAfter(syncedAt);
  }

  void _buildTree() {
    _rootNode = TreeNode(name: 'Root', type: NodeType.root);

    final List<String> filePaths = widget.yamlFiles.keys
        .where((path) =>
            !path.contains('complete_raw.yaml') &&
            !path.contains('raw_project.yaml'))
        .toList()
      ..sort();

    final List<TreeNode> aiTouchedNodes = [];
    final aiTouchedEntries = widget.aiTouchedTimestamps?.entries.toList() ?? [];
    aiTouchedEntries.sort((a, b) => b.value.compareTo(a.value));

    for (final entry in aiTouchedEntries) {
      final filePath = entry.key;
      if (!widget.yamlFiles.containsKey(filePath)) continue;

      final filename = filePath.split('/').last;
      final type = _determineNodeType(filename, true);
      final friendlyName = _getFriendlyName(filename, filePath, type);
      aiTouchedNodes.add(
        TreeNode(
          name: friendlyName,
          type: type,
          filePath: filePath,
        ),
      );
    }

    if (aiTouchedNodes.isNotEmpty) {
      final aiSection = TreeNode(
        name: 'AI Assist Changes',
        type: NodeType.aiAssistSection,
        children: aiTouchedNodes,
      );
      _rootNode.children.add(aiSection);
      if (_previousAiTouchedCount == 0) {
        _expandedNodes.add('${NodeType.aiAssistSection}_AI Assist Changes');
      }
    }
    _previousAiTouchedCount = aiTouchedNodes.length;

    // Build unsaved section
    final List<TreeNode> unsavedNodes = [];
    for (final filePath in regularFilePaths) {
      if (_isUnsaved(filePath)) {
        final filename = filePath.split('/').last;
        final type = _determineNodeType(filename, true);
        final friendlyName = _getFriendlyName(filename, filePath, type);
        unsavedNodes.add(TreeNode(
          name: friendlyName,
          type: type,
          filePath: filePath,
        ));
      }
    }

    if (unsavedNodes.isNotEmpty) {
      final unsavedSection = TreeNode(
        name: 'Unsaved Files',
        type: NodeType.unsavedSection,
        children: unsavedNodes,
      );
      _rootNode.children.add(unsavedSection);
      if (_previousUnsavedCount == 0) {
        _expandedNodes.add('${NodeType.unsavedSection}_Unsaved Files');
      }
    }
    _previousUnsavedCount = unsavedNodes.length;

    final pathToNode = HashMap<String, TreeNode>();
    pathToNode[''] = _rootNode;

    bool matchesSearch(String name) {
      return _searchQuery.isEmpty || name.toLowerCase().contains(_searchQuery);
    }

    for (final filePath in regularFilePaths) {
      List<String> pathParts;
      String cleanFilePath = filePath;

      if (filePath.startsWith('archive_')) {
        cleanFilePath = filePath.replaceFirst('archive_', '');
      }
      pathParts = cleanFilePath.split('/');

      TreeNode currentNode = _rootNode;
      String currentPath = '';

      for (int i = 0; i < pathParts.length; i++) {
        String pathPart = pathParts[i];
        final isLeaf = i == pathParts.length - 1;

        if (pathPart == 'node' &&
            i > 0 &&
            pathParts[i - 1] == 'page-widget-tree-outline') {
          continue;
        }

        final nodeType = _determineNodeType(pathPart, isLeaf);
        final friendlyName = _getFriendlyName(pathPart, filePath, nodeType);

        currentPath = currentPath.isEmpty ? pathPart : '$currentPath/$pathPart';

        TreeNode? existingNode = pathToNode[currentPath];
        if (existingNode == null) {
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

        if (matchesSearch(friendlyName)) {
          _expandedNodes.add('${nodeType}_$friendlyName');
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
        if (a.type == NodeType.aiAssistSection) return -1;
        if (b.type == NodeType.aiAssistSection) return 1;
        if (a.type == NodeType.unsavedSection) return -1;
        if (b.type == NodeType.unsavedSection) return 1;
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
                    fillColor: const Color(0xFF0F172A),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(
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

    IconData icon = _getNodeIcon(node.type);
    Color iconColor = _getNodeColor(node.type);
    Color textColor = _getTextColor(node);
    final statusBadges = _buildStatusBadges(node);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (node.filePath != null) {
            widget.onFileSelected?.call(node.filePath!);
            setState(() {
              _selectedFilePath = node.filePath;
            });
          }
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
          height: 32,
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withOpacity(0.1)
                : Colors.transparent,
            border: isSelected
                ? Border.all(color: AppTheme.primaryColor.withOpacity(0.3))
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.only(left: depth * 20.0 + 10),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Center(
                    child: Icon(icon, size: 14, color: iconColor),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: AppTheme.bodyMedium.copyWith(
                      color: textColor,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (statusBadges.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: statusBadges,
                  ),
                ],
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
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getNodeIcon(NodeType type) {
    switch (type) {
      case NodeType.aiAssistSection:
        return Icons.auto_awesome;
      case NodeType.unsavedSection:
        return Icons.pending_actions;
      case NodeType.collection:
        return Icons.folder;
      case NodeType.component:
        return FontAwesomeIcons.gem;
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
      case NodeType.aiAssistSection:
        return AppTheme.primaryColor;
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
  }

  Color _getTextColor(TreeNode node) {
    if (node.type == NodeType.unsavedSection) {
      return Colors.orange;
    }
    if (node.type == NodeType.aiAssistSection) {
      return AppTheme.primaryColor;
    }
    if (node.filePath != null && _isUnsaved(node.filePath!)) {
      return Colors.orange;
    }
    return AppTheme.textPrimary;
  }

  List<Widget> _buildStatusBadges(TreeNode node) {
    if (node.filePath == null) return [];

    final filePath = node.filePath!;
    final badges = <Widget>[];
    final updateAt = widget.updateTimestamps?[filePath];
    final syncAt = widget.syncTimestamps?[filePath];
    final validationAt = widget.validationTimestamps?[filePath];
    final isUnsaved = _isUnsaved(filePath);
    final isValidated =
        validationAt != null && (updateAt == null || !validationAt.isBefore(updateAt));
    final isSynced =
        syncAt != null && (updateAt == null || !syncAt.isBefore(updateAt));
    final isAiTouched = widget.aiTouchedTimestamps?.containsKey(filePath) ?? false;

    if (isAiTouched) {
      badges.add(_buildChip(
        label: 'AI edit',
        color: AppTheme.primaryColor.withOpacity(0.15),
        borderColor: AppTheme.primaryColor,
        icon: Icons.auto_fix_high,
        textColor: AppTheme.primaryColor,
      ));
    }

    if (isUnsaved) {
      badges.add(_buildChip(
        label: 'Unsaved',
        color: Colors.orange.withOpacity(0.15),
        borderColor: Colors.orange,
        icon: Icons.warning_amber_rounded,
        textColor: Colors.orange,
      ));
    } else if (isSynced) {
      badges.add(_buildChip(
        label: 'Saved',
        color: AppTheme.successColor.withOpacity(0.15),
        borderColor: AppTheme.successColor,
        icon: Icons.check_circle,
        textColor: AppTheme.successColor,
      ));
    }

    if (isValidated) {
      badges.add(_buildChip(
        label: 'Validated',
        color: AppTheme.validColor.withOpacity(0.15),
        borderColor: AppTheme.validColor,
        icon: Icons.verified,
        textColor: AppTheme.validColor,
      ));
    }

    return badges;
  }

  Widget _buildChip({
    required String label,
    required Color color,
    required Color borderColor,
    required IconData icon,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
