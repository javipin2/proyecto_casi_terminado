import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ciudad_provider.dart';
import '../models/ciudad.dart';
import '../services/ciudad_preference_service.dart';
import '../services/push_notification_service.dart';
import 'lugar_screen.dart';
import 'programador/programador_login_screen.dart';

class CiudadScreen extends StatefulWidget {
  const CiudadScreen({super.key});

  @override
  State<CiudadScreen> createState() => _CiudadScreenState();
}

class _CiudadScreenState extends State<CiudadScreen> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isSelectingCiudad = false;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
    
    // Cargar ciudades después del build para evitar "setState during build"
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CiudadProvider>(context, listen: false).fetchCiudades();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Obtener la ciudad guardada en preferencias o la primera disponible
        try {
          final ciudadGuardada = await CiudadPreferenceService.getSelectedCiudad();
          if (ciudadGuardada != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => LugarScreen(ciudad: ciudadGuardada),
              ),
            );
          } else {
            // Si no hay ciudad guardada, usar la primera disponible
            final ciudadProvider = Provider.of<CiudadProvider>(context, listen: false);
            if (ciudadProvider.ciudades.isNotEmpty) {
              final primeraCiudad = ciudadProvider.ciudades.first;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => LugarScreen(ciudad: primeraCiudad),
                ),
              );
            }
          }
        } catch (e) {
          // En caso de error, usar la primera ciudad disponible
          final ciudadProvider = Provider.of<CiudadProvider>(context, listen: false);
          if (ciudadProvider.ciudades.isNotEmpty) {
            final primeraCiudad = ciudadProvider.ciudades.first;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => LugarScreen(ciudad: primeraCiudad),
              ),
            );
          }
        }
        return false;
      },
      child: Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Seleccionar Ciudad',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
        backgroundColor: const Color(0xFF2E7D60),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProgramadorLoginScreen(),
                ),
              );
            },
            tooltip: 'Acceso Programador',
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2E7D60), Color(0xFF43A077)],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Consumer<CiudadProvider>(
            builder: (context, ciudadProvider, child) {
              if (ciudadProvider.isLoading) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D60)),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Cargando ciudades...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (ciudadProvider.errorMessage != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        ciudadProvider.errorMessage!,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => ciudadProvider.fetchCiudades(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D60),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                );
              }

              if (ciudadProvider.ciudades.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_city,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No hay ciudades disponibles',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => ciudadProvider.fetchCiudades(),
                color: const Color(0xFF2E7D60),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: ciudadProvider.ciudades.length,
                  itemBuilder: (context, index) {
                    final ciudad = ciudadProvider.ciudades[index];
                    return _buildCiudadCard(ciudad, index);
                  },
                ),
              );
            },
          ),
        ),
        ),
          if (_isSelectingCiudad)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: const Center(
                  child: Card(
                    margin: EdgeInsets.symmetric(horizontal: 48),
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D60)),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Cargando ciudad...',
                            style: TextStyle(fontSize: 16, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  Widget _buildCiudadCard(Ciudad ciudad, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 100)),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 6,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              onTap: _isSelectingCiudad
                  ? null
                  : () async {
                      setState(() => _isSelectingCiudad = true);
                      final c = ciudad;
                      try {
                        await CiudadPreferenceService.saveSelectedCiudad(c);
                        await PushNotificationService().updateCiudadForNotifications(c.id);
                      } catch (_) {}
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LugarScreen(ciudad: c),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _isSelectingCiudad = false);
                      });
                    },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Colors.green[50]!],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2E7D60), Color(0xFF4CAF50)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2E7D60).withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          ciudad.codigo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ciudad.nombre,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2E7D60),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.location_city, size: 16, color: Colors.grey[600]),
                              const SizedBox(width: 6),
                              Text(
                                'Código: ${ciudad.codigo}',
                                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D60).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios,
                        color: Color(0xFF2E7D60),
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
