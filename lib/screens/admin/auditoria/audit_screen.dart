// lib/screens/audit_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:reserva_canchas/models/audit_log.dart';
import 'package:reserva_canchas/providers/audit_provider.dart';


class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  _AuditScreenState createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  DateTime _diaSeleccionado = DateTime.now();
  bool _soloHoy = true;
  String _filtroAccion = 'todas';
  String _filtroRiesgo = 'todos';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AuditProvider>();
      provider.cargarAuditoria().then((_) {
        // Filtro por defecto: solo auditorías de HOY
        final hoy = DateTime.now();
        final inicio = DateTime(hoy.year, hoy.month, hoy.day, 0, 0, 0);
        final fin = DateTime(hoy.year, hoy.month, hoy.day, 23, 59, 59);
        provider.aplicarFiltros(
          fechaInicio: inicio,
          fechaFin: fin,
          accion: _filtroAccion,
          nivelRiesgo: _filtroRiesgo,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Auditoría del Sistema'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () => context.read<AuditProvider>().cargarAuditoria(),
          ),
          IconButton(
            icon: Icon(Icons.notifications),
            onPressed: _mostrarAlertas,
          ),
        ],
      ),
      body: Consumer<AuditProvider>(
        builder: (context, auditProvider, child) {
          if (auditProvider.isLoading) {
            return Center(child: CircularProgressIndicator());
          }

          if (auditProvider.errorMessage.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(auditProvider.errorMessage),
                  ElevatedButton(
                    onPressed: () => auditProvider.cargarAuditoria(),
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
          // Panel lateral izquierdo - Más ancho y con scroll si es necesario
          SizedBox(
            width: 400,
            child: SingleChildScrollView(
            child: Column(
              children: [
                _buildFiltrosCard(auditProvider),
                  SizedBox(height: 20),
                _buildEstadisticasCard(auditProvider),
                  SizedBox(height: 20), // Espacio adicional al final
              ],
            ),
          ),
          ),
          SizedBox(width: 24),
          // Panel principal
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
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          _buildResumenSuperior(auditProvider),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _mostrarFiltros(auditProvider),
                    icon: Icon(Icons.filter_list, size: 18),
                    label: Text('Filtros', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _mostrarEstadisticas(auditProvider),
                    icon: Icon(Icons.analytics, size: 18),
                    label: Text('Estadísticas', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Expanded(child: _buildListaAuditoria(auditProvider)),
        ],
      ),
    );
  }

  Widget _buildFiltrosCard(AuditProvider auditProvider) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade50,
            Colors.indigo.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.filter_list, color: Colors.blue.shade700, size: 20),
                ),
                SizedBox(width: 12),
                Text(
                  'Filtros',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            _buildFiltroFechas(),
            SizedBox(height: 20),
            _buildFiltroAccion(),
            SizedBox(height: 20),
            _buildFiltroRiesgo(),
            SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    child: ElevatedButton.icon(
                    onPressed: () => _aplicarFiltros(auditProvider),
                      icon: Icon(Icons.search, size: 18),
                      label: Text('Aplicar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 44,
                    child: OutlinedButton.icon(
                    onPressed: () => _limpiarFiltros(auditProvider),
                      icon: Icon(Icons.clear, size: 18),
                      label: Text('Limpiar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue.shade600,
                        side: BorderSide(color: Colors.blue.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadisticasCard(AuditProvider auditProvider) {
    final estadisticas = auditProvider.estadisticas;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green.shade50,
            Colors.teal.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade100, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.green.shade100,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.analytics, color: Colors.green.shade700, size: 20),
                ),
                SizedBox(width: 12),
                Text(
                  'Estadísticas',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            _buildEstadisticaItem('Total', estadisticas['total'], Colors.blue),
            SizedBox(height: 8),
            _buildEstadisticaItem('Crítico', estadisticas['critico'], Colors.red),
            SizedBox(height: 8),
            _buildEstadisticaItem('Alto', estadisticas['alto'], Colors.orange),
            SizedBox(height: 8),
            _buildEstadisticaItem('Medio', estadisticas['medio'], Colors.yellow.shade700),
            SizedBox(height: 8),
            _buildEstadisticaItem('Bajo', estadisticas['bajo'], Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadisticaItem(String label, int valor, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
          Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              valor.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenSuperior(AuditProvider auditProvider) {
    final estadisticas = auditProvider.estadisticas;
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildResumenItem(
              'Total',
              estadisticas['total'].toString(),
              Icons.list_alt,
              Colors.blue,
            ),
            _buildResumenItem(
              'Críticas',
              estadisticas['critico'].toString(),
              Icons.error,
              Colors.red,
            ),
            _buildResumenItem(
              'Altas',
              estadisticas['alto'].toString(),
              Icons.warning,
              Colors.orange,
            ),
            _buildResumenItem(
              'Filtradas',
              auditProvider.entriesFiltradas.length.toString(),
              Icons.filter_list,
              Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumenItem(String label, String valor, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        SizedBox(height: 4),
        Text(
          valor,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildListaAuditoria(AuditProvider auditProvider) {
    final entries = auditProvider.entriesFiltradas;
    
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No se encontraron entradas de auditoría'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _buildAuditEntryCard(entry);
      },
    );
  }

  Widget _buildAuditEntryCard(AuditEntry entry) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () => _mostrarDetalleEntry(entry),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: entry.colorNivelRiesgo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: entry.colorNivelRiesgo.withOpacity(0.3)),
                ),
                child: Icon(entry.iconoNivelRiesgo, color: entry.colorNivelRiesgo),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_formatDescription(entry), style: TextStyle(fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('${entry.usuarioNombre} • ${entry.fechaFormateada}', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                    SizedBox(height: 6),
                    _buildChipsResumen(entry),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: entry.colorNivelRiesgo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(entry.nombreNivelRiesgo, style: TextStyle(color: entry.colorNivelRiesgo, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
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
    final bool precioPersonalizado = meta['precio_personalizado'] == true || meta['tiene_precio_personalizado'] == true;
    final double? porcentajeCambio = (meta['porcentaje_cambio_precio'] as num?)?.toDouble();

    // Cliente (prioridad alta para exclusión de días)
    if (clienteNombre != null && clienteNombre.isNotEmpty) {
      chips.add(_chipSecundario('Cliente: $clienteNombre'));
    }

    // Cancha / Horario
    if (cancha != null) chips.add(_chipSecundario(cancha));
    if (horario != null) chips.add(_chipSecundario(horario));

    // Precio personalizado
    if (precioPersonalizado) chips.add(_chipEtiqueta('Precio Personalizado'));

    // Porcentaje cambio de precio
    if (porcentajeCambio != null && porcentajeCambio > 0) {
      chips.add(_chipAlerta(
        porcentajeCambio >= 30 ? 'Cambio precio: ${porcentajeCambio.toStringAsFixed(1)}%' : 'Ajuste precio: ${porcentajeCambio.toStringAsFixed(1)}%'
      ));
    }

    // Comparación de precio en creación si está disponible
    final analisisCreacion = meta['analisis_creacion'] as Map<String, dynamic>?;
    final contextoPrecio = analisisCreacion != null ? analisisCreacion['contexto_precio'] as Map<String, dynamic>? : null;
    if (contextoPrecio != null && contextoPrecio['precio_original'] != null && contextoPrecio['precio_aplicado'] != null) {
      final formatter = NumberFormat('#,##0', 'es_CO');
      chips.add(_chipSecundario('Precio: ${formatter.format(contextoPrecio['precio_original'])} → ${formatter.format(contextoPrecio['precio_aplicado'])}'));
    }

    // Alertas (solo primeras 2 para no saturar)
    if (entry.alertas.isNotEmpty) {
      for (final alerta in entry.alertas.take(2)) {
        chips.add(_chipAlerta(alerta));
      }
    }

    // Filtrar y mostrar solo metadatos relevantes (evitar IDs largos)
    final metadatosRelevantes = _getRelevantMetadataForChips(meta);
    for (final entry in metadatosRelevantes.entries) {
      if (entry.value != null && entry.value.toString().isNotEmpty) {
        final value = entry.value.toString();
        // Solo mostrar si no es un ID largo
        if (!_isLongId(value)) {
          chips.add(_chipSecundario('${_formatMetadataKey(entry.key)}: $value'));
        }
      }
    }

    if (chips.isEmpty) return SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _chipEtiqueta(String text) {
    return Chip(label: Text(text, style: TextStyle(fontSize: 10)), backgroundColor: Colors.indigo.shade50, side: BorderSide(color: Colors.indigo.shade200));
  }

  Widget _chipSecundario(String text) {
    return Chip(label: Text(text, style: TextStyle(fontSize: 10)), backgroundColor: Colors.grey.shade100, side: BorderSide(color: Colors.grey.shade300));
  }

  Widget _chipAlerta(String text) {
    return Chip(label: Text(text, style: TextStyle(fontSize: 10)), backgroundColor: Colors.red.shade50, side: BorderSide(color: Colors.red.shade200));
  }

  Widget _buildFiltroFechas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fecha',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                child: ElevatedButton(
                  onPressed: () {
                setState(() {
                  _soloHoy = true;
                  _diaSeleccionado = DateTime.now();
                });
              },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _soloHoy ? Colors.blue.shade600 : Colors.grey.shade100,
                    foregroundColor: _soloHoy ? Colors.white : Colors.grey.shade600,
                    elevation: _soloHoy ? 2 : 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text(
                    'Hoy',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 40,
                child: ElevatedButton(
                  onPressed: () async {
                final fecha = await showDatePicker(
                  context: context,
                  initialDate: _diaSeleccionado,
                  firstDate: DateTime.now().subtract(Duration(days: 365)),
                  lastDate: DateTime.now().add(Duration(days: 365)),
                );
                if (fecha != null) {
                  setState(() {
                    _soloHoy = false;
                    _diaSeleccionado = fecha;
                  });
                }
              },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !_soloHoy ? Colors.blue.shade600 : Colors.grey.shade100,
                    foregroundColor: !_soloHoy ? Colors.white : Colors.grey.shade600,
                    elevation: !_soloHoy ? 2 : 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text(
                    DateFormat('dd/MM/yyyy').format(_diaSeleccionado),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFiltroAccion() {
    final acciones = [
      {'value': 'todas', 'label': 'Todas'},
      {'value': 'crear_reserva', 'label': 'Crear Reserva'},
      {'value': 'editar_reserva', 'label': 'Editar Reserva'},
      {'value': 'eliminar_reserva', 'label': 'Eliminar Reserva'},
      {'value': 'cambio_precio_cancha', 'label': 'Cambio Precio'},
      {'value': 'crear_reserva_precio_personalizado', 'label': 'Reserva con Descuento'},
      {'value': 'excluir_dia_reserva_recurrente', 'label': 'Excluir Día'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acción',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade100,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButtonFormField<String>(
          value: _filtroAccion,
          decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              hintText: 'Seleccionar acción',
            ),
            dropdownColor: Colors.white,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 14,
          ),
          items: acciones.map((accion) => DropdownMenuItem(
            value: accion['value'],
            child: Text(accion['label']!),
          )).toList(),
          onChanged: (value) => setState(() => _filtroAccion = value!),
          ),
        ),
      ],
    );
  }

  Widget _buildFiltroRiesgo() {
    final riesgos = [
      {'value': 'todos', 'label': 'Todos'},
      {'value': 'critico', 'label': 'Crítico'},
      {'value': 'alto', 'label': 'Alto'},
      {'value': 'medio', 'label': 'Medio'},
      {'value': 'bajo', 'label': 'Bajo'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nivel de Riesgo',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade100,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButtonFormField<String>(
          value: _filtroRiesgo,
          decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              hintText: 'Seleccionar nivel',
            ),
            dropdownColor: Colors.white,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 14,
          ),
          items: riesgos.map((riesgo) => DropdownMenuItem(
            value: riesgo['value'],
            child: Text(riesgo['label']!),
          )).toList(),
          onChanged: (value) => setState(() => _filtroRiesgo = value!),
          ),
        ),
      ],
    );
  }

  // Eliminado selector de rango; se usa ChoiceChip + datePicker en _buildFiltroFechas

  void _aplicarFiltros(AuditProvider auditProvider) {
    // Calcular rango según selección
    final base = _soloHoy ? DateTime.now() : _diaSeleccionado;
    final inicio = DateTime(base.year, base.month, base.day, 0, 0, 0);
    final fin = DateTime(base.year, base.month, base.day, 23, 59, 59);

    auditProvider.aplicarFiltros(
      fechaInicio: inicio,
      fechaFin: fin,
      accion: _filtroAccion,
      nivelRiesgo: _filtroRiesgo,
    );
  }

  void _limpiarFiltros(AuditProvider auditProvider) {
    setState(() {
      _soloHoy = true;
      _diaSeleccionado = DateTime.now();
      _filtroAccion = 'todas';
      _filtroRiesgo = 'todos';
    });
    _aplicarFiltros(auditProvider);
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
            // Handle para arrastrar
              Container(
                width: 40,
                height: 4,
              margin: EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            // Contenido con scroll
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
            // Handle para arrastrar
              Container(
                width: 40,
                height: 4,
              margin: EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            // Contenido con scroll
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
              // Header con gradiente rojo
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.red.shade50,
                      Colors.red.shade100,
                    ],
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
                      child: Icon(
                        Icons.warning,
                        color: Colors.red.shade600,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alertas Críticas',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${alertas.length} alertas pendientes',
                            style: TextStyle(
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
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Contenido principal
              Flexible(
                child: Container(
                  padding: EdgeInsets.all(24),
          child: alertas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 64,
                                color: Colors.green.shade400,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No hay alertas pendientes',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Todo está bajo control',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
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
                                      child: Icon(
                                        Icons.error_outline,
                                        color: Colors.red.shade600,
                                        size: 20,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                          Text(
                                            alerta['titulo'],
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red.shade800,
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            alerta['descripcion'],
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.person,
                                                size: 16,
                                                color: Colors.grey.shade500,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                alerta['usuario'],
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              SizedBox(width: 16),
                                              Icon(
                                                Icons.access_time,
                                                size: 16,
                                                color: Colors.grey.shade500,
                                              ),
                                              SizedBox(width: 4),
                          Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(
                              (alerta['timestamp'] as Timestamp).toDate()
                            ),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                          ),
                        ],
                      ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      height: 36,
                                      child: ElevatedButton(
                        onPressed: () {
                          auditProvider.marcarAlertaLeida(alerta['id']);
                          Navigator.pop(context);
                          _mostrarAlertas(); // Recargar
                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green.shade600,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        ),
                                        child: Text(
                                          'Marcar leída',
                                          style: TextStyle(fontSize: 12),
                                        ),
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
              
              // Footer con botón
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header con gradiente
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      entry.colorNivelRiesgo.withOpacity(0.1),
                      entry.colorNivelRiesgo.withOpacity(0.05),
                    ],
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
                        color: entry.colorNivelRiesgo.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        entry.iconoNivelRiesgo,
                        color: entry.colorNivelRiesgo,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.descripcion,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${entry.usuarioNombre} • ${entry.fechaFormateada}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: entry.colorNivelRiesgo.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: entry.colorNivelRiesgo.withOpacity(0.3)),
                      ),
                      child: Text(
                        entry.nombreNivelRiesgo,
                        style: TextStyle(
                          color: entry.colorNivelRiesgo,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Contenido principal
              Flexible(
          child: SingleChildScrollView(
                  padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                      // Información básica
                      _buildInfoSection('Información Básica', [
                        _buildInfoItem('Acción', entry.accion, Icons.touch_app),
                        _buildInfoItem('Usuario', entry.usuarioNombre, Icons.person),
                        _buildInfoItem('Rol', entry.usuarioRol, Icons.badge),
                        _buildInfoItem('Entidad', _formatEntityName(entry), Icons.category),
                      ]),
                      
                      // Cambios detectados (solo si hay)
                if (entry.cambiosDetectados.isNotEmpty) ...[
                        SizedBox(height: 24),
                        _buildChangesSection(entry.cambiosDetectados),
                      ],
                      
                      // Alertas (solo si hay)
                if (entry.alertas.isNotEmpty) ...[
                        SizedBox(height: 24),
                        _buildAlertsSection(entry.alertas),
                      ],
                      
                      // Información relevante de metadatos
                if (entry.metadatos.isNotEmpty) ...[
                        SizedBox(height: 24),
                        _buildRelevantMetadata(entry.metadatos),
                ],
              ],
            ),
          ),
        ),
              
              // Footer con botón
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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

  Widget _buildInfoSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
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
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
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
              style: TextStyle(
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
                      style: TextStyle(
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
              style: TextStyle(
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
                      style: TextStyle(
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
    // Filtrar solo metadatos relevantes e importantes
    final relevantKeys = [
      'cancha_nombre', 'horario', 'precio_personalizado', 
      'tiene_precio_personalizado', 'porcentaje_cambio_precio',
      'analisis_creacion', 'nombre', 'cliente_nombre', 'cancha_id',
      'sede_id', 'reserva_id', 'cliente_id'
    ];
    
    final relevantData = <String, dynamic>{};
    metadata.forEach((key, value) {
      if (relevantKeys.contains(key) && value != null) {
        // Priorizar nombres sobre IDs
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
              style: TextStyle(
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
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          _formatMetadataValue(entry.value),
                          style: TextStyle(
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
    
    // Reemplazar IDs con nombres cuando estén disponibles en metadatos
    final meta = entry.metadatos;
    
    // Reemplazar nombres de canchas
    if (meta.containsKey('cancha_nombre') && meta['cancha_nombre'] != null) {
      description = description.replaceAll(entry.entidadId, meta['cancha_nombre']);
    }
    
    // Reemplazar nombres de clientes
    if (meta.containsKey('nombre') && meta['nombre'] != null) {
      description = description.replaceAll(entry.entidadId, meta['nombre']);
    } else if (meta.containsKey('cliente_nombre') && meta['cliente_nombre'] != null) {
      description = description.replaceAll(entry.entidadId, meta['cliente_nombre']);
    }
    
    // Limpiar IDs largos que puedan aparecer en la descripción
    description = description.replaceAll(RegExp(r'[a-zA-Z0-9]{15,}'), 'ID');
    
    return description;
  }

  String _formatEntityName(AuditEntry entry) {
    final meta = entry.metadatos;
    
    // Intentar obtener el nombre de la entidad desde los metadatos
    if (meta.containsKey('cancha_nombre') && meta['cancha_nombre'] != null) {
      return '${entry.entidad} - ${meta['cancha_nombre']}';
    }
    
    if (meta.containsKey('nombre') && meta['nombre'] != null) {
      return '${entry.entidad} - ${meta['nombre']}';
    }
    
    if (meta.containsKey('cliente_nombre') && meta['cliente_nombre'] != null) {
      return '${entry.entidad} - ${meta['cliente_nombre']}';
    }
    
    // Si no hay nombre disponible, mostrar solo el tipo de entidad
    return entry.entidad;
  }

  Map<String, dynamic> _getRelevantMetadataForChips(Map<String, dynamic> metadata) {
    final relevantKeys = [
      'fecha', 'estado', 'monto', 'precio', 'descuento', 'tipo', 'motivo'
    ];
    
    final relevantData = <String, dynamic>{};
    metadata.forEach((key, value) {
      if (relevantKeys.contains(key) && value != null) {
        relevantData[key] = value;
      }
    });
    
    return relevantData;
  }

  bool _isLongId(String value) {
    // Detectar si es un ID largo (más de 15 caracteres alfanuméricos)
    return RegExp(r'^[a-zA-Z0-9]{15,}$').hasMatch(value);
  }
}