# Project-specific R8/ProGuard rules.
# Keep this file present because release minification references it.
# Add targeted keep rules here only when a concrete shrink/obfuscation issue is observed.

# Remove framework log calls from release artifacts to reduce binary intelligence
# and accidental sensitive-data exposure through logcat on rooted/debuggable devices.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
    public static int wtf(...);
    public static boolean isLoggable(...);
}
