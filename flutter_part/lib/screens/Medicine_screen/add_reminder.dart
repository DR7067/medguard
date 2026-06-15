import 'package:flutter/material.dart';
import 'reminder.dart';
import 'dart:async';
import 'package:flutter/services.dart';

const Color kPrimaryColor = Color(0xFF2563EB);
const Color kPrimaryDark = Color(0xFF1D4ED8);
const Color kLightBlue = Color(0xFF3B82F6);
const Color kBackground = Color(0xFFF6F8FC);

class ReminderDose {
  TimeOfDay time;
  String instruction;
  bool isDone;

  ReminderDose({
    required this.time,
    this.instruction = "",
    this.isDone = false,
  });
}

class AddReminderScreen extends StatefulWidget {
  final Reminder? existingReminder;

  const AddReminderScreen({super.key, this.existingReminder});

  @override
  State<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends State<AddReminderScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _intervalController = TextEditingController();

  String _selectedType = 'Tablet';
  List<TimeOfDay> _times = [];
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isInterval = false;
  TimeOfDay? _intervalStartTime;
  final List<String> _types = ['Tablet', 'Capsule', 'Syrup', 'Other'];

  static const MethodChannel _channel = MethodChannel(
    "medguard/alarm_scheduler",
  );

  @override
  void initState() {
    super.initState();
    if (widget.existingReminder != null) {
      final r = widget.existingReminder!;
      _nameController.text = r.medicineName;
      _selectedType = r.type;
      _dosageController.text = r.dosage;
      _notesController.text = r.notes ?? "";
      _startDate = r.startDate;
      _endDate = r.endDate;
      _isInterval = r.isInterval;
      if (r.isInterval) {
        _intervalController.text = r.intervalHours?.toString() ?? "";
        _intervalStartTime = r.intervalStartTime;
      } else {
        _times = List.from(r.times);
      }
    }
  }

  String _getUnit() {
    switch (_selectedType) {
      case 'Tablet':
        return "tab";
      case 'Capsule':
        return "cap";
      case 'Syrup':
        return "ml";
      default:
        return "";
    }
  }

