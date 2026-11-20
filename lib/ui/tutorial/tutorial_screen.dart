import 'package:material_ui/material_ui.dart';

import '../../data/storage.dart';
import '../theme.dart';
import 'tutorial_content.dart';

/// Großes Tutorial: Übersicht der Kapitel (gelesene sind abgehakt).
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  late final List<TutChapter> _chapters = buildTutorial();

  Future<void> _open(int i) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TutorialChapterScreen(chapters: _chapters, index: i)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final seen = Store.tutorialSeen;
    final done = _chapters.where((c) => seen.contains(c.id)).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Tutorial')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            GlowCard(
              tint: C.accent,
              strength: 0.10,
              child: Row(
                children: [
                  Icon(Icons.menu_book_rounded, color: C.accent, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Alles, was die App kann',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('Wähle ein Kapitel und wische durch die Seiten. $done von ${_chapters.length} angesehen.',
                            style: TextStyle(color: C.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            for (final (i, c) in _chapters.indexed)
              GlowCard(
                onTap: () => _open(i),
                strength: 0.03,
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: C.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                      child: Icon(c.icon, color: C.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${i + 1}. ${c.title}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          Text(c.summary,
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    seen.contains(c.id)
                        ? Icon(Icons.check_circle_rounded, color: C.dbl)
                        : Text('${c.pages.length} S.', style: TextStyle(color: C.muted, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ein Kapitel: Seiten zum Wischen, am Ende „Jetzt ausprobieren“ und „Nächstes Kapitel“.
class TutorialChapterScreen extends StatefulWidget {
  const TutorialChapterScreen({super.key, required this.chapters, required this.index});
  final List<TutChapter> chapters;
  final int index;

  @override
  State<TutorialChapterScreen> createState() => _TutorialChapterScreenState();
}

class _TutorialChapterScreenState extends State<TutorialChapterScreen> {
  final _pc = PageController();
  int _page = 0;

  TutChapter get c => widget.chapters[widget.index];
  bool get _last => _page == c.pages.length - 1;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _onPage(int p) {
    setState(() => _page = p);
    if (p == c.pages.length - 1) Store.markTutorialSeen(c.id);
  }

  void _next() {
    if (!_last) {
      _pc.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
      return;
    }
    Store.markTutorialSeen(c.id);
    if (widget.index + 1 < widget.chapters.length) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => TutorialChapterScreen(chapters: widget.chapters, index: widget.index + 1)));
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasNext = widget.index + 1 < widget.chapters.length;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      appBar: AppBar(title: Text(c.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pc,
                itemCount: c.pages.length,
                onPageChanged: _onPage,
                itemBuilder: (context, i) {
                  final p = c.pages[i];
                  final text = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.title, style: TextStyle(fontSize: wide ? 32 : 22, fontWeight: FontWeight.w800)),
                      SizedBox(height: wide ? 14 : 8),
                      Text(p.text, style: TextStyle(color: C.muted2, fontSize: wide ? 21 : 15, height: 1.45)),
                    ],
                  );
                  // Ausschnitt auf den verfügbaren Platz skalieren (auf dem Tablet auch vergrößern)
                  final visual = FittedBox(fit: BoxFit.contain, child: p.visual(context));
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: wide
                        ? Row(children: [
                            Expanded(flex: 5, child: visual),
                            const SizedBox(width: 24),
                            Expanded(flex: 4, child: SingleChildScrollView(child: text)),
                          ])
                        : Column(children: [
                            Expanded(flex: 6, child: visual),
                            const SizedBox(height: 16),
                            Expanded(flex: 4, child: SingleChildScrollView(child: SizedBox(width: double.infinity, child: text))),
                          ]),
                  );
                },
              ),
            ),
            // Seitenpunkte
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < c.pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(3),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page ? C.accent : C.line,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  if (_last && c.tryIt != null) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Store.markTutorialSeen(c.id);
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => c.tryIt!()));
                        },
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        icon: const Icon(Icons.touch_app_rounded),
                        label: Text(c.tryLabel ?? 'Jetzt ausprobieren', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: PrimaryButton(
                      label: !_last ? 'Weiter' : (hasNext ? 'Nächstes Kapitel' : 'Fertig'),
                      icon: !_last || hasNext ? Icons.arrow_forward_rounded : Icons.check_rounded,
                      height: 52,
                      onTap: _next,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
