from pathlib import Path

root = Path('source/lib')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    if old not in text:
        raise RuntimeError(f'Marker not found in {path}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


decor = root / 'theme/screen_decor.dart'
text = decor.read_text(encoding='utf-8')
old_body = "        body: body,\n        floatingActionButton: floatingActionButton,"
new_body = (
    "        body: body == null\n"
    "            ? null\n"
    "            : _DecorForeground(scene: scene, child: body!),\n"
    "        floatingActionButton: floatingActionButton,"
)
if old_body not in text:
    raise RuntimeError('DecorScaffold body marker not found')
text = text.replace(old_body, new_body, 1)

marker = 'class DecorSectionBanner extends StatelessWidget {'
foreground = '''class _DecorForeground extends StatelessWidget {
  final ScreenDecorScene scene;
  final Widget child;

  const _DecorForeground({required this.scene, required this.child});

  @override
  Widget build(BuildContext context) {
    final accent = scene.accent;
    final dark = AppColors.isDarkMode;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                right: -26,
                top: 18,
                child: Transform.rotate(
                  angle: -.13,
                  child: Icon(
                    scene.primaryIcon,
                    size: 112,
                    color: accent.withOpacity(dark ? .045 : .032),
                  ),
                ),
              ),
              Positioned(
                left: -18,
                bottom: 54,
                child: Transform.rotate(
                  angle: .15,
                  child: Icon(
                    scene.secondaryIcon,
                    size: 82,
                    color: accent.withOpacity(dark ? .034 : .026),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

'''
if marker not in text:
    raise RuntimeError('DecorSectionBanner marker not found')
text = text.replace(marker, foreground + marker, 1)
decor.write_text(text, encoding='utf-8')

replace_once(
    root / 'screens/practice_screen.dart',
    "    return ColoredBox(\n      color: PracticeColors.background,\n      child: SafeArea(",
    "    return ScreenDecorBackdrop(\n      scene: ScreenDecorScene.practice,\n      baseColor: PracticeColors.background,\n      child: SafeArea(",
)
replace_once(
    root / 'screens/junior_oncall_screen.dart',
    "      return ColoredBox(\n        color: theme.scaffoldBackgroundColor,\n        child: RefreshIndicator(",
    "      return ScreenDecorBackdrop(\n        scene: ScreenDecorScene.onCall,\n        baseColor: theme.scaffoldBackgroundColor,\n        child: RefreshIndicator(",
)
replace_once(
    root / 'screens/senior_oncall_screen.dart',
    "      return ColoredBox(\n        color: AppColors.paper,\n        child: RefreshIndicator(",
    "      return ScreenDecorBackdrop(\n        scene: ScreenDecorScene.onCall,\n        baseColor: AppColors.paper,\n        child: RefreshIndicator(",
)

print('Embedded and opaque decor visibility patch applied.')
