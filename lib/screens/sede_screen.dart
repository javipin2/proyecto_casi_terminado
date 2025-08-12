import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/sede_provider.dart';
import 'canchas_screen.dart';
import 'admin/admin_login_screen.dart';
import 'promociones_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class SedeScreen extends StatefulWidget {
  const SedeScreen({super.key});

  @override
  State<SedeScreen> createState() => _SedeScreenState();
}

class _SedeScreenState extends State<SedeScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _scrollController;
  late AnimationController _navigationController;
  
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _headerSizeAnimation;
  late Animation<double> _backgroundOpacityAnimation;
  late Animation<double> _navigationSlideAnimation;

  final ScrollController _listScrollController = ScrollController();
  double _scrollProgress = 0.0;
  bool _showNavigation = false;
  int _selectedNavIndex = 0;

  int _logoTapCount = 0;
  DateTime? _lastTapTime;

  // Estilos constantes actualizados
  static const _primaryColor = Color(0xFF2E7D60);
  static const _accentColor = Color(0xFF4CAF50);
  static const _navBarColor = Color(0xFF2E7D60);
  static const _navBarAccent = Color(0xFF4CAF50);
  static const _cardRadius = 16.0;
  static const _headerRadius = 24.0;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scrollController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _navigationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    _headerSizeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.65,
    ).animate(
      CurvedAnimation(
        parent: _scrollController,
        curve: Curves.easeOutCubic,
      ),
    );

    _backgroundOpacityAnimation = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(
      CurvedAnimation(
        parent: _scrollController,
        curve: Curves.easeOutCubic,
      ),
    );

    _navigationSlideAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _navigationController,
        curve: Curves.easeOutBack,
      ),
    );

    _listScrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SedeProvider>(context, listen: false).fetchSedes();
      _controller.forward();
      
      // Mostrar la navegación después de un delay
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _showNavigation = true;
          });
          _navigationController.forward();
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _navigationController.dispose();
    _listScrollController.removeListener(_onScroll);
    _listScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
  final maxScroll = _listScrollController.position.maxScrollExtent;
  final currentScroll = _listScrollController.offset;
  
  setState(() {
    _scrollProgress = (currentScroll / maxScroll).clamp(0.0, 1.0);
  });

  // Animación más suave basada en el scroll - ajustada para el nuevo comportamiento
  final scrollRatio = (currentScroll / 110).clamp(0.0, 1.0); // Reducido de 100 a 150 para transición más suave
  _scrollController.animateTo(scrollRatio);
}




  bool _isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width > 768;
  }

  double _getMaxContentWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1200) return 1000;
    if (screenWidth > 768) return 700;
    return screenWidth;
  }

  double _getResponsiveSize(BuildContext context, double mobileSize, double desktopSize) {
    return _isLargeScreen(context) ? desktopSize : mobileSize;
  }

  void _seleccionarSede(BuildContext context, String sede) async {
    HapticFeedback.lightImpact();
    Provider.of<SedeProvider>(context, listen: false).setSede(sede);
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const CanchasScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.1, 0),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: ScaleTransition(
                scale: Tween<double>(
                  begin: 0.95,
                  end: 1.0,
                ).animate(curvedAnimation),
                child: child,
              ),
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  void _handleLogoTap() {
    final now = DateTime.now();

    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 500) {
      _logoTapCount++;

      if (_logoTapCount > 1) {
        HapticFeedback.lightImpact();
      }

      if (_logoTapCount >= 3) {
        _logoTapCount = 0;
        HapticFeedback.mediumImpact();
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const LoginScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              final curvedAnimation = CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOutCubic,
              );
              return FadeTransition(
                opacity: curvedAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.2),
                    end: Offset.zero,
                  ).animate(curvedAnimation),
                  child: child,
                ),
              );
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    } else {
      _logoTapCount = 1;
    }

    _lastTapTime = now;
  }

  Future<void> _launchURL(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  void _onNavigationTap(int index) {
  HapticFeedback.lightImpact();
  
  // Solo cambiar el índice si no estamos navegando
  if (index != _selectedNavIndex) {
    setState(() {
      _selectedNavIndex = index;
    });

    switch (index) {
      case 0:
        // Ya estamos en inicio (sede actual), no hacer nada
        break;
      case 1:
        // Ir a promociones
        _navigateToPromociones();
        break;
    }
  }
}

  void _navigateToPromociones() {
  Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          const PromocionesScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curvedAnimation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.1, 0),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 600),
    ),
  ).then((_) {
    // Resetear el índice cuando regrese
    setState(() {
      _selectedNavIndex = 0;
    });
  });
}


  @override
