The Android build fails with three separate errors. Fix each precisely, show the actual file content before and after each fix (not a summary), and do not touch unrelated code.

ERROR 1 - lib/pages/home_page.dart, around line 458:
lib/pages/home_page.dart:458:9: Error: Expected an identifier, but got ')'.
lib/pages/home_page.dart:458:9: Error: Expected ']' before this.
Print the actual content of lines 440 to 465 of this file with line numbers first. This looks like a malformed list or argument list (likely a stray comma, a missing item, or a bracket closed in the wrong place). Based on what the real code shows, fix the syntax so the list/argument structure is valid, then print the same line range again showing the corrected version.

ERROR 2 - lib/pages/home_page.dart, around line 474:
lib/pages/home_page.dart:474:24: Error: The getter 'defaultTargetPlatform' isn't defined for the type '_TransferTabState'.
Print the actual content of lines 460 to 480 of this file with line numbers first. 'defaultTargetPlatform' is a top-level getter from 'package:flutter/foundation.dart', it is not a class member. Fix by either adding `import 'package:flutter/foundation.dart';` at the top of the file if missing, or correcting the reference if it's being called incorrectly (e.g. as `this.defaultTargetPlatform` instead of the plain top-level getter). Print the corrected lines after fixing.

ERROR 3 - lib/util/native/cross_file_converters.dart, around line 23:
lib/util/native/cross_file_converters.dart:23:37: Error: Member not found: 'audio'.
    AssetType.audio => FileType.audio,
Print the actual content of lines 1 to 40 of this file with line numbers first, including the full definition or import of whatever 'FileType' enum is used here. Determine whether 'FileType' is this app's own custom enum (defined somewhere in this codebase, likely lib/model or lib/util) or an enum from a package. If it's this app's own enum and it genuinely has no 'audio' member, add one (consistent with how the other members like 'image' and 'video' are defined and used elsewhere for audio file handling). If 'AssetType.audio' is the actual missing member instead (from the photo_manager package), fix that side instead. State clearly which side was actually missing before fixing it, based on what you find.

After fixing all three:
1. Do a full static review of all three changed files for balanced brackets, correct imports, and consistent syntax.
2. Commit with a message like "fix: resolve home_page.dart syntax/import errors and missing FileType.audio".
3. Explicitly push to main. Run `git fetch && git log origin/main -1 --oneline` and paste the output.

Report back with all the real file content you printed (before and after for each error), and the actual command output from the final step.
