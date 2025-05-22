import 'package:flutter/material.dart';
import 'screens/home_screen.dart'; // Assuming HomeScreen will be in lib/screens
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
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
        cardTheme: CardTheme(
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
