import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reserva_canchas/screens/admin/registro/EncargadoRegistroReservasScreen.dart';
import 'package:reserva_canchas/screens/admin/reservas%20a%20confirmar/reservas_pendientes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../sede_screen.dart';

class EncargadoDashboardScreen extends StatefulWidget {
  const EncargadoDashboardScreen({super.key});

  @override
  EncargadoDashboardScreenState createState() => EncargadoDashboardScreenState();
}

class EncargadoDashboardScreenState extends State<EncargadoDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _badgeController;
  late Stream<QuerySnapshot> _reservasPendientesStream;

  // Paleta de colores
  final Color _secondaryColor = const Color(0xFF6366F1);
  final Color _accentColor = const Color(0xFF8B5CF6);
  final Color _backgroundColor = const Color(0xFFF8FAFC);
  final Color _cardColor = Colors.white;
  final Color _surfaceColor = const Color(0xFFF1F5F9);
  final Color _textPrimary = const Color(0xFF0F172A);
  final Color _textSecondary = const Color(0xFF64748B);
  final Color _borderColor = const Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    
    _reservasPendientesStream = FirebaseFirestore.instance
        .collection('reservas')
        .where('confirmada', isEqualTo: false)
        .snapshots();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _badgeController.dispose();
    super.dispose();
  }

  Future<void> _showLogoutConfirmation(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 10,
          backgroundColor: _cardColor,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: Colors.red.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Cerrar Sesión',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Text(
            '¿Estás seguro de que deseas cerrar sesión?',
            style: GoogleFonts.inter(
              color: _textSecondary,
              fontSize: 15,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: _textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: Text(
                'Cancelar',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _logout(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Cerrar Sesión',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
              ),
              const SizedBox(height: 16),
              Text(
                'Cerrando sesión...',
                style: GoogleFonts.inter(
                  color: _textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pop();
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const SedeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Error al cerrar sesión: $e',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = screenSize.width > 1200;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: _buildAppBar(context),
      drawer: isDesktop ? null : _buildDrawer(context, user),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _backgroundColor,
              _surfaceColor.withValues(alpha: 0.3),
            ],
            stops: const [0.0, 1.0],
          ),
        ),
        child: Column(
          children: [
            _buildWelcomeHeader(user),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 32.0 : 16.0,
                  vertical: isDesktop ? 24.0 : 16.0,
                ),
                child: 
                LayoutBuilder(
  builder: (context, constraints) {
    int crossAxisCount;
    double childAspectRatio;
    
    if (constraints.maxWidth > 1200) {
      crossAxisCount = 3;  // Cambio de 2 a 3
      childAspectRatio = 1.2;  // Cambio de 0.95 a 1.2
    } else if (constraints.maxWidth > 900) {
      crossAxisCount = 2;
      childAspectRatio = 1.0;  // Cambio de 0.9 a 1.0
    } else if (constraints.maxWidth > 600) {
      crossAxisCount = 2;
      childAspectRatio = 0.95;  // Cambio de 0.85 a 0.95
    } else {
      crossAxisCount = 1;
      childAspectRatio = 1.1;
    }
    
    return GridView.count(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: isDesktop ? 20 : 20,  // Cambio de 24 a 20
      mainAxisSpacing: isDesktop ? 20 : 20,   // Cambio de 24 a 20
      childAspectRatio: childAspectRatio,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      children: _buildEncargadoCards(context),
    );
  },
),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_secondaryColor, _accentColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _secondaryColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.dashboard_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Encargado',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              fontSize: 20,
            ),
          ),
        ],
      ),
      backgroundColor: _cardColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      surfaceTintColor: Colors.transparent,
      shadowColor: _borderColor,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: _borderColor,
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          child: Tooltip(
            message: 'Cerrar sesión',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showLogoutConfirmation(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.shade200,
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.logout_rounded,
                    color: Colors.red.shade600,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeHeader(User? user) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = screenSize.width > 1200;
    final isTablet = screenSize.width > 768;
    
    final hour = DateTime.now().hour;
    String greeting = 'Buenos días';
    IconData greetingIcon = Icons.wb_sunny_rounded;
    
    if (hour >= 12 && hour < 18) {
      greeting = 'Buenas tardes';
      greetingIcon = Icons.wb_sunny_outlined;
    } else if (hour >= 18) {
      greeting = 'Buenas noches';
      greetingIcon = Icons.brightness_3_rounded;
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(
        horizontal: isDesktop ? 32.0 : 16.0,
        vertical: isDesktop ? 24.0 : 16.0,
      ),
      padding: EdgeInsets.all(isDesktop ? 28.0 : 20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_secondaryColor, _accentColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _secondaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      greetingIcon,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: isDesktop ? 24 : 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      greeting,
                      style: GoogleFonts.inter(
                        fontSize: isDesktop ? 16 : 14,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Encargado',
                  style: GoogleFonts.inter(
                    fontSize: isDesktop ? 28 : 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'encargado@gmail.com',
                  style: GoogleFonts.inter(
                    fontSize: isDesktop ? 14 : 12,
                    color: Colors.white.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (isTablet) ...[
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_pulseController.value * 0.05),
                  child: Container(
                    width: isDesktop ? 64 : 56,
                    height: isDesktop ? 64 : 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Colors.white,
                      size: isDesktop ? 32 : 28,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, duration: 600.ms);
  }

  List<Widget> _buildEncargadoCards(BuildContext context) {
    final cardConfigs = [
      {
        'icon': Icons.pending_actions_rounded,
        'title': 'Reservas Pendientes',
        'description': 'Confirma las reservas pendientes.',
        'color': const Color(0xFFFF6B35),
        'bgColor': const Color(0xFFFFF4E6),
        'screen': const Confirmar(),
        'hasNotification': true,
      },
      {
        'icon': Icons.book_rounded,
        'title': 'Registro de Reservas',
        'description': 'Historial de reservas.',
        'color': const Color(0xFF06B6D4),
        'bgColor': const Color(0xFFECFEFF),
        'screen': const EncargadoRegistroReservasScreen(),
        'hasNotification': false,
      },
    ];

    return cardConfigs.asMap().entries.map((entry) {
      final index = entry.key;
      final config = entry.value;
      
      if (config['hasNotification'] == true) {
        return StreamBuilder<QuerySnapshot>(
          stream: _reservasPendientesStream,
          builder: (context, snapshot) {
            int notificationCount = 0;
            if (snapshot.hasData) {
              notificationCount = snapshot.data!.docs.length;
            }
            
            return _buildEncargadoCard(
              icon: config['icon'] as IconData,
              title: config['title'] as String,
              description: config['description'] as String,
              color: config['color'] as Color,
              backgroundColor: config['bgColor'] as Color,
              context: context,
              screen: config['screen'] as Widget,
              delay: index * 100,
              notificationCount: notificationCount,
            );
          },
        );
      }
      
      return _buildEncargadoCard(
        icon: config['icon'] as IconData,
        title: config['title'] as String,
        description: config['description'] as String,
        color: config['color'] as Color,
        backgroundColor: config['bgColor'] as Color,
        context: context,
        screen: config['screen'] as Widget,
        delay: index * 100,
      );
    }).toList();
  }

  Widget _buildEncargadoCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required Color backgroundColor,
    required BuildContext context,
    required Widget screen,
    required int delay,
    int? notificationCount,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = screenSize.width > 1200;
    final isTablet = screenSize.width > 768;
    
    return Animate(
      effects: [
        FadeEffect(
          duration: const Duration(milliseconds: 600),
          delay: Duration(milliseconds: 300 + delay),
          curve: Curves.easeOutCubic,
        ),
        SlideEffect(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
          duration: const Duration(milliseconds: 600),
          delay: Duration(milliseconds: 300 + delay),
          curve: Curves.easeOutCubic,
        ),
        ScaleEffect(
          begin: const Offset(0.9, 0.9),
          end: const Offset(1.0, 1.0),
          duration: const Duration(milliseconds: 600),
          delay: Duration(milliseconds: 300 + delay),
          curve: Curves.easeOutCubic,
        ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => screen,
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0);
                    const end = Offset.zero;
                    const curve = Curves.easeInOutCubic;
                    var tween = Tween(begin: begin, end: end)
                        .chain(CurveTween(curve: curve));
                    return SlideTransition(
                      position: animation.drive(tween),
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    );
                  },
                  transitionDuration: const Duration(milliseconds: 400),
                ),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: 
            Container(
              height: double.infinity,
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _borderColor.withValues(alpha: 0.5),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: color.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Center(
                    child: Padding(
  padding: EdgeInsets.all(isDesktop ? 20.0 : 20.0),  // Cambio de 24.0 a 20.0
  child: Column(

                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: Duration(milliseconds: 600 + delay),
                            curve: Curves.elasticOut,
                            builder: (context, value, child) {
                              return Transform.scale(
                                scale: value,
                                child: 
                                Container(
  width: isDesktop ? 56 : 56,  // Cambio de 64 a 56
  height: isDesktop ? 56 : 56, // Cambio de 64 a 56
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [
        backgroundColor,
        backgroundColor.withValues(alpha: 0.7),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(16),  // Cambio de 18 a 16
    border: Border.all(
      color: color.withValues(alpha: 0.3),
      width: 2,
    ),
    boxShadow: [
      BoxShadow(
        color: color.withValues(alpha: 0.2),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  ),
  child: Icon(
    icon,
    size: isDesktop ? 28 : 28,  // Cambio de 32 a 28
    color: color,
  ),
),

                              );
                            },
                          ),
                          SizedBox(height: isDesktop ? 16 : 16),  // Cambio de 20 a 16
Text(
  title,
  style: GoogleFonts.inter(
    fontSize: isDesktop ? 16 : 16,  // Cambio de 18 a 16
    fontWeight: FontWeight.w700,
    color: _textPrimary,
    letterSpacing: -0.5,
  ),
  textAlign: TextAlign.center,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
),
SizedBox(height: isDesktop ? 6 : 6),   // Cambio de 8 a 6
Flexible(
  child: Text(
    description,
    style: GoogleFonts.inter(
      fontSize: isDesktop ? 13 : 13,  // Cambio de 14 a 13
      color: _textSecondary,
      height: 1.4,
      fontWeight: FontWeight.w500,
    ),
    textAlign: TextAlign.center,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  ),
),
SizedBox(height: isDesktop ? 16 : 16), // Cambio de 20 a 16

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  color.withValues(alpha: 0.1),
                                  color.withValues(alpha: 0.05),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: color.withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Acceder',
                                  style: GoogleFonts.inter(
                                    fontSize: isDesktop ? 13 : 12,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: isDesktop ? 16 : 14,
                                  color: color,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (notificationCount != null && notificationCount > 0)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: AnimatedBuilder(
                        animation: _badgeController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: 1.0 + (_badgeController.value * 0.15),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.red.shade500,
                                    Colors.red.shade600,
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.shade500.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                  BoxShadow(
                                    color: Colors.red.shade500.withValues(alpha: 0.2),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              child: Center(
                                child: Text(
                                  notificationCount > 99 ? '99+' : '$notificationCount',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    height: 1.0,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (isTablet)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.03),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
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

  Widget _buildDrawer(BuildContext context, User? user) {
    return Drawer(
      backgroundColor: _cardColor,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_secondaryColor, _accentColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Encargado',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'encargado@gmail.com',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildDrawerItem(
                  icon: Icons.dashboard_rounded,
                  title: 'Dashboard',
                  onTap: () => Navigator.pop(context),
                ),
                _buildDrawerItem(
                  icon: Icons.pending_actions_rounded,
                  title: 'Reservas Pendientes',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const Confirmar()),
                    );
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.book_rounded,
                  title: 'Registro de Reservas',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const EncargadoRegistroReservasScreen()),
                    );
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(),
                ),
                _buildDrawerItem(
                  icon: Icons.logout_rounded,
                  title: 'Cerrar Sesión',
                  onTap: () {
                    Navigator.pop(context);
                    _showLogoutConfirmation(context);
                  },
                  isDestructive: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDestructive 
                ? Colors.red.withValues(alpha: 0.1)
                : _surfaceColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: isDestructive ? Colors.red.shade600 : _textSecondary,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            color: isDestructive ? Colors.red.shade600 : _textPrimary,
            fontSize: 14,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}