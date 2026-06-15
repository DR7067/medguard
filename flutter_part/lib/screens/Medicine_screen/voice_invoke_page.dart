import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'add_reminder.dart';

const Color kVoicePrimaryColor = Color(0xFF2BB0A8);
const Color kVoicePrimaryLightColor = Color(0xFF4ACCC9);
const Color kVoiceBackgroundColor = Color(0xFFF9FAFB);
const String kReminderVoiceLanguageKey = 'reminder_voice_language';

class VoiceInvokeReminderPage extends StatefulWidget {
  final String medicine;
  final List<ReminderDose> existingReminders;
  final DateTime? startDate;
  final DateTime? endDate;
  final void Function(
    List<ReminderDose> doses,
    DateTime? start,
    DateTime? end,
  ) onSave;

  const VoiceInvokeReminderPage({
    super.key,
    required this.medicine,
    required this.existingReminders,
    this.startDate,
    this.endDate,
    required this.onSave,
  });

  @override
  State<VoiceInvokeReminderPage> createState() => _VoiceInvokeReminderPageState();
}

class _VoiceInvokeReminderPageState extends State<VoiceInvokeReminderPage> {
  late List<ReminderDose> doses;
  late List<ReminderDose> pastDoses;

  TimeOfDay? selectedTime;
  final TextEditingController instructionController = TextEditingController();
  final TextEditingController durationController = TextEditingController();

  late DateTime startDate;
  DateTime? endDate;

  ReminderDose? editingDose;

  late FlutterTts flutterTts;
  String _voiceLanguage = 'en-IN';

  @override
  void initState() {
    super.initState();

    flutterTts = FlutterTts();
    flutterTts.setSpeechRate(0.5);
    flutterTts.setVolume(1.0);
    flutterTts.setPitch(1.0);
    flutterTts.awaitSpeakCompletion(true);
    _loadVoiceLanguage();

    doses = widget.existingReminders
        .where((d) => !d.isDone)
        .map(
          (e) => ReminderDose(
            time: e.time,
            instruction: e.instruction,
            isDone: e.isDone,
          ),
        )
        .toList();

    pastDoses = widget.existingReminders
        .where((d) => d.isDone)
        .map(
          (e) => ReminderDose(
            time: e.time,
            instruction: e.instruction,
            isDone: e.isDone,
          ),
        )
        .toList();

    startDate = widget.startDate ?? DateTime.now();
    endDate = widget.endDate;

    if (endDate != null) {
      durationController.text =
          endDate!.difference(startDate).inDays.toString();
    }

    _sortDoses();
  }

  Future<void> _loadVoiceLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(kReminderVoiceLanguageKey) ?? 'en-IN';
    final shortCode = savedLanguage.split('-').first;
    final candidates = <String>[savedLanguage, shortCode, 'en-IN'];

    for (final code in candidates) {
      final available = await flutterTts.isLanguageAvailable(code);
      if (available == true) {
        if (!mounted) return;
        setState(() => _voiceLanguage = code);
        await flutterTts.setLanguage(_voiceLanguage);
        return;
      }
    }

