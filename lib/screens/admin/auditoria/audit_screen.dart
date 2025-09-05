// lib/screens/audit_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:reserva_canchas/models/audit_log.dart';
import 'package:reserva_canchas/providers/audit_provider.dart';


class AuditScreen extends StatefulWidget {
  @override
  _AuditScreenState createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  String _filtroAccion = 'todas';
  String _filtroRiesgo = 'todos';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuditProvider>().cargarAuditoria();
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
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel lateral izquierdo
          Container(
            width: 320,
            child: Column(
              children: [
                _buildFiltrosCard(auditProvider),
                SizedBox(height: 16),
                _buildEstadisticasCard(auditProvider),
              ],
            ),
          ),
          SizedBox(width: 16),
          // Panel principal
          Expanded(
            child: Column(
              children: [
                _buildResumenSuperior(auditProvider),
                SizedBox(height: 16),
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
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _mostrarFiltros(auditProvider),
                  icon: Icon(Icons.filter_list),
                  label: Text('Filtros'),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _mostrarEstadisticas(auditProvider),
                  icon: Icon(Icons.analytics),
                  label: Text('Estadísticas'),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Expanded(child: _buildListaAuditoria(auditProvider)),
        ],
      ),
    );
  }

  Widget _buildFiltrosCard(AuditProvider auditProvider) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            _buildFiltroFechas(),
            SizedBox(height: 16),
            _buildFiltroAccion(),
            SizedBox(height: 16),
            _buildFiltroRiesgo(),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _aplicarFiltros(auditProvider),
                    child: Text('Aplicar'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: () => _limpiarFiltros(auditProvider),
                    child: Text('Limpiar'),
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
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Estadísticas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            _buildEstadisticaItem('Total', estadisticas['total'], Colors.blue),
            _buildEstadisticaItem('Crítico', estadisticas['critico'], Colors.red),
            _buildEstadisticaItem('Alto', estadisticas['alto'], Colors.orange),
            _buildEstadisticaItem('Medio', estadisticas['medio'], Colors.yellow.shade700),
            _buildEstadisticaItem('Bajo', estadisticas['bajo'], Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadisticaItem(String label, int valor, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              valor.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
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
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: entry.colorNivelRiesgo.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: entry.colorNivelRiesgo.withOpacity(0.3)),
          ),
          child: Icon(
            entry.iconoNivelRiesgo,
            color: entry.colorNivelRiesgo,
          ),
        ),
        title: Text(
          entry.descripcion,
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${entry.usuarioNombre} • ${entry.fechaFormateada}'),
            if (entry.tieneAlertas) ...[
              SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: entry.alertas.map((alerta) => Chip(
                  label: Text(alerta, style: TextStyle(fontSize: 10)),
                  backgroundColor: Colors.red.shade50,
                  side: BorderSide(color: Colors.red.shade200),
                )).toList(),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: entry.colorNivelRiesgo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                entry.nombreNivelRiesgo,
                style: TextStyle(
                  color: entry.colorNivelRiesgo,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _mostrarDetalleEntry(entry),
      ),
    );
  }

  Widget _buildFiltroFechas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rango de Fechas', style: TextStyle(fontWeight: FontWeight.w500)),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _seleccionarFecha(true),
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _fechaInicio != null
                        ? DateFormat('dd/MM/yyyy').format(_fechaInicio!)
                        : 'Fecha inicio',
                    style: TextStyle(
                      color: _fechaInicio != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => _seleccionarFecha(false),
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _fechaFin != null
                        ? DateFormat('dd/MM/yyyy').format(_fechaFin!)
                        : 'Fecha fin',
                    style: TextStyle(
                      color: _fechaFin != null ? Colors.black : Colors.grey,
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
      {'value': 'crear_cancha', 'label': 'Crear Cancha'},
      {'value': 'editar_cancha', 'label': 'Editar Cancha'},
      {'value': 'crear_reserva_precio_personalizado', 'label': 'Reserva con Descuento'},
      {'value': 'cancelar_reserva_recurrente', 'label': 'Cancelar Recurrente'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Acción', style: TextStyle(fontWeight: FontWeight.w500)),
        SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _filtroAccion,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: acciones.map((accion) => DropdownMenuItem(
            value: accion['value'],
            child: Text(accion['label']!),
          )).toList(),
          onChanged: (value) => setState(() => _filtroAccion = value!),
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
        Text('Nivel de Riesgo', style: TextStyle(fontWeight: FontWeight.w500)),
        SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _filtroRiesgo,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: riesgos.map((riesgo) => DropdownMenuItem(
            value: riesgo['value'],
            child: Text(riesgo['label']!),
          )).toList(),
          onChanged: (value) => setState(() => _filtroRiesgo = value!),
        ),
      ],
    );
  }

  void _seleccionarFecha(bool esInicio) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now().add(Duration(days: 30)),
    );

    if (fecha != null) {
      setState(() {
        if (esInicio) {
          _fechaInicio = fecha;
        } else {
          _fechaFin = fecha;
        }
      });
    }
  }

  void _aplicarFiltros(AuditProvider auditProvider) {
    auditProvider.aplicarFiltros(
      fechaInicio: _fechaInicio,
      fechaFin: _fechaFin,
      accion: _filtroAccion,
      nivelRiesgo: _filtroRiesgo,
    );
  }

  void _limpiarFiltros(AuditProvider auditProvider) {
    setState(() {
      _fechaInicio = null;
      _fechaFin = null;
      _filtroAccion = 'todas';
      _filtroRiesgo = 'todos';
    });
    auditProvider.limpiarFiltros();
  }

  void _mostrarFiltros(AuditProvider auditProvider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(child: _buildFiltrosCard(auditProvider)),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarEstadisticas(AuditProvider auditProvider) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: 400,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(child: _buildEstadisticasCard(auditProvider)),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarAlertas() async {
    final auditProvider = context.read<AuditProvider>();
    final alertas = await auditProvider.obtenerAlertasNoLeidas();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Alertas Críticas (${alertas.length})'),
        content: Container(
          width: double.maxFinite,
          height: 400,
          child: alertas.isEmpty
              ? Center(child: Text('No hay alertas pendientes'))
              : ListView.builder(
                  itemCount: alertas.length,
                  itemBuilder: (context, index) {
                    final alerta = alertas[index];
                    return ListTile(
                      leading: Icon(Icons.error, color: Colors.red),
                      title: Text(alerta['titulo']),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(alerta['descripcion']),
                          SizedBox(height: 4),
                          Text(
                            'Usuario: ${alerta['usuario']}',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(
                              (alerta['timestamp'] as Timestamp).toDate()
                            ),
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      trailing: TextButton(
                        onPressed: () {
                          auditProvider.marcarAlertaLeida(alerta['id']);
                          Navigator.pop(context);
                          _mostrarAlertas(); // Recargar
                        },
                        child: Text('Marcar leída'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _mostrarDetalleEntry(AuditEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detalle de Auditoría'),
        content: Container(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetalleItem('Acción', entry.accion),
                _buildDetalleItem('Usuario', entry.usuarioNombre),
                _buildDetalleItem('Rol', entry.usuarioRol),
                _buildDetalleItem('Fecha', entry.fechaFormateada),
                _buildDetalleItem('Entidad', entry.entidad),
                _buildDetalleItem('ID Entidad', entry.entidadId),
                _buildDetalleItem('Nivel de Riesgo', entry.nombreNivelRiesgo),
                
                if (entry.cambiosDetectados.isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text('Cambios Detectados:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...entry.cambiosDetectados.map((cambio) => Padding(
                    padding: EdgeInsets.only(left: 16, top: 4),
                    child: Text('• $cambio'),
                  )),
                ],
                
                if (entry.alertas.isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text('Alertas:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...entry.alertas.map((alerta) => Padding(
                    padding: EdgeInsets.only(left: 16, top: 4),
                    child: Text('• $alerta', style: TextStyle(color: Colors.red)),
                  )),
                ],

                if (entry.metadatos.isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text('Información Adicional:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...entry.metadatos.entries.map((meta) => Padding(
                    padding: EdgeInsets.only(left: 16, top: 4),
                    child: Text('${meta.key}: ${meta.value}'),
                  )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalleItem(String label, String valor) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}