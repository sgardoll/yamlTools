import 'package:flutter/material.dart';
import '../storage/preferences_manager.dart';
import 'package:intl/intl.dart';

class RecentProjectsWidget extends StatefulWidget {
  final Function(String projectId) onProjectSelected;
  final bool showHeader;

  const RecentProjectsWidget({
    Key? key,
    required this.onProjectSelected,
    this.showHeader = true,
  }) : super(key: key);

  @override
  _RecentProjectsWidgetState createState() => _RecentProjectsWidgetState();
}

class _RecentProjectsWidgetState extends State<RecentProjectsWidget> {
  List<Map<String, dynamic>> _recentProjects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecentProjects();
  }

  Future<void> _loadRecentProjects() async {
    setState(() {
      _isLoading = true;
    });

    final projects = await PreferencesManager.getRecentProjects();

    setState(() {
      _recentProjects = projects;
      _isLoading = false;
    });
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
        Expanded(
          child: ListView.builder(
            itemCount: _recentProjects.length,
            itemBuilder: (context, index) {
              final project = _recentProjects[index];
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
        ),
      ],
    );
  }
}
