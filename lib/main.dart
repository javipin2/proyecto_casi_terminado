import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/providers/peticion_provider.dart';
import 'providers/sede_provider.dart';
import 'providers/reserva_provider.dart';
import 'providers/cancha_provider.dart';
import 'providers/audit_provider.dart';
import 'providers/version_provider.dart'; // ✅ NUEVO PROVIDER
import 'providers/reserva_recurrente_provider.dart';
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
  
  // Inicializar Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(
    MultiProvider(
      providers: [
        // ✅ AGREGAR VERSION PROVIDER PRIMERO (importante el orden)
        ChangeNotifierProvider(create: (context) => VersionProvider()),
        
        // Providers existentes
        ChangeNotifierProvider(create: (context) => ReservaProvider()),
        ChangeNotifierProvider(create: (context) => SedeProvider()),
        ChangeNotifierProvider(create: (context) => CanchaProvider()),
        ChangeNotifierProvider(create: (context) => AuditProvider()),
        ChangeNotifierProvider(create: (_) => ReservaRecurrenteProvider()),
        ChangeNotifierProvider(create: (_) => PeticionProvider()),
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
      theme: ThemeData(
        primaryColor: Colors.green,
        // ✅ CORREGIDO: Usar DialogThemeData en lugar de DialogTheme
        dialogTheme: const DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          elevation: 8,
        ),
        // Configuración para ElevatedButton
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}