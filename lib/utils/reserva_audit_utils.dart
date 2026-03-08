// lib/utils/reserva_audit_utils_mejorado.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../providers/audit_provider.dart';

/// ✅ UMBRALES UNIFICADOS DE RIESGO - Usar en TODO el sistema
class UmbralesRiesgo {
  static const int critico = 80;   // ≥80 puntos
  static const int alto = 60;      // 60-79 puntos
  static const int medio = 35;     // 35-59 puntos
  static const int bajo = 0;       // 0-34 puntos
}

class ReservaAuditUtils {
  
  /// Auditar edición de reservas con análisis mejorado
  static Future<void> auditarEdicionReserva({
    required String reservaId,
    required Map<String, dynamic> datosAntiguos,
    required Map<String, dynamic> datosNuevos,
    String? descripcionPersonalizada,
    Map<String, dynamic>? metadatosAdicionales,
    bool esReservaRecurrente = false,
    String? tipoEdicion, // 'normal', 'dia_especifico', 'precio_recurrente'
  }) async {
    try {
      // VALIDACIÓN: Evitar llamadas duplicadas
      if (metadatosAdicionales?.containsKey('_audit_processed') == true) {
        debugPrint('⚠️ Auditoría ya procesada, evitando duplicación');
        return;
      }

      // Análisis completo de cambios
      final analisisCambios = _analizarCambiosCompleto(datosAntiguos, datosNuevos);
      
      // Determinar tipo de acción específica
      String accionEspecifica = 'editar_reserva';
      if (esReservaRecurrente) {
        accionEspecifica = tipoEdicion == 'precio_recurrente' 
            ? 'editar_precio_reserva_recurrente'
            : 'editar_reserva_dia_especifico';
      }
      
      // Si hay cambio crítico de precio, usar acción específica
      if (analisisCambios['esCambioCriticoPrecios'] == true) {
        accionEspecifica = esReservaRecurrente 
            ? 'editar_precio_critico_reserva_recurrente'
            : 'editar_reserva_precio_critico';
      }

      await AuditProvider.registrarAccion(
        accion: accionEspecifica,
        entidad: esReservaRecurrente ? 'reserva_recurrente' : 'reserva',
        entidadId: reservaId,
        datosAntiguos: _limpiarDatosSensibles(datosAntiguos),
        datosNuevos: _limpiarDatosSensibles(datosNuevos),
        metadatos: {
          // MARCADORES CRÍTICOS: Indica que viene de ReservaAuditUtils
          '_audit_processed': true,
          'fuente_original': 'ReservaAuditUtils',
          'metodo_auditoria': 'auditarEdicionReserva',
          
          // Información básica de la reserva
          'cancha_nombre': datosNuevos['cancha_nombre'] ?? datosAntiguos['cancha_nombre'],
          'sede': datosNuevos['sede'] ?? datosAntiguos['sede'],
          'cliente': datosNuevos['nombre'] ?? datosAntiguos['nombre'],
          'fecha_reserva': datosNuevos['fecha'] ?? datosAntiguos['fecha'],
          'horario': datosNuevos['horario'] ?? datosAntiguos['horario'],
          
          // Análisis de cambios detallado (CLAVE: esto es lo que usará AuditProvider)
          'nivel_riesgo_calculado': analisisCambios['nivel_riesgo_calculado'],
          'cambios_detectados': analisisCambios['cambios_detectados'],
          'alertas_generadas': analisisCambios['alertas_generadas'],
          'cantidad_cambios': analisisCambios['cantidad_cambios'],
          'esCambioCriticoPrecios': analisisCambios['esCambioCriticoPrecios'],
          'porcentaje_cambio_precio': analisisCambios['porcentaje_cambio_precio'],
          'diferencia_precio': analisisCambios['diferencia_precio'],
          'metricas_cambios': analisisCambios['metricas_cambios'],
          
          // Metadatos de contexto
          'tipo_edicion': tipoEdicion ?? 'normal',
          'es_reserva_recurrente': esReservaRecurrente,
          'tiene_precio_personalizado': datosNuevos['precio_personalizado'] ?? false,
          
          // Información de impacto financiero
          'impacto_financiero': _calcularImpactoFinanciero(datosAntiguos, datosNuevos),
          
          // Metadatos adicionales del contexto
          ...?metadatosAdicionales,
        },
        descripcion: descripcionPersonalizada ?? _generarDescripcionMejorada(
          datosAntiguos, 
          datosNuevos, 
          analisisCambios,
          esReservaRecurrente,
        ),
      );
    } catch (e) {
      debugPrint('Error auditando edición de reserva: $e');
    }
  }




  /// Análisis completo de cambios con detección mejorada de anomalías
  static Map<String, dynamic> _analizarCambiosCompleto(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
  ) {
    final cambiosDetectados = <String>[];
    final alertasGeneradas = <String>[];
    final metricasCambios = <String, dynamic>{};

    // 1. ANÁLISIS DE CAMBIOS DE PRECIO - MEJORADO
    final analisisPrecios = _analizarCambiosPreciosDetallado(datosAntiguos, datosNuevos);
    if (analisisPrecios['hay_cambios'] == true) {
      cambiosDetectados.addAll(analisisPrecios['cambios_detectados'] as List<String>);
      alertasGeneradas.addAll(analisisPrecios['alertas'] as List<String>);
      metricasCambios.addAll(analisisPrecios['metricas'] as Map<String, dynamic>);
    }

    // 2. ANÁLISIS DE CAMBIOS DE FECHA/HORARIO - MEJORADO
    final analisisFechas = _analizarCambiosFechaHorario(datosAntiguos, datosNuevos);
    cambiosDetectados.addAll(analisisFechas['cambios'] as List<String>);
    alertasGeneradas.addAll(analisisFechas['alertas'] as List<String>);

    // 3. ANÁLISIS DE CAMBIOS DE CLIENTE
    final analisisCliente = _analizarCambiosCliente(datosAntiguos, datosNuevos);
    cambiosDetectados.addAll(analisisCliente['cambios'] as List<String>);

    // 4. ANÁLISIS DE CAMBIOS DE PAGOS
    final analisisPagos = _analizarCambiosPagos(datosAntiguos, datosNuevos);
    cambiosDetectados.addAll(analisisPagos['cambios'] as List<String>);
    alertasGeneradas.addAll(analisisPagos['alertas'] as List<String>);

    // 5. ANÁLISIS DE CAMBIOS DE UBICACIÓN (SEDE/CANCHA)
    final analisisUbicacion = _analizarCambiosUbicacion(datosAntiguos, datosNuevos);
    cambiosDetectados.addAll(analisisUbicacion['cambios'] as List<String>);
    alertasGeneradas.addAll(analisisUbicacion['alertas'] as List<String>);

    // 6. DETECCIÓN DE PATRONES SOSPECHOSOS
    final patronesSospechosos = _detectarPatronesSospechosos(datosAntiguos, datosNuevos);
    alertasGeneradas.addAll(patronesSospechosos);

    // 7. CALCULAR NIVEL DE RIESGO BASADO EN MÚLTIPLES FACTORES
    String nivelRiesgo = _calcularNivelRiesgoMejorado(
      analisisPrecios,
      analisisFechas,
      analisisPagos,
      alertasGeneradas,
    );

    // ✅ MEJORA: Los descuentos ya están considerados en el cálculo de puntuación
    // No forzar niveles manualmente, confiar en la puntuación calculada
    // Si un descuento es significativo, la puntuación ya lo reflejará
    
    // Nota: Los ajustes manuales se eliminaron para confiar en el sistema de puntuación unificado

    return {
      'cambios_detectados': cambiosDetectados,
      'alertas_generadas': alertasGeneradas,
      'nivel_riesgo_calculado': nivelRiesgo,
      'cantidad_cambios': cambiosDetectados.length,
      'esCambioCriticoPrecios': analisisPrecios['es_cambio_critico'] ?? false,
      'porcentaje_cambio_precio': analisisPrecios['porcentaje_cambio'] ?? 0.0,
      'diferencia_precio': analisisPrecios['diferencia_precio'] ?? 0.0,
      'metricas_cambios': metricasCambios,
    };
  }

