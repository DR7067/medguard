package com.example.flutter_part

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.MissingResourceException

class AlarmActivity : android.app.Activity(), TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var spoken = false
    private var speakInActivity = true
    private var speechText: String = ""
    private var repeatCount = 0
    private var stopRequested = false
    private var pendingRepeat = false
    private var currentUtteranceId: String = ""
    private val repeatLimit = 4
    private val repeatGapMs = 1500L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var notificationId: Int = 0
    private var medicineName: String = ""
    private var dosage: String = ""
    private var medicineType: String = "Tablet"
    private var voiceLanguage: String = "en-IN"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        setContentView(R.layout.activity_alarm)
        AlarmSpeech.stop()
        speakInActivity = intent.getBooleanExtra("speakInActivity", true)
        notificationId = intent.getIntExtra("notificationId", 0)
        voiceLanguage = normalizeLanguageCode(
            intent.getStringExtra("languageCode") ?: loadSavedReminderLanguage()
        )

        medicineName = intent.getStringExtra("medicineName").orEmpty()
        dosage = intent.getStringExtra("dosage").orEmpty()
        medicineType = intent.getStringExtra("medicineType") ?: "Tablet"
        val timeText = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        speechText = buildSpeechText(voiceLanguage, medicineName, dosage, medicineType)

        val medicineLabel = resolveMedicineLabel(medicineName, medicineType, voiceLanguage)
        findViewById<TextView>(R.id.alarmTime).text = timeText
        findViewById<TextView>(R.id.alarmSubtitle).text =
            if (dosage.isBlank()) medicineLabel else "$medicineLabel - $dosage"

        findViewById<Button>(R.id.snoozeButton).setOnClickListener {
            stopRequested = true
            tts?.stop()
            AlarmSpeech.stop()
            cancelActiveNotification()

            if (scheduleNextSnooze()) {
                Toast.makeText(this, "Snoozed for 10 minutes", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, "Snooze limit reached", Toast.LENGTH_SHORT).show()
            }
            finish()
        }

        findViewById<Button>(R.id.takenButton).setOnClickListener {
            stopRequested = true
            tts?.stop()
            AlarmSpeech.stop()
            cancelAlarmCompletely()
            clearSnoozeCount()
            Toast.makeText(this, "Medicine marked as taken", Toast.LENGTH_SHORT).show()
            finish()
        }

        if (speakInActivity) {
            tts = TextToSpeech(this, this)
            tts?.setPitch(1.0f)
            tts?.setOnUtteranceProgressListener(
                object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit

                    override fun onDone(utteranceId: String?) {
                        if (stopRequested) return
                        if (utteranceId != currentUtteranceId) return
                        if (pendingRepeat) return
                        if (repeatCount >= repeatLimit) return
                        pendingRepeat = true
                        mainHandler.postDelayed(
                            {
                                pendingRepeat = false
                                if (!stopRequested) speakOnce()
                            },
                            repeatGapMs
                        )
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) = Unit

                    override fun onError(utteranceId: String?, errorCode: Int) = Unit
                }
            )
        }
    }

    override fun onInit(status: Int) {
        if (!speakInActivity) return
        if (status == TextToSpeech.SUCCESS && !spoken) {
            spoken = true
            applyBestLanguage(voiceLanguage)
            tts?.setSpeechRate(resolveSpeechRate(voiceLanguage))
            repeatCount = 0
            speakOnce()
        }
    }

    private fun speakOnce() {
        if (stopRequested || repeatCount >= repeatLimit) return
        repeatCount += 1
        pendingRepeat = false
        currentUtteranceId = "alarm_tts_$repeatCount"
        tts?.speak(speechText, TextToSpeech.QUEUE_FLUSH, null, currentUtteranceId)
    }

    override fun onDestroy() {
        stopRequested = true
        mainHandler.removeCallbacksAndMessages(null)
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }

    private fun cancelActiveNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        manager.cancel(notificationId)
    }

    private fun cancelAlarmCompletely() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun scheduleNextSnooze(): Boolean {
        if (notificationId == 0) return false

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val key = "$SNOOZE_KEY_PREFIX$notificationId"
        val currentCount = prefs.getInt(key, 0)
        if (currentCount >= MAX_SNOOZE_COUNT) return false

        prefs.edit().putInt(key, currentCount + 1).apply()

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAtMillis = System.currentTimeMillis() + SNOOZE_INTERVAL_MILLIS

        val receiverIntent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("notificationId", notificationId)
            putExtra("medicineName", medicineName)
            putExtra("dosage", dosage)
            putExtra("medicineType", medicineType)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            notificationId,
            receiverIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            }
        } catch (_: SecurityException) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            }
        }

        return true
    }

    private fun clearSnoozeCount() {
        if (notificationId == 0) return
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().remove("$SNOOZE_KEY_PREFIX$notificationId").apply()
    }

    private fun loadSavedReminderLanguage(): String {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getString("flutter.reminder_voice_language", null)
            ?: prefs.getString("reminder_voice_language", null)
            ?: "en-IN"
    }

    private fun resolveSpeechRate(languageCode: String): Float {
        return when (languageCode.lowercase()) {
            "hi", "hi-in" -> 0.90f
            "mr", "mr-in" -> 0.92f
            else -> 0.95f
        }
    }

    private fun buildSpeechText(languageCode: String, medicine: String, dosageText: String, type: String): String {
        val med = sanitizeForSpeech(medicine)
        val medLabel = resolveMedicineLabel(med, type, languageCode)
        val d = sanitizeForSpeech(dosageText)
        return when (languageCode.lowercase()) {
            "hi", "hi-in" -> {
                if (d.isEmpty()) "\u0926\u0935\u093e \u0932\u0947\u0928\u0947 \u0915\u093e \u0938\u092e\u092f \u0939\u094b \u0917\u092f\u093e \u0939\u0948. \u0915\u0943\u092a\u092f\u093e $medLabel \u0905\u092d\u0940 \u0932\u0947\u0902."
                else "\u0926\u0935\u093e \u0932\u0947\u0928\u0947 \u0915\u093e \u0938\u092e\u092f \u0939\u094b \u0917\u092f\u093e \u0939\u0948. \u0915\u0943\u092a\u092f\u093e $medLabel, $d \u0905\u092d\u0940 \u0932\u0947\u0902."
            }
            "mr", "mr-in" -> {
                if (d.isEmpty()) "\u0914\u0937\u0927 \u0918\u0947\u0923\u094d\u092f\u093e\u091a\u0940 \u0935\u0947\u0933 \u091d\u093e\u0932\u0940 \u0906\u0939\u0947. \u0915\u0943\u092a\u092f\u093e $medLabel \u0906\u0924\u093e \u0918\u094d\u092f\u093e."
                else "\u0914\u0937\u0927 \u0918\u0947\u0923\u094d\u092f\u093e\u091a\u0940 \u0935\u0947\u0933 \u091d\u093e\u0932\u0940 \u0906\u0939\u0947. \u0915\u0943\u092a\u092f\u093e $medLabel $d \u0906\u0924\u093e \u0918\u094d\u092f\u093e."
            }
            else -> {
                if (d.isEmpty()) "It is time for your medicine. Please take $medLabel now."
                else "It is time for your medicine. Please take $medLabel, $d now."
            }
        }
    }

    private fun resolveMedicineLabel(medicine: String, type: String, languageCode: String): String {
        val med = medicine.trim() // Do not translate medicine names
        val isSyrup = type.lowercase() == "syrup"
        val suffix = when (languageCode.lowercase()) {
            "hi", "hi-in" -> if (isSyrup) "\u0938\u093f\u0930\u092a" else "\u0926\u0935\u093e"
            "mr", "mr-in" -> if (isSyrup) "\u0938\u093f\u0930\u092a" else "\u0914\u0937\u0927"
            else -> if (isSyrup) "syrup" else "medicine"
        }
        return if (med.isEmpty()) suffix else "$med $suffix"
    }

    private fun localizeMedicalTerms(input: String, languageCode: String): String {
        if (input.isBlank()) return ""
        return Regex("[A-Za-z]+").replace(input) { match ->
            translateMedicalToken(match.value, languageCode) ?: match.value
        }
    }

    private fun translateMedicalToken(token: String, languageCode: String): String? {
        val normalizedLanguage = when (languageCode.lowercase()) {
            "hi", "hi-in" -> "hi"
            "mr", "mr-in" -> "mr"
            else -> "en"
        }

        return when (token.lowercase()) {
            "fever" -> when (normalizedLanguage) {
                "hi" -> "\u092c\u0941\u0916\u093e\u0930"
                "mr" -> "\u0924\u093e\u092a"
                else -> null
            }
            "cold" -> when (normalizedLanguage) {
                "hi" -> "\u0938\u0930\u094d\u0926\u0940"
                "mr" -> "\u0938\u0930\u094d\u0926\u0940"
                else -> null
            }
            "cough" -> when (normalizedLanguage) {
                "hi" -> "\u0916\u093e\u0902\u0938\u0940"
                "mr" -> "\u0916\u094b\u0915\u0932\u093e"
                else -> null
            }
            "pain" -> when (normalizedLanguage) {
                "hi" -> "\u0926\u0930\u094d\u0926"
                "mr" -> "\u0935\u0947\u0926\u0928\u093e"
                else -> null
            }
            "headache" -> when (normalizedLanguage) {
                "hi" -> "\u0938\u093f\u0930\u0926\u0930\u094d\u0926"
                "mr" -> "\u0921\u094b\u0915\u0947\u0926\u0941\u0916\u0940"
                else -> null
            }
            "acidity" -> when (normalizedLanguage) {
                "hi" -> "\u090f\u0938\u093f\u0921\u093f\u091f\u0940"
                "mr" -> "\u0905\u0945\u0938\u093f\u0921\u093f\u091f\u0940"
                else -> null
            }
            else -> null
        }
    }

    private fun applyBestLanguage(languageCode: String) {
        val candidates = when (languageCode.lowercase()) {
            "mr", "mr-in" -> listOf(
                Locale.forLanguageTag("mr-IN"),
                Locale.forLanguageTag("mr"),
                Locale.forLanguageTag("hi-IN"),
                Locale.forLanguageTag("en-IN")
            )
            "hi", "hi-in" -> listOf(
                Locale.forLanguageTag("hi-IN"),
                Locale.forLanguageTag("hi"),
                Locale.forLanguageTag("en-IN")
            )
            else -> listOf(Locale.forLanguageTag("en-IN"), Locale.ENGLISH)
        }

        for (locale in candidates) {
            val result = tts?.setLanguage(locale) ?: continue
            if (result >= TextToSpeech.LANG_AVAILABLE) {
                applyPreferredVoice(languageCode, locale)
                return
            }
        }

        tts?.setLanguage(Locale.forLanguageTag("en-IN"))
    }

    private fun applyPreferredVoice(languageCode: String, targetLocale: Locale) {
        val allVoices = tts?.voices ?: return
        val preferred = when (languageCode.lowercase()) {
            "mr", "mr-in" -> allVoices.firstOrNull { v ->
                localeLanguage(v.locale) == "mr" || v.name.lowercase().contains("mr")
            }
            "hi", "hi-in" -> allVoices.firstOrNull { v ->
                localeLanguage(v.locale) == "hi" || v.name.lowercase().contains("hi")
            }
            else -> allVoices.firstOrNull { v ->
                localeLanguage(v.locale) == targetLocale.language
            }
        }

        if (preferred != null) tts?.voice = preferred
    }

    private fun localeLanguage(locale: Locale?): String {
        if (locale == null) return ""
        return try {
            locale.language.lowercase()
        } catch (_: MissingResourceException) {
            ""
        }
    }

    private fun sanitizeForSpeech(value: String): String {
        return value
            .replace(Regex("[^\\p{L}\\p{N}\\s]+"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun normalizeLanguageCode(rawCode: String?): String {
        val trimmed = rawCode?.trim().orEmpty()
        if (trimmed.isBlank()) return "en-IN"
        return trimmed.replace('_', '-')
    }

    companion object {
        private const val PREFS_NAME = "alarm_snooze_prefs"
        private const val SNOOZE_KEY_PREFIX = "snooze_count_"
        private const val MAX_SNOOZE_COUNT = 3
        private const val SNOOZE_INTERVAL_MILLIS = 10 * 60 * 1000L
    }
}
