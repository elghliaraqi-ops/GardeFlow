from pathlib import Path

ROOT = Path('.')
HOME = ROOT / 'source/lib/screens/home_screen.dart'
CONFIG = ROOT / 'source/tool/configure_android.dart'
ALARM_BRIDGE = ROOT / 'source/tool/install_system_alarm_bridge.py'

home = HOME.read_text()

import_anchor = "import '../services/push_notification_service.dart';\n"
widget_import = "import '../services/android_widget_service.dart';\n"
if widget_import not in home:
    if import_anchor not in home:
        raise SystemExit('Home import anchor missing')
    home = home.replace(import_anchor, import_anchor + widget_import, 1)

state_anchor = '''  final ScrollController _homeScrollController = ScrollController();

  @override
  void dispose() {'''
state_replacement = '''  final ScrollController _homeScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    AndroidWidgetService.instance.action.addListener(_handleWidgetAction);
    unawaited(AndroidWidgetService.instance.initialize());
  }

  void _handleWidgetAction() {
    final action = AndroidWidgetService.instance.action.value;
    if (!mounted || action == null) return;
    var target = 0;
    switch (action) {
      case 'planning':
      case 'next_guard':
        target = 1;
        break;
      case 'practice':
        target = 2;
        break;
      case 'astreintes':
        target = 3;
        break;
      default:
        target = 0;
    }
    if (_tab != target) setState(() => _tab = target);
    AndroidWidgetService.instance.consumeAction();
  }

  @override
  void dispose() {
    AndroidWidgetService.instance.action.removeListener(_handleWidgetAction);'''
if 'AndroidWidgetService.instance.action.addListener' not in home:
    if state_anchor not in home:
        raise SystemExit('Home state anchor missing')
    home = home.replace(state_anchor, state_replacement, 1)

post_frame_anchor = '''        if (context.mounted && appState.currentUser != null) {
          PushNotificationService.instance.navigationReady('''
post_frame_replacement = '''        if (context.mounted && appState.currentUser != null) {
          unawaited(AndroidWidgetService.instance.sync(appState));
          PushNotificationService.instance.navigationReady('''
if 'AndroidWidgetService.instance.sync(appState)' not in home:
    if post_frame_anchor not in home:
        raise SystemExit('Home post-frame anchor missing')
    home = home.replace(post_frame_anchor, post_frame_replacement, 1)

HOME.write_text(home)

config = CONFIG.read_text()
write_anchor = '''  xml = xml.replaceRange(appOpening.end, appOpening.end, additions);'''
widget_receiver = """  if (!xml.contains('GardeFlowWidgetProvider')) {
    additions += '''\n        <receiver android:name=\".GardeFlowWidgetProvider\" android:exported=\"true\">
            <intent-filter>
                <action android:name=\"android.appwidget.action.APPWIDGET_UPDATE\" />
            </intent-filter>
            <meta-data android:name=\"android.appwidget.provider\" android:resource=\"@xml/gardeflow_widget_info\" />
        </receiver>''';
  }
"""
if "android.appwidget.action.APPWIDGET_UPDATE" not in config:
    if write_anchor not in config:
        raise SystemExit('Android manifest write anchor missing')
    config = config.replace(write_anchor, widget_receiver + write_anchor, 1)

source_copy_anchor = '''  final resources = Directory('${root.path}/tool/android-res');
  for (final source in resources.listSync(recursive: true).whereType<File>()) {
    final relative = source.path.substring(resources.path.length + 1);
    final target = file('android/app/src/main/res/$relative');
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
  }
  stdout.writeln('Android configuré : $packageName (Firebase planninghm6).');'''
source_copy_replacement = '''  final resources = Directory('${root.path}/tool/android-res');
  for (final source in resources.listSync(recursive: true).whereType<File>()) {
    final relative = source.path.substring(resources.path.length + 1);
    final target = file('android/app/src/main/res/$relative');
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
  }

  final nativeSources = Directory('${root.path}/tool/android-src');
  if (nativeSources.existsSync()) {
    for (final source in nativeSources.listSync(recursive: true).whereType<File>()) {
      final relative = source.path.substring(nativeSources.path.length + 1);
      final target = file(
        'android/app/src/main/kotlin/com/huim6/huim6_planning/$relative',
      );
      target.parent.createSync(recursive: true);
      source.copySync(target.path);
    }
  }
  stdout.writeln('Android configuré : $packageName (Firebase planninghm6).');'''
