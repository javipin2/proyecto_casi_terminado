// lib/providers/reserva_provider.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:reserva_canchas/providers/audit_provider.dart';
import '../models/reserva.dart';

class ReservaProvider with ChangeNotifier {
  Reserva? _reservaActual;
  List<Reserva>? _reservasGrupales; // ✅ PARA MANEJAR MÚLTIPLES RESERVAS

  Reserva? get reservaActual => _reservaActual;
  List<Reserva>? get reservasGrupales => _reservasGrupales;

  // ✅ GETTER PARA SABER SI ES RESERVA GRUPAL
  bool get esReservaGrupal => _reservasGrupales != null && _reservasGrupales!.length > 1;

  // ✅ GETTER PARA OBTENER EL MONTO TOTAL DE TODAS LAS RESERVAS
  double get montoTotalGrupal {
    if (_reservasGrupales != null) {
      return _reservasGrupales!.fold(0.0, (sum, reserva) => sum + reserva.montoTotal);
    }
    return _reservaActual?.montoTotal ?? 0.0;
  }

  // ✅ GETTER PARA OBTENER EL MONTO PAGADO TOTAL
  double get montoPagadoTotal {
    if (_reservasGrupales != null) {
      return _reservasGrupales!.fold(0.0, (sum, reserva) => sum + reserva.montoPagado);
    }
    return _reservaActual?.montoPagado ?? 0.0;
  }

  /// **Iniciar una nueva reserva individual en memoria**
  void iniciarReserva(Reserva reserva) {
    _reservaActual = reserva;
    _reservasGrupales = null; // Limpiar reservas grupales
    notifyListeners();
  }

  /// ✅ **Iniciar múltiples reservas grupales en memoria**
  void iniciarReservasGrupales(List<Reserva> reservas, {String? grupoId}) {
    if (reservas.isEmpty) return;
    
    // Asignar ID de grupo si se proporciona
    if (grupoId != null) {
      _reservasGrupales = reservas.map((reserva) => reserva.copyWith(
        grupoReservaId: grupoId,
        totalHorasGrupo: reservas.length,
      )).toList();
    } else {
      _reservasGrupales = List.from(reservas);
    }
    
    _reservaActual = null; // Limpiar reserva individual
    notifyListeners();
  }

  /// **Actualizar datos del cliente en la reserva actual o grupales**
  void actualizarDatosCliente({
    required String nombre,
    required String telefono,
    required String email,
  }) {
    if (_reservaActual != null) {
      _reservaActual!.nombre = nombre;
      _reservaActual!.telefono = telefono;
      _reservaActual!.email = email;
      notifyListeners();
    } else if (_reservasGrupales != null) {
      // ✅ ACTUALIZAR TODAS LAS RESERVAS DEL GRUPO
      for (var reserva in _reservasGrupales!) {
        reserva.nombre = nombre;
        reserva.telefono = telefono;
        reserva.email = email;
      }
      notifyListeners();
    }
  }

  /// ✅ **Actualizar precio personalizado para reserva individual**
  void actualizarPrecioPersonalizado(double nuevoPrecio, {double? precioOriginal}) {
    if (_reservaActual != null) {
      final original = precioOriginal ?? _reservaActual!.montoTotal;
      final descuento = original - nuevoPrecio;
      
      _reservaActual = _reservaActual!.copyWith(
        montoTotal: nuevoPrecio,
        precioPersonalizado: true,
        precioOriginal: original,
        descuentoAplicado: descuento > 0 ? descuento : 0,
      );
      notifyListeners();
    }
  }

  /// ✅ **Actualizar precios personalizados para reservas grupales**
  void actualizarPreciosGrupales(Map<int, double> nuevosPrecios) {
    if (_reservasGrupales != null) {
      for (int i = 0; i < _reservasGrupales!.length; i++) {
        if (nuevosPrecios.containsKey(i)) {
          final reserva = _reservasGrupales![i];
          final nuevoPrecio = nuevosPrecios[i]!;
          final precioOriginal = reserva.precioOriginal ?? reserva.montoTotal;
          final descuento = precioOriginal - nuevoPrecio;
          
          _reservasGrupales![i] = reserva.copyWith(
            montoTotal: nuevoPrecio,
            precioPersonalizado: true,
            precioOriginal: precioOriginal,
            descuentoAplicado: descuento > 0 ? descuento : 0,
          );
        }
      }
      notifyListeners();
    }
  }

