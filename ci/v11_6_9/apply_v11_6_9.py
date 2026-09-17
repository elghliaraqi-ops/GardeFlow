from pathlib import Path


def must_replace(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"V11.6.9: pattern not found in {path}: {old[:160]!r}")
    p.write_text(text.replace(old, new, count))


must_replace('pubspec.yaml', 'version: 11.6.8+168', 'version: 11.6.9+169')

# ---------------------------------------------------------------------------
# Official PDF viewer robustness
# ---------------------------------------------------------------------------
# Fix the automatic doctor-name regexp emitted by V11.6.8. The previous Dart
# source contained four backslashes, making the regexp look for a literal
# backslash instead of whitespace between first/last names.
p = Path('lib/screens/official_planning_screen.dart')
text = p.read_text()
text = text.replace(r"${RegExp.escape(prenom)}\\s+${RegExp.escape(nom)}", r"${RegExp.escape(prenom)}\s+${RegExp.escape(nom)}")
text = text.replace(r"${RegExp.escape(nom)}\\s+${RegExp.escape(prenom)}", r"${RegExp.escape(nom)}\s+${RegExp.escape(prenom)}")
text = text.replace(r"${RegExp.escape(firstPrenom)}\\s+${RegExp.escape(nom)}", r"${RegExp.escape(firstPrenom)}\s+${RegExp.escape(nom)}")
text = text.replace(r"${RegExp.escape(nom)}\\s+${RegExp.escape(firstPrenom)}", r"${RegExp.escape(nom)}\s+${RegExp.escape(firstPrenom)}")
p.write_text(text)

# Follow pdfrx lifecycle: dispose search helpers when the document is detached
# and initialize them only from onViewerReady. Also schedule the visual state
# update asynchronously to avoid rebuilding from a viewer callback.
must_replace(
    'lib/screens/official_planning_screen.dart',
    """    _startDoctorHighlight();
    if (mounted) setState(() {});
  }
""",
    """    _startDoctorHighlight();
    Future.microtask(() {
      if (mounted) setState(() {});
    });
  }
""",
)

must_replace(
    'lib/screens/official_planning_screen.dart',
    """                          pagePaintCallbacks: [
                            _paintDoctorMatches,
                            _paintManualMatches,
                          ],
                          onViewerReady: (document, controller) {
                            _viewerDidBecomeReady(controller);
                          },
""",
    """                          pagePaintCallbacks: [
                            _paintDoctorMatches,
                            _paintManualMatches,
                          ],
                          onDocumentChanged: (document) {
                            if (document == null) {
                              Future.microtask(() {
                                if (!mounted) return;
                                _disposeSearchers();
                                setState(() => _viewerReady = false);
                              });
                            }
                          },
                          onViewerReady: (document, controller) {
                            _viewerDidBecomeReady(controller);
                          },
""",
)

# ---------------------------------------------------------------------------
# Reminder settings contrast/readability
# ---------------------------------------------------------------------------
# Force explicit colors for delay chips. This prevents dark/black label text
# from becoming invisible depending on the device theme.
must_replace(
    'lib/screens/settings_screen.dart',
    """                      FilterChip(
                        label: Text(appState.reminderDelayLabel(minutes)),
                        selected: appState.reminderDelays.contains(minutes),
                        onSelected: _saving
""",
    """                      FilterChip(
                        label: Text(appState.reminderDelayLabel(minutes)),
                        selected: appState.reminderDelays.contains(minutes),
                        backgroundColor: AppColors.paperAlt,
                        selectedColor: AppColors.brand,
                        checkmarkColor: Colors.white,
                        side: const BorderSide(color: AppColors.line),
                        labelStyle: TextStyle(
                          color: appState.reminderDelays.contains(minutes) ? Colors.white : AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: _saving
""",
)

# Keep dropdown values readable as well on devices using a dark system theme.
text = Path('lib/screens/settings_screen.dart').read_text()
text = text.replace(
    "decoration: const InputDecoration(labelText: 'Profil de sonnerie'),",
    "decoration: const InputDecoration(labelText: 'Profil de sonnerie'),\n                  dropdownColor: Colors.white,\n                  style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),",
)
text = text.replace(
    "decoration: const InputDecoration(labelText: 'Répétitions'),",
    "decoration: const InputDecoration(labelText: 'Répétitions'),\n                        dropdownColor: Colors.white,\n                        style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),",
)
text = text.replace(
    "decoration: const InputDecoration(labelText: 'Après'),",
    "decoration: const InputDecoration(labelText: 'Après'),\n                        dropdownColor: Colors.white,\n                        style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),",
)
Path('lib/screens/settings_screen.dart').write_text(text)

print('GardeFlow V11.6.9 applied successfully')
