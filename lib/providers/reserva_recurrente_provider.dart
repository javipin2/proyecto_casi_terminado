// lib/providers/reserva_recurrente_provider.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:reserva_canchas/providers/audit_provider.dart';
import '../models/reserva_recurrente.dart';
import '../models/reserva.dart';
import '../models/cancha.dart';
import '../models/horario.dart';

class ReservaRecurrenteProvider with ChangeNotifier {
  List<ReservaRecurrente> _reservasRecurrentes = [];
  bool _isLoading = false;
  String _errorMessage = '';

  List<ReservaRecurrente> get reservasRecurrentes => _reservasRecurrentes;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;

  /// Cargar todas las reservas recurrentes
  Future<void> fetchReservasRecurrentes({String? sede}) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      // ✅ CARGAR TODAS LAS RESERVAS RECURRENTES (activas, pausadas, canceladas)
      Query query = FirebaseFirestore.instance
          .collection('reservas_recurrentes');
      
      if (sede != null) {
        query = query.where('sede', isEqualTo: sede);
      }

      final querySnapshot = await query.get();
      _reservasRecurrentes = querySnapshot.docs
          .map((doc) => ReservaRecurrente.fromFirestore(doc))
          .toList();

      debugPrint('📊 Reservas recurrentes cargadas: ${_reservasRecurrentes.length}');
      debugPrint('📊 Activas: ${_reservasRecurrentes.where((r) => r.estado == EstadoRecurrencia.activa).length}');
      debugPrint('📊 Canceladas: ${_reservasRecurrentes.where((r) => r.estado == EstadoRecurrencia.cancelada).length}');
    } catch (e) {
      _errorMessage = 'Error al cargar reservas recurrentes: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Crear una nueva reserva recurrente
  Future<String> crearReservaRecurrente(ReservaRecurrente reserva) async {
  try {
    final docRef = FirebaseFirestore.instance
        .collection('reservas_recurrentes')
        .doc();
    
    final reservaConId = reserva.copyWith(id: docRef.id);
    await docRef.set(reservaConId.toFirestore());
    
    // 🔍 AUDITORÍA: Registrar creación de reserva recurrente
    await AuditProvider.registrarAccion(
      accion: reserva.precioPersonalizado ? 'crear_reserva_recurrente_precio_personalizado' : 'crear_reserva_recurrente',
      entidad: 'reserva_recurrente',
      entidadId: docRef.id,
      datosNuevos: reservaConId.toFirestore(),
      metadatos: {
        'cancha_id': reserva.canchaId,
        'sede': reserva.sede,
        'cliente': reserva.clienteNombre,
        'horario': reserva.horario,
        'dias_semana': reserva.diasSemana,
        'fecha_inicio': reserva.fechaInicio.toIso8601String(),
        'fecha_fin': reserva.fechaFin?.toIso8601String(),
        'monto_total': reserva.montoTotal,
        'descuento_aplicado': reserva.descuentoAplicado ?? 0,
      },
      descripcion: reserva.precioPersonalizado 
        ? 'Reserva recurrente creada con precio personalizado'
        : 'Nueva reserva recurrente creada',
    );
    
    // Agregar a la lista local
    _reservasRecurrentes.add(reservaConId);
    notifyListeners();
    
    return docRef.id;
  } catch (e) {
    _errorMessage = 'Error al crear reserva recurrente: $e';
    debugPrint(_errorMessage);
    throw Exception(_errorMessage);
  }
}




  /// Excluir un día específico de una reserva recurrente
  Future<void> excluirDiaReservaRecurrente(String reservaId, DateTime fecha) async {
    try {
      final index = _reservasRecurrentes.indexWhere((r) => r.id == reservaId);
      if (index == -1) throw Exception('Reserva recurrente no encontrada');

      final reservaActualizada = _reservasRecurrentes[index].excluirDia(fecha);
      
      await FirebaseFirestore.instance
          .collection('reservas_recurrentes')
          .doc(reservaId)
          .update(reservaActualizada.toFirestore());
      
      _reservasRecurrentes[index] = reservaActualizada;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al excluir día: $e';
      debugPrint(_errorMessage);
      throw Exception(_errorMessage);
    }
  }

  /// Incluir un día previamente excluido
  Future<void> incluirDiaReservaRecurrente(String reservaId, DateTime fecha) async {
    try {
      final index = _reservasRecurrentes.indexWhere((r) => r.id == reservaId);
      if (index == -1) throw Exception('Reserva recurrente no encontrada');

      final reservaActualizada = _reservasRecurrentes[index].incluirDia(fecha);
      
      await FirebaseFirestore.instance
          .collection('reservas_recurrentes')
          .doc(reservaId)
          .update(reservaActualizada.toFirestore());
      
      _reservasRecurrentes[index] = reservaActualizada;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al incluir día: $e';
      debugPrint(_errorMessage);
      throw Exception(_errorMessage);
    }
  }

  /// ✅ MÉTODO PRINCIPAL CORREGIDO - OBTENER RESERVAS ACTIVAS PARA UNA FECHA
  List<ReservaRecurrente> obtenerReservasActivasParaFecha(DateTime fecha, {String? sede, String? canchaId}) {
  final ahora = DateTime.now();
  final fechaNormalizada = DateTime(fecha.year, fecha.month, fecha.day);
  final hoyNormalizado = DateTime(ahora.year, ahora.month, ahora.day);
  
  debugPrint('🔍 === FILTRANDO RESERVAS RECURRENTES ===');
  debugPrint('🔍 Fecha solicitada: ${DateFormat('yyyy-MM-dd').format(fecha)}');
  debugPrint('🔍 Sede filtro: $sede');
  debugPrint('🔍 Cancha filtro: $canchaId');
  debugPrint('🔍 Total reservas recurrentes disponibles: ${_reservasRecurrentes.length}');

  final reservasFiltradas = _reservasRecurrentes.where((reserva) {
    // ✅ FILTROS BÁSICOS
    if (sede != null && reserva.sede != sede) {
      debugPrint('   ❌ ${reserva.clienteNombre}: Sede incorrecta (${reserva.sede} != $sede)');
      return false;
    }
    
    if (canchaId != null && reserva.canchaId != canchaId) {
      debugPrint('   ❌ ${reserva.clienteNombre}: Cancha incorrecta (${reserva.canchaId} != $canchaId)');
      return false;
    }

    // ✅ LÓGICA SIMPLIFICADA POR FECHA
    if (fechaNormalizada.isBefore(hoyNormalizado)) {
      // FECHAS PASADAS: Solo mostrar si la reserva estaba activa en esa fecha
      final resultado = _reservaEstabaActivaEnFechaPasada(reserva, fecha);
      debugPrint('   ${resultado ? '✅' : '❌'} ${reserva.clienteNombre}: Fecha pasada - ${resultado ? 'Era activa' : 'No era activa'}');
      return resultado;
    } 
    else if (fechaNormalizada.isAtSameMomentAs(hoyNormalizado)) {
      // HOY: Lógica especial
      final resultado = _reservaEsActivaHoy(reserva, fecha);
      debugPrint('   ${resultado ? '✅' : '❌'} ${reserva.clienteNombre}: Hoy - ${resultado ? 'Activa' : 'No activa'}');
      return resultado;
    } 
    else {
      // FECHAS FUTURAS: Solo activas
      final esActiva = reserva.estado == EstadoRecurrencia.activa;
      final estaEnRango = reserva.estaActivaEnFecha(fecha);
      final resultado = esActiva && estaEnRango;
      debugPrint('   ${resultado ? '✅' : '❌'} ${reserva.clienteNombre}: Futuro - Activa: $esActiva, En rango: $estaEnRango');
      return resultado;
    }
  }).toList();

  debugPrint('🔍 === RESULTADO FILTRADO ===');
  debugPrint('🔍 Reservas que cumplen filtros: ${reservasFiltradas.length}');
  
  for (var reserva in reservasFiltradas) {
    debugPrint('   ✅ ${reserva.clienteNombre} - ${reserva.horario} - Estado: ${reserva.estado}');
  }
  
  return reservasFiltradas;
}

/// ✅ MÉTODO AUXILIAR PARA FECHAS PASADAS
bool _reservaEstabaActivaEnFechaPasada(ReservaRecurrente reserva, DateTime fecha) {
  // Verificar si la fecha está dentro del rango de la reserva
  if (!reserva.estaActivaEnFecha(fecha)) return false;
  
  // Si tiene fechaFin, verificar que la fecha esté antes o igual a fechaFin
  if (reserva.fechaFin != null) {
    final fechaFinNormalizada = DateTime(reserva.fechaFin!.year, reserva.fechaFin!.month, reserva.fechaFin!.day);
    final fechaNormalizada = DateTime(fecha.year, fecha.month, fecha.day);
    
    if (fechaNormalizada.isAfter(fechaFinNormalizada)) {
      return false; // La reserva ya había terminado
    }
  }
  
  return true; // Era activa en esa fecha pasada
}

/// ✅ MÉTODO AUXILIAR PARA HOY
bool _reservaEsActivaHoy(ReservaRecurrente reserva, DateTime fecha) {
  // Si está cancelada, verificar si fue cancelada después de hoy
  if (reserva.estado == EstadoRecurrencia.cancelada) {
    if (reserva.fechaFin != null) {
      final fechaFinNormalizada = DateTime(reserva.fechaFin!.year, reserva.fechaFin!.month, reserva.fechaFin!.day);
      final hoyNormalizado = DateTime(fecha.year, fecha.month, fecha.day);
      
      // Si fechaFin incluye hoy o es después, mostrar para historial
      return !hoyNormalizado.isAfter(fechaFinNormalizada) && reserva.estaActivaEnFecha(fecha);
    }
    // Si no tiene fechaFin específica, mostrar para historial
    return reserva.estaActivaEnFecha(fecha);
  }
  
  // Si está activa, verificar normalmente
  return reserva.estado == EstadoRecurrencia.activa && reserva.estaActivaEnFecha(fecha);
}




  /// Verificar si un horario está ocupado por una reserva recurrente
  bool esHorarioOcupadoPorRecurrente(DateTime fecha, String horario, String canchaId, String sede) {
    final reservasActivas = obtenerReservasActivasParaFecha(fecha, sede: sede, canchaId: canchaId);
    return reservasActivas.any((reserva) => reserva.horario == horario);
  }

  /// Generar reservas normales desde reservas recurrentes para un rango de fechas
  // 🔥 MÉTODO CORREGIDO EN reserva_recurrente_provider.dart
Future<List<Reserva>> generarReservasDesdeRecurrentes(
  DateTime fechaInicio, 
  DateTime fechaFin, 
  Map<String, Cancha> canchasMap
) async {
  final List<Reserva> reservasGeneradas = [];
  
  // 🔥 NUEVA: Obtener todas las reservas individuales que tienen precio independiente
  final reservasIndividualesPersonalizadas = await _obtenerReservasIndividualesPersonalizadas(
    fechaInicio, 
    fechaFin
  );
  
  for (var fecha = fechaInicio; fecha.isBefore(fechaFin.add(Duration(days: 1))); fecha = fecha.add(Duration(days: 1))) {
    final reservasActivas = obtenerReservasActivasParaFecha(fecha);
    
    for (var reservaRecurrente in reservasActivas) {
      final cancha = canchasMap[reservaRecurrente.canchaId];
      if (cancha == null) continue;
      
      final horario = Horario.fromHoraFormateada(reservaRecurrente.horario);
      
      // 🔥 NUEVA LÓGICA: Verificar si existe una reserva individual personalizada para esta fecha/cancha/hora
      final claveReserva = '${DateFormat('yyyy-MM-dd').format(fecha)}_${reservaRecurrente.canchaId}_${reservaRecurrente.horario}';
      final reservaPersonalizada = reservasIndividualesPersonalizadas[claveReserva];
      
      // 🔥 Usar precio personalizado si existe, sino usar el de la recurrente
      double montoTotal = reservaRecurrente.montoTotal;
      double montoPagado = reservaRecurrente.montoPagado;
      bool precioPersonalizado = reservaRecurrente.precioPersonalizado;
      double? precioOriginal = reservaRecurrente.precioOriginal;
      double? descuentoAplicado = reservaRecurrente.descuentoAplicado;
      
      if (reservaPersonalizada != null) {
        debugPrint('💰 Usando precio personalizado para $claveReserva: ${reservaPersonalizada['montoTotal']}');
        montoTotal = reservaPersonalizada['montoTotal'];
        montoPagado = reservaPersonalizada['montoPagado'];
        precioPersonalizado = reservaPersonalizada['precioPersonalizado'] ?? false;
        precioOriginal = reservaPersonalizada['precioOriginal'];
        descuentoAplicado = reservaPersonalizada['descuentoAplicado'];
      }
      
      final reserva = Reserva(
        id: '${reservaRecurrente.id}_${DateFormat('yyyy-MM-dd').format(fecha)}',
        cancha: cancha,
        fecha: fecha,
        horario: horario,
        sede: reservaRecurrente.sede,
        tipoAbono: montoPagado >= montoTotal ? TipoAbono.completo : TipoAbono.parcial,
        montoTotal: montoTotal, // 🔥 Ahora usa el precio correcto
        montoPagado: montoPagado, // 🔥 Ahora usa el monto pagado correcto
        nombre: reservaRecurrente.clienteNombre,
        telefono: reservaRecurrente.clienteTelefono,
        email: reservaRecurrente.clienteEmail,
        confirmada: true,
        reservaRecurrenteId: reservaRecurrente.id,
        esReservaRecurrente: true,
        precioPersonalizado: precioPersonalizado,
        precioOriginal: precioOriginal,
        descuentoAplicado: descuentoAplicado,
      );
      
      reservasGeneradas.add(reserva);
    }
  }
  
  return reservasGeneradas;
}

// 🔥 NUEVO MÉTODO AUXILIAR
Future<Map<String, Map<String, dynamic>>> _obtenerReservasIndividualesPersonalizadas(
  DateTime fechaInicio,
  DateTime fechaFin
) async {
  try {
    final query = FirebaseFirestore.instance
        .collection('reservas')
        .where('precio_independiente_de_recurrencia', isEqualTo: true)
        .where('fecha', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(fechaInicio))
        .where('fecha', isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(fechaFin));
    
    final snapshot = await query.get();
    
    Map<String, Map<String, dynamic>> reservasPersonalizadas = {};
    
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final fecha = data['fecha'] as String;
      final canchaId = data['cancha_id'] as String;
      final horario = data['horario'] as String;
      
      final clave = '${fecha}_${canchaId}_${horario}';
      reservasPersonalizadas[clave] = {
        'montoTotal': (data['montoTotal'] ?? data['valor'] as num?)?.toDouble() ?? 0.0,
        'montoPagado': (data['montoPagado'] as num?)?.toDouble() ?? 0.0,
        'precioPersonalizado': data['precioPersonalizado'] as bool? ?? false,
        'precioOriginal': (data['precio_original'] as num?)?.toDouble(),
        'descuentoAplicado': (data['descuento_aplicado'] as num?)?.toDouble(),
      };
      
      debugPrint('🔍 Reserva personalizada encontrada: $clave - Precio: ${reservasPersonalizadas[clave]!['montoTotal']}');
    }
    
    return reservasPersonalizadas;
  } catch (e) {
    debugPrint('❌ Error obteniendo reservas personalizadas: $e');
    return {};
  }
}



  /// Cancelar una reserva recurrente
  Future<void> cancelarReservaRecurrente(String reservaId) async {
  try {
    final index = _reservasRecurrentes.indexWhere((r) => r.id == reservaId);
    if (index == -1) throw Exception('Reserva recurrente no encontrada');
    
    final reservaAnterior = _reservasRecurrentes[index];
    
    await FirebaseFirestore.instance
        .collection('reservas_recurrentes')
        .doc(reservaId)
        .update({
      'estado': EstadoRecurrencia.cancelada.name,
      'fechaActualizacion': Timestamp.now(),
    });
    
    // 🔍 AUDITORÍA: Registrar cancelación
    await AuditProvider.registrarAccion(
      accion: 'cancelar_reserva_recurrente',
      entidad: 'reserva_recurrente',
      entidadId: reservaId,
      datosAntiguos: {'estado': reservaAnterior.estado.name},
      datosNuevos: {'estado': EstadoRecurrencia.cancelada.name},
      metadatos: {
        'cliente': reservaAnterior.clienteNombre,
        'horario': reservaAnterior.horario,
        'sede': reservaAnterior.sede,
        'monto_afectado': reservaAnterior.montoTotal,
      },
      descripcion: 'Reserva recurrente cancelada completamente',
    );
    
    // NO REMOVER DE LA LISTA, SOLO ACTUALIZAR EL ESTADO
    _reservasRecurrentes[index] = _reservasRecurrentes[index].copyWith(
      estado: EstadoRecurrencia.cancelada,
      fechaActualizacion: DateTime.now(),
    );
    
    notifyListeners();
  } catch (e) {
    _errorMessage = 'Error al cancelar reserva recurrente: $e';
    debugPrint(_errorMessage);
    throw Exception(_errorMessage);
  }
}


  void limpiar() {
    _reservasRecurrentes.clear();
    _errorMessage = '';
    _isLoading = false;
    notifyListeners();
  }

  /// ✅ MÉTODO CORREGIDO PARA CANCELAR RESERVAS FUTURAS
  Future<void> cancelarReservasFuturas(String reservaId) async {
  try {
    final index = _reservasRecurrentes.indexWhere((r) => r.id == reservaId);
    if (index == -1) throw Exception('Reserva recurrente no encontrada');

    final reservaActual = _reservasRecurrentes[index];
    final ahora = DateTime.now();
    
    List<String> nuevosExcluidos = List<String>.from(reservaActual.diasExcluidos);
    DateTime? nuevaFechaFin;
    
    try {
      final horarioReserva = Horario.fromHoraFormateada(reservaActual.horario);
      final horaReservaHoy = DateTime(
        ahora.year, ahora.month, ahora.day,
        horarioReserva.hora.hour, horarioReserva.hora.minute
      );
      
      final diaSemanaHoy = DateFormat('EEEE', 'es').format(ahora).toLowerCase();
      final esHoyDiaValido = reservaActual.diasSemana.contains(diaSemanaHoy);
      final fechaHoyStr = DateFormat('yyyy-MM-dd').format(ahora);
      final yaEstaExcluidoHoy = reservaActual.diasExcluidos.contains(fechaHoyStr);
      
      if (esHoyDiaValido && !yaEstaExcluidoHoy) {
        if (ahora.isBefore(horaReservaHoy)) {
          nuevosExcluidos.add(fechaHoyStr);
          nuevaFechaFin = DateTime(ahora.year, ahora.month, ahora.day - 1, 23, 59, 59, 999);
        } else {
          nuevaFechaFin = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59, 999);
        }
      } else {
        nuevaFechaFin = DateTime(ahora.year, ahora.month, ahora.day - 1, 23, 59, 59, 999);
      }
      
    } catch (e) {
      nuevaFechaFin = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59, 999);
    }
    
    final reservaActualizada = reservaActual.copyWith(
      fechaFin: nuevaFechaFin,
      diasExcluidos: nuevosExcluidos,
      estado: EstadoRecurrencia.cancelada,
      fechaActualizacion: DateTime.now(),
    );
    
    await FirebaseFirestore.instance
        .collection('reservas_recurrentes')
        .doc(reservaId)
        .update(reservaActualizada.toFirestore());
    
    // 🔍 AUDITORÍA: Registrar cancelación de futuras
    await AuditProvider.registrarAccion(
      accion: 'cancelar_reservas_futuras',
      entidad: 'reserva_recurrente',
      entidadId: reservaId,
      datosAntiguos: {
        'estado': reservaActual.estado.name,
        'fechaFin': reservaActual.fechaFin?.toIso8601String(),
        'diasExcluidos': reservaActual.diasExcluidos,
      },
      datosNuevos: {
        'estado': EstadoRecurrencia.cancelada.name,
        'fechaFin': nuevaFechaFin?.toIso8601String(),
        'diasExcluidos': nuevosExcluidos,
      },
      metadatos: {
        'cliente': reservaActual.clienteNombre,
        'horario': reservaActual.horario,
        'sede': reservaActual.sede,
        'fecha_corte': DateFormat('yyyy-MM-dd HH:mm:ss').format(ahora),
        'dias_excluidos_agregados': nuevosExcluidos.where((d) => !reservaActual.diasExcluidos.contains(d)).toList(),
      },
      descripcion: 'Reservas futuras canceladas desde hoy',
    );
    
    _reservasRecurrentes[index] = reservaActualizada;
    notifyListeners();
    
  } catch (e) {
    _errorMessage = 'Error al cancelar reservas futuras: $e';
    debugPrint(_errorMessage);
    throw Exception(_errorMessage);
  }
}



}