from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"Anchor missing in {path}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1))


# Announcements: the public exchange proposal must use the same dynamic
# first-year rule as the exchange sheet and backend, for every guard type.
p = Path('source/lib/screens/announcements_screen.dart')
s = p.read_text()
s = s.replace(
    "    final crossYear = InternPromotions.crossYearBlocked(me, author);\n    final announcementIsUrgence = targetEntry.shiftId.startsWith('urg-');\n    if (crossYear && announcementIsUrgence) {\n      ScaffoldMessenger.of(context).showSnackBar(\n        const SnackBar(\n          content: Text('Les échanges de gardes d’Urgences sont impossibles entre première et deuxième année.'),\n        ),\n      );\n      return;\n    }",
    "    if (state.promotionExchangeBlocked(me, author)) {\n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(\n          content: Text(\n            'La promotion de première année (Promo ${state.currentFirstYearPromotion}) ne peut échanger des gardes qu’avec la même promotion.',\n          ),\n        ),\n      );\n      return;\n    }",
    1,
)
s = s.replace(
    "    final myPromotion = InternPromotions.labelFor(me);",
    "    final myPromotion = InternPromotions.labelFor(\n      me,\n      firstYearPromotion: state.currentFirstYearPromotion,\n    );",
    1,
)
s = s.replace(
    "    if (author != null &&\n        item.shiftId.startsWith('urg-') &&\n        InternPromotions.crossYearBlocked(me, author)) return true;",
    "    if (author != null && state.promotionExchangeBlocked(me, author)) {\n      return true;\n    }",
    1,
)
p.write_text(s)

# Home planning badge: derive training year from the current first-year cohort.
replace_once(
    'source/lib/screens/home_screen.dart',
    "    final promotionLabel = InternPromotions.labelFor(appState.currentUser);",
    "    final promotionLabel = InternPromotions.labelFor(\n      appState.currentUser,\n      firstYearPromotion: appState.currentFirstYearPromotion,\n    );",
)

# Exchange sheet: obsolete after the rule became guard-type agnostic.
p = Path('source/lib/screens/exchange_request_sheet.dart')
s = p.read_text().replace(
    "    final sourceIsUrgence = widget.entry.shiftId.startsWith('urg-');\n",
    "",
    1,
)
p.write_text(s)

# Guard against regressions to the old fixed-Promo-7 / Urgences-only logic.
for path in [
    'source/lib/screens/announcements_screen.dart',
    'source/lib/screens/home_screen.dart',
    'source/lib/screens/exchange_request_sheet.dart',
]:
    text = Path(path).read_text()
    if 'InternPromotions.crossYearBlocked(me, author)' in text:
        raise SystemExit(f'Old direct promotion comparison still present in {path}')
