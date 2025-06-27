import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Para debugPrint

class SedeProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _sedes = [];
  String _selectedSede = '';
  String _errorMessage = '';

  List<Map<String, dynamic>> get sedes => _sedes;
  List<String> get sedeNames => _sedes.map((sede) => sede['nombre'] as String).toList();
  Map<String, String> get sedeImages => {
        for (var sede in _sedes) sede['nombre'] as String: sede['imagen'] as String? ?? ''
      };
  String get selectedSede => _selectedSede;
  String get errorMessage => _errorMessage;

  void setSede(String sede) {
    _selectedSede = sede;
    debugPrint('Sede seleccionada: $sede');
    notifyListeners();
  }

  Future<void> fetchSedes() async {
    try {
      _errorMessage = '';
      debugPrint('Iniciando fetchSedes desde colección sedes...');
      debugPrint('Usuario autenticado: ${FirebaseAuth.instance.currentUser?.uid ?? "No autenticado"}');

      final snapshot = await FirebaseFirestore.instance
          .collection('sedes')
          .where('activa', isEqualTo: true)
          .orderBy('nombre')
          .get();

      debugPrint('Sedes obtenidas: ${snapshot.docs.length}');

      _sedes = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'nombre': data['nombre'] ?? '',
          'imagen': data['imagen'] ?? '',
          'descripcion': data['descripcion'] ?? '',
          'activa': data['activa'] ?? true,
          'ubicacion': data['ubicacion'] ?? '',
          'createdAt': data['createdAt']?.toDate() ?? DateTime.now(),
        };
      }).toList();

      debugPrint('Sedes cargadas: ${_sedes.map((s) => s['nombre']).toList()}');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al cargar sedes: $e';
      debugPrint('Error en fetchSedes: $e');
      notifyListeners();
    }
  }

  Future<bool> sedeHasCanchas(String nombreSede) async {
    try {
      final canchasSnapshot = await FirebaseFirestore.instance
          .collection('canchas')
          .where('sede', isEqualTo: nombreSede)
          .limit(1)
          .get();

      return canchasSnapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error verificando canchas de la sede: $e');
      return false;
    }
  }

  Future<void> crearSede(String nombreSede, {String? imageUrl, String? descripcion, String? ubicacion}) async {
    if (nombreSede.isEmpty) {
      _errorMessage = 'El nombre de la sede no puede estar vacío';
      debugPrint('Error: Nombre de sede vacío');
      notifyListeners();
      return;
    }

    if (_sedes.any((sede) => sede['nombre'] == nombreSede)) {
      _errorMessage = 'Ya existe una sede con ese nombre';
      debugPrint('Error: Sede ya existe');
      notifyListeners();
      return;
    }

    try {
      _errorMessage = '';
      debugPrint('Creando sede: $nombreSede');

      final defaultImageUrl = imageUrl ?? 'https://images.unsplash.com/photo-1544966503-7cc5ac882d5f?ixlib=rb-4.0.3&auto=format&fit=crop&w=300&h=200';

      final sedeRef = FirebaseFirestore.instance.collection('sedes').doc();
      await sedeRef.set({
        'nombre': nombreSede,
        'imagen': defaultImageUrl,
        'descripcion': descripcion ?? 'Presione para continuar',
        'ubicacion': ubicacion ?? nombreSede.toLowerCase(),
        'activa': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _sedes.add({
        'id': sedeRef.id,
        'nombre': nombreSede,
        'imagen': defaultImageUrl,
        'descripcion': descripcion ?? 'Presione para continuar',
        'ubicacion': ubicacion ?? nombreSede.toLowerCase(),
        'activa': true,
        'createdAt': null,
      });

      _sedes.sort((a, b) => (a['nombre'] as String).compareTo(b['nombre'] as String));

      debugPrint('Sede creada exitosamente: $nombreSede');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al crear la sede: $e';
      debugPrint('Error en crearSede: $e');
      notifyListeners();
    }
  }

  Future<void> renombrarSede(String sedeId, String nuevoNombre) async {
    if (nuevoNombre.isEmpty) {
      _errorMessage = 'El nuevo nombre de la sede no puede estar vacío';
      notifyListeners();
      return;
    }

    if (_sedes.any((sede) => sede['nombre'] == nuevoNombre)) {
      _errorMessage = 'Ya existe una sede con ese nombre';
      notifyListeners();
      return;
    }

    try {
      _errorMessage = '';
      debugPrint('Renombrando sede con ID: $sedeId a $nuevoNombre');

      final sedeIndex = _sedes.indexWhere((sede) => sede['id'] == sedeId);
      if (sedeIndex == -1) {
        _errorMessage = 'Sede no encontrada';
        notifyListeners();
        return;
      }

      final batch = FirebaseFirestore.instance.batch();

      final sedeRef = FirebaseFirestore.instance.collection('sedes').doc(sedeId);
      batch.update(sedeRef, {'nombre': nuevoNombre});

      final canchaDocs = await FirebaseFirestore.instance
          .collection('canchas')
          .where('sedeId', isEqualTo: sedeId)
          .get();

      for (var doc in canchaDocs.docs) {
        batch.update(doc.reference, {'sede': nuevoNombre});
      }

      await batch.commit();

      _sedes[sedeIndex]['nombre'] = nuevoNombre;
      _sedes.sort((a, b) => (a['nombre'] as String).compareTo(b['nombre'] as String));

      if (_selectedSede == _sedes[sedeIndex]['nombre']) {
        _selectedSede = nuevoNombre;
      }

      debugPrint('Sede renombrada exitosamente');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al renombrar la sede: $e';
      debugPrint('Error en renombrarSede: $e');
      notifyListeners();
    }
  }

  Future<void> actualizarImagenSede(String sedeId, String nuevaImagenUrl) async {
    try {
      debugPrint('Actualizando imagen de sede con ID: $sedeId');
      
      final sedeIndex = _sedes.indexWhere((sede) => sede['id'] == sedeId);
      if (sedeIndex == -1) {
        _errorMessage = 'Sede no encontrada';
        notifyListeners();
        return;
      }

      await FirebaseFirestore.instance
          .collection('sedes')
          .doc(sedeId)
          .update({'imagen': nuevaImagenUrl});

      _sedes[sedeIndex]['imagen'] = nuevaImagenUrl;

      debugPrint('Imagen actualizada exitosamente');
      notifyListeners();
    } catch (e) {
      debugPrint('Error actualizando imagen de sede: $e');
      _errorMessage = 'Error al actualizar la imagen: $e';
      notifyListeners();
    }
  }

  Future<void> desactivarSede(String sedeId) async {
    try {
      _errorMessage = '';
      debugPrint('Desactivando sede con ID: $sedeId');

      final now = DateTime.now();
      final hoy = DateTime(now.year, now.month, now.day);

      final sedeIndex = _sedes.indexWhere((sede) => sede['id'] == sedeId);
      if (sedeIndex == -1) {
        _errorMessage = 'Sede no encontrada';
        notifyListeners();
        return;
      }
      final nombreSede = _sedes[sedeIndex]['nombre'] as String;

      final reservasActivasQuery = await FirebaseFirestore.instance
          .collection('reservas')
          .where('sede', isEqualTo: sedeId)
          .get();

      final reservasActivas = reservasActivasQuery.docs.where((doc) {
        final data = doc.data();
        final fechaStr = data['fecha'] as String?;
        if (fechaStr == null) return false;

        try {
          final fechaReserva = DateTime.parse(fechaStr);
          final fechaReservaSinHora = DateTime(fechaReserva.year, fechaReserva.month, fechaReserva.day);
          return fechaReservaSinHora.isAtSameMomentAs(hoy) || fechaReservaSinHora.isAfter(hoy);
        } catch (e) {
          return false;
        }
      }).toList();

      if (reservasActivas.isNotEmpty) {
        _errorMessage = 'No se puede desactivar la sede porque tiene ${reservasActivas.length} reserva(s) activa(s)';
        notifyListeners();
        return;
      }

      await FirebaseFirestore.instance
          .collection('sedes')
          .doc(sedeId)
          .update({'activa': false});

      _sedes.removeAt(sedeIndex);

      if (_selectedSede == nombreSede) {
        _selectedSede = '';
      }

      debugPrint('Sede desactivada exitosamente: $nombreSede');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al desactivar la sede: $e';
      debugPrint('Error en desactivarSede: $e');
      notifyListeners();
    }
  }

  Future<void> eliminarSedeCompletamente(String sedeId) async {
    try {
      _errorMessage = '';
      debugPrint('🗑️ Eliminando completamente la sede con ID: $sedeId');

      final now = DateTime.now();
      final hoy = DateTime(now.year, now.month, now.day);

      final sedeIndex = _sedes.indexWhere((sede) => sede['id'] == sedeId);
      if (sedeIndex == -1) {
        _errorMessage = 'Sede no encontrada';
        notifyListeners();
        return;
      }
      final nombreSede = _sedes[sedeIndex]['nombre'] as String;

      final reservasActivasQuery = await FirebaseFirestore.instance
          .collection('reservas')
          .where('sede', isEqualTo: sedeId)
          .get();

      final reservasActivas = reservasActivasQuery.docs.where((doc) {
        final data = doc.data();
        final fechaStr = data['fecha'] as String?;
        if (fechaStr == null) return false;

        try {
          final fechaReserva = DateTime.parse(fechaStr);
          final fechaReservaSinHora = DateTime(fechaReserva.year, fechaReserva.month, fechaReserva.day);
          return fechaReservaSinHora.isAtSameMomentAs(hoy) || fechaReservaSinHora.isAfter(hoy);
        } catch (e) {
          return false;
        }
      }).toList();

      if (reservasActivas.isNotEmpty) {
        _errorMessage = 'No se puede eliminar la sede porque tiene reservas activas';
        notifyListeners();
        return;
      }

      final batch = FirebaseFirestore.instance.batch();

      final sedeRef = FirebaseFirestore.instance.collection('sedes').doc(sedeId);
      batch.delete(sedeRef);

      final canchaDocs = await FirebaseFirestore.instance
          .collection('canchas')
          .where('sedeId', isEqualTo: sedeId)
          .get();

      for (var doc in canchaDocs.docs) {
        batch.delete(doc.reference);
      }

      final reservaDocs = await FirebaseFirestore.instance
          .collection('reservas')
          .where('sede', isEqualTo: sedeId)
          .get();

      for (var doc in reservaDocs.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      if (sedeIndex != -1) {
        _sedes.removeAt(sedeIndex);
      }

      if (_selectedSede == nombreSede) {
        _selectedSede = '';
      }

      debugPrint('✅ Sede eliminada completamente: $nombreSede');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al eliminar la sede: $e';
      debugPrint('❌ Error en eliminarSedeCompletamente: $e');
      notifyListeners();
    }
  }

  Future<void> eliminarSede(String sedeId) async {
    try {
      _errorMessage = '';
      debugPrint('Eliminando sede: $sedeId');

      final canchasSnapshot = await FirebaseFirestore.instance
          .collection('canchas')
          .where('sedeId', isEqualTo: sedeId)
          .get();

      for (var doc in canchasSnapshot.docs) {
        await doc.reference.delete();
      }

      await FirebaseFirestore.instance.collection('sedes').doc(sedeId).delete();

      debugPrint('Sede $sedeId eliminada con éxito');
      await fetchSedes();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al eliminar sede: $e';
      debugPrint('Error en eliminarSede: $e');
      notifyListeners();
      rethrow;
    }
  }
}