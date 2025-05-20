# YAML Tools

A Flutter web application for working with YAML files from FlutterFlow projects.

## Features

- Fetch and parse YAML data from FlutterFlow projects
- Extract and explore ZIP archives containing project files
- View and export individual YAML files
- Generate modified YAML outputs

## Live Demo

The application is deployed at: https://YOUR-USERNAME.github.io/yamlTools/

## Development

### Prerequisites

- Flutter SDK (3.13.0 or higher)
- Dart SDK

### Setup

1. Clone the repository:

   ```
   git clone https://github.com/YOUR-USERNAME/yamlTools.git
   cd yamlTools
   ```

2. Install dependencies:

   ```
   flutter pub get
   ```

3. Run the application:
   ```
   flutter run -d chrome
   ```

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
