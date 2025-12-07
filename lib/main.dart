import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart'; // Assuming HomeScreen will be in lib/screens
import 'theme/app_theme.dart';

bool _isIgnorableInspectorError(FlutterErrorDetails details) {
  try {
    final msg = details.exceptionAsString();
    final stackStr = details.stack?.toString() ?? '';
    // Narrow filter: only ignore the known DevTools inspector selection error
    // that occurs right after hot reload when a stale inspector node id is restored.
    if (msg.contains('Id does not exist') &&
        (stackStr.contains('service extension') || stackStr.contains('toObject'))) {
      return true;
    }
  } catch (_) {
    // Fall through to not ignore if anything unexpected happens
  }
  return false;
}

void main() {
  // Catch framework errors early and filter the specific noisy inspector error.
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_isIgnorableInspectorError(details)) {
      debugPrint('Ignored DevTools inspector selection error after hot reload: '
          '${details.exceptionAsString()}');
      return;
    }
    FlutterError.presentError(details);
  };

  // Also guard async errors that may bubble outside of FlutterError.
  runZonedGuarded(() {
    runApp(const MyApp());
  }, (Object error, StackTrace stack) {
    final msg = error.toString();
    if (msg.contains('Id does not exist') &&
        (stack.toString().contains('service extension') ||
            stack.toString().contains('toObject'))) {
      debugPrint('Ignored DevTools inspector selection error (zoned) after hot reload: '
          '$error');
      return;
    }
    debugPrint('Uncaught zone error: $error');
  });
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlutterFlow YAML Editor AI',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppTheme.primaryColor,
          secondary: AppTheme.secondaryColor,
          surface: AppTheme.surfaceColor,
          background: AppTheme.backgroundColor,
          onBackground: AppTheme.textPrimary,
          onSurface: AppTheme.textPrimary,
          error: AppTheme.errorColor,
        ),
        scaffoldBackgroundColor: AppTheme.backgroundColor,
        cardTheme: CardThemeData(
          color: AppTheme.surfaceColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppTheme.backgroundColor,
          elevation: 0,
          titleTextStyle: AppTheme.headingMedium,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: AppTheme.primaryButtonStyle,
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: AppTheme.outlineButtonStyle,
        ),
        textTheme: TextTheme(
          titleLarge: AppTheme.headingLarge,
          titleMedium: AppTheme.headingMedium,
          titleSmall: AppTheme.headingSmall,
          bodyLarge: AppTheme.bodyLarge,
          bodyMedium: AppTheme.bodyMedium,
          bodySmall: AppTheme.bodySmall,
        ),
        dividerTheme: DividerThemeData(
          color: AppTheme.dividerColor,
          thickness: 1,
        ),
      ),
      home: HomeScreen(),
    );
  }
}