  /// Análisis detallado de cambios de precios
  static Map<String, dynamic> _analizarCambiosPreciosDetallado(
  Map<String, dynamic> datosAntiguos,
  Map<String, dynamic> datosNuevos,
) {
  final cambios = <String>[];
  final alertas = <String>[];
  final metricas = <String, dynamic>{};
  
  // Obtener valores de precio
  final precioAnterior = _extraerValorMonetario(datosAntiguos);
  final precioNuevo = _extraerValorMonetario(datosNuevos);
  
  if (precioAnterior == null || precioNuevo == null) {
    return {
      'hay_cambios': false,
      'cambios_detectados': <String>[],
      'alertas': <String>[],
      'metricas': <String, dynamic>{},
    };
  }
  
  final diferencia = precioNuevo - precioAnterior;
  final porcentajeCambio = precioAnterior > 0 ? (diferencia / precioAnterior * 100).abs() : 0.0;
  
  metricas.addAll({
    'precio_anterior': precioAnterior,
    'precio_nuevo': precioNuevo,
    'diferencia_precio': diferencia,
    'porcentaje_cambio': porcentajeCambio,
  });

  if ((diferencia).abs() > 0.01) { // Cambió el precio
    final formatter = NumberFormat('#,##0', 'es_CO');
    final direccion = diferencia > 0 ? '↗️' : '↘️';
    
    cambios.add('Precio: \$${formatter.format(precioAnterior)} → \$${formatter.format(precioNuevo)} $direccion');
    
    // Clasificación de severidad del cambio de precio - MANTENER CONSISTENTE
    String severidad = '';
    bool esCritico = false;
    
    if (porcentajeCambio >= 70) {
      severidad = 'EXTREMO';
      esCritico = true;
      alertas.add(' CAMBIO DE PRECIO EXTREMO: ${porcentajeCambio.toStringAsFixed(1)}% (${diferencia > 0 ? 'Aumento' : 'Descuento'} de \$${formatter.format(diferencia.abs())})');
    } else if (porcentajeCambio >= 50) {
      severidad = 'CRÍTICO';
      esCritico = true;
      alertas.add(' CAMBIO DE PRECIO CRÍTICO: ${porcentajeCambio.toStringAsFixed(1)}% (${diferencia > 0 ? 'Aumento' : 'Descuento'} de \$${formatter.format(diferencia.abs())})');
    } else if (porcentajeCambio >= 30) {
      severidad = 'ALTO';
      alertas.add(' Cambio de precio significativo: ${porcentajeCambio.toStringAsFixed(1)}% (\$${formatter.format(diferencia.abs())})');
    } else if (porcentajeCambio >= 15) {
      severidad = 'MEDIO';
      alertas.add(' Cambio de precio moderado: ${porcentajeCambio.toStringAsFixed(1)}% (\$${formatter.format(diferencia.abs())})');
    } else if (porcentajeCambio > 0) {
      severidad = 'BAJO';
      alertas.add(' Cambio de precio menor: ${porcentajeCambio.toStringAsFixed(1)}% (\$${formatter.format(diferencia.abs())})');
    }

    // Detectar descuentos inusuales - MANTENER CONSISTENTE
    // Solo mostrar alerta de descuento si no es solo cambio de fecha/hora
    final esSoloCambioFechaHora = _esSoloCambioFechaHora(
      datosAntiguos, 
      datosNuevos, 
      <String>['Fecha:', 'Horario:'] // Lista temporal para verificar
    );
    
    if (diferencia < 0 && diferencia.abs() > 50000 && !esSoloCambioFechaHora) {
      alertas.add('💰 DESCUENTO ALTO DETECTADO: \$${formatter.format(diferencia.abs())}');
    }

    metricas.addAll({
      'severidad_cambio': severidad,
      'es_cambio_critico': esCritico,
      'es_aumento': diferencia > 0,
      'es_descuento': diferencia < 0,
    });
    
    return {
      'hay_cambios': true,
      'cambios_detectados': cambios,
      'alertas': alertas,
      'metricas': metricas,
      'es_cambio_critico': esCritico,
      'porcentaje_cambio': porcentajeCambio,
      'diferencia_precio': diferencia,
    };
  }
  
  return {
    'hay_cambios': false,
    'cambios_detectados': <String>[],
    'alertas': <String>[],
    'metricas': metricas,
  };
}





  /// Análisis de cambios de fecha y horario
  static Map<String, dynamic> _analizarCambiosFechaHorario(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
  ) {
    final cambios = <String>[];
    final alertas = <String>[];
    
    // Análisis de cambio de fecha
    if (datosAntiguos['fecha'] != datosNuevos['fecha']) {
      try {
        final fechaAnterior = DateTime.parse(datosAntiguos['fecha'].toString());
        final fechaNueva = DateTime.parse(datosNuevos['fecha'].toString());
        final hoy = DateTime.now();
        
        final fechaAntFormat = DateFormat('dd/MM/yyyy').format(fechaAnterior);
        final fechaNueFormat = DateFormat('dd/MM/yyyy').format(fechaNueva);
        
        cambios.add('Fecha: $fechaAntFormat → $fechaNueFormat');
        
        // Alertas por proximidad
        final diasHastaFechaAnterior = fechaAnterior.difference(hoy).inDays;
        final diasHastaFechaNueva = fechaNueva.difference(hoy).inDays;
        
        if (diasHastaFechaAnterior <= 1) {
          alertas.add('⚠️ Cambio de fecha en reserva inmediata (era para ${diasHastaFechaAnterior == 0 ? 'hoy' : 'mañana'})');
        }
        
        if (diasHastaFechaNueva <= 0) {
          alertas.add('🚨 FECHA CAMBIADA A FECHA PASADA O HOY');
        }
        
        // Diferencia significativa en días
        final diferenciaEnDias = (fechaNueva.difference(fechaAnterior).inDays).abs();
        if (diferenciaEnDias > 30) {
          alertas.add('📅 Cambio de fecha significativo: $diferenciaEnDias días de diferencia');
        }
        
      } catch (e) {
        cambios.add('Fecha: ${datosAntiguos['fecha']} → ${datosNuevos['fecha']} (formato no válido)');
        alertas.add('⚠️ Error al analizar cambio de fecha');
      }
    }
    
    // Análisis de cambio de horario
    if (datosAntiguos['horario'] != datosNuevos['horario']) {
      cambios.add('Horario: ${datosAntiguos['horario']} → ${datosNuevos['horario']}');
      
      // Detectar cambios de horario peak
      final horarioAnterior = datosAntiguos['horario'].toString();
      final horarioNuevo = datosNuevos['horario'].toString();
      
      if (_esHorarioPeak(horarioAnterior) && !_esHorarioPeak(horarioNuevo)) {
        alertas.add('📉 Cambio de horario peak a horario regular');
      } else if (!_esHorarioPeak(horarioAnterior) && _esHorarioPeak(horarioNuevo)) {
        alertas.add('📈 Cambio de horario regular a horario peak');
      }
    }
    
    return {
      'cambios': cambios,
      'alertas': alertas,
    };
  }

  /// Análisis de cambios de cliente
  static Map<String, dynamic> _analizarCambiosCliente(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
  ) {
    final cambios = <String>[];
    
    if (datosAntiguos['nombre'] != datosNuevos['nombre']) {
      cambios.add('Cliente: ${datosAntiguos['nombre']} → ${datosNuevos['nombre']}');
    }
    
    if (datosAntiguos['telefono'] != datosNuevos['telefono']) {
      cambios.add('Teléfono: ${datosAntiguos['telefono']} → ${datosNuevos['telefono']}');
    }
    
    return {'cambios': cambios};
  }

  /// Análisis de cambios de pagos
  static Map<String, dynamic> _analizarCambiosPagos(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
  ) {
    final cambios = <String>[];
    final alertas = <String>[];
    
    final pagoAnterior = (datosAntiguos['montoPagado'] as num?)?.toDouble() ?? 0.0;
    final pagoNuevo = (datosNuevos['montoPagado'] as num?)?.toDouble() ?? 0.0;
    
    if ((pagoAnterior - pagoNuevo).abs() > 0.01) {
      final formatter = NumberFormat('#,##0', 'es_CO');
      final diferencia = pagoNuevo - pagoAnterior;
      final direccion = diferencia > 0 ? '↗️' : '↘️';
      
      cambios.add('Abono: \$${formatter.format(pagoAnterior)} → \$${formatter.format(pagoNuevo)} $direccion');
      
      // Alertas para cambios de pago
      if (diferencia < 0 && diferencia.abs() > 20000) {
        alertas.add('💸 REDUCCIÓN SIGNIFICATIVA DE ABONO: \$${formatter.format(diferencia.abs())}');
      } else if (diferencia > 50000) {
        alertas.add('💰 AUMENTO SIGNIFICATIVO DE ABONO: \$${formatter.format(diferencia)}');
      }
    }
    
    // Análisis de cambio de estado de pago
    if (datosAntiguos['estado'] != datosNuevos['estado']) {
      final estadoAnt = datosAntiguos['estado'] == 'completo' ? 'Pagado Completo' : 'Pago Parcial';
      final estadoNue = datosNuevos['estado'] == 'completo' ? 'Pagado Completo' : 'Pago Parcial';
      cambios.add('Estado de Pago: $estadoAnt → $estadoNue');
    }
    
    return {
      'cambios': cambios,
      'alertas': alertas,
    };
  }

