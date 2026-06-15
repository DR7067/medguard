import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/reminder_alert_service.dart';

const Color kAlarmBgStart = Color(0xFF0C1030);
const Color kAlarmBgEnd = Color(0xFF171B42);
const Color kAlarmButton = Color(0xFF2A2F59);
const Color kTakenButton = Color(0xFF2BB0A8);
const String kReminderVoiceLanguageKey = 'reminder_voice_language';

class ReminderAlertScreen extends StatefulWidget {
  final List<DueReminderItem> dueItems;

  const ReminderAlertScreen({super.key, required this.dueItems});

  @override
  State<ReminderAlertScreen> createState() => _ReminderAlertScreenState();
}

class _ReminderAlertScreenState extends State<ReminderAlertScreen> {
  late FlutterTts _flutterTts;
  Timer? _repeatTimer;
  bool _isSnoozed = false;
  bool _ttsConfigured = false;
  String _voiceLanguage = 'en-IN';
  int _speakCount = 0;
  static const int maxSpeaks = 4;

  @override
  void initState() {
    super.initState();
    _flutterTts = FlutterTts();
    _flutterTts.setVolume(1.0);
    _flutterTts.awaitSpeakCompletion(true);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadVoiceLanguage();
      if (!mounted) return;
      _startRepeatingVoice();
    });
  }

  Future<void> _loadVoiceLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(kReminderVoiceLanguageKey) ?? 'en-IN';
    final shortCode = savedLanguage.split('-').first;
    final candidates = <String>[savedLanguage, shortCode, 'en-IN'];

    for (final code in candidates) {
      final available = await _flutterTts.isLanguageAvailable(code);
      if (available == true) {
        _voiceLanguage = code;
        await _configureVoice();
        return;
      }
    }

    _voiceLanguage = 'en-IN';
    await _configureVoice();
  }

  String get _languageCode => _voiceLanguage.split('-').first.toLowerCase();

  String _localizeMedicalTerms(String input) {
    return input.trim();
  }

  Future<void> _configureVoice() async {
    await _setBestAvailableVoice();
    _ttsConfigured = true;
  }

  Future<void> _setBestAvailableVoice() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices is! List) return;

      Map<dynamic, dynamic>? selected;
      final localePrefix = _voiceLanguage.toLowerCase();
      final langPrefix = _languageCode;

      for (final voice in voices) {
        if (voice is! Map) continue;
        final locale = (voice['locale'] ?? '').toString().toLowerCase();
        if (locale == localePrefix) {
          selected = voice;
          break;
        }
      }

      selected ??= voices.cast<dynamic>().whereType<Map>().firstWhere((voice) {
        final locale = (voice['locale'] ?? '').toString().toLowerCase();
        return locale.startsWith(langPrefix);
      }, orElse: () => <dynamic, dynamic>{});

      if (selected.isEmpty) return;

      final name = selected['name'];
      final locale = selected['locale'];
      if (name == null || locale == null) return;

      await _flutterTts.setVoice(<String, String>{
        'name': name.toString(),
        'locale': locale.toString(),
      });
    } catch (_) {
      // Keep language-level fallback if voice enumeration fails.
    }
  }

  String _alarmIntroText() {
    switch (_languageCode) {
      case 'hi':
        return 'दवा लेने का समय हो गया है।';
      case 'mr':
        return 'औषध घेण्याची वेळ झाली आहे.';
      default:
        return 'It is time to take your medicine.';
    }
  }

  String _medicineLabel(String medicine, String type) {
    final med = medicine
        .trim(); // Use medicine name as-is, without any translation or localization
    String suffix;
    switch (_languageCode) {
      case 'hi':
        suffix = 'दवा';
        break;
      case 'mr':
        suffix = 'औषध';
        break;
      default:
        suffix = 'medicine';
    }
    if (med.isEmpty) return suffix;
    return '$med $suffix';
  }

  String _medicineSuffix(String type) {
    switch (_languageCode) {
      case 'hi':
        return 'दवा';
      case 'mr':
        return 'औषध';
      default:
        return 'medicine';
    }
  }

  String _takeMedicineText(DueReminderItem item) {
    final medName = item.reminder.medicineName.trim();
    final suffix = _medicineSuffix(item.reminder.type);
    final med = medName.isEmpty ? suffix : '$medName $suffix';
    switch (_languageCode) {
      case 'hi':
        return 'कृपया $med ${item.reminder.dosage} अभी लें।';
      case 'mr':
        return 'कृपया $med ${item.reminder.dosage} आत्ता घ्या.';
      default:
        return 'Please take $med, ${item.reminder.dosage}, now.';
    }
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    _isSnoozed = true;
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _speakAll() async {
    if (widget.dueItems.isEmpty) return;
    if (_isSnoozed) return;
    if (_speakCount >= maxSpeaks) return;

    _speakCount++;

    await _flutterTts.stop();
    if (!_ttsConfigured) {
      await _configureVoice();
    }

    final message =
        '${_alarmIntroText()} ${_takeMedicineText(widget.dueItems.first)}';
    await _flutterTts.speak(message);
  }

  void _startRepeatingVoice() {
    _speakCount = 0;
    _repeatTimer?.cancel();
    _speakAll();
    _scheduleNextSpeak();
  }

  void _scheduleNextSpeak() {
    if (_speakCount >= maxSpeaks) return;
    _repeatTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      _speakAll();
      _scheduleNextSpeak();
    });
  }

  void _closeAlarm(String action) {
    _isSnoozed = true;
    _repeatTimer?.cancel();
    _flutterTts.stop();
    Navigator.of(context).pop(action);
  }

  Future<void> _onSnoozePressed() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Snoozed for 10 mins'),
        duration: Duration(milliseconds: 1400),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _closeAlarm('snooze');
  }

  String _reminderLine() {
    if (widget.dueItems.length == 1) {
      final item = widget.dueItems.first;
      final medLabel = _medicineLabel(
        item.reminder.medicineName,
        item.reminder.type,
      );
      return '$medLabel - ${item.reminder.dosage}';
    }

    final names = widget.dueItems
        .map((e) => _medicineLabel(e.reminder.medicineName, e.reminder.type))
        .toSet();
    return '${widget.dueItems.length} medicines: ${names.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final displayTime = widget.dueItems.isNotEmpty
        ? widget.dueItems.first.time.format(context)
        : TimeOfDay.fromDateTime(DateTime.now()).format(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: kAlarmBgStart,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kAlarmBgStart, kAlarmBgEnd],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -140,
                left: -120,
                child: Container(
                  width: 360,
                  height: 360,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.04),
                  ),
                ),
              ),
              Positioned(
                bottom: -180,
                right: -120,
                child: Container(
                  width: 380,
                  height: 380,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.03),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 96),
                    Text(
                      displayTime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Text(
                        _reminderLine(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _onSnoozePressed,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kAlarmButton,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(54),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: const Text(
                                'Snooze',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _closeAlarm('taken'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kTakenButton,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(54),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: const Text(
                                'Taken',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
