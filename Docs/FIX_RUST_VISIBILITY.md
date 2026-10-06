TASK: Fix real Rust compile errors from the Android build. Do NOT change any #[frb] function signatures. Do NOT edit frb_generated.rs or anything under lib/rust (machine-generated).

Run git pull first (a bot pushed generated files).

Work only in packages/localsend_isolates/rust/src/api/pairing.rs unless stated. PRINT the lines before and after every fix.

ERROR 1 (E0603): JoinedPairingDevice, PairingDeviceInfo, PairingSessionEvent, PairingSessionSnapshot are "private struct import". In api/pairing.rs (~line 9) the `use localsend::pairing::{...}` is private, but frb_generated.rs refers to them as crate::api::pairing::X. Change that import to `pub use` for every type on that line.

ERROR 2 (E0603 + E0616): StagedTempFiles (~line 398) is a private struct with private field `paths`. Make it `pub struct` and `pub paths`. Then grep frb_generated.rs for "crate::api::pairing::" and confirm EVERY type it names is pub with pub fields. Fix any that are not.

ERROR 3 (E0308, ~line 247): .prepare_upload(request, ...) expects PrepareUploadRequestDto but gets PrepareUploadRequestDtoV2. The method is in packages/core/src/http/client/mod.rs:104. First PRINT that method signature and both DTO struct definitions. Find how an existing working caller (api/http.rs or api/server.rs) builds this request, and use the same type or conversion. Do not guess.

ERROR 4 (E0424, E0425, not shown yet): Read api/pairing.rs fully. Find (a) any use of `self` in a function with no self parameter, (b) any name, function or type that is undefined or not imported. Fix using the real definitions. Print each fix.

Ignore the unused-import warning.

FINISH: git add, commit "fix: pairing visibility and DTO type for FRB build", git push origin main. If the push fails with an auth error, STOP and say so (I will push manually). Show git log -1 --stat and the commit hash.
