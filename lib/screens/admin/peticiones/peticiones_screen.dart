// lib/screens/admin/peticiones_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:reserva_canchas/models/peticion.dart';
import 'package:reserva_canchas/providers/peticion_provider.dart';
import 'package:reserva_canchas/screens/admin/auditoria/audit_screen.dart';
import '../../widgets/peticion_card.dart';

class PeticionesScreen extends StatefulWidget {
  const PeticionesScreen({Key? key}) : super(key: key);

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
      
      _mostrarError('Error al cambiar configuración: $e');
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
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
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
          style: GoogleFonts.montserrat(color: Colors.white),
        ),
        backgroundColor: _secondaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(height: 16),
              Text(
                'Cargando peticiones...',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
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
    ),
  ),
  automaticallyImplyLeading: false,
  backgroundColor: _backgroundColor,
  elevation: 0,
  foregroundColor: _primaryColor,
  actions: [
    // Indicador de SuperAdmin
    Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade400, Colors.purple.shade600],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.admin_panel_settings,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            'SUPER',
            style: GoogleFonts.montserrat(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ),
    // 🆕 NUEVO BOTÓN DE AUDITORÍA
    Container(
      margin: const EdgeInsets.only(right: 8),
      child: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade400, Colors.teal.shade600],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.analytics,
            color: Colors.white,
            size: 18,
          ),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AuditScreen(),
            ),
          );
        },
        tooltip: 'Ver Auditoría',
      ),
    ),
    IconButton(
      icon: Icon(Icons.refresh, color: _secondaryColor),
      onPressed: _refrescarPeticiones,
      tooltip: 'Refrescar',
    ),
  ],
  bottom: PreferredSize(
    preferredSize: const Size.fromHeight(48),
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: _secondaryColor,
          borderRadius: BorderRadius.circular(6),
        ),
        labelPadding: EdgeInsets.zero,
        tabs: [
          _buildCompactTab(Icons.pending_actions, 'Pendientes'),
          _buildCompactTab(Icons.check_circle, 'Aprobadas'),
          _buildCompactTab(Icons.cancel, 'Rechazadas'),
          _buildCompactTab(Icons.list_alt, 'Todas'),
        ],
        labelColor: Colors.white,
        unselectedLabelColor: _primaryColor.withOpacity(0.6),
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
                _buildControlTotalCard(peticionProvider),
              ],
              
              // Card de estadísticas
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCard(
                      'Total',
                      estadisticas['total']?.toString() ?? '0',
                      _primaryColor,
                      Icons.all_inbox,
                    ),
                    _buildStatCard(
                      'Pendientes',
                      estadisticas['pendientes']?.toString() ?? '0',
                      Colors.orange,
                      Icons.pending_actions,
                    ),
                    _buildStatCard(
                      'Aprobadas',
                      estadisticas['aprobadas']?.toString() ?? '0',
                      Colors.green,
                      Icons.check_circle,
                    ),
                    _buildStatCard(
                      'Rechazadas',
                      estadisticas['rechazadas']?.toString() ?? '0',
                      Colors.red,
                      Icons.cancel,
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),
              
              // TabBarView
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPeticionesList(peticionProvider.peticionesPendientes),
                    _buildPeticionesList(
                      peticionProvider.peticiones.where((p) => p.fueAprobada).toList(),
                    ),
                    _buildPeticionesList(
                      peticionProvider.peticiones.where((p) => p.fueRechazada).toList(),
                    ),
                    _buildPeticionesList(peticionProvider.peticiones),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // FRAGMENTO 1: Reemplazar el método _buildControlTotalCard completo