  /// Análisis de cambios de ubicación
  static Map<String, dynamic> _analizarCambiosUbicacion(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
  ) {
    final cambios = <String>[];
    final alertas = <String>[];
    
    // Cambio de sede
    if (datosAntiguos['sede'] != datosNuevos['sede']) {
      cambios.add('Sede: ${datosAntiguos['sede']} → ${datosNuevos['sede']}');
      alertas.add('🏢 Cambio de sede detectado');
    }
    
    // Cambio de cancha
    if (datosAntiguos['cancha_id'] != datosNuevos['cancha_id']) {
      cambios.add('Cancha: ${datosAntiguos['cancha_nombre'] ?? 'ID: ${datosAntiguos['cancha_id']}'} → ${datosNuevos['cancha_nombre'] ?? 'ID: ${datosNuevos['cancha_id']}'}');
    }
    
    return {
      'cambios': cambios,
      'alertas': alertas,
    };
  }

  /// Detectar patrones sospechosos
  static List<String> _detectarPatronesSospechosos(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
  ) {
    final alertas = <String>[];
    
    // 1. Precio personalizado activado con descuento alto
    if (datosNuevos['precio_personalizado'] == true) {
      final precioAnterior = _extraerValorMonetario(datosAntiguos) ?? 0;
      final precioNuevo = _extraerValorMonetario(datosNuevos) ?? 0;
      final descuento = precioAnterior - precioNuevo;
      
      // Solo mostrar alerta si no es solo cambio de fecha/hora
      final esSoloCambioFechaHora = _esSoloCambioFechaHora(
        datosAntiguos, 
        datosNuevos, 
        <String>['Fecha:', 'Horario:'] // Lista temporal para verificar
      );
      
      if (descuento > precioAnterior * 0.3 && !esSoloCambioFechaHora) { // Más del 30% de descuento
        alertas.add(' PRECIO PERSONALIZADO CON DESCUENTO ALTO: ${(descuento/precioAnterior*100).toStringAsFixed(1)}%');
      }
    }
    
    // 2. Múltiples cambios simultáneos (posible manipulación)
    int cambiosImportantes = 0;
    if (datosAntiguos['fecha'] != datosNuevos['fecha']) cambiosImportantes++;
    if (datosAntiguos['horario'] != datosNuevos['horario']) cambiosImportantes++;
    if (datosAntiguos['cancha_id'] != datosNuevos['cancha_id']) cambiosImportantes++;
    if (datosAntiguos['sede'] != datosNuevos['sede']) cambiosImportantes++;
    if ((_extraerValorMonetario(datosAntiguos) ?? 0) != (_extraerValorMonetario(datosNuevos) ?? 0)) cambiosImportantes++;
    
    if (cambiosImportantes >= 3) {
      alertas.add('🔄 MÚLTIPLES CAMBIOS SIMULTÁNEOS: $cambiosImportantes modificaciones importantes');
    }
    
    // 3. Cambio a fecha/horario premium con descuento
    final fechaAnterior = datosAntiguos['fecha'];
    final fechaNueva = datosNuevos['fecha'];
    
    if (fechaAnterior != fechaNueva && datosNuevos['precio_personalizado'] == true) {
      try {
        final fechaDateTime = DateTime.parse(fechaNueva.toString());
        if (_esFechaFinDeSemana(fechaDateTime)) {
          alertas.add('🎪 Cambio a fin de semana con precio personalizado');
        }
      } catch (e) {
        // Ignorar errores de parsing
      }
    }
    
    return alertas;
  }

  /// ✅ CALCULAR NIVEL DE RIESGO MEJORADO - Sistema unificado
  static String _calcularNivelRiesgoMejorado(
    Map<String, dynamic> analisisPrecios,
    Map<String, dynamic> analisisFechas,
    Map<String, dynamic> analisisPagos,
    List<String> alertasGeneradas,
  ) {
    int puntuacionRiesgo = 0;
    
    // 1. FACTOR PRECIO (máximo 45 puntos)
    // Considera tanto porcentaje como monto absoluto
    if (analisisPrecios['es_cambio_critico'] == true) {
      final porcentaje = (analisisPrecios['porcentaje_cambio'] ?? 0.0) as double;
      final diferenciaAbsoluta = (analisisPrecios['diferencia_precio'] ?? 0.0) as double;
      
      // Puntos por porcentaje (máximo 30 puntos)
      if (porcentaje >= 70) {
        puntuacionRiesgo += 30;
      } else if (porcentaje >= 50) {
        puntuacionRiesgo += 25;
      } else if (porcentaje >= 30) {
        puntuacionRiesgo += 20;
      } else if (porcentaje >= 15) {
        puntuacionRiesgo += 12;
      }
      
      // Puntos por monto absoluto (máximo 15 puntos)
      final diferenciaAbs = diferenciaAbsoluta.abs();
      if (diferenciaAbs >= 100000) {
        puntuacionRiesgo += 15;
      } else if (diferenciaAbs >= 50000) {
        puntuacionRiesgo += 10;
      } else if (diferenciaAbs >= 20000) {
        puntuacionRiesgo += 5;
      }
    }
    
    // 2. FACTOR FECHA/HORARIO (máximo 20 puntos)
    final alertasFechas = analisisFechas['alertas'] as List<String>;
    if (alertasFechas.any((a) => a.contains('🚨'))) {
      puntuacionRiesgo += 20;
    } else if (alertasFechas.any((a) => a.contains('⚠️'))) {
      puntuacionRiesgo += 15;
    } else if (alertasFechas.isNotEmpty) {
      puntuacionRiesgo += 10;
    }
    
    // 3. FACTOR PAGOS (máximo 20 puntos)
    final alertasPagos = analisisPagos['alertas'] as List<String>;
    if (alertasPagos.any((a) => a.contains('💸'))) {
      puntuacionRiesgo += 20;
    } else if (alertasPagos.any((a) => a.contains('💰'))) {
      puntuacionRiesgo += 12;
    } else if (alertasPagos.isNotEmpty) {
      puntuacionRiesgo += 5;
    }
    
    // 4. FACTOR PATRONES SOSPECHOSOS (máximo 15 puntos)
    final cantidadAlertas = alertasGeneradas.length;
    if (cantidadAlertas >= 5) {
      puntuacionRiesgo += 15;
    } else if (cantidadAlertas >= 3) {
      puntuacionRiesgo += 10;
    } else if (cantidadAlertas >= 1) {
      puntuacionRiesgo += 5;
    }
    
    // ✅ CLASIFICACIÓN FINAL CON UMBRALES UNIFICADOS
    if (puntuacionRiesgo >= UmbralesRiesgo.critico) return 'critico';
    if (puntuacionRiesgo >= UmbralesRiesgo.alto) return 'alto';
    if (puntuacionRiesgo >= UmbralesRiesgo.medio) return 'medio';
    return 'bajo';
  }

  /// Generar descripción mejorada
  static String _generarDescripcionMejorada(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
    Map<String, dynamic> analisisCambios,
    bool esReservaRecurrente,
  ) {
    final cliente = datosNuevos['nombre'] ?? datosAntiguos['nombre'] ?? 'Cliente';
    final cambios = analisisCambios['cambios_detectados'] as List<String>;
    final nivelRiesgo = analisisCambios['nivel_riesgo_calculado'];
    
    String prefijo = '';
    if (esReservaRecurrente) prefijo = '🔄 ';
    if (nivelRiesgo == 'critico') {
      prefijo += '🚨 ';
    } else if (nivelRiesgo == 'alto') prefijo += '🔴 ';
    else if (nivelRiesgo == 'medio') prefijo += '🟡 ';
    
    if (cambios.isEmpty) {
      return '${prefijo}Reserva de $cliente editada sin cambios críticos detectados';
    }
    
    // Detectar si solo se cambió fecha/hora (sin cambios de precio significativos)
    final soloCambioFechaHora = _esSoloCambioFechaHora(datosAntiguos, datosNuevos, cambios);
    
    String tipoModificacion = '';
    if (datosNuevos['precio_personalizado'] == true && !soloCambioFechaHora) {
      tipoModificacion = ' (Precio Personalizado)';
    }
    
    // Filtrar cambios de precio si solo se cambió fecha/hora
    final cambiosFiltrados = soloCambioFechaHora 
        ? cambios.where((cambio) => !cambio.contains('Precio:')).toList()
        : cambios;
    
    if (cambiosFiltrados.isEmpty) {
      return '${prefijo}Reserva de $cliente: Cambio de fecha/hora$tipoModificacion';
    }
    
    if (cambiosFiltrados.length == 1) {
      return '${prefijo}Reserva de $cliente: ${cambiosFiltrados.first}$tipoModificacion';
    }
    
    final cambiosPrincipales = cambiosFiltrados.take(2).join(' | ');
    final sufijo = cambiosFiltrados.length > 2 ? ' +${cambiosFiltrados.length - 2} cambios más' : '';
    
    return '${prefijo}Reserva de $cliente: $cambiosPrincipales$sufijo$tipoModificacion';
  }




