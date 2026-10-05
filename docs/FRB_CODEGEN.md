TASK: Add a manual GitHub Actions workflow that regenerates flutter_rust_bridge bindings and commits them. Do NOT edit any Rust or Dart source except as stated.

1. First commit and push the pending uncommitted stream-argument-order change as-is.

2. PRINT (do not guess) the full contents of:
   - every file in .github/workflows/ (especially the Android build workflow)
   - flutter_rust_bridge.yaml (find it with: find . -name "flutter_rust_bridge.yaml" -not -path "*/node_modules/*")
   - the flutter_rust_bridge version in Cargo.toml and pubspec.yaml
   - rust-toolchain.toml

3. Create .github/workflows/frb-codegen.yml:
   - name: Regenerate FRB bindings
   - trigger: workflow_dispatch only
   - permissions: contents: write
   - steps: checkout; set up Flutter and Rust using EXACTLY the same versions/actions as the existing Android build workflow; cargo install flutter_rust_bridge_codegen with the exact version matching Cargo.toml (--locked); flutter pub get; run flutter_rust_bridge_codegen generate from the directory containing flutter_rust_bridge.yaml
   - then git add ONLY the generated output paths named in flutter_rust_bridge.yaml, commit "chore: regenerate FRB bindings", push to main
   - also upload the generated files as a workflow artifact so nothing is lost if the push fails
   - if the codegen step fails, the log must show the full error

4. Confirm the pairing functions (start/stop session, join, event stream) are inside the rust_input module that the yaml scans. If they are not, print where they are and tell me; do not move them silently.

5. Commit and push the workflow to main. Show git log -1 --stat and the commit hash.