  /// **Registrar pago y confirmar reserva**
  void registrarPago(double monto) {
    if (_reservaActual != null) {
      _reservaActual!.montoPagado = monto;
      _reservaActual!.confirmada = true;
      notifyListeners();
    } else if (_reservasGrupales != null) {
      // ✅ DISTRIBUIR EL PAGO ENTRE LAS RESERVAS GRUPALES
      final montoTotal = montoTotalGrupal;
      double montoRestante = monto;
      
      for (int i = 0; i < _reservasGrupales!.length; i++) {
        final reserva = _reservasGrupales![i];
        final proporcion = reserva.montoTotal / montoTotal;
        final pagoReserva = i == _reservasGrupales!.length - 1 
            ? montoRestante // Para la última, asignar lo que quede
            : monto * proporcion;
        
        _reservasGrupales![i] = reserva.copyWith(
          montoPagado: pagoReserva,
          confirmada: true,
        );
        montoRestante -= pagoReserva;
      }
      notifyListeners();
    }
  }

  /// ✅ **Registrar pagos individuales para reservas grupales**
  void registrarPagoGrupal(int indiceReserva, double monto) {
    if (_reservasGrupales != null && indiceReserva < _reservasGrupales!.length) {
      _reservasGrupales![indiceReserva] = _reservasGrupales![indiceReserva].copyWith(
        montoPagado: monto,
        confirmada: true,
      );
      notifyListeners();
    }
  }

