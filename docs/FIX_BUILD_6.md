The Android build fails with a Kotlin compile error, not a Dart one:

e: file:///tmp/build/app/android/app/src/main/kotlin/com/omnidrop/app/MainActivity.kt:90 Unresolved reference. None of the following candidates is applicable because of a receiver type mismatch.
fun Long.toRfc3339(): String

Do the following, in order, and show your work:

1. Print the actual content of MainActivity.kt from line 1 to line 110 with line numbers, so the real code is visible, including any imports related to date/time handling.
2. Find where `toRfc3339()` is defined (search the Kotlin files in this project for its declaration) and print that definition.
3. Based on both of those, identify exactly what type is being called with `.toRfc3339()` on line 90, and why it doesn't match `Long`. Common causes: it's actually a `Date`, `java.time.Instant`, a nullable `Long?` that needs a null check or `!!` or `?:` default first, or it's a different variable entirely than intended. State clearly which one it is.
4. Fix it by converting the value to a plain non-null `Long` before calling `.toRfc3339()` (the correct fix depends on what you find in step 3, e.g. calling `.time` on a Date, or `.toEpochMilli()` on an Instant, or handling nullability properly). Do not change the `toRfc3339()` function itself unless it is genuinely wrong for every caller.
5. Print the corrected lines 80-100 showing the fix.
6. Review the rest of MainActivity.kt for any other similar type mismatches around date/file metadata handling (this file was recently modified for Copy Phone / file listing features), since one mistake of this kind often has siblings.

After fixing:
1. Commit with a message like "fix: resolve Long/toRfc3339 type mismatch in MainActivity.kt".
2. Explicitly push to main. Run `git fetch && git log origin/main -1 --oneline` and paste the output.

Report back with all real file content and command output requested above, not summaries.
