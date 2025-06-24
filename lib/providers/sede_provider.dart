import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SedeProvider with ChangeNotifier {
  String _sede = 'Sede 1'; // Valor por defecto
  final List<String> _validSedes = ['Sede 1', 'Sede 2']; // Sedes válidas

  String get sede => _sede;
  List<String> get validSedes => _validSedes; // Getter público

  /// **Carga la sede almacenada en Firestore**
  Future<void> cargarSede() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('sedeActual')
          .get();
      if (doc.exists) {
        final sedeFromFirestore = doc['sede'] as String?;
        if (sedeFromFirestore != null &&
            _validSedes.contains(sedeFromFirestore)) {
          _sede = sedeFromFirestore;
          debugPrint('SedeProvider: Sede cargada desde Firestore: $_sede');
          notifyListeners();
        } else {
          debugPrint(
              'SedeProvider: Sede inválida en Firestore, usando default: $_sede');
        }
      } else {
        debugPrint(
            'SedeProvider: Documento sedeActual no existe, usando default: $_sede');
      }
    } catch (error) {
      debugPrint('SedeProvider: Error al cargar sede: $error');
    }
  }

  /// **Actualiza la sede en Firestore y verifica la escritura**
  Future<void> setSede(String nuevaSede) async {
    if (!_validSedes.contains(nuevaSede)) {
      debugPrint(
          'SedeProvider: Intento de establecer sede inválida: $nuevaSede');
      return;
    }

    try {
      // Escribir en Firestore
      await FirebaseFirestore.instance
          .collection('config')
          .doc('sedeActual')
          .set({'sede': nuevaSede});

      // Verificar que la escritura fue exitosa
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('sedeActual')
          .get();

      if (doc.exists && doc['sede'] == nuevaSede) {
        _sede = nuevaSede;
        debugPrint('SedeProvider: Sede actualizada correctamente: $_sede');
        notifyListeners();
      } else {
        debugPrint(
            'SedeProvider: Fallo al verificar la escritura de sede: $nuevaSede');
      }
    } catch (error) {
      debugPrint('SedeProvider: Error al actualizar sede: $error');
    }
  }
}