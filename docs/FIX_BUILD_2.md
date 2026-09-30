The GitHub Actions Android build fails with these Dart compile errors. Fix each one precisely, do not rewrite unrelated code.

ERROR SET 1 - lib/pages/tabs/send_tab.dart, around lines 74-76:
Too many positional arguments errors on an Expanded(...) and a RoundedRectangleBorder(...) widget constructor. This almost always means a bracket or parenthesis was mismatched earlier in the surrounding widget tree, causing the parser to misread these constructor calls. Carefully review the widget code from roughly line 60 to line 80, find the actual bracket/parenthesis mismatch, and fix it so these constructors receive only their intended named arguments.

ERROR SET 2 - lib/pages/tabs/send_tab.dart, around lines 404-422:
A switch block mixes two incompatible Dart syntaxes: "case SessionStatus.canceledBySender:" followed on the next line by "return ...;" (old-style switch STATEMENT syntax), but the compiler expected "=>" (newer switch EXPRESSION syntax), meaning this switch is being used as an expression elsewhere. Look at how this switch is invoked (is it assigned to a variable, returned directly, or embedded in an expression?) and make the whole switch block consistently use ONE syntax: either full switch-statement syntax (case X: return Y; for every case, with a matching closing brace) or full switch-expression syntax (case X => Y, for every case, comma separated, as a single expression). Match whichever style the rest of the switch block already uses for its other cases, and apply it to the canceledBySender and canceledByReceiver cases too.

ERROR SET 3 - lib/pages/web_share_page.dart, lines 154 and 160:
"if (_sendMode) await _init(encrypted: _encrypted);" is being used where a value/expression is expected, but this produces no value (void), causing a compile error. Restructure so this is a standalone statement (its own line, ending in a semicolon, not nested inside a larger expression, ternary, or return statement). If it currently needs to produce a value for something else to use, refactor so the value is computed separately and this line is a plain conditional statement.

After fixing all three error sets:
1. Do a careful re-read of both files to check for any other syntax issues introduced by the same earlier edit, since these errors may not be the only ones.
2. Commit with a message like "fix: resolve Dart syntax errors in send_tab.dart and web_share_page.dart".
3. Explicitly push to main and confirm the push succeeded with the new commit hash.

Report back: what was actually wrong in each case, what you changed, and confirmation the push completed.
