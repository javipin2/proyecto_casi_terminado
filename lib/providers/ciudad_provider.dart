import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ciudad.dart';
import '../services/index_error_service.dart';

class CiudadProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Ciudad> _ciudades = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Ciudad> get ciudades => _ciudades;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchCiudades() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Log requisitos de índice
      IndexErrorService.logIndexRequirements('ciudades', ['activa'], ['nombre']);

      final query = _firestore
          .collection('ciudades')
          .where('activa', isEqualTo: true)
          .orderBy('nombre');

      final querySnapshot = await IndexErrorService.queryWithIndexHandling(
        query,
        'ciudades',
      );

      _ciudades = querySnapshot.docs
          .map((doc) => Ciudad.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

    } catch (e) {
      IndexErrorService.handleFirestoreError(e, 'fetchCiudades');
      _errorMessage = 'Error al cargar ciudades: $e';
      if (kDebugMode) {
        print('Error en CiudadProvider.fetchCiudades: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchTodasLasCiudades() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Log requisitos de índice
      IndexErrorService.logIndexRequirements('ciudades', [], ['nombre']);

      final query = _firestore
          .collection('ciudades')
          .orderBy('nombre')
          .limit(100);

      final querySnapshot = await IndexErrorService.queryWithIndexHandling(
        query,
        'ciudades',
      );

      _ciudades = querySnapshot.docs
          .map((doc) => Ciudad.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

    } catch (e) {
      IndexErrorService.handleFirestoreError(e, 'fetchTodasLasCiudades');
      _errorMessage = 'Error al cargar ciudades: $e';
      if (kDebugMode) {
        print('Error en CiudadProvider.fetchTodasLasCiudades: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> crearCiudad(Ciudad ciudad) async {
    try {
      await _firestore.collection('ciudades').add(ciudad.toFirestore());
      await fetchTodasLasCiudades();
    } catch (e) {
      _errorMessage = 'Error al crear ciudad: $e';
      if (kDebugMode) {
        print('Error en CiudadProvider.crearCiudad: $e');
      }
      notifyListeners();
    }
  }

  Future<void> actualizarCiudad(String id, Map<String, dynamic> datos) async {
    try {
      await _firestore.collection('ciudades').doc(id).update(datos);
      await fetchTodasLasCiudades();
    } catch (e) {
      _errorMessage = 'Error al actualizar ciudad: $e';
      if (kDebugMode) {
        print('Error en CiudadProvider.actualizarCiudad: $e');
      }
      notifyListeners();
    }
  }

  Future<void> eliminarCiudad(String id) async {
    try {
      await _firestore.collection('ciudades').doc(id).delete();
      await fetchTodasLasCiudades();
    } catch (e) {
      _errorMessage = 'Error al eliminar ciudad: $e';
      if (kDebugMode) {
        print('Error en CiudadProvider.eliminarCiudad: $e');
      }
      notifyListeners();
    }
  }

  void limpiarError() {
    _errorMessage = null;
    notifyListeners();
  }
}
