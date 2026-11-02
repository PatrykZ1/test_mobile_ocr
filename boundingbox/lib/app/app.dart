import 'package:flutter/material.dart';
import 'theme.dart';
import '../navigation/home_shell.dart';

class BoundingBoxApp extends StatelessWidget {
  const BoundingBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'License Plate Detector',
      theme: AppTheme.dark,
      home: const HomeShell(),
    );
  }
}
