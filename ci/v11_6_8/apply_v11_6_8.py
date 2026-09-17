from pathlib import Path


def must_replace(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"V11.6.8: pattern not found in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new, count))


must_replace('pubspec.yaml', 'version: 11.6.7+167', 'version: 11.6.8+168')

# pdfrx 2.4.x requires PdfTextSearcher to be created only after the PDF
# document is attached to the PdfViewerController. V11.6.7 created the
# searchers in initState, which can trigger a null-check crash when opening a
# PDF. Keep the existing viewer features but initialize searchers in
# onViewerReady, as recommended by pdfrx.
p = Path('lib/screens/official_planning_screen.dart')
text = p.read_text()
marker = 'class _OfficialPdfViewerScreen extends StatefulWidget {'
pos = text.find(marker)
if pos < 0:
    raise SystemExit('V11.6.8: PDF viewer marker not found')

text = text[:pos] + r'''class _OfficialPdfViewerScreen extends StatefulWidget {
  final SharedResource resource;
  final AppUser? currentUser;

  const _OfficialPdfViewerScreen({required this.resource, required this.currentUser});

  @override
  State<_OfficialPdfViewerScreen> createState() => _OfficialPdfViewerScreenState();
}

class _OfficialPdfViewerScreenState extends State<_OfficialPdfViewerScreen> {
  final _backend = SupabaseBackendService.instance;
  final PdfViewerController _controller = PdfViewerController();
  final TextEditingController _searchField = TextEditingController();

  PdfTextSearcher? _doctorSearcher;
  PdfTextSearcher? _manualSearcher;

  Uint8List? _bytes;
  Object? _error;
  bool _loading = true;
  bool _searchMode = false;
  bool _viewerReady = false;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _disposeSearchers() {
    final doctor = _doctorSearcher;
    final manual = _manualSearcher;
    if (doctor != null) {
      doctor.removeListener(_onSearchChanged);
      doctor.dispose();
    }
    if (manual != null) {
      manual.removeListener(_onSearchChanged);
      manual.dispose();
    }
    _doctorSearcher = null;
    _manualSearcher = null;
  }

  @override
  void dispose() {
    _disposeSearchers();
    _searchField.dispose();
    super.dispose();
  }

  Future<void> _loadPdf() async {
    _disposeSearchers();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _viewerReady = false;
        _searchMode = false;
        _searchField.clear();
      });
    }
    try {
      final bytes = await _backend.downloadSharedResource(widget.resource.storagePath);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Pattern? _doctorPattern() {
    final user = widget.currentUser;
    if (user == null) return null;
    final nom = user.nom.trim();
    final prenom = user.prenom.trim();
    if (nom.isEmpty || prenom.isEmpty) return null;

    final firstPrenom = prenom.split(RegExp(r'\s+')).first;
    final variants = <String>{
      '${RegExp.escape(prenom)}\\s+${RegExp.escape(nom)}',
      '${RegExp.escape(nom)}\\s+${RegExp.escape(prenom)}',
      '${RegExp.escape(firstPrenom)}\\s+${RegExp.escape(nom)}',
      '${RegExp.escape(nom)}\\s+${RegExp.escape(firstPrenom)}',
    };
    return RegExp('(?:${variants.join('|')})', caseSensitive: false);
  }

  void _startDoctorHighlight() {
    final searcher = _doctorSearcher;
    final pattern = _doctorPattern();
    if (searcher == null || pattern == null) return;
    searcher.startTextSearch(
      pattern,
      caseInsensitive: true,
      goToFirstMatch: false,
      searchImmediately: true,
    );
  }

  void _search(String raw) {
    final searcher = _manualSearcher;
    if (searcher == null) return;
    final query = raw.trim();
    if (query.isEmpty) {
      searcher.resetTextSearch();
      return;
    }
    searcher.startTextSearch(
      query,
      caseInsensitive: true,
      goToFirstMatch: true,
      searchImmediately: true,
    );
  }

  void _toggleSearch() {
    if (!_viewerReady) return;
    setState(() {
      _searchMode = !_searchMode;
      if (!_searchMode) {
        _searchField.clear();
        _manualSearcher?.resetTextSearch();
      }
    });
  }

  void _paintDoctorMatches(Canvas canvas, Rect pageRect, PdfPage page) {
    _doctorSearcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  void _paintManualMatches(Canvas canvas, Rect pageRect, PdfPage page) {
    _manualSearcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  void _viewerDidBecomeReady(PdfViewerController controller) {
    if (_viewerReady) return;

    // Critical V11.6.8 fix: instantiate PdfTextSearcher only now, after the
    // controller owns a loaded document.
    _disposeSearchers();
    _doctorSearcher = PdfTextSearcher(controller)..addListener(_onSearchChanged);
    _manualSearcher = PdfTextSearcher(controller)..addListener(_onSearchChanged);
    _viewerReady = true;

    _startDoctorHighlight();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final manualSearcher = _manualSearcher;
    final currentIndex = manualSearcher?.currentIndex;
    final matchCount = manualSearcher?.matches.length ?? 0;
    final searching = manualSearcher?.isSearching ?? false;
    final searchStatus = searching
        ? 'Recherche…'
        : matchCount == 0
            ? 'Aucun résultat'
            : '${(currentIndex ?? 0) + 1}/$matchCount';

    return Scaffold(
      backgroundColor: const Color(0xFF202226),
      appBar: AppBar(
        titleSpacing: 8,
        title: _searchMode
            ? TextField(
                controller: _searchField,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  if (value.trim().length >= 2 || value.trim().isEmpty) _search(value);
                },
                onSubmitted: _search,
                decoration: const InputDecoration(
                  hintText: 'Rechercher un nom, mot, service…',
                  border: InputBorder.none,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Planning officiel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                    widget.resource.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: _searchMode ? 'Fermer la recherche' : 'Rechercher dans le PDF',
            onPressed: _loading || bytes == null || !_viewerReady ? null : _toggleSearch,
            icon: Icon(_searchMode ? Icons.close_rounded : Icons.search_rounded),
          ),
          if (!_searchMode) ...[
            IconButton(
              tooltip: 'Zoom arrière',
              onPressed: _loading || bytes == null || !_viewerReady ? null : () => _controller.zoomDown(),
              icon: const Icon(Icons.zoom_out_rounded),
            ),
            IconButton(
              tooltip: 'Zoom avant',
              onPressed: _loading || bytes == null || !_viewerReady ? null : () => _controller.zoomUp(),
              icon: const Icon(Icons.zoom_in_rounded),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || bytes == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.picture_as_pdf_outlined, size: 48, color: Colors.white70),
                        const SizedBox(height: 12),
                        const Text(
                          'Impossible d’afficher ce PDF.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadPdf,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: PdfViewer.data(
                        bytes,
                        sourceName: widget.resource.displayName,
                        controller: _controller,
                        params: PdfViewerParams(
                          backgroundColor: const Color(0xFF202226),
                          margin: 10,
                          minScale: 0.7,
                          maxScale: 8.0,
                          panEnabled: true,
                          scaleEnabled: true,
                          matchTextColor: const Color(0xFFFFF176).withOpacity(0.62),
                          activeMatchTextColor: const Color(0xFFFFB300).withOpacity(0.78),
                          pagePaintCallbacks: [
                            _paintDoctorMatches,
                            _paintManualMatches,
                          ],
                          onViewerReady: (document, controller) {
                            _viewerDidBecomeReady(controller);
                          },
                        ),
                      ),
                    ),
                    if (_searchMode)
                      Positioned(
                        top: 10,
                        left: 12,
                        right: 12,
                        child: SafeArea(
                          bottom: false,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.72),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    searchStatus,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Résultat précédent',
                                    onPressed: matchCount == 0 ? null : () => _manualSearcher?.goToPrevMatch(),
                                    icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Résultat suivant',
                                    onPressed: matchCount == 0 ? null : () => _manualSearcher?.goToNextMatch(),
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.62),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              !_viewerReady
                                  ? 'Chargement du document…'
                                  : widget.currentUser == null
                                      ? 'Pincez pour zoomer • loupe pour rechercher'
                                      : '${widget.currentUser!.fullName} est surligné en fluo • loupe pour rechercher',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
'''

p.write_text(text)
print('GardeFlow V11.6.8 PDF viewer hotfix applied successfully')
