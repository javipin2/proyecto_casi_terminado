// lib/providers/audit_provider_mejorado.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:reserva_canchas/models/audit_log.dart';

class AuditProvider with ChangeNotifier {
  List<AuditEntry> _auditEntries = [];
  bool _isLoading = false;
  String _errorMessage = '';
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  String _filtroAccion = 'todas';
  String _filtroRiesgo = 'todos';
  String _filtroUsuario = 'todos';

  // Cache para optimización
  Map<String, dynamic>? _estadisticasCache;
  DateTime? _ultimaActualizacionCache;

  // Getters
  List<AuditEntry> get auditEntries => _auditEntries;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  DateTime? get fechaInicio => _fechaInicio;
  DateTime? get fechaFin => _fechaFin;
  String get filtroAccion => _filtroAccion;
  String get filtroRiesgo => _filtroRiesgo;
  String get filtroUsuario => _filtroUsuario;

  // Filtros aplicados con mejor rendimiento
  List<AuditEntry> get entriesFiltradas {
    List<AuditEntry> filtradas = List.from(_auditEntries);

    // Aplicar filtros en orden de selectividad
    if (_filtroRiesgo != 'todos') {
      filtradas = filtradas.where((entry) => entry.nivelRiesgo == _filtroRiesgo).toList();
    }

    if (_filtroAccion != 'todas') {
      filtradas = filtradas.where((entry) => entry.accion == _filtroAccion).toList();
    }

    if (_filtroUsuario != 'todos') {
      filtradas = filtradas.where((entry) => entry.usuarioId == _filtroUsuario).toList();
    }

    if (_fechaInicio != null && _fechaFin != null) {
      filtradas = filtradas.where((entry) {
        final fecha = entry.timestamp.toDate();
        return fecha.isAfter(_fechaInicio!.subtract(Duration(days: 1))) &&
               fecha.isBefore(_fechaFin!.add(Duration(days: 1)));
      }).toList();
    }

    return filtradas;
  }

  // Estadísticas mejoradas con cache
  Map<String, dynamic> get estadisticas {
    // Verificar cache
    if (_estadisticasCache != null && 
        _ultimaActualizacionCache != null &&
        DateTime.now().difference(_ultimaActualizacionCache!).inMinutes < 5) {
      return _estadisticasCache!;
    }

    final entries = entriesFiltradas;
    final estadisticasCalculadas = {
      'total': entries.length,
      'critico': entries.where((e) => e.nivelRiesgo == 'critico').length,
      'alto': entries.where((e) => e.nivelRiesgo == 'alto').length,
      'medio': entries.where((e) => e.nivelRiesgo == 'medio').length,
      'bajo': entries.where((e) => e.nivelRiesgo == 'bajo').length,
      'porAccion': _agruparPorAccion(entries),
      'porUsuario': _agruparPorUsuario(entries),
      'porFecha': _agruparPorFecha(entries),
      'tendencias': _calcularTendencias(entries),
      'alertasActivas': entries.where((e) => e.tieneAlertas).length,
      'impactoFinanciero': _calcularImpactoFinanciero(entries),
    };

    _estadisticasCache = estadisticasCalculadas;
    _ultimaActualizacionCache = DateTime.now();

    return estadisticasCalculadas;
  }

