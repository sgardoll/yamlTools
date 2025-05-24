import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ProjectHeader extends StatelessWidget {
  final String projectName;
  final String viewMode;
  final Function(String) onViewModeChanged;

  const ProjectHeader({
    Key? key,
    required this.projectName,
    required this.viewMode,
    required this.onViewModeChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Color(0xFF1E293B), // Slate-800
        border: Border(
          bottom: BorderSide(color: Color(0xFF334155), width: 1), // Slate-700
        ),
      ),
      child: Row(
        children: [
          // Project Icon and Name
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color:
                      Color(0xFF3B82F6).withOpacity(0.1), // Blue with opacity
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Color(0xFF3B82F6).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.folder_outlined,
                  color: Color(0xFF3B82F6), // Blue-500
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Project:',
                style: TextStyle(
                  color: Color(0xFF94A3B8), // Slate-400
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints: BoxConstraints(maxWidth: 300),
                child: Text(
                  projectName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.25,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const Spacer(),

          // View Mode Selection
          Row(
            children: [
              Text(
                'View Mode:',
                style: TextStyle(
                  color: Color(0xFF94A3B8), // Slate-400
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),

              // Toggle buttons with improved styling
              Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Color(0xFF0F172A), // Slate-900
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Color(0xFF334155), // Slate-700
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Edited Files Button
                    _buildViewModeButton(
                      label: 'Edited Files',
                      isActive: viewMode == 'edited_files',
                      onTap: () => onViewModeChanged('edited_files'),
                    ),

                    // Tree View Button
                    _buildViewModeButton(
                      label: 'Tree View',
                      isActive: viewMode == 'tree_view',
                      onTap: () => onViewModeChanged('tree_view'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color:
                isActive ? Color(0xFF3B82F6) : Colors.transparent, // Blue-500
            borderRadius: BorderRadius.circular(6),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Color(0xFF3B82F6).withOpacity(0.2),
                      offset: Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive
                  ? Colors.white
                  : Color(
                      0xFF94A3B8), // Explicit white for active, slate-400 for inactive
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
              letterSpacing: -0.25,
            ),
          ),
        ),
      ),
    );
  }
}
