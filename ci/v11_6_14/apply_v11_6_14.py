from pathlib import Path
import shutil


def must_replace(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"V11.6.14: pattern not found in {path}: {old[:180]!r}")
    p.write_text(text.replace(old, new, count))


def assemble(prefix: str, target: str) -> None:
    parts = sorted(Path(__file__).parent.glob(f'{prefix}.part*'))
    if not parts:
        raise SystemExit(f'V11.6.14: no parts found for {prefix}')
    destination = Path(target)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(''.join(part.read_text() for part in parts))


must_replace('pubspec.yaml', 'version: 11.6.13+173', 'version: 11.6.14+174')
must_replace(
    'pubspec.yaml',
    'flutter_local_notifications: 17.2.4',
    'flutter_local_notifications: 19.5.0',
)

base = Path(__file__).parent
for source_name, target in [
    ('notification_service.dart', 'lib/services/notification_service.dart'),
    ('configure_android.dart', 'tool/configure_android.dart'),
]:
    source = base / source_name
    destination = Path(target)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)

assemble('settings_screen', 'lib/screens/settings_screen.dart')
assemble('junior_oncall_screen', 'lib/screens/junior_oncall_screen.dart')

# Stable native notification identifiers: rebuilding reminders must replace the
# same Android alarm instead of creating a new native alarm every time.
must_replace(
    'lib/state/app_state.dart',
    "ownerPhone:me.phone,dateStr:r.dateStr,notificationKey:r.id,title:'Attention · GardeFlow',",
    "ownerPhone:me.phone,dateStr:r.dateStr,notificationKey:'${e.id}|${e.shiftId}|${r.fireAt.millisecondsSinceEpoch}',title:'Attention · GardeFlow',",
)

# Keep a conservative number of native future alarms on Android. The local
# model can retain more reminders; the closest 96 are activated natively.
must_replace(
    'lib/state/app_state.dart',
    'final limit=!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS?56:200;',
    'final limit=!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS?56:96;',
)

print('GardeFlow V11.6.14 reminders and Junior on-call redesign applied successfully')
