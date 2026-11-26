import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/camera_page.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const PrimeApp());
}

class PrimeApp extends StatelessWidget {
  const PrimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '定焦 PRIME',
      debugShowCheckedModeBanner: false,
      theme: PrimeTokens.theme(),
      home: const CameraPage(),
    );
  }
}
