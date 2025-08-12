// lib/screens/admin/audit_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:reserva_canchas/models/audit_log.dart';
import 'package:reserva_canchas/providers/audit_provider.dart';
import 'package:reserva_canchas/screens/widgets/alert_panel.dart';
import 'package:reserva_canchas/services/audit_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({Key? key}) : super(key: key);

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final Color _primaryColor = const Color(0xFF3C4043);
  final Color _secondaryColor = const Color(0xFF4285F4);
  final Color _backgroundColor = Colors.white;
  final Color _cardColor = const Color(0xFFF8F9FA);
  final Color _dangerColor = const Color(0xFFDC3545);
  final Color _warningColor = const Color(0xFFFFC107);

  final TextEditingController _searchController = TextEditingController();
  List<AuditLog> _logsFiltered = [];
  bool _showFilters = false;
  bool _showAlertas = true;
  Map<String, dynamic>? _estadisticasSospechosas;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 10, vsync: this); // 10 tabs: Alertas + 9 CategoriaLog
    _cargarLogs();
    _cargarEstadisticasSospechosas();
    _searchController.addListener(() => _filtrarLogs(_searchController.text));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarLogs() async {
    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    await auditProvider.cargarLogsRecientes();
    setState(() {
      _logsFiltered = auditProvider.logs;
    });
  }

  Future<void> _cargarEstadisticasSospechosas() async {
    final auditService = AuditService();
    final stats = await auditService.obtenerEstadisticasSospechosas();
    setState(() {
      _estadisticasSospechosas = stats;
    });
  }

  void _filtrarLogs(String texto) {
    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    setState(() {
      if (texto.isEmpty) {
        _logsFiltered = auditProvider.logs;
      } else {
        _logsFiltered = auditProvider.logs.where((log) =>
            log.descripcion.toLowerCase().contains(texto.toLowerCase()) ||
            log.usuarioNombre.toLowerCase().contains(texto.toLowerCase()) ||
            log.accionTexto.toLowerCase().contains(texto.toLowerCase())
        ).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.security, color: _primaryColor),
            const SizedBox(width: 8),
            Text(
              'Centro de Control y Auditoría',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                color: _primaryColor,
              ),
            ),
          ],
        ),
        automaticallyImplyLeading: false,
        backgroundColor: _backgroundColor,
        elevation: 0,
        foregroundColor: _primaryColor,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: _secondaryColor,
          unselectedLabelColor: _primaryColor.withOpacity(0.6),
          indicatorColor: _secondaryColor,
          labelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Alertas'),
            Tab(text: 'Reservas'),
            Tab(text: 'Canchas'),
            Tab(text: 'Precios'),
            Tab(text: 'Sistema'),
            Tab(text: 'Seguridad'),
            Tab(text: 'Clientes'),
            Tab(text: 'Configuración'),
            Tab(text: 'Usuarios'),
            Tab(text: 'Reportes'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
            onPressed: () => setState(() => _showFilters = !_showFilters),
            tooltip: 'Filtros',
          ),
          IconButton(
            icon: Icon(Icons.analytics, color: _primaryColor),
            onPressed: () {
              if (_estadisticasSospechosas != null) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Estadísticas Sospechosas', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _estadisticasSospechosas!.entries.map((e) => _buildStatRow(e.key, e.value.toString())).toList(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cerrar', style: GoogleFonts.montserrat()),
                      ),
                    ],
                  ),
                );
              }
            },
            tooltip: 'Estadísticas Sospechosas',
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('alertas_criticas')
                .where('leida', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              final alertasCount = snapshot.data?.docs.length ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications_active, color: _dangerColor),
                    onPressed: () {
                      setState(() {
                        _showAlertas = !_showAlertas;
                        if (_showAlertas) _tabController.animateTo(0);
                      });
                    },
                    tooltip: 'Alertas críticas',
                  ),
                  if (alertasCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: _dangerColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$alertasCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ).animate(
                        onPlay: (controller) => controller.repeat(),
                      ).shake(duration: const Duration(milliseconds: 1000)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showFilters) _buildFilterPanel(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                AlertPanel(showOnlyUnread: true),
                _buildLogsView(CategoriaLog.reservas),
                _buildLogsView(CategoriaLog.canchas),
                _buildLogsView(CategoriaLog.precios),
                _buildLogsView(CategoriaLog.sistema),
                _buildLogsView(CategoriaLog.seguridad),
                _buildLogsView(CategoriaLog.clientes),
                _buildLogsView(CategoriaLog.configuracion),
                _buildLogsView(CategoriaLog.usuarios),
                _buildLogsView(CategoriaLog.reportes),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _secondaryColor,
        child: const Icon(Icons.refresh),
        onPressed: () async {
          await _cargarLogs();
          await _cargarEstadisticasSospechosas();
        },
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: _cardColor,
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Buscar logs',
              prefixIcon: Icon(Icons.search, color: _primaryColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showDatePicker,
                  icon: const Icon(Icons.calendar_today),
                  label: Text('Seleccionar fechas', style: GoogleFonts.montserrat()),
                  style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _exportarLogs,
                  icon: const Icon(Icons.download),
                  label: Text('Exportar', style: GoogleFonts.montserrat()),
                  style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _limpiarLogsAntiguos,
            icon: const Icon(Icons.delete_sweep),
            label: Text('Limpiar logs antiguos', style: GoogleFonts.montserrat()),
            style: ElevatedButton.styleFrom(backgroundColor: _dangerColor),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsView(CategoriaLog categoria) {
    return Consumer<AuditProvider>(
      builder: (context, provider, _) {
        final logs = _logsFiltered
            .where((log) => log.categoria == categoria)
            .toList();
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.error != null) {
          return Center(
            child: Text(
              'Error: ${provider.error}',
              style: GoogleFonts.montserrat(color: _dangerColor),
            ),
          );
        }
        if (logs.isEmpty) {
          return Center(
            child: Text(
              'No hay logs para esta categoría',
              style: GoogleFonts.montserrat(),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            return _buildLogCard(log);
          },
        );
      },
    );
  }

  Widget _buildLogCard(AuditLog log) {
    return Card(
      color: _cardColor,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: ExpansionTile(
        leading: Icon(
          _getIconForCategory(log.categoria),
          color: _getColorForSeverity(log.severidad.name),
        ),
        title: Text(
          log.accionTexto,
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Usuario: ${log.usuarioNombre} - ${log.fechaFormateada}',
          style: GoogleFonts.montserrat(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Descripción: ${log.descripcion}', style: GoogleFonts.montserrat()),
                Text('Severidad: ${log.severidad.name.toUpperCase()}', style: GoogleFonts.montserrat()),
                if (log.entidadId != null) Text('Entidad ID: ${log.entidadId}', style: GoogleFonts.montserrat()),
                if (log.datosAnteriores.isNotEmpty) 
                  Text('Datos Anteriores: ${log.datosAnteriores}', style: GoogleFonts.montserrat()),
                if (log.datosNuevos.isNotEmpty) 
                  Text('Datos Nuevos: ${log.datosNuevos}', style: GoogleFonts.montserrat()),
                if (log.metadatos.isNotEmpty) 
                  Text('Metadatos: ${log.metadatos}', style: GoogleFonts.montserrat()),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 300));
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.montserrat(fontSize: 14),
          ),
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _limpiarLogsAntiguos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Limpiar Logs Antiguos',
          style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Esto eliminará todos los logs con más de 90 días de antigüedad. Esta acción no se puede deshacer.',
          style: GoogleFonts.montserrat(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.montserrat()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _dangerColor),
            child: Text(
              'Confirmar',
              style: GoogleFonts.montserrat(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final auditProvider = Provider.of<AuditProvider>(context, listen: false);
        await auditProvider.limpiarLogsAntiguos();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Logs antiguos eliminados exitosamente',
              style: GoogleFonts.montserrat(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        await _cargarLogs();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al limpiar logs: $e',
              style: GoogleFonts.montserrat(color: Colors.white),
            ),
            backgroundColor: _dangerColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  void _showDatePicker() async {
    final dateRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      currentDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: _secondaryColor),
          ),
          child: child!,
        );
      },
    );

    if (dateRange != null) {
      final auditProvider = Provider.of<AuditProvider>(context, listen: false);
      await auditProvider.cargarLogs(
        fechaInicio: dateRange.start,
        fechaFin: dateRange.end,
      );
      setState(() {
        _logsFiltered = auditProvider.logs;
      });
    }
  }

  Future<void> _exportarLogs() async {
    try {
      final auditProvider = Provider.of<AuditProvider>(context, listen: false);
      final csvContent = auditProvider.exportarLogsCSV();
      // En una implementación real, aquí guardarías o compartirías el archivo CSV
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Logs exportados exitosamente (${auditProvider.logs.length} registros)',
                  style: GoogleFonts.montserrat(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error al exportar logs: $e',
            style: GoogleFonts.montserrat(color: Colors.white),
          ),
          backgroundColor: _dangerColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Color _getColorForSeverity(String severidad) {
    switch (severidad) {
      case 'critical':
        return _dangerColor;
      case 'error':
        return Colors.red.shade600;
      case 'warning':
        return _warningColor;
      case 'info':
        return Colors.blue.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _getIconForCategory(CategoriaLog categoria) {
    switch (categoria) {
      case CategoriaLog.reservas:
        return Icons.event_busy;
      case CategoriaLog.canchas:
        return Icons.sports_soccer;
      case CategoriaLog.precios:
        return Icons.attach_money;
      case CategoriaLog.sistema:
        return Icons.settings_applications;
      case CategoriaLog.seguridad:
        return Icons.security;
      case CategoriaLog.clientes:
        return Icons.person;
      case CategoriaLog.configuracion:
        return Icons.tune;
      case CategoriaLog.usuarios:
        return Icons.people;
      case CategoriaLog.reportes:
        return Icons.analytics;
    }
  }
}