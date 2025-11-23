class AIRequest {
  final String userPrompt;
  final List<String> pinnedFilePaths;
  final Map<String, String> projectFiles;

  AIRequest({
    required this.userPrompt,
    required this.pinnedFilePaths,
    required this.projectFiles,
  });
}

class ProposedChange {
  final String summary;
  final List<FileModification> modifications;

  ProposedChange({required this.summary, required this.modifications});

  factory ProposedChange.fromJson(Map<String, dynamic> json) {
    return ProposedChange(
      summary: json['summary'] ?? 'No summary provided',
      modifications: (json['modifications'] as List?)
              ?.map((e) => FileModification.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class FileModification {
  final String filePath;
  final String originalContent;
  final String newContent;
  final bool isNewFile;
  final List<String>? touchedPaths; // Optional: paths the AI claims it modified

  FileModification({
    required this.filePath,
    required this.originalContent,
    required this.newContent,
    required this.isNewFile,
    this.touchedPaths,
  });

  factory FileModification.fromJson(Map<String, dynamic> json) {
    return FileModification(
      filePath: json['filePath'] ?? '',
      originalContent: json['originalContent'] ?? '',
      newContent: json['newContent'] ?? '',
      isNewFile: json['isNewFile'] ?? false,
      touchedPaths: (json['touchedPaths'] as List?)?.map((e) => e.toString()).toList(),
    );
  }
}
