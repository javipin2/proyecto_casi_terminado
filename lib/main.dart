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
      title: 'Reserva de Canchas.   mira, estoy aciendo un proyecto en flutter y ya va a pasar a produccion. mi proyecto esta vinculado a firebase, te voy a pasar mi codigo uno por uno con sus advertencias y me las solucionaras, quiero que tambien me optimices los proceso de firebase y que quede funcionando de la forma mas optima posible todo. no quiero que cambies la logica ni la funcionalidad actual, solo solucionar las advertencias sin dañar mi codigo y si es posible optimizar el proceso de firebase en colsultas y permisos y todo lo relacionado a firebase ya que el cobra por uso, pero no quiero que me lo reestructures, solo optimiza si puedes, sino puedes, no lo hagas, es que tengo muchoos archivos dependientes de otros, por eso no puedo cambiar mucho los datos.pero no quiero que uses cache porque eso aveces influye con la actualizacion o visualizacion de datos en tiempo real, lo que no es recomendable en una app de reservas. quiero que se optimise con el firebase pero dentro de lo nnormal, me entiendes? vamos con el primer codigo. y con optimizar el codigo para firebase me refiero a ver que todo vaya bien, que no hayan redundancias y que no se hagan consultas innecesarias, me entiendes? vamos con el primer codigo.',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
      theme: ThemeData(primaryColor: Colors.green),
      home: const SplashScreen(),
    );
  }
}

