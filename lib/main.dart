import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'diagnostics/app_logger.dart';
import 'screens/home_screen.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      AppLogger.log('${details.exceptionAsString()}\n${details.stack}', level: 'ERROR');
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      AppLogger.log('$error\n$stack', level: 'ERROR');
      return true;
    };

    runApp(const QRDataApp());
  }, (Object error, StackTrace stack) {
    AppLogger.log('$error\n$stack', level: 'ERROR');
  });
}

class QRDataApp extends StatelessWidget {
  const QRDataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'QRData',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
