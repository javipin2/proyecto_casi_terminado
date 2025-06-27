import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../providers/sede_provider.dart';
import '../providers/cancha_provider.dart';
import 'cancha_card.dart';
import 'horarios_screen.dart';
import 'sede_screen.dart';

class CanchasScreen extends StatefulWidget {
  const CanchasScreen({super.key});

  @override
  State<CanchasScreen> createState() => _CanchasScreenState();
}

class _CanchasScreenState extends State<CanchasScreen>
    with SingleTickerProviderStateMixin {
  late Future<void> _futureCanchas;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _futureCanchas = _loadCanchas();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadCanchas() async {
    try {
      final sedeProvider = Provider.of<SedeProvider>(context, listen: false);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final sedeProvider = Provider.of<SedeProvider>(context);
    final canchaProvider = Provider.of<CanchaProvider>(context);

    // Recargar canchas al regresar a la pantalla
    if (canchaProvider.canchas.isEmpty && !canchaProvider.isLoading) {
      _futureCanchas = _loadCanchas();
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF5F5F5), Colors.white],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.white,
          scrolledUnderElevation: 0,
          elevation: 0,
          title: FadeTransition(
            opacity: _fadeAnimation,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'logo',
                  child: Image.asset('assets/img1.png', height: 40, width: 40),
                ),
                const SizedBox(width: 12),
                const Text(
                  'La jugada',
                  style: TextStyle(
                    fontSize: 20,
                    fontFamily: "Pacifico",
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF424242),
                  ),
                ),
              ],
            ),
          ),
          centerTitle: true,
          leading: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF424242)),
              onPressed: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, animation, __) {
                      return FadeTransition(
                        opacity: animation,
                        child: const SedeScreen(),
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 300),
                  ),
                );
              },
              tooltip: 'Cambiar sede',
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Chip(
                label: Text(
                  'Sede: ${sedeProvider.selectedSede}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF424242)),
                ),
                backgroundColor: Colors.grey.shade100,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
        body: FutureBuilder<void>(
          future: _futureCanchas,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting ||
                canchaProvider.isLoading) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade300),
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

            if (canchaProvider.canchas.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sports_soccer_outlined,
                        size: 80, color: Colors.grey.shade400),
                    const SizedBox(height: 20),
                    Text(
                      "No hay canchas disponibles",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _futureCanchas = _loadCanchas();
                        });
                      },
                      child: Text(
                        "Reintentar",
                        style: TextStyle(color: Colors.green.shade700),
                      ),
                    ),
                  ],
                ),
              );
            }

            return AnimationLimiter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0, left: 4),
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: Text(
                          'Canchas disponibles',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          setState(() {
                            _futureCanchas = _loadCanchas();
                          });
                        },
                        color: Colors.green.shade400,
                        backgroundColor: Colors.white,
                        child: AnimationLimiter(
                          child: ListView.builder(
                            itemCount: canchaProvider.canchas.length,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (context, index) {
                              final cancha = canchaProvider.canchas[index];
                              return AnimationConfiguration.staggeredList(
                                position: index,
                                duration: const Duration(milliseconds: 375),
                                child: SlideAnimation(
                                  verticalOffset: 50.0,
                                  child: FadeInAnimation(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 16.0),
                                      child: CanchaCard(
                                        cancha: cancha,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            PageRouteBuilder(
                                              pageBuilder: (_, animation, __) {
                                                return FadeTransition(
                                                  opacity: animation,
                                                  child: HorariosScreen(cancha: cancha),
                                                );
                                              },
                                              transitionDuration: const Duration(milliseconds: 300),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}