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
