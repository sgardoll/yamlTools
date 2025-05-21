import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final List<DiffLine> diffLines = _computeDiff(originalContent, modifiedContent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with filename and controls - only show if onClose is provided
        // This avoids duplication when used inside the tree view
        if (onClose != null)
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    fileName,
                    style: TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy modified content',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: modifiedContent));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Modified content copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
        
        // Diff header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Original',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Modified',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),

        // Diff content
        Expanded(
          child: diffLines.isEmpty
              ? const Center(child: Text('No changes detected'))
              : ListView.builder(
                  itemCount: diffLines.length,
                  itemBuilder: (context, index) {
                    final diffLine = diffLines[index];
                    return _buildDiffLine(diffLine);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDiffLine(DiffLine line) {
    Color? backgroundColor;
    Widget lineContent;

    switch (line.type) {
      case DiffType.added:
        backgroundColor = Colors.green[50];
        lineContent = Row(
          children: [
            // Empty space for the original side
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.grey[300]!)),
                ),
              ),
            ),
            // Added content on the modified side
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: backgroundColor,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('+', style: TextStyle(color: Colors.green[800])),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        line.content,
                        style: TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        break;

      case DiffType.removed:
        backgroundColor = Colors.red[50];
        lineContent = Row(
          children: [
            // Removed content on the original side
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: backgroundColor,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('-', style: TextStyle(color: Colors.red[800])),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        line.content,
                        style: TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Empty space for the modified side
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: Colors.grey[300]!)),
                ),
              ),
            ),
          ],
        );
        break;

      case DiffType.unchanged:
        backgroundColor = null;
        lineContent = Row(
          children: [
            // Same content on both sides
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  line.content,
                  style: TextStyle(fontFamily: 'monospace', color: Colors.grey[700]),
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  line.content,
                  style: TextStyle(fontFamily: 'monospace', color: Colors.grey[700]),
                ),
              ),
            ),
          ],
        );
        break;
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        color: backgroundColor,
      ),
      child: lineContent,
    );
  }

  // Compute the diff between original and modified content
  List<DiffLine> _computeDiff(String original, String modified) {
    final List<DiffLine> result = [];
    
    // Split content into lines
    final List<String> originalLines = original.split('\n');
    final List<String> modifiedLines = modified.split('\n');

    // Simple implementation of diff calculation (can be improved with a better algorithm)
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
        for (int k = j + 1; k < modifiedLines.length && k < j + 5; k++) {
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
          for (int k = i + 1; k < originalLines.length && k < i + 5; k++) {
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