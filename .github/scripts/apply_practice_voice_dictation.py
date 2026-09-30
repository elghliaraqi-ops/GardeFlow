from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 match, found {count}")
    return text.replace(old, new, 1)


root = Path(__file__).resolve().parents[2]

# 1) Flutter dependency -------------------------------------------------------
pubspec = root / "source/pubspec.yaml"
text = pubspec.read_text(encoding="utf-8")
if "speech_to_text:" not in text:
    text = replace_once(
        text,
        "  shared_preferences: ^2.5.3\n",
        "  shared_preferences: ^2.5.3\n  speech_to_text: ^7.4.0\n",
        "pubspec speech_to_text",
    )
pubspec.write_text(text, encoding="utf-8")

# 2) Android microphone / speech-recognition visibility ----------------------
android_tool = root / "source/tool/configure_android.dart"
text = android_tool.read_text(encoding="utf-8")
text = replace_once(
    text,
    "'SCHEDULE_EXACT_ALARM', 'VIBRATE', 'WAKE_LOCK'",
    "'SCHEDULE_EXACT_ALARM', 'RECORD_AUDIO', 'VIBRATE', 'WAKE_LOCK'",
    "Android RECORD_AUDIO permission",
)
anchor = """  final appOpening = RegExp(r'<application\\b[^>]*>').firstMatch(xml);\n  if (appOpening == null) throw StateError('Application absente du manifest');\n"""
addition = """  if (!xml.contains('android.speech.RecognitionService')) {\n    final applicationStart = RegExp(r'<application\\b').firstMatch(xml);\n    if (applicationStart == null) {\n      throw StateError('Application absente du manifest');\n    }\n    const speechQueries = '''\n    <queries>\n        <intent>\n            <action android:name=\"android.speech.RecognitionService\" />\n        </intent>\n    </queries>\n''';\n    xml = xml.replaceRange(\n      applicationStart.start,\n      applicationStart.start,\n      speechQueries,\n    );\n  }\n  final appOpening = RegExp(r'<application\\b[^>]*>').firstMatch(xml);\n  if (appOpening == null) throw StateError('Application absente du manifest');\n"""
if "android.speech.RecognitionService" not in text:
    text = replace_once(text, anchor, addition, "Android speech recognition query")
android_tool.write_text(text, encoding="utf-8")

# 3) Practice form dictation --------------------------------------------------
practice = root / "source/lib/screens/practice_screen.dart"
text = practice.read_text(encoding="utf-8")

if "package:speech_to_text/speech_to_text.dart" not in text:
    text = replace_once(
        text,
        "import 'package:intl/intl.dart';\n",
        "import 'package:intl/intl.dart';\nimport 'package:speech_to_text/speech_to_text.dart' as stt;\n",
        "speech_to_text import",
    )

fields_anchor = """class _PracticeCaseFormScreenState extends State<PracticeCaseFormScreen> {\n  final _service = PracticeService.instance;\n  final _formKey = GlobalKey<FormState>();\n"""
fields_new = """class _PracticeCaseFormScreenState extends State<PracticeCaseFormScreen> {\n  final _service = PracticeService.instance;\n  final _formKey = GlobalKey<FormState>();\n  final stt.SpeechToText _speech = stt.SpeechToText();\n  TextEditingController? _dictatingController;\n  String? _dictatingLabel;\n  String _dictationBaseText = '';\n  bool _speechReady = false;\n  bool _speechInitializing = false;\n  String? _speechLocaleId;\n"""
if "_dictatingController" not in text:
    text = replace_once(text, fields_anchor, fields_new, "Practice speech state")

dispose_old = """  @override\n  void dispose() {\n    _autosave?.cancel();\n    for (final controller in _controllers) {\n      controller.dispose();\n    }\n    super.dispose();\n  }\n"""
dispose_new = """  @override\n  void dispose() {\n    _autosave?.cancel();\n    if (_speech.isListening) {\n      unawaited(_speech.cancel());\n    }\n    for (final controller in _controllers) {\n      controller.dispose();\n    }\n    super.dispose();\n  }\n"""
if "unawaited(_speech.cancel())" not in text:
    text = replace_once(text, dispose_old, dispose_new, "Practice speech dispose")

