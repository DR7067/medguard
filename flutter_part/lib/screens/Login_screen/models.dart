import 'package:flutter/material.dart';

// Master Medicine (catalog)
class MasterMedicine {
  final String name;
  final String description;

  MasterMedicine({required this.name, this.description = ''});
}

// Reminder
class ReminderDose {
  final TimeOfDay time;
  final String note;

  ReminderDose({required this.time, this.note = ''});
}

// User medicine
class UserMedicine {
  final MasterMedicine medicine;
  int quantity;
  int dosagePerDay;
  DateTime expiryDate;
  DateTime addedDate;
  List<ReminderDose> reminders;

  UserMedicine({
    required this.medicine,
    required this.quantity,
    required this.dosagePerDay,
    required this.expiryDate,
    required this.addedDate,
    required this.reminders,
  });

  DateTime get expectedFinishDate {
    if (dosagePerDay <= 0) return addedDate;
    int days = (quantity / dosagePerDay).ceil();
    return addedDate.add(Duration(days: days));
  }

  bool get isFinished => quantity <= 0;
  bool get isExpired => DateTime.now().isAfter(expiryDate);
}

// App user (head or dependent)
class AppUser {
  final String id;
  final String name;
  final bool isHead; // true if head
  List<AppUser> linkedUsers; // dependents or head can see all
  List<UserMedicine> medicines;

  AppUser({
    required this.id,
    required this.name,
    this.isHead = false,
    this.linkedUsers = const [],
    this.medicines = const [],
  });

  // View all medicines for dashboard
  List<UserMedicine> get allMedicines {
    List<UserMedicine> all = [...medicines];
    for (var user in linkedUsers) {
      all.addAll(user.medicines);
    }
    return all;
  }

  // Add medicine to any linked user or self
  void addMedicine({
    required String targetUserId,
    required UserMedicine medicine,
  }) {
    if (targetUserId == id) {
      medicines.add(medicine);
    } else {
      for (var user in linkedUsers) {
        if (user.id == targetUserId) {
          user.medicines.add(medicine);
          break;
        }
      }
    }
  }

  // Add linked user (only head can do this)
  void addLinkedUser(AppUser user) {
    if (isHead) linkedUsers.add(user);
  }
}