  // Métodos auxiliares mejorados
  static double? _extraerValorMonetario(Map<String, dynamic> datos) {
    // Buscar en múltiples campos posibles
    final campos = ['valor', 'montoTotal', 'precio', 'monto_total'];
    for (final campo in campos) {
      if (datos.containsKey(campo) && datos[campo] != null) {
        return (datos[campo] as num).toDouble();
      }
    }
    return null;
  }

  static bool _esHorarioPeak(String horario) {
    // Definir horarios peak (ejemplo: 18:00-22:00)
    final regex = RegExp(r'(\d{1,2}):(\d{2})');
    final match = regex.firstMatch(horario);
    if (match != null) {
      final hora = int.parse(match.group(1)!);
      return hora >= 18 && hora <= 22;
    }
    return false;
  }

  static bool _esFechaFinDeSemana(DateTime fecha) {
    return fecha.weekday == DateTime.friday || 
           fecha.weekday == DateTime.saturday || 
           fecha.weekday == DateTime.sunday;
  }

  /// Detectar si solo se cambió fecha/hora (sin cambios de precio significativos)
  static bool _esSoloCambioFechaHora(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
    List<String> cambiosDetectados,
  ) {
    // Verificar si solo hay cambios de fecha y/o horario
    final soloFechaHora = cambiosDetectados.every((cambio) => 
        cambio.contains('Fecha:') || cambio.contains('Horario:'));
    
    if (!soloFechaHora) return false;
    
    // Verificar que no haya cambios significativos de precio
    final precioAnterior = _extraerValorMonetario(datosAntiguos);
    final precioNuevo = _extraerValorMonetario(datosNuevos);
    
    if (precioAnterior == null || precioNuevo == null) return true;
    
    final diferencia = (precioNuevo - precioAnterior).abs();
    final porcentajeCambio = precioAnterior > 0 ? (diferencia / precioAnterior * 100) : 0.0;
    
    // Si el cambio de precio es menor al 5%, se considera solo cambio de fecha/hora
    return porcentajeCambio < 5.0;
  }

  static Map<String, dynamic> _calcularImpactoFinanciero(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
  ) {
    final precioAnterior = _extraerValorMonetario(datosAntiguos) ?? 0;
    final precioNuevo = _extraerValorMonetario(datosNuevos) ?? 0;
    final pagoAnterior = (datosAntiguos['montoPagado'] as num?)?.toDouble() ?? 0;
    final pagoNuevo = (datosNuevos['montoPagado'] as num?)?.toDouble() ?? 0;
    
    return {
      'diferencia_ingresos': precioNuevo - precioAnterior,
      'diferencia_pagos': pagoNuevo - pagoAnterior,
      'impacto_neto': (precioNuevo - pagoNuevo) - (precioAnterior - pagoAnterior),
      'porcentaje_cambio_ingresos': precioAnterior > 0 ? ((precioNuevo - precioAnterior) / precioAnterior * 100) : 0,
    };
  }

  static Map<String, dynamic> _limpiarDatosSensibles(Map<String, dynamic> datos) {
    final datosLimpios = Map<String, dynamic>.from(datos);
    
    // Remover campos sensibles
    datosLimpios.remove('password');
    datosLimpios.remove('token');
    datosLimpios.remove('session_id');
    
    return datosLimpios;
  }

  /// Auditar eliminación de reservas con análisis mejorado
  static Future<void> auditarEliminacionReserva({
    required String reservaId,
    required Map<String, dynamic> datosReserva,
    String? motivo,
    bool esEliminacionMasiva = false,
  }) async {
    try {
      // Calcular impacto de la eliminación
      final impactoFinanciero = _calcularImpactoEliminacion(datosReserva);
      
      String accionEspecifica = 'eliminar_reserva';
      if (esEliminacionMasiva) {
        accionEspecifica = 'eliminar_reserva_masivo';
      } else if (impactoFinanciero['es_impacto_alto'] == true) {
        accionEspecifica = 'eliminar_reserva_impacto_alto';
      }

      // Forzar nivel de riesgo según el tipo de eliminación
      final bool esAltoImpacto = accionEspecifica == 'eliminar_reserva_impacto_alto';
      final bool esEliminacionFuturas = accionEspecifica == 'eliminar_reserva_masivo'; // Cancelar reservas futuras

      await AuditProvider.registrarAccion(
        accion: accionEspecifica,
        entidad: 'reserva',
        entidadId: reservaId,
        datosAntiguos: _limpiarDatosSensibles(datosReserva),
        metadatos: {
          // Marcadores estándar para unificar formato y detección
          '_audit_processed': true,
          'fuente_original': 'ReservaAuditUtils',
          'metodo_auditoria': 'auditarEliminacionReserva',

          'cancha_nombre': datosReserva['cancha_nombre'] ?? 'No especificada',
          'sede': datosReserva['sede'] ?? 'No especificada',
          'cliente': datosReserva['nombre'] ?? 'No especificado',
          'fecha_reserva': datosReserva['fecha'] ?? 'No especificada',
          'horario': datosReserva['horario'] ?? 'No especificado',
          'motivo_eliminacion': motivo ?? 'No especificado',
          'es_eliminacion_masiva': esEliminacionMasiva,
          'impacto_financiero': impactoFinanciero,
          'valor_perdido': datosReserva['montoTotal'] ?? datosReserva['valor'] ?? 0,
          'abono_perdido': datosReserva['montoPagado'] ?? 0,
          'estado_al_eliminar': datosReserva['estado'] ?? 'desconocido',
          'tenia_precio_personalizado': datosReserva['precio_personalizado'] ?? false,
          'reserva_confirmada': datosReserva['confirmada'] ?? false,
          // Normalización de claves para análisis posterior
          'nivel_riesgo_calculado': esAltoImpacto ? 'alto' : (esEliminacionFuturas ? 'bajo' : 'medio'),
          'alertas_generadas': List<String>.from(impactoFinanciero['alertas'] ?? const <String>[]),
          'cambios_detectados': <String>['eliminacion_reserva'],
        },
        descripcion: _generarDescripcionEliminacion(datosReserva, motivo, impactoFinanciero, esAltoImpacto: esAltoImpacto),
        // Forzar nivel según tipo: alto impacto = alto, eliminar futuras = bajo, resto = medio
        nivelRiesgoForzado: esAltoImpacto ? null : (esEliminacionFuturas ? 'bajo' : 'medio'),
      );
    } catch (e) {
      debugPrint('Error auditando eliminación de reserva: $e');
    }
  }

  /// Auditar creación de reservas con análisis mejorado
  static Future<void> auditarCreacionReserva({
    required String reservaId,
    required Map<String, dynamic> datosReserva,
    bool tieneDescuento = false,
    double? descuentoAplicado,
    bool esReservaGrupal = false,
    int cantidadHoras = 1,
    Map<String, dynamic>? contextoPrecio,
  }) async {
    try {
      // Análizar el contexto de la creación
      final analisisCreacion = _analizarContextoCreacion(
        datosReserva, 
        tieneDescuento, 
        descuentoAplicado, 
        esReservaGrupal,
        contextoPrecio,
      );

      String accionEspecifica = 'crear_reserva';
      
      if (analisisCreacion['es_sospechosa'] == true) {
        accionEspecifica = 'crear_reserva_sospechosa';
      } else if (tieneDescuento && (descuentoAplicado ?? 0) > 30000) {
        accionEspecifica = 'crear_reserva_descuento_alto';
      } else if (esReservaGrupal) {
        accionEspecifica = tieneDescuento ? 'crear_reserva_grupal_descuento' : 'crear_reserva_grupal';
      } else if (tieneDescuento) {
        accionEspecifica = 'crear_reserva_precio_personalizado';
      }

      // Determinar nivel de riesgo para creaciones según reglas solicitadas
      String nivelRiesgoCreacion = 'bajo';
      final monto = (datosReserva['montoTotal'] ?? datosReserva['valor'] ?? 0) as num;
      final descuento = (descuentoAplicado ?? 0).toDouble();
      final porcentajeDescuento = (tieneDescuento && (monto + descuento) > 0)
          ? (descuento / (monto + descuento)) * 100
          : 0.0;

      // Precio personalizado activo -> riesgo mínimo MEDIO
      if (datosReserva['precio_personalizado'] == true || tieneDescuento) {
        nivelRiesgoCreacion = 'medio';
      }

      // Endurecer por descuentos poco comunes
      if (porcentajeDescuento >= 50) {
        nivelRiesgoCreacion = 'critico';
      } else if (porcentajeDescuento >= 30) {
        if (nivelRiesgoCreacion == 'bajo' || nivelRiesgoCreacion == 'medio') {
          nivelRiesgoCreacion = 'alto';
        }
      }

      await AuditProvider.registrarAccion(
        accion: accionEspecifica,
        entidad: 'reserva',
        entidadId: reservaId,
        datosNuevos: _limpiarDatosSensibles(datosReserva),
        metadatos: {
          'cancha_nombre': datosReserva['cancha_nombre'] ?? 'No especificada',
          'sede': datosReserva['sede'] ?? 'No especificada',
          'cliente': datosReserva['nombre'] ?? 'No especificado',
          'fecha_reserva': datosReserva['fecha'] ?? 'No especificada',
          'horario': datosReserva['horario'] ?? 'No especificado',
          'monto_total': datosReserva['montoTotal'] ?? datosReserva['valor'] ?? 0,
          'monto_pagado': datosReserva['montoPagado'] ?? 0,
          'tiene_descuento': tieneDescuento,
          'descuento_aplicado': descuentoAplicado ?? 0,
          'es_reserva_grupal': esReservaGrupal,
          'cantidad_horas': cantidadHoras,
          'precio_personalizado': datosReserva['precio_personalizado'] ?? false,
          'analisis_creacion': analisisCreacion,
          // Proveer nivel para unificar con ediciones
          'nivel_riesgo_calculado': nivelRiesgoCreacion,
          'alertas_generadas': List<String>.from(analisisCreacion['alertas'] ?? const <String>[]),
          'cambios_detectados': <String>['creacion_reserva'],
        },
        descripcion: _generarDescripcionCreacion(
          datosReserva, 
          tieneDescuento, 
          esReservaGrupal, 
          cantidadHoras,
          analisisCreacion,
        ),
      );
    } catch (e) {
      debugPrint('Error auditando creación de reserva: $e');
    }
  }

