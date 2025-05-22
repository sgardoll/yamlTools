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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        border: Border(
          bottom: BorderSide(color: AppTheme.dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Project Icon and Name
          Row(
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                color: AppTheme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Project:',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                projectName,
                style: AppTheme.headingSmall,
              ),
            ],
          ),

          const Spacer(),

          // View Mode Selection
          Row(
            children: [
              Text(
                'View Mode:',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),

              // Toggle buttons
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(8),
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
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppTheme.textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
