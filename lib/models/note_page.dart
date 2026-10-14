import 'dart:io';

/// One physical notebook page, kept as two copies:
/// [originalPath] is never overwritten; [enhancedPath] is the cleaned scan.
/// This separation prevents accidental loss of arrows, formulas and diagrams.
class NotePage {
  NotePage({required this.id, required this.originalPath, required this.enhancedPath,
    this.recognizedText = '', this.error});
  final String id;
  final String originalPath;
  final String enhancedPath;
  final String recognizedText;
  final String? error;
  File get image => File(enhancedPath);

  NotePage copyWith({String? enhancedPath, String? recognizedText, String? error}) => NotePage(
    id: id, originalPath: originalPath,
    enhancedPath: enhancedPath ?? this.enhancedPath,
    recognizedText: recognizedText ?? this.recognizedText,
    error: error,
  );
}

/// Output of either the offline keyword guide or the optional AI server.
class NoteInsight {
  const NoteInsight({required this.topic, required this.summary, required this.explanations,
    this.source = 'Offline topic guide'});
  final String topic;
  final String summary;
  final List<String> explanations;
  final String source;
}
