from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"Anchor not found: {label}")
    if text.count(old) != 1:
        raise SystemExit(f"Anchor is not unique ({text.count(old)}): {label}")
    return text.replace(old, new, 1)


root = Path(__file__).resolve().parents[2]
practice_path = root / "source/lib/screens/practice_screen.dart"
ios_path = root / "source/tool/configure_ios.dart"

practice = practice_path.read_text(encoding="utf-8")

old_state = """  TextEditingController? _dictatingController;
  String? _dictatingLabel;
  String _dictationBaseText = '';
  bool _speechReady = false;
  bool _speechInitializing = false;
  String? _speechLocaleId;
  final _age = TextEditingController();
"""
new_state = """  TextEditingController? _dictatingController;
  String? _dictatingLabel;
  bool _speechReady = false;
  bool _speechInitializing = false;
  String? _speechLocaleId;
  Timer? _speechRestartTimer;
  bool _dictationRequested = false;
  bool _speechStarting = false;
  int _speechSession = 0;
  int _consecutiveSpeechErrors = 0;

  static const List<String> _medicalSpeechHints = <String>[
    'douleur abdominale',
    'épigastre',
    'hypochondre droit',
    'hypochondre gauche',
    'fosse iliaque droite',
    'fosse iliaque gauche',
    'point de McBurney',
    'défense abdominale',
    'contracture abdominale',
    'nausées',
    'vomissements',
    'diarrhée',
    'constipation',
    'dyspnée',
    'dysurie',
    'hématurie',
    'hématémèse',
    'méléna',
    'tachycardie',
    'hypotension',
    'hypertension',
    'saturation',
    'auscultation',
    'appendicite',
    'cholécystite',
    'pancréatite',
    'péritonite',
    'occlusion intestinale',
    'scanner abdominal',
    'échographie abdominale',
    'TDM',
    'IRM',
    'ECG',
    'CRP',
    'leucocytes',
    'hémoglobine',
    'créatinine',
    'natrémie',
    'kaliémie',
    'troponine',
    'conduite à tenir',
  ];
  final _age = TextEditingController();
"""
practice = replace_once(practice, old_state, new_state, "speech state")

old_dispose = """  void dispose() {
    _autosave?.cancel();
    if (_speech.isListening) {
      unawaited(_speech.cancel());
    }
"""
new_dispose = """  void dispose() {
    _autosave?.cancel();
    _speechRestartTimer?.cancel();
    _dictationRequested = false;
    _speechSession++;
    if (_speech.isListening) {
      unawaited(_speech.cancel());
    }
"""
practice = replace_once(practice, old_dispose, new_dispose, "dispose speech cleanup")