  /// Analizar contexto de creación para detectar anomalías
  static Map<String, dynamic> _analizarContextoCreacion(
    Map<String, dynamic> datosReserva,
    bool tieneDescuento,
    double? descuentoAplicado,
    bool esReservaGrupal,
    Map<String, dynamic>? contextoPrecio,
  ) {
    final alertas = <String>[];
    bool esSospechosa = false;
    
    final monto = (datosReserva['montoTotal'] ?? datosReserva['valor'] ?? 0) as num;
    final descuento = descuentoAplicado ?? 0;
    
    // 1. Descuento excesivo
    if (tieneDescuento && descuento > 0) {
      final porcentajeDescuento = (descuento / (monto + descuento)) * 100;
      if (porcentajeDescuento > 50) {
        alertas.add('Descuento mayor al 50%: ${porcentajeDescuento.toStringAsFixed(1)}%');
        esSospechosa = true;
      } else if (porcentajeDescuento > 30) {
        alertas.add('Descuento significativo: ${porcentajeDescuento.toStringAsFixed(1)}%');
      }
    }
    
    // 2. Precio muy bajo para el horario/fecha
    try {
      final fecha = DateTime.parse(datosReserva['fecha'].toString());
      final horario = datosReserva['horario'].toString();
      
      if (_esFechaFinDeSemana(fecha) && _esHorarioPeak(horario) && monto < 30000) {
        alertas.add('Precio bajo para fin de semana en horario peak');
        esSospechosa = true;
      }
    } catch (e) {
      // Ignorar errores de parsing
    }
    
    // 3. Reserva grupal con descuento alto
    if (esReservaGrupal && tieneDescuento && descuento > 20000) {
      alertas.add('Reserva grupal con descuento alto');
      esSospechosa = true;
    }
    
    // 4. Creación fuera de horario laboral
    final ahora = DateTime.now();
    if (ahora.hour < 6 || ahora.hour > 23) {
      alertas.add('Creación fuera de horario laboral: ${DateFormat('HH:mm').format(ahora)}');
    }
    
    return {
      'alertas': alertas,
      'es_sospechosa': esSospechosa,
      'porcentaje_descuento': tieneDescuento ? (descuento / (monto + descuento)) * 100 : 0,
      'contexto_precio': contextoPrecio ?? {},
    };
  }

  /// Calcular impacto de eliminación
  static Map<String, dynamic> _calcularImpactoEliminacion(Map<String, dynamic> datosReserva) {
    final montoTotal = (datosReserva['montoTotal'] ?? datosReserva['valor'] ?? 0) as num;
    final montoPagado = (datosReserva['montoPagado'] ?? 0) as num;
    final pendientePorPagar = montoTotal - montoPagado;
    
    bool esImpactoAlto = false;
    final alertas = <String>[];
    
    if (montoTotal >= 100000) {
      alertas.add('Eliminación de reserva de alto valor');
      esImpactoAlto = true;
    }
    
    if (montoPagado >= 50000) {
      alertas.add('Pérdida de abono significativo');
      esImpactoAlto = true;
    }
    
    // Verificar proximidad de la fecha
    try {
      final fechaReserva = DateTime.parse(datosReserva['fecha'].toString());
      final diferenciaDias = fechaReserva.difference(DateTime.now()).inDays;
      
      if (diferenciaDias <= 1) {
        alertas.add('Eliminación de reserva inmediata');
        esImpactoAlto = true;
      } else if (diferenciaDias <= 3) {
        alertas.add('Eliminación de reserva próxima');
      }
    } catch (e) {
      // Ignorar errores de parsing
    }
    
    return {
      'valor_total_perdido': montoTotal,
      'abono_perdido': montoPagado,
      'pendiente_perdido': pendientePorPagar,
      'es_impacto_alto': esImpactoAlto,
      'alertas': alertas,
    };
  }

  /// Generar descripción de eliminación
  static String _generarDescripcionEliminacion(
    Map<String, dynamic> datosReserva,
    String? motivo,
    Map<String, dynamic> impactoFinanciero,
    {bool esAltoImpacto = false}
  ) {
    final cliente = datosReserva['nombre'] ?? 'Cliente';
    final formatter = NumberFormat('#,##0', 'es_CO');
    final monto = (datosReserva['montoTotal'] ?? datosReserva['valor'] ?? 0) as num;
    
    // Prefijo coherente: Alto impacto = rojo/alarma, normal = advertencia amarilla
    String descripcion = esAltoImpacto
      ? '🚨 ELIMINACIÓN DE ALTO IMPACTO: Reserva de $cliente eliminada'
      : ' Reserva de $cliente eliminada';
    
    descripcion += ' (${formatter.format(monto)})';
    
    if (motivo != null && motivo.isNotEmpty) {
      descripcion += ' - Motivo: $motivo';
    }
    
    final alertas = impactoFinanciero['alertas'] as List<String>;
    if (alertas.isNotEmpty) {
      descripcion += ' [${alertas.join(', ')}]';
    }
    
    return descripcion;
  }

  /// Generar descripción de creación mejorada
  static String _generarDescripcionCreacion(
    Map<String, dynamic> datosReserva,
    bool tieneDescuento,
    bool esReservaGrupal,
    int cantidadHoras,
    Map<String, dynamic> analisisCreacion,
  ) {
    final cliente = datosReserva['nombre'] ?? 'Cliente';
    final cancha = datosReserva['cancha_nombre'] ?? 'Cancha';
    final formatter = NumberFormat('#,##0', 'es_CO');
    final monto = (datosReserva['montoTotal'] ?? datosReserva['valor'] ?? 0) as num;
    
    String prefijo = '';
    if (analisisCreacion['es_sospechosa'] == true) {
      prefijo = '⚠️ ';
    }
    
    String descripcion = prefijo;
    
    if (esReservaGrupal) {
      descripcion += 'Reserva grupal creada para $cliente';
      descripcion += ' ($cantidadHoras hora${cantidadHoras > 1 ? 's' : ''})';
    } else {
      descripcion += 'Nueva reserva creada para $cliente';
    }
    
    descripcion += ' en $cancha por ${formatter.format(monto)}';

    // Mostrar comparación de precio por defecto vs aplicado cuando hay precio personalizado/ descuento
    try {
      final contextoPrecio = analisisCreacion['contexto_precio'] as Map<String, dynamic>?;
      final precioOriginal = (contextoPrecio?['precio_original'] as num?)?.toDouble();
      final precioAplicado = (contextoPrecio?['precio_aplicado'] as num?)?.toDouble();
      if (precioOriginal != null && precioAplicado != null && (precioOriginal - precioAplicado).abs() > 0.01) {
        final direccion = precioAplicado < precioOriginal ? '↘️' : '↗️';
        descripcion += ' | Precio: ${formatter.format(precioOriginal)} → ${formatter.format(precioAplicado)} $direccion';
      }
    } catch (_) {
      // ignorar
    }
    
    if (tieneDescuento) {
      final porcentajeDescuento = analisisCreacion['porcentaje_descuento'] ?? 0;
      if (porcentajeDescuento > 0) {
        descripcion += ' (${porcentajeDescuento.toStringAsFixed(1)}% descuento)';
      } else {
        descripcion += ' (precio personalizado)';
      }
    }
    
    final alertas = analisisCreacion['alertas'] as List<String>;
    if (alertas.isNotEmpty) {
      descripcion += ' [${alertas.take(2).join(', ')}]';
    }
    
    return descripcion;
  }

