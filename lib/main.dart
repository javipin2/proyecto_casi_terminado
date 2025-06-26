import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/sede_provider.dart';
import 'providers/reserva_provider.dart';
import 'providers/cancha_provider.dart';
import 'screens/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';

// Declara un RouteObserver global
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeDateFormatting('es');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ReservaProvider()),
        ChangeNotifierProvider(create: (context) => SedeProvider()),
        ChangeNotifierProvider(create: (context) => CanchaProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reserva de Canchas',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
      theme: ThemeData(primaryColor: Colors.green),
      home: const SplashScreen(),
    );
  }
}