Widget build(BuildContext context) {
  final size = MediaQuery.of(context).size;
  final sedeProvider = Provider.of<SedeProvider>(context);
  final maxWidth = _getMaxContentWidth(context);

  return Scaffold(
    backgroundColor: Colors.grey[50],
    body: Stack(
      children: [
        // Contenido principal
        Column(
          children: [
            // Header con imagen de fondo y logo
            AnimatedBuilder(
              animation: Listenable.merge([_headerSizeAnimation, _backgroundOpacityAnimation]),
              builder: (context, child) {
                final headerHeight = size.height * (0.32 * _headerSizeAnimation.value);
                return Container(
                  height: headerHeight,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      // Imagen de fondo con bordes redondeados
                      Positioned.fill(
                        child: Container(
                          margin: EdgeInsets.only(bottom: _headerRadius),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(_headerRadius),
                              bottomRight: Radius.circular(_headerRadius),
                            ),
                            image: DecorationImage(
                              image: AssetImage('assets/grama1.jpg'),
                              fit: BoxFit.cover,
                              colorFilter: ColorFilter.mode(
                                _primaryColor.withOpacity(_backgroundOpacityAnimation.value),
                                BlendMode.overlay,
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      // Overlay con degradado
                      Positioned.fill(
                        child: Container(
                          margin: EdgeInsets.only(bottom: _headerRadius),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(_headerRadius),
                              bottomRight: Radius.circular(_headerRadius),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color.fromARGB(58, 61, 61, 61).withOpacity(0.4),
                                const Color.fromARGB(28, 48, 48, 48).withOpacity(0.6),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      // Logo en la parte derecha con animación
                      Positioned(
                        right: 24,
                        top: MediaQuery.of(context).padding.top + 20,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: ScaleTransition(
                              scale: _headerSizeAnimation,
                              child: GestureDetector(
                                onTap: _handleLogoTap,
                                child: Container(
                                  padding: EdgeInsets.all(1),
                                  decoration: BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color.fromARGB(88, 0, 0, 0),
                                        blurRadius: 20,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Image.asset(
                                    'assets/img1.png',
                                    width: 90,
                                    height: 90,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.sports_tennis,
                                        size: 50,
                                        color: Colors.white,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Título principal con animación
                      Positioned(
                        left: 24,
                        bottom: 40,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: ScaleTransition(
                              scale: _headerSizeAnimation,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Selecciona',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w300,
                                      color: Colors.white.withOpacity(0.95),
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  Text(
                                    'una sede',
                                    style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  SizedBox(height: 25),
                                  Text(
                                    '',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white.withOpacity(0.85),
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Lista de sedes superpuesta sobre el header
            Expanded(
              child: AnimatedBuilder(
                animation: _scrollController,
                builder: (context, child) {
                  // Calcula los valores basados en el scroll
                  final scrollValue = _scrollController.value;
                  final overlayOffset = -80 + (scrollValue * 90); // De -60 a -20
                  final containerWidth = 0.85 + (scrollValue * 0.1); // De 0.85 a 0.95
                  final horizontalMargin = 16.0 + (scrollValue * 8.0); // De 16 a 24
                  final topPadding = 10.0 + (scrollValue * 10.0); // De 16 a 32
                  final borderRadius = 28.0 - (scrollValue * 10.0); // De 28 a 20
                  
                  return Transform.translate(
                    offset: Offset(0, overlayOffset),
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(borderRadius),
                          topRight: Radius.circular(borderRadius),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08 + (scrollValue * 0.07)), // Sombra más intensa cuando se separa
                            blurRadius: 20 + (scrollValue * 10),
                            offset: Offset(0, -5 - (scrollValue * 5)),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxWidth * containerWidth,
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(5.0, topPadding, 5, 0),
                            child: sedeProvider.sedes.isEmpty
                                ? _buildEmptyState(context)
                                : Column(
                                    children: [
                                      Expanded(
                                        child: _buildSedesListWithSoftwareLink(sedeProvider, context),
                                      ),
                                      SizedBox(height: 100), // Espacio para la navegación
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),


          ],
        ),

        // Navigation Bar estilo moderno con colores actualizados
        if (_showNavigation)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _navigationSlideAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, 100 * _navigationSlideAnimation.value),
                  child: Container(
                    margin: EdgeInsets.fromLTRB(20, 0, 20, 20),
                    height: 70,
                    decoration: BoxDecoration(
                      color: _navBarColor,
                      borderRadius: BorderRadius.circular(35),
                      boxShadow: [
                        BoxShadow(
                          color: _navBarColor.withOpacity(0.3),
                          blurRadius: 25,
                          offset: Offset(0, 10),
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildNavItem(
                            icon: Icons.home_rounded,
                            label: 'INICIO',
                            index: 0,
                            isSelected: _selectedNavIndex == 0,
                          ),
                        ),
                        Expanded(
                          child: _buildNavItem(
                            icon: Icons.local_offer_rounded,
                            label: 'OFERTAS',
                            index: 1,
                            isSelected: _selectedNavIndex == 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    ),
  );
}



  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => _onNavigationTap(index),
      child: Container(
        height: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: Duration(milliseconds: 100),
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected ? _navBarAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                size: 24,
              ),
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 800),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: Icon(
                  Icons.location_off_outlined,
                  size: _getResponsiveSize(context, 64.0, 80.0),
                  color: Colors.grey[400],
                ),
              );
            },
          ),
          SizedBox(height: _getResponsiveSize(context, 16.0, 20.0)),
          FadeTransition(
            opacity: _fadeAnimation,
            child: Text(
              'No hay sedes disponibles',
              style: TextStyle(
                fontSize: _getResponsiveSize(context, 18.0, 22.0),
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSedesListWithSoftwareLink(SedeProvider sedeProvider, BuildContext context) {
  final isLarge = _isLargeScreen(context);
  
  if (isLarge) {
    return GridView.builder(
      controller: _listScrollController,
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.4,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: sedeProvider.sedes.length + 1, // +1 para el enlace del software
      itemBuilder: (context, index) {
        if (index < sedeProvider.sedes.length) {
          return _buildSedeCardAnimated(sedeProvider, index, context);
        } else {
          return _buildSoftwareLinkCard(context);
        }
      },
    );
  } else {
    return ListView.builder(
      controller: _listScrollController,
      physics: const BouncingScrollPhysics(),
      itemCount: sedeProvider.sedes.length + 1, // +1 para el enlace del software
      itemBuilder: (context, index) {
        if (index < sedeProvider.sedes.length) {
          return Padding(
            padding: EdgeInsets.only(bottom: 16.0),
            child: _buildSedeCardAnimated(sedeProvider, index, context),
          );
        } else {
          return Padding(
            padding: EdgeInsets.only(bottom: 24.0, top: 8.0),
            child: _buildSoftwareLinkCard(context),
          );
        }
      },
    );
  }
}


  Widget _buildSoftwareLinkCard(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_cardRadius),
              border: Border.all(
                color: _primaryColor.withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  Icons.code_rounded,
                  size: 32,
                  color: _primaryColor,
                ),
                SizedBox(height: 12),
                Text(
                  '¿Te interesa nuestro software?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _launchURL('https://wa.me/573001234567'),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Contáctanos en ',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        TextSpan(
                          text: 'WhatsApp',
                          style: TextStyle(
                            color: _primaryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: _primaryColor,
                          ),
                        ),
                        TextSpan(
                          text: ' para más información',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSedeCardAnimated(SedeProvider sedeProvider, int index, BuildContext context) {
    final sede = sedeProvider.sedes[index];
    final nombreSede = sede['nombre'] as String;
    final imagenSede = sede['imagen'] as String;
    
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 100 + (index * 50)),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, 0.5),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: _controller,
                curve: Interval(
                  0.3 + (index * 0.1),
                  0.7 + (index * 0.1),
                  curve: Curves.easeOutCubic,
                ),
              ),
            ),
            child: Hero(
              tag: 'sede_$nombreSede',
              child: _buildSedeCard(
                context,
                title: nombreSede,
                imageUrl: imagenSede,
                sede: nombreSede,
                descripcion: sede['descripcion'] as String? ?? '',
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSedeCard(
    BuildContext context, {
    required String title,
    required String imageUrl,
    required String sede,
    String? descripcion,
  }) {
    final size = MediaQuery.of(context).size;
    
    return Container(
      height: _getResponsiveSize(context, size.height * 0.25, 100.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _seleccionarSede(context, sede),
          borderRadius: BorderRadius.circular(_cardRadius),
          splashColor: _primaryColor.withOpacity(0.1),
          highlightColor: _primaryColor.withOpacity(0.05),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_cardRadius),
              color: Colors.white,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_cardRadius),
              child: Stack(
                children: [
                  // Background Image
                  Positioned.fill(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey[50],
                          child: Center(
                            child: CircularProgressIndicator(
                              color: _primaryColor,
                              strokeWidth: 2,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _primaryColor.withOpacity(0.1), 
                                _accentColor.withOpacity(0.1)
                              ],
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.location_city,
                              size: _getResponsiveSize(context, 48.0, 56.0),
                              color: _primaryColor,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  
                  // Gradient Overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.6),
                          ],
                          stops: const [0.3, 1.0],
                        ),
                      ),
                    ),
                  ),
                  
                  // Content
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.all(_getResponsiveSize(context, 20.0, 24.0)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: _getResponsiveSize(context, 22.0, 24.0),
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  descripcion?.isNotEmpty == true 
                                      ? descripcion! 
                                      : 'Toca para seleccionar',
                                  style: TextStyle(
                                    fontSize: _getResponsiveSize(context, 14.0, 15.0),
                                    color: Colors.white.withOpacity(0.9),
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.all(_getResponsiveSize(context, 12.0, 14.0)),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(0, 0, 0, 0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color.fromRGBO(0, 0, 0, 0.9),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white,
                              size: _getResponsiveSize(context, 16.0, 18.0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}