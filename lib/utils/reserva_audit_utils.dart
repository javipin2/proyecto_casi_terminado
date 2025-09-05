// lib/utils/reserva_audit_utils_mejorado.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../providers/audit_provider.dart';

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
          'cancha_nombre': datosNuevos['cancha_nombre'] ?? datosAntiguos['cancha_nombre'],
          'sede': datosNuevos['sede'] ?? datosAntiguos['sede'],
          'cliente': datosNuevos['nombre'] ?? datosAntiguos['nombre'],
          'fecha_reserva': datosNuevos['fecha'] ?? datosAntiguos['fecha'],
          'horario': datosNuevos['horario'] ?? datosAntiguos['horario'],
          
          // Análisis de cambios detallado
          ...analisisCambios,
          
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
    final nivelRiesgo = _calcularNivelRiesgoMejorado(
      analisisPrecios,
      analisisFechas,
      analisisPagos,
      alertasGeneradas,
    );

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
      alertas.add('🚨 CAMBIO DE PRECIO EXTREMO: ${porcentajeCambio.toStringAsFixed(1)}% (${diferencia > 0 ? 'Aumento' : 'Descuento'} de \$${formatter.format(diferencia.abs())})');
    } else if (porcentajeCambio >= 50) {
      severidad = 'CRÍTICO';
      esCritico = true;
      alertas.add('🔴 CAMBIO DE PRECIO CRÍTICO: ${porcentajeCambio.toStringAsFixed(1)}% (${diferencia > 0 ? 'Aumento' : 'Descuento'} de \$${formatter.format(diferencia.abs())})');
    } else if (porcentajeCambio >= 30) {
      severidad = 'ALTO';
      alertas.add('🟠 Cambio de precio significativo: ${porcentajeCambio.toStringAsFixed(1)}% (\$${formatter.format(diferencia.abs())})');
    } else if (porcentajeCambio >= 15) {
      severidad = 'MEDIO';
      alertas.add('🟡 Cambio de precio moderado: ${porcentajeCambio.toStringAsFixed(1)}% (\$${formatter.format(diferencia.abs())})');
    } else if (porcentajeCambio > 0) {
      severidad = 'BAJO';
      alertas.add('🔵 Cambio de precio menor: ${porcentajeCambio.toStringAsFixed(1)}% (\$${formatter.format(diferencia.abs())})');
    }

    // Detectar descuentos inusuales - MANTENER CONSISTENTE
    if (diferencia < 0 && diferencia.abs() > 50000) {
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
          alertas.add('📅 Cambio de fecha significativo: ${diferenciaEnDias} días de diferencia');
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
    
    if (datosAntiguos['correo'] != datosNuevos['correo']) {
      cambios.add('Email: ${datosAntiguos['correo'] ?? 'Sin email'} → ${datosNuevos['correo'] ?? 'Sin email'}');
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
      
      if (descuento > precioAnterior * 0.3) { // Más del 30% de descuento
        alertas.add('🎯 PRECIO PERSONALIZADO CON DESCUENTO ALTO: ${(descuento/precioAnterior*100).toStringAsFixed(1)}%');
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

  /// Calcular nivel de riesgo mejorado
  static String _calcularNivelRiesgoMejorado(
    Map<String, dynamic> analisisPrecios,
    Map<String, dynamic> analisisFechas,
    Map<String, dynamic> analisisPagos,
    List<String> alertasGeneradas,
  ) {
    int puntuacionRiesgo = 0;
    
    // Factores de precio (peso: 40%)
    if (analisisPrecios['es_cambio_critico'] == true) {
      final porcentaje = analisisPrecios['porcentaje_cambio'] ?? 0.0;
      if (porcentaje >= 70) puntuacionRiesgo += 40;
      else if (porcentaje >= 50) puntuacionRiesgo += 35;
      else if (porcentaje >= 30) puntuacionRiesgo += 25;
      else if (porcentaje >= 15) puntuacionRiesgo += 15;
    }
    
    // Factores de fecha/horario (peso: 20%)
    final alertasFechas = analisisFechas['alertas'] as List<String>;
    if (alertasFechas.any((a) => a.contains('🚨'))) puntuacionRiesgo += 20;
    else if (alertasFechas.any((a) => a.contains('⚠️'))) puntuacionRiesgo += 15;
    else if (alertasFechas.isNotEmpty) puntuacionRiesgo += 10;
    
    // Factores de pagos (peso: 20%)
    final alertasPagos = analisisPagos['alertas'] as List<String>;
    if (alertasPagos.any((a) => a.contains('💸'))) puntuacionRiesgo += 15;
    else if (alertasPagos.any((a) => a.contains('💰'))) puntuacionRiesgo += 10;
    
    // Patrones sospechosos (peso: 20%)
    final cantidadAlertas = alertasGeneradas.length;
    if (cantidadAlertas >= 5) puntuacionRiesgo += 20;
    else if (cantidadAlertas >= 3) puntuacionRiesgo += 15;
    else if (cantidadAlertas >= 1) puntuacionRiesgo += 10;
    
    // Clasificación final
    if (puntuacionRiesgo >= 70) return 'critico';
    if (puntuacionRiesgo >= 45) return 'alto';
    if (puntuacionRiesgo >= 25) return 'medio';
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
    if (nivelRiesgo == 'critico') prefijo += '🚨 ';
    else if (nivelRiesgo == 'alto') prefijo += '🔴 ';
    else if (nivelRiesgo == 'medio') prefijo += '🟡 ';
    
    if (cambios.isEmpty) {
      return '${prefijo}Reserva de $cliente editada sin cambios críticos detectados';
    }
    
    String tipoModificacion = '';
    if (datosNuevos['precio_personalizado'] == true) {
      tipoModificacion = ' (Precio Personalizado)';
    }
    
    if (cambios.length == 1) {
      return '${prefijo}Reserva de $cliente: ${cambios.first}$tipoModificacion';
    }
    
    final cambiosPrincipales = cambios.take(2).join(' | ');
    final sufijo = cambios.length > 2 ? ' +${cambios.length - 2} cambios más' : '';
    
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
    
    // Enmascarar email parcialmente
    if (datosLimpios.containsKey('correo') && datosLimpios['correo'] != null) {
      final email = datosLimpios['correo'].toString();
      if (email.contains('@') && email.length > 4) {
        final partes = email.split('@');
        if (partes[0].length > 2) {
          datosLimpios['correo'] = '${partes[0].substring(0, 2)}***@${partes[1]}';
        }
      }
    }
    
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

      await AuditProvider.registrarAccion(
        accion: accionEspecifica,
        entidad: 'reserva',
        entidadId: reservaId,
        datosAntiguos: _limpiarDatosSensibles(datosReserva),
        metadatos: {
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
        },
        descripcion: _generarDescripcionEliminacion(datosReserva, motivo, impactoFinanciero),
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
  ) {
    final cliente = datosReserva['nombre'] ?? 'Cliente';
    final formatter = NumberFormat('#,##0', 'es_CO');
    final monto = (datosReserva['montoTotal'] ?? datosReserva['valor'] ?? 0) as num;
    
    String descripcion = 'Reserva de $cliente eliminada';
    
    if (impactoFinanciero['es_impacto_alto'] == true) {
      descripcion = '🚨 ELIMINACIÓN DE ALTO IMPACTO: $descripcion';
    }
    
    descripcion += ' (\${formatter.format(monto)})';
    
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
    
    descripcion += ' en $cancha por \${formatter.format(monto)}';
    
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
    return '\${formatter.format(valor)}';
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
}