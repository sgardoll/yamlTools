import 'package:flutter/material.dart';

/// Fallback placeholder for platforms where HTML iframe embeds are unavailable.
Widget buildYouTubeEmbed({
  required String videoUrl,
  double aspectRatio = 16 / 9,
  BorderRadius? borderRadius,
}) {
  return ClipRRect(
    borderRadius: borderRadius ?? BorderRadius.circular(12),
    child: Container(
      color: Colors.black12,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_circle_fill, size: 48, color: Colors.grey.shade700),
          const SizedBox(height: 8),
          const Text(
            'Video preview available on web builds',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          SelectableText(
            videoUrl,
            textAlign: TextAlign.center,
            style: const TextStyle(
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    ),
  );
}
