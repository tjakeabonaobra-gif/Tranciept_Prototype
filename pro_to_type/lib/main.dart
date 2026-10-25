import 'package:flutter/material.dart';
import 'screens/navigation_screen.dart';

void main() {
  runApp(const TranCeiptApp());
}

class TranCeiptApp extends StatelessWidget {
  const TranCeiptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TranCeipt — Legazpi Nav',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const NavigationScreen(),
    );
  }
}