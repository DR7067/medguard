import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static Future<void> init() async {
    tz.initializeTimeZones();
    await _configureLocalTimeZone();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('logo');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(settings: settings);

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();

      // Ensure channels exist so FCM notifications can display when app is closed.
      const medicineChannel = AndroidNotificationChannel(
        'medicine_channel',
        'Medicine Reminders',
        description: 'Reminder notifications for medicines',
        importance: Importance.max,
      );
      const careEventChannel = AndroidNotificationChannel(
        'care_event_channel',
        'Care Events',
        description: 'Notifications from caretaker actions',
        importance: Importance.max,
      );
      await androidPlugin.createNotificationChannel(medicineChannel);
      await androidPlugin.createNotificationChannel(careEventChannel);
    }
  }

  static Future<void> _configureLocalTimeZone() async {
    try {
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    AndroidScheduleMode scheduleMode =
        AndroidScheduleMode.inexactAllowWhileIdle;

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final notificationsEnabled = await androidPlugin?.areNotificationsEnabled();
    if (notificationsEnabled == false) {
      await androidPlugin?.requestNotificationsPermission();
    }
    final canScheduleExact = await androidPlugin
        ?.canScheduleExactNotifications();
    if (canScheduleExact == true) {
      scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    }

    await _notifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'medicine_channel',
          'Medicine Reminders',
          channelDescription: 'Reminder notifications for medicines',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'logo',
        ),
      ),
      androidScheduleMode: scheduleMode,
    );
  }

  static int _stableId(String key) => key.hashCode & 0x7fffffff;

  static Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    final id = _stableId(
      '$title|$body|${DateTime.now().millisecondsSinceEpoch}',
    );
    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'care_event_channel',
          'Care Events',
          channelDescription: 'Notifications from caretaker actions',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'logo',
        ),
      ),
    );
  }

  static int _expiryOnDayId(String medicineName, DateTime expiryDate) {
    final dateKey = "${expiryDate.year}-${expiryDate.month}-${expiryDate.day}";
    return _stableId("expiry_on:$medicineName:$dateKey");
  }

  static int _expiryDayBeforeId(String medicineName, DateTime expiryDate) {
    final dateKey = "${expiryDate.year}-${expiryDate.month}-${expiryDate.day}";
    return _stableId("expiry_before:$medicineName:$dateKey");
  }

  static Future<void> scheduleMedicineExpiryNotifications({
    required String medicineName,
    required DateTime expiryDate,
  }) async {
    final now = DateTime.now();
    final onDay = DateTime(
      expiryDate.year,
      expiryDate.month,
      expiryDate.day,
      expiryDate.hour,
      expiryDate.minute,
    );
    final dayBefore = onDay.subtract(const Duration(days: 1));

    if (dayBefore.isAfter(now)) {
      await scheduleNotification(
        id: _expiryDayBeforeId(medicineName, expiryDate),
        title: "Medicine Expiry Tomorrow",
        body: "$medicineName expires tomorrow",
        scheduledDate: dayBefore,
      );
    }

    if (onDay.isAfter(now)) {
      await scheduleNotification(
        id: _expiryOnDayId(medicineName, expiryDate),
        title: "Medicine Expiry Today",
        body: "$medicineName expires today",
        scheduledDate: onDay,
      );
    }
  }

  static Future<void> cancelMedicineExpiryNotifications({
    required String medicineName,
    required DateTime expiryDate,
  }) async {
    await _notifications.cancel(
      id: _expiryDayBeforeId(medicineName, expiryDate),
    );
    await _notifications.cancel(id: _expiryOnDayId(medicineName, expiryDate));
  }
}
