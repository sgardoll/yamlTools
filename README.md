# FlutterFlow YAML Tools

Flutter app for exploring, editing, validating, and re-uploading FlutterFlow project YAML. It provides structured views of your project files, diffing, and an optional AI-assisted editing flow.

## Highlights

- Fetches project YAML via the FlutterFlow API (project ID + API token) and persists recent projects locally.
- Multiple viewers: flat list, tree view, and an edited-only list with git-style diffs.
- Inline validation and update: validate a single YAML file and push it back to FlutterFlow (uses the production `v2` API base, `POST /v2/updateProjectByYaml` with a base64-encoded ZIP payload).
- Optional AI assist: enter an OpenAI API key to generate proposed changes, review them, and apply selectively.
- Local-only secrets: API tokens/keys are stored on-device via secure storage; nothing is uploaded besides API requests you trigger.

## Requirements

- Flutter 3.24.x (workflow pins 3.24.3)
- Dart 3.4+
- Flutter web enabled (`flutter config --enable-web`)

## Run Locally

```bash
flutter pub get
flutter run -d chrome        # or another device
```

## Credentials

- **FlutterFlow**: Project ID + API token are required to fetch/validate/update YAML. They are cached locally.
- **OpenAI (optional)**: Add your key in the AI Assist panel to enable change proposals. The key is stored locally and only used for your requests.

## Deploy (GitHub Pages)

- CI/CD lives in `.github/workflows/pages.yml`; pushes to `main` (or manual dispatch) build `flutter build web --release --base-href /yamlTools/` and deploy to GitHub Pages.
- First time: enable Pages → Source: GitHub Actions in repo settings. The workflow publishes to the `gh-pages` environment/branch for you.
- Local manual build, if needed:
  ```bash
  flutter build web --release --base-href /yamlTools/ --web-renderer canvaskit --source-maps
  ```

## Development Notes

- API calls:
  - Validation: `POST /v2/validateProjectYaml` with a single-file base64 ZIP `{ fileKey: content }`.
  - Update: `POST /v2/updateProjectByYaml` with the same zipped format; no commit message or fallback endpoints are currently used.
  - Folder/key normalization: archive/plural prefixes map to API keys (`archive_pages/*` → `page/*`, `archive_custom_actions/*` → `customAction/*`) and file keys are derived from YAML content when present.
- Lint/tests: `flutter analyze` and `flutter test`.
- Generated web artifacts (build output, canvaskit, root-level flutter.js, icons, etc.) are intentionally excluded from the repo; rebuild locally when needed.

## License

MIT — see `LICENSE`.
