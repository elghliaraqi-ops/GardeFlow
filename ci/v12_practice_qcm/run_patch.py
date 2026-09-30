from pathlib import Path

patch_path = Path('ci/v12_practice_qcm/apply_patch.py')
code = patch_path.read_text(encoding='utf-8')

old_once = """def once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)
"""
new_once = """def once(text, old, new, label):
    count = text.count(old)
    if count == 1:
        return text.replace(old, new, 1)
    if label.startswith('qcm '):
        state_idx = text.index('class _PracticeScreenState')
        pos = text.find(old, state_idx)
        if pos >= 0:
            return text[:pos] + new + text[pos + len(old):]
    raise SystemExit(f'{label}: expected 1 match, found {count}')
"""
if old_once not in code:
    raise SystemExit('Expected once helper not found')
code = code.replace(old_once, new_once, 1)

old_home = """    home = once(
        home,
        '  @override\\n  Widget build(BuildContext context) {',
        '  @override\\n  void dispose() {\\n    _homeScrollController.dispose();\\n    super.dispose();\\n  }\\n\\n  @override\\n  Widget build(BuildContext context) {',
        'home dispose',
    )
"""
new_home = """    home_state_idx = home.index('class _HomeScreenState')
    home_build_idx = home.index('  @override\\n  Widget build(BuildContext context) {', home_state_idx)
    home = (
        home[:home_build_idx]
        + '  @override\\n  void dispose() {\\n    _homeScrollController.dispose();\\n    super.dispose();\\n  }\\n\\n'
        + home[home_build_idx:]
    )
"""
if old_home not in code:
    raise SystemExit('Expected HomeScreen dispose patch block not found')
code = code.replace(old_home, new_home, 1)

exec(compile(code, str(patch_path), 'exec'))
