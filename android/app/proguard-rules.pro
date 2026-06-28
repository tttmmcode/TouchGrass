# ── Flutter ──────────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ── Firebase ─────────────────────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ── Firebase Crashlytics ─────────────────────────────────────────────────────
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# ── Firebase Performance ─────────────────────────────────────────────────────
-keep class com.google.firebase.perf.** { *; }

# ── Google Sign-In ───────────────────────────────────────────────────────────
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ── Google Maps ──────────────────────────────────────────────────────────────
-keep class com.google.maps.** { *; }
-dontwarn com.google.maps.**

# ── Camera ───────────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.camera.** { *; }

# ── Kotlin coroutines ────────────────────────────────────────────────────────
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}
