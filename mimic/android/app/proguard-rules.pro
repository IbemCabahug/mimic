# --- Flutter ---
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- App entry / disguise alias (manifest-referenced; explicit for safety) ---
-keep class com.example.mimic.MainActivity { *; }

# --- flutter_secure_storage + Tink + AndroidX security-crypto ---
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**
-keep class androidx.security.crypto.** { *; }

# --- CameraX / camera ---
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# --- video_player (Media3 / ExoPlayer) ---
-keep class androidx.media3.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn androidx.media3.**
-dontwarn com.google.android.exoplayer2.**

# --- photo_manager / wechat_assets_picker ---
-keep class com.fluttercandies.** { *; }

# --- mobile_scanner (ML Kit barcode) ---
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-dontwarn com.google.mlkit.**

# --- syncfusion_flutter_pdfviewer ---
-keep class com.syncfusion.** { *; }

# --- local_auth (biometric) ---
-keep class androidx.biometric.** { *; }

# --- Defensive: native methods, annotations, Java/Kotlin enum reflection ---
-keepattributes *Annotation*
-keepclassmembers class * { native <methods>; }
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
