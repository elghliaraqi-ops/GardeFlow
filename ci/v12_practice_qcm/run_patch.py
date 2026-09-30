from pathlib import Path

patch_path = Path('ci/v12_practice_qcm/apply_patch.py')
code = patch_path.read_text(encoding='utf-8')
old = """    home = once(\n        home,\n        '  @override\\n  Widget build(BuildContext context) {',\n        '  @override\\n  void dispose() {\\n    _homeScrollController.dispose();\\n    super.dispose();\\n  }\\n\\n  @override\\n  Widget build(BuildContext context) {',\n        'home dispose',\n    )\n"""
new = """    home_state_idx = home.index('class _HomeScreenState')\n    home_build_idx = home.index('  @override\\n  Widget build(BuildContext context) {', home_state_idx)\n    home = (\n        home[:home_build_idx]\n        + '  @override\\n  void dispose() {\\n    _homeScrollController.dispose();\\n    super.dispose();\\n  }\\n\\n'\n        + home[home_build_idx:]\n    )\n"""
if old not in code:
    raise SystemExit('Expected HomeScreen dispose patch block not found')
code = code.replace(old, new, 1)
exec(compile(code, str(patch_path), 'exec'))