  /// Cargar auditoría con filtros mejorados
  Future<void> cargarAuditoria({
    int limite = 200,
    bool forzarRecarga = false,
  }) async {
    if (_isLoading && !forzarRecarga) return;

    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      Query query = FirebaseFirestore.instance
          .collection('auditoria')
          .orderBy('timestamp', descending: true);

      // Aplicar filtros en la consulta para mejor rendimiento
      if (_filtroRiesgo != 'todos') {
        query = query.where('nivel_riesgo', isEqualTo: _filtroRiesgo);
      }

      if (_fechaInicio != null && _fechaFin != null) {
        query = query
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_fechaInicio!))
            .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(_fechaFin!.add(Duration(days: 1))));
      }

      query = query.limit(limite);

      final querySnapshot = await query.get();
      _auditEntries = querySnapshot.docs
          .map((doc) => AuditEntry.fromFirestore(doc))
          .toList();

      // Invalidar cache de estadísticas
      _estadisticasCache = null;

    } catch (e) {
      _errorMessage = 'Error al cargar auditoría: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Aplicar filtros con validación
  void aplicarFiltros({
    DateTime? fechaInicio,
    DateTime? fechaFin,
    String? accion,
    String? nivelRiesgo,
    String? usuario,
  }) {
    // Validar fechas
    if (fechaInicio != null && fechaFin != null && fechaInicio.isAfter(fechaFin)) {
      _errorMessage = 'La fecha de inicio no puede ser posterior a la fecha fin';
      notifyListeners();
      return;
    }

    _fechaInicio = fechaInicio;
    _fechaFin = fechaFin;
    _filtroAccion = accion ?? 'todas';
    _filtroRiesgo = nivelRiesgo ?? 'todos';
    _filtroUsuario = usuario ?? 'todos';

    // Invalidar cache
    _estadisticasCache = null;

    notifyListeners();
  }

  /// Limpiar filtros
  void limpiarFiltros() {
    _fechaInicio = null;
    _fechaFin = null;
    _filtroAccion = 'todas';
    _filtroRiesgo = 'todos';
    _filtroUsuario = 'todos';
    _estadisticasCache = null;
    notifyListeners();
  }

  /// MÉTODO PRINCIPAL MEJORADO - Registrar acción con análisis avanzado
  static Future<void> registrarAccion({
  required String accion,
  required String entidad,
  required String entidadId,
  Map<String, dynamic>? datosAntiguos,
  Map<String, dynamic>? datosNuevos,
  Map<String, dynamic>? metadatos,
  String? descripcion,
  String? nivelRiesgoForzado,
}) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Obtener datos del usuario con cache
    final userData = await _obtenerDatosUsuario(user.uid);

    // DECISIÓN CLAVE: Si es una auditoría de reservas que viene de ReservaAuditUtils,
    // NO hacer análisis duplicado
    final esAuditoriaReserva = entidad.contains('reserva') && 
                             accion.contains('editar_reserva') &&
                             metadatos?.containsKey('metodo_edicion') == true;

    Map<String, dynamic> analisisRiesgo;
    String nivelRiesgoFinal;
    String descripcionFinal;
    
    if (esAuditoriaReserva) {
      // Para reservas: usar datos que vienen de ReservaAuditUtils
      analisisRiesgo = _extraerAnalisisDeMetadatos(metadatos, datosAntiguos, datosNuevos);
      nivelRiesgoFinal = nivelRiesgoForzado ?? analisisRiesgo['nivel'];
      descripcionFinal = descripcion ?? _generarDescripcionBasica(accion, entidad, datosNuevos);
    } else {
      // Para otras entidades: usar análisis completo original
      analisisRiesgo = _analizarRiesgoMejorado(
        accion: accion,
        entidad: entidad,
        datosAntiguos: datosAntiguos,
        datosNuevos: datosNuevos,
        metadatos: metadatos,
      );
      nivelRiesgoFinal = nivelRiesgoForzado ?? analisisRiesgo['nivel'];
      descripcionFinal = descripcion ?? _generarDescripcionMejorada(
        accion: accion,
        entidad: entidad,
        datosAntiguos: datosAntiguos,
        datosNuevos: datosNuevos,
        metadatos: metadatos,
        analisisRiesgo: analisisRiesgo,
      );
    }

    // Obtener información de contexto
    final contextoAdicional = await _obtenerContextoAdicional(accion, entidad, entidadId);

    final auditEntry = {
      'accion': accion,
      'entidad': entidad,
      'entidad_id': entidadId,
      'usuario_id': user.uid,
      'usuario_nombre': userData['nombre'],
      'usuario_rol': userData['rol'],
      'timestamp': Timestamp.now(),
      'datos_antiguos': datosAntiguos ?? {},
      'datos_nuevos': datosNuevos ?? {},
      'metadatos': {
        ...metadatos ?? {},
        ...contextoAdicional,
        'version_sistema': '2.0',
        'fuente_analisis': esAuditoriaReserva ? 'ReservaAuditUtils' : 'AuditProvider',
      },
      'descripcion': descripcionFinal,
      'nivel_riesgo': nivelRiesgoFinal,
      'alertas': analisisRiesgo['alertas'] ?? [],
      'cambios_detectados': analisisRiesgo['cambios'] ?? [],
      'puntuacion_riesgo': analisisRiesgo['puntuacion_riesgo'] ?? 0,
      'ip_address': await _obtenerIP(),
      'user_agent': 'Flutter App v2.0',
      'dispositivo_info': await _obtenerInfoDispositivo(),
    };

    // Guardar en Firestore
    final docRef = await FirebaseFirestore.instance
        .collection('auditoria')
        .add(auditEntry);

    // Procesar alertas críticas
    if (nivelRiesgoFinal == 'critico') {
      await _procesarAlertaCritica(auditEntry, docRef.id);
    }

    debugPrint('✅ Auditoría registrada: $accion [${nivelRiesgoFinal.toUpperCase()}] - Fuente: ${esAuditoriaReserva ? 'ReservaAuditUtils' : 'AuditProvider'}');

  } catch (e) {
    debugPrint('❌ Error registrando auditoría: $e');
  }
}



