import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:reserva_canchas/providers/audit_provider.dart'; // Para debugPrint

class SedeProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _sedes = [];
  String _selectedSede = '';
  String _errorMessage = '';
  String? _lugarId; // Nuevo: ID del lugar para filtrar sedes
  String? _lastLoadedLugarId;
  bool _isFetching = false;

  List<Map<String, dynamic>> get sedes => _sedes;
  List<String> get sedeNames =>
      _sedes.map((sede) => sede['nombre'] as String).toList();
  Map<String, String> get sedeImages => {
        for (var sede in _sedes)
          sede['nombre'] as String: sede['imagen'] as String? ?? ''
      };
  String get selectedSede => _selectedSede;
  String get errorMessage => _errorMessage;
  String? get lugarId => _lugarId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void setSede(String sede) {
    _selectedSede = sede;
    debugPrint('Sede seleccionada: $sede');
    notifyListeners();
  }

  // Nuevo: Establecer lugar para filtrar sedes
  void setLugar(String lugarId) {
    if (_lugarId == lugarId) return; // Evitar notificaciones innecesarias
    _lugarId = lugarId;
    debugPrint('Lugar establecido: $lugarId');
    // No llamamos fetchSedes aquí para evitar doble carga si el llamador ya la dispara
    notifyListeners();
  }

  // Nuevo: Limpiar lugar
  void clearLugar() {
    _lugarId = null;
    _sedes = [];
    _selectedSede = '';
    debugPrint('Lugar limpiado');
    notifyListeners();
  }

  Future<void> fetchSedes() async {
    if (_isFetching) {
      debugPrint('fetchSedes evitado: ya hay una carga en curso');
      return;
    }
    try {
      _errorMessage = '';
      debugPrint('Iniciando fetchSedes desde colección sedes...');
      debugPrint(
          'Usuario autenticado: ${FirebaseAuth.instance.currentUser?.uid ?? "No autenticado"}');
      debugPrint('Lugar ID: $_lugarId');

      if (_lugarId == null) {
        _errorMessage = 'No se ha seleccionado un lugar';
        debugPrint('Error: No se ha seleccionado un lugar');
        notifyListeners();
        return;
      }

      if (_lastLoadedLugarId == _lugarId && _sedes.isNotEmpty) {
        debugPrint('Sedes ya cargadas para lugar $_lugarId, omitiendo recarga');
        return;
      }

      _isFetching = true;

      // Solo validar permisos si el usuario está autenticado y tiene rol
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(user.uid)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            final userRole = userData['rol'];
            final userLugarId = userData['lugarId'];
            
            // Solo validar si el usuario tiene un rol (no es visitante)
            if (userRole != null && userRole != 'programador' && userLugarId != _lugarId) {
              _errorMessage = 'No tienes permisos para acceder a este lugar';
              debugPrint('Error: Usuario no autorizado para lugar $_lugarId');
              notifyListeners();
              return;
            }
          }
        } catch (e) {
          debugPrint('Error verificando permisos: $e');
          // Si hay error, permitir acceso (fallback para visitantes)
        }
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('sede')
          .where('lugarId', isEqualTo: _lugarId)
          .where('activa', isEqualTo: true)
          .orderBy('nombre')
          .limit(100)
          .get();

      debugPrint('Sedes obtenidas para lugar $_lugarId: ${snapshot.docs.length}');

      _sedes = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'nombre': data['nombre'] ?? '',
          'imagen': data['imagen'] ?? '',
          'descripcion': data['descripcion'] ?? '',
          'activa': data['activa'] ?? true,
          'ubicacion': data['ubicacion'] ?? '',
          'latitud': data['latitud'],
          'longitud': data['longitud'],
          'createdAt': data['createdAt']?.toDate() ?? DateTime.now(),
        };
      }).toList();

      debugPrint('Sedes cargadas: ${_sedes.map((s) => s['nombre']).toList()}');
      _lastLoadedLugarId = _lugarId;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al cargar sedes: $e';
      debugPrint('Error en fetchSedes: $e');
      notifyListeners();
    }
    finally {
      _isFetching = false;
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

  Future<void> crearSede(String nombreSede,
      {String? imageUrl, String? descripcion, String? ubicacion, double? latitud, double? longitud}) async {
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

      final defaultImageUrl = imageUrl ??
          'https://images.unsplash.com/photo-1544966503-7cc5ac882d5f?ixlib=rb-4.0.3&auto=format&fit=crop&w=300&h=200';

      final sedeRef = FirebaseFirestore.instance.collection('sede').doc();
      await sedeRef.set({
        'nombre': nombreSede,
        'imagen': defaultImageUrl,
        'descripcion': descripcion ?? 'Presione para continuar',
        'ubicacion': ubicacion ?? nombreSede.toLowerCase(),
        'latitud': latitud,
        'longitud': longitud,
        'lugarId': _lugarId, // ✅ Agregar lugarId
        'activa': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 🔍 AUDITORÍA: Registrar creación de sede
      await AuditProvider.registrarAccion(
        accion: 'crear_sede',
        entidad: 'sede',
        entidadId: sedeRef.id,
        datosNuevos: {
          'nombre': nombreSede,
          'imagen': defaultImageUrl,
          'descripcion': descripcion ?? 'Presione para continuar',
          'ubicacion': ubicacion ?? nombreSede.toLowerCase(),
          'latitud': latitud,
          'longitud': longitud,
          'lugarId': _lugarId,
          'activa': true,
        },
        metadatos: {
          'nombre_sede': nombreSede,
          'imagen_url': defaultImageUrl,
        },
        descripcion: 'Nueva sede creada: $nombreSede',
      );

      _sedes.add({
        'id': sedeRef.id,
        'nombre': nombreSede,
        'imagen': defaultImageUrl,
        'descripcion': descripcion ?? 'Presione para continuar',
        'ubicacion': ubicacion ?? nombreSede.toLowerCase(),
        'latitud': latitud,
        'longitud': longitud,
        'activa': true,
        'createdAt': DateTime.now(),
      });

      _sedes.sort(
          (a, b) => (a['nombre'] as String).compareTo(b['nombre'] as String));

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

      final sedeRef = FirebaseFirestore.instance.collection('sede').doc(sedeId);
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
      _sedes.sort(
          (a, b) => (a['nombre'] as String).compareTo(b['nombre'] as String));

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

  Future<void> actualizarUbicacionSede(
      String sedeId, double? latitud, double? longitud) async {
    try {
      debugPrint('Actualizando ubicación de sede con ID: $sedeId');

      final sedeIndex = _sedes.indexWhere((sede) => sede['id'] == sedeId);
      if (sedeIndex == -1) {
        _errorMessage = 'Sede no encontrada';
        notifyListeners();
        return;
      }

      final updateData = <String, dynamic>{};
      if (latitud != null && longitud != null) {
        updateData['latitud'] = latitud;
        updateData['longitud'] = longitud;
      }

      await FirebaseFirestore.instance
          .collection('sede')
          .doc(sedeId)
          .update(updateData);

      _sedes[sedeIndex]['latitud'] = latitud;
      _sedes[sedeIndex]['longitud'] = longitud;

      debugPrint('Ubicación actualizada exitosamente');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al actualizar la ubicación: $e';
      debugPrint('Error en actualizarUbicacionSede: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> actualizarImagenSede(
      String sedeId, String nuevaImagenUrl) async {
    try {
      debugPrint('Actualizando imagen de sede con ID: $sedeId');

      final sedeIndex = _sedes.indexWhere((sede) => sede['id'] == sedeId);
      if (sedeIndex == -1) {
        _errorMessage = 'Sede no encontrada';
        notifyListeners();
        return;
      }

      await FirebaseFirestore.instance
          .collection('sede')
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
      final datosSedeAnterior = Map<String, dynamic>.from(_sedes[sedeIndex]);

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
          final fechaReservaSinHora =
              DateTime(fechaReserva.year, fechaReserva.month, fechaReserva.day);
          return fechaReservaSinHora.isAtSameMomentAs(hoy) ||
              fechaReservaSinHora.isAfter(hoy);
        } catch (e) {
          return false;
        }
      }).toList();

      if (reservasActivas.isNotEmpty) {
        _errorMessage =
            'No se puede desactivar la sede porque tiene ${reservasActivas.length} reserva(s) activa(s)';
        notifyListeners();
        return;
      }

      await FirebaseFirestore.instance
          .collection('sede')
          .doc(sedeId)
          .update({'activa': false});

      // 🔍 AUDITORÍA: Registrar desactivación de sede
      await AuditProvider.registrarAccion(
        accion: 'desactivar_sede',
        entidad: 'sede',
        entidadId: sedeId,
        datosAntiguos: datosSedeAnterior,
        datosNuevos: {'activa': false},
        metadatos: {
          'nombre_sede': nombreSede,
          'reservas_verificadas': reservasActivas.length,
        },
        descripcion: 'Sede desactivada: $nombreSede',
      );

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
          final fechaReservaSinHora =
              DateTime(fechaReserva.year, fechaReserva.month, fechaReserva.day);
          return fechaReservaSinHora.isAtSameMomentAs(hoy) ||
              fechaReservaSinHora.isAfter(hoy);
        } catch (e) {
          return false;
        }
      }).toList();

      if (reservasActivas.isNotEmpty) {
        _errorMessage =
            'No se puede eliminar la sede porque tiene reservas activas';
        notifyListeners();
        return;
      }

      final batch = FirebaseFirestore.instance.batch();

      final sedeRef = FirebaseFirestore.instance.collection('sede').doc(sedeId);
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

      await FirebaseFirestore.instance.collection('sede').doc(sedeId).delete();

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

  Future<String?> getDownloadLinkFromFirebase() async {
    try {
      DocumentSnapshot linkDoc =
          await _firestore.collection('link').doc('descarga').get();

      if (linkDoc.exists) {
        Map<String, dynamic> data = linkDoc.data() as Map<String, dynamic>;
        return data['apk_url'] as String?;
      }

      return null;
    } catch (e) {
      print('Error al obtener enlace de descarga desde Firebase: $e');
      return null;
    }
  }

  // Método alternativo para obtener múltiples campos del documento descarga
  Future<Map<String, dynamic>?> getDownloadInfo() async {
    try {
      DocumentSnapshot linkDoc =
          await _firestore.collection('link').doc('descarga').get();

      if (linkDoc.exists) {
        return linkDoc.data() as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('Error al obtener información de descarga: $e');
      return null;
    }
  }

  // Método para verificar si el enlace está activo
  Future<bool> isDownloadLinkActive() async {
    try {
      DocumentSnapshot linkDoc =
          await _firestore.collection('link').doc('descarga').get();

      if (linkDoc.exists) {
        Map<String, dynamic> data = linkDoc.data() as Map<String, dynamic>;
        return data['active'] ?? true; // Por defecto true si no existe el campo
      }

      return false;
    } catch (e) {
      print('Error al verificar estado del enlace: $e');
      return false;
    }
  }

  // Método para actualizar el enlace de descarga (para admin)
  Future<bool> updateDownloadLink(String newLink) async {
    try {
      await _firestore.collection('link').doc('descarga').set({
        'apk_url': newLink,
        'updated_at': FieldValue.serverTimestamp(),
        'active': true,
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      print('Error al actualizar enlace de descarga: $e');
      return false;
    }
  }

  // Método para desactivar el enlace de descarga
  Future<bool> deactivateDownloadLink() async {
    try {
      await _firestore.collection('link').doc('descarga').update({
        'active': false,
        'deactivated_at': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('Error al desactivar enlace: $e');
      return false;
    }
  }
}
