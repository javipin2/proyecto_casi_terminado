import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

class PromocionesScreen extends StatefulWidget {
  const PromocionesScreen({super.key});

  @override
  State<PromocionesScreen> createState() => _PromocionesScreenState();
}

class _PromocionesScreenState extends State<PromocionesScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _fabController;
  late AnimationController _headerController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _headerFadeAnimation;

  // Colores más sofisticados
  static const _primaryColor = Color(0xFF1B5E3F);
  static const _cardColor = Color(0xFFFFFFFE);

  // Usar imagen de assets en lugar de URL
  final String _backgroundImagePath = 'assets/grama1.jpg'; // Cambia por tu ruta

  // Lista mejorada de promociones
  final List<Map<String, dynamic>> _promociones = [
    {
      'titulo': 'Primera Reserva',
      'subtitulo': 'Descuento especial',
      'descripcion': 'Obtén 50% de descuento en tu primera reserva. Válido para canchas de fútbol, tenis y básquet.',
      'descuento': '50%',
      'validez': '31 Dic 2024',
      'codigo': 'PRIMERA50',
      'tipo': 'Nuevo Cliente',
      'icono': Icons.star_rounded,
      'gradientColors': [Color(0xFFFF6B6B), Color(0xFFFF8E8E)],
      'popular': true,
    },

  ];

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );


    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
      ),
    );


    _headerFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _headerController,
        curve: Curves.easeInOut,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.forward();
      _headerController.forward();
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _fabController.forward();
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _fabController.dispose();
    _headerController.dispose();
    super.dispose();
  }

  bool _isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width > 768;
  }

  double _getResponsiveSize(BuildContext context, double mobileSize, double desktopSize) {
    return _isLargeScreen(context) ? desktopSize : mobileSize;
  }

  void _copyToClipboard(String codigo) {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: codigo));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Código $codigo copiado al portapapeles'),
          ],
        ),
        backgroundColor: _primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Color(0xFFF8FAFB),
      body: CustomScrollView(
        slivers: [
          // Header como SliverAppBar
          SliverToBoxAdapter(
            child: _buildEnhancedHeader(size),
          ),
          
          // Lista de promociones
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final delay = index * 0.1;
                      final slideAnimation = Tween<Offset>(
                        begin: const Offset(0.3, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: _controller,
                          curve: Interval(
                            delay,
                            0.8 + delay,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                      );
                      
                      final fadeAnimation = Tween<double>(
                        begin: 0.0,
                        end: 1.0,
                      ).animate(
                        CurvedAnimation(
                          parent: _controller,
                          curve: Interval(
                            delay,
                            0.7 + delay,
                            curve: Curves.easeOut,
                          ),
                        ),
                      );

                      return SlideTransition(
                        position: slideAnimation,
                        child: FadeTransition(
                          opacity: fadeAnimation,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: _buildEnhancedPromocionCard(_promociones[index]),
                          ),
                        ),
                      );
                    },
                  );
                },
                childCount: _promociones.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedHeader(Size size) {
    return SizedBox(
      height: size.height * 0.38,
      width: double.infinity,
      child: Stack(
        children: [
          // Imagen de fondo con fallback a gradiente
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              // Gradiente como fallback si no hay imagen
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color.fromARGB(88, 71, 71, 71),
                  const Color.fromARGB(97, 0, 0, 0),
                ],
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                // Usar AssetImage en lugar de NetworkImage
                image: DecorationImage(
                  image: AssetImage(_backgroundImagePath),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    const Color.fromARGB(255, 0, 0, 0).withOpacity(0.8),
                    BlendMode.multiply,
                  ),
                  onError: (exception, stackTrace) {
                    // Si la imagen no carga, usa solo el gradiente
                  },
                ),
              ),
            ),
          ),
          
          // Gradiente adicional siempre presente
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color.fromARGB(40, 66, 66, 9).withOpacity(0.7),
                  const Color.fromARGB(96, 0, 0, 9).withOpacity(0.6),
                ],
              ),
            ),
          ),
          
          // Patrón decorativo sutil
          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              child: CustomPaint(
                painter: _EnhancedPatternPainter(),
              ),
            ),
          ),
          
          // Contenido del header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Botón de regreso mejorado
                  FadeTransition(
                    opacity: _headerFadeAnimation,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded, 
                                       color: Colors.white, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Título principal mejorado
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _headerFadeAnimation,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Badge de promociones
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.local_fire_department_rounded, 
                                     color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'OFERTAS ESPECIALES',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          Text(
                            'Promociones',
                            style: TextStyle(
                              fontSize: _getResponsiveSize(context, 36, 42),
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -1,
                              height: 1.1,
                            ),
                          ),
                          
                          Text(
                            'Exclusivas',
                            style: TextStyle(
                              fontSize: _getResponsiveSize(context, 24, 28),
                              fontWeight: FontWeight.w300,
                              color: Colors.white.withOpacity(0.95),
                              letterSpacing: 2,
                            ),
                          ),
                          
                          const SizedBox(height: 12),
                          
                          Text(
                            '',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedPromocionCard(Map<String, dynamic> promocion) {
    final gradientColors = promocion['gradientColors'] as List<Color>;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: _cardColor,
          child: InkWell(
            onTap: () => _copyToClipboard(promocion['codigo']),
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header de la tarjeta
                  Row(
                    children: [
                      // Ícono con gradiente
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: gradientColors[0].withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          promocion['icono'],
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Badge de tipo
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                promocion['tipo'].toUpperCase(),
                                style: TextStyle(
                                  color: _primaryColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 4),
                            
                            // Título
                            Text(
                              promocion['titulo'],
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A1A),
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Descuento destacado
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          promocion['descuento'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  if (promocion['popular'] == true) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Color(0xFFFFD700).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Color(0xFFFFD700), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 14),
                          SizedBox(width: 4),
                          Text(
                            'MÁS POPULAR',
                            style: TextStyle(
                              color: Color(0xFFB8860B),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 16),
                  
                  // Subtítulo y descripción
                  Text(
                    promocion['subtitulo'],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: gradientColors[0],
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    promocion['descripcion'],
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Código promocional mejorado
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Color(0xFFF8FAFB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _primaryColor.withOpacity(0.15),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'CÓDIGO PROMOCIONAL',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.content_copy_rounded, 
                                       size: 12, color: Colors.grey[600]),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                promocion['codigo'],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: _primaryColor,
                                  letterSpacing: 1.5,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _primaryColor,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryColor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.content_copy_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Información adicional
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Válido hasta: ${promocion['validez']}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Text(
                          'ACTIVA',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
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
      ),
    );
  }
}

// Painter mejorado para patrones más sutiles
class _EnhancedPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    // Círculos sutiles
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 2; j++) {
        final dx = (size.width / 2) * i + size.width * 0.1;
        final dy = (size.height / 1.5) * j + size.height * 0.2;
        final radius = 40.0 + (i * 15.0);
        
        canvas.drawCircle(
          Offset(dx, dy),
          radius,
          paint..color = Colors.white.withOpacity(0.04),
        );
      }
    }

    // Líneas geométricas sutiles
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path();
    path.moveTo(size.width * 0.7, 0);
    path.lineTo(size.width * 0.9, size.height * 0.3);
    path.lineTo(size.width * 1.1, size.height * 0.1);
    
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Extensión para matemáticas
extension MathUtils on double {
  double sin() => math.sin(this);
}