package com.example.flutter_part

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.Locale
import java.util.MissingResourceException

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val medicineName = intent.getStringExtra("medicineName").orEmpty()
        val dosage = intent.getStringExtra("dosage").orEmpty()
        val medicineType = intent.getStringExtra("medicineType") ?: "Tablet"
        val notificationId = intent.getIntExtra("notificationId", 0)
        val languageCode = normalizeLanguageCode(loadSavedReminderLanguage(context))

        createChannel(context)

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val isInteractive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
            powerManager.isInteractive
        } else {
            @Suppress("DEPRECATION")
            powerManager.isScreenOn
        }

        val title = "Medicine Reminder"
        val body = buildSpeechText(languageCode, medicineName, dosage, medicineType)

        val activityIntent = Intent(context, AlarmActivity::class.java).apply {
            putExtra("notificationId", notificationId)
            putExtra("medicineName", medicineName)
            putExtra("dosage", dosage)
            putExtra("medicineType", medicineType)
            putExtra("languageCode", languageCode)
            putExtra("speakInActivity", !isInteractive)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(fullScreenPendingIntent)
            .setAutoCancel(true)
            .setOngoing(true)

        if (isInteractive) {
            // Screen ON: heads-up notification + TTS.
            AlarmSpeech.speak(context.applicationContext, body, languageCode)
        } else {
            // Screen OFF/locked: launch full-screen alarm UI.
            builder.setFullScreenIntent(fullScreenPendingIntent, true)
        }

        NotificationManagerCompat.from(context).notify(notificationId, builder.build())
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Alarm Reminders",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Full-screen medicine alarm reminders"
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun loadSavedReminderLanguage(context: Context): String {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getString("flutter.reminder_voice_language", null)
            ?: prefs.getString("reminder_voice_language", null)
            ?: "en-IN"
    }

    private fun normalizeLanguageCode(rawCode: String?): String {
        val trimmed = rawCode?.trim().orEmpty()
        if (trimmed.isBlank()) return "en-IN"
        return trimmed.replace('_', '-')
    }

    companion object {
        const val CHANNEL_ID = "alarm_reminder_channel"
    }
}

object AlarmSpeech {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var queuedText: String = ""
    private var queuedLanguage: String = "en-IN"
    private var repeatCount = 0
    private var stopRequested = false
    private var pendingRepeat = false
    private var currentUtteranceId: String = ""
    private const val repeatLimit = 4
    private const val repeatGapMs = 1500L
    private val mainHandler = Handler(Looper.getMainLooper())

    fun speak(context: Context, text: String, languageCode: String) {
        stop()
        queuedText = text
        queuedLanguage = languageCode
        repeatCount = 0
        stopRequested = false

        val existing = tts
        if (existing != null && ready) {
            speakOnce()
            return
        }

        if (existing == null) {
            tts = TextToSpeech(context) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    ready = true
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
                    speakOnce()
                }
            }
        }
    }

    fun stop() {
        stopRequested = true
        mainHandler.removeCallbacksAndMessages(null)
        tts?.stop()
    }

    private fun speakOnce() {
        if (stopRequested || queuedText.isBlank() || repeatCount >= repeatLimit) return
        repeatCount += 1
        applyBestLanguage(queuedLanguage)
        tts?.setSpeechRate(resolveSpeechRate(queuedLanguage))
        pendingRepeat = false
        currentUtteranceId = "receiver_alarm_tts_$repeatCount"
        tts?.speak(queuedText, TextToSpeech.QUEUE_FLUSH, null, currentUtteranceId)
    }

    private fun resolveSpeechRate(languageCode: String): Float {
        return when (languageCode.lowercase()) {
            "hi", "hi-in" -> 0.90f
            "mr", "mr-in" -> 0.92f
            else -> 0.95f
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
}

private fun buildSpeechText(languageCode: String, medicineName: String, dosage: String, type: String): String {
    val medicine = sanitizeForSpeech(medicineName)
    val medicineLabel = resolveMedicineLabel(medicine, type, languageCode)
    val d = sanitizeForSpeech(dosage)

    return when (languageCode.lowercase()) {
        "hi", "hi-in" -> {
            if (d.isEmpty()) "\u0926\u0935\u093e \u0932\u0947\u0928\u0947 \u0915\u093e \u0938\u092e\u092f \u0939\u094b \u0917\u092f\u093e \u0939\u0948. \u0915\u0943\u092a\u092f\u093e $medicineLabel \u0905\u092d\u0940 \u0932\u0947\u0902."
            else "\u0926\u0935\u093e \u0932\u0947\u0928\u0947 \u0915\u093e \u0938\u092e\u092f \u0939\u094b \u0917\u092f\u093e \u0939\u0948. \u0915\u0943\u092a\u092f\u093e $medicineLabel, $d \u0905\u092d\u0940 \u0932\u0947\u0902."
        }
        "mr", "mr-in" -> {
            if (d.isEmpty()) "\u0914\u0937\u0927 \u0918\u0947\u0923\u094d\u092f\u093e\u091a\u0940 \u0935\u0947\u0933 \u091d\u093e\u0932\u0940 \u0906\u0939\u0947. \u0915\u0943\u092a\u092f\u093e $medicineLabel \u0906\u0924\u093e \u0918\u094d\u092f\u093e."
            else "\u0914\u0937\u0927 \u0918\u0947\u0923\u094d\u092f\u093e\u091a\u0940 \u0935\u0947\u0933 \u091d\u093e\u0932\u0940 \u0906\u0939\u0947. \u0915\u0943\u092a\u092f\u093e $medicineLabel $d \u0906\u0924\u093e \u0918\u094d\u092f\u093e."
        }
        else -> {
            if (d.isEmpty()) "It is time for your medicine. Please take $medicineLabel now."
            else "It is time for your medicine. Please take $medicineLabel, $d now."
        }
    }
}

private fun resolveMedicineLabel(medicineName: String, type: String, languageCode: String): String {
    val medicine = medicineName.trim() // Do not translate medicine names
    val isSyrup = type.lowercase() == "syrup"
    val suffix = when (languageCode.lowercase()) {
        "hi", "hi-in" -> if (isSyrup) "\u0938\u093f\u0930\u092a" else "\u0926\u0935\u093e"
        "mr", "mr-in" -> if (isSyrup) "\u0938\u093f\u0930\u092a" else "\u0914\u0937\u0927"
        else -> if (isSyrup) "syrup" else "medicine"
    }
    return if (medicine.isEmpty()) suffix else "$medicine $suffix"
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

private fun sanitizeForSpeech(value: String): String {
    return value
        .replace(Regex("[^\\p{L}\\p{N}\\s]+"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()
}
