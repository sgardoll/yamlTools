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
  - System prompt incorporates `YAML_Usage_Guidelines.md` as constraints

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

## State Management Patterns

Focus on **Definition vs Implementation** separation:
- **YAML defines state requirements**: Pages declare needed parameters (e.g., `userId`), actions specify arguments
- **Implementation happens elsewhere**: Action Flow Editor generates mutation logic, Custom Actions contain manual Dart code
- The Project API/YAML is declarative - it describes WHAT state is needed, not HOW it changes
- State mutations occur through FlutterFlow's visual Action Flow Editor or custom Dart code, never in YAML

## AI Prompting Patterns & Constraints

The `YAML_Usage_Guidelines.md` serves as a system prompt for AI YAML generation. Critical constraints:

### Context-First Generation Pattern
- Always provide full YAML context to AI before requesting modifications
- AI must preserve entire file structure, only changing requested sections
- Include pinned files as context for cross-file dependencies

### Key/Name Dichotomy (STRICT)
- **Machine key**: Unique identifier like `m8lp4` (often system-generated)
- **Human name**: Readable identifier like `handleBranchDeeplink`
- AI frequently confuses these - must enforce separation in `identifier` blocks:
  ```yaml
  identifier:
    name: handleBranchDeeplink  # Human-readable
    key: m8lp4                   # Machine identifier
	```

### Schema Enforcement (STRICT)
- Never accept bare type names like "String"
- Always require full schema: dataType: { scalarType: String, nonNullable: true }
- Enforce inputValue wrappers where required by FlutterFlow
- Color values must use either themeColor references or ARGB hex strings
### UI vs Metadata Separation
- UI Structure: JSON format (widget trees in -tree.json files)
- Metadata: YAML format (configuration, parameters, themes)
- AI must understand this distinction - never mix formats
- Page YAML contains metadata only; actual widgets are in separate JSON


## Project-Specific Conventions
File Path Patterns

Archive folders map to singular API keys:
'archive_pages/home.yaml' → 'page/home'

'archive_custom_actions/auth.yaml' → 'customAction/auth'
'theme.yaml' → 'theme' 

Root files use direct names. 

### **YAML Schema Requirements**

* Font sizes: fontSizeValue: { inputValue: 22 }  
* Colors: { themeColor: PRIMARY } or { value: "4294967295" }  
* Actions include dataType: { scalarType: Action, nestedParams: \[...\] }  
* Custom functions have identifier: { name: funcName, key: uniqueKey }  
* Arguments require full dataType specification with scalarType
