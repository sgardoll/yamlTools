import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class DiffViewWidget extends StatelessWidget {
  final String originalContent;
  final String modifiedContent;
  final String fileName;
  final Function()? onClose;

  const DiffViewWidget({
    Key? key,
    required this.originalContent,
    required this.modifiedContent,
    required this.fileName,
    this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Generate the diff
    final List<DiffLine> diffLines =
        _computeDiff(originalContent, modifiedContent);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with filename and controls
          if (onClose != null)
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                border: Border(
                  bottom: BorderSide(color: AppTheme.dividerColor),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.compare_arrows,
                      color: AppTheme.primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Changes in $fileName',
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy modified content',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: modifiedContent));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                              'Modified content copied to clipboard'),
                          duration: const Duration(seconds: 2),
                          backgroundColor: AppTheme.successColor,
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),

          // Diff content with improved readability
          Expanded(
            child: diffLines.isEmpty
                ? Center(
                    child: Text(
                      'No changes detected',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: diffLines.length,
                    itemBuilder: (context, index) {
                      final diffLine = diffLines[index];
                      return _buildDiffLine(diffLine, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffLine(DiffLine line, int lineNumber) {
    Color? backgroundColor;
    Color? textColor;
    String prefix;
    IconData? icon;
    Color? iconColor;

    switch (line.type) {
      case DiffType.added:
        backgroundColor = Colors.green[50];
        textColor = Colors.green[900];
        prefix = '+';
        icon = Icons.add;
        iconColor = Colors.green[700];
        break;

      case DiffType.removed:
        backgroundColor = Colors.red[50];
        textColor = Colors.red[900];
        prefix = '-';
        icon = Icons.remove;
        iconColor = Colors.red[700];
        break;

      case DiffType.unchanged:
        backgroundColor = Colors.transparent;
        textColor = AppTheme.textSecondary;
        prefix = ' ';
        icon = null;
        iconColor = null;
        break;
    }

    // Skip displaying too many unchanged lines to reduce clutter
    if (line.type == DiffType.unchanged) {
      // Show a limited number of context lines around changes
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              child: Text(
                '${lineNumber + 1}',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textMuted,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 20,
              child: Text(
                prefix,
                style: AppTheme.bodyMedium.copyWith(
                  color: textColor,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                line.content.isEmpty ? ' ' : line.content,
                style: AppTheme.monospace.copyWith(
                  color: textColor,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // For added/removed lines, use more prominent styling
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: iconColor?.withOpacity(0.3) ?? Colors.transparent,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              child: Text(
                '${lineNumber + 1}',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textMuted,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 12),
            if (icon != null)
              Icon(
                icon,
                size: 16,
                color: iconColor,
              )
            else
              Container(width: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                line.content.isEmpty ? ' ' : line.content,
                style: AppTheme.monospace.copyWith(
                  color: textColor,
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: line.type != DiffType.unchanged
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Compute the diff between original and modified content
  List<DiffLine> _computeDiff(String original, String modified) {
    final List<DiffLine> result = [];

    // Split content into lines
    final List<String> originalLines = original.split('\n');
    final List<String> modifiedLines = modified.split('\n');

    // Simple implementation of diff calculation
    int i = 0, j = 0;

    while (i < originalLines.length || j < modifiedLines.length) {
      // If we've reached the end of original content, all remaining lines are additions
      if (i >= originalLines.length) {
        while (j < modifiedLines.length) {
          result.add(DiffLine(modifiedLines[j], DiffType.added));
          j++;
        }
        break;
      }

      // If we've reached the end of modified content, all remaining lines are removals
      if (j >= modifiedLines.length) {
        while (i < originalLines.length) {
          result.add(DiffLine(originalLines[i], DiffType.removed));
          i++;
        }
        break;
      }

      // If lines are the same, add as unchanged and advance both counters
      if (originalLines[i] == modifiedLines[j]) {
        result.add(DiffLine(originalLines[i], DiffType.unchanged));
        i++;
        j++;
      } else {
        // Look ahead to see if this is just an addition or removal
        bool found = false;

        // Check if current original line appears later in modified content
        for (int k = j + 1; k < modifiedLines.length && k < j + 3; k++) {
          if (originalLines[i] == modifiedLines[k]) {
            // Lines between j and k are additions
            for (int l = j; l < k; l++) {
              result.add(DiffLine(modifiedLines[l], DiffType.added));
            }
            j = k;
            found = true;
            break;
          }
        }

        if (!found) {
          // Check if current modified line appears later in original content
          for (int k = i + 1; k < originalLines.length && k < i + 3; k++) {
            if (originalLines[k] == modifiedLines[j]) {
              // Lines between i and k are removals
              for (int l = i; l < k; l++) {
                result.add(DiffLine(originalLines[l], DiffType.removed));
              }
              i = k;
              found = true;
              break;
            }
          }
        }

        // If we couldn't find a match looking ahead, treat as a modified line (remove and add)
        if (!found) {
          result.add(DiffLine(originalLines[i], DiffType.removed));
          result.add(DiffLine(modifiedLines[j], DiffType.added));
          i++;
          j++;
        }
      }
    }

    return result;
  }
}

// Model for a line in the diff view
class DiffLine {
  final String content;
  final DiffType type;

  DiffLine(this.content, this.type);
}

// Types of differences
enum DiffType {
  added,
  removed,
  unchanged,
}