  /// **Confirmar reserva y enviarla a Firestore**
  Future<void> confirmarReserva() async {
  if (_reservaActual != null) {
    _reservaActual!.confirmada = true;
    notifyListeners();

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('reservas')
          .add(_reservaActual!.toFirestore());
      
      // 🔍 AUDITORÍA: Registrar creación de reserva
      await AuditProvider.registrarAccion(
        accion: _reservaActual!.precioPersonalizado ? 'crear_reserva_precio_personalizado' : 'crear_reserva',
        entidad: 'reserva',
        entidadId: docRef.id,
        datosNuevos: _reservaActual!.toFirestore(),
        metadatos: {
          'cancha_nombre': _reservaActual!.cancha.nombre,
          'sede': _reservaActual!.sede,
          'fecha': _reservaActual!.fecha.toIso8601String(),
          'horario': _reservaActual!.horario.horaFormateada,
          'cliente': _reservaActual!.nombre,
          'monto_total': _reservaActual!.montoTotal,
          'descuento_aplicado': _reservaActual!.descuentoAplicado ?? 0,
        },
        descripcion: _reservaActual!.precioPersonalizado 
          ? 'Reserva creada con precio personalizado'
          : 'Nueva reserva creada',
      );
      
      _reservaActual = null;
      notifyListeners();
    } catch (e) {
      throw Exception('🔥 Error al guardar la reserva en Firestore: $e');
    }
  } else if (_reservasGrupales != null) {
    await confirmarReservasGrupales();
  }
}


  /// ✅ **Confirmar múltiples reservas grupales**
  Future<List<String>> confirmarReservasGrupales() async {
  if (_reservasGrupales == null || _reservasGrupales!.isEmpty) {
    throw Exception('No hay reservas grupales para confirmar');
  }

  try {
    final List<String> idsCreados = [];
    final batch = FirebaseFirestore.instance.batch();
    final grupoId = _reservasGrupales![0].grupoReservaId ?? 
                   DateTime.now().millisecondsSinceEpoch.toString();

    for (var reserva in _reservasGrupales!) {
      final docRef = FirebaseFirestore.instance.collection('reservas').doc();
      
      final reservaConGrupo = reserva.copyWith(
        grupoReservaId: grupoId,
        totalHorasGrupo: _reservasGrupales!.length,
        confirmada: true,
      );
      
      batch.set(docRef, reservaConGrupo.toFirestore());
      idsCreados.add(docRef.id);
    }

    await batch.commit();
    
    // 🔍 AUDITORÍA: Registrar creación de reservas grupales
    final tieneDescuentos = _reservasGrupales!.any((r) => r.precioPersonalizado);
    final montoTotalGrupo = _reservasGrupales!.fold(0.0, (sum, r) => sum + r.montoTotal);
    final descuentoTotalGrupo = _reservasGrupales!.fold(0.0, (sum, r) => sum + (r.descuentoAplicado ?? 0));
    
    await AuditProvider.registrarAccion(
      accion: tieneDescuentos ? 'crear_reservas_grupales_precio_personalizado' : 'crear_reservas_grupales',
      entidad: 'reserva_grupal',
      entidadId: grupoId,
      datosNuevos: {
        'cantidad_reservas': _reservasGrupales!.length,
        'monto_total_grupo': montoTotalGrupo,
        'descuento_total_grupo': descuentoTotalGrupo,
        'reservas_ids': idsCreados,
        'tiene_descuentos': tieneDescuentos,
      },
      metadatos: {
        'cancha_nombre': _reservasGrupales![0].cancha.nombre,
        'sede': _reservasGrupales![0].sede,
        'fecha': _reservasGrupales![0].fecha.toIso8601String(),
        'cliente': _reservasGrupales![0].nombre,
        'horarios': _reservasGrupales!.map((r) => r.horario.horaFormateada).toList(),
      },
      descripcion: tieneDescuentos 
        ? 'Reservas grupales creadas con descuentos (${_reservasGrupales!.length} horas)'
        : 'Reservas grupales creadas (${_reservasGrupales!.length} horas)',
    );
    
    _reservasGrupales = null;
    notifyListeners();
    
    return idsCreados;
  } catch (e) {
    throw Exception('🔥 Error al guardar las reservas grupales en Firestore: $e');
  }
}




  /// **Cancelar reserva antes de confirmarla**
  void cancelarReserva() {
    _reservaActual = null;
    _reservasGrupales = null;
    notifyListeners();
  }

  /// ✅ **Obtener reservas por grupo**
  Future<List<Reserva>> obtenerReservasPorGrupo(String grupoId) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('reservas')
          .where('grupo_reserva_id', isEqualTo: grupoId)
          .orderBy('horario')
          .get();

      final List<Reserva> reservas = [];
      for (var doc in querySnapshot.docs) {
        reservas.add(await Reserva.fromFirestore(doc));
      }
      
      return reservas;
    } catch (e) {
      debugPrint('Error al obtener reservas del grupo $grupoId: $e');
      return [];
    }
  }

  /// ✅ **Verificar si una reserva pertenece a un grupo**
  Future<bool> esPartDeGrupo(String reservaId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reservas')
          .doc(reservaId)
          .get();
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return data.containsKey('grupo_reserva_id') && 
               data['grupo_reserva_id'] != null;
      }
      
      return false;
    } catch (e) {
      debugPrint('Error al verificar si la reserva es parte de un grupo: $e');
      return false;
    }
  }

  /// ✅ **Obtener estadísticas de reservas grupales**
  Map<String, dynamic> get estadisticasActuales {
    if (_reservasGrupales != null) {
      return {
        'totalReservas': _reservasGrupales!.length,
        'montoTotal': montoTotalGrupal,
        'montoPagado': montoPagadoTotal,
        'montoRestante': montoTotalGrupal - montoPagadoTotal,
        'tienenDescuento': _reservasGrupales!.any((r) => r.tieneDescuento),
        'descuentoTotal': _reservasGrupales!.fold(0.0, (sum, r) => sum + (r.descuentoAplicado ?? 0)),
        'esGrupal': true,
      };
    } else if (_reservaActual != null) {
      return {
        'totalReservas': 1,
        'montoTotal': _reservaActual!.montoTotal,
        'montoPagado': _reservaActual!.montoPagado,
        'montoRestante': _reservaActual!.montoTotal - _reservaActual!.montoPagado,
        'tienenDescuento': _reservaActual!.tieneDescuento,
        'descuentoTotal': _reservaActual!.descuentoAplicado ?? 0,
        'esGrupal': false,
      };
    }
    
    return {
      'totalReservas': 0,
      'montoTotal': 0.0,
      'montoPagado': 0.0,
      'montoRestante': 0.0,
      'tienenDescuento': false,
      'descuentoTotal': 0.0,
      'esGrupal': false,
    };
  }
}