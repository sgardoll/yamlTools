import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppHeader extends StatelessWidget {
  final VoidCallback? onNewProject;
  final VoidCallback? onReload;
  final VoidCallback? onAIAssist;
  final bool showOnlyNewProject;

  const AppHeader({
    Key? key,
    this.onNewProject,
    this.onReload,
    this.onAIAssist,
    this.showOnlyNewProject = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        final actionButtons = _buildActionButtons();

        return Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                AppTheme.cardColor,
                AppTheme.primaryColor,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withOpacity(0.2),
                offset: Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleSection(),
                    if (actionButtons.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: actionButtons,
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    _buildTitleSection(),
                    const Spacer(),
                    if (actionButtons.isNotEmpty)
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: actionButtons,
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildTitleSection() {
    return Row(
      mainAxisSize: MainAxisSize.min,
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
                    color: AppTheme.secondaryColor,
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
    );
  }

  List<Widget> _buildActionButtons() {
    final buttons = <Widget>[];

    // Show "New Project" only when a callback is provided
    if (onNewProject != null) {
      buttons.add(
        _buildHeaderButton(
          onPressed: onNewProject,
          icon: Icons.add,
          label: 'New Project',
          isPrimary: true,
        ),
      );
    }

    if (!showOnlyNewProject) {
      buttons
        ..add(_buildHeaderButton(
          onPressed: onReload,
          icon: Icons.refresh,
          label: 'Reload',
          backgroundColor: const Color(0xFF22C55E),
        ))
        ..add(_buildHeaderButton(
          onPressed: onAIAssist,
          icon: Icons.auto_awesome,
          label: 'AI Assist',
          backgroundColor: const Color(0xFFEC4899),
        ));
    }

    return buttons;
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
          foregroundColor: isPrimary ? AppTheme.primaryColor : Colors.white,
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
              return AppTheme.primaryColor;
            }
            return Colors.white;
          }),
          iconColor: MaterialStateProperty.resolveWith<Color>((states) {
            if (isPrimary) {
              return AppTheme.primaryColor;
            }
            return Colors.white;
          }),
        ),
      ),
    );
  }
}
