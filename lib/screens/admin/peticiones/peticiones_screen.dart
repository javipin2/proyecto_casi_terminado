// lib/screens/admin/peticiones_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:reserva_canchas/models/peticion.dart';
import 'package:reserva_canchas/providers/peticion_provider.dart';
import 'package:reserva_canchas/screens/admin/auditoria/audit_screen.dart';
import '../../widgets/peticion_card.dart';

class PeticionesScreen extends StatefulWidget {
  const PeticionesScreen({super.key});

  @override
  PeticionesScreenState createState() => PeticionesScreenState();
}

class PeticionesScreenState extends State<PeticionesScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);
  bool _isLoading = false;
  bool _esSuperAdmin = false;
  bool _toggleLoading = false;
  late AnimationController _switchAnimationController;
  late Animation<double> _switchAnimation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _switchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _switchAnimation = CurvedAnimation(
      parent: _switchAnimationController,
      curve: Curves.easeInOut,
    );
    _verificarRolYCargarPeticiones();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _switchAnimationController.dispose();
    super.dispose();
  }

  Future<void> _verificarRolYCargarPeticiones() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
      
      // Verificar si es superadmin
      final esSuperAdmin = await peticionProvider.esSuperAdmin();
      setState(() {
        _esSuperAdmin = esSuperAdmin;
      });

      if (!esSuperAdmin) {
        // Si no es superadmin, mostrar mensaje y redirigir
        _mostrarError('No tienes permisos para acceder a esta sección.');
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      // Inicializar escucha en tiempo real del control total
      peticionProvider.iniciarEscuchaControlTotal();

      // Cargar peticiones y configuración de control
      await Future.wait([
        peticionProvider.cargarPeticiones(),
        peticionProvider.cargarConfiguracionControl(),
      ]);

      // Animar el switch según el estado actual
      if (peticionProvider.controlTotalActivado) {
        _switchAnimationController.forward();
      }

    } catch (e) {
      _mostrarError('Error al cargar peticiones: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refrescarPeticiones() async {
    try {
      final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
      await peticionProvider.cargarPeticiones();
    } catch (e) {
      _mostrarError('Error al refrescar peticiones: $e');
    }
  }

  Future<void> _alternarControlTotal() async {
    if (_toggleLoading) return; // Prevenir múltiples clicks

    setState(() {
      _toggleLoading = true;
    });

    try {
      final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
      final estadoAnterior = peticionProvider.controlTotalActivado;
      
      // Animar el switch inmediatamente para feedback visual
      if (estadoAnterior) {
        _switchAnimationController.reverse();
      } else {
        _switchAnimationController.forward();
      }

      await peticionProvider.alternarControlTotal();
      
      // El estado se actualizará automáticamente por el listener en tiempo real
      final estadoFinal = peticionProvider.controlTotalActivado;
      
      // Mostrar mensaje de éxito
      _mostrarExito(estadoFinal 
          ? '✅ Control total activado.\n\nLos administradores ahora pueden:\n• Hacer cambios directos sin peticiones\n• Modificar fechas, horarios y precios\n• Editar información completa de reservas'
          : '⚠️ Control total desactivado.\n\nLos administradores ahora deben:\n• Crear peticiones para cambios importantes\n• Esperar aprobación del superadministrador\n• Mantener registro de modificaciones');
          
    } catch (e) {
      // Revertir animación en caso de error
      final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
      if (peticionProvider.controlTotalActivado) {
        _switchAnimationController.forward();
      } else {
        _switchAnimationController.reverse();
      }
      
      if (mounted) {
        _mostrarError('Error al cambiar configuración: $e');
      }
    } finally {
      setState(() {
        _toggleLoading = false;
      });
    }
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: GoogleFonts.montserrat(color: Colors.white),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _mostrarExito(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: GoogleFonts.montserrat(color: Colors.white, fontSize: 13),
        ),
        backgroundColor: _secondaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;
    
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_secondaryColor),
              ),
              const SizedBox(height: 12),
              Text(
                'Cargando peticiones...',
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(
          'Gestión de Peticiones',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            fontSize: isWideScreen ? 18 : 16,
          ),
        ),
        automaticallyImplyLeading: false,
        backgroundColor: _backgroundColor,
        elevation: 0,
        foregroundColor: _primaryColor,
        toolbarHeight: isWideScreen ? 64 : 56,
        actions: [
          // Indicador de SuperAdmin
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade400, Colors.purple.shade600],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withAlpha((0.2 * 255).round()),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.admin_panel_settings,
                  color: Colors.white,
                  size: isWideScreen ? 16 : 14,
                ),
                const SizedBox(width: 3),
                Text(
                  'SUPER',
                  style: GoogleFonts.montserrat(
                    fontSize: isWideScreen ? 11 : 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // Botón de Auditoría
          Container(
            margin: const EdgeInsets.only(right: 6),
            child: IconButton(
              icon: Container(
                padding: EdgeInsets.all(isWideScreen ? 6 : 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade400, Colors.teal.shade600],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.analytics,
                  color: Colors.white,
                  size: isWideScreen ? 18 : 16,
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AuditScreen(),
                  ),
                );
              },
              tooltip: 'Ver Auditoría',
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.refresh, 
              color: _secondaryColor,
              size: isWideScreen ? 22 : 20,
            ),
            onPressed: _refrescarPeticiones,
            tooltip: 'Refrescar',
          ),
          SizedBox(width: isWideScreen ? 8 : 4),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(isWideScreen ? 48 : 44),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: isWideScreen ? 16 : 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: _secondaryColor,
                borderRadius: BorderRadius.circular(4),
              ),
              labelPadding: EdgeInsets.zero,
              tabs: [
                _buildCompactTab(Icons.pending_actions, 'Pendientes', isWideScreen),
                _buildCompactTab(Icons.check_circle, 'Aprobadas', isWideScreen),
                _buildCompactTab(Icons.cancel, 'Rechazadas', isWideScreen),
                _buildCompactTab(Icons.list_alt, 'Todas', isWideScreen),
              ],
              labelColor: Colors.white,
              unselectedLabelColor: _primaryColor.withAlpha((0.6 * 255).round()),
              indicatorColor: Colors.transparent,
            ),
          ),
        ),
      ),
      body: Consumer<PeticionProvider>(
        builder: (context, peticionProvider, child) {
          final estadisticas = peticionProvider.estadisticas;

          // Actualizar animación del switch cuando cambie el estado
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (peticionProvider.controlTotalActivado && !_switchAnimationController.isCompleted) {
              _switchAnimationController.forward();
            } else if (!peticionProvider.controlTotalActivado && _switchAnimationController.isCompleted) {
              _switchAnimationController.reverse();
            }
          });

          return Column(
            children: [
              // Card de Control Total - Solo visible para superadmin
              if (_esSuperAdmin) ...[
                _buildControlTotalCard(peticionProvider, isWideScreen),
                SizedBox(height: isWideScreen ? 8 : 4),
              ],
              
              // Card de estadísticas
              Container(
                margin: EdgeInsets.fromLTRB(
                  isWideScreen ? 16 : 8, 
                  isWideScreen ? 8 : 4, 
                  isWideScreen ? 16 : 8, 
                  isWideScreen ? 12 : 8,
                ),
                padding: EdgeInsets.all(isWideScreen ? 16 : 12),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.04 * 255).round()),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: isWideScreen 
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatCard('Total', estadisticas['total']?.toString() ?? '0', _primaryColor, Icons.all_inbox, isWideScreen),
                        _buildStatCard('Pendientes', estadisticas['pendientes']?.toString() ?? '0', Colors.orange, Icons.pending_actions, isWideScreen),
                        _buildStatCard('Aprobadas', estadisticas['aprobadas']?.toString() ?? '0', Colors.green, Icons.check_circle, isWideScreen),
                        _buildStatCard('Rechazadas', estadisticas['rechazadas']?.toString() ?? '0', Colors.red, Icons.cancel, isWideScreen),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCard('Total', estadisticas['total']?.toString() ?? '0', _primaryColor, Icons.all_inbox, isWideScreen),
                        _buildStatCard('Pendientes', estadisticas['pendientes']?.toString() ?? '0', Colors.orange, Icons.pending_actions, isWideScreen),
                        _buildStatCard('Aprobadas', estadisticas['aprobadas']?.toString() ?? '0', Colors.green, Icons.check_circle, isWideScreen),
                        _buildStatCard('Rechazadas', estadisticas['rechazadas']?.toString() ?? '0', Colors.red, Icons.cancel, isWideScreen),
                      ],
                    ),
              ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),
              
              // TabBarView
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPeticionesList(peticionProvider.peticionesPendientes, isWideScreen),
                    _buildPeticionesList(
                      peticionProvider.peticiones.where((p) => p.fueAprobada).toList(),
                      isWideScreen,
                    ),
                    _buildPeticionesList(
                      peticionProvider.peticiones.where((p) => p.fueRechazada).toList(),
                      isWideScreen,
                    ),
                    _buildPeticionesList(peticionProvider.peticiones, isWideScreen),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControlTotalCard(PeticionProvider peticionProvider, bool isWideScreen) {
    final controlActivado = peticionProvider.controlTotalActivado;
    
    return Container(
      margin: EdgeInsets.fromLTRB(
        isWideScreen ? 16 : 8, 
        isWideScreen ? 12 : 8, 
        isWideScreen ? 16 : 8, 
        0,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: controlActivado 
              ? [Colors.green.shade50, Colors.green.shade100]
              : [Colors.orange.shade50, Colors.orange.shade100],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: controlActivado ? Colors.green.shade300 : Colors.orange.shade300,
          width: 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.symmetric(
            horizontal: isWideScreen ? 16 : 12, 
            vertical: isWideScreen ? 8 : 6,
          ),
          childrenPadding: EdgeInsets.fromLTRB(
            isWideScreen ? 16 : 12, 
            0, 
            isWideScreen ? 16 : 12, 
            isWideScreen ? 12 : 10,
          ),
          leading: AnimatedBuilder(
            animation: _switchAnimation,
            builder: (context, child) {
              return Container(
                padding: EdgeInsets.all(isWideScreen ? 8 : 6),
                decoration: BoxDecoration(
                  color: Color.lerp(
                    Colors.orange.withAlpha((0.3 * 255).round()),
                    Colors.green.withAlpha((0.3 * 255).round()),
                    _switchAnimation.value,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  controlActivado ? Icons.admin_panel_settings : Icons.pending_actions,
                  color: Color.lerp(
                    Colors.orange.shade700,
                    Colors.green.shade700,
                    _switchAnimation.value,
                  ),
                  size: isWideScreen ? 20 : 18,
                ),
              );
            },
          ),
          title: Text(
            'Control Total',
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.w600,
              fontSize: isWideScreen ? 15 : 13,
              color: controlActivado ? Colors.green.shade800 : Colors.orange.shade800,
            ),
          ),
          subtitle: Text(
            controlActivado ? 'Cambios directos activos' : 'Requiere peticiones',
            style: GoogleFonts.montserrat(
              fontSize: isWideScreen ? 12 : 11,
              color: controlActivado ? Colors.green.shade600 : Colors.orange.shade600,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isWideScreen ? 8 : 6, 
                  vertical: isWideScreen ? 3 : 2,
                ),
                decoration: BoxDecoration(
                  color: controlActivado 
                      ? Colors.green.withAlpha((0.2 * 255).round())
                      : Colors.orange.withAlpha((0.2 * 255).round()),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  controlActivado ? 'ON' : 'OFF',
                  style: GoogleFonts.montserrat(
                    fontSize: isWideScreen ? 10 : 9,
                    fontWeight: FontWeight.w600,
                    color: controlActivado ? Colors.green.shade800 : Colors.orange.shade800,
                  ),
                ),
              ),
              SizedBox(width: isWideScreen ? 8 : 6),
              Icon(Icons.expand_more, size: isWideScreen ? 20 : 18),
            ],
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controlActivado 
                            ? 'Los administradores pueden realizar cambios inmediatos sin aprobación'
                            : 'Los administradores deben crear peticiones para cambios importantes',
                        style: GoogleFonts.montserrat(
                          fontSize: isWideScreen ? 12 : 11,
                          color: controlActivado ? Colors.green.shade700 : Colors.orange.shade700,
                        ),
                      ),
                      SizedBox(height: isWideScreen ? 10 : 8),
                      Row(
                        children: [
                          Icon(
                            controlActivado ? Icons.check_circle : Icons.warning,
                            size: isWideScreen ? 14 : 12,
                            color: controlActivado ? Colors.green.shade600 : Colors.orange.shade600,
                          ),
                          SizedBox(width: isWideScreen ? 6 : 4),
                          Expanded(
                            child: Text(
                              controlActivado ? 'CAMBIOS INMEDIATOS' : 'REQUIERE APROBACIÓN',
                              style: GoogleFonts.montserrat(
                                fontSize: isWideScreen ? 10 : 9,
                                fontWeight: FontWeight.w600,
                                color: controlActivado ? Colors.green.shade700 : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: isWideScreen ? 16 : 12),
                if (_toggleLoading)
                  SizedBox(
                    width: isWideScreen ? 20 : 18,
                    height: isWideScreen ? 20 : 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        controlActivado ? Colors.green.shade600 : Colors.orange.shade600,
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _mostrarDialogoConfirmacionToggle(!controlActivado),
                    child: Container(
                      width: isWideScreen ? 44 : 40,
                      height: isWideScreen ? 24 : 22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(isWideScreen ? 12 : 11),
                        color: controlActivado ? Colors.green.shade400 : Colors.orange.shade300,
                      ),
                      child: Stack(
                        children: [
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            left: controlActivado ? (isWideScreen ? 22 : 20) : 2,
                            top: 2,
                            child: Container(
                              width: isWideScreen ? 20 : 18,
                              height: isWideScreen ? 20 : 18,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(isWideScreen ? 10 : 9),
                              ),
                              child: Icon(
                                controlActivado ? Icons.check : Icons.close,
                                size: isWideScreen ? 12 : 10,
                                color: controlActivado ? Colors.green.shade600 : Colors.orange.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.3, end: 0);
  }

  Widget _buildCompactTab(IconData icon, String label, bool isWideScreen) {
    return Tab(
      height: isWideScreen ? 40 : 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: isWideScreen ? 16 : 14),
          SizedBox(width: isWideScreen ? 4 : 3),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: isWideScreen ? 11 : 10,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoConfirmacionToggle(bool nuevoValor) async {
    final colorBoton = nuevoValor ? Colors.orange.shade600 : _secondaryColor;
    final textoBoton = nuevoValor ? 'Activar Control' : 'Desactivar Control';

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: nuevoValor ? Colors.green.withAlpha((0.1 * 255).round()) : Colors.orange.withAlpha((0.1 * 255).round()),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                nuevoValor ? Icons.admin_panel_settings : Icons.pending_actions,
                color: nuevoValor ? Colors.green.shade600 : Colors.orange.shade600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                nuevoValor ? 'Activar Control Total' : 'Desactivar Control Total',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _primaryColor,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nuevoValor 
                    ? '¿Estás seguro que quieres dar control total a los administradores?'
                    : '¿Estás seguro que quieres requerir peticiones para los cambios?',
                style: GoogleFonts.montserrat(
                  fontSize: 14, 
                  color: _primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: nuevoValor ? Colors.orange.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: nuevoValor ? Colors.orange.shade200 : Colors.blue.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          nuevoValor ? Icons.warning : Icons.info,
                          color: nuevoValor ? Colors.orange.shade700 : Colors.blue.shade700,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            nuevoValor ? 'Esto permitirá que los administradores:' : 'Los administradores deberán:',
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: nuevoValor ? Colors.orange.shade800 : Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (nuevoValor) ...[
                      _buildListItem('Modifiquen reservas directamente sin aprobación', Icons.edit),
                      _buildListItem('Cambien fechas, horarios y precios instantáneamente', Icons.schedule),
                      _buildListItem('Accedan a todas las funciones de edición', Icons.admin_panel_settings),
                      _buildListItem('Realicen cambios críticos sin supervisión', Icons.warning, isWarning: true),
                    ] else ...[
                      _buildListItem('Crear peticiones para cambios importantes', Icons.request_page),
                      _buildListItem('Esperar aprobación del superadministrador', Icons.approval),
                      _buildListItem('Mantener un registro completo de cambios', Icons.history),
                      _buildListItem('Garantizar supervisión de modificaciones', Icons.security, isPositive: true),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.montserrat(
                color: _primaryColor,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorBoton,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              textoBoton,
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _alternarControlTotal();
    }
  }

  Widget _buildListItem(String text, IconData icon, {bool isWarning = false, bool isPositive = false}) {
    Color color = Colors.grey.shade700;
    if (isWarning) color = Colors.orange.shade700;
    if (isPositive) color = Colors.green.shade700;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: color,
                fontWeight: isWarning || isPositive ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon, bool isWideScreen) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(isWideScreen ? 10 : 8),
          decoration: BoxDecoration(
            color: color.withAlpha((0.1 * 255).round()),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withAlpha((0.3 * 255).round())),
          ),
          child: Icon(
            icon, 
            color: color, 
            size: isWideScreen ? 20 : 18,
          ),
        ),
        SizedBox(height: isWideScreen ? 6 : 4),
        Text(
          value,
          style: GoogleFonts.montserrat(
            fontSize: isWideScreen ? 18 : 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: GoogleFonts.montserrat(
            fontSize: isWideScreen ? 11 : 10,
            color: _primaryColor.withAlpha((0.7 * 255).round()),
          ),
        ),
      ],
    );
  }

  Widget _buildPeticionesList(List<Peticion> peticiones, bool isWideScreen) {
    if (peticiones.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: isWideScreen ? 64 : 56,
              color: _primaryColor.withAlpha((0.3 * 255).round()),
            ),
            SizedBox(height: isWideScreen ? 16 : 12),
            Text(
              'No hay peticiones',
              style: GoogleFonts.montserrat(
                fontSize: isWideScreen ? 18 : 16,
                color: _primaryColor.withAlpha((0.6 * 255).round()),
              ),
            ),
            SizedBox(height: isWideScreen ? 8 : 6),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isWideScreen ? 32 : 24),
              child: Text(
                'Las peticiones aparecerán aquí cuando los admins realicen cambios.',
                style: GoogleFonts.montserrat(
                  fontSize: isWideScreen ? 14 : 13,
                  color: _primaryColor.withAlpha((0.5 * 255).round()),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refrescarPeticiones,
      color: _secondaryColor,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: isWideScreen ? 16 : 8, 
          vertical: isWideScreen ? 8 : 4,
        ),
        itemCount: peticiones.length,
        itemBuilder: (context, index) {
          final peticion = peticiones[index];
          return Padding(
            padding: EdgeInsets.only(bottom: isWideScreen ? 8 : 6),
            child: PeticionCard(
              peticion: peticion,
              onAprobar: _esSuperAdmin ? () => _aprobarPeticion(peticion) : null,
              onRechazar: _esSuperAdmin ? () => _rechazarPeticion(peticion) : null,
            ).animate(delay: (index * 50).ms).fadeIn(duration: 400.ms).slideX(
                  begin: -0.1,
                  end: 0,
                  duration: 400.ms,
                  curve: Curves.easeOutQuad,
                ),
          );
        },
      ),
    );
  }

  Future<void> _aprobarPeticion(Peticion peticion) async {
    final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
    final confirm = await _mostrarDialogoConfirmacion(
      '¿Aprobar petición?',
      'Se aplicarán todos los cambios realizados por ${peticion.adminName}.\n\nEsto incluye:\n${peticion.descripcionCambios}',
      'Aprobar',
      Colors.green,
    );

    if (confirm != true) return;

    try {
      await peticionProvider.aprobarPeticion(peticion.id);
      
      _mostrarExito('✅ Petición aprobada exitosamente.\n\nLos cambios han sido aplicados a la reserva.');
    } catch (e) {
      _mostrarError('Error al aprobar la petición: $e');
    }
  }

  Future<void> _rechazarPeticion(Peticion peticion) async {
    final peticionProvider = Provider.of<PeticionProvider>(context, listen: false);
    final motivo = await _mostrarDialogoRechazo();
    if (motivo == null || motivo.trim().isEmpty) return;

    try {
      await peticionProvider.rechazarPeticion(peticion.id, motivo);
      
      _mostrarExito('❌ Petición rechazada.\n\nLos cambios no se han aplicado y el administrador ha sido notificado.');
    } catch (e) {
      _mostrarError('Error al rechazar la petición: $e');
    }
  }

  Future<bool?> _mostrarDialogoConfirmacion(
    String titulo,
    String mensaje,
    String textoBoton,
    Color colorBoton,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Text(
          titulo,
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _primaryColor,
          ),
        ),
        content: Text(
          mensaje,
          style: GoogleFonts.montserrat(
            fontSize: 14,
            color: _primaryColor,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.montserrat(
                color: _primaryColor,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorBoton,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              textoBoton,
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _mostrarDialogoRechazo() {
    final controller = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Text(
          'Rechazar Petición',
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _primaryColor,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Especifica el motivo del rechazo para que el administrador comprenda la decisión:',
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Ej: Información incorrecta, conflicto de horarios, etc.',
                hintStyle: GoogleFonts.montserrat(fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _secondaryColor),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: GoogleFonts.montserrat(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancelar',
              style: GoogleFonts.montserrat(
                color: _primaryColor,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Por favor especifica un motivo',
                      style: GoogleFonts.montserrat(fontSize: 13),
                    ),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(12),
                  ),
                );
                return;
              }
              Navigator.of(context).pop(controller.text.trim());
            },
            child: Text(
              'Rechazar',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}