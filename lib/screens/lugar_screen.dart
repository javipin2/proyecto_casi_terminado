import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:collection';
import '../providers/lugar_provider.dart';
import '../models/ciudad.dart';
import '../models/lugar.dart';
import '../models/cancha.dart';
import '../models/horario.dart';
import 'sede_screen.dart';
import 'ciudad_screen.dart';
import 'detalles_screen.dart';
import 'package:intl/intl.dart';

class LugarScreen extends StatefulWidget {
  final Ciudad ciudad;

  const LugarScreen({super.key, required this.ciudad});

  @override
  State<LugarScreen> createState() => _LugarScreenState();
}

class _LugarScreenState extends State<LugarScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _scrollAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _headerOpacityAnimation;
  late Animation<double> _headerScaleAnimation;
  
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  
  // Estado para favoritos
  Set<String> _favoriteLugares = {};
  int _currentPageIndex = 0; // 0 = Disponible, 1 = Favoritos
  late PageController _pageController;

  // Control de cambio de pestañas para evitar spam rápido (especialmente en web)
  DateTime _lastTabChange = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minTabChangeInterval = Duration(milliseconds: 600);

  // Promociones
  String _todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
  
  // ✅ NUEVO: Información de promoción activa
  Map<String, dynamic>? _promocionActiva; // {precio_promocional, promoId, cancha_id, horario}

  // Colores del header (mismo diseño que sede_screen)
  static const _headerBackground = Color(0xFF111624);
  static const _buttonBackground = Color(0xFF1A2033);
  static const _accentTeal = Color(0xFF2DD4BF);

  // Colores para tarjetas (mismo estilo que sedes)
  static const _cardOverlayBg = Color(0xE6181818);
  static const _textPrimary = Color(0xFF1F2937);
  static const _textSecondary = Color(0xFF6B7280);
  static const _tagBg = Color(0xFFF3F4F6);
  static const _ratingStar = Color(0xFFFBBF24);
  static const _primaryGreen = Color(0xFF2E7D60);

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentPageIndex);
    
    // Animación principal de entrada
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Animación para efectos de scroll
    _scrollAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    // Animaciones para el header dinámico
    _headerOpacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _scrollAnimationController,
      curve: Curves.easeInOut,
    ));

    _headerScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).animate(CurvedAnimation(
      parent: _scrollAnimationController,
      curve: Curves.easeInOut,
    ));

    _animationController.forward();
    
    // Cargar lugares al inicializar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lugarProvider = Provider.of<LugarProvider>(context, listen: false);
      lugarProvider.fetchLugaresPorCiudad(widget.ciudad.id);
      _loadFavorites();
    });
  }
  
  void _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final favoritesJson = prefs.getString('favorite_lugares_${widget.ciudad.id}');
    if (favoritesJson != null) {
      final List<dynamic> favoritesList = json.decode(favoritesJson);
      setState(() {
        _favoriteLugares = favoritesList.map((e) => e.toString()).toSet();
      });
    }
  }
  
  void _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = json.encode(_favoriteLugares.toList());
    await prefs.setString('favorite_lugares_${widget.ciudad.id}', favoritesJson);
  }
  
  void _toggleFavorite(String lugarId) {
    setState(() {
      if (_favoriteLugares.contains(lugarId)) {
        _favoriteLugares.remove(lugarId);
      } else {
        _favoriteLugares.add(lugarId);
      }
    });
    _saveFavorites();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollAnimationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Navegar a CiudadScreen al presionar atrás
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CiudadScreen()),
        );
        return false;
      },
      child: Scaffold(
      backgroundColor: Colors.grey[50],
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Consumer<LugarProvider>(
            builder: (context, lugarProvider, child) {
              if (lugarProvider.isLoading) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D60)),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Cargando lugares...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (lugarProvider.errorMessage != null) {
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
                        lugarProvider.errorMessage!,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => lugarProvider.fetchLugaresPorCiudad(widget.ciudad.id),
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

              if (lugarProvider.lugares.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No hay lugares disponibles',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return _buildCustomScrollView(lugarProvider.lugares);
            },
          ),
        ),
        ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, -2)),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentPageIndex,
          height: 68,
          indicatorColor: const Color(0xFF2E7D60).withOpacity(0.12),
          surfaceTintColor: Colors.white,
          overlayColor: WidgetStateProperty.resolveWith((_) => Colors.transparent),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.location_on_outlined),
              selectedIcon: Icon(Icons.location_on, color: Color(0xFF2E7D60)),
              label: 'Disponible',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite, color: Color(0xFF2E7D60)),
              label: 'Favoritos',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_offer_outlined),
              selectedIcon: Icon(Icons.local_offer, color: Color(0xFF2E7D60)),
              label: 'Promociones',
            ),
          ],
          onDestinationSelected: (index) {
            final now = DateTime.now();
            // Evitar cambios muy rápidos de pestaña (debounce)
            if (index == _currentPageIndex ||
                now.difference(_lastTabChange) < _minTabChangeInterval) {
              return;
            }
            _lastTabChange = now;

            setState(() {
              _currentPageIndex = index;
            });
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
        ),
      ),
      ),
    );
  }

  Widget _buildCustomScrollView(List<Lugar> lugares) {
  return Stack(
    children: [
      Container(color: _headerBackground),
      Column(
        children: [
          AnimatedBuilder(
            animation: _scrollAnimationController,
            builder: (context, child) {
              final progress = _scrollAnimationController.value;
              final headerHeight = 80.0 + (120.0 * (1.0 - progress));
              final opacity = 1.0 - progress;

              return Container(
                height: headerHeight.clamp(80.0, 200.0),
                decoration: const BoxDecoration(
                  color: _headerBackground,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Descubre',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _showSearchFilter,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(
                                  color: _buttonBackground,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.tune, color: Colors.white, size: 22),
                              ),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 48),
                              icon: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(
                                  color: _buttonBackground,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.more_vert, color: Colors.white, size: 22),
                              ),
                              tooltip: 'Opciones',
                              onSelected: (value) {
                                if (value == 'change_city') {
                                  _showChangeCityDialog();
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem<String>(
                                  value: 'change_city',
                                  child: Row(
                                    children: [
                                      Icon(Icons.location_city, color: _accentTeal),
                                      SizedBox(width: 8),
                                      Text('Cambiar Ciudad'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (progress < 0.95) ...[
                          const SizedBox(height: 12),
                          Flexible(
                            child: Opacity(
                              opacity: opacity.clamp(0.0, 1.0),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Lugares Deportivos',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Encuentra los mejores lugares en ${widget.ciudad.nombre}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white.withOpacity(0.85),
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Text(
                                          'Categorías',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildCategoryChip('Fútbol', Icons.sports_soccer, _accentTeal),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // Contenido blanco principal
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
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Indicador de filtros aplicados (solo en pestaña Disponible)
                  if (_selectedDate != null && _selectedTime != null && _currentPageIndex == 0)
                    _buildFilterIndicator(),
                  // Contenido principal con detección de scroll
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification notification) {
                        if (notification is ScrollUpdateNotification) {
                          // Calcular el progreso del scroll (0.0 a 1.0)
                          final scrollProgress = (notification.metrics.pixels / 200).clamp(0.0, 1.0);
                          _scrollAnimationController.value = scrollProgress;
                        }
                        return false;
                      },
                      child: _buildPageView(lugares),
                    ),
                  ),
                ],
              ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}


  Widget _buildCategoryChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
              borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }


  // Reemplazado por BottomNavigationBar

  Widget _buildPageView(List<Lugar> lugares) {
    return PageView(
      controller: _pageController,
      physics: const ClampingScrollPhysics(),
      onPageChanged: (index) {
        if (!mounted) return;
        _lastTabChange = DateTime.now();
        setState(() {
          _currentPageIndex = index;
        });
      },
      children: [
        _buildAvailableContent(lugares),
        _buildFavoritesContent(lugares),
        _buildPromotionsContent(lugares),
      ],
    );
  }

  Widget _buildAvailableContent(List<Lugar> lugares) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header para lista vertical
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
                  child: const Icon(
                    Icons.location_city,
                          color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Todos los Lugares',
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
          // Lista vertical de todos los lugares
          ...lugares.map((lugar) => _buildEnhancedFavoriteCard(lugar)),
        ],
      ),
    );
  }

  Widget _buildFavoritesContent(List<Lugar> lugares) {
    final favoriteLugares = lugares.where((lugar) => _favoriteLugares.contains(lugar.id)).toList();
    
    if (favoriteLugares.isEmpty) {
      return Center(
                      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
                        children: [
            Icon(
              Icons.favorite_border,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
                          Text(
              'No tienes lugares favoritos',
                            style: TextStyle(
                fontSize: 18,
                              color: Colors.grey[600],
                fontWeight: FontWeight.w500,
                            ),
                          ),
            const SizedBox(height: 8),
                          Text(
              'Toca el corazón en cualquier lugar para agregarlo a favoritos',
                            style: TextStyle(
                fontSize: 14,
                              color: Colors.grey[500],
                            ),
              textAlign: TextAlign.center,
                          ),
                        ],
                      ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de favoritos
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
                  child: const Icon(
                    Icons.favorite,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Mis Favoritos',
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
          ...favoriteLugares.map((lugar) => _buildEnhancedFavoriteCard(lugar)),
        ],
      ),
    );
  }


  Widget _buildPromotionsContent(List<Lugar> lugares) {
    // Solo construir los streams cuando la pestaña de Promociones está activa (index 2)
    // Esto evita crear/destruir listeners de Firestore al cambiar de tab
    if (_currentPageIndex != 2) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14, left: 2),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD4A843).withOpacity(0.5), width: 1),
                  ),
                  child: const Icon(
                    Icons.local_offer_rounded,
                    color: Color(0xFFD4A843),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Promociones',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          ...lugares.map((lugar) => _buildLugarPromotions(lugar)).toList(),
          // Mensaje cuando no hay promociones visibles
          Builder(builder: (context) {
            // Verificar si algún lugar tiene promos visibles (los widgets no-vacíos)
            // Usamos un StreamBuilder ligero solo para saber si hay datos
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('promociones')
                  .where('activo', isEqualTo: true)
                  .where('fecha', isGreaterThanOrEqualTo: _todayStr)
                  .limit(1)
                  .snapshots(),
              builder: (context, snap) {
                final hayPromos = snap.hasData && snap.data!.docs.isNotEmpty;
                if (hayPromos) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.local_offer_outlined, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          'Sin promociones por el momento',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Las ofertas aparecerán aquí cuando estén disponibles',
                          style: TextStyle(fontSize: 12, color: Colors.grey[350]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLugarPromotions(Lugar lugar) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('promociones')
          .where('lugarId', isEqualTo: lugar.id)
          .where('activo', isEqualTo: true)
          .where('fecha', isGreaterThanOrEqualTo: _todayStr)
          .orderBy('fecha')
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: const LinearProgressIndicator(
              minHeight: 2,
              color: Color(0xFF2E7D60),
              backgroundColor: Colors.transparent,
            ),
          );
        }

        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        // Un solo stream de reservas por lugar (evita muchos listeners y el error del SDK en web)
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('reservas')
              .where('lugarId', isEqualTo: lugar.id)
              .where('fecha', isGreaterThanOrEqualTo: _todayStr)
              .limit(100)
              .snapshots(),
          builder: (context, resSnap) {
            if (resSnap.hasError) {
              return _buildPromocionesBlock(lugar, docs, []);
            }
            final reservasDocs = resSnap.data?.docs ?? [];

            return _buildPromocionesBlock(lugar, docs, reservasDocs);
          },
        );
      },
    );
  }

  /// Construye el bloque de promos de un lugar, agrupadas por fecha.
  Widget _buildPromocionesBlock(
    Lugar lugar,
    List<QueryDocumentSnapshot<Object?>> promoDocs,
    List<QueryDocumentSnapshot<Object?>> reservasDocs,
  ) {
    // Filtrar promos válidas (sin reserva, no vencidas) y agrupar por fecha
    final List<_PromoVisible> visibles = [];
    final now = DateTime.now();
    final hoyStr = DateFormat('yyyy-MM-dd').format(now);

    for (final d in promoDocs) {
      final data = (d.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
      final promoId = d.id;
      final fecha = (data['fecha'] as String? ?? '').trim();
      final canchaId = (data['cancha_id'] as String? ?? '').trim();
      final horarioPromo = (data['horario'] as String? ?? '').trim();

      if (fecha.isEmpty || canchaId.isEmpty) continue;

      // Filtrar promociones vencidas: si es hoy y la hora ya pasó, no mostrar
      if (fecha == hoyStr && horarioPromo.isNotEmpty) {
        final hora24 = _convertirHora12A24(horarioPromo);
        if (now.hour >= hora24) continue;
      }
      // Fechas anteriores a hoy ya están filtradas por la query (fecha >= _todayStr)

      final horarioPromoNormalizado = Horario.normalizarHora(horarioPromo);
      bool ocultar = false;

      for (final r in reservasDocs) {
        final rd = (r.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
        if ((rd['fecha'] as String? ?? '').trim() != fecha) continue;
        if ((rd['cancha_id'] as String? ?? '').trim() != canchaId) continue;
        final hRes = Horario.normalizarHora((rd['horario'] as String? ?? '').trim());
        if (hRes == horarioPromoNormalizado) {
          ocultar = true;
          break;
        }
      }

      if (!ocultar) {
        visibles.add(_PromoVisible(fecha: fecha, data: data, promoId: promoId));
      }
    }

    // ✅ Deduplicar: solo una promoción por (fecha, cancha, horario). Si hay varias, mostrar la de mejor precio (menor precio_promocional).
    final Map<String, _PromoVisible> unicasPorSlot = {};
    for (final p in visibles) {
      final fechaP = (p.data['fecha'] as String? ?? '').trim();
      final canchaIdP = (p.data['cancha_id'] as String? ?? '').trim();
      final horarioNorm = Horario.normalizarHora((p.data['horario'] as String? ?? '').trim());
      final key = '$fechaP|$canchaIdP|$horarioNorm';
      final precioPromo = (p.data['precio_promocional'] as num?)?.toDouble();
      final existente = unicasPorSlot[key];
      if (existente == null) {
        unicasPorSlot[key] = p;
      } else {
        final precioExistente = (existente.data['precio_promocional'] as num?)?.toDouble();
        if (precioPromo != null && (precioExistente == null || precioPromo < precioExistente)) {
          unicasPorSlot[key] = p;
        }
      }
    }
    final visiblesUnicas = unicasPorSlot.values.toList();

    if (visiblesUnicas.isEmpty) return const SizedBox.shrink();

    // Agrupar por fecha preservando orden
    final LinkedHashMap<String, List<_PromoVisible>> porFecha = LinkedHashMap();
    for (final p in visiblesUnicas) {
      porFecha.putIfAbsent(p.fecha, () => []).add(p);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nombre del lugar minimalista
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, color: Colors.grey[500], size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    lugar.nombre,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.grey[600],
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${visiblesUnicas.length} oferta${visiblesUnicas.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400], fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          // Promos agrupadas por fecha
          ...porFecha.entries.map((entry) {
            final fechaStr = entry.key;
            final promos = entry.value;
            String label = '';
            try {
              final dt = DateTime.parse(fechaStr);
              final now = DateTime.now();
              final hoy = DateTime(now.year, now.month, now.day);
              final diff = dt.difference(hoy).inDays;
              if (diff == 0) {
                label = 'Hoy';
              } else if (diff == 1) {
                label = 'Mañana';
              } else {
                label = DateFormat('EEEE d MMM', 'es').format(dt);
                label = label[0].toUpperCase() + label.substring(1);
              }
            } catch (_) {
              label = fechaStr;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Encabezado de fecha
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 6, left: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4A843),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[700],
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(height: 0.5, color: Colors.grey[300]),
                      ),
                    ],
                  ),
                ),
                ...promos.map((p) => _buildPromoCard(lugar, p.data, p.promoId)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPromoCard(Lugar lugar, Map<String, dynamic> data, String promoId) {
    final fechaStr = (data['fecha'] as String? ?? '').trim();
    final horario = (data['horario'] as String? ?? '').trim();
    final precioPromo = (data['precio_promocional'] as num?)?.toDouble();
    final precioOriginal = (data['precio_original'] as num?)?.toDouble();
    final canchaNombre = (data['cancha_nombre'] as String? ?? '').trim();
    final nota = (data['nota'] as String? ?? '').trim();
    DateTime? fecha;
    String fechaBonita = '';
    try {
      fecha = DateTime.parse(fechaStr);
      fechaBonita = DateFormat('EEE d MMM', 'es').format(fecha).toUpperCase();
    } catch (_) {}

    double? descuentoPct;
    if (precioOriginal != null && precioPromo != null && precioOriginal > 0 && precioPromo < precioOriginal) {
      descuentoPct = (1 - (precioPromo / precioOriginal)) * 100;
    }

    return _PremiumPromoCard(
      lugar: lugar,
      fechaBonita: fechaBonita,
      horario: horario,
      canchaNombre: canchaNombre,
      nota: nota,
      precioPromo: precioPromo,
      precioOriginal: precioOriginal,
      descuentoPct: descuentoPct,
      onReservar: () => _onSelectPromotion(lugar, data, promoId),
    );
  }

  void _onSelectPromotion(Lugar lugar, Map<String, dynamic> promo, String promoId) async {
    try {
      final fechaStr = (promo['fecha'] as String? ?? '').trim();
      final horarioStr = (promo['horario'] as String? ?? '').trim();
      final precioPromocional = (promo['precio_promocional'] as num?)?.toDouble();
      final canchaId = (promo['cancha_id'] as String? ?? '').trim();
      
      if (fechaStr.isEmpty || horarioStr.isEmpty || precioPromocional == null || canchaId.isEmpty) {
        debugPrint('❌ Datos de promoción incompletos');
        return;
      }
      
      final fecha = DateTime.parse(fechaStr);
      final hora24 = _convertirHora12A24(horarioStr);
      
      // ✅ GUARDAR INFORMACIÓN DE LA PROMOCIÓN
      setState(() {
        _selectedDate = fecha;
        _selectedTime = TimeOfDay(hour: hora24, minute: 0);
        _promocionActiva = {
          'precio_promocional': precioPromocional,
          'promoId': promoId,
          'cancha_id': canchaId,
          'horario': horarioStr,
          'fecha': fechaStr,
        };
      });
      
      debugPrint('🎯 Promoción seleccionada:');
      debugPrint('   - Precio: COP ${precioPromocional.toStringAsFixed(0)}');
      debugPrint('   - Cancha ID: $canchaId');
      debugPrint('   - Horario: $horarioStr');
      
      _navegarAReserva(lugar);
    } catch (e) {
      debugPrint('❌ Error seleccionando promoción: $e');
    }
  }
  Widget _buildEnhancedFavoriteCard(Lugar lugar) {
    final isFavorite = _favoriteLugares.contains(lugar.id);
    const imageHeight = 180.0;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 500),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 24 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SedeScreen(
                          ciudad: widget.ciudad,
                          lugar: lugar,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  splashColor: Colors.black.withOpacity(0.06),
                  highlightColor: Colors.black.withOpacity(0.04),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              height: imageHeight,
                              width: double.infinity,
                              child: (lugar.fotoUrl != null && lugar.fotoUrl!.isNotEmpty)
                                  ? Image.network(
                                      lugar.fotoUrl!,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Container(
                                          color: Colors.grey[200],
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              value: loadingProgress.expectedTotalBytes != null
                                                  ? loadingProgress.cumulativeBytesLoaded /
                                                      loadingProgress.expectedTotalBytes!
                                                  : null,
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
                                            ),
                                          ),
                                        );
                                      },
                                      errorBuilder: (context, error, stackTrace) =>
                                          _buildPlaceholderImage(),
                                    )
                                  : _buildPlaceholderImage(),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _cardOverlayBg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.star_rounded, color: _ratingStar, size: 16),
                                        SizedBox(width: 4),
                                        Text(
                                          '5.0',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _toggleFavorite(lugar.id),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _cardOverlayBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isFavorite
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        size: 20,
                                        color: isFavorite ? const Color(0xFFE53E3E) : Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              bottom: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _cardOverlayBg,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_rounded,
                                        color: _accentTeal, size: 16),
                                    const SizedBox(width: 4),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 140),
                                      child: Text(
                                        lugar.direccion,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lugar.nombre,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                lugar.direccion,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: _textSecondary,
                                  height: 1.35,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _tagBg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'LUGAR',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _textSecondary,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _tagBg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'FÚTBOL',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _textSecondary,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: Colors.grey[400],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2E7D60).withOpacity(0.8),
            const Color(0xFF43A077).withOpacity(0.8),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.sports_soccer_rounded,
                size: 40,
                color: const Color(0xFF2E7D60),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Imagen no disponible',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterIndicator() {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 500),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.8 + (0.2 * value),
          child: Opacity(
            opacity: value,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_selectedDate != null && _selectedTime != null) {
                  _showAvailabilityResults();
                }
              },
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF2E7D60).withOpacity(0.08),
                    const Color(0xFF4CAF50).withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF2E7D60).withOpacity(0.25),
                  width: 1.5,
                ),
              ),
      child: Row(
        children: [
          Icon(
              Icons.filter_alt,
            color: const Color(0xFF2E7D60),
              size: 20,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Filtros aplicados',
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF2E7D60).withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('EEE d MMM', 'es').format(_selectedDate!)} · ${_formatHora12h(_selectedTime!.hour)}',
                  style: const TextStyle(
                    color: Color(0xFF2E7D60),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              setState(() {
                _selectedDate = null;
                _selectedTime = null;
              });
              Provider.of<LugarProvider>(context, listen: false)
                  .fetchLugaresPorCiudad(widget.ciudad.id);
            },
            icon: const Icon(Icons.close, color: Color(0xFF2E7D60)),
            iconSize: 20,
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

  void _showSearchFilter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSearchFilterModal(),
    );
  }

  Widget _buildSearchFilterModal() {
    return StatefulBuilder(
      builder: (context, setModalState) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D60).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.tune,
                        color: Color(0xFF2E7D60),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Filtrar por fecha y hora',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D60),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Verás disponibilidad y precios por lugar',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      color: Colors.grey[600],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Fecha
                Text(
                  'Seleccionar Fecha',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    await _selectDate();
                    if (mounted) setModalState(() {});
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: _selectedDate != null ? const Color(0xFF2E7D60) : Colors.grey[600],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _selectedDate != null
                              ? DateFormat('EEEE d MMM yyyy', 'es').format(_selectedDate!)
                              : 'Toca para elegir fecha',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: _selectedDate != null ? FontWeight.w600 : FontWeight.normal,
                            color: _selectedDate != null ? Colors.black87 : Colors.grey[600],
                          ),
                        ),
                        const Spacer(),
                        if (_selectedDate != null)
                          Icon(Icons.check_circle, color: const Color(0xFF2E7D60), size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Hora
                Text(
                  'Seleccionar Hora',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    await _selectTime();
                    if (mounted) setModalState(() {});
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          color: _selectedTime != null ? const Color(0xFF2E7D60) : Colors.grey[600],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _selectedTime != null
                              ? _formatHora12h(_selectedTime!.hour)
                              : 'Toca para elegir hora',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: _selectedTime != null ? FontWeight.w600 : FontWeight.normal,
                            color: _selectedTime != null ? Colors.black87 : Colors.grey[600],
                          ),
                        ),
                        const Spacer(),
                        if (_selectedTime != null)
                          Icon(Icons.check_circle, color: const Color(0xFF2E7D60), size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Botones de acción
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedDate = null;
                          _selectedTime = null;
                        });
                        Navigator.pop(context);
                        Provider.of<LugarProvider>(context, listen: false)
                            .fetchLugaresPorCiudad(widget.ciudad.id);
                      },
                      child: const Text(
                        'Limpiar Filtros',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        if (_selectedDate != null && _selectedTime != null) {
                          if (mounted) {
                            _showAvailabilityResults();
                          }
                        } else {
                          Provider.of<LugarProvider>(context, listen: false)
                              .fetchLugaresPorCiudad(widget.ciudad.id);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D60),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Aplicar y ver resultados'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2E7D60),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final hora24 = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D60).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.access_time, color: Color(0xFF2E7D60), size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Seleccionar hora',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D60),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: Colors.grey[600],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Elige la hora para ver disponibilidad y precios',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(24, (index) {
                    final h12 = _convertirHora24A12(index);
                    final label = '${h12['hora']}:00 ${h12['periodo']}';
                    return ActionChip(
                      label: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: _selectedTime?.hour == index
                          ? const Color(0xFF2E7D60).withOpacity(0.15)
                          : Colors.grey[100],
                      side: BorderSide(
                        color: _selectedTime?.hour == index
                            ? const Color(0xFF2E7D60)
                            : Colors.grey[300]!,
                        width: _selectedTime?.hour == index ? 2 : 1,
                      ),
                      onPressed: () => Navigator.pop(context, index),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (hora24 != null && mounted) {
      setState(() {
        _selectedTime = TimeOfDay(hour: hora24, minute: 0);
      });
    }
  }


  void _showChangeCityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_city, color: Color(0xFF2E7D60)),
            SizedBox(width: 8),
            Text('Cambiar Ciudad'),
          ],
        ),
        content: const Text(
          '¿Deseas cambiar la ciudad actual? Se te llevará a la pantalla de selección de ciudades.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
                        onPressed: () {
              Navigator.pop(context); // Cerrar diálogo
              Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                  builder: (context) => const CiudadScreen(),
                            ),
                          );
                        },
                              style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D60),
                                foregroundColor: Colors.white,
            ),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  // Funciones de filtros y disponibilidad
  Future<Map<String, dynamic>> _getCanchaAvailability(Lugar lugar) async {
    try {
      if (_selectedDate == null || _selectedTime == null) {
        return {
          'total': 0,
          'disponibles': 0,
          'apartadas': 0,
          'procesando': 0,
        };
      }
      
      final fechaStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final horaStr = '${_selectedTime!.hour.toString().padLeft(2, '0')}:00';
      
      // Buscar canchas directamente por lugarId
      final canchasSnapshot = await FirebaseFirestore.instance
          .collection('canchas')
          .where('lugarId', isEqualTo: lugar.id)
          .get();
      
      if (canchasSnapshot.docs.isEmpty) {
        return {
          'total': 0,
          'disponibles': 0,
          'apartadas': 0,
          'procesando': 0,
        };
      }
      
      final canchas = canchasSnapshot.docs.map((doc) => Cancha.fromFirestore(doc)).toList();
      return await _procesarCanchas(canchas, fechaStr, horaStr, lugar.id);
      
    } catch (e) {
      return {
        'total': 0,
        'disponibles': 0,
        'apartadas': 0,
        'procesando': 0,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> _procesarCanchas(List<Cancha> canchas, String fechaStr, String horaStr, String lugarId) async {
    print('🔍 DEBUG: Procesando ${canchas.length} canchas para $fechaStr a las $horaStr');
    
    int totalCanchas = 0;
    int canchasDisponibles = 0;
    int canchasApartadas = 0;
    int canchasProcesando = 0;
    final List<double> preciosDisponibles = [];
    bool tieneAlMenosUnaPromo = false;

    // Cargar promociones activas para este lugar y fecha (precio promocional por cancha+horario)
    final Map<String, double> precioPromoPorCanchaHorario = {};
    if (lugarId.isNotEmpty && fechaStr.compareTo(_todayStr) >= 0) {
      try {
        final promosSnapshot = await FirebaseFirestore.instance
            .collection('promociones')
            .where('lugarId', isEqualTo: lugarId)
            .where('fecha', isEqualTo: fechaStr)
            .where('activo', isEqualTo: true)
            .get();
        for (var doc in promosSnapshot.docs) {
          final d = doc.data();
          final canchaId = (d['cancha_id'] as String? ?? '').trim();
          final horario = (d['horario'] as String? ?? '').trim();
          final precioPromo = (d['precio_promocional'] as num?)?.toDouble();
          if (canchaId.isNotEmpty && horario.isNotEmpty && precioPromo != null && precioPromo > 0) {
            final key = '${canchaId}_${Horario.normalizarHora(horario)}';
            precioPromoPorCanchaHorario[key] = precioPromo;
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error cargando promociones para filtro: $e');
      }
    }

    for (var cancha in canchas) {
      print('🏟️ DEBUG: Procesando cancha: ${cancha.nombre}');
      
      final day = DateFormat('EEEE', 'es').format(_selectedDate!).toLowerCase();
      final preciosPorDia = cancha.preciosPorHorario[day] ?? {};
      
      final hora24 = _selectedTime!.hour;
      final hora12 = _convertirHora24A12(hora24);
      final horaStr12 = '${hora12['hora']}:00 ${hora12['periodo']}';
      
      print('   📅 Día: $day, Hora 24h: $hora24, Hora 12h: $horaStr12');
      print('   📋 Horarios disponibles: ${preciosPorDia.keys.toList()}');
      
      final horaConfig = preciosPorDia[horaStr12];
      print('   ⚙️ Configuración para $horaStr12: $horaConfig');
      
      if (horaConfig == null || horaConfig['habilitada'] != true) {
        print('   ❌ Cancha no disponible en este horario');
        continue;
      }

      totalCanchas++;
      print('   ✅ Cancha disponible en horario, verificando reservas...');

      // Verificar reservas existentes para esta cancha, fecha y hora
      final reservasSnapshot = await FirebaseFirestore.instance
          .collection('reservas')
          .where('fecha', isEqualTo: fechaStr)
          .where('cancha_id', isEqualTo: cancha.id)
          .get();

      print('   📋 Reservas encontradas: ${reservasSnapshot.docs.length}');

      bool tieneReservaConfirmada = false;
      bool tieneReservaPendiente = false;

      // Verificar reservas
      for (var reservaDoc in reservasSnapshot.docs) {
        final reservaData = reservaDoc.data();
        final horarioReserva = reservaData['horario'] as String? ?? '';
        final confirmada = reservaData['confirmada'] as bool? ?? false;
        
        print('     Reserva: horario=$horarioReserva, confirmada=$confirmada');
        
        // Convertir la hora de la reserva a formato 24h para comparar
        final horaReserva24h = _convertirHora12A24(horarioReserva);
        final horaSeleccionada24h = _selectedTime!.hour;
        
        print('     Hora reserva (24h): $horaReserva24h, Hora seleccionada (24h): $horaSeleccionada24h');
        
        // Verificar si el horario coincide
        if (horaReserva24h == horaSeleccionada24h) {
          if (confirmada) {
            tieneReservaConfirmada = true;
            print('     ✅ Reserva confirmada encontrada');
          } else {
            tieneReservaPendiente = true;
            print('     ⏳ Reserva pendiente encontrada');
          }
        }
      }

      // Determinar estado final
      if (tieneReservaConfirmada) {
        canchasApartadas++;
        print('   🔴 Cancha apartada (reserva confirmada)');
      } else if (tieneReservaPendiente) {
        canchasProcesando++;
        print('   🟠 Cancha procesando pago');
      } else {
        canchasDisponibles++;
        final promoKey = '${cancha.id}_${Horario.normalizarHora(horaStr12)}';
        final precioPromo = precioPromoPorCanchaHorario[promoKey];
        if (precioPromo != null) tieneAlMenosUnaPromo = true;
        final precio = precioPromo ??
            ((horaConfig['precio'] is num)
                ? (horaConfig['precio'] as num).toDouble()
                : cancha.precio);
        preciosDisponibles.add(precio);
        print('   🟢 Cancha disponible');
      }
    }

    print('📊 DEBUG: Resultados finales - Total: $totalCanchas, Disponibles: $canchasDisponibles, Apartadas: $canchasApartadas, Procesando: $canchasProcesando');

    double? precioDesde;
    if (preciosDisponibles.isNotEmpty) {
      preciosDisponibles.sort();
      precioDesde = preciosDisponibles.first;
    }

    final tienePromo = tieneAlMenosUnaPromo;

    return {
      'total': totalCanchas,
      'disponibles': canchasDisponibles,
      'apartadas': canchasApartadas,
      'procesando': canchasProcesando,
      'precioDesde': precioDesde,
      'precios': preciosDisponibles,
      'tienePromo': tienePromo,
    };
  }

  String _normalizarHora(String hora) {
    try {
      // Limpiar espacios y caracteres extra
      String horaLimpia = hora.trim();
      
      if (horaLimpia.contains(':')) {
        final parts = horaLimpia.split(':');
        if (parts.length >= 2) {
          final hour = int.parse(parts[0]);
          final minute = int.parse(parts[1]);
          return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        }
      }
      
      // Si es solo un número, asumir que son horas
      if (RegExp(r'^\d+$').hasMatch(horaLimpia)) {
        final hour = int.parse(horaLimpia);
        return '${hour.toString().padLeft(2, '0')}:00';
      }
      
      return horaLimpia;
    } catch (e) {
      return hora;
    }
  }

  Map<String, String> _convertirHora24A12(int hora24) {
    if (hora24 == 0) {
      return {'hora': '12', 'periodo': 'AM'};
    } else if (hora24 < 12) {
      return {'hora': hora24.toString(), 'periodo': 'AM'};
    } else if (hora24 == 12) {
      return {'hora': '12', 'periodo': 'PM'};
    } else {
      return {'hora': (hora24 - 12).toString(), 'periodo': 'PM'};
    }
  }

  String _formatHora12h(int hora24) {
    final h = _convertirHora24A12(hora24);
    return '${h['hora']}:00 ${h['periodo']}';
  }

  int _convertirDiaSemana(String dia) {
    switch (dia.toLowerCase()) {
      case 'lunes':
      case 'monday':
        return 1;
      case 'martes':
      case 'tuesday':
        return 2;
      case 'miércoles':
      case 'wednesday':
        return 3;
      case 'jueves':
      case 'thursday':
        return 4;
      case 'viernes':
      case 'friday':
        return 5;
      case 'sábado':
      case 'saturday':
        return 6;
      case 'domingo':
      case 'sunday':
        return 7;
      default:
        return 0;
    }
  }

  int _convertirHora12A24(String hora12) {
    try {
      // Limpiar la hora
      String horaLimpia = hora12.trim().toUpperCase();
      
      // Si ya está en formato 24h, devolver directamente
      if (!horaLimpia.contains('AM') && !horaLimpia.contains('PM')) {
        if (horaLimpia.contains(':')) {
          return int.parse(horaLimpia.split(':')[0]);
        }
        return int.parse(horaLimpia);
      }
      
      // Extraer hora, minuto y período
      final parts = horaLimpia.split(' ');
      final timePart = parts[0];
      final period = parts.length > 1 ? parts[1] : '';
      
      final timeParts = timePart.split(':');
      int hour = int.parse(timeParts[0]);
      
      // Convertir a formato 24h
      if (period == 'AM') {
        if (hour == 12) hour = 0;
      } else if (period == 'PM') {
        if (hour != 12) hour += 12;
      }
      
      return hour;
    } catch (e) {
      print('Error convirtiendo hora 12h a 24h: $hora12 - $e');
      return 0;
    }
  }

  Future<void> _navegarAReserva(Lugar lugar) async {
    try {
      if (_selectedDate == null || _selectedTime == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor selecciona fecha y hora primero'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      final canchasSnapshot = await FirebaseFirestore.instance
          .collection('canchas')
          .where('lugarId', isEqualTo: lugar.id)
          .get();
      
      if (!mounted) return;

      if (canchasSnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay canchas disponibles para este lugar'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final canchas = canchasSnapshot.docs.map((doc) => Cancha.fromFirestore(doc)).toList();
      
      // ✅ Si la reserva viene de una promoción, la promoción ya tiene cancha asignada: ir directo a esa cancha sin preguntar
      if (_promocionActiva != null) {
        final canchaIdPromo = (_promocionActiva!['cancha_id'] as String? ?? '').trim();
        if (canchaIdPromo.isNotEmpty) {
          final canchaPromo = canchas.where((c) => c.id == canchaIdPromo).firstOrNull;
          if (canchaPromo != null) {
            if (!mounted) return;
            _irADetalles(canchaPromo, lugar);
            return;
          }
        }
      }
      
      // Verificar disponibilidad para cada cancha
      final canchasDisponibles = <Cancha>[];
      final fechaStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final hora24 = _selectedTime!.hour;
      final hora12 = _convertirHora24A12(hora24);
      final horaStr = '${hora12['hora']}:00 ${hora12['periodo']}';
      final day = DateFormat('EEEE', 'es').format(_selectedDate!).toLowerCase();
      
      for (var cancha in canchas) {
        final preciosPorDia = cancha.preciosPorHorario[day] ?? {};
        final horaConfig = preciosPorDia[horaStr];
        
        if (horaConfig != null && horaConfig['habilitada'] == true) {
          // Verificar si no hay reservas confirmadas
          final reservasSnapshot = await FirebaseFirestore.instance
              .collection('reservas')
              .where('fecha', isEqualTo: fechaStr)
              .where('cancha_id', isEqualTo: cancha.id)
              .get();
          
          bool tieneReservaConfirmada = false;
          for (var reservaDoc in reservasSnapshot.docs) {
            final reservaData = reservaDoc.data();
            final horarioReserva = reservaData['horario'] as String? ?? '';
            final confirmada = reservaData['confirmada'] as bool? ?? false;
            
            if (_normalizarHora(horarioReserva) == _normalizarHora('${hora24.toString().padLeft(2, '0')}:00') && confirmada) {
              tieneReservaConfirmada = true;
              break;
            }
          }
          
          if (!tieneReservaConfirmada) {
            canchasDisponibles.add(cancha);
          }
        }
      }
      
      if (!mounted) return;

      if (canchasDisponibles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay canchas disponibles para la fecha y hora seleccionada'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      if (canchasDisponibles.length > 1) {
        _mostrarSelectorCanchas(lugar, canchasDisponibles);
      } else {
        _irADetalles(canchasDisponibles.first, lugar);
      }
      
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _mostrarSelectorCanchas(Lugar lugar, List<Cancha> canchas) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona una cancha',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2E7D60),
              ),
            ),
            const SizedBox(height: 16),
            ...canchas.map((cancha) => ListTile(
              leading: const Icon(Icons.sports_soccer, color: Color(0xFF2E7D60)),
              title: Text(cancha.nombre),
              subtitle: Text(cancha.ubicacion),
              onTap: () {
                Navigator.pop(context);
                _irADetalles(cancha, lugar);
              },
            )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _irADetalles(Cancha cancha, Lugar lugar) {
    final hora24 = _selectedTime!.hour;
    
    final horario = Horario(
      hora: TimeOfDay(hour: hora24, minute: 0),
      estado: EstadoHorario.disponible,
    );
    
    // ✅ VERIFICAR SI HAY PROMOCIÓN ACTIVA PARA ESTA CANCHA Y HORARIO
    Map<String, dynamic>? promocionParaEstaCancha;
    if (_promocionActiva != null) {
      final canchaIdPromo = _promocionActiva!['cancha_id'] as String?;
      final horarioPromo = _promocionActiva!['horario'] as String?;
      final horarioNormalizado = Horario.normalizarHora(horario.horaFormateada);
      final horarioPromoNormalizado = horarioPromo != null ? Horario.normalizarHora(horarioPromo) : null;
      
      if (canchaIdPromo == cancha.id && horarioPromoNormalizado == horarioNormalizado) {
        promocionParaEstaCancha = _promocionActiva;
        debugPrint('✅ Promoción aplicable encontrada para cancha ${cancha.nombre}');
      }
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetallesScreen(
          cancha: cancha,
          fecha: _selectedDate!,
          horario: horario,
          sede: lugar.nombre,
          precioPromocional: promocionParaEstaCancha?['precio_promocional'] as double?,
          promocionId: promocionParaEstaCancha?['promoId'] as String?,
        ),
      ),
    ).then((reservaCreada) {
      if (!mounted) return;
      if (reservaCreada == true) {
        setState(() {
          _promocionActiva = null;
        });
      }
    });
  }

  void _showAvailabilityResults() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildAvailabilityModal(),
    );
  }

  Widget _buildAvailabilityModal() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D60),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.sports_soccer, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Disponibilidad de Canchas',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${DateFormat('EEE d MMM yyyy', 'es').format(_selectedDate!)} · ${_formatHora12h(_selectedTime!.hour)}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Consumer<LugarProvider>(
              builder: (context, lugarProvider, child) {
                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: lugarProvider.lugares.length,
                  itemBuilder: (context, index) {
                    final lugar = lugarProvider.lugares[index];
                    return _buildAvailabilityCard(lugar);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityCard(Lugar lugar) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getCanchaAvailability(lugar),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D60)),
                    strokeWidth: 2,
                  ),
                  SizedBox(width: 16),
                  Text('Verificando disponibilidad...'),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          lugar.nombre,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D60),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Error',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Error al verificar disponibilidad',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final availability = snapshot.data ?? {};
        final canchasDisponibles = availability['disponibles'] ?? 0;
        final canchasApartadas = availability['apartadas'] ?? 0;
        final canchasProcesando = availability['procesando'] ?? 0;
        final totalCanchas = availability['total'] ?? 0;
        final precioDesde = availability['precioDesde'] as double?;
        final precios = (availability['precios'] as List<dynamic>?)?.cast<double>() ?? [];
        final hayVariosPrecios = precios.length > 1 && precios.toSet().length > 1;
        final tienePromo = availability['tienePromo'] as bool? ?? false;

        Color statusColor;
        String statusText;
        IconData statusIcon;

        if (totalCanchas == 0) {
          statusColor = Colors.grey;
          statusText = 'Sin canchas';
          statusIcon = Icons.sports_soccer;
        } else if (canchasDisponibles > 0) {
          statusColor = Colors.green;
          statusText = '$canchasDisponibles disponible${canchasDisponibles > 1 ? 's' : ''}';
          statusIcon = Icons.check_circle;
        } else if (canchasProcesando > 0) {
          statusColor = Colors.orange;
          statusText = '$canchasProcesando procesando pago';
          statusIcon = Icons.payment;
        } else {
          statusColor = Colors.red;
          statusText = 'Todas apartadas';
          statusIcon = Icons.block;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lugar.nombre,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D60),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Dirección: ${lugar.direccion}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Teléfono: ${lugar.telefono}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                if (precioDesde != null && canchasDisponibles > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D60).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF2E7D60).withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 18,
                          color: const Color(0xFF2E7D60),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hayVariosPrecios
                              ? 'Desde \$${precioDesde.toStringAsFixed(0)} / hora'
                              : '\$${precioDesde.toStringAsFixed(0)} / hora',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E7D60),
                          ),
                        ),
                        if (hayVariosPrecios) ...[
                          const SizedBox(width: 4),
                          Text(
                            '(${canchasDisponibles} canchas)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (tienePromo) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.local_offer, size: 12, color: Colors.orange.shade800),
                                const SizedBox(width: 4),
                                Text(
                                  'Promo',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (totalCanchas > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (canchasDisponibles > 0) ...[
                        _buildStatusChip('Disponibles', canchasDisponibles, Colors.green),
                        const SizedBox(width: 8),
                      ],
                      if (canchasApartadas > 0) ...[
                        _buildStatusChip('Apartadas', canchasApartadas, Colors.red),
                        const SizedBox(width: 8),
                      ],
                      if (canchasProcesando > 0) ...[
                        _buildStatusChip('Procesando', canchasProcesando, Colors.orange),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context); // Cerrar modal
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SedeScreen(ciudad: widget.ciudad, lugar: lugar),
                            ),
                          );
                        },
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text('Ver Canchas'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2E7D60),
                          side: const BorderSide(color: Color(0xFF2E7D60)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: canchasDisponibles > 0 ? () {
                          Navigator.pop(context); // Cerrar modal
                          _navegarAReserva(lugar);
                        } : null,
                        icon: const Icon(Icons.sports_soccer, size: 16),
                        label: const Text('Reservar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canchasDisponibles > 0 
                              ? const Color(0xFF2E7D60) 
                              : Colors.grey,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ✅ Tarjeta de promoción minimalista: fondo oscuro, borde dorado, compacta
class _PromoVisible {
  final String fecha;
  final Map<String, dynamic> data;
  final String promoId;
  _PromoVisible({required this.fecha, required this.data, required this.promoId});
}

class _PremiumPromoCard extends StatefulWidget {
  final Lugar lugar;
  final String fechaBonita;
  final String horario;
  final String canchaNombre;
  final String nota;
  final double? precioPromo;
  final double? precioOriginal;
  final double? descuentoPct;
  final VoidCallback onReservar;

  const _PremiumPromoCard({
    required this.lugar,
    required this.fechaBonita,
    required this.horario,
    required this.canchaNombre,
    required this.nota,
    required this.precioPromo,
    required this.precioOriginal,
    required this.descuentoPct,
    required this.onReservar,
  });

  @override
  State<_PremiumPromoCard> createState() => _PremiumPromoCardState();
}

class _PremiumPromoCardState extends State<_PremiumPromoCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _shineController;

  static const _gold = Color(0xFFD4A843);
  static const _goldLight = Color(0xFFE8C85A);
  static const _goldDark = Color(0xFFAA8520);
  static const _darkBg = Color(0xFF141414);

  @override
  void initState() {
    super.initState();
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _shineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasDescuento = widget.descuentoPct != null && widget.descuentoPct! > 0;

    return AnimatedBuilder(
      animation: _shineController,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + (_shineController.value * 3), -0.5),
              end: Alignment(1.0 + (_shineController.value * 3), 0.5),
              colors: const [_goldDark, _goldLight, _gold, _goldLight, _goldDark],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: _gold.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _darkBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  // Shine sweep overlay
                  Positioned.fill(
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        final pos = _shineController.value;
                        return LinearGradient(
                          begin: Alignment(-2.0 + (pos * 4), -0.3),
                          end: Alignment(-1.0 + (pos * 4), 0.3),
                          colors: [
                            Colors.transparent,
                            _gold.withOpacity(0.06),
                            Colors.transparent,
                          ],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.srcATop,
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                  // Content
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onReservar,
                      splashColor: _gold.withOpacity(0.15),
                      highlightColor: _gold.withOpacity(0.08),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Badge descuento / icono oferta
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [_gold.withOpacity(0.25), _goldDark.withOpacity(0.15)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _gold.withOpacity(0.6), width: 1.2),
                              ),
                              child: hasDescuento
                                  ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '-${widget.descuentoPct!.toInt()}%',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                            color: _goldLight,
                                            height: 1,
                                          ),
                                        ),
                                        const Text(
                                          'OFF',
                                          style: TextStyle(
                                            fontSize: 7,
                                            fontWeight: FontWeight.w700,
                                            color: _gold,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Icon(Icons.local_fire_department_rounded, color: _goldLight, size: 22),
                            ),
                            const SizedBox(width: 12),
                            // Info: label + fecha + hora/cancha
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Label "OFERTA"
                                  Row(
                                    children: [
                                      ShaderMask(
                                        shaderCallback: (bounds) {
                                          final pos = _shineController.value;
                                          return LinearGradient(
                                            begin: Alignment(-1.0 + (pos * 3), 0),
                                            end: Alignment(1.0 + (pos * 3), 0),
                                            colors: const [_goldDark, _goldLight, _gold],
                                          ).createShader(bounds);
                                        },
                                        child: const Text(
                                          'OFERTA',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: 1.8,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        width: 20,
                                        height: 1,
                                        color: _gold.withOpacity(0.4),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  if (widget.fechaBonita.isNotEmpty)
                                    Text(
                                      widget.fechaBonita,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withOpacity(0.95),
                                      ),
                                    ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${widget.horario} · ${widget.canchaNombre}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withOpacity(0.65),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (widget.nota.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.nota,
                                      style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Precio + botón
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (widget.precioOriginal != null &&
                                    widget.precioOriginal! > 0 &&
                                    widget.precioPromo != null &&
                                    widget.precioPromo! < widget.precioOriginal!)
                                  Text(
                                    '\$${widget.precioOriginal!.toInt()}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white.withOpacity(0.4),
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: Colors.white.withOpacity(0.4),
                                    ),
                                  ),
                                if (widget.precioPromo != null)
                                  ShaderMask(
                                    shaderCallback: (bounds) {
                                      final pos = _shineController.value;
                                      return LinearGradient(
                                        begin: Alignment(-1.0 + (pos * 3), 0),
                                        end: Alignment(1.0 + (pos * 3), 0),
                                        colors: const [_goldDark, _goldLight, Colors.white, _goldLight, _goldDark],
                                        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                                      ).createShader(bounds);
                                    },
                                    child: Text(
                                      '\$${widget.precioPromo!.toInt()}',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [_goldDark, _gold, _goldLight],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _gold.withOpacity(0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: widget.onReservar,
                                      borderRadius: BorderRadius.circular(8),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        child: Text(
                                          'Reservar',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: _darkBg,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

