import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:reserva_canchas/screens/admin/encargado_dashboard.dart';
import 'package:reserva_canchas/screens/admin/super_admin_dashboard.dart';
import 'admin_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  
  late AnimationController _animationController;
  late AnimationController _shakeController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    ));
    
    _slideAnimation = Tween<double>(
      begin: 50.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.2, 1.0, curve: Curves.elasticOut),
    ));
    
    _shakeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticInOut,
    ));
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _shakeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      _shakeController.forward().then((_) => _shakeController.reset());
      HapticFeedback.lightImpact();
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final uid = userCredential.user!.uid;

      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();

      if (!doc.exists) {
        throw Exception("No se encontró información de usuario en Firestore.");
      }

      final rol = doc.data()!['rol'];

      if (!mounted) return;

      HapticFeedback.mediumImpact();

      // Navegación actualizada según el rol
      if (rol == 'superadmin') {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const SuperAdminDashboardScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOutCubic,
                )),
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else if (rol == 'admin') {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const AdminDashboardScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOutCubic,
                )),
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else if (rol == 'encargado') {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) =>
                const EncargadoDashboardScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOutCubic,
                )),
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else {
        _showErrorSnackBar("Rol no autorizado");
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String errorMessage = "Error al iniciar sesión";
      if (e.code == 'user-not-found') {
        errorMessage = "Usuario no encontrado";
      } else if (e.code == 'wrong-password') {
        errorMessage = "Contraseña incorrecta";
      } else if (e.code == 'invalid-email') {
        errorMessage = "Formato de correo inválido";
      } else if (e.code == 'user-disabled') {
        errorMessage = "Esta cuenta ha sido deshabilitada";
      }
      
      _shakeController.forward().then((_) => _shakeController.reset());
      _showErrorSnackBar(errorMessage);
    } catch (e) {
      if (!mounted) return;
      _shakeController.forward().then((_) => _shakeController.reset());
      _showErrorSnackBar("Error: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFE53E3E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'El correo es requerido';
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
      return 'Formato de correo inválido';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'La contraseña es requerida';
    }
    if (value.length < 6) {
      return 'Mínimo 6 caracteres';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 700;
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: Color(0xFF2D3748),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
          splashRadius: 24,
          tooltip: 'Volver a sedes',
        ),
        title: const Text(
          'Acceso Administrativo',
          style: TextStyle(
            color: Color(0xFF2D3748),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF7FAFC),
              Color(0xFFEDF2F7),
              Color(0xFFE2E8F0),
            ],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _fadeAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.translate(
                  offset: Offset(0, _slideAnimation.value),
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24.0,
                          vertical: isSmallScreen ? 16.0 : 32.0,
                        ),
                        child: AnimatedBuilder(
                          animation: _shakeAnimation,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(
                                _shakeAnimation.value * 
                                10 * 
                                (1 - _shakeAnimation.value).abs(),
                                0,
                              ),
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 400),
                                child: Card(
                                  elevation: 20,
                                  shadowColor: Colors.black.withValues(alpha: 0.1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(24),
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.white,
                                          Color(0xFFFAFAFA),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        width: 1,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.all(isSmallScreen ? 24.0 : 32.0),
                                      child: Form(
                                        key: _formKey,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Logo mejorado con imagen
                                            Container(
                                              width: isSmallScreen ? 80 : 100,
                                              height: isSmallScreen ? 80 : 100,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(20),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: 0.1),
                                                    blurRadius: 20,
                                                    offset: const Offset(0, 10),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(20),
                                                child: Image.asset(
                                                  'assets/img1.png',
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return Container(
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          colors: [
                                                            Theme.of(context).primaryColor,
                                                            Theme.of(context).primaryColor.withValues(alpha: 0.8),
                                                          ],
                                                        ),
                                                        borderRadius: BorderRadius.circular(20),
                                                      ),
                                                      child: Icon(
                                                        Icons.sports_soccer,
                                                        size: isSmallScreen ? 40 : 50,
                                                        color: Colors.white,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                            
                                            SizedBox(height: isSmallScreen ? 20 : 28),
                                            
                                            // Título mejorado
                                            const Text(
                                              "Reserva de Canchas",
                                              style: TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF2D3748),
                                                letterSpacing: -0.5,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              "Ingresa tus credenciales para continuar",
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: const Color(0xFF718096),
                                                fontWeight: FontWeight.w500,
                                                height: 1.4,
                                              ),
                                            ),
                                            
                                            SizedBox(height: isSmallScreen ? 28 : 36),
                                            
                                            // Campo de correo mejorado
                                            TextFormField(
                                              controller: _emailController,
                                              validator: _validateEmail,
                                              decoration: InputDecoration(
                                                labelText: "Correo electrónico",
                                                hintText: "ejemplo@correo.com",
                                                prefixIcon: Container(
                                                  margin: const EdgeInsets.all(12),
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF4299E1).withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Icon(
                                                    Icons.email_outlined,
                                                    color: Color(0xFF4299E1),
                                                    size: 20,
                                                  ),
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFE2E8F0),
                                                    width: 1.5,
                                                  ),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFE2E8F0),
                                                    width: 1.5,
                                                  ),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFF4299E1),
                                                    width: 2,
                                                  ),
                                                ),
                                                errorBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFE53E3E),
                                                    width: 1.5,
                                                  ),
                                                ),
                                                filled: true,
                                                fillColor: const Color(0xFFF7FAFC),
                                                labelStyle: const TextStyle(
                                                  color: Color(0xFF718096),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                hintStyle: TextStyle(
                                                  color: const Color(0xFF718096).withValues(alpha: 0.7),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(
                                                  horizontal: 20,
                                                  vertical: 16,
                                                ),
                                              ),
                                              keyboardType: TextInputType.emailAddress,
                                              textInputAction: TextInputAction.next,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFF2D3748),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            
                                            const SizedBox(height: 20),
                                            
                                            // Campo de contraseña mejorado
                                            TextFormField(
                                              controller: _passwordController,
                                              validator: _validatePassword,
                                              decoration: InputDecoration(
                                                labelText: "Contraseña",
                                                hintText: "Ingresa tu contraseña",
                                                prefixIcon: Container(
                                                  margin: const EdgeInsets.all(12),
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF9F7AEA).withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Icon(
                                                    Icons.lock_outline,
                                                    color: Color(0xFF9F7AEA),
                                                    size: 20,
                                                  ),
                                                ),
                                                suffixIcon: IconButton(
                                                  icon: Container(
                                                    padding: const EdgeInsets.all(8),
                                                    child: Icon(
                                                      _obscurePassword
                                                          ? Icons.visibility_off_outlined
                                                          : Icons.visibility_outlined,
                                                      color: const Color(0xFF718096),
                                                      size: 20,
                                                    ),
                                                  ),
                                                  onPressed: () {
                                                    setState(() {
                                                      _obscurePassword = !_obscurePassword;
                                                    });
                                                    HapticFeedback.selectionClick();
                                                  },
                                                  splashRadius: 20,
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFE2E8F0),
                                                    width: 1.5,
                                                  ),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFE2E8F0),
                                                    width: 1.5,
                                                  ),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFF9F7AEA),
                                                    width: 2,
                                                  ),
                                                ),
                                                errorBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFE53E3E),
                                                    width: 1.5,
                                                  ),
                                                ),
                                                filled: true,
                                                fillColor: const Color(0xFFF7FAFC),
                                                labelStyle: const TextStyle(
                                                  color: Color(0xFF718096),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                hintStyle: TextStyle(
                                                  color: const Color(0xFF718096).withValues(alpha: 0.7),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(
                                                  horizontal: 20,
                                                  vertical: 16,
                                                ),
                                              ),
                                              obscureText: _obscurePassword,
                                              textInputAction: TextInputAction.done,
                                              onFieldSubmitted: (_) => _login(),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFF2D3748),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            
                                            const SizedBox(height: 16),
                                            
                                            // Checkbox "Recordarme" funcional
                                            Row(
                                              children: [
                                                Transform.scale(
                                                  scale: 1.1,
                                                  child: Checkbox(
                                                    value: _rememberMe,
                                                    onChanged: (value) {
                                                      setState(() {
                                                        _rememberMe = value ?? false;
                                                      });
                                                      HapticFeedback.selectionClick();
                                                    },
                                                    activeColor: const Color(0xFF4299E1),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                const Text(
                                                  "Recordar sesión",
                                                  style: TextStyle(
                                                    color: Color(0xFF718096),
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            
                                            SizedBox(height: isSmallScreen ? 24 : 32),
                                            
                                            // Botón de login mejorado
                                            SizedBox(
                                              width: double.infinity,
                                              height: 56,
                                              child: ElevatedButton(
                                                onPressed: _isLoading ? null : _login,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF4299E1),
                                                  foregroundColor: Colors.white,
                                                  disabledBackgroundColor: const Color(0xFFCBD5E0),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  elevation: 0,
                                                  shadowColor: Colors.transparent,
                                                ).copyWith(
                                                  overlayColor: WidgetStateProperty.all(
                                                    Colors.white.withValues(alpha: 0.2),
                                                  ),
                                                ),
                                                child: _isLoading
                                                    ? Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          SizedBox(
                                                            width: 20,
                                                            height: 20,
                                                            child: CircularProgressIndicator(
                                                              color: Colors.white,
                                                              strokeWidth: 2.5,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 12),
                                                          const Text(
                                                            "INICIANDO...",
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.w600,
                                                              letterSpacing: 0.5,
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                    : Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          const Icon(
                                                            Icons.login_rounded,
                                                            size: 20,
                                                          ),
                                                          const SizedBox(width: 8),
                                                          const Text(
                                                            "INGRESAR",
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.w600,
                                                              letterSpacing: 0.5,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                            ),
                                            
                                            SizedBox(height: isSmallScreen ? 16 : 24),
                                            
                                            // Indicador de seguridad
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 12,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF48BB78).withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: const Color(0xFF48BB78).withValues(alpha: 0.2),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.security_rounded,
                                                    color: const Color(0xFF48BB78),
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    "Conexión segura protegida",
                                                    style: TextStyle(
                                                      color: const Color(0xFF48BB78),
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                    ),
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
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}