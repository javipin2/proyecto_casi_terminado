// lib/services/audit_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:reserva_canchas/models/audit_log.dart';
import 'package:reserva_canchas/models/alerta_critica.dart';
import 'package:reserva_canchas/services/anomaly_detector.dart';
import 'dart:developer' as developer;

class AuditService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AnomalyDetector _anomalyDetector = AnomalyDetector();

  // ✅ REGISTRAR LOG DE AUDITORÍA
  Future<void> registrarLog({
    required CategoriaLog categoria,
    required SeveridadLog severidad,
    required TipoAccion accion,
    required String usuarioId,
    required String usuarioNombre,
    required String descripcion,
    String? entidadId,
    String? entidadTipo,
    Map<String, dynamic> datosAnteriores = const {},
    Map<String, dynamic> datosNuevos = const {},
    Map<String, dynamic> metadatos = const {},
  }) async {
    try {
      final log = AuditLog(
        id: '',
        categoria: categoria,
        severidad: severidad,
        accion: accion,
        usuarioId: usuarioId,
        usuarioNombre: usuarioNombre,
        descripcion: descripcion,
        entidadId: entidadId,
        entidadTipo: entidadTipo,
        datosAnteriores: datosAnteriores,
        datosNuevos: datosNuevos,
        metadatos: metadatos,
        timestamp: DateTime.now(),
      );

      await _firestore.collection('audit_logs').add(log.toFirestore());

      // 🔍 ANALIZAR ANOMALÍAS EN TIEMPO REAL
      await _analizarYCrearAlertas(log);
      
      developer.log('✅ Log de auditoría registrado: ${log.descripcion}');
    } catch (e) {
      developer.log('🔥 Error al registrar log de auditoría: $e');
    }
  }

  // 🚨 CREAR ALERTA CRÍTICA
  Future<void> crearAlertaCritica({
    required TipoAlerta tipo,
    required NivelRiesgo nivelRiesgo,
    required String titulo,
    required String descripcion,
    required String usuarioId,
    required String usuarioNombre,
    String? entidadAfectada,
    Map<String, dynamic> detalles = const {},
    String? accionRecomendada,
  }) async {
    try {
      final alerta = AlertaCritica(
        id: '',
        tipo: tipo,
        nivelRiesgo: nivelRiesgo,
        titulo: titulo,
        descripcion: descripcion,
        usuarioId: usuarioId,
        usuarioNombre: usuarioNombre,
        entidadAfectada: entidadAfectada,
        detalles: detalles,
        timestamp: DateTime.now(),
        accionRecomendada: accionRecomendada,
      );

      await _firestore.collection('alertas_criticas').add(alerta.toFirestore());
      developer.log('🚨 Alerta crítica creada: $titulo');
    } catch (e) {
      developer.log('🔥 Error al crear alerta crítica: $e');
    }
  }

  // 🔍 ANALIZAR Y CREAR ALERTAS AUTOMÁTICAMENTE
  Future<void> _analizarYCrearAlertas(AuditLog log) async {
    // 1. DETECTAR PRECIOS ANÓMALOS
    if (log.categoria == CategoriaLog.precios || log.accion == TipoAccion.descuento_aplicado) {
      await _detectarPreciosAnomalos(log);
    }

    // 2. DETECTAR ELIMINACIONES MASIVAS
    if (log.accion == TipoAccion.eliminar) {
      await _detectarEliminacionesMasivas(log);
    }

    // 3. DETECTAR ACTIVIDAD SOSPECHOSA
    await _detectarActividadSospechosa(log);

    // 4. DETECTAR CAMBIOS CRÍTICOS
    if (log.severidad == SeveridadLog.critical) {
      await _detectarCambiosCriticos(log);
    }
  }

  // 💰 DETECTAR PRECIOS ANÓMALOS
  Future<void> _detectarPreciosAnomalos(AuditLog log) async {
    final esAnomaloPrecio = await _anomalyDetector.esPrecioAnomalo(
      log.datosNuevos,
      log.datosAnteriores,
      log.entidadId ?? '',
    );

    if (esAnomaloPrecio.esAnomalo) {
      await crearAlertaCritica(
        tipo: TipoAlerta.precio_anomalo,
        nivelRiesgo: esAnomaloPrecio.nivelRiesgo,
        titulo: 'Precio Anómalo Detectado',
        descripcion: esAnomaloPrecio.razon,
        usuarioId: log.usuarioId,
        usuarioNombre: log.usuarioNombre,
        entidadAfectada: log.entidadId,
        detalles: {
          'precio_anterior': log.datosAnteriores['valor'] ?? 0,
          'precio_nuevo': log.datosNuevos['valor'] ?? 0,
          'descuento_porcentaje': esAnomaloPrecio.porcentajeDescuento,
          'log_id': log.id,
        },
        accionRecomendada: 'Revisar justificación del precio y contactar al admin responsable',
      );
    }
  }

  // 🗑️ DETECTAR ELIMINACIONES MASIVAS
  Future<void> _detectarEliminacionesMasivas(AuditLog log) async {
    // Contar eliminaciones del usuario en los últimos 5 minutos
    final hace5Min = DateTime.now().subtract(const Duration(minutes: 5));
    
    final eliminacionesRecientes = await _firestore
        .collection('audit_logs')
        .where('usuarioId', isEqualTo: log.usuarioId)
        .where('accion', isEqualTo: TipoAccion.eliminar.name)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(hace5Min))
        .get();

    if (eliminacionesRecientes.docs.length >= 5) {
      await crearAlertaCritica(
        tipo: TipoAlerta.eliminacion_masiva,
        nivelRiesgo: NivelRiesgo.alto,
        titulo: 'Eliminación Masiva Detectada',
        descripcion: '${log.usuarioNombre} ha eliminado ${eliminacionesRecientes.docs.length} elementos en 5 minutos',
        usuarioId: log.usuarioId,
        usuarioNombre: log.usuarioNombre,
        detalles: {
          'cantidad_eliminaciones': eliminacionesRecientes.docs.length,
          'tiempo_transcurrido': '5 minutos',
        },
        accionRecomendada: 'Contactar inmediatamente al usuario para verificar las eliminaciones',
      );
    }
  }

  // 👤 DETECTAR ACTIVIDAD SOSPECHOSA
  Future<void> _detectarActividadSospechosa(AuditLog log) async {
    // Detectar actividad fuera de horario laboral
    final hora = log.timestamp.hour;
    if (hora < 6 || hora > 22) {
      await crearAlertaCritica(
        tipo: TipoAlerta.actividad_inusual,
        nivelRiesgo: NivelRiesgo.medio,
        titulo: 'Actividad Fuera de Horario',
        descripcion: '${log.usuarioNombre} realizó "${log.descripcion}" a las ${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}',
        usuarioId: log.usuarioId,
        usuarioNombre: log.usuarioNombre,
        detalles: {
          'hora': '${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}',
          'accion': log.accionTexto,
        },
        accionRecomendada: 'Verificar si es actividad autorizada',
      );
    }

    // Detectar múltiples acciones en poco tiempo
    final hace1Min = DateTime.now().subtract(const Duration(minutes: 1));
    final accionesRecientes = await _firestore
        .collection('audit_logs')
        .where('usuarioId', isEqualTo: log.usuarioId)
        .where('timestamp', isGreaterThan: Timestamp.fromDate(hace1Min))
        .get();

    if (accionesRecientes.docs.length >= 10) {
      await crearAlertaCritica(
        tipo: TipoAlerta.actividad_inusual,
        nivelRiesgo: NivelRiesgo.alto,
        titulo: 'Actividad Excesivamente Rápida',
        descripcion: '${log.usuarioNombre} realizó ${accionesRecientes.docs.length} acciones en 1 minuto',
        usuarioId: log.usuarioId,
        usuarioNombre: log.usuarioNombre,
        detalles: {
          'cantidad_acciones': accionesRecientes.docs.length,
          'tiempo_transcurrido': '1 minuto',
        },
        accionRecomendada: 'Posible uso de scripts automatizados - verificar inmediatamente',
      );
    }
  }

  // ⚠️ DETECTAR CAMBIOS CRÍTICOS
  Future<void> _detectarCambiosCriticos(AuditLog log) async {
    await crearAlertaCritica(
      tipo: TipoAlerta.cambio_critico,
      nivelRiesgo: NivelRiesgo.critico,
      titulo: 'Cambio Crítico en el Sistema',
      descripcion: log.descripcion,
      usuarioId: log.usuarioId,
      usuarioNombre: log.usuarioNombre,
      entidadAfectada: log.entidadId,
      detalles: {
        'categoria': log.categoria.name,
        'datos_anteriores': log.datosAnteriores,
        'datos_nuevos': log.datosNuevos,
        'log_id': log.id,
      },
      accionRecomendada: 'Revisión inmediata requerida',
    );
  }

  // 📊 OBTENER ESTADÍSTICAS SOSPECHOSAS
  Future<Map<String, dynamic>> obtenerEstadisticasSospechosas() async {
    final ahora = DateTime.now();
    final hace24h = ahora.subtract(const Duration(hours: 24));
    final hace7d = ahora.subtract(const Duration(days: 7));

    try {
      // Contar logs críticos en las últimas 24h
      final logsCriticos24h = await _firestore
          .collection('audit_logs')
          .where('severidad', isEqualTo: SeveridadLog.critical.name)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(hace24h))
          .get();

      // Contar alertas no leídas
      final alertasNoLeidas = await _firestore
          .collection('alertas_criticas')
          .where('leida', isEqualTo: false)
          .get();

      // Contar eliminaciones en la última semana
      final eliminaciones7d = await _firestore
          .collection('audit_logs')
          .where('accion', isEqualTo: TipoAccion.eliminar.name)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(hace7d))
          .get();

      // Contar descuentos aplicados en la última semana
      final descuentos7d = await _firestore
          .collection('audit_logs')
          .where('accion', isEqualTo: TipoAccion.descuento_aplicado.name)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(hace7d))
          .get();

      // Obtener usuarios más activos
      final usuariosActivos = await _obtenerUsuariosMasActivos();

      return {
        'Logs Críticos (24h)': logsCriticos24h.docs.length,
        'Alertas Pendientes': alertasNoLeidas.docs.length,
        'Eliminaciones (7d)': eliminaciones7d.docs.length,
        'Descuentos Aplicados (7d)': descuentos7d.docs.length,
        'Usuario Más Activo': usuariosActivos['mas_activo'] ?? 'N/A',
        'Acciones del Más Activo': usuariosActivos['cantidad_acciones'] ?? 0,
      };
    } catch (e) {
      developer.log('🔥 Error al obtener estadísticas: $e');
      return {
        'Error': 'No se pudieron cargar las estadísticas',
      };
    }
  }

  // 👥 OBTENER USUARIOS MÁS ACTIVOS
  Future<Map<String, dynamic>> _obtenerUsuariosMasActivos() async {
    final hace24h = DateTime.now().subtract(const Duration(hours: 24));
    
    try {
      final logs = await _firestore
          .collection('audit_logs')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(hace24h))
          .get();

      final Map<String, int> conteoUsuarios = {};
      final Map<String, String> nombresUsuarios = {};

      for (final doc in logs.docs) {
        final data = doc.data();
        final usuarioId = data['usuarioId'] ?? '';
        final usuarioNombre = data['usuarioNombre'] ?? 'Desconocido';
        
        if (usuarioId.isNotEmpty) {
          conteoUsuarios[usuarioId] = (conteoUsuarios[usuarioId] ?? 0) + 1;
          nombresUsuarios[usuarioId] = usuarioNombre;
        }
      }

      if (conteoUsuarios.isEmpty) {
        return {'mas_activo': 'Ninguno', 'cantidad_acciones': 0};
      }

      final usuarioMasActivo = conteoUsuarios.entries
          .reduce((a, b) => a.value > b.value ? a : b);

      return {
        'mas_activo': nombresUsuarios[usuarioMasActivo.key] ?? 'Desconocido',
        'cantidad_acciones': usuarioMasActivo.value,
      };
    } catch (e) {
      developer.log('🔥 Error al obtener usuarios más activos: $e');
      return {'mas_activo': 'Error', 'cantidad_acciones': 0};
    }
  }

  // 🧹 LIMPIAR LOGS ANTIGUOS (más de 90 días)
  Future<void> limpiarLogsAntiguos() async {
    final hace90Dias = DateTime.now().subtract(const Duration(days: 90));
    
    try {
      final batch = _firestore.batch();
      final logsAntiguos = await _firestore
          .collection('audit_logs')
          .where('timestamp', isLessThan: Timestamp.fromDate(hace90Dias))
          .get();

      for (final doc in logsAntiguos.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      
      // Registrar la limpieza
      await registrarLog(
        categoria: CategoriaLog.sistema,
        severidad: SeveridadLog.info,
        accion: TipoAccion.eliminar,
        usuarioId: 'SYSTEM',
        usuarioNombre: 'Sistema',
        descripcion: 'Limpieza automática de logs antiguos (${logsAntiguos.docs.length} logs eliminados)',
        metadatos: {
          'cantidad_eliminados': logsAntiguos.docs.length,
          'fecha_limite': DateFormat('yyyy-MM-dd').format(hace90Dias),
        },
      );

      developer.log('🧹 ${logsAntiguos.docs.length} logs antiguos eliminados');
    } catch (e) {
      developer.log('🔥 Error al limpiar logs antiguos: $e');
      throw e;
    }
  }

  // 📄 OBTENER LOGS CON FILTROS
  Future<List<AuditLog>> obtenerLogs({
    CategoriaLog? categoria,
    SeveridadLog? severidad,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    String? usuarioId,
    int limite = 100,
  }) async {
    try {
      Query query = _firestore.collection('audit_logs');

      if (categoria != null) {
        query = query.where('categoria', isEqualTo: categoria.name);
      }

      if (severidad != null) {
        query = query.where('severidad', isEqualTo: severidad.name);
      }

      if (usuarioId != null && usuarioId.isNotEmpty) {
        query = query.where('usuarioId', isEqualTo: usuarioId);
      }

      if (fechaInicio != null) {
        query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(fechaInicio));
      }

      if (fechaFin != null) {
        query = query.where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(fechaFin));
      }

      query = query.orderBy('timestamp', descending: true).limit(limite);

      final snapshot = await query.get();
      return snapshot.docs.map((doc) => AuditLog.fromFirestore(doc)).toList();
    } catch (e) {
      developer.log('🔥 Error al obtener logs: $e');
      return [];
    }
  }

  // 📊 OBTENER ALERTAS CRÍTICAS
  Future<List<AlertaCritica>> obtenerAlertasCriticas({
    bool? soloNoLeidas,
    NivelRiesgo? nivelMinimo,
    int limite = 50,
  }) async {
    try {
      Query query = _firestore.collection('alertas_criticas');

      if (soloNoLeidas == true) {
        query = query.where('leida', isEqualTo: false);
      }

      if (nivelMinimo != null) {
        // Para filtrar por nivel mínimo, necesitaríamos un campo numérico
        // Por simplicidad, filtraremos en el cliente
      }

      query = query.orderBy('timestamp', descending: true).limit(limite);

      final snapshot = await query.get();
      var alertas = snapshot.docs.map((doc) => AlertaCritica.fromFirestore(doc)).toList();

      // Filtrar por nivel mínimo si se especifica
      if (nivelMinimo != null) {
        final nivelIndex = NivelRiesgo.values.indexOf(nivelMinimo);
        alertas = alertas.where((alerta) => 
          NivelRiesgo.values.indexOf(alerta.nivelRiesgo) >= nivelIndex).toList();
      }

      return alertas;
    } catch (e) {
      developer.log('🔥 Error al obtener alertas críticas: $e');
      return [];
    }
  }

  // ✅ MARCAR ALERTA COMO LEÍDA
  Future<void> marcarAlertaComoLeida(String alertaId) async {
    try {
      await _firestore
          .collection('alertas_criticas')
          .doc(alertaId)
          .update({'leida': true});
    } catch (e) {
      developer.log('🔥 Error al marcar alerta como leída: $e');
    }
  }
}