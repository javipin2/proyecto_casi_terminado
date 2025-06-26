import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/sede_provider.dart';
import 'canchas_screen.dart';
import 'admin/admin_login_screen.dart';

class SedeScreen extends StatefulWidget {
  const SedeScreen({super.key});

  @override
  State<SedeScreen> createState() => _SedeScreenState();
}

class _SedeScreenState extends State<SedeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  int _logoTapCount = 0;
  DateTime? _lastTapTime;

  // Estilos constantes para mejor organización
  static const _primaryColor = Color(0xFF2E7D60);
  static const _accentColor = Color(0xFF4CAF50);
  static const _cardRadius = 16.0;

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
      duration: const Duration(milliseconds: 1000),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOutQuart),
      ),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 0.6, curve: Curves.easeOutQuart),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SedeProvider>(context, listen: false).fetchSedes();
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Función para determinar si es pantalla grande
  bool _isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width > 768;
  }

  // Función para obtener el ancho máximo del contenido
  double _getMaxContentWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1200) return 1000;
    if (screenWidth > 768) return 700;
    return screenWidth;
  }

  // Función para obtener tamaños responsivos
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
            curve: Curves.easeOutQuart,
          );
          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
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
                curve: Curves.easeInOutQuart,
              );
              return FadeTransition(
                opacity: curvedAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.1),
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final sedeProvider = Provider.of<SedeProvider>(context);
    _isLargeScreen(context);
    final maxWidth = _getMaxContentWidth(context);

    return Scaffold(
      backgroundColor: Colors.white, // Fondo blanco
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: FadeTransition(
          opacity: _fadeAnimation,
          child: const Text(''),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Container(
        color: Colors.white, // Fondo blanco explícito
        width: double.infinity,
        child: Center(
          child: Container(
            width: maxWidth,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _getResponsiveSize(context, size.width * 0.05, 24.0),
                  vertical: _getResponsiveSize(context, size.height * 0.02, 32.0),
                ),
                child: Column(
                  children: [
                    // Header Section
                    SlideTransition(
                      position: _slideAnimation,
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: _buildHeader(context),
                      ),
                    ),
                    
                    SizedBox(height: _getResponsiveSize(context, size.height * 0.04, 48.0)),
                    
                    // Sedes List
                    Expanded(
                      child: sedeProvider.sedes.isEmpty
                          ? _buildEmptyState(context)
                          : _buildSedesList(sedeProvider, context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _isLargeScreen(context);
    
    return Column(
      children: [
        // Logo
        GestureDetector(
          onTap: _handleLogoTap,
          child: Container(
            padding: EdgeInsets.all(_getResponsiveSize(context, 16.0, 20.0)),
            decoration: BoxDecoration(
              color: Colors.white,
            ),
            child: Image.asset(
              'assets/img1.png',
              width: _getResponsiveSize(context, size.width * 0.2, 80.0),
              height: _getResponsiveSize(context, size.width * 0.2, 80.0),
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.sports_tennis,
                  size: _getResponsiveSize(context, size.width * 0.15, 60.0),
                  color: _primaryColor,
                );
              },
            ),
          ),
        ),
        
        SizedBox(height: _getResponsiveSize(context, size.height * 0.03, 32.0)),
        
        // Title and Subtitle
        Text(
          'Selecciona una sede',
          style: TextStyle(
            fontSize: _getResponsiveSize(context, 28.0, 36.0),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1B4D3E),
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        
        SizedBox(height: _getResponsiveSize(context, size.height * 0.01, 12.0)),
        
        Text(
          'Para comenzar tu reserva',
          style: TextStyle(
            fontSize: _getResponsiveSize(context, 16.0, 18.0),
            fontWeight: FontWeight.w400,
            color: const Color(0xFF6B7280),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_off_outlined,
            size: _getResponsiveSize(context, 64.0, 80.0),
            color: Colors.grey[400],
          ),
          SizedBox(height: _getResponsiveSize(context, 16.0, 20.0)),
          Text(
            'No hay sedes disponibles',
            style: TextStyle(
              fontSize: _getResponsiveSize(context, 18.0, 22.0),
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSedesList(SedeProvider sedeProvider, BuildContext context) {
    final isLarge = _isLargeScreen(context);
    
    if (isLarge) {
      // Vista de grid para pantallas grandes
      return GridView.builder(
        physics: const BouncingScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.4,
          crossAxisSpacing: 24,
          mainAxisSpacing: 24,
        ),
        itemCount: sedeProvider.sedes.length,
        itemBuilder: (context, index) {
          final sede = sedeProvider.sedes[index];
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 300 + (index * 100)),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: Hero(
                  tag: 'sede_$sede',
                  child: _buildSedeCard(
                    context,
                    title: sede,
                    imageUrl: sedeProvider.sedeImages[sede] ?? 
                             'https://via.placeholder.com/400x200',
                    sede: sede,
                  ),
                ),
              );
            },
          );
        },
      );
    } else {
      // Vista de lista para móviles
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: sedeProvider.sedes.length,
        itemBuilder: (context, index) {
          final sede = sedeProvider.sedes[index];
          return Padding(
            padding: EdgeInsets.only(bottom: 16.0),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 300 + (index * 100)),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Hero(
                    tag: 'sede_$sede',
                    child: _buildSedeCard(
                      context,
                      title: sede,
                      imageUrl: sedeProvider.sedeImages[sede] ?? 
                               'https://via.placeholder.com/400x200',
                      sede: sede,
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    }
  }

  Widget _buildSedeCard(
    BuildContext context, {
    required String title,
    required String imageUrl,
    required String sede,
  }) {
    final size = MediaQuery.of(context).size;
    _isLargeScreen(context);
    
    return Container(
      height: _getResponsiveSize(context, size.height * 0.25, 200.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.12),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _seleccionarSede(context, sede),
          borderRadius: BorderRadius.circular(_cardRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_cardRadius),
              color: Colors.white,
              border: Border.all(
                color: Colors.grey.withOpacity(0.1),
                width: 1,
              ),
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
                                _primaryColor.withOpacity(0.05), 
                                _accentColor.withOpacity(0.05)
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
                          stops: const [0.5, 1.0],
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
                                  'Toca para seleccionar',
                                  style: TextStyle(
                                    fontSize: _getResponsiveSize(context, 14.0, 15.0),
                                    color: Colors.white.withOpacity(0.9),
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.all(_getResponsiveSize(context, 12.0, 14.0)),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
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