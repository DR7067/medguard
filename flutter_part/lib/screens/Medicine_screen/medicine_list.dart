import 'package:flutter/material.dart';
import 'package:flutter_part/screens/Home_screen/activity_service.dart';
import 'package:flutter_part/screens/Home_screen/recent_activity.dart';
import 'medicine.dart';
import 'add_medicine.dart';
import 'reminder.dart';
import '../../services/reminder_alert_service.dart';

const Color kPrimaryColor = Color(0xFF2563EB);
const Color kPrimaryDark = Color(0xFF1D4ED8);
const Color kPrimaryLight = Color(0xFF3B82F6);
const Color kBackgroundColor = Color(0xFFEFF6FF);

class MedicineList extends StatefulWidget {
  final List<Medicine> medicines;
  final List<Reminder> reminders;
  final void Function(Medicine, int) onEdit;
  final void Function(int) onDelete;
  final Future<void> Function() onChanged;

  const MedicineList({
    super.key,
    required this.medicines,
    required this.reminders,
    required this.onEdit,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<MedicineList> createState() => _MedicineListState();
}

class _MedicineListState extends State<MedicineList> {
  String searchQuery = '';
  bool showActive = true;

  List<RecentActivity> recentActivities = [];

  @override
  void initState() {
    super.initState();
    ReminderAlertService.instance.takenUpdates.addListener(_refreshList);
  }

  @override
  void dispose() {
    ReminderAlertService.instance.takenUpdates.removeListener(_refreshList);
    super.dispose();
  }

  void _refreshList() {
    if (mounted) setState(() {});
  }

  List<Medicine> get filteredMeds => widget.medicines
      .where((med) => showActive ? !isExpired(med) : isExpired(med))
      .where(
        (med) => med.name.toLowerCase().contains(searchQuery.toLowerCase()),
      )
      .toList();

  bool isExpired(Medicine med) {
    return med.expiryDate.isBefore(DateTime.now());
  }

  bool isExpiringSoon(Medicine med) {
    final now = DateTime.now();
    final difference = med.expiryDate.difference(now).inDays;
    return difference >= 0 && difference <= 7;
  }

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            GestureDetector(
              onTap: () async {
                final newMed = await Navigator.push<Medicine>(
                  context,
                  MaterialPageRoute(builder: (_) => const AddMedicine()),
                );
                if (newMed != null) {
                  widget.medicines.add(newMed);
                  await widget.onChanged();
                }
                Navigator.pop(context);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: kPrimaryColor,
                    child: Icon(Icons.medication, color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  Text("Add Medicine"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Medicine"),
        content: const Text("Are you sure you want to delete this medicine?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              widget.onDelete(index);
              Navigator.pop(ctx);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Convert Medicine -> Reminder for the service
  Reminder toReminder(Medicine med) {
    final reminderForMedicine = widget.reminders.cast<Reminder?>().firstWhere(
      (r) => r != null && r.medicineName.trim().toLowerCase() == med.name.trim().toLowerCase(),
      orElse: () => null,
    );

    return Reminder(
      medicineName: med.name,
      type: med.type.name,
      dosage: med.tags,
      times: reminderForMedicine?.times ?? const <TimeOfDay>[],
      startDate: DateTime.now(),
      endDate: med.expiryDate,
    );
  }

  /// Mark medicine as taken and update nextDose
  Future<void> _markTaken(Medicine med) async {
    final dueItem = DueReminderItem(
      reminder: toReminder(med),
      time: TimeOfDay.now(),
      triggerDate: DateTime.now(),
    );

    await ReminderAlertService.instance.updateSavedRemindersAfterTaken([
      dueItem,
    ]);

    ReminderAlertService.instance.nextDoseAfter(
      dueItem.reminder,
      DateTime.now(),
    );

    setState(() {});

    ActivityService.instance.addActivity(
      RecentActivity(
        description: "You took ${med.name}",
        timestamp: DateTime.now(),
        type: ActivityType.medicine,
      ),
    );
  }

  Widget _buildRecentActivities() {
    if (recentActivities.isEmpty) {
      return const Center(child: Text("No recent activities yet"));
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recentActivities.length,
      itemBuilder: (context, index) {
        final activity = recentActivities[index];
        return ListTile(
          leading: const Icon(Icons.history, color: kPrimaryColor),
          title: Text(activity.description),
          subtitle: Text(
            "${activity.timestamp.hour.toString().padLeft(2, '0')}:${activity.timestamp.minute.toString().padLeft(2, '0')} - "
            "${activity.timestamp.day}-${activity.timestamp.month}-${activity.timestamp.year}",
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [kPrimaryColor, kPrimaryLight]),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Medicine List",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Icon(Icons.medical_services, color: Colors.white),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth / 2;

                return Stack(
                  children: [
                    // Background Container
                    Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 6),
                        ],
                      ),
                    ),

                    // Sliding Indicator
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      left: showActive ? 0 : width,
                      child: Container(
                        width: width,
                        height: 50,
                        decoration: BoxDecoration(
                          color: showActive ? kPrimaryColor : Colors.red,
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),

                    // Text Buttons
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => showActive = true),
                            child: Container(
                              height: 50,
                              alignment: Alignment.center,
                              child: Text(
                                "Active",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: showActive
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => showActive = false),
                            child: Container(
                              height: 50,
                              alignment: Alignment.center,
                              child: Text(
                                "Expired",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: !showActive
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (val) => setState(() => searchQuery = val),
              decoration: InputDecoration(
                hintText: "Search medicines...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: filteredMeds.isEmpty
                ? const Center(
                    child: Text(
                      "No medicines found",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredMeds.length,
                    itemBuilder: (context, index) {
                      final med = filteredMeds[index];
                      final originalIndex = widget.medicines.indexOf(med);

                      final isTakenToday = ReminderAlertService.instance
                          .isTakenToday(med.name);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isTakenToday
                              ? Colors.green.shade50
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 8),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: med.isExpired
                                    ? Colors.red.shade50
                                    : kPrimaryLight.withOpacity(0.2),
                              ),
                              child: Icon(
                                Icons.medication,
                                color: med.isExpired
                                    ? Colors.red
                                    : kPrimaryColor,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          med.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),

                                      if (isExpired(med))
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade100,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Text(
                                            "Expired",
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      else if (isExpiringSoon(med))
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade100,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Text(
                                            "Expiring Soon",
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),

                                      if (isTakenToday)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 6),
                                          child: Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (med.tags.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        med.tags,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),

                                  const SizedBox(height: 6),

                                  Text(
                                    "Expiry: ${med.expiryDate.day}-${med.expiryDate.month}-${med.expiryDate.year}",
                                  ),

                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.check_circle,
                                color: Colors.blue,
                              ),
                              onPressed: () => _markTaken(med),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  widget.onEdit(med, originalIndex);
                                } else if (value == 'delete') {
                                  _confirmDelete(originalIndex);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text("Edit"),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text("Delete"),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
