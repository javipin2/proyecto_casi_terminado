// lib/providers/reserva_provider.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reserva.dart';

class ReservaProvider with ChangeNotifier {
  Reserva? _reservaActual;

  Reserva? get reservaActual => _reservaActual;

  /// **Iniciar una nueva reserva en memoria**
  void iniciarReserva(Reserva reserva) {
    _reservaActual = reserva;
    notifyListeners();
  }

  /// **Actualizar datos del cliente en la reserva actual**
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
    }
  }

  /// **Registrar pago y confirmar reserva**
  void registrarPago(double monto) {
    if (_reservaActual != null) {
      _reservaActual!.montoPagado = monto;
      _reservaActual!.confirmada = true;
      notifyListeners();
    }
  }

  /// **Confirmar reserva y enviarla a Firestore**
  Future<void> confirmarReserva() async {
    if (_reservaActual != null) {
      _reservaActual!.confirmada = true;
      notifyListeners();

      try {
        await FirebaseFirestore.instance
            .collection('reservas')
            .add(_reservaActual!.toFirestore());
        _reservaActual = null; // Limpiar la reserva actual después de guardarla
        notifyListeners();
      } catch (e) {
        throw Exception('🔥 Error al guardar la reserva en Firestore: $e');
      }
    }
  }

  /// **Cancelar reserva antes de confirmarla**
  void cancelarReserva() {
    _reservaActual = null;
    notifyListeners();
  }
}