Widget _buildControlTotalCard(PeticionProvider peticionProvider) {
  final controlActivado = peticionProvider.controlTotalActivado;
  
  return Container(
    margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: controlActivado 
            ? [Colors.green.shade50, Colors.green.shade100]
            : [Colors.orange.shade50, Colors.orange.shade100],
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: controlActivado ? Colors.green.shade300 : Colors.orange.shade300,
      ),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: AnimatedBuilder(
          animation: _switchAnimation,
          builder: (context, child) {
            return Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Color.lerp(
                  Colors.orange.withOpacity(0.3),
                  Colors.green.withOpacity(0.3),
                  _switchAnimation.value,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                controlActivado ? Icons.admin_panel_settings : Icons.pending_actions,
                color: Color.lerp(
                  Colors.orange.shade700,
                  Colors.green.shade700,
                  _switchAnimation.value,
                ),
                size: 20,
              ),
            );
          },
        ),
        title: Text(
          'Control Total',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: controlActivado ? Colors.green.shade800 : Colors.orange.shade800,
          ),
        ),
        subtitle: Text(
          controlActivado ? 'Cambios directos activos' : 'Requiere peticiones',
          style: GoogleFonts.montserrat(
            fontSize: 12,
            color: controlActivado ? Colors.green.shade600 : Colors.orange.shade600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: controlActivado 
                    ? Colors.green.withOpacity(0.2)
                    : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                controlActivado ? 'ON' : 'OFF',
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: controlActivado ? Colors.green.shade800 : Colors.orange.shade800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more, size: 20),
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
                        fontSize: 12,
                        color: controlActivado ? Colors.green.shade700 : Colors.orange.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          controlActivado ? Icons.check_circle : Icons.warning,
                          size: 14,
                          color: controlActivado ? Colors.green.shade600 : Colors.orange.shade600,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            controlActivado ? 'CAMBIOS INMEDIATOS' : 'REQUIERE APROBACIÓN',
                            style: GoogleFonts.montserrat(
                              fontSize: 10,
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
              const SizedBox(width: 16),
              if (_toggleLoading)
                SizedBox(
                  width: 20,
                  height: 20,
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
                    width: 44,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: controlActivado ? Colors.green.shade400 : Colors.orange.shade300,
                    ),
                    child: Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          left: controlActivado ? 22 : 2,
                          top: 2,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              controlActivado ? Icons.check : Icons.close,
                              size: 12,
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


Widget _buildCompactTab(IconData icon, String label) {
  return Tab(
    height: 40,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 11,
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
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: nuevoValor ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
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
                  fontSize: 18,
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
                  fontSize: 16, 
                  color: _primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: nuevoValor ? Colors.orange.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
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
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            nuevoValor ? 'Esto permitirá que los administradores:' : 'Los administradores deberán:',
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: nuevoValor ? Colors.orange.shade800 : Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorBoton,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              textoBoton,
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: color,
                fontWeight: isWarning || isPositive ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
  return Column(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(height: 6),
      Text(
        value,
        style: GoogleFonts.montserrat(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      Text(
        title,
        style: GoogleFonts.montserrat(
          fontSize: 11,
          color: _primaryColor.withOpacity(0.7),
        ),
      ),
    ],
  );
}



Widget _buildCompactStatCard(String title, String value, Color color, IconData icon) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                title,
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  color: _primaryColor.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}





  Widget _buildPeticionesList(List<Peticion> peticiones) {
    if (peticiones.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: _primaryColor.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No hay peticiones',
              style: GoogleFonts.montserrat(
                fontSize: 18,
                color: _primaryColor.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Las peticiones aparecerán aquí cuando los admins realicen cambios.',
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: _primaryColor.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refrescarPeticiones,
      color: _secondaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: peticiones.length,
        itemBuilder: (context, index) {
          final peticion = peticiones[index];
          return PeticionCard(
            peticion: peticion,
            onAprobar: _esSuperAdmin ? () => _aprobarPeticion(peticion) : null,
            onRechazar: _esSuperAdmin ? () => _rechazarPeticion(peticion) : null,
          ).animate(delay: (index * 100).ms).fadeIn(duration: 500.ms).slideX(
                begin: -0.2,
                end: 0,
                duration: 500.ms,
                curve: Curves.easeOutQuad,
              );
        },
      ),
    );
  }

  Future<void> _aprobarPeticion(Peticion peticion) async {
    final confirm = await _mostrarDialogoConfirmacion(
      '¿Aprobar petición?',
      'Se aplicarán todos los cambios realizados por ${peticion.adminName}.\n\nEsto incluye:\n${peticion.descripcionCambios}',
      'Aprobar',
      Colors.green,
    );

    if (confirm != true) return;

    try {
      await Provider.of<PeticionProvider>(context, listen: false)
          .aprobarPeticion(peticion.id);
      
      _mostrarExito('✅ Petición aprobada exitosamente.\n\nLos cambios han sido aplicados a la reserva.');
    } catch (e) {
      _mostrarError('Error al aprobar la petición: $e');
    }
  }

  Future<void> _rechazarPeticion(Peticion peticion) async {
    final motivo = await _mostrarDialogoRechazo();
    if (motivo == null || motivo.trim().isEmpty) return;

    try {
      await Provider.of<PeticionProvider>(context, listen: false)
          .rechazarPeticion(peticion.id, motivo);
      
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
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          titulo,
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _primaryColor,
          ),
        ),
        content: Text(
          mensaje,
          style: GoogleFonts.montserrat(
            fontSize: 16,
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
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              textoBoton,
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
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
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Rechazar Petición',
          style: GoogleFonts.montserrat(
            fontSize: 18,
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
                fontSize: 16,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Ej: Información incorrecta, conflicto de horarios, etc.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _secondaryColor),
                ),
              ),
              style: GoogleFonts.montserrat(),
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
            ),
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Por favor especifica un motivo'),
                    backgroundColor: Colors.redAccent,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}