static Map<String, dynamic> _extraerAnalisisDeMetadatos(
  Map<String, dynamic>? metadatos,
  Map<String, dynamic>? datosAntiguos,
  Map<String, dynamic>? datosNuevos,
) {
  if (metadatos == null) {
    return {'nivel': 'bajo', 'alertas': <String>[], 'cambios': <String>[], 'puntuacion_riesgo': 0};
  }

  // Extraer información del análisis ya realizado en ReservaAuditUtils
  final List<String> alertas = [];
  final List<String> cambios = [];
  int puntuacionRiesgo = 0;
  String nivelRiesgo = 'bajo';

  // Buscar información de cambios en contexto financiero
  if (metadatos.containsKey('contexto_financiero')) {
    final contexto = metadatos['contexto_financiero'] as Map<String, dynamic>?;
    if (contexto != null) {
      final diferenciaPrecio = (contexto['diferencia_precio'] as num?)?.toDouble() ?? 0;
      final esAumento = contexto['es_aumento'] as bool? ?? false;
      final esDescuento = contexto['es_descuento'] as bool? ?? false;

      if (diferenciaPrecio != 0) {
        final precioAnterior = _extraerPrecio(datosAntiguos!) ?? 0;
        final porcentaje = precioAnterior > 0 ? (diferenciaPrecio.abs() / precioAnterior * 100) : 0;
        
        final formatter = NumberFormat('#,##0', 'es_CO');
        final direccion = esAumento ? '↗️' : '↘️';
        cambios.add('Precio modificado: ${esAumento ? 'Aumento' : 'Descuento'} de \$${formatter.format(diferenciaPrecio.abs())} $direccion');

        // Determinar nivel de riesgo basado en porcentaje (usando la misma lógica de tu interfaz)
        if (porcentaje >= 70) {
          alertas.add('🚨 CAMBIO DE PRECIO EXTREMO: ${porcentaje.toStringAsFixed(1)}%');
          puntuacionRiesgo = 90;
          nivelRiesgo = 'critico';
        } else if (porcentaje >= 50) {
          alertas.add('🔴 CAMBIO DE PRECIO CRÍTICO: ${porcentaje.toStringAsFixed(1)}%');
          puntuacionRiesgo = 80;
          nivelRiesgo = 'critico';
        } else if (porcentaje >= 30) {
          alertas.add('🟠 Cambio de precio significativo: ${porcentaje.toStringAsFixed(1)}%');
          puntuacionRiesgo = 65;
          nivelRiesgo = 'alto';
        } else if (porcentaje >= 15) {
          alertas.add('🟡 Cambio de precio moderado: ${porcentaje.toStringAsFixed(1)}%');
          puntuacionRiesgo = 40;
          nivelRiesgo = 'medio';
        } else if (porcentaje > 0) {
          alertas.add('🔵 Cambio de precio menor: ${porcentaje.toStringAsFixed(1)}%');
          puntuacionRiesgo = 15;
          nivelRiesgo = 'bajo';
        }
      }
    }
  }

  // Agregar otros cambios detectados si los hay
  if (datosAntiguos != null && datosNuevos != null) {
    if (datosAntiguos['nombre'] != datosNuevos['nombre']) {
      cambios.add('Cliente modificado');
    }
    if (datosAntiguos['telefono'] != datosNuevos['telefono']) {
      cambios.add('Teléfono actualizado');
    }
    if (datosAntiguos['fecha'] != datosNuevos['fecha']) {
      cambios.add('Fecha modificada');
      puntuacionRiesgo += 10; // Incrementar un poco el riesgo
    }
    if (datosAntiguos['horario'] != datosNuevos['horario']) {
      cambios.add('Horario modificado');
      puntuacionRiesgo += 5;
    }
  }

  // Ajustar nivel de riesgo final basado en puntuación actualizada
  if (nivelRiesgo == 'bajo' && puntuacionRiesgo > 0) {
    if (puntuacionRiesgo >= 70) nivelRiesgo = 'critico';
    else if (puntuacionRiesgo >= 45) nivelRiesgo = 'alto';
    else if (puntuacionRiesgo >= 25) nivelRiesgo = 'medio';
  }

  // Verificar información de reserva para alertas adicionales
  if (metadatos.containsKey('informacion_reserva')) {
    final infoReserva = metadatos['informacion_reserva'] as Map<String, dynamic>?;
    if (infoReserva != null) {
      if (infoReserva['es_reserva_proxima'] == true) {
        alertas.add('⏰ Modificación en reserva próxima');
        puntuacionRiesgo += 10;
      }
      if (infoReserva['horario_peak'] == true) {
        alertas.add('🕐 Reserva en horario peak');
      }
      if (infoReserva['fin_de_semana'] == true) {
        alertas.add('📅 Reserva en fin de semana');
      }
    }
  }

  return {
    'nivel': nivelRiesgo,
    'alertas': alertas,
    'cambios': cambios,
    'puntuacion_riesgo': puntuacionRiesgo,
  };
}