  /// Formatear monto mejorado
  static String formatearMonto(dynamic monto) {
    if (monto == null) return '\$0';
    final valor = (monto as num).toDouble();
    final formatter = NumberFormat('#,##0', 'es_CO');
    return formatter.format(valor);
  }

  /// Formatear fecha mejorada
  static String formatearFecha(dynamic fecha) {
    if (fecha == null) return 'Sin fecha';
    
    try {
      DateTime fechaDateTime;
      if (fecha is Timestamp) {
        fechaDateTime = fecha.toDate();
      } else if (fecha is DateTime) {
        fechaDateTime = fecha;
      } else {
        fechaDateTime = DateTime.parse(fecha.toString());
      }
      
      return DateFormat('dd/MM/yyyy', 'es').format(fechaDateTime);
    } catch (e) {
      return fecha.toString();
    }
  }

  /// ✅ Auditar procesamiento de devolución
  static Future<void> auditarProcesarDevolucion({
    required String reservaId,
    required Map<String, dynamic> datosReserva,
    String? motivo,
  }) async {
    try {
      // Calcular nivel de riesgo y análisis
      final analisisDevolucion = _analizarDevolucion(datosReserva);
      
      await AuditProvider.registrarAccion(
        accion: 'procesar_devolucion',
        entidad: 'reserva',
        entidadId: reservaId,
        datosAntiguos: _limpiarDatosSensibles(datosReserva),
        datosNuevos: {
          ..._limpiarDatosSensibles(datosReserva),
          'estado': 'devolucion',
          'confirmada': null, // Campo eliminado
          'abono_entregado': false,
        },
        metadatos: {
          '_audit_processed': true,
          'fuente_original': 'ReservaAuditUtils',
          'metodo_auditoria': 'auditarProcesarDevolucion',
          
          // Información básica
          'cancha_nombre': datosReserva['cancha_nombre'] ?? 'No especificada',
          'sede': datosReserva['sede'] ?? 'No especificada',
          'cliente': datosReserva['nombre'] ?? 'No especificado',
          'fecha_reserva': datosReserva['fecha'] ?? 'No especificada',
          'horario': datosReserva['horario'] ?? 'No especificado',
          
          // Información financiera
          'monto_abono_devolver': datosReserva['montoPagado'] ?? 0,
          'monto_total_reserva': datosReserva['montoTotal'] ?? datosReserva['valor'] ?? 0,
          'porcentaje_pagado': analisisDevolucion['porcentaje_pagado'],
          'estado_anterior': analisisDevolucion['estado_anterior'],
          'reserva_completada': analisisDevolucion['reserva_completada'],
          
          // Contexto temporal
          'fecha_reserva_original': datosReserva['fecha'],
          'dias_desde_reserva': analisisDevolucion['dias_desde_reserva'],
          'horario_procesamiento': DateTime.now().toIso8601String(),
          'es_fuera_horario_laboral': analisisDevolucion['es_fuera_horario_laboral'],
          
          // Análisis de riesgo
          'nivel_riesgo_calculado': analisisDevolucion['nivel_riesgo'],
          'puntuacion_riesgo': analisisDevolucion['puntuacion_riesgo'],
          'alertas_generadas': analisisDevolucion['alertas'],
          'cambios_detectados': <String>['procesar_devolucion'],
          
          // Motivo si está disponible
          'motivo_devolucion': motivo ?? 'No especificado',
        },
        descripcion: _generarDescripcionProcesarDevolucion(datosReserva, analisisDevolucion),
      );
    } catch (e) {
      debugPrint('Error auditando procesamiento de devolución: $e');
    }
  }

  /// ✅ Auditar confirmación de devolución (entrega del abono)
  static Future<void> auditarConfirmarDevolucion({
    required String reservaId,
    required Map<String, dynamic> datosReserva,
  }) async {
    try {
      await AuditProvider.registrarAccion(
        accion: 'confirmar_devolucion',
        entidad: 'reserva',
        entidadId: reservaId,
        datosAntiguos: {
          ..._limpiarDatosSensibles(datosReserva),
          'abono_entregado': false,
        },
        datosNuevos: {
          ..._limpiarDatosSensibles(datosReserva),
          'abono_entregado': true,
        },
        metadatos: {
          '_audit_processed': true,
          'fuente_original': 'ReservaAuditUtils',
          'metodo_auditoria': 'auditarConfirmarDevolucion',
          
          'cancha_nombre': datosReserva['cancha_nombre'] ?? 'No especificada',
          'sede': datosReserva['sede'] ?? 'No especificada',
          'cliente': datosReserva['nombre'] ?? 'No especificado',
          'monto_abono_devuelto': datosReserva['montoPagado'] ?? 0,
          'fecha_confirmacion': DateTime.now().toIso8601String(),
          
          'nivel_riesgo_calculado': 'bajo', // Confirmación administrativa
          'puntuacion_riesgo': 5, // Muy bajo riesgo
          'alertas_generadas': <String>[],
          'cambios_detectados': <String>['confirmar_devolucion'],
        },
        descripcion: _generarDescripcionConfirmarDevolucion(datosReserva),
        nivelRiesgoForzado: 'bajo', // Siempre bajo para confirmaciones
      );
    } catch (e) {
      debugPrint('Error auditando confirmación de devolución: $e');
    }
  }

  /// Analizar devolución y calcular nivel de riesgo
  static Map<String, dynamic> _analizarDevolucion(Map<String, dynamic> datosReserva) {
    final alertas = <String>[];
    int puntuacionRiesgo = 15; // Base por ser devolución
    
    final montoAbono = (datosReserva['montoPagado'] ?? 0) as num;
    final montoTotal = (datosReserva['montoTotal'] ?? datosReserva['valor'] ?? 0) as num;
    final porcentajePagado = montoTotal > 0 ? (montoAbono / montoTotal * 100) : 0.0;
    final reservaCompletada = porcentajePagado >= 100;
    
    // 1. FACTOR MONTO DEL ABONO (máximo 45 puntos)
    final montoAbonoDouble = montoAbono.toDouble();
    final formatter = NumberFormat('#,##0', 'es_CO');
    if (montoAbonoDouble >= 100000) {
      puntuacionRiesgo += 45;
      alertas.add('DEVOLUCIÓN DE ALTO VALOR: \$${formatter.format(montoAbonoDouble.toInt())} a devolver');
    } else if (montoAbonoDouble >= 50000) {
      puntuacionRiesgo += 30;
      alertas.add('Devolución de valor significativo: \$${formatter.format(montoAbonoDouble.toInt())}');
    } else if (montoAbonoDouble >= 20000) {
      puntuacionRiesgo += 15;
    } else {
      puntuacionRiesgo += 5;
    }
    
    // 2. FACTOR ESTADO DE LA RESERVA (máximo 25 puntos)
    if (reservaCompletada) {
      puntuacionRiesgo += 25;
      alertas.add('DEVOLUCIÓN DE RESERVA COMPLETADA: Cliente ya había pagado el total');
    } else if (porcentajePagado > 70) {
      puntuacionRiesgo += 15;
      alertas.add('Devolución de reserva con más del 70% pagado');
    } else if (porcentajePagado > 30) {
      puntuacionRiesgo += 8;
    } else {
      puntuacionRiesgo += 3;
    }
    
    // 3. FACTOR CONTEXTO TEMPORAL (máximo 15 puntos)
    final ahora = DateTime.now();
    if (ahora.hour < 5 || ahora.hour >= 23) {
      puntuacionRiesgo += 15;
      alertas.add('DEVOLUCIÓN PROCESADA FUERA DE HORARIO: Entre 11pm-5am');
    }
    
    // 4. FACTOR PATRONES (máximo 15 puntos)
    // TODO: Implementar consulta de historial de devoluciones del cliente
    // Por ahora, estructura lista para mejoras futuras
    
    // Calcular nivel de riesgo
    String nivelRiesgo;
    if (puntuacionRiesgo >= UmbralesRiesgo.critico) {
      nivelRiesgo = 'critico';
    } else if (puntuacionRiesgo >= UmbralesRiesgo.alto) {
      nivelRiesgo = 'alto';
    } else if (puntuacionRiesgo >= UmbralesRiesgo.medio) {
      nivelRiesgo = 'medio';
    } else {
      nivelRiesgo = 'bajo';
    }
    
    // Calcular días desde la reserva
    int diasDesdeReserva = 0;
    try {
      final fechaReserva = DateTime.parse(datosReserva['fecha'].toString());
      diasDesdeReserva = DateTime.now().difference(fechaReserva).inDays;
    } catch (e) {
      // Ignorar errores
    }
    
    return {
      'nivel_riesgo': nivelRiesgo,
      'puntuacion_riesgo': puntuacionRiesgo,
      'alertas': alertas,
      'monto_abono': montoAbonoDouble,
      'monto_total': montoTotal.toDouble(),
      'porcentaje_pagado': porcentajePagado,
      'reserva_completada': reservaCompletada,
      'estado_anterior': reservaCompletada ? 'completo' : (porcentajePagado > 50 ? 'parcial_alto' : 'parcial_bajo'),
      'dias_desde_reserva': diasDesdeReserva,
      'es_fuera_horario_laboral': ahora.hour < 5 || ahora.hour >= 23,
    };
  }

