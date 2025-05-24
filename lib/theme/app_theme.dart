import 'package:flutter/material.dart';

class AppTheme {
  // Main colors - Updated to match professional design
  static const Color primaryColor = Color(0xFF3B82F6); // Blue-500
  static const Color secondaryColor = Color(0xFFEC4899); // Pink-500 for AI
  static const Color backgroundColor = Color(0xFF0F172A); // Slate-900
  static const Color surfaceColor = Color(0xFF1E293B); // Slate-800
  static const Color cardColor = Color(0xFF1E293B); // Slate-800
  static const Color dividerColor = Color(0xFF334155); // Slate-700
  static const Color borderColor = Color(0xFF475569); // Slate-600

  // Text colors
  static const Color textPrimary = Color(0xFFFFFFFF); // White
  static const Color textSecondary = Color(0xFF94A3B8); // Slate-400
  static const Color textMuted = Color(0xFF64748B); // Slate-500
  static const Color textAccent = Color(0xFF3B82F6); // Blue-500

  // Status colors
  static const Color successColor = Color(0xFF22C55E); // Green-500
  static const Color errorColor = Color(0xFFEF4444); // Red-500
  static const Color warningColor = Color(0xFFF59E0B); // Amber-500
  static const Color infoColor = Color(0xFF3B82F6); // Blue-500

  // Validation status colors
  static const Color validColor = Color(0xFF22C55E); // Green-500
  static const Color updatedColor = Color(0xFF3B82F6); // Blue-500
  static const Color syncedColor = Color(0xFF8B5CF6); // Violet-500

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
    shadowColor: primaryColor.withOpacity(0.2),
  );

  static ButtonStyle secondaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: surfaceColor,
    foregroundColor: textPrimary,
    textStyle: const TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 14,
      letterSpacing: -0.25,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: borderColor, width: 1),
    ),
    elevation: 0,
  );

  static ButtonStyle outlineButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: primaryColor,
    side: const BorderSide(color: primaryColor, width: 1.5),
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
    border: Border.all(color: dividerColor, width: 1),
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
    border: Border.all(color: dividerColor, width: 1),
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
          color: isError ? errorColor : borderColor,
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isError ? errorColor : borderColor,
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isError ? errorColor : primaryColor,
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
      colors: [Color(0xFF4F46E5), Color(0xFF3B82F6)],
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
