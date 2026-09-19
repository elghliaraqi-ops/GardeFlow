from pathlib import Path

EXPECTED = "version: 11.6.28+188"
TARGET = "version: 11.6.29+189"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.29: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

directory = Path("lib/screens/directory_screen.dart")
d = directory.read_text()

old_top_action = """        if (widget.embedded && isAdmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: SoftIconButton(
                icon: Icons.person_add_alt_1_rounded,
                tooltip: 'Ajouter un contact',
                onTap: () => _openContactEditor(context, appState),
              ),
            ),
          ),"""

if old_top_action not in d:
    raise SystemExit("V11.6.29: embedded add-contact header action not found")
d = d.replace(old_top_action, "", 1)

old_embedded = """    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.paper,
        child: SafeArea(bottom: false, child: content),
      );
    }"""

new_embedded = """    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.paper,
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: content,
              ),
            ),
            if (isAdmin)
              Positioned(
                right: 18,
                bottom: 18,
                child: SafeArea(
                  top: false,
                  child: FloatingActionButton(
                    heroTag: 'directory-add-contact-embedded',
                    tooltip: 'Ajouter un contact',
                    onPressed: () => _openContactEditor(context, appState),
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    elevation: 5,
                    child: const Icon(Icons.person_add_alt_1_rounded),
                  ),
                ),
              ),
          ],
        ),
      );
    }"""

if old_embedded not in d:
    raise SystemExit("V11.6.29: embedded directory return block not found")
d = d.replace(old_embedded, new_embedded, 1)

old_standalone = """      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _openContactEditor(context, appState),
              icon: const Icon(Icons.add_call),
              label: const Text('Ajouter'),
            )
          : null,"""

new_standalone = """      floatingActionButton: isAdmin
          ? FloatingActionButton(
              heroTag: 'directory-add-contact-standalone',
              tooltip: 'Ajouter un contact',
              onPressed: () => _openContactEditor(context, appState),
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              child: const Icon(Icons.person_add_alt_1_rounded),
            )
          : null,"""

if old_standalone not in d:
    raise SystemExit("V11.6.29: standalone directory FAB block not found")
d = d.replace(old_standalone, new_standalone, 1)

directory.write_text(d)

print("GardeFlow V11.6.29: bouton Ajouter un contact déplacé en FAB admin")
