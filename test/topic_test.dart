import 'package:flutter_test/flutter_test.dart';
import 'package:notecraft_ai/services/note_insights.dart';

void main() {
  test('physics terms are classified and have tips', () {
    final insight = NoteInsights.fromText('Force mass acceleration momentum energy');
    expect(insight.topic, 'Physics');
    expect(insight.explanations, isNotEmpty);
  });
  test('empty handwriting OCR is handled carefully', () {
    final insight = NoteInsights.fromText('   ');
    expect(insight.topic, 'Unrecognized handwriting');
  });
}
