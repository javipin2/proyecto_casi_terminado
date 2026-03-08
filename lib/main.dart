import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:reserva_canchas/providers/audit_provider.dart';
import 'providers/sede_provider.dart';
import 'providers/reserva_provider.dart';
import 'providers/cancha_provider.dart';
import 'providers/version_provider.dart'; // ✅ NUEVO PROVIDER
import 'providers/auth_provider.dart'; // ✅ NUEVO PROVIDER DE AUTENTICACIÓN
import 'providers/reserva_recurrente_provider.dart';
import 'providers/ciudad_provider.dart';
import 'providers/lugar_provider.dart';
import 'providers/promocion_provider.dart';
import 'screens/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/cleanup_service.dart'; // ✅ SERVICIO DE LIMPIEZA AUTOMÁTICA
import 'services/index_error_service.dart'; // ✅ SERVICIO DE DETECCIÓN DE ERRORES DE ÍNDICES
import 'services/push_notification_service.dart'; // ✅ NOTIFICACIONES PUSH (PROMOCIONES)

// Declara un RouteObserver global
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

void main() async {
  if (kIsWeb) {
    // En web todo debe correr en la misma zona que runApp para evitar "Zone mismatch".
    runZonedGuarded(() async {
      await _initAndRunApp();
    }, (error, stack) {
      if (error.toString().contains('ViewInsets cannot be negative') ||
          error.toString().contains('_viewInsets.isNonNegative')) {
        if (kDebugMode) {
          debugPrint('Web: error conocido al cerrar teclado (se ignora): $error');
        }
        return;
      }
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'main',
        context: ErrorDescription('Error no capturado'),
      ));
    });
  } else {
    await _initAndRunApp();
  }
}

Future<void> _initAndRunApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeDateFormatting('es');

  if (!kIsWeb) {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          systemNavigationBarContrastEnforced: true,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      );
    } catch (_) {}
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  CleanupService.programarLimpiezaAutomatica();
  IndexErrorService.generateIndexReport();
  try {
    await PushNotificationService().initialize();
  } catch (e) {
    if (kDebugMode && kIsWeb) {
      debugPrint('PushNotificationService (web): $e');
    }
  }

  _runMyApp();
}

void _runMyApp() {
  runApp(
    MultiProvider(
      providers: [
        // ✅ AGREGAR AUTH PROVIDER PRIMERO (más importante)
        ChangeNotifierProvider(create: (context) => AuthProvider()),
        
        // ✅ AGREGAR VERSION PROVIDER SEGUNDO
        ChangeNotifierProvider(create: (context) => VersionProvider()),
        
        // Providers existentes
        ChangeNotifierProvider(create: (context) => ReservaProvider()),
        // ✅ SedeProvider dependiente de AuthProvider para precargar sedes al cambiar de cuenta
        ChangeNotifierProxyProvider<AuthProvider, SedeProvider>(
          create: (context) => SedeProvider(),
          update: (context, auth, sedeProv) {
            final prov = sedeProv ?? SedeProvider();
            final lugarId = auth.currentLugarId;
            if (lugarId == null) {
              prov.clearLugar();
            } else {
              if (prov.lugarId != lugarId) {
                prov.setLugar(lugarId);
                // Disparar carga inmediata de sedes al cambiar de cuenta/lugar
                prov.fetchSedes();
              }
            }
            return prov;
          },
        ),
        // ✅ CanchaProvider dependiente de AuthProvider para precargar canchas al cambiar de cuenta
        ChangeNotifierProxyProvider<AuthProvider, CanchaProvider>(
          create: (context) => CanchaProvider(),
          update: (context, auth, canchaProv) {
            final prov = canchaProv ?? CanchaProvider();
            final lugarId = auth.currentLugarId;
            if (lugarId == null) {
              prov.clearLugar();
            } else {
              if (prov.lugarId != lugarId) {
                prov.setLugar(lugarId);
                // Cargar todas las canchas del lugar al cambiar de cuenta
                prov.fetchAllCanchas();
              }
            }
            return prov;
          },
        ),
        ChangeNotifierProvider(create: (context) => AuditProvider()),
        ChangeNotifierProvider(create: (_) => ReservaRecurrenteProvider()),
        
        // ✅ NUEVOS PROVIDERS PARA CIUDADES Y LUGARES
        ChangeNotifierProvider(create: (context) => CiudadProvider()),
        ChangeNotifierProvider(create: (context) => LugarProvider()),
        
        // ✅ NUEVO PROVIDER PARA PROMOCIONES (centralizado)
        ChangeNotifierProvider(create: (context) => PromocionProvider()),
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
      // Respetar en todas las pantallas los bordes del sistema (notch, barra de navegación).
      // En web no usamos SafeArea en el root para evitar el error de ViewInsets al cerrar el teclado.
      builder: (context, child) {
        if (kIsWeb) {
          return child ?? const SizedBox.shrink();
        }
        return SafeArea(
          top: true,
          bottom: true,
          left: true,
          right: true,
          child: child ?? const SizedBox.shrink(),
        );
      },
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