/// Generar descripción básica para reservas (ya viene analizada)
static String _generarDescripcionBasica(
  String accion, 
  String entidad, 
  Map<String, dynamic>? datosNuevos,
) {
  final cliente = datosNuevos?['nombre'] ?? 'Cliente';
  
  switch (accion) {
    case 'editar_reserva':
    case 'editar_reserva_precio_critico':
      return 'Reserva de $cliente editada desde registro';
    default:
      return 'Acción $accion realizada';
  }
}





  /// Análisis de riesgo mejorado con múltiples factores
  static Map<String, dynamic> _analizarRiesgoMejorado({
  required String accion,
  required String entidad,
  Map<String, dynamic>? datosAntiguos,
  Map<String, dynamic>? datosNuevos,
  Map<String, dynamic>? metadatos,
}) {
  // Solo usar este método para entidades que NO sean reservas
  if (entidad.contains('reserva')) {
    return {'nivel': 'bajo', 'alertas': <String>[], 'cambios': <String>[], 'puntuacion_riesgo': 0};
  }

  // AQUÍ VA TU MÉTODO ORIGINAL COMPLETO para otras entidades
  num puntuacionRiesgo = 0;
  List<String> alertas = [];
  List<String> cambios = [];

  // 1. Análisis por tipo de acción (peso base: 20 puntos)
  puntuacionRiesgo += _analizarRiesgoPorAccion(accion, alertas);

  // 2. Análisis de cambios de datos (peso: 40 puntos)
  if (datosAntiguos != null && datosNuevos != null) {
    final analisisCambios = _analizarCambiosDatos(datosAntiguos, datosNuevos);
    puntuacionRiesgo += analisisCambios['puntuacion'];
    alertas.addAll(analisisCambios['alertas']);
    cambios.addAll(analisisCambios['cambios']);
  }

  // 3. Análisis de contexto temporal (peso: 15 puntos)
  puntuacionRiesgo += _analizarContextoTemporal(metadatos, alertas);

  // 4. Análisis de patrones de usuario (peso: 15 puntos)
  puntuacionRiesgo += _analizarPatronesUsuario(accion, alertas);

  // 5. Análisis de impacto financiero (peso: 10 puntos)
  puntuacionRiesgo += _analizarImpactoFinanciero(datosAntiguos, datosNuevos, alertas);

  // Determinar nivel de riesgo basado en puntuación
  String nivelRiesgo;
  if (puntuacionRiesgo >= 80) nivelRiesgo = 'critico';
  else if (puntuacionRiesgo >= 60) nivelRiesgo = 'alto';
  else if (puntuacionRiesgo >= 35) nivelRiesgo = 'medio';
  else nivelRiesgo = 'bajo';

  return {
    'nivel': nivelRiesgo,
    'alertas': alertas,
    'cambios': cambios,
    'puntuacion_riesgo': puntuacionRiesgo,
    'factores_analizados': {
      'accion': true,
      'cambios_datos': datosAntiguos != null && datosNuevos != null,
      'contexto_temporal': true,
      'patrones_usuario': true,
      'impacto_financiero': true,
    },
  };
}



  /// Análisis de riesgo por tipo de acción
  static int _analizarRiesgoPorAccion(String accion, List<String> alertas) {
    switch (accion) {
      case 'eliminar_reserva':
      case 'eliminar_reserva_impacto_alto':
        alertas.add('Eliminación de reserva detectada');
        return 25;
      
      case 'editar_reserva_precio_critico':
      case 'crear_reserva_descuento_alto':
        alertas.add('Operación financiera crítica');
        return 30;
      
      case 'cancelar_reserva_recurrente':
      case 'eliminar_reserva_masivo':
        alertas.add('Operación masiva detectada');
        return 20;
      
      case 'editar_precio_reserva_recurrente':
        alertas.add('Modificación de precio en reserva recurrente');
        return 25;
        
      case 'crear_reserva_sospechosa':
        alertas.add('Patrones sospechosos en creación');
        return 35;
      
      case 'crear_reserva_precio_personalizado':
      case 'editar_reserva':
        return 10;
      
      default:
        return 5;
    }
  }

  /// Análisis de cambios en datos
  static Map<String, dynamic> _analizarCambiosDatos(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
  ) {
    int puntuacion = 0;
    List<String> alertas = [];
    List<String> cambios = [];

    // Análisis de cambios de precio
    final precioAnterior = _extraerPrecio(datosAntiguos);
    final precioNuevo = _extraerPrecio(datosNuevos);
    
    if (precioAnterior != null && precioNuevo != null && precioAnterior != precioNuevo) {
      final diferencia = precioNuevo - precioAnterior;
      final porcentaje = precioAnterior > 0 ? (diferencia / precioAnterior * 100).abs() : 0;
      
      cambios.add('Precio: ${NumberFormat('#,##0', 'es_CO').format(precioAnterior)} → ${NumberFormat('#,##0', 'es_CO').format(precioNuevo)}');
      
      if (porcentaje >= 70) {
        alertas.add('CAMBIO DE PRECIO EXTREMO: ${porcentaje.toStringAsFixed(1)}%');
        puntuacion += 40;
      } else if (porcentaje >= 50) {
        alertas.add('Cambio de precio crítico: ${porcentaje.toStringAsFixed(1)}%');
        puntuacion += 35;
      } else if (porcentaje >= 30) {
        alertas.add('Cambio de precio significativo: ${porcentaje.toStringAsFixed(1)}%');
        puntuacion += 25;
      } else if (porcentaje >= 15) {
        alertas.add('Cambio de precio moderado: ${porcentaje.toStringAsFixed(1)}%');
        puntuacion += 15;
      } else {
        puntuacion += 5;
      }
    }

    // Análisis de otros cambios importantes
    final camposImportantes = ['fecha', 'horario', 'cancha_id', 'sede'];
    int cambiosImportantes = 0;
    
    for (String campo in camposImportantes) {
      if (datosAntiguos[campo] != datosNuevos[campo]) {
        cambiosImportantes++;
        cambios.add('$campo modificado');
      }
    }
    
    if (cambiosImportantes >= 3) {
      alertas.add('MÚLTIPLES CAMBIOS SIMULTÁNEOS: $cambiosImportantes');
      puntuacion += 20;
    } else if (cambiosImportantes >= 2) {
      alertas.add('Cambios múltiples detectados');
      puntuacion += 10;
    }

    return {
      'puntuacion': puntuacion,
      'alertas': alertas,
      'cambios': cambios,
    };
  }

  /// Análisis de contexto temporal
  static int _analizarContextoTemporal(Map<String, dynamic>? metadatos, List<String> alertas) {
    int puntuacion = 0;
    final ahora = DateTime.now();
    
    // Operaciones fuera de horario laboral
    if (ahora.hour < 6 || ahora.hour > 23) {
      alertas.add('Operación fuera de horario laboral');
      puntuacion += 10;
    }
    
    // Operaciones en días festivos o fines de semana
    if (ahora.weekday == DateTime.saturday || ahora.weekday == DateTime.sunday) {
      alertas.add('Operación en fin de semana');
      puntuacion += 5;
    }
    
    // Verificar proximidad de fecha de reserva si está disponible
    if (metadatos != null && metadatos.containsKey('fecha_reserva')) {
      try {
        final fechaReserva = DateTime.parse(metadatos['fecha_reserva'].toString());
        final diferencia = fechaReserva.difference(ahora).inDays;
        
        if (diferencia <= 0) {
          alertas.add('Modificación de reserva para fecha pasada o hoy');
          puntuacion += 15;
        } else if (diferencia == 1) {
          alertas.add('Modificación de reserva para mañana');
          puntuacion += 10;
        }
      } catch (e) {
        // Ignorar errores de parsing
      }
    }
    
    return puntuacion;
  }

  /// Análisis de patrones de usuario
  static int _analizarPatronesUsuario(String accion, List<String> alertas) {
    // Este sería un análisis más complejo en producción
    // Por ahora, implementación básica
    
    // Verificar si son muchas operaciones del mismo tipo en poco tiempo
    // (Esto requeriría consultar el historial, implementación simplificada)
    return 0;
  }

  /// Análisis de impacto financiero
  static int _analizarImpactoFinanciero(
    Map<String, dynamic>? datosAntiguos,
    Map<String, dynamic>? datosNuevos,
    List<String> alertas,
  ) {
    int puntuacion = 0;
    
    if (datosAntiguos != null && datosNuevos != null) {
      final precioAnterior = _extraerPrecio(datosAntiguos) ?? 0;
      final precioNuevo = _extraerPrecio(datosNuevos) ?? 0;
      final diferencia = (precioNuevo - precioAnterior).abs();
      
      if (diferencia >= 100000) {
        alertas.add('ALTO IMPACTO FINANCIERO: ${NumberFormat('#,##0', 'es_CO').format(diferencia)}');
        puntuacion += 10;
      } else if (diferencia >= 50000) {
        alertas.add('Impacto financiero significativo');
        puntuacion += 5;
      }
    }
    
    return puntuacion;
  }

  /// Generar descripción mejorada
  static String _generarDescripcionMejorada({
    required String accion,
    required String entidad,
    Map<String, dynamic>? datosAntiguos,
    Map<String, dynamic>? datosNuevos,
    Map<String, dynamic>? metadatos,
    Map<String, dynamic>? analisisRiesgo,
  }) {
    // Obtener información básica
    final cliente = datosNuevos?['nombre'] ?? datosAntiguos?['nombre'] ?? 'Cliente';
    final cancha = metadatos?['cancha_nombre'] ?? 'Cancha';
    
    String descripcion = '';
    
    // Prefijo según nivel de riesgo
    final nivelRiesgo = analisisRiesgo?['nivel'] ?? 'bajo';
    if (nivelRiesgo == 'critico') descripcion += '🚨 ';
    else if (nivelRiesgo == 'alto') descripcion += '🔴 ';
    else if (nivelRiesgo == 'medio') descripcion += '🟡 ';
    
    // Descripción base según acción
    switch (accion) {
      case 'crear_reserva':
        descripcion += 'Reserva creada para $cliente en $cancha';
        break;
      case 'crear_reserva_precio_personalizado':
        descripcion += 'Reserva con precio personalizado creada para $cliente';
        break;
      case 'crear_reserva_sospechosa':
        descripcion += 'RESERVA SOSPECHOSA creada para $cliente';
        break;
      case 'editar_reserva':
        descripcion += 'Reserva de $cliente editada';
        break;
      case 'editar_reserva_precio_critico':
        descripcion += 'EDICIÓN CRÍTICA de reserva de $cliente';
        break;
      case 'eliminar_reserva':
        descripcion += 'Reserva de $cliente eliminada';
        break;
      case 'eliminar_reserva_impacto_alto':
        descripcion += 'ELIMINACIÓN DE ALTO IMPACTO: reserva de $cliente';
        break;
      default:
        descripcion += 'Acción $accion realizada';
    }
    
    // Añadir información de cambios si está disponible
    final cambios = analisisRiesgo?['cambios'] as List<String>?;
    if (cambios != null && cambios.isNotEmpty) {
      if (cambios.length == 1) {
        descripcion += ' (${cambios.first})';
      } else if (cambios.length <= 3) {
        descripcion += ' (${cambios.join(', ')})';
      } else {
        descripcion += ' (${cambios.take(2).join(', ')} +${cambios.length - 2} más)';
      }
    }
    
    return descripcion;
  }

  /// Obtener datos del usuario con cache
  static final Map<String, Map<String, dynamic>> _cacheUsuarios = {};
  
  static Future<Map<String, dynamic>> _obtenerDatosUsuario(String userId) async {
    if (_cacheUsuarios.containsKey(userId)) {
      return _cacheUsuarios[userId]!;
    }
    
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(userId)
          .get();

      final userData = userDoc.data() ?? {};
      final resultado = {
        'nombre': userData['nombre'] ?? userData['name'] ?? 'Usuario desconocido',
        'rol': userData['rol'] ?? 'usuario',
      };
      
      _cacheUsuarios[userId] = resultado;
      return resultado;
    } catch (e) {
      return {'nombre': 'Usuario desconocido', 'rol': 'usuario'};
    }
  }

  /// Obtener contexto adicional
  static Future<Map<String, dynamic>> _obtenerContextoAdicional(
    String accion,
    String entidad,
    String entidadId,
  ) async {
    final contexto = <String, dynamic>{};
    
    // Obtener información adicional según el tipo de entidad
    if (entidad == 'reserva' || entidad == 'reserva_recurrente') {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(entidad == 'reserva' ? 'reservas' : 'reservas_recurrentes')
            .doc(entidadId)
            .get();
            
        if (doc.exists) {
          final data = doc.data()!;
          contexto.addAll({
            'sede_contexto': data['sede'],
            'cancha_contexto': data['cancha_nombre'],
            'fecha_contexto': data['fecha'],
            'estado_contexto': data['estado'],
          });
        }
      } catch (e) {
        // Ignorar errores
      }
    }
    
    return contexto;
  }

  /// Procesar alerta crítica mejorada
  static Future<void> _procesarAlertaCritica(
    Map<String, dynamic> auditEntry,
    String auditEntryId,
  ) async {
    try {
      // Crear alerta crítica mejorada
      await FirebaseFirestore.instance
          .collection('alertas_criticas')
          .add({
        'audit_entry_id': auditEntryId,
        'titulo': _generarTituloAlerta(auditEntry),
        'descripcion': auditEntry['descripcion'],
        'usuario': auditEntry['usuario_nombre'],
        'usuario_id': auditEntry['usuario_id'],
        'accion': auditEntry['accion'],
        'entidad': auditEntry['entidad'],
        'entidad_id': auditEntry['entidad_id'],
        'timestamp': auditEntry['timestamp'],
        'alertas': auditEntry['alertas'],
        'puntuacion_riesgo': auditEntry['puntuacion_riesgo'],
        'metadatos': auditEntry['metadatos'],
        'leida': false,
        'nivel': 'critico',
        'prioridad': _calcularPrioridadAlerta(auditEntry),
        'requiere_accion': true,
        'fecha_expiracion': Timestamp.fromDate(
          DateTime.now().add(Duration(days: 7)),
        ),
      });
      
      // Enviar notificación push si está configurado
      await _enviarNotificacionPush(auditEntry);
      
      debugPrint('🚨 Alerta crítica procesada: ${auditEntry['accion']}');
    } catch (e) {
      debugPrint('❌ Error procesando alerta crítica: $e');
    }
  }

  static String _generarTituloAlerta(Map<String, dynamic> auditEntry) {
    final accion = auditEntry['accion'];
    final usuario = auditEntry['usuario_nombre'];
    
    switch (accion) {
      case 'editar_reserva_precio_critico':
        return 'PRECIO CRÍTICO: $usuario modificó precio drásticamente';
      case 'eliminar_reserva_impacto_alto':
        return 'ELIMINACIÓN CRÍTICA: $usuario eliminó reserva de alto valor';
      case 'crear_reserva_sospechosa':
        return 'RESERVA SOSPECHOSA: Patrones anómalos detectados por $usuario';
      default:
        return 'ALERTA CRÍTICA: $accion por $usuario';
    }
  }

  static int _calcularPrioridadAlerta(Map<String, dynamic> auditEntry) {
    final puntuacion = auditEntry['puntuacion_riesgo'] as int? ?? 0;
    if (puntuacion >= 90) return 1; // Crítica
    if (puntuacion >= 80) return 2; // Alta
    return 3; // Normal
  }

  /// Actualizar estadísticas en tiempo real
  static Future<void> _actualizarEstadisticasEnTiempoReal(
    String accion,
    Map<String, dynamic> analisisRiesgo,
  ) async {
    try {
      final hoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      await FirebaseFirestore.instance
          .collection('estadisticas_auditoria')
          .doc(hoy)
          .set({
        'fecha': hoy,
        'total_operaciones': FieldValue.increment(1),
        'operaciones_${analisisRiesgo['nivel']}': FieldValue.increment(1),
        'acciones.$accion': FieldValue.increment(1),
        'ultima_actualizacion': Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error actualizando estadísticas: $e');
    }
  }

  /// Enviar notificación push
  static Future<void> _enviarNotificacionPush(Map<String, dynamic> auditEntry) async {
    // Implementación de notificaciones push
    // Esto dependería de tu sistema de notificaciones
    debugPrint('📱 Notificación push enviada: ${auditEntry['titulo'] ?? auditEntry['descripcion']}');
  }

  /// Métodos auxiliares
  static double? _extraerPrecio(Map<String, dynamic> datos) {
    final campos = ['valor', 'montoTotal', 'precio', 'monto_total'];
    for (final campo in campos) {
      if (datos.containsKey(campo) && datos[campo] != null) {
        return (datos[campo] as num).toDouble();
      }
    }
    return null;
  }

  static Future<String> _obtenerIP() async {
    return 'IP no disponible en Flutter';
  }

  static Future<Map<String, dynamic>> _obtenerInfoDispositivo() async {
    return {
      'plataforma': 'Flutter',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  // Métodos de agrupación mejorados
  Map<String, int> _agruparPorAccion(List<AuditEntry> entries) {
    final Map<String, int> agrupado = {};
    for (var entry in entries) {
      agrupado[entry.accion] = (agrupado[entry.accion] ?? 0) + 1;
    }
    return Map.fromEntries(
      agrupado.entries.toList()..sort((a, b) => b.value.compareTo(a.value))
    );
  }

  Map<String, int> _agruparPorUsuario(List<AuditEntry> entries) {
    final Map<String, int> agrupado = {};
    for (var entry in entries) {
      agrupado[entry.usuarioNombre] = (agrupado[entry.usuarioNombre] ?? 0) + 1;
    }
    return Map.fromEntries(
      agrupado.entries.toList()..sort((a, b) => b.value.compareTo(a.value))
    );
  }

  Map<String, int> _agruparPorFecha(List<AuditEntry> entries) {
    final Map<String, int> agrupado = {};
    for (var entry in entries) {
      final fecha = DateFormat('yyyy-MM-dd').format(entry.fechaLocal);
      agrupado[fecha] = (agrupado[fecha] ?? 0) + 1;
    }
    return agrupado;
  }

  Map<String, dynamic> _calcularTendencias(List<AuditEntry> entries) {
    if (entries.length < 2) return {};
    
    final hoy = DateTime.now();
    final ayer = hoy.subtract(Duration(days: 1));
    
    final entradashoy = entries.where((e) => 
      DateFormat('yyyy-MM-dd').format(e.fechaLocal) == 
      DateFormat('yyyy-MM-dd').format(hoy)
    ).length;
    
    final entradasAyer = entries.where((e) => 
      DateFormat('yyyy-MM-dd').format(e.fechaLocal) == 
      DateFormat('yyyy-MM-dd').format(ayer)
    ).length;
    
    final tendencia = entradashoy - entradasAyer;
    
    return {
      'hoy': entradashoy,
      'ayer': entradasAyer,
      'tendencia': tendencia,
      'porcentaje_cambio': entradasAyer > 0 ? (tendencia / entradasAyer * 100) : 0,
    };
  }

  Map<String, dynamic> _calcularImpactoFinanciero(List<AuditEntry> entries) {
    double impactoTotal = 0;
    int operacionesFinancieras = 0;
    
    for (var entry in entries) {
      if (entry.metadatos.containsKey('impacto_financiero')) {
        final impacto = entry.metadatos['impacto_financiero'];
        if (impacto is Map && impacto.containsKey('diferencia_ingresos')) {
          impactoTotal += (impacto['diferencia_ingresos'] as num?)?.toDouble() ?? 0;
          operacionesFinancieras++;
        }
      }
    }
    
    return {
      'impacto_total': impactoTotal,
      'operaciones_financieras': operacionesFinancieras,
      'impacto_promedio': operacionesFinancieras > 0 ? impactoTotal / operacionesFinancieras : 0,
    };
  }

  /// Obtener alertas no leídas con mejor rendimiento
  Future<List<Map<String, dynamic>>> obtenerAlertasNoLeidas() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('alertas_criticas')
          .where('leida', isEqualTo: false)
          .orderBy('prioridad')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      return query.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      debugPrint('Error obteniendo alertas: $e');
      return [];
    }
  }

  /// Marcar alerta como leída
  Future<void> marcarAlertaLeida(String alertaId) async {
    try {
      await FirebaseFirestore.instance
          .collection('alertas_criticas')
          .doc(alertaId)
          .update({
        'leida': true,
        'fecha_lectura': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('Error marcando alerta como leída: $e');
    }
  }

  /// Obtener resumen de alertas críticas del día
  Future<Map<String, dynamic>> obtenerResumenAlertasHoy() async {
    try {
      final hoy = DateTime.now();
      final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
      final finHoy = inicioHoy.add(Duration(days: 1));
      
      final query = await FirebaseFirestore.instance
          .collection('alertas_criticas')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioHoy))
          .where('timestamp', isLessThan: Timestamp.fromDate(finHoy))
          .get();

      final alertas = query.docs;
      final noLeidas = alertas.where((doc) => doc.data()['leida'] == false).length;
      final criticas = alertas.where((doc) => doc.data()['prioridad'] == 1).length;
      
      return {
        'total_hoy': alertas.length,
        'no_leidas': noLeidas,
        'criticas': criticas,
        'requieren_accion': alertas.where((doc) => 
          doc.data()['requiere_accion'] == true).length,
      };
    } catch (e) {
      debugPrint('Error obteniendo resumen de alertas: $e');
      return {};
    }
  }
}