  InputDecoration _inputStyle(String hint, double fontSize) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: fontSize * 0.9),
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(
        horizontal: fontSize,
        vertical: fontSize * 0.6,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fontSize * 0.6),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _sectionCard({required Widget child, double padding = 16}) {
    return Container(
      margin: EdgeInsets.only(bottom: padding),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(padding),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) setState(() => _times.add(picked));
  }

  Future<void> _pickIntervalStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) setState(() => _intervalStartTime = picked);
  }

  Future<void> _saveReminder() async {
    if (_nameController.text.isEmpty ||
        _dosageController.text.isEmpty ||
        _startDate == null ||
        _endDate == null ||
        (!_isInterval && _times.isEmpty) ||
        (_isInterval &&
            (_intervalStartTime == null || _intervalController.text.isEmpty))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields")),
      );
      return;
    }

    final reminder = Reminder(
      medicineName: _nameController.text,
      type: _selectedType,
      dosage: _dosageController.text,
      times: _isInterval ? [] : _times,
      startDate: _startDate!,
      endDate: _endDate!,
      notes: _notesController.text,
      isInterval: _isInterval,
      intervalHours: _isInterval
          ? int.tryParse(_intervalController.text)
          : null,
      intervalStartTime: _isInterval ? _intervalStartTime : null,
    );

    List<Map<String, dynamic>> alarms = [];

    if (_isInterval && _intervalStartTime != null) {
      DateTime next = DateTime(
        _startDate!.year,
        _startDate!.month,
        _startDate!.day,
        _intervalStartTime!.hour,
        _intervalStartTime!.minute,
      );
      final intervalMillis = int.tryParse(_intervalController.text) ?? 0;
      while (next.isBefore(_endDate!.add(const Duration(days: 1)))) {
        alarms.add({
          "id": next.millisecondsSinceEpoch ~/ 1000,
          "medicineName": reminder.medicineName,
          "dosage": reminder.dosage,
          "triggerAtMillis": next.millisecondsSinceEpoch,
        });
        next = next.add(Duration(hours: intervalMillis));
      }
    } else {
      for (var t in _times) {
        DateTime next = DateTime(
          _startDate!.year,
          _startDate!.month,
          _startDate!.day,
          t.hour,
          t.minute,
        );
        while (next.isBefore(_endDate!.add(const Duration(days: 1)))) {
          alarms.add({
            "id": next.millisecondsSinceEpoch ~/ 1000,
            "medicineName": reminder.medicineName,
            "dosage": reminder.dosage,
            "triggerAtMillis": next.millisecondsSinceEpoch,
          });
          next = next.add(const Duration(days: 1));
        }
      }
    }

    try {
      await _channel.invokeMethod("replaceReminderAlarms", {"alarms": alarms});
    } catch (e) {
      debugPrint("Failed to schedule alarms: $e");
    }

    if (!mounted) return;
    Navigator.pop(context, reminder);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final fontSize = width * 0.04; // scaled font

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kPrimaryDark,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.existingReminder == null ? "Add Reminder" : "Edit Reminder",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: fontSize,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(width * 0.03),
        child: Column(
          children: [
            /// Medicine Details
            _sectionCard(
              padding: width * 0.03,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Medicine Details",
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: height * 0.01),
                  TextField(
                    controller: _nameController,
                    style: TextStyle(fontSize: fontSize),
                    decoration: _inputStyle("Medicine Name", fontSize),
                  ),
                  SizedBox(height: height * 0.008),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedType,
                    decoration: _inputStyle("Type", fontSize),
                    items: _types
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t,
                              style: TextStyle(fontSize: fontSize),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => _selectedType = val!),
                  ),
                  SizedBox(height: height * 0.008),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dosageController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                          style: TextStyle(fontSize: fontSize),
                          decoration: _inputStyle("Dosage", fontSize),
                        ),
                      ),
                      SizedBox(width: width * 0.02),
                      Text(
                        _getUnit(),
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            /// Schedule
            _sectionCard(
              padding: width * 0.03,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Schedule",
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: height * 0.01),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isInterval = false),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: height * 0.015,
                            ),
                            decoration: BoxDecoration(
                              color: !_isInterval
                                  ? kPrimaryColor
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Specific Times",
                              style: TextStyle(
                                color: !_isInterval
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w600,
                                fontSize: fontSize * 0.9,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: width * 0.02),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isInterval = true),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: height * 0.015,
                            ),
                            decoration: BoxDecoration(
                              color: _isInterval
                                  ? kPrimaryColor
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Interval",
                              style: TextStyle(
                                color: _isInterval
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w600,
                                fontSize: fontSize * 0.9,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: height * 0.01),
                  if (_isInterval) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        "Start Time",
                        style: TextStyle(fontSize: fontSize),
                      ),
                      trailing: Text(
                        _intervalStartTime != null
                            ? _intervalStartTime!.format(context)
                            : "Select",
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: _pickIntervalStartTime,
                    ),
                    SizedBox(height: height * 0.008),
                    TextField(
                      controller: _intervalController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(fontSize: fontSize),
                      decoration: _inputStyle("Repeat every (hours)", fontSize),
                    ),
                  ] else ...[
                    Wrap(
                      spacing: 6,
                      children: _times
                          .map(
                            (t) => Chip(
                              label: Text(
                                t.format(context),
                                style: TextStyle(fontSize: fontSize * 0.9),
                              ),
                              backgroundColor: kPrimaryColor.withOpacity(0.1),
                              deleteIconColor: kPrimaryColor,
                              onDeleted: () => setState(() => _times.remove(t)),
                            ),
                          )
                          .toList(),
                    ),
                    SizedBox(height: height * 0.008),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kLightBlue,
                          padding: EdgeInsets.symmetric(
                            vertical: height * 0.015,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _pickTime,
                        child: Text(
                          "Add Time",
                          style: TextStyle(fontSize: fontSize),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            /// Dates
            _sectionCard(
              padding: width * 0.03,
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      "Start Date",
                      style: TextStyle(fontSize: fontSize),
                    ),
                    trailing: Text(
                      _startDate != null
                          ? "${_startDate!.day}/${_startDate!.month}/${_startDate!.year}"
                          : "Select",
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => _pickDate(true),
                  ),
                  Divider(),
                  ListTile(
                    title: Text(
                      "End Date",
                      style: TextStyle(fontSize: fontSize),
                    ),
                    trailing: Text(
                      _endDate != null
                          ? "${_endDate!.day}/${_endDate!.month}/${_endDate!.year}"
                          : "Select",
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => _pickDate(false),
                  ),
                ],
              ),
            ),

            /// Notes
            _sectionCard(
              padding: width * 0.03,
              child: TextField(
                controller: _notesController,
                maxLines: 3,
                style: TextStyle(fontSize: fontSize),
                decoration: _inputStyle("Notes (optional)", fontSize),
              ),
            ),

            SizedBox(height: height * 0.01),

            /// Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryDark,
                  padding: EdgeInsets.symmetric(vertical: height * 0.018),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _saveReminder,
                child: Text(
                  widget.existingReminder == null
                      ? "Save Reminder"
                      : "Update Reminder",
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
