# Repository Guidelines

Use this guide when contributing to the FlutterFlow YAML Tools app. Keep changes small, validated, and consistent with the existing API/AI workflows.

## Project Structure & Module Organization
- `lib/services/`: `FlutterFlowApiService` (validate before update with `/v2/validateProjectYaml`, primary `/v2/updateProjectByYaml` plus fallbacks), `YamlFileUtils` for key/path inference and archive prefix mapping (e.g., `archive_pages/home.yaml` → `page/home`), and `services/ai/` for OpenAI prompts enforced by `YAML_Usage_Guidelines.md`.
- `lib/widgets/`: core UI pieces such as `YamlContentViewer`, `AIAssistPanel`, `ModernYamlTree`, and `DiffViewWidget` that drive editing, browsing, and diff review flows.
- `lib/storage/`: `PreferencesManager` for secure API/AI credential storage and recent project cache.
- `test/`: Dart tests for API, AI, and utility logic; add new `_test.dart` files alongside related code.

## Build, Test, and Development Commands
- Install deps: `flutter pub get`.
- Run web app: `flutter run -d chrome` (ensure `flutter config --enable-web`).
- Static analysis: `flutter analyze` (run before submitting PRs).
- Tests: `flutter test` (cover service logic, YAML inference, and AI JSON parsing).
- Release web build: `flutter build web --release --base-href /yamlTools/ --web-renderer canvaskit --source-maps`.

## Coding Style & Naming Conventions
- Dart: follow analyzer rules, 2-space indent, `dart format .` if formatting drifts. Keep code comments purposeful.
- YAML schema (strict): keep full files intact; only edit requested sections. Separate human `identifier.name` from machine `identifier.key`. Always specify full `dataType` blocks (e.g., `dataType: { scalarType: String, nonNullable: true }`), wrap inputs in `inputValue`, and use themeColor or ARGB hex for colors. Never mix UI JSON with YAML metadata.
- File keys must mirror YAML content keys before API calls; auto-fix mismatches via `YamlFileUtils` when needed.

## Testing Guidelines
- Place tests in `test/` with descriptive names (e.g., `flutterflow_api_service_test.dart`), mirroring the module under test.
- Focus on critical workflows: validation-before-update sequencing, fallback endpoints, key normalization, AI structured response parsing, and tree/diff behavior.
- Prefer deterministic fixtures; avoid networked tests. Add regression tests for bug fixes.

## Commit & Pull Request Guidelines
- Use concise, conventional-style commits (`feat(api): ...`, `docs(README): ...`) aligned with existing history.
- PRs should include: purpose/issue link, summary of key changes, how to reproduce/test, and screenshots or text diffs for UI-facing updates.
- Run `flutter analyze` and `flutter test` before opening a PR; note results in the description. Exclude secrets and built artifacts from commits (credentials stay local via `PreferencesManager`).

## Security & Configuration Tips
- Do not commit API or OpenAI keys; they are stored locally and securely. Avoid logging secrets in debug output.
- When editing YAML, respect the context-first generation pattern: provide full file context to AI, pin related files for cross-file dependencies, and preserve declarative metadata (state mutations belong to Action Flow or custom Dart, not YAML).
