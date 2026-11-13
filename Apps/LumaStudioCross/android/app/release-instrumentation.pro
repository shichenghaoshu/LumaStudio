# AndroidJUnitRunner shares this AndroidX runtime class with the app. Keep the
# public trace entry points so native instrumentation can test the minified APK.
-keep class androidx.tracing.Trace { *; }
# The native test runner uses Kotlin entry points which otherwise look unused
# to the production app shrinker. This retains runtime API, not test code.
-keep class kotlin.** { *; }
