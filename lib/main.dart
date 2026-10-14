import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/note_page.dart';
import 'services/ai_service.dart';
import 'services/enhancement.dart';
import 'services/export_service.dart';
import 'services/note_insights.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NoteCraftApp());
}

/// Design system: these colors are reflected in the scan / learn / settings UI.
class Ink {
  static const navy = Color(0xFF101F32);
  static const teal = Color(0xFF087D83);
  static const aqua = Color(0xFFDCF4F0);
  static const paper = Color(0xFFF6F7F4);
  static const muted = Color(0xFF6F8190);
}

class NoteCraftApp extends StatelessWidget {
  const NoteCraftApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NoteCraft AI', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: Ink.paper,
      colorScheme: ColorScheme.fromSeed(seedColor: Ink.teal, surface: Ink.paper),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 30, color: Ink.navy, fontWeight: FontWeight.w800, letterSpacing: -1),
        titleLarge: TextStyle(fontSize: 20, color: Ink.navy, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(fontSize: 15, color: Ink.navy, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(fontSize: 13, color: Ink.navy),
      ),
    ),
    home: const NoteCraftHome(),
  );
}

class NoteCraftHome extends StatefulWidget {
  const NoteCraftHome({super.key});
  @override
  State<NoteCraftHome> createState() => _NoteCraftHomeState();
}

