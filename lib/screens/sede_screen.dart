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
  
  int _selectedIndex = 0;
  late PageController _pageController;
  late AnimationController _navigationController;
  late Animation<double> _navigationSlideAnimation;

  // Colores constantes para la navegación
  static const _navBarColor = Color(0xFF2E7D60);
  static const _navBarAccent = Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    
    _pageController = PageController(initialPage: _selectedIndex);
    
    _navigationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
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

    // Mostrar la navegación con animación
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          _navigationController.forward();
        }
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _navigationController.dispose();
    super.dispose();
  }

  void _onNavigationTap(int index) {
    if (index != _selectedIndex) {
      HapticFeedback.lightImpact();
      
      setState(() {
        _selectedIndex = index;
      });
      
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _onPageChanged(int index) {
    if (index != _selectedIndex) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Contenido principal con PageView
          PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            physics: const BouncingScrollPhysics(),
            children: const [
              SedeScreenContent(), // Versión sin navegación del SedeScreen
              PromocionesScreenContent(), // Versión sin navegación del PromocionesScreen
            ],
          ),
          
          // Barra de navegación fija
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
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 0, 0, 0),
                      borderRadius: BorderRadius.circular(35),
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.3),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
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
                            isSelected: _selectedIndex == 0,
                          ),
                        ),
                        Expanded(
                          child: _buildNavItem(
                            icon: Icons.local_offer_rounded,
                            label: 'OFERTAS',
                            index: 1,
                            isSelected: _selectedIndex == 1,
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
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isSelected ? _navBarAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// SEDE SCREEN CONTENT
// ==========================================
class SedeScreenContent extends StatefulWidget {
  const SedeScreenContent({super.key});

  @override
  State<SedeScreenContent> createState() => _SedeScreenContentState();
}

class _SedeScreenContentState extends State<SedeScreenContent>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _scrollController;
  
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _headerSizeAnimation;
  late Animation<double> _backgroundOpacityAnimation;

  final ScrollController _listScrollController = ScrollController();
  double _scrollProgress = 0.0;

  int _logoTapCount = 0;
  DateTime? _lastTapTime;

  // Estilos constantes actualizados
  static const _primaryColor = Color(0xFF2E7D60);
  static const _accentColor = Color(0xFF4CAF50);
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

    _listScrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SedeProvider>(context, listen: false).fetchSedes();
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _listScrollController.removeListener(_onScroll);
    _listScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final maxScroll = _listScrollController.position.maxScrollExtent;
    final currentScroll = _listScrollController.offset;
    
    setState(() {
      _scrollProgress = maxScroll > 0 ? (currentScroll / maxScroll).clamp(0.0, 1.0) : 0.0;
    });

    final scrollRatio = (currentScroll / 110).clamp(0.0, 1.0);
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final sedeProvider = Provider.of<SedeProvider>(context);
    final maxWidth = _getMaxContentWidth(context);

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header con imagen de fondo y logo
          _buildAnimatedHeader(context, size),
          
          // Lista de sedes superpuesta sobre el header
          Expanded(
            child: _buildSedesList(context, sedeProvider, maxWidth),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedHeader(BuildContext context, Size size) {
    return AnimatedBuilder(
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
                        const Color.fromARGB(255, 0, 0, 0).withOpacity(_backgroundOpacityAnimation.value),
                        BlendMode.overlay,
                      ),
                    ),
                  ),
                ),
              ),
              
              // Overlay con degradado
              _buildHeaderOverlay(),
              
              // Logo en la parte derecha con animación
              _buildAnimatedLogo(context),

              // Título principal con animación
              _buildAnimatedTitle(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderOverlay() {
    return Positioned.fill(
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
    );
  }

  Widget _buildAnimatedLogo(BuildContext context) {
    return Positioned(
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
    );
  }

  Widget _buildAnimatedTitle() {
    return Positioned(
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
    );
  }

  Widget _buildSedesList(BuildContext context, SedeProvider sedeProvider, double maxWidth) {
    return AnimatedBuilder(
      animation: _scrollController,
      builder: (context, child) {
        // Calcula los valores basados en el scroll
        final scrollValue = _scrollController.value;
        final overlayOffset = -80 + (scrollValue * 90);
        final containerWidth = 0.85 + (scrollValue * 0.1);
        final horizontalMargin = 20.0 + (scrollValue * 6.0);
        final topPadding = 10.0 + (scrollValue * 10.0);
        final borderRadius = 28.0 - (scrollValue * 10.0);
        
        return Transform.translate(
          offset: Offset(0, overlayOffset),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color.fromARGB(0, 0, 0, 0),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(borderRadius),
                topRight: Radius.circular(borderRadius),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.08 + (scrollValue * 0.07)),
                  blurRadius: 10 + (scrollValue * 10),
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
                            SizedBox(height: 20), // Espacio extra para la navegación
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
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
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.4,
          crossAxisSpacing: 24,
          mainAxisSpacing: 24,
        ),
        itemCount: sedeProvider.sedes.length + 1,
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
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        itemCount: sedeProvider.sedes.length + 1,
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
    return GestureDetector(
      onTap: () => _launchURL('https://wa.me/573018315940'),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          children: [
            TextSpan(
              text: '¿Te interesa nuestro software? ',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            TextSpan(
              text: 'Contáctanos en WhatsApp',
              style: TextStyle(
                color: _primaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w400,
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
            color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.1),
            blurRadius: 10,
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
          splashColor: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.1),
          highlightColor: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.05),
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
                          color: Colors.grey[100],
                          child: Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.grey[400],
                              size: 40,
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
                            const Color.fromARGB(14, 143, 143, 143),
                            const Color.fromARGB(117, 0, 0, 0).withOpacity(0.8),
                          ],
                          stops: const [0.3, 1.0],
                        ),
                      ),
                    ),
                  ),
                  
                  // Título
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
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

// ==========================================
// PROMOCIONES SCREEN CONTENT (PLACEHOLDER)
// ==========================================
class PromocionesScreenContent extends StatelessWidget {
  const PromocionesScreenContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[50],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_offer_rounded,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Promociones',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Próximamente disponible',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}