import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppHeader extends StatelessWidget {
  final VoidCallback? onNewProject;
  final VoidCallback? onRecent;
  final VoidCallback? onReload;
  final VoidCallback? onAIAssist;
  final bool showOnlyNewProject;

  const AppHeader({
    Key? key,
    this.onNewProject,
    this.onRecent,
    this.onReload,
    this.onAIAssist,
    this.showOnlyNewProject = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF4F46E5), // Indigo-600
            Color(0xFF6366F1), // Indigo-500
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo and Title
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF1F2937),
                      Color(0xFF111827),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      offset: const Offset(0, 2),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(
                          Icons.code,
                          color: Color(0xFF4F46E5),
                          size: 20,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              RichText(
                text: const TextSpan(children: [
                  TextSpan(
                      text: 'FlutterFlow ',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.5)),
                  TextSpan(
                      text: 'YAML Tools',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                          color: Colors.white70,
                          letterSpacing: -0.5))
                ]),
              ),
            ],
          ),

          const Spacer(),

          // Action Buttons
          Row(
            children: [
              // New Project Button (Primary)
              _buildHeaderButton(
                onPressed: onNewProject,
                icon: Icons.add,
                label: 'New Project',
                isPrimary: true,
              ),
              if (!showOnlyNewProject) ...[
                const SizedBox(width: 8),

                // Recent Button
                _buildHeaderButton(
                  onPressed: onRecent,
                  icon: Icons.history,
                  label: 'Recent',
                  backgroundColor: Colors.white.withOpacity(0.1),
                ),
                const SizedBox(width: 8),

                // Reload Button (Success Green)
                _buildHeaderButton(
                  onPressed: onReload,
                  icon: Icons.refresh,
                  label: 'Reload',
                  backgroundColor: Color(0xFF22C55E),
                ),
                const SizedBox(width: 8),

                // AI Assist Button (Orange/Pink)
                _buildHeaderButton(
                  onPressed: onAIAssist,
                  icon: Icons.auto_awesome,
                  label: 'AI Assist',
                  backgroundColor: Color(0xFFEC4899),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    bool isPrimary = false,
    Color? backgroundColor,
  }) {
    return Container(
      height: 36,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? Colors.white
              : backgroundColor ?? Colors.white.withOpacity(0.15),
          foregroundColor: isPrimary ? Color(0xFF4F46E5) : Colors.white,
          elevation: isPrimary ? 2 : 0,
          shadowColor:
              isPrimary ? Colors.black.withOpacity(0.1) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: isPrimary
                ? BorderSide.none
                : BorderSide(color: Colors.white.withOpacity(0.3), width: 1),
          ),
          minimumSize: Size(0, 36),
        ).copyWith(
          foregroundColor: MaterialStateProperty.resolveWith<Color>((states) {
            if (isPrimary) {
              return Color(0xFF4F46E5);
            }
            return Colors.white;
          }),
          iconColor: MaterialStateProperty.resolveWith<Color>((states) {
            if (isPrimary) {
              return Color(0xFF4F46E5);
            }
            return Colors.white;
          }),
        ),
      ),
    );
  }
}
