// lib/providers/peticion_provider.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/peticion.dart';
import '../models/reserva.dart';

class PeticionProvider with ChangeNotifier {
  List<Peticion> _peticiones = [];
  bool _isLoading = false;
  bool _controlTotalActivado = false;
  StreamSubscription<DocumentSnapshot>? _controlSubscription;

  List<Peticion> get peticiones => _peticiones;
  bool get isLoading => _isLoading;
  bool get controlTotalActivado => _controlTotalActivado;

  // Obtener peticiones pendientes (para superadmin)
  List<Peticion> get peticionesPendientes => 
      _peticiones.where((p) => p.estaPendiente).toList();

  // Obtener peticiones por admin
  List<Peticion> peticionesPorAdmin(String adminId) =>
      _peticiones.where((p) => p.adminId == adminId).toList();

  /// **Inicializar escucha en tiempo real del control total**
  void iniciarEscuchaControlTotal() {
    _controlSubscription?.cancel();
    
    _controlSubscription = FirebaseFirestore.instance
        .collection('config')
        .doc('admin_control')
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final nuevoEstado = snapshot.data()!['control_total_activado'] ?? false;
          if (_controlTotalActivado != nuevoEstado) {
            _controlTotalActivado = nuevoEstado;
            debugPrint('Control total actualizado en tiempo real: $_controlTotalActivado');
            notifyListeners();
          }
        } else {
          if (_controlTotalActivado != false) {
            _controlTotalActivado = false;
            notifyListeners();
          }
        }
      },
      onError: (error) {
        debugPrint('Error en escucha de control total: $error');
      },
    );
  }

  /// **Detener escucha del control total**
  void detenerEscuchaControlTotal() {
    _controlSubscription?.cancel();
    _controlSubscription = null;
  }

  /// **Alternar control total de administradores (solo superadmin)**
  Future<void> alternarControlTotal() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No hay usuario autenticado');
      }

      // Verificar que es superadmin
      if (!await esSuperAdmin()) {
        throw Exception('Solo los superadministradores pueden cambiar esta configuración');
      }

      final nuevoEstado = !_controlTotalActivado;
      
      // Crear documento de configuración si no existe
      final configRef = FirebaseFirestore.instance
          .collection('config')
          .doc('admin_control');
      
      await configRef.set({
        'control_total_activado': nuevoEstado,
        'activado_por': user.uid,
        'fecha_cambio': Timestamp.now(),
        'version': FieldValue.increment(1), // Para detectar cambios
      }, SetOptions(merge: true));

      // No actualizamos el estado local aquí porque el listener lo hará
      debugPrint('Control total ${nuevoEstado ? "activado" : "desactivado"}');
      
    } catch (e) {
      debugPrint('Error al alternar control total: $e');
      throw Exception('Error al cambiar la configuración: $e');
    }
  }

  /// **Cargar configuración de control total (una sola vez)**
  Future<void> cargarConfiguracionControl() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('admin_control')
          .get();

      if (doc.exists && doc.data() != null) {
        final nuevoEstado = doc.data()!['control_total_activado'] ?? false;
        if (_controlTotalActivado != nuevoEstado) {
          _controlTotalActivado = nuevoEstado;
          notifyListeners();
        }
      } else {
        // Crear documento por defecto
        await FirebaseFirestore.instance
            .collection('config')
            .doc('admin_control')
            .set({
          'control_total_activado': false,
          'fecha_creacion': Timestamp.now(),
        });
        
        if (_controlTotalActivado != false) {
          _controlTotalActivado = false;
          notifyListeners();
        }
      }
      
    } catch (e) {
      debugPrint('Error al cargar configuración de control: $e');
      if (_controlTotalActivado != false) {
        _controlTotalActivado = false;
        notifyListeners();
      }
    }
  }

  /// **Verificar si un admin puede hacer cambios directos**
  Future<bool> puedeHacerCambiosDirectos() async {
    if (await esSuperAdmin()) {
      return true; // Superadmin siempre puede
    }

    if (await esAdmin() && _controlTotalActivado) {
      return true; // Admin puede si el control total está activado
    }

    return false; // En caso contrario, debe usar peticiones
  }

  /// **Crear una nueva petición**
  Future<String> crearPeticion({
    required String reservaId,
    required Map<String, dynamic> valoresAntiguos,
    required Map<String, dynamic> valoresNuevos,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No hay usuario autenticado');
      }

      // Verificar que es admin (no superadmin, ellos no necesitan peticiones)
      if (!await esAdmin() || await esSuperAdmin()) {
        throw Exception('Solo los administradores pueden crear peticiones');
      }

      // Verificar que el control total no esté activado
      if (_controlTotalActivado) {
        throw Exception('El control total está activado, puedes hacer cambios directamente');
      }

      // Obtener información del admin
      final adminDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      
      final adminName = adminDoc.exists 
          ? (adminDoc.data()?['name'] ?? 'Admin desconocido')
          : 'Admin desconocido';

      // Generar descripción de cambios
      final descripcion = Peticion.generarDescripcionCambios(
        valoresAntiguos, 
        valoresNuevos
      );

      final peticion = Peticion(
        id: '', // Se asignará automáticamente
        reservaId: reservaId,
        adminId: user.uid,
        adminName: adminName,
        valoresAntiguos: valoresAntiguos,
        valoresNuevos: valoresNuevos,
        fechaCreacion: DateTime.now(),
        descripcionCambios: descripcion,
      );

      // Guardar en Firestore
      final docRef = await FirebaseFirestore.instance
          .collection('peticiones')
          .add(peticion.toFirestore());

      // Actualizar la lista local
      await cargarPeticiones();
      
      return docRef.id;
    } catch (e) {
      debugPrint('Error al crear petición: $e');
      throw Exception('Error al crear la petición: $e');
    }
  }

  /// **Cargar todas las peticiones**
  Future<void> cargarPeticiones() async {
    _isLoading = true;
    notifyListeners();

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('peticiones')
          .orderBy('fecha_creacion', descending: true)
          .get();

      _peticiones = querySnapshot.docs
          .map((doc) => Peticion.fromFirestore(doc))
          .toList();

    } catch (e) {
      debugPrint('Error al cargar peticiones: $e');
      _peticiones = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// **Aprobar una petición (solo superadmin)**
  Future<void> aprobarPeticion(String peticionId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No hay usuario autenticado');
      }

      if (!await esSuperAdmin()) {
        throw Exception('Solo los superadministradores pueden aprobar peticiones');
      }

      final peticion = _peticiones.firstWhere((p) => p.id == peticionId);
      
      // Actualizar el estado de la petición
      await FirebaseFirestore.instance
          .collection('peticiones')
          .doc(peticionId)
          .update({
        'estado': 'aprobada',
        'fecha_respuesta': Timestamp.now(),
        'super_admin_id': user.uid,
      });

      // Aplicar los cambios a la reserva
      await _aplicarCambiosReserva(peticion.reservaId, peticion.valoresNuevos);

      // Actualizar la lista local
      await cargarPeticiones();

    } catch (e) {
      debugPrint('Error al aprobar petición: $e');
      throw Exception('Error al aprobar la petición: $e');
    }
  }

  /// **Rechazar una petición (solo superadmin)**
  Future<void> rechazarPeticion(String peticionId, String motivo) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No hay usuario autenticado');
      }

      if (!await esSuperAdmin()) {
        throw Exception('Solo los superadministradores pueden rechazar peticiones');
      }

      // Actualizar el estado de la petición
      await FirebaseFirestore.instance
          .collection('peticiones')
          .doc(peticionId)
          .update({
        'estado': 'rechazada',
        'fecha_respuesta': Timestamp.now(),
        'super_admin_id': user.uid,
        'motivo_rechazo': motivo,
      });

      // Actualizar la lista local
      await cargarPeticiones();

    } catch (e) {
      debugPrint('Error al rechazar petición: $e');
      throw Exception('Error al rechazar la petición: $e');
    }
  }

  /// **Aplicar cambios a la reserva**
  Future<void> _aplicarCambiosReserva(
    String reservaId, 
    Map<String, dynamic> nuevosValores
  ) async {
    try {
      // Convertir los valores al formato correcto para Firestore
      final updateData = <String, dynamic>{};
      
      nuevosValores.forEach((key, value) {
        switch (key) {
          case 'nombre':
          case 'telefono':
          case 'correo':
          case 'fecha':
          case 'horario':
          case 'cancha_id':
          case 'sede':
            updateData[key] = value;
            break;
          case 'valor':
            updateData['valor'] = value;
            break;
          case 'montoPagado':
            updateData['montoPagado'] = value;
            break;
          case 'estado':
            updateData['estado'] = value;
            break;
          case 'confirmada':
            updateData['confirmada'] = value;
            break;
        }
      });
      
      if (updateData.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('reservas')
            .doc(reservaId)
            .update(updateData);
        
        debugPrint('Cambios aplicados a la reserva $reservaId: $updateData');
      }
    } catch (e) {
      debugPrint('Error al aplicar cambios a la reserva: $e');
      throw Exception('Error al aplicar cambios a la reserva: $e');
    }
  }

  /// **Verificar si el usuario es superadmin**
  Future<bool> esSuperAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final role = userDoc.data()?['rol'] as String?;
        return role == 'superadmin';
      }

      return false;
    } catch (e) {
      debugPrint('Error al verificar rol de superadmin: $e');
      return false;
    }
  }

  /// **Verificar si el usuario es admin (o superadmin)**
  Future<bool> esAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final role = userDoc.data()?['rol'] as String?;
        return role == 'admin' || role == 'superadmin';
      }

      return false;
    } catch (e) {
      debugPrint('Error al verificar rol de admin: $e');
      return false;
    }
  }

  /// **Obtener estadísticas de peticiones**
  Map<String, int> get estadisticas {
    return {
      'total': _peticiones.length,
      'pendientes': _peticiones.where((p) => p.estaPendiente).length,
      'aprobadas': _peticiones.where((p) => p.fueAprobada).length,
      'rechazadas': _peticiones.where((p) => p.fueRechazada).length,
    };
  }

  /// **Limpiar peticiones locales**
  void limpiar() {
    _peticiones = [];
    _isLoading = false;
    _controlTotalActivado = false;
    detenerEscuchaControlTotal();
    notifyListeners();
  }

  @override
  void dispose() {
    detenerEscuchaControlTotal();
    super.dispose();
  }
}