import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lugar.dart';
import '../services/index_error_service.dart';

class LugarProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Lugar> _lugares = [];
  String? _ciudadSeleccionada;
  bool _isLoading = false;
  String? _errorMessage;

  List<Lugar> get lugares => _lugares;
  String? get ciudadSeleccionada => _ciudadSeleccionada;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchLugaresPorCiudad(String ciudadId) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      _ciudadSeleccionada = ciudadId;
      notifyListeners();

      IndexErrorService.logIndexRequirements('lugares', ['ciudadId', 'activo'], ['nombre']);

      final query = _firestore
          .collection('lugares')
          .where('ciudadId', isEqualTo: ciudadId)
          .where('activo', isEqualTo: true)
          .orderBy('nombre');

      final querySnapshot = await IndexErrorService.queryWithIndexHandling(
        query,
        'lugares',
      );

      // Ignorar resultado si el usuario ya cambió de ciudad
      if (_ciudadSeleccionada != ciudadId) return;

      _lugares = querySnapshot.docs
          .map((doc) => Lugar.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

    } catch (e) {
      IndexErrorService.handleFirestoreError(e, 'fetchLugaresPorCiudad');
      _errorMessage = 'Error al cargar lugares: $e';
      if (kDebugMode) {
        print('Error en LugarProvider.fetchLugaresPorCiudad: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchTodosLosLugares() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final querySnapshot = await _firestore
          .collection('lugares')
          .orderBy('nombre')
          .limit(100)
          .get();

      _lugares = querySnapshot.docs
          .map((doc) => Lugar.fromFirestore(doc.data(), doc.id))
          .toList();

    } catch (e) {
      _errorMessage = 'Error al cargar lugares: $e';
      if (kDebugMode) {
        print('Error en LugarProvider.fetchTodosLosLugares: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchLugaresDisponibles(String ciudadId, DateTime fecha, TimeOfDay hora) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      _ciudadSeleccionada = ciudadId;
      notifyListeners();

      // Log requisitos de índice
      IndexErrorService.logIndexRequirements('lugares', ['ciudadId', 'activo'], ['nombre']);

      final query = _firestore
          .collection('lugares')
          .where('ciudadId', isEqualTo: ciudadId)
          .where('activo', isEqualTo: true)
          .orderBy('nombre');

      final querySnapshot = await IndexErrorService.queryWithIndexHandling(
        query,
        'lugares',
      );

      _lugares = querySnapshot.docs
          .map((doc) => Lugar.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      // Aquí se podría implementar lógica adicional para filtrar por disponibilidad
      // consultando las reservas en la fecha/hora seleccionada

    } catch (e) {
      IndexErrorService.handleFirestoreError(e, 'fetchLugaresDisponibles');
      _errorMessage = 'Error al cargar lugares disponibles: $e';
      if (kDebugMode) {
        print('Error en LugarProvider.fetchLugaresDisponibles: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> crearLugar(Lugar lugar) async {
    try {
      await _firestore.collection('lugares').add(lugar.toFirestore());
      if (_ciudadSeleccionada != null) {
        await fetchLugaresPorCiudad(_ciudadSeleccionada!);
      } else {
        await fetchTodosLosLugares();
      }
    } catch (e) {
      _errorMessage = 'Error al crear lugar: $e';
      if (kDebugMode) {
        print('Error en LugarProvider.crearLugar: $e');
      }
      notifyListeners();
    }
  }

  Future<void> actualizarLugar(String id, Map<String, dynamic> datos) async {
    try {
      await _firestore.collection('lugares').doc(id).update(datos);
      if (_ciudadSeleccionada != null) {
        await fetchLugaresPorCiudad(_ciudadSeleccionada!);
      } else {
        await fetchTodosLosLugares();
      }
    } catch (e) {
      _errorMessage = 'Error al actualizar lugar: $e';
      if (kDebugMode) {
        print('Error en LugarProvider.actualizarLugar: $e');
      }
      notifyListeners();
    }
  }

  Future<void> activarDesactivarLugar(String lugarId, bool activo) async {
    try {
      await _firestore.collection('lugares').doc(lugarId).update({
        'activo': activo,
        'updatedAt': Timestamp.now(),
      });
      if (_ciudadSeleccionada != null) {
        await fetchLugaresPorCiudad(_ciudadSeleccionada!);
      } else {
        await fetchTodosLosLugares();
      }
    } catch (e) {
      _errorMessage = 'Error al actualizar lugar: $e';
      if (kDebugMode) {
        print('Error en LugarProvider.activarDesactivarLugar: $e');
      }
      notifyListeners();
    }
  }

  Future<void> eliminarLugar(String id) async {
    try {
      await _firestore.collection('lugares').doc(id).delete();
      if (_ciudadSeleccionada != null) {
        await fetchLugaresPorCiudad(_ciudadSeleccionada!);
      } else {
        await fetchTodosLosLugares();
      }
    } catch (e) {
      _errorMessage = 'Error al eliminar lugar: $e';
      if (kDebugMode) {
        print('Error en LugarProvider.eliminarLugar: $e');
      }
      notifyListeners();
    }
  }

  void limpiarError() {
    _errorMessage = null;
    notifyListeners();
  }
}
