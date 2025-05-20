import 'package:flutter/material.dart';

/// Placeholder function for non-web platforms
void downloadFile(String fileName, String content, BuildContext context) {
  // No-op implementation for platforms other than web
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('File download is only available in web version'),
      backgroundColor: Colors.orange,
      duration: Duration(seconds: 3),
    ),
  );
}