methods_anchor = """  void _changed() {\n    if (_restoring) return;\n"""
methods = r'''  Future<bool> _ensureSpeechReady() async {
    if (_speechReady) return true;
    if (_speechInitializing) return false;
    if (mounted) setState(() => _speechInitializing = true);
    try {
      final available = await _speech.initialize(
        onStatus: (_) {
          if (mounted) setState(() {});
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _dictatingController = null;
            _dictatingLabel = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Dictée interrompue : ${error.errorMsg.replaceAll('_', ' ')}',
              ),
            ),
          );
        },
      );
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'La dictée vocale est indisponible. Autorisez le microphone et la reconnaissance vocale, ou utilisez un navigateur compatible.',
              ),
            ),
          );
        }
        return false;
      }

      String? french;
      final locales = await _speech.locales();
      for (final locale in locales) {
        final id = locale.localeId.toLowerCase().replaceAll('-', '_');
        if (id == 'fr_fr') {
          french = locale.localeId;
          break;
        }
        if (french == null && id.startsWith('fr_')) {
          french = locale.localeId;
        }
      }
      _speechLocaleId = french;
      _speechReady = true;
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d’activer la dictée vocale : $e')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _speechInitializing = false);
    }
  }

  Future<void> _toggleDictation(
    TextEditingController controller,
    String label,
  ) async {
    if (_speechInitializing) return;

    if (identical(_dictatingController, controller) && _speech.isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() {
          _dictatingController = null;
          _dictatingLabel = null;
        });
      }
      return;
    }

    if (_speech.isListening) {
      await _speech.stop();
    }
    if (!await _ensureSpeechReady()) return;

    _dictationBaseText = controller.text.trimRight();
    if (mounted) {
      setState(() {
        _dictatingController = controller;
        _dictatingLabel = label;
      });
    }

    try {
      await _speech.listen(
        localeId: _speechLocaleId,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        onResult: (result) {
          if (!mounted || !identical(_dictatingController, controller)) return;
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          final separator = _dictationBaseText.isEmpty ? '' : ' ';
          final nextText = '$_dictationBaseText$separator$words';
          controller.value = TextEditingValue(
            text: nextText,
            selection: TextSelection.collapsed(offset: nextText.length),
          );
          if (result.finalResult && mounted) {
            setState(() {
              _dictatingController = null;
              _dictatingLabel = null;
            });
          } else {
            setState(() {});
          }
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dictatingController = null;
        _dictatingLabel = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de démarrer la dictée : $e')),
      );
    }
  }

  void _changed() {
    if (_restoring) return;
'''
if "Future<bool> _ensureSpeechReady()" not in text:
    text = replace_once(text, methods_anchor, methods, "Practice dictation methods")

header_old = """                  _FormHeader(\n                      patientNumber: number,\n                      syncLabel: _syncLabel,\n                      pending: widget.existing?.pendingSync == true),\n                  const SizedBox(height: 16),\n"""
header_new = """                  _FormHeader(\n                      patientNumber: number,\n                      syncLabel: _syncLabel,\n                      pending: widget.existing?.pendingSync == true),\n                  const SizedBox(height: 10),\n                  const _PracticeNotice(\n                    icon: Icons.mic_rounded,\n                    text:\n                        'Dictée vocale : touchez le micro d’une rubrique puis dictez. Le texte s’ajoute à ce qui est déjà saisi. GardeFlow ne conserve aucun enregistrement audio.',\n                  ),\n                  const SizedBox(height: 16),\n"""
if "Dictée vocale : touchez le micro" not in text:
    text = replace_once(text, header_old, header_new, "Practice dictation notice")

chief_old = """                      _field(_chiefComplaint, 'Motif principal (facultatif)',\n                          icon: Icons.short_text_rounded),\n"""
chief_new = """                      _field(\n                        _chiefComplaint,\n                        'Motif principal (facultatif)',\n                        icon: Icons.short_text_rounded,\n                        voice: true,\n                        voiceLabel: 'Motif principal',\n                      ),\n"""
if "voiceLabel: 'Motif principal'" not in text:
    text = replace_once(text, chief_old, chief_new, "Chief complaint dictation")