    if (!mounted) return;
    setState(() => _voiceLanguage = 'en-IN');
    await flutterTts.setLanguage(_voiceLanguage);
  }

  @override
  void dispose() {
    instructionController.dispose();
    durationController.dispose();
    flutterTts.stop();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  int _minutes(TimeOfDay t) => (t.hour * 60) + t.minute;

  void _sortDoses() {
    doses.sort((a, b) => _minutes(a.time).compareTo(_minutes(b.time)));
    pastDoses.sort((a, b) => _minutes(a.time).compareTo(_minutes(b.time)));
  }

  String get _languageCode => _voiceLanguage.split('-').first.toLowerCase();

  String _singleDoseSpeech(String medicine, String time) {
    switch (_languageCode) {
      case 'hi':
        return '$medicine का समय $time है। कृपया दवा लें।';
      case 'mr':
        return '$medicine ची वेळ $time झाली आहे. कृपया औषध घ्या.';
      case 'ta':
        return '$medicine எடுத்துக்கொள்ளும் நேரம் $time. தயவுசெய்து மருந்து எடுத்துக்கொள்ளுங்கள்.';
      case 'te':
        return '$medicine తీసుకునే సమయం $time. దయచేసి మందు తీసుకోండి.';
      case 'bn':
        return '$medicine খাওয়ার সময় $time। দয়া করে ওষুধ খান।';
      default:
        return 'It is time to take $medicine at $time';
    }
  }

  String _allDosesIntroSpeech(String medicine) {
    switch (_languageCode) {
      case 'hi':
        return '$medicine के रिमाइंडर समय ये हैं।';
      case 'mr':
        return '$medicine च्या स्मरण वेळा या आहेत.';
      case 'ta':
        return '$medicine க்கான நினைவூட்டல் நேரங்கள் இவை.';
      case 'te':
        return '$medicine కోసం గుర్తు చేసే సమయాలు ఇవి.';
      case 'bn':
        return '$medicine এর রিমাইন্ডার সময়গুলো এগুলো।';
      default:
        return 'Your reminder times for $medicine are.';
    }
  }

  Future<void> speakDose(ReminderDose dose) async {
    await flutterTts.stop();

    final time = dose.time.format(context);
    final medicine = widget.medicine;

    await flutterTts.setLanguage(_voiceLanguage);
    await flutterTts.speak(_singleDoseSpeech(medicine, time));
  }

  Future<void> _speakAllDoses() async {
    if (doses.isEmpty) return;

    await flutterTts.stop();
    await flutterTts.setLanguage(_voiceLanguage);
    await flutterTts.speak(_allDosesIntroSpeech(widget.medicine));

    for (final dose in doses) {
      final time = dose.time.format(context);
      if (dose.instruction.trim().isEmpty) {
        await flutterTts.speak(time);
      } else {
        await flutterTts.speak('$time. ${dose.instruction}');
      }
    }
  }

  Future<void> pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t != null) setState(() => selectedTime = t);
  }

  Future<void> pickStartDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        startDate = d;
        if (endDate != null && endDate!.isBefore(startDate)) {
          endDate = startDate;
        }
        calculateEndDateFromDuration();
      });
      widget.onSave([...doses, ...pastDoses], startDate, endDate);
    }
  }

  Future<void> pickEndDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: endDate ?? startDate.add(const Duration(days: 1)),
      firstDate: startDate,
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        endDate = d;
        durationController.text =
            endDate!.difference(startDate).inDays.toString();
      });
      widget.onSave([...doses, ...pastDoses], startDate, endDate);
    }
  }

  void calculateEndDateFromDuration() {
    final days = int.tryParse(durationController.text) ?? 0;
    if (days > 0) {
      endDate = startDate.add(Duration(days: days));
    }
  }

  void addOrUpdateDose() {
    if (selectedTime == null) return;

    if (editingDose != null) {
      editingDose!.time = selectedTime!;
      editingDose!.instruction = instructionController.text.trim();
      doses.add(editingDose!);
      editingDose = null;
    } else {
      doses.add(
        ReminderDose(
          time: selectedTime!,
          instruction: instructionController.text.trim(),
        ),
      );
    }

    _sortDoses();
    selectedTime = null;
    instructionController.clear();
    widget.onSave([...doses, ...pastDoses], startDate, endDate);
    setState(() {});
  }

  void openBottomSheet({ReminderDose? dose}) {
    if (dose != null) {
      editingDose = dose;
      selectedTime = dose.time;
      instructionController.text = dose.instruction;
      doses.remove(dose);
    } else {
      editingDose = null;
      selectedTime = null;
      instructionController.clear();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text(
                  selectedTime == null
                      ? 'Pick Time'
                      : selectedTime!.format(context),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kVoicePrimaryLightColor,
                ),
                onPressed: pickTime,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: instructionController,
                decoration: const InputDecoration(
                  labelText: 'Instruction (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  addOrUpdateDose();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(45),
                  backgroundColor: kVoicePrimaryColor,
                ),
                child:
                    Text(editingDose != null ? 'Update Reminder' : 'Add Reminder'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void deleteDose(ReminderDose dose) {
    doses.remove(dose);
    pastDoses.add(dose);
    _sortDoses();
    widget.onSave([...doses, ...pastDoses], startDate, endDate);
    setState(() {});
  }

  void markDone(ReminderDose dose, bool val) {
    dose.isDone = val;
    if (val) {
      doses.remove(dose);
      pastDoses.add(dose);
    }
    _sortDoses();
    widget.onSave([...doses, ...pastDoses], startDate, endDate);
    setState(() {});
  }

  void reactivateDose(ReminderDose dose) {
    pastDoses.remove(dose);
    dose.isDone = false;
    doses.add(dose);
    _sortDoses();
    widget.onSave([...doses, ...pastDoses], startDate, endDate);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVoiceBackgroundColor,
      appBar: AppBar(
        title: Text('Voice Invoke - ${widget.medicine}'),
        backgroundColor: kVoicePrimaryColor,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kVoicePrimaryColor, kVoicePrimaryLightColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reminder Window',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickStartDate,
                            icon: const Icon(Icons.calendar_today),
                            label: Text('Start: ${_formatDate(startDate)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickEndDate,
                            icon: const Icon(Icons.event),
                            label: Text(
                              endDate == null
                                  ? 'Pick End Date'
                                  : 'End: ${_formatDate(endDate!)}',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: durationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Duration (days)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        setState(calculateEndDateFromDuration);
                        widget.onSave([...doses, ...pastDoses], startDate, endDate);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Reminder Times Set',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => openBottomSheet(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kVoicePrimaryColor,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: doses.isEmpty
                ? Center(
                    child: Text(
                      'No reminder times set yet',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                    itemCount: doses.length,
                    itemBuilder: (context, index) {
                      final dose = doses[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            backgroundColor:
                                kVoicePrimaryLightColor.withOpacity(0.22),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: kVoicePrimaryColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            dose.time.format(context),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          subtitle: dose.instruction.isEmpty
                              ? null
                              : Text(dose.instruction),
                          trailing: Wrap(
                            spacing: 0,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.record_voice_over,
                                  color: kVoicePrimaryColor,
                                ),
                                onPressed: () => speakDose(dose),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: kVoicePrimaryColor,
                                ),
                                onPressed: () => openBottomSheet(dose: dose),
                              ),
                              Checkbox(
                                value: dose.isDone,
                                onChanged: (v) => markDone(dose, v ?? false),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (pastDoses.isNotEmpty)
            ExpansionTile(
              title: const Text('Past Reminders'),
              children: pastDoses
                  .map(
                    (dose) => ListTile(
                      title: Text(dose.time.format(context)),
                      subtitle:
                          dose.instruction.isEmpty ? null : Text(dose.instruction),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.record_voice_over,
                              color: kVoicePrimaryColor,
                            ),
                            onPressed: () => speakDose(dose),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.replay,
                              color: kVoicePrimaryColor,
                            ),
                            onPressed: () => reactivateDose(dose),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: doses.isEmpty ? null : _speakAllDoses,
                      icon: const Icon(Icons.volume_up),
                      label: const Text('Voice Invoke All'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kVoicePrimaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
