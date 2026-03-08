import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'ciudad_screen.dart';
import 'lugar_screen.dart';
import '../providers/version_provider.dart';
import '../providers/auth_provider.dart';
import '../services/version_service.dart';
import '../services/ciudad_preference_service.dart';
import '../services/push_notification_service.dart';
import 'update_required_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'admin/super_admin_dashboard.dart';
import 'admin/encargado_dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  Timer? _navigationTimer;
  
  String _statusMessage = 'Iniciando aplicación...';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    // Mostrar aviso si las notificaciones están bloqueadas (permiso denegado antes de tener context)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.onPermissionDenied = (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      };
      for (final msg in PushNotificationService.pendingPermissionDeniedMessages) {
        PushNotificationService.onPermissionDenied!(msg);
      }
      PushNotificationService.pendingPermissionDeniedMessages.clear();
    });

    // Inicializar verificación de versiones
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _statusMessage = 'Inicializando autenticación...';
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final versionProvider = Provider.of<VersionProvider>(context, listen: false);
      
      // Inicializar el provider de autenticación PRIMERO
      await authProvider.initialize();
      
      setState(() {
        _statusMessage = 'Verificando versión...';
      });
      
      // Inicializar el provider de versiones
      await versionProvider.initialize();
      
      setState(() {
        _statusMessage = 'Consultando actualizaciones...';
      });

      // Verificar actualizaciones
      await versionProvider.checkForUpdates();

      // Determinar siguiente pantalla basado en el estado
      await _handleVersionCheck(versionProvider, authProvider);

    } catch (e) {
      debugPrint('Error inicializando app: $e');
      // En caso de error, continuar normalmente después de un delay
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _navigateToMainApp(authProvider);
    }
  }

  Future<void> _handleVersionCheck(VersionProvider versionProvider, AuthProvider authProvider) async {
    final updateStatus = versionProvider.updateStatus;

    switch (updateStatus) {
      case UpdateStatus.forceUpdate:
        // Actualización obligatoria - ir directo a pantalla de actualización
        setState(() {
          _statusMessage = 'Actualización requerida';
        });
        await Future.delayed(const Duration(milliseconds: 500));
        _navigateToUpdateScreen();
        break;

      case UpdateStatus.maintenance:
        // Modo mantenimiento - ir a pantalla de mantenimiento
        setState(() {
          _statusMessage = 'Aplicación en mantenimiento';
        });
        await Future.delayed(const Duration(milliseconds: 500));
        _navigateToUpdateScreen();
        break;

      case UpdateStatus.optionalUpdate:
        // Actualización opcional - mostrar y luego continuar
        setState(() {
          _statusMessage = 'Nueva versión disponible';
        });
        await Future.delayed(const Duration(milliseconds: 1000));
        _navigateToMainAppWithOptionalUpdate(versionProvider, authProvider);
        break;

      case UpdateStatus.upToDate:
        // Todo bien - continuar normalmente
        setState(() {
          _statusMessage = 'Aplicación actualizada';
        });
        await Future.delayed(const Duration(milliseconds: 500));
        _navigateToMainApp(authProvider);
        break;

      case UpdateStatus.error:
        // Error verificando - continuar normalmente pero loggear
        debugPrint('Error verificando versión: ${versionProvider.errorMessage}');
        setState(() {
          _statusMessage = 'Continuando...';
        });
        await Future.delayed(const Duration(milliseconds: 500));
        _navigateToMainApp(authProvider);
        break;
    }
  }

  void _navigateToMainApp(AuthProvider authProvider) async {
    if (!mounted) return;

    _navigationTimer = Timer(const Duration(milliseconds: 500), () async {
      if (mounted) {
        // Verificar si el usuario está autenticado
        if (authProvider.isAuthenticated) {
          // Navegar al dashboard correspondiente según el rol
          _navigateToDashboard(authProvider);
        } else {
          // Verificar si es la primera vez o si hay ciudad guardada
          final isFirstTime = await CiudadPreferenceService.isFirstTime();
          final hasSelectedCiudad = await CiudadPreferenceService.hasSelectedCiudad();
          
          if (isFirstTime || !hasSelectedCiudad) {
            // Primera vez o no hay ciudad guardada -> ir a selección de ciudades
            _navigateToCiudadScreen();
          } else {
            // Hay ciudad guardada -> ir directamente a lugares
            final ciudad = await CiudadPreferenceService.getSelectedCiudad();
            if (ciudad != null) {
              _navigateToLugarScreen(ciudad);
            } else {
              _navigateToCiudadScreen();
            }
          }
        }
      }
    });
  }

  void _navigateToUpdateScreen() {
    if (!mounted) return;

    _navigationTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const UpdateRequiredScreen(canDismiss: false),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.1),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            transitionDuration: const Duration(milliseconds: 1000),
          ),
        );
      }
    });
  }

  void _navigateToMainAppWithOptionalUpdate(VersionProvider versionProvider, AuthProvider authProvider) async {
    if (!mounted) return;

    _navigationTimer = Timer(const Duration(milliseconds: 500), () async {
      if (mounted) {
        // Verificar si el usuario está autenticado
        if (authProvider.isAuthenticated) {
          // Navegar al dashboard correspondiente según el rol
          _navigateToDashboard(authProvider);
        } else {
          // Verificar si es la primera vez o si hay ciudad guardada
          final isFirstTime = await CiudadPreferenceService.isFirstTime();
          final hasSelectedCiudad = await CiudadPreferenceService.hasSelectedCiudad();
          
          if (isFirstTime || !hasSelectedCiudad) {
            // Primera vez o no hay ciudad guardada -> ir a selección de ciudades
            _navigateToCiudadScreen();
          } else {
            // Hay ciudad guardada -> ir directamente a lugares
            final ciudad = await CiudadPreferenceService.getSelectedCiudad();
            if (ciudad != null) {
              _navigateToLugarScreen(ciudad);
            } else {
              _navigateToCiudadScreen();
            }
          }
        }

        // Mostrar dialog de actualización opcional después de la navegación
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            _showOptionalUpdateDialog(versionProvider);
          }
        });
      }
    });
  }

  void _navigateToCiudadScreen() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const CiudadScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  void _navigateToLugarScreen(ciudad) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            LugarScreen(ciudad: ciudad),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  void _navigateToDashboard(AuthProvider authProvider) {
    if (!mounted) return;

    Widget destination;
    
    if (authProvider.isSuperAdmin) {
      destination = const SuperAdminDashboardScreen();
    } else if (authProvider.userRole == 'admin') {
      destination = const AdminDashboardScreen();
    } else if (authProvider.isEncargado) {
      destination = const EncargadoDashboardScreen();
    } else {
      // Si no tiene un rol válido, ir a la pantalla principal
      destination = const CiudadScreen();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            )),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Future<void> _showOptionalUpdateDialog(VersionProvider versionProvider) async {
    final shouldUpdate = await versionProvider.showOptionalUpdateDialog(context);
    
    if (shouldUpdate && mounted) {
      final success = await versionProvider.openUpdateUrl();
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el enlace de descarga'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Imagen de fondo
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/fondo2.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Degradado encima de la imagen
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromARGB(0, 255, 255, 255), // Transparente
                  Color.fromARGB(232, 0, 0, 0), // Oscuro
                ],
              ),
            ),
          ),
          // Contenido principal
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _opacityAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo principal
                        Container(
                          width: 400,
                          height: 300,
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(0, 255, 255, 255),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color.fromARGB(38, 0, 0, 0)
                                    .withOpacity(0.1),
                                blurRadius: 50,
                                spreadRadius: 0,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/demo.png',
                            width: 240,
                            height: 240,
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint('Error cargando logo: $error');
                              return const Icon(Icons.error,
                                  color: Colors.red, size: 70);
                            },
                          ),
                        ),
                        
                        const SizedBox(height: 40),
                        
                        // Indicador de carga y mensaje de estado
                        Column(
                          children: [
                            // Indicador de progreso
                            Consumer<VersionProvider>(
                              builder: (context, versionProvider, child) {
                                if (versionProvider.isCheckingForUpdates) {
                                  return const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  );
                                } else {
                                  return Container(
                                    width: 24,
                                    height: 24,
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  );
                                }
                              },
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Mensaje de estado
                            Text(
                              _statusMessage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Información de versión en la parte inferior
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Consumer<VersionProvider>(
              builder: (context, versionProvider, child) {
                return FadeTransition(
                  opacity: _opacityAnimation,
                  child: Column(
                    children: [
                      Text(
                        'Versión ${versionProvider.currentAppVersion}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (versionProvider.hasError) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Error: ${versionProvider.errorMessage}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}