class _NoteCraftHomeState extends State<NoteCraftHome> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _ocr = TextRecognizer(script: TextRecognitionScript.latin);
  final TextEditingController _serverController = TextEditingController();
  final Map<String, int> _rotations = {}; // Rotation per page, maintained between editing operations.
  final List<NotePage> _pages = [];
  ScanStyle _style = ScanStyle.paper;
  int _selected = 0;
  int _tab = 0;
  bool _busy = false;
  String _activity = '';
  String _endpoint = '';
  NoteInsight? _aiInsight;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _ocr.close();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    // Restore page paths after an app restart; original files live in app storage.
    final prefs = await SharedPreferences.getInstance();
    _endpoint = prefs.getString('ai_endpoint') ?? '';
    _serverController.text = _endpoint;
    final rows = prefs.getStringList('scan_pages') ?? [];
    for (final raw in rows) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final p = NotePage(id: j['id'] as String,
          originalPath: j['original'] as String,
          enhancedPath: j['enhanced'] as String,
          recognizedText: (j['text'] ?? '') as String);
        if (await File(p.originalPath).exists() && await File(p.enhancedPath).exists()) {
          _pages.add(p);
          _rotations[p.id] = (j['rotation'] ?? 0) as int;
        }
      } catch (_) { /* Ignore one corrupted entry; keep the rest of the document. */ }
    }
    if (mounted) setState(() {});
    // Android may stop the app while the system gallery is open; recover picked files.
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.files != null && lost.files!.isNotEmpty) await _addFiles(lost.files!);
    } catch (_) { /* Recovery is best effort only. */ }
  }

  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('scan_pages', _pages.map((p) => jsonEncode({
      'id': p.id, 'original': p.originalPath,
      'enhanced': p.enhancedPath, 'text': p.recognizedText, 'rotation': _rotations[p.id] ?? 0,
    })).toList());
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message),
      behavior: SnackBarBehavior.floating));
  }

  /// Camera entry point: uses Android's native camera intent via image_picker.
  Future<void> _camera() async {
    if (_busy) return;
    try {
      final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 95);
      if (photo != null) await _addFiles([photo]);
    } catch (e) { _message('Camera unavailable: $e'); }
  }

  /// Gallery entry point: select many pages in one action.
  Future<void> _gallery() async {
    if (_busy) return;
    try {
      final photos = await _picker.pickMultiImage(imageQuality: 95);
      if (photos.isNotEmpty) await _addFiles(photos);
    } catch (e) { _message('Could not import pictures: $e'); }
  }

  Future<void> _addFiles(List<XFile> files) async {
    setState(() { _busy = true; _activity = 'Preparing ${files.length} page(s)…'; });
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (var i = 0; i < files.length; i++) {
        if (mounted) setState(() => _activity = 'Cleaning page ${i + 1} of ${files.length}…');
        final id = '${DateTime.now().microsecondsSinceEpoch}_$i';
        final original = File('${dir.path}/note_${id}_original.jpg');
        final enhanced = File('${dir.path}/note_${id}_clean.jpg');
        final input = await files[i].readAsBytes();
        await original.writeAsBytes(input);
        // Enhancement runs on an isolate so the progress indicator remains responsive.
        final output = await ScanEnhancement.process(input, _style);
        await enhanced.writeAsBytes(output);
        var text = '';
        try {
          // OCR is for topic hints and AI explanation; the exported page remains an image.
          final recognized = await _ocr.processImage(InputImage.fromFilePath(enhanced.path));
          text = recognized.text;
        } catch (_) { /* Handwritten formulae or offline ML models may not OCR reliably. */ }
        if (!mounted) return;
        setState(() {
          _rotations[id] = 0;
          _pages.add(NotePage(id: id, originalPath: original.path,
            enhancedPath: enhanced.path, recognizedText: text));
          _selected = _pages.length - 1;
          _aiInsight = null;
        });
        await _saveSession();
      }
    } catch (e) { _message('Scanning failed: $e');
    } finally {
      if (mounted) setState(() { _busy = false; _activity = ''; });
    }
  }

  Future<void> _applyStyle(ScanStyle style, {int rotation = 0}) async {
    _style = style;
    if (_pages.isEmpty || _busy) { setState(() {}); return; }
    setState(() { _busy = true; _activity = 'Refining handwriting and diagrams…'; });
    try {
      final old = _pages[_selected];
      final input = await File(old.originalPath).readAsBytes();
      final nextRotation = ((_rotations[old.id] ?? 0) + rotation) % 360;
      final output = await ScanEnhancement.process(input, style, rotation: nextRotation);
      _rotations[old.id] = nextRotation;
      await File(old.enhancedPath).writeAsBytes(output);
      // Flutter caches decoded FileImage pixels by path; evict after overwriting.
      await FileImage(File(old.enhancedPath)).evict();
      await _saveSession();
      if (mounted) setState(() {});
    } catch (e) { _message('Could not apply filter: $e');
    } finally { if (mounted) setState(() { _busy = false; _activity = ''; }); }
  }

  Future<void> _removeSelected() async {
    if (_pages.isEmpty || _busy) return;
    final item = _pages.removeAt(_selected);
    _rotations.remove(item.id);
    try { await File(item.originalPath).delete(); } catch (_) {}
    try { await File(item.enhancedPath).delete(); } catch (_) {}
    setState(() { _selected = _pages.isEmpty ? 0 : _selected.clamp(0, _pages.length - 1).toInt(); _aiInsight = null; });
    await _saveSession();
  }

  Future<void> _editOcr() async {
    if (_pages.isEmpty) return;
    final current = _pages[_selected];
    final controller = TextEditingController(text: current.recognizedText);
    final edit = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Correct recognized text'),
      content: SizedBox(width: 450, child: TextField(controller: controller,
        maxLines: 9, minLines: 5,
        decoration: const InputDecoration(hintText: 'Type corrected words or equations…', border: OutlineInputBorder()))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Save'))],
    ));
    if (edit == null || !mounted) return;
    setState(() { _pages[_selected] = current.copyWith(recognizedText: edit); _aiInsight = null; });
    await _saveSession();
  }

  Future<void> _export(bool asPdf) async {
    if (_busy || _pages.isEmpty) return;
    setState(() { _busy = true; _activity = asPdf ? 'Preparing PDF…' : 'Preparing images…'; });
    try { await ExportService.sharePages(_pages, asPdf: asPdf);
    } catch (e) { _message('Export failed: $e');
    } finally { if (mounted) setState(() { _busy = false; _activity = ''; }); }
  }

  Future<void> _explainWithAI() async {
    if (_busy || _pages.isEmpty) return;
    if (_endpoint.trim().isEmpty) {
      _message('Add an HTTPS AI endpoint under Settings first.'); return;
    }
    final consent = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Send notes to your AI server?'),
      content: const Text('Up to 3 reduced-size scan images and OCR text will be uploaded to your configured server for explanations. Do not send private notes to a server you do not trust.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue'))],
    ));
    if (consent != true || !mounted) return;
    setState(() { _busy = true; _activity = 'Understanding your notes…'; });
    try {
      final insight = await AiService.explain(_endpoint, _pages);
      if (mounted) setState(() => _aiInsight = insight);
    } catch (e) { _message('AI explanation unavailable: $e');
    } finally { if (mounted) setState(() { _busy = false; _activity = ''; }); }
  }

  Widget _pill(IconData icon, String label, VoidCallback onTap, {bool selected = false}) =>
      InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(color: selected ? Ink.teal : Colors.white,
            border: Border.all(color: selected ? Ink.teal : const Color(0xFFE0E7E7)), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: selected ? Colors.white : Ink.navy), const SizedBox(width: 7),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: selected ? Colors.white : Ink.navy)),
          ])));

  Widget _sectionHeader(String eyebrow, String title, {String? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(eyebrow.toUpperCase(), style: const TextStyle(color: Ink.teal, fontWeight: FontWeight.w800,
      letterSpacing: 1.7, fontSize: 10)), const SizedBox(height: 4),
      Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (trailing != null) Text(trailing, style: const TextStyle(color: Ink.muted, fontSize: 12))]),
    ]));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Ink.paper, toolbarHeight: 69, automaticallyImplyLeading: false,
        title: Row(children: [Container(width: 39, height: 39,
          decoration: BoxDecoration(color: Ink.navy, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.draw_rounded, color: Colors.white, size: 22)),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NoteCraft', style: TextStyle(fontSize: 20, color: Ink.navy, fontWeight: FontWeight.w900, letterSpacing: -0.7)),
            Text('STUDY STUDIO', style: TextStyle(fontSize: 9, color: Ink.muted, fontWeight: FontWeight.w800, letterSpacing: 2)),
          ]), const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(color: Ink.aqua, borderRadius: BorderRadius.circular(30)),
            child: Row(children: [const Icon(Icons.shield_outlined, color: Ink.teal, size: 14), const SizedBox(width: 5),
              Text(_endpoint.isEmpty ? 'Offline' : 'Hybrid', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Ink.teal))])),
        ]),
      ),
      body: SafeArea(child: Column(children: [
        // The top navigation switches between scans, topic explanations, and settings.
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          child: Row(children: [
            for (final entry in [(Icons.document_scanner_outlined, 'Scan'), (Icons.auto_stories_outlined, 'Insights'), (Icons.tune_outlined, 'Settings')].indexed)
              Expanded(child: Padding(padding: EdgeInsets.only(right: entry.$1 == 2 ? 0 : 7),
                child: _navItem(entry.$2.$1, entry.$2.$2, entry.$1))),
          ])),
        Expanded(child: Stack(children: [
          if (_tab == 0) _scanTab() else if (_tab == 1) _insightsTab() else _settingsTab(),
          if (_busy) Positioned(left: 0, right: 0, top: 0,
            child: LinearProgressIndicator(minHeight: 3, color: Ink.teal,
              backgroundColor: Ink.aqua, semanticsLabel: _activity)),
        ])),
        if (_busy) Container(color: Ink.aqua, width: double.infinity, padding: const EdgeInsets.all(10),
          child: Text(_activity, textAlign: TextAlign.center,
            style: const TextStyle(color: Ink.teal, fontWeight: FontWeight.bold, fontSize: 12))),
      ])),
    );
  }

  Widget _navItem(IconData icon, String title, int index) {
    final active = _tab == index;
    return InkWell(onTap: () => setState(() => _tab = index), borderRadius: BorderRadius.circular(12),
      child: Container(padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(color: active ? Ink.navy : Colors.white,
          borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 17, color: active ? Colors.white : Ink.muted), const SizedBox(width: 6),
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12,
            color: active ? Colors.white : Ink.muted)),
        ])));
  }

  Widget _scanTab() => ListView(padding: const EdgeInsets.fromLTRB(18, 19, 18, 24), children: [
    _sectionHeader('01 / Capture + refine', 'Your note workspace', trailing: '${_pages.length} page${_pages.length == 1 ? '' : 's'}'),
    // Primary action buttons: native camera + multi-select photo gallery.
    Row(children: [
      Expanded(child: FilledButton.icon(onPressed: _busy ? null : _camera,
        icon: const Icon(Icons.photo_camera_outlined, size: 19), label: const Text('Take photo'),
        style: FilledButton.styleFrom(backgroundColor: Ink.teal,
          padding: const EdgeInsets.symmetric(vertical: 17), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))))),
      const SizedBox(width: 9),
      Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _gallery,
        icon: const Icon(Icons.collections_outlined, size: 19), label: const Text('Add pages'),
        style: OutlinedButton.styleFrom(foregroundColor: Ink.navy,
          padding: const EdgeInsets.symmetric(vertical: 17),
          side: const BorderSide(color: Color(0xFFDCE4E3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))))),
    ]),
    const SizedBox(height: 18),
    // Document viewport: photograph or helpful instructional empty state.
    Container(height: 350, decoration: BoxDecoration(color: const Color(0xFFE7EBE8),
      borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFDDE4E1))),
      child: _pages.isEmpty ? _emptyScan() : Stack(fit: StackFit.expand, children: [
        Padding(padding: const EdgeInsets.all(16),
          child: ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.file(
            _pages[_selected].image,
            key: ValueKey('${_pages[_selected].id}_${_style.name}_${_busy}'),
            fit: BoxFit.contain, errorBuilder: (ctx, err, stack) => const Center(child: Text('Image unavailable'))))),
        Positioned(top: 12, left: 12, child: _cornerTag('PAGE ${_selected + 1} / ${_pages.length}')),
        Positioned(bottom: 11, right: 11, child: _cornerTag('HANDWRITING PRESERVED')),
      ])),
    const SizedBox(height: 17),
    if (_pages.isNotEmpty) ...[
      _sectionHeader('Edit your scan', 'Enhancement styles'),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final style in ScanStyle.values) ...[
          _pill(style == ScanStyle.color ? Icons.palette_outlined : style == ScanStyle.mono
              ? Icons.contrast_outlined : style == ScanStyle.original ? Icons.image_outlined : Icons.auto_fix_high,
              style.label, () => _applyStyle(style), selected: _style == style),
          const SizedBox(width: 7),
        ]
      ])),
      const SizedBox(height: 15),
      Wrap(spacing: 7, runSpacing: 7, children: [
        _pill(Icons.rotate_right, 'Rotate 90°', () => _applyStyle(_style, rotation: 90)),
        _pill(Icons.delete_outline, 'Remove', _removeSelected),
        _pill(Icons.spellcheck, 'Correct OCR', _editOcr),
      ]),
      const SizedBox(height: 17),
      // Page strip: tap any page to preview and edit; long press to reorder via ReorderableListView.
      _sectionHeader('Document pages', 'Page organizer', trailing: 'Long-press to reorder'),
      SizedBox(height: 93, child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal, itemCount: _pages.length,
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) newIndex--;
          setState(() {
            final selectedId = _pages[_selected].id;
            final page = _pages.removeAt(oldIndex); _pages.insert(newIndex, page);
            _selected = _pages.indexWhere((p) => p.id == selectedId);
          });
          _saveSession();
        },
        itemBuilder: (ctx, i) => GestureDetector(key: ValueKey(_pages[i].id),
          onTap: () => setState(() => _selected = i),
          child: Container(width: 68, height: 90, margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.all(4), decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _selected == i ? Ink.teal : const Color(0xFFDDE6E2), width: _selected == i ? 2 : 1)),
            child: Column(children: [Expanded(child: Image.file(_pages[i].image, fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Icon(Icons.image_not_supported_outlined))),
              Text('${i + 1}', style: const TextStyle(color: Ink.navy, fontSize: 10, fontWeight: FontWeight.bold))])),
        ),
      )),
      const SizedBox(height: 17),
      _sectionHeader('03 / Save + share', 'Choose output format'),
      Row(children: [
        Expanded(child: _exportButton('Export PDF', 'All pages', Icons.picture_as_pdf_outlined, () => _export(true))),
        const SizedBox(width: 10),
        Expanded(child: _exportButton('Export images', 'JPEG files', Icons.photo_library_outlined, () => _export(false))),
      ]),
    ] else ...[
      const SizedBox(height: 17),
      const Row(children: [Icon(Icons.check_circle_outline, size: 18, color: Ink.teal), SizedBox(width: 7),
        Expanded(child: Text('Keeps formulas, handwriting and diagrams in their original positions.',
          style: TextStyle(color: Ink.muted, fontSize: 12)))]),
    ],
  ]);

  Widget _emptyScan() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 80, height: 80, decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.document_scanner_outlined, size: 40, color: Ink.teal)),
    const SizedBox(height: 18),
    const Text('Your next great idea starts here',
      style: TextStyle(color: Ink.navy, fontWeight: FontWeight.w800, fontSize: 16)),
    const SizedBox(height: 7),
    const Padding(padding: EdgeInsets.symmetric(horizontal: 24),
      child: Text('Capture handwritten notes, equations, diagrams, or entire notebook pages.',
        textAlign: TextAlign.center, style: TextStyle(color: Ink.muted, fontSize: 12, height: 1.5))),
    const SizedBox(height: 16),
    const Icon(Icons.arrow_upward_rounded, color: Ink.teal, size: 24),
  ]);

  Widget _cornerTag(String label) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(color: Ink.navy.withValues(alpha: .82), borderRadius: BorderRadius.circular(5)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w800)));

  Widget _exportButton(String title, String caption, IconData icon, VoidCallback onTap) =>
    InkWell(onTap: _busy ? null : onTap, borderRadius: BorderRadius.circular(15),
      child: Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFDDE7E3))),
        child: Row(children: [Icon(icon, color: Ink.teal, size: 27), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Ink.navy, fontWeight: FontWeight.w800, fontSize: 12)),
            Text(caption, style: const TextStyle(color: Ink.muted, fontSize: 10)),
          ]))])));

  Widget _insightsTab() {
    final local = NoteInsights.fromText(_pages.map((e) => e.recognizedText).join('\n'));
    final insight = _aiInsight ?? local;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 22, 18, 30), children: [
      _sectionHeader('02 / Understand', 'Your study insights'),
      _infoCard(icon: Icons.auto_awesome_outlined, title: insight.topic, subtitle: insight.source,
        child: Text(insight.summary, style: const TextStyle(color: Ink.navy, height: 1.5, fontSize: 13))),
      const SizedBox(height: 13),
      _infoCard(icon: Icons.lightbulb_outline, title: 'Explanations + next steps',
        subtitle: _aiInsight == null ? 'Topic-based offline guidance' : 'AI-assisted learning',
        child: Column(children: [for (final tip in insight.explanations) Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.arrow_right_alt_rounded, color: Ink.teal, size: 20),
            const SizedBox(width: 8), Expanded(child: Text(tip,
              style: const TextStyle(color: Ink.navy, fontSize: 12, height: 1.5))),
          ]))])),
      const SizedBox(height: 13),
      FilledButton.icon(onPressed: _pages.isEmpty || _busy ? null : _explainWithAI,
        icon: const Icon(Icons.psychology_alt_outlined), label: const Text('Explain with AI (optional)'),
        style: FilledButton.styleFrom(backgroundColor: Ink.navy, padding: const EdgeInsets.symmetric(vertical: 16))),
      const SizedBox(height: 8),
      const Text('Offline mode only gives general topic guides. The optional server can analyze your notes and diagrams in more detail.',
        style: TextStyle(fontSize: 11, color: Ink.muted, height: 1.5)),
      const SizedBox(height: 21),
      _sectionHeader('Editable transcription', 'Recognized words'),
      if (_pages.isEmpty) const Text('Add a photo to see OCR text.', style: TextStyle(color: Ink.muted))
      else for (var i = 0; i < _pages.length; i++) Container(
        margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text('PAGE ${i + 1}', style: const TextStyle(color: Ink.teal, fontWeight: FontWeight.bold, fontSize: 10)),
            const Spacer(), TextButton(onPressed: () { setState(() => _selected = i); _editOcr(); },
              child: const Text('Correct text'))]),
          Text(_pages[i].recognizedText.isEmpty ? 'No readable text detected; diagrams are still preserved in the scan.'
              : _pages[i].recognizedText,
            maxLines: 10, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Ink.navy, height: 1.5, fontSize: 12)),
        ])),
    ]);
  }

  Widget _infoCard({required IconData icon, required String title, required String subtitle, required Widget child}) =>
    Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE2E9E6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: Ink.aqua,
          borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Ink.teal)),
          const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Ink.navy)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Ink.muted)),
          ]))]), const SizedBox(height: 16), child,
      ]));

  Widget _settingsTab() {
    return ListView(padding: const EdgeInsets.fromLTRB(18, 22, 18, 25), children: [
      _sectionHeader('03 / Customize', 'App settings'),
      _infoCard(icon: Icons.lock_outline, title: 'Private by default',
        subtitle: 'Scans stay on this phone',
        child: const Text('Camera, enhancement, OCR, storage, and PDF/JPEG export work locally. Notes leave the phone only when you explicitly approve an optional AI request.',
          style: TextStyle(color: Ink.navy, height: 1.5))),
      const SizedBox(height: 14),
      _infoCard(icon: Icons.hub_outlined, title: 'Optional AI backend',
        subtitle: 'Requires a trusted HTTPS server',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _serverController, autocorrect: false, keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'https://your-server.com/explain',
              helperText: 'Never insert an OpenAI API key here.', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: FilledButton(
            onPressed: () async {
              final url = _serverController.text.trim();
              if (url.isNotEmpty && !(Uri.tryParse(url)?.hasScheme == true && url.startsWith('https://'))) {
                _message('Please enter an HTTPS URL.'); return;
              }
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('ai_endpoint', url);
              if (mounted) setState(() => _endpoint = url);
              _message('AI connection setting saved.');
            }, child: const Text('Save endpoint'))),
        ])),
      const SizedBox(height: 14),
      _infoCard(icon: Icons.edit_note_outlined, title: 'About the enhanced handwriting',
        subtitle: 'Honest scanning, not fabricated ink',
        child: const Text('The filters clean pixels and preserve the original strokes and drawing layout. This prototype does not yet recreate illegible writing, automatically straighten perspective, or intelligently redraw diagrams. Check the result before sharing.',
          style: TextStyle(color: Ink.navy, height: 1.5))),
      const SizedBox(height: 14),
      const Text('NoteCraft AI • Source-editable Flutter prototype • Version 1.0',
        textAlign: TextAlign.center, style: TextStyle(color: Ink.muted, fontSize: 11)),
    ]);
  }
}
