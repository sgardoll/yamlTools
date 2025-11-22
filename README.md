# FlutterFlow YAML Tools

A Flutter application that helps you visualize, explore, and edit YAML files from FlutterFlow projects. It provides multiple ways to view and interact with FlutterFlow YAML structure.

## Key Features

### Git-like Diff View

When you modify a YAML file, the application shows your changes in a side-by-side git-like diff view:

- Green highlighting for added lines
- Red highlighting for removed lines
- Easy visualization of what changed before and after your edits
- Clean, intuitive interface for understanding the impact of your modifications

### 1. Tree View Visualization

The application now provides a hierarchical tree view for your FlutterFlow YAML structure! This intuitive visualization makes it easy to understand the relationship between pages, components, and widget trees.

- **Color-coded nodes**: Different types of components are color-coded for easy identification:

  - Components (purple)
  - Containers (teal)
  - Layout widgets like Columns (indigo)
  - Standard widgets (green)
  - Collections/data nodes (orange)

- **Expandable/collapsible nodes**: Click on a node to expand or collapse its children, allowing you to focus on specific parts of the widget tree.

- **Interactive navigation**: Click on leaf nodes to view their content in the editor.

### 2. Multiple View Options

Choose the view that best suits your needs:

1. **Edited Files**: View only files you've modified during your session
2. **Flat List**: View all YAML files in a simple list format (traditional view)
3. **Tree View**: Visualize the hierarchical structure of your FlutterFlow project

### 3. Authentication & Project Management

- Save and reuse API tokens
- View recent projects
- Fetch YAML from FlutterFlow projects

## Getting Started

1. Enter your FlutterFlow Project ID and API Token
2. Click "Fetch YAML" to download your project YAML files
3. Explore your project using the different view options:
   - Switch to "Tree View" to see the hierarchical structure
   - Use "Flat List" to see all files
   - Use "Edited Files" to focus on modifications

## How to Get Your FlutterFlow API Token

1. Log in to FlutterFlow
2. Go to Account Settings
3. Generate a new API token

## How the Tree View Works

The tree view parses the file paths of your YAML files to reconstruct the widget tree structure. It intelligently identifies different types of nodes based on naming patterns:

- Files in `collections/` are shown as collection nodes
- Files in `component/` are shown as component nodes
- Files containing `Container` in their ID are shown as container widgets
- Files containing `Column` in their ID are shown as layout widgets
- Other widget files are shown as standard widgets

This provides a much more intuitive visualization than a flat list of files.

## Coming Soon

- Built-in verification flow to validate YAML changes against FlutterFlow constraints before upload.
- One-click re-upload pipeline to push verified YAML back into your FlutterFlow project without leaving the app.
- Progress feedback and safety checks so you can confidently round-trip edits from download to re-upload.

## Development

This project is built with Flutter and can be run on web or desktop platforms.

### Running the Project

```bash
flutter pub get
flutter run -d chrome
```

## Dependencies

- flutter
- http
- yaml
- archive
- shared_preferences
- path

## Features

- Fetch and parse YAML data from FlutterFlow projects
- Extract and explore ZIP archives containing project files
- View and export individual YAML files
- Generate modified YAML outputs

## Live Demo

The application is deployed at: https://YOUR-USERNAME.github.io/yamlTools/

## Deployment

The application is automatically deployed to GitHub Pages when changes are pushed to the main branch, using GitHub Actions.

### Manual Deployment

To manually deploy the application:

1. Build the web version:

   ```
   flutter build web --release --base-href /yamlTools/
   ```

2. Deploy the contents of the `build/web` directory to your web server or GitHub Pages.

## GitHub Pages Configuration

This repository is set up to deploy to GitHub Pages using GitHub Actions:

1. The workflow defined in `.github/workflows/deploy.yml` builds and deploys the app
2. The deployment uses the `gh-pages` branch
3. GitHub Pages is configured to serve from this branch

### First-time Setup for GitHub Pages

1. Push changes to the repository
2. Go to your repository on GitHub
3. Navigate to Settings > Pages
4. Set the Source to "GitHub Actions"
5. The workflow will deploy your app automatically

## License

[MIT License](LICENSE)
# Trigger deployment
