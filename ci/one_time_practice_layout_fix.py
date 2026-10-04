from pathlib import Path

practice = Path('source/lib/screens/practice_screen.dart')
s = practice.read_text()

old = '''              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _PracticePrimaryActionCard('''
new = '''              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PracticePrimaryActionCard('''

if old not in s:
    if new in s:
        print('Practice primary action row already uses bounded vertical constraints.')
    else:
        raise SystemExit('Practice primary action row anchor not found')
else:
    s = s.replace(old, new, 1)
    practice.write_text(s)
    print('Practice primary action row fixed for ListView constraints.')