if "final nativeSources = Directory" not in config:
    if source_copy_anchor not in config:
        raise SystemExit('Android resource copy anchor missing')
    config = config.replace(source_copy_anchor, source_copy_replacement, 1)
CONFIG.write_text(config)

# install_system_alarm_bridge.py regenerates MainActivity after configure_android.dart.
# Merge the widget channel into that generated MainActivity so neither feature overwrites the other.
bridge = ALARM_BRIDGE.read_text()
main_start = bridge.find("main_kotlin = r'''package __PACKAGE__")
main_end_marker = "'''.replace(\"__PACKAGE__\", package_name)\nmain_activity.write_text(main_kotlin, encoding=\"utf-8\")"
main_end = bridge.find(main_end_marker, main_start)
if main_start < 0 or main_end < 0:
    raise SystemExit('System alarm MainActivity template not found')
main_block = bridge[main_start:main_end]
if 'com.huim6.huim6_planning/widget' not in main_block:
    class_anchor = 'class MainActivity : FlutterActivity() {\n'
    class_fields = '''class MainActivity : FlutterActivity() {
    companion object {
        private const val WIDGET_CHANNEL = "com.huim6.huim6_planning/widget"
        private const val EXTRA_WIDGET_ACTION = "gardeflow_widget_action"
    }

    private var widgetChannel: MethodChannel? = null
    private var pendingWidgetAction: String? = null
'''
    if class_anchor not in main_block:
        raise SystemExit('System alarm MainActivity class anchor missing')
    main_block = main_block.replace(class_anchor, class_fields, 1)

    super_anchor = '        super.configureFlutterEngine(flutterEngine)\n'
    super_replacement = '''        super.configureFlutterEngine(flutterEngine)
        pendingWidgetAction = intent?.getStringExtra(EXTRA_WIDGET_ACTION)
'''
    if super_anchor not in main_block:
        raise SystemExit('System alarm configureFlutterEngine anchor missing')
    main_block = main_block.replace(super_anchor, super_replacement, 1)

    tail = '''        }
    }
}
'''
    widget_tail = '''        }

        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIDGET_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialWidgetAction" -> {
                        val value = pendingWidgetAction
                        pendingWidgetAction = null
                        result.success(value)
                    }
                    "updateWidgetData" -> {
                        @Suppress("UNCHECKED_CAST")
                        val values = call.arguments as? Map<String, Any?> ?: emptyMap()
                        val prefs = getSharedPreferences(GardeFlowWidgetProvider.PREFS_NAME, MODE_PRIVATE)
                        val editor = prefs.edit()
                        values.forEach { (key, value) ->
                            editor.putString(key, value?.toString().orEmpty())
                        }
                        editor.apply()
                        GardeFlowWidgetProvider.updateAll(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra(EXTRA_WIDGET_ACTION)
        if (!action.isNullOrBlank()) {
            pendingWidgetAction = action
            widgetChannel?.invokeMethod("widgetAction", action)
        }
    }
}
'''
    if tail not in main_block:
        raise SystemExit('System alarm MainActivity tail anchor missing')
    main_block = main_block.replace(tail, widget_tail, 1)
    bridge = bridge[:main_start] + main_block + bridge[main_end:]
ALARM_BRIDGE.write_text(bridge)

for required in (
    widget_import.strip(),
    'AndroidWidgetService.instance.sync(appState)',
    "case 'practice':",
    "case 'astreintes':",
):
    if required not in home:
        raise SystemExit(f'missing Home widget integration: {required}')
for required in (
    'android.appwidget.action.APPWIDGET_UPDATE',
    "final nativeSources = Directory",
    'gardeflow_widget_info',
):
    if required not in config:
        raise SystemExit(f'missing Android widget integration: {required}')
for required in (
    'com.huim6.huim6_planning/widget',
    'GardeFlowWidgetProvider.updateAll(this)',
    'override fun onNewIntent',
    'gardeflow/fullscreen_alarm',
):
    if required not in bridge:
        raise SystemExit(f'missing merged MainActivity feature: {required}')

print('GardeFlow Android widget integrated without replacing the system alarm bridge.')
