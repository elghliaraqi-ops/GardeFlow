#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected 1 occurrence, found {count}: {old!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'source/lib/screens/announcements_screen.dart',
    'if (state.promotionExchangeBlocked(me, author)) {',
    '''if (state.promotionExchangeBlocked(\n      me,\n      author,\n      sourceShiftId: targetEntry.shiftId,\n    )) {''',
)
replace_once(
    'source/lib/screens/announcements_screen.dart',
    'if (author != null && state.promotionExchangeBlocked(me, author)) {',
    '''if (author != null &&\n        state.promotionExchangeBlocked(\n          me,\n          author,\n          sourceShiftId: item.shiftId,\n        )) {''',
)

replace_once(
    'source/lib/screens/exchange_request_sheet.dart',
    'if (state.promotionExchangeBlocked(me, targetUser)) {',
    '''if (state.promotionExchangeBlocked(\n        me,\n        targetUser,\n        sourceShiftId: widget.entry.shiftId,\n      )) {''',
)
replace_once(
    'source/lib/screens/exchange_request_sheet.dart',
    '''final crossYearWithSelected =\n        state.promotionExchangeBlocked(me, selectedDoctorUser);''',
    '''final crossYearWithSelected = state.promotionExchangeBlocked(\n      me,\n      selectedDoctorUser,\n      sourceShiftId: widget.entry.shiftId,\n    );''',
)
replace_once(
    'source/lib/screens/exchange_request_sheet.dart',
    'if (crossYearWithSelected) return false;',
    '''if (crossYearWithSelected ||\n                state.promotionExchangeBlocked(\n                  me,\n                  selectedDoctorUser,\n                  sourceShiftId: widget.entry.shiftId,\n                  targetShiftId: e.shiftId,\n                )) {\n              return false;\n            }''',
)
replace_once(
    'source/lib/screens/exchange_request_sheet.dart',
    'final crossYear = state.promotionExchangeBlocked(me, doctorUser);',
    '''final crossYear = state.promotionExchangeBlocked(\n                            me,\n                            doctorUser,\n                            sourceShiftId: widget.entry.shiftId,\n                          );''',
)
replace_once(
    'source/lib/screens/exchange_request_sheet.dart',
    'if (crossYear) return false;',
    '''if (crossYear ||\n                                state.promotionExchangeBlocked(\n                                  me,\n                                  doctorUser,\n                                  sourceShiftId: widget.entry.shiftId,\n                                  targetShiftId: e.shiftId,\n                                )) {\n                              return false;\n                            }''',
)

print('Promotion call sites updated.')
