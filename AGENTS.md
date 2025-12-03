# Repository Guidelines

Use this guide when contributing to the FlutterFlow YAML Tools app. Keep changes small, validated, and aligned with API/AI workflows.

## Project Structure & Module Organization
- `lib/services/`: `FlutterFlowApiService` (validate via `/v2/validateProjectYaml` before `/v2/updateProjectByYaml` with fallbacks), `YamlFileUtils` for archive prefix mapping (`archive_pages/home.yaml` → `page/home`) and key repair, and `services/ai/` for OpenAI prompts constrained by `YAML_Usage_Guidelines.md`.
- `lib/widgets/`: `YamlContentViewer`, `AIAssistPanel`, `ModernYamlTree`, `DiffViewWidget`, and supporting UI.
- `lib/storage/`: `PreferencesManager` handles secure credentials and recent project cache.
- `test/`: coverage for API, AI, and utility logic; add `_test.dart` files mirroring the module under test.

## Build, Test, and Development Commands
- Install deps: `flutter pub get`.
- Run web app: `flutter run -d chrome` (enable web: `flutter config --enable-web`).
- Static analysis: `flutter analyze`; format if needed with `dart format .`.
- Tests: `flutter test`.
- Release web build: `flutter build web --release --base-href /yamlTools/ --web-renderer canvaskit --source-maps`.

## Coding Style & Naming Conventions
- Dart: follow analyzer rules, 2-space indent, purposeful comments, and keep methods small.
- YAML: preserve full files, edit only requested sections, keep `identifier.name` (human) and `identifier.key` (machine) distinct, supply full `dataType` blocks (e.g., `dataType: { scalarType: String, nonNullable: true }`), wrap inputs in `inputValue`, use themeColor or ARGB hex for colors, and keep UI JSON separate from YAML metadata.
- File keys must align with YAML content keys before API calls; rely on `YamlFileUtils` to normalize archive prefixes and fix mismatches.

## Testing Guidelines
- Place tests in `test/` with descriptive names (e.g., `flutterflow_api_service_test.dart`).
- Cover validation-before-update sequencing, fallback endpoints, key normalization, AI structured JSON parsing, and tree/diff behavior.
- Ensure test fixtures exercise updates across varied subdirectories (pages, custom actions, themes, archive folders) to catch path/key edge cases.
- Prefer deterministic fixtures; avoid networked tests and add regressions for fixes.

## Commit & Pull Request Guidelines
- Use concise, conventional-style commits (`feat(api): ...`, `docs(README): ...`) in line with repo history.
- PRs should include purpose/issue link, short change list, how to test, and screenshots or text diffs for UI updates.
- Run `flutter analyze` and `flutter test` before opening a PR; note results in the description. Exclude secrets and built artifacts (credentials stay local via `PreferencesManager`).

## Security & Configuration Tips
- Do not commit API or OpenAI keys; they remain local via `PreferencesManager`. Avoid logging secrets in debug output.
- When editing YAML, follow the context-first pattern: give AI full file context, pin related files for cross-file dependencies, and keep YAML declarative (state mutations stay in Action Flow or custom Dart).
