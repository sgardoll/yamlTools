import 'package:flutter/material.dart';
import '../storage/preferences_manager.dart';
import 'package:intl/intl.dart';

class RecentProjectsWidget extends StatefulWidget {
  final Function(String projectId) onProjectSelected;
  final bool showHeader;
  final int? maxItems;
  final bool enableSearch;

  const RecentProjectsWidget({
    Key? key,
    required this.onProjectSelected,
    this.showHeader = true,
    this.maxItems,
    this.enableSearch = false,
  }) : super(key: key);

  @override
  _RecentProjectsWidgetState createState() => _RecentProjectsWidgetState();
}

class _RecentProjectsWidgetState extends State<RecentProjectsWidget> {
  List<Map<String, dynamic>> _recentProjects = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadRecentProjects();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentProjects() async {
    setState(() {
      _isLoading = true;
    });

    final projects = await PreferencesManager.getRecentProjects();
    projects.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

    setState(() {
      _recentProjects = projects;
      _isLoading = false;
    });
  }

  void _handleSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase().trim();
    });
  }

  List<Map<String, dynamic>> get _filteredProjects {
    if (_recentProjects.isEmpty) return [];

    final filtered = _recentProjects.where((project) {
      if (_searchQuery.isEmpty) return true;
      final name = (project['name'] ?? '').toString().toLowerCase();
      final id = (project['id'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) || id.contains(_searchQuery);
    }).toList();

    if (widget.maxItems != null && widget.maxItems! > 0 && _searchQuery.isEmpty) {
      return filtered.take(widget.maxItems!).toList();
    }

    return filtered;
  }

  String _formatTimestamp(int timestamp) {
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final formatter = DateFormat('MMM d, yyyy h:mm a');
    return formatter.format(date);
  }

  Future<void> _removeProject(String projectId) async {
    await PreferencesManager.removeRecentProject(projectId);
    _loadRecentProjects();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_recentProjects.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No recent projects',
            style: TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Projects',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await PreferencesManager.clearRecentProjects();
                    _loadRecentProjects();
                  },
                  child: const Text('Clear All'),
                ),
              ],
            ),
          ),
        if (widget.showHeader) const Divider(),
        if (widget.enableSearch)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search recent projects by name or ID',
              ),
            ),
          ),
        if (widget.enableSearch) const SizedBox(height: 8),
        if (_filteredProjects.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'No projects match your search.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredProjects.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final project = _filteredProjects[index];
              return ListTile(
                title: Text(
                  project['name'] ?? 'Unnamed Project',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'ID: ${project['id']} • ${_formatTimestamp(project['timestamp'] ?? 0)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeProject(project['id']),
                ),
                onTap: () => widget.onProjectSelected(project['id']),
              );
            },
          ),
      ],
    );
  }
}