  /// Generar descripción para procesar devolución
  static String _generarDescripcionProcesarDevolucion(
    Map<String, dynamic> datosReserva,
    Map<String, dynamic> analisis,
  ) {
    final cliente = datosReserva['nombre'] ?? 'Cliente';
    final montoAbono = analisis['monto_abono'] as double;
    final nivelRiesgo = analisis['nivel_riesgo'] as String;
    final formatter = NumberFormat('#,##0', 'es_CO');
    
    String prefijo = '';
    if (nivelRiesgo == 'critico') {
      prefijo = '🚨 ';
    } else if (nivelRiesgo == 'alto') {
      prefijo = '🔴 ';
    } else if (nivelRiesgo == 'medio') {
      prefijo = '🟡 ';
    }
    
    String descripcion = '${prefijo}Devolución procesada para $cliente';
    descripcion += ' - Abono a devolver: \$${formatter.format(montoAbono.toInt())}';
    
    if (analisis['reserva_completada'] == true) {
      descripcion += ' (Reserva completada)';
    }
    
    final alertas = analisis['alertas'] as List<String>;
    if (alertas.isNotEmpty) {
      descripcion += ' [${alertas.first}]';
    }
    
    return descripcion;
  }

  /// Generar descripción para confirmar devolución
  static String _generarDescripcionConfirmarDevolucion(Map<String, dynamic> datosReserva) {
    final cliente = datosReserva['nombre'] ?? 'Cliente';
    final montoAbono = (datosReserva['montoPagado'] ?? 0) as num;
    final formatter = NumberFormat('#,##0', 'es_CO');
    
    return '✅ Devolución confirmada para $cliente - Abono entregado: \$${formatter.format(montoAbono.toInt())}';
  }

  /// ✅ Auditar creación de promoción
  static Future<void> auditarCreacionPromocion({
    required String promocionId,
    required Map<String, dynamic> datosPromocion,
    double? precioNormal,
  }) async {
    try {
      final analisisPromocion = _analizarPromocion(datosPromocion, precioNormal, null);
      
      await AuditProvider.registrarAccion(
        accion: 'crear_promocion',
        entidad: 'promocion',
        entidadId: promocionId,
        datosNuevos: _limpiarDatosSensibles(datosPromocion),
        metadatos: {
          '_audit_processed': true,
          'fuente_original': 'ReservaAuditUtils',
          'metodo_auditoria': 'auditarCreacionPromocion',
          
          'cancha_nombre': datosPromocion['cancha_nombre'] ?? 'No especificada',
          'sede': datosPromocion['sede'] ?? 'No especificada',
          'fecha': datosPromocion['fecha'] ?? 'No especificada',
          'horario': datosPromocion['horario'] ?? 'No especificado',
          'precio_promocional': datosPromocion['precio_promocional'] ?? 0,
          'precio_normal': precioNormal ?? 0,
          'descuento_aplicado': analisisPromocion['descuento_aplicado'],
          'porcentaje_descuento': analisisPromocion['porcentaje_descuento'],
          
          'nivel_riesgo_calculado': analisisPromocion['nivel_riesgo'],
          'puntuacion_riesgo': analisisPromocion['puntuacion_riesgo'],
          'alertas_generadas': analisisPromocion['alertas'],
          'cambios_detectados': <String>['creacion_promocion'],
        },
        descripcion: _generarDescripcionCreacionPromocion(datosPromocion, analisisPromocion),
      );
    } catch (e) {
      debugPrint('Error auditando creación de promoción: $e');
    }
  }

  /// ✅ Auditar edición de promoción
  static Future<void> auditarEdicionPromocion({
    required String promocionId,
    required Map<String, dynamic> datosAntiguos,
    required Map<String, dynamic> datosNuevos,
    double? precioNormal,
  }) async {
    try {
      final analisisPromocion = _analizarPromocion(datosNuevos, precioNormal, datosAntiguos);
      
      await AuditProvider.registrarAccion(
        accion: 'editar_promocion',
        entidad: 'promocion',
        entidadId: promocionId,
        datosAntiguos: _limpiarDatosSensibles(datosAntiguos),
        datosNuevos: _limpiarDatosSensibles(datosNuevos),
        metadatos: {
          '_audit_processed': true,
          'fuente_original': 'ReservaAuditUtils',
          'metodo_auditoria': 'auditarEdicionPromocion',
          
          'cancha_nombre': datosNuevos['cancha_nombre'] ?? datosAntiguos['cancha_nombre'] ?? 'No especificada',
          'sede': datosNuevos['sede'] ?? datosAntiguos['sede'] ?? 'No especificada',
          'fecha': datosNuevos['fecha'] ?? datosAntiguos['fecha'] ?? 'No especificada',
          'horario': datosNuevos['horario'] ?? datosAntiguos['horario'] ?? 'No especificado',
          'precio_promocional_anterior': datosAntiguos['precio_promocional'] ?? 0,
          'precio_promocional_nuevo': datosNuevos['precio_promocional'] ?? 0,
          'precio_normal': precioNormal ?? 0,
          'descuento_aplicado': analisisPromocion['descuento_aplicado'],
          'porcentaje_descuento': analisisPromocion['porcentaje_descuento'],
          'cambio_precio': analisisPromocion['cambio_precio'],
          'porcentaje_cambio_precio': analisisPromocion['porcentaje_cambio_precio'],
          
          'nivel_riesgo_calculado': analisisPromocion['nivel_riesgo'],
          'puntuacion_riesgo': analisisPromocion['puntuacion_riesgo'],
          'alertas_generadas': analisisPromocion['alertas'],
          'cambios_detectados': analisisPromocion['cambios'],
        },
        descripcion: _generarDescripcionEdicionPromocion(datosAntiguos, datosNuevos, analisisPromocion),
      );
    } catch (e) {
      debugPrint('Error auditando edición de promoción: $e');
    }
  }

  /// ✅ Auditar eliminación de promoción
  static Future<void> auditarEliminacionPromocion({
    required String promocionId,
    required Map<String, dynamic> datosPromocion,
  }) async {
    try {
      await AuditProvider.registrarAccion(
        accion: 'eliminar_promocion',
        entidad: 'promocion',
        entidadId: promocionId,
        datosAntiguos: _limpiarDatosSensibles(datosPromocion),
        metadatos: {
          '_audit_processed': true,
          'fuente_original': 'ReservaAuditUtils',
          'metodo_auditoria': 'auditarEliminacionPromocion',
          
          'cancha_nombre': datosPromocion['cancha_nombre'] ?? 'No especificada',
          'sede': datosPromocion['sede'] ?? 'No especificada',
          'fecha': datosPromocion['fecha'] ?? 'No especificada',
          'horario': datosPromocion['horario'] ?? 'No especificado',
          'precio_promocional': datosPromocion['precio_promocional'] ?? 0,
          
          'nivel_riesgo_calculado': 'medio', // Eliminación siempre medio
          'puntuacion_riesgo': 20,
          'alertas_generadas': <String>[],
          'cambios_detectados': <String>['eliminacion_promocion'],
        },
        descripcion: _generarDescripcionEliminacionPromocion(datosPromocion),
        nivelRiesgoForzado: 'medio',
      );
    } catch (e) {
      debugPrint('Error auditando eliminación de promoción: $e');
    }
  }