clinical_old = """  Widget _clinicalSection(\n          String title, TextEditingController controller, String hint) =>\n      _formSection(\n        title: title,\n        children: [_field(controller, hint, lines: 4)],\n      );\n"""
clinical_new = """  Widget _clinicalSection(\n          String title, TextEditingController controller, String hint) =>\n      _formSection(\n        title: title,\n        children: [\n          _field(\n            controller,\n            hint,\n            lines: 4,\n            voice: true,\n            voiceLabel: title.replaceAll(' *', ''),\n          ),\n        ],\n      );\n"""
if "voiceLabel: title.replaceAll(' *', '')" not in text:
    text = replace_once(text, clinical_old, clinical_new, "Clinical section dictation")

double_old_1 = """          _field(first, '$firstLabel…', lines: 2),\n"""
double_new_1 = """          _field(\n            first,\n            '$firstLabel…',\n            lines: 2,\n            voice: true,\n            voiceLabel: '$title · $firstLabel',\n          ),\n"""
if "voiceLabel: '$title · $firstLabel'" not in text:
    text = replace_once(text, double_old_1, double_new_1, "First history dictation")

double_old_2 = """          _field(second, '$secondLabel…', lines: 2),\n"""
double_new_2 = """          _field(\n            second,\n            '$secondLabel…',\n            lines: 2,\n            voice: true,\n            voiceLabel: '$title · $secondLabel',\n          ),\n"""
if "voiceLabel: '$title · $secondLabel'" not in text:
    text = replace_once(text, double_old_2, double_new_2, "Second history dictation")

field_old = """  Widget _field(TextEditingController controller, String hint,\n          {IconData? icon, int lines = 1, TextInputType? keyboardType}) =>\n      TextFormField(\n        controller: controller,\n        maxLines: lines,\n        keyboardType: keyboardType ??\n            (lines > 1 ? TextInputType.multiline : TextInputType.text),\n        style: const TextStyle(color: Colors.white, fontSize: 13),\n        decoration: _practiceInputDecoration(hint, icon),\n      );\n"""
field_new = """  Widget _field(\n    TextEditingController controller,\n    String hint, {\n    IconData? icon,\n    int lines = 1,\n    TextInputType? keyboardType,\n    bool voice = false,\n    String? voiceLabel,\n  }) {\n    final active = voice &&\n        identical(_dictatingController, controller) &&\n        _speech.isListening;\n    return TextFormField(\n      controller: controller,\n      maxLines: lines,\n      keyboardType: keyboardType ??\n          (lines > 1 ? TextInputType.multiline : TextInputType.text),\n      style: const TextStyle(color: Colors.white, fontSize: 13),\n      decoration: _practiceInputDecoration(hint, icon).copyWith(\n        helperText: active\n            ? 'Écoute en cours · appuyez de nouveau sur le micro pour arrêter'\n            : null,\n        helperStyle: const TextStyle(\n          color: PracticeColors.accent,\n          fontSize: 10.5,\n          fontWeight: FontWeight.w700,\n        ),\n        suffixIcon: voice\n            ? IconButton(\n                tooltip: active\n                    ? 'Arrêter la dictée'\n                    : 'Dicter ${voiceLabel ?? hint}',\n                onPressed: _speechInitializing\n                    ? null\n                    : () => _toggleDictation(\n                          controller,\n                          voiceLabel ?? hint,\n                        ),\n                icon: _speechInitializing &&\n                        identical(_dictatingController, controller)\n                    ? const SizedBox(\n                        width: 18,\n                        height: 18,\n                        child: CircularProgressIndicator(\n                          strokeWidth: 2,\n                          color: PracticeColors.accent,\n                        ),\n                      )\n                    : Icon(\n                        active ? Icons.stop_circle_rounded : Icons.mic_rounded,\n                        color: active\n                            ? PracticeColors.hospitalized\n                            : PracticeColors.accent,\n                      ),\n              )\n            : null,\n      ),\n    );\n  }\n"""
if "bool voice = false" not in text:
    text = replace_once(text, field_old, field_new, "Voice-enabled Practice field")

practice.write_text(text, encoding="utf-8")

print("Practice voice dictation patch applied")
