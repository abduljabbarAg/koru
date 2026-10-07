# Koru keeps nothing reflective, but sqflite and the platform channel do, and a
# minified release build that strips them fails at runtime rather than at build
# time, which is the worst place to find out.

# sqflite ships its own consumer rules; these cover the plugin registration that
# Flutter relies on.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# The secure key channel is resolved by name at runtime.
-keep class com.abduljabbar.koru.MainActivity { *; }

# Flutter's Play Store split application references Play Core, which is not on
# the classpath because this app is not distributed as an app bundle with Play
# split install. R8 treats the reference as a hard error; the class is never
# loaded, so silence the warning rather than pulling in a dependency the app will
# never use.
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
