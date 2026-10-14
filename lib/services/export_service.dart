import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/note_page.dart';

/// Exports the actual enhanced pixel images, retaining diagrams and handwritten strokes.
/// PDF embeds one scan per page. Images are shared as JPEG files, one per scan.
class ExportService {
  static Future<void> sharePages(List<NotePage> pages, {required bool asPdf}) async {
    if (pages.isEmpty) throw StateError('There are no pages to export');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dir = await getTemporaryDirectory();
    if (!asPdf) {
      final files = pages.map((p) => XFile(p.enhancedPath)).toList();
      await SharePlus.instance.share(ShareParams(files: files,
        subject: 'NoteCraft scanned pages', text: 'Enhanced handwritten notes'));
      return;
    }
    final document = pw.Document(compress: true);
    for (final page in pages) {
      final data = await File(page.enhancedPath).readAsBytes();
      final photo = pw.MemoryImage(data);
      document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (context) => pw.Center(child: pw.Image(photo, fit: pw.BoxFit.contain)),
      ));
    }
    final out = File('${dir.path}/NoteCraft_$stamp.pdf');
    await out.writeAsBytes(await document.save());
    await SharePlus.instance.share(ShareParams(
      files: [XFile(out.path)],
      subject: 'NoteCraft multipage PDF',
    ));
  }
}
