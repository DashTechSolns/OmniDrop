The in-app file browser's Folder category shows "This folder is empty" for subfolders that almost certainly contain files (e.g. a folder named "Animated Movies" on the user's device). This is a regression from the recent storage/DocumentFile work. Diagnose and fix precisely.

1. Find the code that handles folder navigation in the file browser (likely in in_app_file_browser.dart or a related file/controller touched in the recent storage batch). Print its actual current content for the function(s) responsible for: (a) listing root-level folders, (b) listing the contents of a folder once navigated into.

2. Identify exactly how folder navigation currently fetches child items - is it using DocumentFile.listFiles() on the correct child URI, or is it possibly re-querying the parent/root URI instead of the navigated-into subfolder's URI? Is there any error being silently caught and shown as "empty" instead of surfaced? Print any relevant error handling/catch blocks in this code path.

3. Based on what you find, state clearly what the actual bug is (e.g. "navigation passes the wrong URI when drilling into a subfolder" or "the query throws a permission error that gets swallowed and shown as empty state" or similar - describe the ACTUAL cause found in the real code, not a guess).

4. Fix the bug so navigating into any subfolder correctly lists its real contents. If the current design makes it hard to tell "genuinely empty" apart from "query failed," add a distinct error state (e.g. "Couldn't read this folder" instead of "This folder is empty") so future bugs like this are visible rather than silently misleading.

5. Print the corrected code.

6. Commit with a message like "fix: folder browsing shows empty state instead of real contents".
7. Push to main. Run `git fetch && git log origin/main -1 --oneline` and paste the output.

Do not touch anything outside the folder-navigation code path described above. Report back with all real code and command output requested, not summaries.
