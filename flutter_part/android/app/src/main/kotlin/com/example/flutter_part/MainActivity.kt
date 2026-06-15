package com.example.flutter_part

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "replaceReminderAlarms" -> {
                        val rawAlarms = call.argument<List<*>>("alarms").orEmpty()
                        val alarms =
                            rawAlarms.mapNotNull { item ->
                                @Suppress("UNCHECKED_CAST")
                                item as? Map<String, Any?>
                            }
                        replaceReminderAlarms(alarms)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun replaceReminderAlarms(alarms: List<Map<String, Any?>>) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val oldIds = prefs.getStringSet(KEY_IDS, emptySet()).orEmpty()

        for (idStr in oldIds) {
            val id = idStr.toIntOrNull() ?: continue
            val pendingIntent = buildAlarmPendingIntent(id, "", "")
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }

        val newIds = mutableSetOf<String>()
        val now = System.currentTimeMillis()

        for (alarm in alarms) {
            val id = (alarm["id"] as? Number)?.toInt() ?: continue
            val triggerAt = (alarm["triggerAtMillis"] as? Number)?.toLong() ?: continue
            if (triggerAt <= now) continue

            val medicineName = alarm["medicineName"] as? String ?: ""
            val dosage = alarm["dosage"] as? String ?: ""

            val pendingIntent = buildAlarmPendingIntent(id, medicineName, dosage)

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        pendingIntent
                    )
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                }
                newIds.add(id.toString())
            } catch (_: SecurityException) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                } else {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
                }
                newIds.add(id.toString())
            }
        }

        prefs.edit().putStringSet(KEY_IDS, newIds).apply()
    }

    private fun buildAlarmPendingIntent(
        id: Int,
        medicineName: String,
        dosage: String
    ): PendingIntent {
        val intent =
            Intent(this, AlarmReceiver::class.java).apply {
                putExtra("notificationId", id)
                putExtra("medicineName", medicineName)
                putExtra("dosage", dosage)
            }

        return PendingIntent.getBroadcast(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    companion object {
        private const val CHANNEL_NAME = "medguard/alarm_scheduler"
        private const val PREFS_NAME = "alarm_scheduler_prefs"
        private const val KEY_IDS = "scheduled_alarm_ids"
    }
}
