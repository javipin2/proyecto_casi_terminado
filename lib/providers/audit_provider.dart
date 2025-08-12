// lib/providers/audit_provider.dart
import 'package:flutter/material.dart';
import 'package:reserva_canchas/models/audit_log.dart';
import 'package:reserva_canchas/models/alerta_critica.dart';
import 'package:reserva_canchas/services/audit_service.dart';

class AuditProvider with ChangeNotifier {
  final AuditService _auditService = AuditService();
  
  List<AuditLog> _logs = [];
  List<AlertaCritica> _alertas = [];
  bool _isLoading = false;
  String? _error;
  
  // Filtros activos
  CategoriaLog? _categoriaFiltro;
  SeveridadLog? _severidadFiltro;
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  String? _usuarioFiltro;

  // Getters
  List<AuditLog> get logs => _logs;
  List<AlertaCritica> get alertas => _alertas;
  bool get isLoading => _isLoading;
  String? get error => _error;
  CategoriaLog? get categoriaFiltro => _categoriaFiltro;
  SeveridadLog? get severidadFiltro => _severidadFiltro;
  DateTime? get fechaInicio => _fechaInicio;
  DateTime? get fechaFin => _fechaFin;
  String? get usuarioFiltro => _usuarioFiltro;

  // 📥 CARGAR LOGS RECIENTES
  Future<void> cargarLogsRecientes() async {
    _setLoading(true);
    try {
      _logs = await _auditService.obtenerLogs(limite: 200);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // 📥 CARGAR LOGS CON FILTROS
  Future<void> cargarLogs({
    CategoriaLog? categoria,
    SeveridadLog? severidad,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    String? usuarioId,
  }) async {
    _setLoading(true);
    try {
      _categoriaFiltro = categoria;
      _severidadFiltro = severidad;
      _fechaInicio = fechaInicio;
      _fechaFin = fechaFin;
      _usuarioFiltro = usuarioId;

      _logs = await _auditService.obtenerLogs(
        categoria: categoria,
        severidad: severidad,
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
        usuarioId: usuarioId,
        limite: 200,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // 🚨 CARGAR ALERTAS CRÍTICAS
  Future<void> cargarAlertas({bool soloNoLeidas = true}) async {
    try {
      _alertas = await _auditService.obtenerAlertasCriticas(
        soloNoLeidas: soloNoLeidas,
        limite: 100,
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // ✅ MARCAR ALERTA COMO LEÍDA
  Future<void> marcarAlertaLeida(String alertaId) async {
    try {
      await _auditService.marcarAlertaComoLeida(alertaId);
      final index = _alertas.indexWhere((a) => a.id == alertaId);
      if (index != -1) {
        _alertas.removeAt(index);
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // 🧹 LIMPIAR LOGS ANTIGUOS
  Future<void> limpiarLogsAntiguos() async {
    _setLoading(true);
    try {
      await _auditService.limpiarLogsAntiguos();
      await cargarLogsRecientes(); // Recargar después de limpiar
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // 📄 EXPORTAR LOGS A CSV
  String exportarLogsCSV() {
    final header = 'Timestamp,Categoria,Severidad,Accion,Usuario,Descripcion,Entidad ID,Datos Anteriores,Datos Nuevos\n';
    final rows = _logs.map((log) {
      return '${log.fechaFormateada},${log.categoria.name},${log.severidad.name},${log.accionTexto},"${log.usuarioNombre}","${log.descripcion}",${log.entidadId ?? ''},"${log.datosAnteriores}","${log.datosNuevos}"';
    }).join('\n');
    
    return header + rows;
  }

  // 🔄 LIMPIAR FILTROS
  void limpiarFiltros() {
    _categoriaFiltro = null;
    _severidadFiltro = null;
    _fechaInicio = null;
    _fechaFin = null;
    _usuarioFiltro = null;
    cargarLogsRecientes();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
}