import 'package:flutter/material.dart';
import 'youtube_embed_stub.dart'
    if (dart.library.html) 'youtube_embed_web.dart' as impl;

class YouTubeEmbed extends StatelessWidget {
  const YouTubeEmbed({
    Key? key,
    required this.videoUrl,
    this.aspectRatio = 16 / 9,
    this.borderRadius,
  }) : super(key: key);

  final String videoUrl;
  final double aspectRatio;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return impl.buildYouTubeEmbed(
      videoUrl: videoUrl,
      aspectRatio: aspectRatio,
      borderRadius: borderRadius,
    );
  }
}
