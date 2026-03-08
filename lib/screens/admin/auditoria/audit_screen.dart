// lib/screens/audit_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reserva_canchas/models/audit_log.dart';
import 'package:reserva_canchas/providers/audit_provider.dart';
import 'package:reserva_canchas/services/cleanup_service.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  _AuditScreenState createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> with SingleTickerProviderStateMixin {
  String _filtroRapidoFecha = 'hoy'; // hoy, ayer, semana, mes, personalizado
  String _filtroAccion = 'todas';
  String _filtroRiesgo = 'todos';
  DateTime? _fechaInicioPersonalizada;
  DateTime? _fechaFinPersonalizada;
  bool _isCleaningUp = false;
  Map<String, int> _cleanupStats = {};
  Timer? _autoRefreshTimer;
  bool _autoRefreshEnabled = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AuditProvider>();
      provider.cargarAuditoria().then((_) {
        _aplicarFiltroRapido('hoy', provider);
      });
      
      _cargarEstadisticasLimpieza();
      _iniciarAutoRefresh();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _iniciarAutoRefresh() {
    _autoRefreshTimer?.cancel();
    if (_autoRefreshEnabled) {
      _autoRefreshTimer = Timer.periodic(Duration(seconds: 30), (timer) {
        if (mounted) {
          context.read<AuditProvider>().cargarAuditoria(forzarRecarga: true);
        }
      });
    }
  }

  Future<void> _aplicarFiltroRapido(String tipo, AuditProvider provider) async {
    final ahora = DateTime.now();
    DateTime inicio, fin;

    setState(() {
      _filtroRapidoFecha = tipo;
      _fechaInicioPersonalizada = null;
      _fechaFinPersonalizada = null;
    });

    switch (tipo) {
      case 'hoy':
        inicio = DateTime(ahora.year, ahora.month, ahora.day, 0, 0, 0);
        fin = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59, 999);
        break;
      case 'ayer':
        final ayer = ahora.subtract(Duration(days: 1));
        inicio = DateTime(ayer.year, ayer.month, ayer.day, 0, 0, 0);
        fin = DateTime(ayer.year, ayer.month, ayer.day, 23, 59, 59, 999);
        break;
      case 'semana':
        inicio = ahora.subtract(Duration(days: 7));
        inicio = DateTime(inicio.year, inicio.month, inicio.day, 0, 0, 0);
        fin = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59, 999);
        break;
      case 'mes':
        inicio = ahora.subtract(Duration(days: 30));
        inicio = DateTime(inicio.year, inicio.month, inicio.day, 0, 0, 0);
        fin = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59, 999);
        break;
      default:
        inicio = DateTime(ahora.year, ahora.month, ahora.day, 0, 0, 0);
        fin = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59, 999);
    }

    await provider.aplicarFiltros(
      fechaInicio: inicio,
      fechaFin: fin,
      accion: _filtroAccion,
      nivelRiesgo: _filtroRiesgo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.security, size: 24),
            ),
            SizedBox(width: 12),
            Text('Auditoría', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold)),
          ],
        ),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          Tooltip(
            message: _autoRefreshEnabled ? 'Auto-refresh activado' : 'Auto-refresh desactivado',
            child: IconButton(
              icon: Icon(_autoRefreshEnabled ? Icons.sync : Icons.sync_disabled),
              onPressed: () {
                setState(() {
                  _autoRefreshEnabled = !_autoRefreshEnabled;
                });
                _iniciarAutoRefresh();
              },
            ),
          ),
          IconButton(
            icon: Stack(
              children: [
                Icon(Icons.notifications),
                Consumer<AuditProvider>(
                  builder: (context, provider, _) {
                    final criticas = provider.estadisticas['critico'] ?? 0;
                    if (criticas > 0) {
                      return Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            criticas.toString(),
                            style: TextStyle(fontSize: 10, color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    return SizedBox.shrink();
                  },
                ),
              ],
            ),
            onPressed: _mostrarAlertas,
            tooltip: 'Alertas críticas',
          ),
          IconButton(
            icon: Icon(Icons.cleaning_services),
            onPressed: _mostrarLimpieza,
            tooltip: 'Limpieza de datos',
          ),
        ],
      ),
      body: Consumer<AuditProvider>(
        builder: (context, auditProvider, child) {
          if (auditProvider.isLoading && auditProvider.auditEntries.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Cargando auditoría...', style: GoogleFonts.montserrat()),
                ],
              ),
            );
          }

          if (auditProvider.errorMessage.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(auditProvider.errorMessage, style: GoogleFonts.montserrat()),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => auditProvider.cargarAuditoria(forzarRecarga: true),
                    child: Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 1024;
              final isTablet = constraints.maxWidth > 768;

              if (isDesktop) {
                return _buildDesktopLayout(auditProvider);
              } else if (isTablet) {
                return _buildTabletLayout(auditProvider);
              } else {
                return _buildMobileLayout(auditProvider);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildDesktopLayout(AuditProvider auditProvider) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildFiltrosCard(auditProvider),
                  SizedBox(height: 20),
                  _buildEstadisticasCard(auditProvider),
                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
          SizedBox(width: 24),
          Expanded(
            child: Column(
              children: [
                _buildResumenSuperior(auditProvider),
                SizedBox(height: 20),
                Expanded(child: _buildListaAuditoria(auditProvider)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(AuditProvider auditProvider) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildFiltrosCard(auditProvider)),
              SizedBox(width: 16),
              Expanded(child: _buildEstadisticasCard(auditProvider)),
            ],
          ),
          SizedBox(height: 16),
          _buildResumenSuperior(auditProvider),
          SizedBox(height: 16),
          Expanded(child: _buildListaAuditoria(auditProvider)),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(AuditProvider auditProvider) {
    return Column(
      children: [
        _buildResumenSuperior(auditProvider),
        SizedBox(height: 12),
        _buildFiltrosRapidosMobile(auditProvider),
        SizedBox(height: 12),
        Expanded(child: _buildListaAuditoria(auditProvider)),
      ],
    );
  }

  Widget _buildFiltrosRapidosMobile(AuditProvider auditProvider) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _mostrarFiltros(auditProvider),
              icon: Icon(Icons.filter_list, size: 18),
              label: Text('Filtros', style: GoogleFonts.montserrat(fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _mostrarEstadisticas(auditProvider),
              icon: Icon(Icons.analytics, size: 18),
              label: Text('Estadísticas', style: GoogleFonts.montserrat(fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltrosCard(AuditProvider auditProvider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.indigo.shade600],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.tune, color: Colors.white, size: 24),
                SizedBox(width: 12),
                Text(
                  'Filtros',
                  style: GoogleFonts.montserrat(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rango de Fecha',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildChipFiltro('Hoy', 'hoy', _filtroRapidoFecha == 'hoy', () async {
                      setState(() {
                        _filtroRapidoFecha = 'hoy';
                        _fechaInicioPersonalizada = null;
                        _fechaFinPersonalizada = null;
                      });
                      await _aplicarFiltroRapido('hoy', auditProvider);
                    }),
                    _buildChipFiltro('Ayer', 'ayer', _filtroRapidoFecha == 'ayer', () async {
                      setState(() {
                        _filtroRapidoFecha = 'ayer';
                        _fechaInicioPersonalizada = null;
                        _fechaFinPersonalizada = null;
                      });
                      await _aplicarFiltroRapido('ayer', auditProvider);
                    }),
                    _buildChipFiltro('Semana', 'semana', _filtroRapidoFecha == 'semana', () async {
                      setState(() {
                        _filtroRapidoFecha = 'semana';
                        _fechaInicioPersonalizada = null;
                        _fechaFinPersonalizada = null;
                      });
                      await _aplicarFiltroRapido('semana', auditProvider);
                    }),
                    _buildChipFiltro('Mes', 'mes', _filtroRapidoFecha == 'mes', () async {
                      setState(() {
                        _filtroRapidoFecha = 'mes';
                        _fechaInicioPersonalizada = null;
                        _fechaFinPersonalizada = null;
                      });
                      await _aplicarFiltroRapido('mes', auditProvider);
                    }),
                    _buildChipFiltro('Personalizado', 'personalizado', _filtroRapidoFecha == 'personalizado', () {
                      setState(() {
                        _filtroRapidoFecha = 'personalizado';
                        if (_fechaInicioPersonalizada == null) {
                          _fechaInicioPersonalizada = DateTime.now().subtract(Duration(days: 7));
                        }
                        if (_fechaFinPersonalizada == null) {
                          _fechaFinPersonalizada = DateTime.now();
                        }
                      });
                      _aplicarFiltrosPersonalizados(auditProvider);
                    }),
                  ],
                ),
                if (_filtroRapidoFecha == 'personalizado') ...[
                  SizedBox(height: 16),
                  _buildRangoFechasPersonalizado(auditProvider),
                ],
                SizedBox(height: 20),
                Text(
                  'Nivel de Riesgo',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildChipRiesgo('Todos', 'todos', Colors.grey, _filtroRiesgo == 'todos', () async {
                      setState(() => _filtroRiesgo = 'todos');
                      await _aplicarFiltros(auditProvider);
                    }),
                    _buildChipRiesgo('Crítico', 'critico', Colors.red, _filtroRiesgo == 'critico', () async {
                      setState(() => _filtroRiesgo = 'critico');
                      await _aplicarFiltros(auditProvider);
                    }),
                    _buildChipRiesgo('Alto', 'alto', Colors.orange, _filtroRiesgo == 'alto', () async {
                      setState(() => _filtroRiesgo = 'alto');
                      await _aplicarFiltros(auditProvider);
                    }),
                    _buildChipRiesgo('Medio', 'medio', Colors.yellow.shade700, _filtroRiesgo == 'medio', () async {
                      setState(() => _filtroRiesgo = 'medio');
                      await _aplicarFiltros(auditProvider);
                    }),
                    _buildChipRiesgo('Bajo', 'bajo', Colors.green, _filtroRiesgo == 'bajo', () async {
                      setState(() => _filtroRiesgo = 'bajo');
                      await _aplicarFiltros(auditProvider);
                    }),
                  ],
                ),
                SizedBox(height: 20),
                Text(
                  'Tipo de Acción',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _filtroAccion,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    style: GoogleFonts.montserrat(fontSize: 14),
                    items: [
                      {'value': 'todas', 'label': 'Todas las acciones'},
                      {'value': 'crear_reserva', 'label': 'Crear Reserva'},
                      {'value': 'editar_reserva', 'label': 'Editar Reserva'},
                      {'value': 'eliminar_reserva', 'label': 'Eliminar Reserva'},
                      {'value': 'completar_pago_solo_abono', 'label': 'Completar Pago Solo Abono'},
                      {'value': 'procesar_devolucion', 'label': 'Procesar Devolución'},
                      {'value': 'confirmar_devolucion', 'label': 'Confirmar Devolución'},
                      {'value': 'excluir_dia_reserva_recurrente', 'label': 'Excluir Día Recurrente'},
                      {'value': 'cancelar_reservas_futuras_recurrente', 'label': 'Cancelar Futuras'},
                    ].map((accion) => DropdownMenuItem(
                      value: accion['value'],
                      child: Text(accion['label']!),
                    )).toList(),
                    onChanged: (value) async {
                      setState(() => _filtroAccion = value!);
                      await _aplicarFiltros(auditProvider);
                    },
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async => await _limpiarFiltros(auditProvider),
                        icon: Icon(Icons.clear, size: 18),
                        label: Text('Limpiar', style: GoogleFonts.montserrat()),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipFiltro(String label, String value, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade600 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.blue.shade600 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildChipRiesgo(String label, String value, Color color, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: selected ? Colors.white : color,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangoFechasPersonalizado(AuditProvider auditProvider) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seleccionar Rango de Fechas',
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final fecha = await showDatePicker(
                      context: context,
                      initialDate: _fechaInicioPersonalizada ?? DateTime.now().subtract(Duration(days: 7)),
                      firstDate: DateTime.now().subtract(Duration(days: 365)),
                      lastDate: DateTime.now(),
                    );
                    if (fecha != null) {
                      setState(() {
                        _fechaInicioPersonalizada = fecha;
                        if (_fechaFinPersonalizada != null && _fechaInicioPersonalizada!.isAfter(_fechaFinPersonalizada!)) {
                          _fechaFinPersonalizada = _fechaInicioPersonalizada;
                        }
                      });
                      await _aplicarFiltrosPersonalizados(auditProvider);
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.blue.shade600, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fecha Inicio',
                                style: GoogleFonts.montserrat(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                _fechaInicioPersonalizada != null
                                    ? DateFormat('dd/MM/yyyy').format(_fechaInicioPersonalizada!)
                                    : 'Seleccionar',
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade800,
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
              SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final fecha = await showDatePicker(
                      context: context,
                      initialDate: _fechaFinPersonalizada ?? DateTime.now(),
                      firstDate: _fechaInicioPersonalizada ?? DateTime.now().subtract(Duration(days: 365)),
                      lastDate: DateTime.now(),
                    );
                    if (fecha != null) {
                      setState(() {
                        _fechaFinPersonalizada = fecha;
                        if (_fechaInicioPersonalizada != null && _fechaFinPersonalizada!.isBefore(_fechaInicioPersonalizada!)) {
                          _fechaInicioPersonalizada = _fechaFinPersonalizada;
                        }
                      });
                      await _aplicarFiltrosPersonalizados(auditProvider);
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.blue.shade600, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fecha Fin',
                                style: GoogleFonts.montserrat(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                _fechaFinPersonalizada != null
                                    ? DateFormat('dd/MM/yyyy').format(_fechaFinPersonalizada!)
                                    : 'Seleccionar',
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade800,
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEstadisticasCard(AuditProvider auditProvider) {
    final estadisticas = auditProvider.estadisticas;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade600, Colors.teal.shade600],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.analytics, color: Colors.white, size: 24),
                SizedBox(width: 12),
                Text(
                  'Estadísticas',
                  style: GoogleFonts.montserrat(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                _buildEstadisticaItem('Total', estadisticas['total'], Colors.blue, Icons.list_alt),
                SizedBox(height: 12),
                _buildEstadisticaItem('Crítico', estadisticas['critico'], Colors.red, Icons.error),
                SizedBox(height: 12),
                _buildEstadisticaItem('Alto', estadisticas['alto'], Colors.orange, Icons.warning),
                SizedBox(height: 12),
                _buildEstadisticaItem('Medio', estadisticas['medio'], Colors.yellow.shade700, Icons.info),
                SizedBox(height: 12),
                _buildEstadisticaItem('Bajo', estadisticas['bajo'], Colors.green, Icons.check_circle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadisticaItem(String label, int valor, Color color, IconData icon) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              valor.toString(),
              style: GoogleFonts.montserrat(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenSuperior(AuditProvider auditProvider) {
    final estadisticas = auditProvider.estadisticas;
    final entriesFiltradas = auditProvider.entriesFiltradas.length;
    
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildResumenItem(
              'Total',
              estadisticas['total'].toString(),
              Icons.list_alt,
              Colors.blue,
            ),
          ),
          Container(width: 1, height: 60, color: Colors.grey.shade200),
          Expanded(
            child: _buildResumenItem(
              'Críticas',
              estadisticas['critico'].toString(),
              Icons.error,
              Colors.red,
            ),
          ),
          Container(width: 1, height: 60, color: Colors.grey.shade200),
          Expanded(
            child: _buildResumenItem(
              'Altas',
              estadisticas['alto'].toString(),
              Icons.warning,
              Colors.orange,
            ),
          ),
          Container(width: 1, height: 60, color: Colors.grey.shade200),
          Expanded(
            child: _buildResumenItem(
              'Filtradas',
              entriesFiltradas.toString(),
              Icons.filter_list,
              Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenItem(String label, String valor, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        SizedBox(height: 8),
        Text(
          valor,
          style: GoogleFonts.montserrat(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildListaAuditoria(AuditProvider auditProvider) {
    final entries = auditProvider.entriesFiltradas;
  final tieneMas = auditProvider.tieneMasResultados;
    
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
            SizedBox(height: 16),
            Text(
              'No se encontraron entradas',
              style: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Intenta ajustar los filtros',
              style: GoogleFonts.montserrat(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => auditProvider.cargarAuditoria(forzarRecarga: true),
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: entries.length + (tieneMas ? 1 : 0),
        itemBuilder: (context, index) {
          // Último ítem: botón / indicador de "Cargar más"
          if (tieneMas && index == entries.length) {
            if (auditProvider.isLoading) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: () => auditProvider.cargarMasAuditoria(),
                  icon: Icon(Icons.expand_more),
                  label: Text(
                    'Cargar más',
                    style: GoogleFonts.montserrat(),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            );
          }

          final entry = entries[index];
          return Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _buildAuditEntryCard(entry),
          );
        },
      ),
    );
  }

  Widget _buildAuditEntryCard(AuditEntry entry) {
    final usuario = entry.usuarioNombre.isNotEmpty ? entry.usuarioNombre : 'Usuario';
    final avatarLetter = usuario.trim().isNotEmpty ? usuario.trim()[0].toUpperCase() : 'U';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _mostrarDetalleEntry(entry),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: entry.colorNivelRiesgo.withOpacity(0.3),
              width: entry.nivelRiesgo == 'critico' ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: entry.colorNivelRiesgo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: entry.colorNivelRiesgo.withOpacity(0.3)),
                  ),
                  child: Icon(entry.iconoNivelRiesgo, color: entry.colorNivelRiesgo, size: 24),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.blueGrey.shade100,
                            child: Text(
                              avatarLetter,
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade700,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  usuario,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  entry.fechaFormateada,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text(
                        _formatDescription(entry),
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.4,
                          color: Colors.grey.shade800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 8),
                      _buildChipsResumen(entry),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: entry.colorNivelRiesgo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: entry.colorNivelRiesgo.withOpacity(0.3)),
                  ),
                  child: Text(
                    entry.nombreNivelRiesgo,
                    style: GoogleFonts.montserrat(
                      color: entry.colorNivelRiesgo,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChipsResumen(AuditEntry entry) {
    final chips = <Widget>[];
    final meta = entry.metadatos;
    
    String? cancha = meta['cancha_nombre'];
    String? horario = meta['horario'];
    String? clienteNombre = meta['nombre'] ?? meta['cliente_nombre'];
    String? estado = meta['estado'] ?? meta['ESTADO'];

    if (clienteNombre != null && clienteNombre.isNotEmpty) {
      chips.add(_chipSecundario('Cliente: $clienteNombre'));
    }
    if (cancha != null) chips.add(_chipSecundario(cancha));
    if (horario != null) chips.add(_chipSecundario(horario));
    if (estado != null) chips.add(_chipSecundario('ESTADO: $estado'));

    if (entry.alertas.isNotEmpty) {
      chips.add(_chipAlerta(entry.alertas.first));
    }

    if (chips.isEmpty) return SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _chipSecundario(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        text,
        style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey.shade700),
      ),
    );
  }

  Widget _chipAlerta(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(
        text,
        style: GoogleFonts.montserrat(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _aplicarFiltros(AuditProvider auditProvider) async {
    final ahora = DateTime.now();
    DateTime inicio, fin;

    // Si hay fechas personalizadas, usarlas
    if (_filtroRapidoFecha == 'personalizado' && 
        _fechaInicioPersonalizada != null && 
        _fechaFinPersonalizada != null) {
      inicio = DateTime(_fechaInicioPersonalizada!.year, _fechaInicioPersonalizada!.month, _fechaInicioPersonalizada!.day, 0, 0, 0);
      fin = DateTime(_fechaFinPersonalizada!.year, _fechaFinPersonalizada!.month, _fechaFinPersonalizada!.day, 23, 59, 59);
    } else {
      switch (_filtroRapidoFecha) {
        case 'hoy':
          inicio = DateTime(ahora.year, ahora.month, ahora.day, 0, 0, 0);
          fin = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59);
          break;
        case 'ayer':
          final ayer = ahora.subtract(Duration(days: 1));
          inicio = DateTime(ayer.year, ayer.month, ayer.day, 0, 0, 0);
          fin = DateTime(ayer.year, ayer.month, ayer.day, 23, 59, 59);
          break;
        case 'semana':
          inicio = ahora.subtract(Duration(days: 7));
          inicio = DateTime(inicio.year, inicio.month, inicio.day, 0, 0, 0);
          fin = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59);
          break;
        case 'mes':
          inicio = ahora.subtract(Duration(days: 30));
          inicio = DateTime(inicio.year, inicio.month, inicio.day, 0, 0, 0);
          fin = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59);
          break;
        default:
          inicio = DateTime(ahora.year, ahora.month, ahora.day, 0, 0, 0);
          fin = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59);
      }
    }

    auditProvider.aplicarFiltros(
      fechaInicio: inicio,
      fechaFin: fin,
      accion: _filtroAccion,
      nivelRiesgo: _filtroRiesgo,
    );
  }

  Future<void> _aplicarFiltrosPersonalizados(AuditProvider auditProvider) async {
    if (_fechaInicioPersonalizada != null && _fechaFinPersonalizada != null) {
      final inicio = DateTime(_fechaInicioPersonalizada!.year, _fechaInicioPersonalizada!.month, _fechaInicioPersonalizada!.day, 0, 0, 0);
      final fin = DateTime(_fechaFinPersonalizada!.year, _fechaFinPersonalizada!.month, _fechaFinPersonalizada!.day, 23, 59, 59, 999);
      
      await auditProvider.aplicarFiltros(
        fechaInicio: inicio,
        fechaFin: fin,
        accion: _filtroAccion,
        nivelRiesgo: _filtroRiesgo,
      );
    }
  }

  Future<void> _limpiarFiltros(AuditProvider auditProvider) async {
    setState(() {
      _filtroRapidoFecha = 'hoy';
      _filtroAccion = 'todas';
      _filtroRiesgo = 'todos';
      _fechaInicioPersonalizada = null;
      _fechaFinPersonalizada = null;
    });
    await _aplicarFiltroRapido('hoy', auditProvider);
  }

  void _mostrarFiltros(AuditProvider auditProvider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _buildFiltrosCard(auditProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarEstadisticas(AuditProvider auditProvider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _buildEstadisticasCard(auditProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarAlertas() async {
    final auditProvider = context.read<AuditProvider>();
    final alertas = await auditProvider.obtenerAlertasNoLeidas();
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(maxWidth: 700, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade50, Colors.red.shade100],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.warning, color: Colors.red.shade600, size: 24),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alertas Críticas',
                            style: GoogleFonts.montserrat(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${alertas.length} alertas pendientes',
                            style: GoogleFonts.montserrat(
                              color: Colors.red.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Text(
                        '${alertas.length}',
                        style: GoogleFonts.montserrat(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Container(
                  padding: EdgeInsets.all(24),
                  child: alertas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade400),
                              SizedBox(height: 16),
                              Text(
                                'No hay alertas pendientes',
                                style: GoogleFonts.montserrat(
                                  fontSize: 18,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: alertas.length,
                          itemBuilder: (context, index) {
                            final alerta = alertas[index];
                            return Container(
                              margin: EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            alerta['titulo'],
                                            style: GoogleFonts.montserrat(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red.shade800,
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            alerta['descripcion'],
                                            style: GoogleFonts.montserrat(
                                              fontSize: 14,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Icon(Icons.person, size: 16, color: Colors.grey.shade500),
                                              SizedBox(width: 4),
                                              Text(
                                                alerta['usuario'],
                                                style: GoogleFonts.montserrat(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              SizedBox(width: 16),
                                              Icon(Icons.access_time, size: 16, color: Colors.grey.shade500),
                                              SizedBox(width: 4),
                                              Text(
                                                DateFormat('dd/MM/yyyy HH:mm').format(
                                                  (alerta['timestamp'] as Timestamp).toDate()
                                                ),
                                                style: GoogleFonts.montserrat(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      height: 36,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          auditProvider.marcarAlertaLeida(alerta['id']);
                                          Navigator.pop(context);
                                          _mostrarAlertas();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green.shade600,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        ),
                                        child: Text('Marcar leída', style: GoogleFonts.montserrat(fontSize: 12)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, size: 18),
                      label: Text('Cerrar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDetalleEntry(AuditEntry entry) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Builder(builder: (context) {
          final media = MediaQuery.of(context);
          final maxWidth = media.size.width < 600 ? 380.0 : 600.0;
          final maxHeight = media.size.height * 0.9;

          return Container(
            width: media.size.width * 0.92,
            constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: entry.colorNivelRiesgo.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.descripcion,
                                      style: GoogleFonts.montserrat(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade800,
                                        height: 1.35,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundColor: Colors.blueGrey.shade100,
                                          child: Text(
                                            (entry.usuarioNombre.isNotEmpty ? entry.usuarioNombre[0].toUpperCase() : 'U'),
                                            style: GoogleFonts.montserrat(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.blueGrey.shade700,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${entry.usuarioNombre} • ${entry.fechaFormateada}',
                                            style: GoogleFonts.montserrat(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                        _buildInfoSection('Información Básica', [
                          _buildInfoItem('Acción', entry.accion, Icons.touch_app),
                          _buildInfoItem('Usuario', entry.usuarioNombre, Icons.person),
                          _buildInfoItem('Rol', entry.usuarioRol, Icons.badge),
                          _buildInfoItem('Entidad', _formatEntityName(entry), Icons.category),
                        ]),
                        
                        if (entry.cambiosDetectados.isNotEmpty) ...[
                          SizedBox(height: 24),
                          _buildChangesSection(entry.cambiosDetectados),
                        ],
                        
                        if (entry.alertas.isNotEmpty) ...[
                          SizedBox(height: 24),
                          _buildAlertsSection(entry.alertas),
                        ],
                        
                        if (entry.metadatos.isNotEmpty) ...[
                          SizedBox(height: 24),
                          _buildRelevantMetadata(entry.metadatos),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, size: 18),
                        label: Text('Cerrar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.blue.shade600, size: 16),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangesSection(List<String> changes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.compare_arrows, color: Colors.orange.shade600, size: 20),
            SizedBox(width: 8),
            Text(
              'Cambios Detectados',
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Column(
            children: changes.map((change) => Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade600,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      change,
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertsSection(List<String> alerts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning, color: Colors.red.shade600, size: 20),
            SizedBox(width: 8),
            Text(
              'Alertas',
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            children: alerts.map((alert) => Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade600, size: 16),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      alert,
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRelevantMetadata(Map<String, dynamic> metadata) {
    final relevantKeys = [
      'cancha_nombre', 'horario', 'precio_personalizado', 
      'tiene_precio_personalizado', 'porcentaje_cambio_precio',
      'analisis_creacion', 'nombre', 'cliente_nombre', 'cancha_id',
      'sede_id', 'reserva_id', 'cliente_id', 'motivo', 'estado'
    ];
    
    final relevantData = <String, dynamic>{};
    metadata.forEach((key, value) {
      if (relevantKeys.contains(key) && value != null) {
        if (key.endsWith('_id')) {
          final nombreKey = key.replaceAll('_id', '_nombre');
          if (!metadata.containsKey(nombreKey) || metadata[nombreKey] == null) {
            relevantData[key] = value;
          }
        } else {
          relevantData[key] = value;
        }
      }
    });

    if (relevantData.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
            SizedBox(width: 8),
            Text(
              'Información Adicional',
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            children: relevantData.entries.map((entry) => Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatMetadataKey(entry.key),
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          _formatMetadataValue(entry.value),
                          style: GoogleFonts.montserrat(
                            fontSize: 14,
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  String _formatMetadataKey(String key) {
    switch (key) {
      case 'cancha_nombre': return 'Cancha';
      case 'horario': return 'Horario';
      case 'precio_personalizado': return 'Precio Personalizado';
      case 'tiene_precio_personalizado': return 'Tiene Descuento';
      case 'porcentaje_cambio_precio': return 'Cambio de Precio';
      case 'analisis_creacion': return 'Análisis de Creación';
      case 'nombre': return 'Cliente';
      case 'cliente_nombre': return 'Cliente';
      case 'cancha_id': return 'ID Cancha';
      case 'sede_id': return 'ID Sede';
      case 'reserva_id': return 'ID Reserva';
      case 'cliente_id': return 'ID Cliente';
      case 'motivo': return 'Motivo';
      case 'estado': return 'Estado';
      default: return key.replaceAll('_', ' ').toUpperCase();
    }
  }

  String _formatMetadataValue(dynamic value) {
    if (value is bool) {
      return value ? 'Sí' : 'No';
    } else if (value is num) {
      if (value.toString().contains('.')) {
        return '${value.toStringAsFixed(1)}%';
      }
      return NumberFormat('#,##0', 'es_CO').format(value);
    } else if (value is Map) {
      return 'Ver detalles...';
    }
    return value.toString();
  }

  String _formatDescription(AuditEntry entry) {
    String description = entry.descripcion;
    final meta = entry.metadatos;
    
    if (meta.containsKey('cancha_nombre') && meta['cancha_nombre'] != null) {
      description = description.replaceAll(entry.entidadId, meta['cancha_nombre']);
    }
    
    if (meta.containsKey('nombre') && meta['nombre'] != null) {
      description = description.replaceAll(entry.entidadId, meta['nombre']);
    } else if (meta.containsKey('cliente_nombre') && meta['cliente_nombre'] != null) {
      description = description.replaceAll(entry.entidadId, meta['cliente_nombre']);
    }
    
    description = description.replaceAll(RegExp(r'[a-zA-Z0-9]{15,}'), 'ID');
    
    return description;
  }

  String _formatEntityName(AuditEntry entry) {
    final meta = entry.metadatos;
    
    if (meta.containsKey('cancha_nombre') && meta['cancha_nombre'] != null) {
      return '${entry.entidad} - ${meta['cancha_nombre']}';
    }
    
    if (meta.containsKey('nombre') && meta['nombre'] != null) {
      return '${entry.entidad} - ${meta['nombre']}';
    }
    
    if (meta.containsKey('cliente_nombre') && meta['cliente_nombre'] != null) {
      return '${entry.entidad} - ${meta['cliente_nombre']}';
    }
    
    return entry.entidad;
  }

  Future<void> _cargarEstadisticasLimpieza() async {
    try {
      final stats = await CleanupService.obtenerEstadisticasAntiguos();
      if (mounted) {
        setState(() {
          _cleanupStats = stats;
        });
      }
    } catch (e) {
      debugPrint('Error cargando estadísticas: $e');
    }
  }

  void _mostrarLimpieza() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade50, Colors.orange.shade100],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.cleaning_services, color: Colors.orange.shade600, size: 24),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Limpieza de Datos',
                            style: GoogleFonts.montserrat(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Eliminar datos antiguos (más de 30 días)',
                            style: GoogleFonts.montserrat(
                              color: Colors.orange.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCleanupStats(),
                      SizedBox(height: 20),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Información sobre la limpieza',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade800,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Text(
                              '• Se eliminarán automáticamente los datos de auditoría con más de 30 días de antigüedad\n'
                              '• Los datos críticos se mantienen para análisis de seguridad\n'
                              '• La limpieza se ejecuta automáticamente cada día al iniciar la aplicación',
                              style: GoogleFonts.montserrat(
                                fontSize: 14,
                                color: Colors.blue.shade700,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, size: 18),
                      label: Text('Cerrar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isCleaningUp ? null : _ejecutarLimpiezaManual,
                      icon: _isCleaningUp 
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(Icons.cleaning_services, size: 18),
                      label: Text(_isCleaningUp ? 'Limpiando...' : 'Limpiar Ahora'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCleanupStats() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Datos antiguos disponibles para limpieza:',
            style: GoogleFonts.montserrat(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Logs de Auditoría',
                  _cleanupStats['audit_antiguos']?.toString() ?? '0',
                  Colors.blue,
                  Icons.analytics,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange.shade600, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Total: ${_cleanupStats['total_antiguos'] ?? 0} registros antiguos',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
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

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _ejecutarLimpiezaManual() async {
    setState(() {
      _isCleaningUp = true;
    });

    try {
      final resultados = await CleanupService.ejecutarLimpiezaManual();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Limpieza completada: ${resultados['audit_eliminados']} logs de auditoría eliminados',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
        
        Navigator.pop(context);
        await _cargarEstadisticasLimpieza();
        context.read<AuditProvider>().cargarAuditoria(forzarRecarga: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error en la limpieza: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCleaningUp = false;
        });
      }
    }
  }
}
