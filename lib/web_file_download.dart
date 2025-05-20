import 'dart:html' as html;
import 'package:flutter/material.dart';

/// Downloads a file on web platform
void downloadFile(String fileName, String content, BuildContext context) {
  try {
    // Create a Blob containing the file content
    final blob = html.Blob([content], 'text/yaml');

    // Create a URL for the Blob
    final url = html.Url.createObjectUrlFromBlob(blob);

    // Create a link element and trigger download
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';

    html.document.body!.children.add(anchor);

    // Trigger the download by programmatically clicking the link
    anchor.click();

    // Clean up
    html.document.body!.children.remove(anchor);
    html.Url.revokeObjectUrl(url);

    print(
        'DEBUG: Downloaded file "$fileName" with content length: ${content.length}');

    // Show a success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$fileName downloaded (${content.length} chars)'),
        duration: Duration(seconds: 2),
      ),
    );
  } catch (e) {
    print('DEBUG: Error during web download: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error downloading file: $e'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }
}
