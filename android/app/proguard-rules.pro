# ============================================================
# ProGuard Rules — CNSC Control de Asistencias
# ============================================================

# Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keepclassmembers class * {
    @io.flutter.embedding.engine.plugins.FlutterPlugin *;
}

# Supabase / Realtime / PostgREST
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# OkHttp (usado internamente por Supabase/Dart HTTP)
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-keep class okio.** { *; }

# Kotlin coroutines
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}
-dontwarn kotlinx.coroutines.**

# Gson (usado en algunos plugins)
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Android componentes principales
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# Notificaciones locales (flutter_local_notifications)
-keep class com.dexterous.** { *; }

# File picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Image picker / cropper
-keep class com.yalantis.ucrop.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }

# Permission handler
-keep class com.baseflow.permissionhandler.** { *; }

# Preserve line numbers for debugging stack traces
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
