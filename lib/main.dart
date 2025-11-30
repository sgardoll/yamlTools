import 'dart:async';
import 'dart:ui' as ui;

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
  runZonedGuarded(() {
    // Ensure bindings are ready before we override pointer handling.
    WidgetsFlutterBinding.ensureInitialized();

    // Work around Flutter web trackpad events reporting kind=trackpad, which
    // trips the framework assertion in PointerMoveEvent (gestures/events.dart).
    _installTrackpadKindWorkaround();

    // Catch framework errors early and filter the specific noisy inspector error.
    FlutterError.onError = (FlutterErrorDetails details) {
      if (_isIgnorableInspectorError(details)) {
        debugPrint('Ignored DevTools inspector selection error after hot reload: '
            '${details.exceptionAsString()}');
        return;
      }
      FlutterError.presentError(details);
    };

    // Run the app in the same zone where bindings were initialized.
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

void _installTrackpadKindWorkaround() {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final previousHandler = dispatcher.onPointerDataPacket;

  dispatcher.onPointerDataPacket = (ui.PointerDataPacket packet) {
    final mappedData = packet.data
        .map(_coerceTrackpadToMouse)
        .toList(growable: false);
    final mappedPacket = ui.PointerDataPacket(data: mappedData);

    // Prefer the original handler installed by the framework.
    previousHandler?.call(mappedPacket);
  };

  debugPrint(
    'Trackpad pointer kind workaround installed: coercing trackpad events to mouse.',
  );
}

ui.PointerData _coerceTrackpadToMouse(ui.PointerData data) {
  if (data.kind != ui.PointerDeviceKind.trackpad) {
    return data;
  }

  // Rebuild the packet entry with a mouse kind to bypass the framework
  // assertion that rejects trackpad PointerMoveEvents on web.
  return ui.PointerData(
    viewId: data.viewId,
    embedderId: data.embedderId,
    timeStamp: data.timeStamp,
    change: data.change,
    kind: ui.PointerDeviceKind.mouse,
    signalKind: data.signalKind,
    device: data.device,
    pointerIdentifier: data.pointerIdentifier,
    physicalX: data.physicalX,
    physicalY: data.physicalY,
    physicalDeltaX: data.physicalDeltaX,
    physicalDeltaY: data.physicalDeltaY,
    buttons: data.buttons,
    obscured: data.obscured,
    synthesized: data.synthesized,
    pressure: data.pressure,
    pressureMin: data.pressureMin,
    pressureMax: data.pressureMax,
    distance: data.distance,
    distanceMax: data.distanceMax,
    size: data.size,
    radiusMajor: data.radiusMajor,
    radiusMinor: data.radiusMinor,
    radiusMin: data.radiusMin,
    radiusMax: data.radiusMax,
    orientation: data.orientation,
    tilt: data.tilt,
    platformData: data.platformData,
    scrollDeltaX: data.scrollDeltaX,
    scrollDeltaY: data.scrollDeltaY,
    panX: data.panX,
    panY: data.panY,
    panDeltaX: data.panDeltaX,
    panDeltaY: data.panDeltaY,
    scale: data.scale,
    rotation: data.rotation,
  );
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
