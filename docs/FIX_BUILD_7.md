The Android build fails with a Kotlin null-safety error:

e: MainActivity.kt:370:35 Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver of type 'WifiConfiguration?'.
e: MainActivity.kt:370:50 Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver of type 'WifiConfiguration?'.

Do the following, in order, and show your work:

1. Print the actual content of MainActivity.kt from line 355 to line 385 with line numbers, so the real code and surrounding context (what variable holds the WifiConfiguration?, where it comes from, e.g. from the hotspot start callback) is visible.
2. Determine why this value is nullable here (e.g. a hotspot-start callback API that can return null on failure) and whether a null case should be handled explicitly (e.g. report a hotspot-start failure back to Dart) rather than just suppressed with !!.
3. Fix line 370 using a proper null-safe approach: prefer a safe call (?.) combined with explicit handling of the null case (e.g. an if/let block that reports failure back through the existing MethodChannel.Result error path used elsewhere in this file) rather than a bare !! non-null assertion, since !! would just crash at runtime instead of failing gracefully if this value is ever actually null.
4. Print the corrected lines 355-385 showing the fix.
5. Do a quick check of the rest of this recently-added hotspot bridge code in MainActivity.kt for any other similar nullable-receiver patterns that might have the same issue but weren't caught by this specific error (the compiler stops at the first errors in a file sometimes, so there could be more once this one is fixed).

After fixing:
1. Commit with a message like "fix: resolve WifiConfiguration nullable receiver errors in MainActivity.kt".
2. Push to main. Run `git fetch && git log origin/main -1 --oneline` and paste the output.

Report back with all real file content and command output requested, not summaries.
