import 'package:flutter/material.dart';

class AppTheme {
  // Core palette sourced from intro_logo.png
  static const Color primaryColor = Color(0xFF3367DC); // Royal Blue
  static const Color secondaryColor = Color(0xFF3EF6C3); // Tropical Mint
  static const Color backgroundColor = Color(0xFF080A40); // Deep Navy
  static const Color surfaceColor = Color(0xFF0B186C); // Deep Twilight
  static const Color cardColor = Color(0xFF093BA1); // Egyptian Blue
  static const Color dividerColor = Color(0xFF1B2F73); // Muted Royal Blue (derived)
  static const Color borderColor = Color(0xFF2142A6); // Softened Egyptian Blue (derived)

  // Text colors
  static const Color textPrimary = Color(0xFFFFFFFF); // White
  static const Color textSecondary = Color(0xFF9DAEF2); // Soft Royal Blue (derived)
  static const Color textMuted = Color(0xFF6576CC); // Subtle twilight tone (derived)
  static const Color textAccent = secondaryColor;

  // Status colors
  static const Color successColor = Color(0xFF22C55E); // Green-500
  static const Color errorColor = Color(0xFFEF4444); // Red-500
  static const Color warningColor = Color(0xFFF59E0B); // Amber-500
  static const Color infoColor = primaryColor; // Royal Blue

  // Validation status colors
  static const Color validColor = Color(0xFF22C55E); // Green-500
  static const Color updatedColor = primaryColor; // Royal Blue
  static const Color syncedColor = secondaryColor; // Tropical Mint

  // Button styles
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    textStyle: const TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 14,
      letterSpacing: -0.25,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    elevation: 2,
    shadowColor: primaryColor.withOpacity(0.25),
  );

  static ButtonStyle secondaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: surfaceColor,
    foregroundColor: secondaryColor,
    textStyle: const TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 14,
      letterSpacing: -0.25,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: secondaryColor.withOpacity(0.6), width: 1),
    ),
    elevation: 0,
  );

  static ButtonStyle outlineButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: secondaryColor,
    side: const BorderSide(color: secondaryColor, width: 1.5),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    textStyle: const TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 14,
      letterSpacing: -0.25,
    ),
  );

  static ButtonStyle dangerButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: errorColor,
    foregroundColor: Colors.white,
    textStyle: const TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 14,
      letterSpacing: -0.25,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    elevation: 2,
    shadowColor: errorColor.withOpacity(0.2),
  );

  // Card styles
  static BoxDecoration cardDecoration = BoxDecoration(
    color: cardColor,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: borderColor, width: 1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        offset: Offset(0, 2),
        blurRadius: 4,
      ),
    ],
  );

  static BoxDecoration panelDecoration = BoxDecoration(
    color: surfaceColor,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: borderColor, width: 1),
  );

  // Text styles with improved typography
  static const TextStyle headingXLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const TextStyle headingLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.5,
    height: 1.3,
  );

  static const TextStyle headingMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.25,
    height: 1.4,
  );

  static const TextStyle headingSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.25,
    height: 1.4,
  );

  static const TextStyle bodyXLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.5,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.4,
  );

  static const TextStyle captionLarge = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textMuted,
    letterSpacing: 0.25,
  );

  static const TextStyle captionSmall = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: textMuted,
    letterSpacing: 0.5,
  );

  static const TextStyle monospace = TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    color: textPrimary,
    height: 1.4,
    letterSpacing: 0.25,
  );

  static const TextStyle monospaceLarge = TextStyle(
    fontFamily: 'monospace',
    fontSize: 16,
    color: textPrimary,
    height: 1.4,
    letterSpacing: 0.25,
  );

  static const TextStyle monospaceSmall = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    color: textSecondary,
    height: 1.4,
    letterSpacing: 0.25,
  );

  // Input field decoration
  static InputDecoration inputDecoration({
    String? labelText,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool isError = false,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isError ? errorColor : dividerColor,
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isError ? errorColor : dividerColor,
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isError ? errorColor : secondaryColor,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: errorColor,
          width: 1,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: errorColor,
          width: 2,
        ),
      ),
      filled: true,
      fillColor: surfaceColor,
      labelStyle: TextStyle(color: textSecondary),
      hintStyle: TextStyle(color: textMuted),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  // Status badge styles
  static BoxDecoration statusBadgeDecoration(Color color) {
    return BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.3), width: 1),
    );
  }

  // Gradient decorations
  static BoxDecoration primaryGradientDecoration = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF0B186C), Color(0xFF3367DC)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(8),
    boxShadow: [
      BoxShadow(
        color: primaryColor.withOpacity(0.2),
        offset: Offset(0, 4),
        blurRadius: 8,
      ),
    ],
  );
}
