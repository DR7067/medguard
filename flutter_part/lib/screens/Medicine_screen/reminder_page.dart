import 'dart:async';
import 'package:flutter/material.dart';
import 'reminder.dart';

const Color kPrimaryColor = Color(0xFF2563EB);
const Color kPrimaryLight = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1D4ED8);
const Color kBackgroundColor = Color(0xFFF6F8FC);

class ReminderPage extends StatefulWidget {
  final List<Reminder> reminders;
  final Function(Reminder, int) onEdit;
  final Function(int) onDelete;
  final Function(int, DateTime) onReactivate;

  const ReminderPage({
    super.key,
    required this.reminders,
    required this.onEdit,
    required this.onDelete,
    required this.onReactivate,
  });

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  bool showActive = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startAutoCheck();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startAutoCheck() {
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      setState(() {}); // rebuild to update active/completed reminders
    });
  }

  bool _isReminderActive(Reminder r) {
    final now = DateTime.now();

    // If reminder ends before today, it's completed
    if (r.endDate.isBefore(DateTime(now.year, now.month, now.day))) {
      return false;
    }

    // If reminder ends today, check if all times have passed
    if (r.endDate.year == now.year &&
        r.endDate.month == now.month &&
        r.endDate.day == now.day) {
      // If any reminder time is still in future, keep it active
      for (var t in r.times) {
        final reminderTime = DateTime(
          now.year,
          now.month,
          now.day,
          t.hour,
          t.minute,
        );
        if (reminderTime.isAfter(now)) return true;
      }
      // All times passed => completed
      return false;
    }

    // Otherwise, still active
    return true;
  }

  String _reminderStatusText(Reminder r) {
    final now = DateTime.now();
    final daysLeft = r.endDate.difference(now).inDays;

    if (daysLeft == 0) {
      return "Completing soon"; // instead of "Ending today"
    } else if (daysLeft > 0) {
      return "$daysLeft day(s) remaining";
    } else {
      return "Completed";
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final activeReminders = <Map<String, dynamic>>[];
    final completedReminders = <Map<String, dynamic>>[];

    for (int i = 0; i < widget.reminders.length; i++) {
      final reminder = widget.reminders[i];
      final isActive = _isReminderActive(reminder);

      if (isActive) {
        activeReminders.add({"reminder": reminder, "index": i});
      } else {
        completedReminders.add({"reminder": reminder, "index": i});
      }
    }

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Column(
        children: [
          /// HEADER
          Container(
            padding: EdgeInsets.fromLTRB(width * 0.05, 50, width * 0.05, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryColor, kPrimaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Reminders",
                  style: TextStyle(
                    fontSize: width * 0.06,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Icon(Icons.lock_clock, color: Colors.white, size: width * 0.07),
              ],
            ),
          ),

          const SizedBox(height: 12),

          /// TOGGLE
          Padding(
            padding: EdgeInsets.symmetric(horizontal: width * 0.04),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => showActive = true),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: width * 0.03),
                        decoration: BoxDecoration(
                          color: showActive
                              ? kPrimaryColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Center(
                          child: Text(
                            "Active",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: width * 0.038,
                              color: showActive ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => showActive = false),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: width * 0.03),
                        decoration: BoxDecoration(
                          color: !showActive
                              ? kPrimaryColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Center(
                          child: Text(
                            "Completed",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: width * 0.038,
                              color: !showActive
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          /// REMINDER LIST
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(width * 0.04),
              children: [
                ...(showActive ? activeReminders : completedReminders).map(
                  (data) => _buildReminderCard(
                    data["reminder"],
                    data["index"],
                    showActive,
                    width,
                  ),
                ),
                if ((showActive && activeReminders.isEmpty) ||
                    (!showActive && completedReminders.isEmpty))
                  _buildEmptyState(width),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String formatDosage(Reminder r) {
    final dose = r.dosage;

    switch (r.type.toLowerCase()) {
      case 'tablet':
      case 'capsule':
        return "$dose pill(s)";
      case 'syrup':
        return "$dose ml";
      case 'injection':
        return "$dose ml";
      case 'drops':
        return "$dose drops";
      default:
        return dose;
    }
  }

  Widget _buildReminderCard(
    Reminder r,
    int index,
    bool isActive,
    double width,
  ) {
    final now = DateTime.now();
    final daysLeft = r.endDate.difference(now).inDays;

    final intervalText = r.isInterval && r.intervalHours != null
        ? "Every ${r.intervalHours} hr"
        : "";

    return Container(
      margin: EdgeInsets.only(bottom: width * 0.03),
      padding: EdgeInsets.all(width * 0.035),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: width * 0.03,
            height: width * 0.03,
            margin: EdgeInsets.only(top: width * 0.015),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? kPrimaryDark : Colors.grey,
            ),
          ),

          SizedBox(width: width * 0.035),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// MEDICINE NAME + STATUS
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.medicineName,
                        style: TextStyle(
                          fontSize: width * 0.042,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    if (daysLeft <= 1 && isActive)
                      Text(
                        "Completing soon",
                        style: TextStyle(
                          fontSize: width * 0.028,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),

                SizedBox(height: width * 0.01),

                /// TYPE • DOSAGE • INTERVAL
                Text(
                  "${r.type} • ${formatDosage(r)} ${intervalText.isNotEmpty ? "• $intervalText" : ""}",
                  style: TextStyle(
                    fontSize: width * 0.032,
                    color: Colors.black54,
                  ),
                ),

                /// NOTES TAG
                if (r.notes != null && r.notes!.trim().isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: width * 0.012),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: width * 0.025,
                        vertical: width * 0.008,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        r.notes!,
                        style: TextStyle(
                          fontSize: width * 0.026,
                          color: kPrimaryDark,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                SizedBox(height: width * 0.01),

                /// DATE RANGE
                Text(
                  "${r.startDate.day}/${r.startDate.month}/${r.startDate.year} – "
                  "${r.endDate.day}/${r.endDate.month}/${r.endDate.year}",
                  style: TextStyle(fontSize: width * 0.03, color: Colors.grey),
                ),

                /// TIMES
                if (r.times.isNotEmpty)
                  Text(
                    r.times.map((t) => t.format(context)).join(', '),
                    style: TextStyle(
                      fontSize: width * 0.03,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ),

          /// MENU BUTTON
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == "edit") widget.onEdit(r, index);
              if (value == "delete") widget.onDelete(index);
              if (value == "reactivate") {
                widget.onReactivate(index, DateTime.now());
              }
            },
            itemBuilder: (context) => [
              if (isActive)
                const PopupMenuItem(value: "edit", child: Text("Edit")),
              if (!isActive)
                const PopupMenuItem(
                  value: "reactivate",
                  child: Text("Set Reminder Again"),
                ),
              const PopupMenuItem(value: "delete", child: Text("Delete")),
            ],
            icon: Icon(Icons.more_vert, size: width * 0.06),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(double width) {
    return Padding(
      padding: EdgeInsets.only(top: width * 0.2),
      child: Column(
        children: [
          Icon(
            Icons.medication_outlined,
            size: width * 0.18,
            color: Colors.grey.shade300,
          ),
          SizedBox(height: width * 0.03),
          Text(
            "No reminders yet",
            style: TextStyle(fontSize: width * 0.04, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
