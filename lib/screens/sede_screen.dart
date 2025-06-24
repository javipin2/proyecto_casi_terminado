import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
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
  final List<Animation<double>> _buttonScales = [];

  int _logoTapCount = 0;
  DateTime? _lastTapTime;

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

    for (int i = 0; i < 2; i++) {
      _buttonScales.add(
        Tween<double>(begin: 0.9, end: 1.0).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Interval(0.3 + (i * 0.1), 0.7 + (i * 0.1),
                curve: Curves.easeOutCubic),
          ),
        ),
      );
    }

    Future.delayed(const Duration(milliseconds: 50), () {
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _seleccionarSede(BuildContext context, String sede) async {
    HapticFeedback.lightImpact();
    await Provider.of<SedeProvider>(context, listen: false).setSede(sede);
    if (!mounted) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const CanchasScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation =
              CurvedAnimation(parent: animation, curve: Curves.easeOutQuart);
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
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: FadeTransition(
          opacity: _fadeAnimation,
          child: const Text(''),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        // Eliminamos el botón de retroceso automático
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  const Color(0xFFF8F9FA),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned.fill(
            child: FadeTransition(
              opacity: Animation<double>.fromValueListenable(
                ValueNotifier(_fadeAnimation.value * 0.4),
              ),
              child: CustomPaint(
                painter: MinimalistPatternPainter(),
                size: Size.infinite,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SlideTransition(
                position: _slideAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: GestureDetector(
                          onTap: _handleLogoTap,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Image.asset(
                              'assets/img1.png',
                              width: 100,
                              height: 100,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.sports_tennis,
                                    size: 70, color: Colors.black87);
                              },
                            ),
                          ),
                        ),
                      ),
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: const Text(
                          'Selecciona una sede',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                            letterSpacing: 0.3,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Text(
                          'Para comenzar tu reserva',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 50),
                      ScaleTransition(
                        scale: _buttonScales[0],
                        child: Hero(
                          tag: "sede_1",
                          child: _buildSedeCard(
                            context,
                            title: 'Sede 1',
                            imagePath: 'assets/cancha2.jpg',
                            sede: 'Sede 1',
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      ScaleTransition(
                        scale: _buttonScales[1],
                        child: Hero(
                          tag: "sede_2",
                          child: _buildSedeCard(
                            context,
                            title: 'Sede 2',
                            imagePath: 'assets/cancha4.jpg',
                            sede: 'Sede 2',
                          ),
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
  }

  Widget _buildSedeCard(
    BuildContext context, {
    required String title,
    required String imagePath,
    required String sede,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 30),
      builder: (context, value, child) {
        return Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15 * value),
                blurRadius: 10 * value,
                offset: Offset(0, 5 * value),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _seleccionarSede(context, sede),
              borderRadius: BorderRadius.circular(14),
              splashColor: Colors.white.withOpacity(0.1),
              highlightColor: Colors.white.withOpacity(0.05),
              child: MouseRegion(
                onEnter: (_) => setState(() {}),
                onExit: (_) => setState(() {}),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    image: DecorationImage(
                      image: AssetImage(imagePath),
                      fit: BoxFit.cover,
                      onError: (exception, stackTrace) {
                        debugPrint('Error cargando imagen de sede: $exception');
                      },
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.15),
                          Colors.black.withOpacity(0.5),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 3,
                                      color: Colors.black38,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.arrow_forward_ios,
                                  color: Colors.white,
                                  size: 14,
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
            ),
          ),
        );
      },
    );
  }
}

class MinimalistPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.04)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.15, size.height * 0.2, size.width * 0.25,
            size.height * 0.15),
        const Radius.circular(20),
      ))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.7, size.height * 0.3, size.width * 0.4,
            size.height * 0.2),
        const Radius.circular(20),
      ))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.1, size.height * 0.75, size.width * 0.3,
            size.height * 0.1),
        const Radius.circular(20),
      ))
      ..addOval(Rect.fromCircle(
        center: Offset(size.width * 0.8, size.height * 0.8),
        radius: size.width * 0.15,
      ));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