new_speech_core = r'''  Future<bool> _ensureSpeechReady() async {
    if (_speechReady) return true;
    if (_speechInitializing) return false;
    if (mounted) setState(() => _speechInitializing = true);
    try {
      final available = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
        finalTimeout: const Duration(seconds: 3),
        options: kIsWeb ? <stt.SpeechConfigOption>[stt.SpeechToText.webDoNotAggregate] : null,
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

      final locales = await _speech.locales();
      final systemLocale = await _speech.systemLocale();

      String normalizedLocale(String value) =>
          value.toLowerCase().replaceAll('-', '_');

      String? exactLocale(String wanted) {
        final normalizedWanted = normalizedLocale(wanted);
        for (final locale in locales) {
          if (normalizedLocale(locale.localeId) == normalizedWanted) {
            return locale.localeId;
          }
        }
        return null;
      }

      String? french;
      final systemId = systemLocale?.localeId;
      if (systemId != null && normalizedLocale(systemId).startsWith('fr')) {
        french = exactLocale(systemId);
      }
      french ??= exactLocale('fr_FR');
      french ??= exactLocale('fr_MA');
      if (french == null) {
        for (final locale in locales) {
          if (normalizedLocale(locale.localeId).startsWith('fr')) {
            french = locale.localeId;
            break;
          }
        }
      }
      _speechLocaleId = french ?? systemId;
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

  void _handleSpeechStatus(String status) {
    if (mounted) setState(() {});
    if (!_dictationRequested) return;
    final normalized = status.toLowerCase();
    if (normalized == stt.SpeechToText.doneStatus.toLowerCase() ||
        normalized == stt.SpeechToText.notListeningStatus.toLowerCase()) {
      _scheduleSpeechRestart();
    }
  }

  bool _isRecoverableSpeechError(String error) {
    final normalized = error.toLowerCase();
    return normalized.contains('no_match') ||
        normalized.contains('speech_timeout') ||
        normalized.contains('retry') ||
        normalized.contains('busy') ||
        normalized.contains('network_timeout') ||
        normalized.contains('server_disconnected') ||
        normalized == 'error_network' ||
        normalized == 'error_server';
  }

  String _friendlySpeechError(String error) {
    final normalized = error.toLowerCase();
    if (normalized.contains('permission')) {
      return 'Microphone non autorisé. Activez l’accès au micro pour GardeFlow dans les réglages de l’appareil.';
    }
    if (normalized.contains('language_not_supported') ||
        normalized.contains('language_unavailable')) {
      return 'La reconnaissance vocale française n’est pas disponible sur cet appareil. Installez ou activez le français dans les réglages de reconnaissance vocale.';
    }
    if (normalized.contains('recognizer_disabled')) {
      return 'La reconnaissance vocale est désactivée sur cet appareil.';
    }
    if (normalized.contains('too_many_requests')) {
      return 'Le service de reconnaissance vocale reçoit trop de requêtes. Réessayez dans quelques instants.';
    }
    if (normalized.contains('network')) {
      return 'La reconnaissance vocale a perdu la connexion. Vérifiez le réseau puis relancez le micro.';
    }
    return 'Dictée interrompue : ${error.replaceAll('_', ' ')}';
  }

  void _handleSpeechError(dynamic error) {
    final message = error.errorMsg?.toString() ?? error.toString();
    if (_dictationRequested && _isRecoverableSpeechError(message)) {
      _consecutiveSpeechErrors++;
      if (_consecutiveSpeechErrors <= 4) {
        if (_speech.isListening) unawaited(_speech.cancel());
        final delay = Duration(
          milliseconds: 350 + ((_consecutiveSpeechErrors - 1) * 250),
        );
        _scheduleSpeechRestart(delay: delay);
        return;
      }
    }

    _dictationRequested = false;
    _speechRestartTimer?.cancel();
    _speechSession++;
    if (!mounted) return;
    setState(() {
      _dictatingController = null;
      _dictatingLabel = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_friendlySpeechError(message))),
    );
  }

  String _normalizeSpeechTranscript(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(
          RegExp(r'\s+([,.;:!?…])'),
          (match) => match.group(1)!,
        );
    if (!kIsWeb || cleaned.isEmpty) return cleaned;

    String keyOf(String token) => token.toLowerCase().replaceAll(
      RegExp(r'^[\s.,;:!?…]+|[\s.,;:!?…]+$'),
      '',
    );

    // Le mode webDoNotAggregate évite le principal bug de doublons de Chrome
    // Android. On conserve seulement une protection prudente contre la
    // répétition immédiate d’un bloc entier, sans supprimer les vrais mots
    // répétés (« très très », « non non », etc.).
    final tokens = cleaned.split(' ');
    var maxBlock = tokens.length ~/ 2;
    if (maxBlock > 16) maxBlock = 16;
    for (var block = maxBlock; block >= 3; block--) {
      var index = 0;
      while (index + (block * 2) <= tokens.length) {
        var identicalBlocks = true;
        for (var offset = 0; offset < block; offset++) {
          if (keyOf(tokens[index + offset]) !=
              keyOf(tokens[index + block + offset])) {
            identicalBlocks = false;
            break;
          }
        }
        if (identicalBlocks) {
          tokens.removeRange(index + block, index + (block * 2));
        } else {
          index++;
        }
      }
    }

    return tokens.join(' ').trim();
  }

  String _combineSpeechSegments(String committed, String incoming) {
    final current = committed.trim();
    final next = incoming.trim();
    if (current.isEmpty) return next;
    if (next.isEmpty) return current;

    final currentKey = current.toLowerCase();
    final nextKey = next.toLowerCase();
    if (nextKey.startsWith('$currentKey ')) return next;
    return '$current $next';
  }

  void _scheduleSpeechRestart({
    Duration delay = const Duration(milliseconds: 450),
  }) {
    if (!_dictationRequested || !mounted) return;
    final controller = _dictatingController;
    final label = _dictatingLabel;
    if (controller == null || label == null) return;

    _speechRestartTimer?.cancel();
    _speechRestartTimer = Timer(delay, () {
      if (!mounted ||
          !_dictationRequested ||
          !identical(_dictatingController, controller)) {
        return;
      }
      unawaited(_startSpeechSession(controller, label));
    });
  }

  Future<void> _startSpeechSession(
    TextEditingController controller,
    String label,
  ) async {
    if (!mounted ||
        !_dictationRequested ||
        !identical(_dictatingController, controller) ||
        _speechStarting ||
        _speech.isListening) {
      return;
    }

    _speechRestartTimer?.cancel();
    _speechStarting = true;
    final session = ++_speechSession;
    final sessionBase = controller.text.trimRight();
    var committedSpeech = '';
    String? lastFinalChunk;
    DateTime? lastFinalAt;

    try {
      final started = await _speech.listen(
        onResult: (result) {
          if (!mounted ||
              !_dictationRequested ||
              session != _speechSession ||
              !identical(_dictatingController, controller)) {
            return;
          }

          final words = _normalizeSpeechTranscript(result.recognizedWords);
          if (words.isEmpty) return;
          _consecutiveSpeechErrors = 0;
          _speech.changePauseFor(Duration(seconds: kIsWeb ? 5 : 7));

          var speechForDisplay = words;
          if (result.finalResult) {
            final now = DateTime.now();
            final rapidDuplicate =
                lastFinalChunk != null &&
                lastFinalChunk!.toLowerCase() == words.toLowerCase() &&
                lastFinalAt != null &&
                now.difference(lastFinalAt!).inMilliseconds < 1200;
            if (!rapidDuplicate) {
              committedSpeech = _combineSpeechSegments(committedSpeech, words);
              lastFinalChunk = words;
              lastFinalAt = now;
            }
            speechForDisplay = committedSpeech;
          } else if (committedSpeech.isNotEmpty) {
            speechForDisplay = _combineSpeechSegments(committedSpeech, words);
          }

          if (speechForDisplay.isEmpty) return;
          final separator = sessionBase.isEmpty ? '' : ' ';
          final nextText = '$sessionBase$separator$speechForDisplay'.trimRight();
          controller.value = TextEditingValue(
            text: nextText,
            selection: TextSelection.collapsed(offset: nextText.length),
          );
          setState(() {});
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: _speechLocaleId,
          listenFor: const Duration(minutes: 3),
          pauseFor: Duration(seconds: kIsWeb ? 7 : 10),
          partialResults: true,
          cancelOnError: false,
          onDevice: false,
          listenMode: stt.ListenMode.dictation,
          autoPunctuation: true,
          enableHapticFeedback: false,
          contextualPhrases: _medicalSpeechHints,
        ),
      );
      if (started == false && _dictationRequested) {
        _scheduleSpeechRestart();
      }
    } catch (e) {
      if (!mounted ||
          !_dictationRequested ||
          session != _speechSession ||
          !identical(_dictatingController, controller)) {
        return;
      }
      _consecutiveSpeechErrors++;
      if (_consecutiveSpeechErrors <= 4) {
        _scheduleSpeechRestart(
          delay: Duration(milliseconds: 400 + (_consecutiveSpeechErrors * 250)),
        );
      } else {
        _dictationRequested = false;
        setState(() {
          _dictatingController = null;
          _dictatingLabel = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de relancer la dictée : $e')),
        );
      }
    } finally {
      _speechStarting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _stopDictation() async {
    _dictationRequested = false;
    _speechRestartTimer?.cancel();
    _speechSession++;
    if (_speech.isListening) await _speech.stop();
    if (!mounted) return;
    setState(() {
      _dictatingController = null;
      _dictatingLabel = null;
    });
  }

  Future<void> _toggleDictation(
    TextEditingController controller,
    String label,
  ) async {
    if (_speechInitializing || _speechStarting) return;

    if (identical(_dictatingController, controller) && _dictationRequested) {
      await _stopDictation();
      return;
    }

    if (_dictationRequested || _speech.isListening) {
      await _stopDictation();
    }
    if (!await _ensureSpeechReady()) return;

    _consecutiveSpeechErrors = 0;
    _dictationRequested = true;
    if (mounted) {
      setState(() {
        _dictatingController = controller;
        _dictatingLabel = label;
      });
    }
    await _startSpeechSession(controller, label);
  }
'''

