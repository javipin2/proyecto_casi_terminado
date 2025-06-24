import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'clientes/clientes_screen.dart';
import 'canchas/canchas_screen.dart';
import 'graficas/graficas_screen.dart';
import 'reservas/admin_reservas_horarios_screen.dart';
import 'registro/admin_registro_reservas_screen.dart';
import '../sede_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  AdminDashboardScreenState createState() => AdminDashboardScreenState();
}

class AdminDashboardScreenState extends State<AdminDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;

  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _logout(BuildContext context) async {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const SedeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Error al cerrar sesión: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 1200;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Panel de Administración',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: _primaryColor,
          ),
        ),
        backgroundColor: _backgroundColor,
        elevation: 0,
        // Eliminamos el botón de retroceso automático
        automaticallyImplyLeading: false,
        actions: [
          Tooltip(
            message: 'Cerrar sesión',
            child: IconButton(
              icon: Icon(Icons.exit_to_app, color: _secondaryColor),
              onPressed: () => _logout(context),
            ),
          ),
        ],
      ),
      // Solo mostramos el drawer en móvil/tablet
      drawer: isDesktop ? null : _buildDrawer(context, user),
      body: Row(
        children: [
          // No mostramos NavigationRail en desktop para este dashboard
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 1200
                      ? 3
                      : constraints.maxWidth > 600
                          ? 2
                          : 1;
                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.2,
                    children: [
                      // Eliminamos la card de "Inicio"
                      _buildAdminCard(
                        icon: Icons.people,
                        title: 'Clientes',
                        description:
                            'Consulta y gestiona clientes registrados.',
                        color: Colors.blue,
                        context: context,
                        screen: const ClientesScreen(),
                      ),
                      _buildAdminCard(
                        icon: Icons.business,
                        title: 'Sedes y Canchas',
                        description: 'Administra sedes y asigna canchas.',
                        color: Colors.orange,
                        context: context,
                        screen: const CanchasScreen(),
                      ),
                      _buildAdminCard(
                        icon: Icons.bar_chart,
                        title: 'Gráficas',
                        description: 'Análisis y conteo de tu negocio.',
                        color: Colors.red,
                        context: context,
                        screen: const GraficasScreen(),
                      ),
                      _buildAdminCard(
                        icon: Icons.schedule,
                        title: 'Reservas',
                        description: 'Gestiona horarios disponibles.',
                        color: Colors.green,
                        context: context,
                        screen: const AdminReservasScreen(),
                      ),
                      _buildAdminCard(
                        icon: Icons.book,
                        title: 'Registro de Reservas',
                        description: 'Consulta el historial de reservas.',
                        color: Colors.teal,
                        context: context,
                        screen: const AdminRegistroReservasScreen(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, User? user) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(
              'Administrador',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            accountEmail: Text(
              user?.email ?? 'No autenticado',
              style: GoogleFonts.montserrat(color: Colors.white70),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: _secondaryColor,
              child: Text(
                user?.email?.substring(0, 1).toUpperCase() ?? 'A',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_secondaryColor, _primaryColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          _buildDrawerItem(
            icon: Icons.dashboard,
            title: 'Dashboard',
            onTap: () {
              Navigator.pop(context);
              // Ya estamos en el dashboard, no necesitamos navegar
            },
          ),
          _buildDrawerItem(
            icon: Icons.people,
            title: 'Clientes',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ClientesScreen()),
              );
            },
          ),
          _buildDrawerItem(
            icon: Icons.business,
            title: 'Sedes y Canchas',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CanchasScreen()),
              );
            },
          ),
          _buildDrawerItem(
            icon: Icons.bar_chart,
            title: 'Gráficas',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GraficasScreen()),
              );
            },
          ),
          _buildDrawerItem(
            icon: Icons.schedule,
            title: 'Reservas',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const AdminReservasScreen()),
              );
            },
          ),
          _buildDrawerItem(
            icon: Icons.book,
            title: 'Registro de Reservas',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const AdminRegistroReservasScreen()),
              );
            },
          ),
          const Divider(),
          _buildDrawerItem(
            icon: Icons.exit_to_app,
            title: 'Cerrar Sesión',
            onTap: () {
              Navigator.pop(context);
              _logout(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Animate(
      effects: [
        FadeEffect(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutQuad,
        ),
        SlideEffect(
          begin: const Offset(0.2, 0),
          end: Offset.zero,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutQuad,
        ),
      ],
      child: ListTile(
        leading: Icon(icon, color: _secondaryColor),
        title: Text(
          title,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w500,
            color: _primaryColor,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildAdminCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required BuildContext context,
    required Widget screen,
  }) {
    return Animate(
      effects: [
        FadeEffect(
          duration: const Duration(milliseconds: 600),
          delay: const Duration(milliseconds: 200),
          curve: Curves.easeOutQuad,
        ),
        ScaleEffect(
          begin: const Offset(0.95, 0.95),
          end: const Offset(1.0, 1.0),
          duration: const Duration(milliseconds: 600),
          delay: const Duration(milliseconds: 200),
          curve: Curves.easeOutQuad,
        ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Card(
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _cardColor, width: 1),
          ),
          color: _cardColor,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      screen,
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0);
                    const end = Offset.zero;
                    const curve = Curves.easeInOutCubic;
                    var tween = Tween(begin: begin, end: end)
                        .chain(CurveTween(curve: curve));
                    return SlideTransition(
                      position: animation.drive(tween),
                      child: child,
                    );
                  },
                  transitionDuration: const Duration(milliseconds: 400),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: MediaQuery.of(context).size.width > 600 ? 60 : 50,
                    color: color,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: GoogleFonts.montserrat(
                      fontSize:
                          MediaQuery.of(context).size.width > 600 ? 20 : 18,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: GoogleFonts.montserrat(
                      fontSize:
                          MediaQuery.of(context).size.width > 600 ? 15 : 14,
                      color: Color.fromRGBO(60, 64, 67, 0.8),
                    ),
                    textAlign: TextAlign.center,
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