  /// Analizar promoción y calcular nivel de riesgo
  static Map<String, dynamic> _analizarPromocion(
    Map<String, dynamic> datosPromocion,
    double? precioNormal,
    Map<String, dynamic>? datosAntiguos,
  ) {
    final alertas = <String>[];
    final cambios = <String>[];
    int puntuacionRiesgo = 10; // Base por ser operación de promoción
    
    final precioPromocional = (datosPromocion['precio_promocional'] as num?)?.toDouble() ?? 0.0;
    final precioNormalDouble = precioNormal ?? 0.0;
    final descuento = precioNormalDouble > 0 ? precioNormalDouble - precioPromocional : 0.0;
    final porcentajeDescuento = precioNormalDouble > 0 ? (descuento / precioNormalDouble * 100) : 0.0;
    
    final formatter = NumberFormat('#,##0', 'es_CO');
    
    // 1. FACTOR DESCUENTO APLICADO (máximo 50 puntos)
    if (precioNormalDouble > 0) {
      if (porcentajeDescuento >= 70) {
        puntuacionRiesgo += 50;
        alertas.add('🚨 DESCUENTO EXTREMO: ${porcentajeDescuento.toStringAsFixed(1)}% (\$${formatter.format(descuento.toInt())})');
      } else if (porcentajeDescuento >= 50) {
        puntuacionRiesgo += 40;
        alertas.add('🔴 DESCUENTO CRÍTICO: ${porcentajeDescuento.toStringAsFixed(1)}% (\$${formatter.format(descuento.toInt())})');
      } else if (porcentajeDescuento >= 30) {
        puntuacionRiesgo += 25;
        alertas.add('🟡 Descuento significativo: ${porcentajeDescuento.toStringAsFixed(1)}% (\$${formatter.format(descuento.toInt())})');
      } else if (porcentajeDescuento >= 15) {
        puntuacionRiesgo += 12;
        alertas.add('Descuento moderado: ${porcentajeDescuento.toStringAsFixed(1)}%');
      } else if (porcentajeDescuento > 0) {
        puntuacionRiesgo += 5;
      }
    }
    
    // 2. FACTOR MONTO ABSOLUTO DEL DESCUENTO (máximo 20 puntos)
    if (descuento >= 100000) {
      puntuacionRiesgo += 20;
      alertas.add('💰 Descuento de alto valor: \$${formatter.format(descuento.toInt())}');
    } else if (descuento >= 50000) {
      puntuacionRiesgo += 12;
      alertas.add('Descuento de valor significativo: \$${formatter.format(descuento.toInt())}');
    } else if (descuento >= 20000) {
      puntuacionRiesgo += 6;
    }
    
    // 3. FACTOR CAMBIO DE PRECIO (solo para ediciones)
      if (datosAntiguos != null) {
        final precioAnteriorRaw = datosAntiguos['precio_promocional'];
        final precioAnterior = precioAnteriorRaw is num ? precioAnteriorRaw.toDouble() : 0.0;
        if ((precioPromocional - precioAnterior).abs() > 0.01) {
          final cambioPrecio = precioPromocional - precioAnterior;
          final porcentajeCambio = precioAnterior > 0 ? (cambioPrecio.abs() / precioAnterior * 100) : 0.0;
          
          cambios.add('Precio promocional: \$${formatter.format(precioAnterior.toInt())} → \$${formatter.format(precioPromocional.toInt())}');
          
          if (porcentajeCambio >= 50) {
            puntuacionRiesgo += 20;
            alertas.add('🔄 Cambio extremo de precio promocional: ${porcentajeCambio.toStringAsFixed(1)}%');
          } else if (porcentajeCambio >= 30) {
            puntuacionRiesgo += 12;
            alertas.add('Cambio significativo de precio promocional: ${porcentajeCambio.toStringAsFixed(1)}%');
          } else if (porcentajeCambio >= 15) {
            puntuacionRiesgo += 6;
          }
        }
      }
    
    // 4. FACTOR CONTEXTO TEMPORAL (máximo 10 puntos)
    try {
      final fecha = DateTime.parse(datosPromocion['fecha'].toString());
      final ahora = DateTime.now();
      final diasHastaFecha = fecha.difference(ahora).inDays;
      
      if (diasHastaFecha <= 0) {
        puntuacionRiesgo += 10;
        alertas.add('⚠️ Promoción para fecha pasada o hoy');
      } else if (diasHastaFecha <= 1) {
        puntuacionRiesgo += 5;
        alertas.add('Promoción para mañana');
      }
      
      // Verificar si es fin de semana
      if (_esFechaFinDeSemana(fecha)) {
        if (porcentajeDescuento >= 30) {
          puntuacionRiesgo += 8;
          alertas.add('🎪 Descuento alto en fin de semana');
        }
      }
    } catch (e) {
      // Ignorar errores de parsing
    }
    
    // Calcular nivel de riesgo
    String nivelRiesgo;
    if (puntuacionRiesgo >= UmbralesRiesgo.critico) {
      nivelRiesgo = 'critico';
    } else if (puntuacionRiesgo >= UmbralesRiesgo.alto) {
      nivelRiesgo = 'alto';
    } else if (puntuacionRiesgo >= UmbralesRiesgo.medio) {
      nivelRiesgo = 'medio';
    } else {
      nivelRiesgo = 'bajo';
    }
    
    final resultado = <String, dynamic>{
      'nivel_riesgo': nivelRiesgo,
      'puntuacion_riesgo': puntuacionRiesgo,
      'alertas': alertas,
      'cambios': cambios,
      'descuento_aplicado': descuento,
      'porcentaje_descuento': porcentajeDescuento,
      'precio_promocional': precioPromocional,
      'precio_normal': precioNormalDouble,
    };
    
    if (datosAntiguos != null) {
      final precioAnteriorRaw = datosAntiguos['precio_promocional'];
      final precioAnterior = precioAnteriorRaw is num ? precioAnteriorRaw.toDouble() : 0.0;
      resultado['cambio_precio'] = precioPromocional - precioAnterior;
      resultado['porcentaje_cambio_precio'] = precioAnterior > 0
          ? ((precioPromocional - precioAnterior).abs() / precioAnterior * 100)
          : 0.0;
    }
    
    return resultado;
  }

  /// Generar descripción para creación de promoción
  static String _generarDescripcionCreacionPromocion(
    Map<String, dynamic> datosPromocion,
    Map<String, dynamic> analisis,
  ) {
    final cancha = datosPromocion['cancha_nombre'] ?? 'Cancha';
    final horario = datosPromocion['horario'] ?? 'Horario';
    final fecha = datosPromocion['fecha'] ?? 'Fecha';
    final nivelRiesgo = analisis['nivel_riesgo'] as String;
    final formatter = NumberFormat('#,##0', 'es_CO');
    final precioPromo = analisis['precio_promocional'] as double;
    final porcentajeDesc = analisis['porcentaje_descuento'] as double;
    
    String prefijo = '';
    if (nivelRiesgo == 'critico') {
      prefijo = '🚨 ';
    } else if (nivelRiesgo == 'alto') {
      prefijo = '🔴 ';
    } else if (nivelRiesgo == 'medio') {
      prefijo = '🟡 ';
    }
    
    String descripcion = '${prefijo}Promoción creada: $cancha - $horario ($fecha)';
    descripcion += ' - Precio: \$${formatter.format(precioPromo.toInt())}';
    
    if (porcentajeDesc > 0) {
      descripcion += ' (${porcentajeDesc.toStringAsFixed(1)}% descuento)';
    }
    
    final alertas = analisis['alertas'] as List<String>;
    if (alertas.isNotEmpty) {
      descripcion += ' [${alertas.first}]';
    }
    
    return descripcion;
  }

  /// Generar descripción para edición de promoción
  static String _generarDescripcionEdicionPromocion(
    Map<String, dynamic> datosAntiguos,
    Map<String, dynamic> datosNuevos,
    Map<String, dynamic> analisis,
  ) {
    final cancha = datosNuevos['cancha_nombre'] ?? datosAntiguos['cancha_nombre'] ?? 'Cancha';
    final horario = datosNuevos['horario'] ?? datosAntiguos['horario'] ?? 'Horario';
    final nivelRiesgo = analisis['nivel_riesgo'] as String;
    final formatter = NumberFormat('#,##0', 'es_CO');
    final precioAnterior = (datosAntiguos['precio_promocional'] as num?)?.toDouble() ?? 0.0;
    final precioNuevo = analisis['precio_promocional'] as double;
    final porcentajeDesc = analisis['porcentaje_descuento'] as double;
    
    String prefijo = '';
    if (nivelRiesgo == 'critico') {
      prefijo = '🚨 ';
    } else if (nivelRiesgo == 'alto') {
      prefijo = '🔴 ';
    } else if (nivelRiesgo == 'medio') {
      prefijo = '🟡 ';
    }
    
    String descripcion = '${prefijo}Promoción editada: $cancha - $horario';
    descripcion += ' - Precio: \$${formatter.format(precioAnterior.toInt())} → \$${formatter.format(precioNuevo.toInt())}';
    
    if (porcentajeDesc > 0) {
      descripcion += ' (${porcentajeDesc.toStringAsFixed(1)}% descuento)';
    }
    
    final cambios = analisis['cambios'] as List<String>;
    if (cambios.isNotEmpty) {
      descripcion += ' | ${cambios.first}';
    }
    
    final alertas = analisis['alertas'] as List<String>;
    if (alertas.isNotEmpty) {
      descripcion += ' [${alertas.first}]';
    }
    
    return descripcion;
  }

  /// Generar descripción para eliminación de promoción
  static String _generarDescripcionEliminacionPromocion(Map<String, dynamic> datosPromocion) {
    final cancha = datosPromocion['cancha_nombre'] ?? 'Cancha';
    final horario = datosPromocion['horario'] ?? 'Horario';
    final fecha = datosPromocion['fecha'] ?? 'Fecha';
    final formatter = NumberFormat('#,##0', 'es_CO');
    final precioPromo = (datosPromocion['precio_promocional'] as num?)?.toDouble() ?? 0.0;
    
    return '🟡 Promoción eliminada: $cancha - $horario ($fecha) - Precio: \$${formatter.format(precioPromo.toInt())}';
  }
}