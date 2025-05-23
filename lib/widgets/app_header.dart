import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppHeader extends StatelessWidget {
  final VoidCallback? onNewProject;
  final VoidCallback? onRecent;
  final VoidCallback? onReload;
  final VoidCallback? onAIAssist;

  const AppHeader({
    Key? key,
    this.onNewProject,
    this.onRecent,
    this.onReload,
    this.onAIAssist,
  }) : super(key: key);

  // Consistent button style for all buttons
  ButtonStyle _getButtonStyle({Color? backgroundColor}) {
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor ?? AppTheme.surfaceColor,
      foregroundColor: Colors.white,
      textStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      ),
      elevation: 0,
      shadowColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        border: Border(
          bottom: BorderSide(color: AppTheme.dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Logo and Title
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: AppTheme.primaryColor,
                ),
                child: const Center(
                  child: Icon(
                    Icons.code,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'FlutterFlow ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: 'YAML Editor AI',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Spacer(),

          // Action Buttons
          Row(
            children: [
              // New Project Button
              ElevatedButton.icon(
                onPressed: onNewProject,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Project'),
                style: _getButtonStyle(backgroundColor: AppTheme.primaryColor),
              ),
              const SizedBox(width: 8),

              // Recent Button
              ElevatedButton.icon(
                onPressed: onRecent,
                icon: const Icon(Icons.history, size: 16),
                label: const Text('Recent'),
                style: _getButtonStyle(),
              ),
              const SizedBox(width: 8),

              // Reload Button
              ElevatedButton.icon(
                onPressed: onReload,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reload'),
                style: _getButtonStyle(backgroundColor: AppTheme.successColor),
              ),
              const SizedBox(width: 8),

              // AI Assist Button
              ElevatedButton.icon(
                onPressed: onAIAssist,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('AI Assist'),
                style: _getButtonStyle(backgroundColor: Colors.orange),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