speech_pattern = re.compile(
    r"  Future<bool> _ensureSpeechReady\(\) async \{.*?\n  void _changed\(\) \{",
    re.S,
)
match = speech_pattern.search(practice)
if not match:
    raise SystemExit("Speech core block not found")
practice = practice[: match.start()] + new_speech_core + "\n  void _changed() {" + practice[match.end() :]

old_active = """    final active =
        voice &&
        identical(_dictatingController, controller) &&
        _speech.isListening;
"""
new_active = """    final active =
        voice &&
        identical(_dictatingController, controller) &&
        _dictationRequested;
    final activelyListening = active && _speech.isListening;
"""
practice = replace_once(practice, old_active, new_active, "voice field active state")

old_helper = """        helperText: active
            ? 'Écoute en cours · appuyez de nouveau sur le micro pour arrêter'
            : null,
"""
new_helper = """        helperText: active
            ? (activelyListening
                  ? 'Écoute en cours · continuez à parler · touchez le micro pour arrêter'
                  : 'Dictée active · reprise automatique de l’écoute…')
            : null,
"""
practice = replace_once(practice, old_helper, new_helper, "voice helper text")

practice_path.write_text(practice, encoding="utf-8")

ios = ios_path.read_text(encoding="utf-8")
anchor = """  info = ensurePlistString(
    info,
    'NSPhotoLibraryAddUsageDescription',
    'GardeFlow peut enregistrer un document ou une image que vous choisissez explicitement.',
  );
  info = ensureBackgroundModes(info);
"""
replacement = """  info = ensurePlistString(
    info,
    'NSPhotoLibraryAddUsageDescription',
    'GardeFlow peut enregistrer un document ou une image que vous choisissez explicitement.',
  );
  info = ensurePlistString(
    info,
    'NSMicrophoneUsageDescription',
    'GardeFlow utilise le microphone uniquement lorsque vous activez la dictée vocale d’une observation clinique.',
  );
  info = ensurePlistString(
    info,
    'NSSpeechRecognitionUsageDescription',
    'GardeFlow utilise la reconnaissance vocale pour transcrire, à votre demande, votre dictée dans les champs cliniques.',
  );
  info = ensureBackgroundModes(info);
"""
ios = replace_once(ios, anchor, replacement, "iOS speech permissions")
ios_path.write_text(ios, encoding="utf-8")

print("Voice dictation reliability patch applied.")
