import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/providers/auth_provider.dart' as auth_provider;
import 'package:reserva_canchas/widgets/payment_lock_overlay.dart';
import 'package:reserva_canchas/screens/admin/registro/EncargadoRegistroReservasScreen.dart';
import 'package:reserva_canchas/screens/admin/reservas%20a%20confirmar/reservas_pendientes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:reserva_canchas/services/lugar_helper.dart';
import 'package:reserva_canchas/services/push_notification_service.dart';
import '../ciudad_screen.dart';

class EncargadoDashboardScreen extends StatefulWidget {
  const EncargadoDashboardScreen({super.key});

  @override
  EncargadoDashboardScreenState createState() => EncargadoDashboardScreenState();
}

class EncargadoDashboardScreenState extends State<EncargadoDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _sidebarController;
  late AnimationController _badgeController;
  Stream<QuerySnapshot>? _reservasPendientesStream;

  // Control del sidebar
  bool _isSidebarCollapsed = false;
  bool _isMobileMenuOpen = false; // Para controlar el menú móvil
  String _currentSection = 'Reservas Pendientes';
  Widget _currentContent = const Confirmar();

  // Paleta de colores mejorada
  final Color _secondaryColor = const Color(0xFF6366F1);
  final Color _accentColor = const Color(0xFF8B5CF6);
  final Color _backgroundColor = const Color(0xFFF8FAFC);
  final Color _cardColor = Colors.white;
  final Color _surfaceColor = const Color(0xFFF1F5F9);
  final Color _textPrimary = const Color(0xFF0F172A);
  final Color _textSecondary = const Color(0xFF64748B);
  final Color _borderColor = const Color(0xFFE2E8F0);
  final Color _sidebarColor = const Color(0xFF1E293B);

  // Configuraciones de las secciones - SOLO RESERVAS PENDIENTES Y REGISTRO
  final List<Map<String, dynamic>> _sections = [
    {
      'icon': Icons.pending_actions_rounded,
      'title': 'Reservas Pendientes',
      'screen': const Confirmar(),
      'hasNotification': true,
    },
    {
      'icon': Icons.book_rounded,
      'title': 'Registro',
      'screen': const EncargadoRegistroReservasScreen(),
      'hasNotification': false,
    },
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _sidebarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _initPendingReservationsStream();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeController.forward();
      _registerAdminTokenForAuditNotifications();
      // En web el AuthProvider puede cargar lugarId después; re-registrar token cuando ya esté disponible.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _registerAdminTokenForAuditNotifications();
      });
    });
  }

  Future<void> _registerAdminTokenForAuditNotifications() async {
    final auth = Provider.of<auth_provider.AuthProvider>(context, listen: false);
    var ciudadId = auth.currentCiudadId;
    final lugarId = auth.currentLugarId;
    if ((ciudadId == null || ciudadId.isEmpty) && lugarId != null && lugarId.isNotEmpty) {
      try {
        final lugarDoc = await FirebaseFirestore.instance
            .collection('lugares')
            .doc(lugarId)
            .get();
        if (lugarDoc.exists && lugarDoc.data() != null) {
          ciudadId = lugarDoc.data()!['ciudadId'] as String?;
        }
      } catch (e) {
        debugPrint('PushNotificationService: no se pudo obtener ciudadId del lugar: $e');
      }
    }
    if (ciudadId != null && ciudadId.isNotEmpty) {
      await PushNotificationService().updateCiudadForNotifications(
        ciudadId,
        lugarId: lugarId,
      );
    }
  }

  Future<void> _initPendingReservationsStream() async {
    try {
      final lugarId = await LugarHelper.getLugarId();
      setState(() {
        _reservasPendientesStream = FirebaseFirestore.instance
            .collection('reservas')
            .where('confirmada', isEqualTo: false)
            .where('lugarId', isEqualTo: lugarId)
            .snapshots();
      });
    } catch (e) {
      setState(() { _reservasPendientesStream = const Stream.empty(); });
    }
  }

  Widget _buildPendingBadge({required Widget Function(int count) builder}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _reservasPendientesStream ?? const Stream.empty(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        if (count <= 0) return const SizedBox.shrink();
        return builder(count);
      },
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _sidebarController.dispose();
    _badgeController.dispose();
    super.dispose();
  }

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width <= 768;
  }


  void _toggleSidebar() {
    setState(() {
      if (_isMobile(context)) {
        _isMobileMenuOpen = !_isMobileMenuOpen;
      } else {
        _isSidebarCollapsed = !_isSidebarCollapsed;
        if (_isSidebarCollapsed) {
          _sidebarController.forward();
        } else {
          _sidebarController.reverse();
        }
      }
    });
  }

  void _navigateToSection(String title, Widget screen) {
    setState(() {
      _currentSection = title;
      _currentContent = screen;
      // En móvil, cerrar el menú después de navegar
      if (_isMobile(context)) {
        _isMobileMenuOpen = false;
      }
    });
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se puede cambiar la contraseña sin sesión activa'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar mi contraseña'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentController,
                decoration: const InputDecoration(
                  labelText: 'Contraseña actual',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newController,
                decoration: const InputDecoration(
                  labelText: 'Nueva contraseña',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                decoration: const InputDecoration(
                  labelText: 'Confirmar nueva contraseña',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final current = currentController.text;
              final newP = newController.text;
              final confirm = confirmController.text;
              if (current.isEmpty || newP.isEmpty || confirm.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Completa todos los campos'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              if (newP != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('La nueva contraseña no coincide'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              if (newP.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('La contraseña debe tener al menos 6 caracteres'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              try {
                final cred = EmailAuthProvider.credential(
                  email: user.email!,
                  password: current,
                );
                await user.reauthenticateWithCredential(cred);
                await user.updatePassword(newP);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contraseña actualizada correctamente'),
                    backgroundColor: Colors.green,
                  ),
                );
              } on FirebaseAuthException catch (e) {
                if (!ctx.mounted) return;
                String msg = 'Error al cambiar contraseña';
                if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
                  msg = 'Contraseña actual incorrecta';
                } else if (e.code == 'weak-password') {
                  msg = 'La nueva contraseña es muy débil';
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg), backgroundColor: Colors.red),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _secondaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cambiar contraseña'),
          ),
        ],
      ),
    );
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
              Flexible(
                child: Text(
                  'Cerrar Sesión',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                    fontSize: 18,
                  ),
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
      final authProvider = Provider.of<auth_provider.AuthProvider>(context, listen: false);
      await authProvider.signOut();
      
      if (mounted) {
        Navigator.of(context).pop();
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const CiudadScreen()),
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
    final isMobile = _isMobile(context);
    final isDesktop = screenSize.width > 1024;
    final user = FirebaseAuth.instance.currentUser;

    if (isMobile) {
      return PaymentLockOverlay(
        child: _buildMobileLayout(context, user),
      );
    } else {
      return PaymentLockOverlay(
        child: _buildDesktopLayout(context, user, isDesktop),
      );
    }
  }

  Future<void> _showEditNameDialog(BuildContext context) async {
    final authProvider = Provider.of<auth_provider.AuthProvider>(context, listen: false);
    final user = FirebaseAuth.instance.currentUser;
    final fallback = user?.email ?? 'Encargado';
    final currentName = authProvider.userName ?? fallback;

    final controller = TextEditingController(text: currentName);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Editar nombre'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Nombre para mostrar',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('El nombre no puede estar vacío'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                final ok = await authProvider.updateUserName(newName);
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nombre actualizado correctamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No se pudo actualizar el nombre'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMobileLayout(BuildContext context, User? user) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: _buildMobileAppBar(context, user),
      drawer: _buildMobileDrawer(context, user),
      body: Container(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: Container(
            decoration: BoxDecoration(
              color: _cardColor,
            ),
            child: _currentContent,
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildMobileAppBar(BuildContext context, User? user) {
    return AppBar(
      backgroundColor: _sidebarColor,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: Builder(
        builder: (context) => IconButton(
          icon: Icon(Icons.menu_rounded),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _currentSection,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Badge de notificaciones para móvil
          _buildPendingBadge(
            builder: (notificationCount) => Container(
                margin: const EdgeInsets.only(left: 8),
                child: AnimatedBuilder(
                  animation: _badgeController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1.0 + (_badgeController.value * 0.1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.red.shade500, Colors.red.shade600],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.shade500.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          notificationCount > 99 ? '99+' : '$notificationCount',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ),
        ],
      ),
      systemOverlayStyle: SystemUiOverlayStyle.light,
    );
  }

  Widget _buildMobileDrawer(BuildContext context, User? user) {
    return Drawer(
      backgroundColor: _sidebarColor,
      child: SafeArea(
        child: Column(
          children: [
            // Header del drawer móvil
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_secondaryColor, _accentColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _secondaryColor.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Panel de Administración',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (user?.email != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      user!.email!,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              color: Colors.white.withValues(alpha: 0.1),
            ),

            // Menú de navegación móvil
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: _sections.length,
                itemBuilder: (context, index) {
                  final section = _sections[index];
                  final isSelected = _currentSection == section['title'];
                  
                  if (section['hasNotification'] == true) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: _reservasPendientesStream ?? const Stream.empty(),
                      builder: (context, snapshot) {
                        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                        return _buildMobileDrawerItem(
                          icon: section['icon'],
                          title: section['title'],
                          isSelected: isSelected,
                          notificationCount: count > 0 ? count : null,
                          onTap: () {
                            _navigateToSection(section['title'], section['screen']);
                            Navigator.of(context).pop(); // Cerrar drawer
                          },
                        );
                      },
                    );
                  }
                  
                  return _buildMobileDrawerItem(
                    icon: section['icon'],
                    title: section['title'],
                    isSelected: isSelected,
                    onTap: () {
                      _navigateToSection(section['title'], section['screen']);
                      Navigator.of(context).pop(); // Cerrar drawer
                    },
                  );
                },
              ),
            ),

            // Footer del drawer móvil
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showChangePasswordDialog(context);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.lock_reset_rounded, size: 20),
                      label: const Text('Cambiar contraseña'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showLogoutConfirmation(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(Icons.logout_rounded, size: 20),
                      label: Text(
                        'Cerrar Sesión',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDrawerItem({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    int? notificationCount,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: ListTile(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        tileColor: isSelected 
            ? _secondaryColor.withValues(alpha: 0.2)
            : null,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSelected 
                ? _secondaryColor.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: isSelected ? _secondaryColor : Colors.white.withValues(alpha: 0.8),
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected 
                ? Colors.white
                : Colors.white.withValues(alpha: 0.9),
            fontSize: 15,
          ),
        ),
        trailing: notificationCount != null && notificationCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade500, Colors.red.shade600],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  notificationCount > 99 ? '99+' : '$notificationCount',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, User? user, bool isDesktop) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Row(
        children: [
          // Sidebar para desktop
          _buildSidebar(context, user, isDesktop),
          
          // Contenido principal
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context, user),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _borderColor,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: _currentContent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, User? user, bool isDesktop) {
    final sidebarWidth = _isSidebarCollapsed ? 80.0 : 280.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      width: sidebarWidth,
      child: Container(
        decoration: BoxDecoration(
          color: _sidebarColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(2, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header del sidebar
            _buildSidebarHeader(user),
            
            // Divisor
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.white.withValues(alpha: 0.1),
            ),
            
            // Menú de navegación
            Expanded(
              child: _buildSidebarMenu(),
            ),
            
            // Footer del sidebar
            _buildSidebarFooter(context),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 600.ms).slideX(begin: -1.0, duration: 600.ms);
  }

  Widget _buildSidebarHeader(User? user) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Logo/Icono
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _isSidebarCollapsed ? 40 : 60,
            height: _isSidebarCollapsed ? 40 : 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_secondaryColor, _accentColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _secondaryColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: _isSidebarCollapsed ? 20 : 28,
            ),
          ),
          
          if (!_isSidebarCollapsed) ...[
            const SizedBox(height: 16),
            Consumer<auth_provider.AuthProvider>(
              builder: (context, authProvider, _) {
                final name = authProvider.userName ?? 'Encargado';
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => _showEditNameDialog(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          size: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (user?.email != null) ...[
              const SizedBox(height: 4),
              Text(
                user!.email!,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSidebarMenu() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _sections.length,
      itemBuilder: (context, index) {
        final section = _sections[index];
        final isSelected = _currentSection == section['title'];
        
        if (section['hasNotification'] == true) {
          return StreamBuilder<QuerySnapshot>(
            stream: _reservasPendientesStream ?? const Stream.empty(),
            builder: (context, snapshot) {
              final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
              return _buildSidebarMenuItem(
                icon: section['icon'],
                title: section['title'],
                isSelected: isSelected,
                notificationCount: count > 0 ? count : null,
                onTap: () => _navigateToSection(section['title'], section['screen']),
              );
            },
          );
        }
        
        return _buildSidebarMenuItem(
          icon: section['icon'],
          title: section['title'],
          isSelected: isSelected,
          onTap: () => _navigateToSection(section['title'], section['screen']),
        );
      },
    );
  }

  Widget _buildSidebarMenuItem({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    int? notificationCount,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: _isSidebarCollapsed ? 0 : 16, 
              vertical: 12
            ),
            decoration: BoxDecoration(
              color: isSelected 
                  ? _secondaryColor.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected 
                    ? _secondaryColor.withValues(alpha: 0.3)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: _isSidebarCollapsed 
                ? _buildCollapsedMenuItem(icon, isSelected, notificationCount)
                : _buildExpandedMenuItem(icon, title, isSelected, notificationCount),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedMenuItem(IconData icon, bool isSelected, int? notificationCount) {
    return SizedBox(
      width: 56,
      child: Stack(
        children: [
          // Icono centrado
          Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected 
                    ? _secondaryColor.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? _secondaryColor : Colors.white.withValues(alpha: 0.8),
                size: 18,
              ),
            ),
          ),
          
          // Badge de notificación posicionado absolutamente
          if (notificationCount != null && notificationCount > 0)
            Positioned(
              right: 8,
              top: 0,
              child: AnimatedBuilder(
                animation: _badgeController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + (_badgeController.value * 0.1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade500, Colors.red.shade600],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.shade500.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Center(
                        child: Text(
                          notificationCount > 9 ? '9+' : '$notificationCount',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
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

  Widget _buildExpandedMenuItem(IconData icon, String title, bool isSelected, int? notificationCount) {
    return Row(
      children: [
        // Icono
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isSelected 
                ? _secondaryColor.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: isSelected ? _secondaryColor : Colors.white.withValues(alpha: 0.8),
            size: 18,
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Título
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected 
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        
        // Badge de notificación
        if (notificationCount != null && notificationCount > 0)
          AnimatedBuilder(
            animation: _badgeController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_badgeController.value * 0.1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade500, Colors.red.shade600],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.shade500.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(minWidth: 20),
                  child: Center(
                    child: Text(
                      notificationCount > 99 ? '99+' : '$notificationCount',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSidebarFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showChangePasswordDialog(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: _isSidebarCollapsed ? 0 : 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _secondaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _secondaryColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: _isSidebarCollapsed
                    ? const SizedBox(
                        width: 56,
                        child: Center(
                          child: Icon(
                            Icons.lock_reset_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Icon(
                            Icons.lock_reset_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Cambiar contraseña',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showLogoutConfirmation(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: _isSidebarCollapsed ? 0 : 16, 
                  vertical: 12
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.red.shade700.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: _isSidebarCollapsed 
                    ? SizedBox(
                        width: 56,
                        child: Center(
                          child: Icon(
                            Icons.logout_rounded,
                            color: Colors.red.shade400,
                            size: 18,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            color: Colors.red.shade400,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Cerrar Sesión',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                              color: Colors.red.shade400,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, User? user) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border(
          bottom: BorderSide(
            color: _borderColor,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            // Botón para toggle del sidebar
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggleSidebar,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    _isSidebarCollapsed ? Icons.menu_rounded : Icons.menu_open_rounded,
                    color: _textSecondary,
                    size: 24,
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Título de la sección actual
            Text(
              _currentSection,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: _textPrimary,
                fontSize: 18,
              ),
            ),
            
            const Spacer(),
            
            // Información del usuario (opcional)
            if (user?.email != null)
              Consumer<auth_provider.AuthProvider>(
                builder: (context, authProvider, _) {
                  final name = authProvider.userName ?? 'Encargado';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _borderColor,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_secondaryColor, _accentColor],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              user!.email!.substring(0, 1).toUpperCase(),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    color: _textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => _showEditNameDialog(context),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: _surfaceColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.edit_rounded,
                                      size: 14,
                                      color: _textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.email!,
                              style: GoogleFonts.inter(
                                color: _textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}