// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

final Set<String> _registeredViewTypes = <String>{};

Widget buildYouTubeEmbed({
  required String videoUrl,
  double aspectRatio = 16 / 9,
  BorderRadius? borderRadius,
}) {
  final videoId = _extractVideoId(videoUrl);
  final viewType = 'youtube-embed-$videoId';
  final embedUrl =
      'https://www.youtube.com/embed/$videoId?rel=0&modestbranding=1&playsinline=1';

  if (!_registeredViewTypes.contains(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int _) {
        final iframe = html.IFrameElement()
          ..src = embedUrl
          ..style.border = '0'
          ..allowFullscreen = true
          ..allow = 'accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture';
        return iframe;
      },
    );
    _registeredViewTypes.add(viewType);
  }

  return ClipRRect(
    borderRadius: borderRadius ?? BorderRadius.circular(12),
    child: AspectRatio(
      aspectRatio: aspectRatio,
      child: HtmlElementView(viewType: viewType),
    ),
  );
}

String _extractVideoId(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.queryParameters.containsKey('v')) {
      return uri.queryParameters['v']!;
    }
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      return segments.last;
    }
  } catch (_) {
    // fall through to default
  }
  return 'dQw4w9WgXcQ'; // harmless default
}
