# FlutterFlow YAML Tools - AI Coding Agent Instructions

## Project Overview

Flutter web app for editing FlutterFlow project YAML files with API integration and AI assistance. The app fetches, validates, and updates YAML configurations through the FlutterFlow API while providing multiple viewing modes and optional OpenAI-powered editing suggestions.

## Architecture & Key Components

### Service Layer (`lib/services/`)

- **FlutterFlowApiService**: Handles all FlutterFlow API interactions with multi-endpoint fallback strategy

  - Primary: `POST /v2/updateProjectByYaml`
  - Fallback: `PUT /v2/projectYaml`
  - Legacy: `POST /v1/projects/{id}/yaml`
  - Always validate with `/v2/validateProjectYaml` before updates
  - File keys must match YAML content keys exactly (e.g., `page/id-Scaffold_123` not `pages/id-Scaffold_123.yaml`)

- **AIService** (`ai/ai_service.dart`): OpenAI integration for YAML modifications

  - Uses GPT-4 with structured JSON responses
  - Preserves full file content, only modifying requested sections
  - Enforces FlutterFlow schema (inputValue wrappers, themeColor refs)

- **YamlFileUtils**: Critical path/key inference logic
  - Maps folder prefixes: `archive_pages/` → `page/`, `archive_custom_actions/` → `customAction/`
  - Auto-fixes mismatched YAML keys before API calls
  - Infers file paths from YAML content structure

### Storage (`lib/storage/`)

- **PreferencesManager**: Secure credential storage using flutter_secure_storage
  - API tokens never leave device, stored encrypted
  - Recent projects cached in SharedPreferences
  - Automatic migration from legacy storage

### UI Components (`lib/widgets/`)

- **YamlContentViewer**: Main editor with validation/update workflow
- **AIAssistPanel**: Review and apply AI-suggested changes
- **ModernYamlTree**: Hierarchical file browser
- **DiffViewWidget**: Git-style change visualization

## Critical Workflows

### YAML Update Flow

1. User edits → Auto-fix key mismatch → Validate via API
2. Build file key candidates (multiple formats attempted)
3. Update via primary endpoint, fallback if needed
4. Track validation/sync timestamps per file

### AI Assist Flow

1. Pin relevant files → Generate prompt with context
2. AI returns structured JSON with file modifications
3. User reviews diffs → Selective application
4. Stage changes → Validate → Push to FlutterFlow

## Project-Specific Conventions

### File Path Patterns

```dart
// Archive folders map to singular API keys:
'archive_pages/home.yaml' → 'page/home'
'archive_custom_actions/auth.yaml' → 'customAction/auth'
'theme.yaml' → 'theme' // Root files use direct names
```

### YAML Schema Requirements

- Font sizes: `fontSizeValue: { inputValue: 22 }`
- Colors: `{ themeColor: PRIMARY }` or `{ value: "4294967295" }`
- Actions include `dataType: { scalarType: Action, nestedParams: [...] }`
- Custom functions have `identifier: { name: funcName, key: uniqueKey }`

### Error Handling

- Network errors trigger fallback endpoints automatically
- Validation errors (4xx) surface immediately without masking
- DevTools inspector errors filtered after hot reload (see main.dart)

## Development Commands

```bash
# Local development
flutter pub get
flutter run -d chrome

# Production build for GitHub Pages
flutter build web --release --base-href /yamlTools/ --web-renderer canvaskit

# Testing
flutter test
flutter analyze
```

## Environment Setup

- Flutter 3.24.x (pinned to 3.24.3 in CI)
- Dart 3.4+
- Web must be enabled: `flutter config --enable-web`
- Credentials stored locally via secure storage

## Key Files

- `lib/services/flutterflow_api_service.dart` - API integration core
- `lib/services/yaml_file_utils.dart` - Path/key mapping logic
- `lib/screens/home_screen.dart` - Main app orchestration
- `YAML_Usage_Guidelines.md` - FlutterFlow YAML schema reference
