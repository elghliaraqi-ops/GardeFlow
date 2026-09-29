from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / 'source/lib/screens/home_screen.dart'
text = path.read_text(encoding='utf-8')
old = """    final badge = appState.totalBadgeCount;\n    final rawInitial = user.nom.trim();\n    final initial = rawInitial.isEmpty\n        ? 'D'\n        : rawInitial.substring(0, 1).toUpperCase();\n"""
new = "    final badge = appState.totalBadgeCount;\n"
if old in text:
    text = text.replace(old, new, 1)
elif 'final rawInitial = user.nom.trim();' in text:
    raise RuntimeError('Unexpected top-bar initial block shape; refusing blind edit')
path.write_text(text, encoding='utf-8')
print('UI refresh cleanup applied')
