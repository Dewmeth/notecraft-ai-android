import '../models/note_page.dart';

/// Fully offline, transparent topic guide; this is not generative AI.
/// The advanced AI button in the interface calls a user-configured backend.
class NoteInsights {
  static NoteInsight fromText(String recognized) {
    final text = recognized.toLowerCase();
    final categories = <String, List<String>>{
      'Mathematics': ['integral', 'derivative', 'matrix', 'theorem', 'sin', 'cos', 'equation', 'algebra', 'function'],
      'Physics': ['force', 'velocity', 'acceleration', 'energy', 'momentum', 'newton', 'thermodynamic', 'pressure'],
      'Chemistry': ['mole', 'atom', 'electron', 'reaction', 'acid', 'base', 'bond', 'oxidation', 'chemical'],
      'Biology': ['cell', 'dna', 'mitosis', 'enzyme', 'organism', 'protein', 'tissue', 'photosynthesis'],
      'Engineering': ['circuit', 'voltage', 'stress', 'strain', 'torque', 'resistance', 'beam', 'current', 'heat transfer'],
      'Computer science': ['algorithm', 'function', 'python', 'database', 'array', 'variable', 'class', 'binary'],
      'History': ['century', 'empire', 'revolution', 'treaty', 'war', 'dynasty', 'independence'],
    };
    var topic = 'General study notes';
    var topScore = 0;
    for (final item in categories.entries) {
      final score = item.value.where(text.contains).length;
      if (score > topScore) { topScore = score; topic = item.key; }
    }
    if (recognized.trim().isEmpty) {
      return const NoteInsight(topic: 'Unrecognized handwriting',
        summary: 'No readable text was detected. Your scan still preserves the original diagrams and handwriting.',
        explanations: ['Try brighter lighting and a photo taken directly above the page.',
          'Handwriting recognition can miss cursive, symbols and mathematical expressions.',
          'You can still export the cleaned pages without OCR.']);
    }
    final guides = <String, List<String>>{
      'Mathematics': ['Check the assumptions and definitions before applying each formula.',
        'Try one worked example, then verify by substitution or dimensional consistency.'],
      'Physics': ['Identify the system, variables, forces and conservation laws.',
        'Write units next to each equation and confirm the result is physically reasonable.'],
      'Chemistry': ['Balance chemical equations and verify the conservation of atoms.',
        'Distinguish between molecular formulas, mixtures and reaction mechanisms.'],
      'Biology': ['Connect each term to its role within the larger biological process.',
        'A labelled diagram often clarifies structure and function.'],
      'Engineering': ['Record units, boundary conditions and modeling assumptions.',
        'Check whether the formula applies to the material, geometry and operating conditions.'],
      'Computer science': ['Trace the algorithm using a small input to understand each step.',
        'Check edge cases, time complexity and variable types.'],
      'History': ['Separate causes, important dates, events and consequences.',
        'Compare multiple accounts before treating an interpretation as a fact.'],
      'General study notes': ['Write down the main question answered by the notes.',
        'Highlight definitions and explain each key idea in your own words.'],
    };
    return NoteInsight(topic: topic,
      summary: 'Detected $topic from ${recognized.trim().split(RegExp(r'\s+')).length} OCR words. This classification is a rough offline guide.',
      explanations: guides[topic] ?? guides['General study notes']!);
  }
}
