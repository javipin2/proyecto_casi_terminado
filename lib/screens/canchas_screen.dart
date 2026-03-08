import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/sede_provider.dart';
import '../providers/cancha_provider.dart';
import '../models/ciudad.dart';
import '../models/lugar.dart';
import 'widgets/cancha_card.dart';
import 'horarios_screen.dart';
import 'sede_screen.dart';

// Colores del header (mismo diseño que sede/lugar)
const _headerBackground = Color(0xFF111624);
const _buttonBackground = Color(0xFF1A2033);
const _accentTeal = Color(0xFF2DD4BF);

class CanchasScreen extends StatefulWidget {
  final Ciudad ciudad;
  final Lugar lugar;
  
  const CanchasScreen({
    super.key,
    required this.ciudad,
    required this.lugar,
  });

  @override
  State<CanchasScreen> createState() => _CanchasScreenState();
}

class _CanchasScreenState extends State<CanchasScreen> {
  late Future<void> _futureCanchas;
  bool _hasInitiallyLoaded = false;

  @override
  void initState() {
    super.initState();
    _futureCanchas = Future.value();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _futureCanchas = _loadCanchas();
      });
    });
  }

  Future<void> _abrirUbicacionEnMapa(double latitud, double longitud) async {
    try {
      // Intentar primero con el esquema nativo de Google Maps (mejor para móvil)
      // Si no está disponible, usar la URL web
      final urls = [
        // Esquema nativo de Google Maps (abre la app si está instalada)
        Uri.parse('google.navigation:q=$latitud,$longitud'),
        // URL web de Google Maps (funciona en navegador y como fallback)
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitud,$longitud'),
      ];
      
      bool abierto = false;
      for (final url in urls) {
        if (await canLaunchUrl(url)) {
          try {
            await launchUrl(
              url,
              mode: LaunchMode.externalApplication,
            );
            abierto = true;
            break;
          } catch (e) {
            debugPrint('Error con URL $url: $e');
            // Continuar con la siguiente URL
            continue;
          }
        }
      }
      
      if (!abierto) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No se pudo abrir Google Maps'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error abriendo Google Maps: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error al abrir la ubicación'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
    }
  }

  void _mostrarMensajeUbicacionNoDefinida(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.location_off, color: Colors.grey.shade300, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'La ubicación de la sede no está definida',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.grey.shade200,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _loadCanchas() async {
    try {
      final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
      final canchaProvider = Provider.of<CanchaProvider>(context, listen: false);
      
      // Establecer el lugar en el CanchaProvider
      canchaProvider.setLugar(widget.lugar.id);
      
      await sedeProvider.fetchSedes();
      if (!mounted) return;

      String selectedSedeName = sedeProvider.selectedSede.isNotEmpty
          ? sedeProvider.selectedSede
          : sedeProvider.sedeNames.isNotEmpty
              ? sedeProvider.sedeNames.first
              : '';

      if (selectedSedeName.isNotEmpty) {
        String sedeId = sedeProvider.sedes.firstWhere(
          (sede) => sede['nombre'] == selectedSedeName,
          orElse: () => {'id': ''},
        )['id'] ?? '';
        if (sedeId.isNotEmpty) {
          sedeProvider.setSede(selectedSedeName);
          debugPrint('📌 Cargando canchas para la sedeId: $sedeId');
          await Provider.of<CanchaProvider>(context, listen: false).fetchCanchas(sedeId);
        } else {
          debugPrint('❌ No se encontró sedeId para $selectedSedeName');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Sede no encontrada'),
              backgroundColor: Colors.red.shade800,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
            ),
          );
        }
      } else {
        debugPrint('❌ No hay sedes disponibles');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No hay sedes disponibles'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error al cargar canchas: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar canchas: $e'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _hasInitiallyLoaded = true;
        });
      }
    }
  }

  void _reloadCanchas() {
    setState(() {
      _hasInitiallyLoaded = false;
      _futureCanchas = _loadCanchas();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sedeProvider = Provider.of<SedeProvider>(context);
    final canchaProvider = Provider.of<CanchaProvider>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 600;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SedeScreen(
              ciudad: widget.ciudad,
              lugar: widget.lugar,
            ),
          ),
        );
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        body: Stack(
          children: [
            Container(color: _headerBackground),
            Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(40),
                      topRight: Radius.circular(40),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 20,
                            offset: const Offset(0, -5),
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: _buildBody(context, sedeProvider, canchaProvider, isWeb, screenWidth),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final sedeProvider = Provider.of<SedeProvider>(context);
    final selectedSede = sedeProvider.selectedSede;
    final sede = sedeProvider.sedes.cast<Map<String, dynamic>?>().firstWhere(
          (s) => s != null && s['nombre'] == selectedSede,
          orElse: () => null,
        );
    final latitud = sede?['latitud'] as double?;
    final longitud = sede?['longitud'] as double?;
    final tieneUbicacion = latitud != null && longitud != null;

    return ClipPath(
      clipper: _CanchasHeaderCurveClipper(),
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          right: 16,
          bottom: 56,
        ),
        decoration: const BoxDecoration(color: _headerBackground),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SedeScreen(
                            ciudad: widget.ciudad,
                            lugar: widget.lugar,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: _buttonBackground,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.chevron_left, color: Colors.white, size: 24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.lugar.nombre,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: tieneUbicacion
                        ? () => _abrirUbicacionEnMapa(latitud, longitud)
                        : () => _mostrarMensajeUbicacionNoDefinida(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: _buttonBackground,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.location_on_rounded,
                        color: tieneUbicacion ? _accentTeal : Colors.white70,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.business_rounded, color: _accentTeal, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      selectedSede.isNotEmpty ? selectedSede.toUpperCase() : 'SEDE',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _accentTeal,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Canchas disponibles',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SedeProvider sedeProvider,
    CanchaProvider canchaProvider,
    bool isWeb,
    double screenWidth,
  ) {
    return FutureBuilder<void>(
      future: _futureCanchas,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || canchaProvider.isLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(_accentTeal),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Cargando canchas disponibles...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        if (canchaProvider.canchas.isEmpty && _hasInitiallyLoaded) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.sports_soccer_outlined, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 20),
                Text(
                  'No hay canchas disponibles',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _reloadCanchas,
                  child: const Text('Reintentar', style: TextStyle(color: _accentTeal)),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reloadCanchas(),
          color: _accentTeal,
          backgroundColor: Colors.white,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isWeb ? screenWidth * 0.05 : 20,
              16,
              isWeb ? screenWidth * 0.05 : 20,
              MediaQuery.of(context).padding.bottom + 24,
            ),
            physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2E7D60), Color(0xFF4CAF50)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2E7D60).withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.sports_soccer_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Canchas disponibles',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isWeb)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 450,
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 20,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: canchaProvider.canchas.length,
                    itemBuilder: (context, index) {
                      final cancha = canchaProvider.canchas[index];
                      return AnimationConfiguration.staggeredGrid(
                        position: index,
                        duration: const Duration(milliseconds: 375),
                        columnCount: (screenWidth / 450).floor(),
                        child: SlideAnimation(
                          verticalOffset: 50.0,
                          child: FadeInAnimation(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: CanchaCard(
                                cancha: cancha,
                                onTap: () => _openHorarios(context, cancha),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                else
                  ...List.generate(
                    canchaProvider.canchas.length,
                    (index) {
                      final cancha = canchaProvider.canchas[index];
                      return AnimationConfiguration.staggeredList(
                        position: index,
                        duration: const Duration(milliseconds: 375),
                        child: SlideAnimation(
                          verticalOffset: 50.0,
                          child: FadeInAnimation(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: CanchaCard(
                                cancha: cancha,
                                onTap: () => _openHorarios(context, cancha),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openHorarios(BuildContext context, dynamic cancha) async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: HorariosScreen(cancha: cancha),
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
    _reloadCanchas();
  }
}

/// Clipper para la curva tipo sonrisa en la parte inferior del header (igual que en sede/lugar).
class _CanchasHeaderCurveClipper extends CustomClipper<Path> {
  static const double curveDepth = 56.0;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final cornerY = h - curveDepth;
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(w, 0);
    path.lineTo(w, cornerY);
    path.quadraticBezierTo(w * 0.5, h, 0, cornerY);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}