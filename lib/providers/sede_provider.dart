import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Para debugPrint

class SedeProvider extends ChangeNotifier {
  List<String> _sedes = [];
  Map<String, String> _sedeImages = {};
  String _selectedSede = '';
  String _errorMessage = '';

  List<String> get sedes => _sedes;
  Map<String, String> get sedeImages => _sedeImages;
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
      debugPrint('Iniciando fetchSedes...');
      
      // Obtener todas las canchas para extraer las sedes únicas
      final snapshot = await FirebaseFirestore.instance
          .collection('canchas')
          .get();

      debugPrint('Documentos obtenidos: ${snapshot.docs.length}');
      final sedesSet = <String>{};
      final sedeImagesMap = <String, String>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final sede = data['sede'] as String?;
        final imageUrl = data['imagen'] as String?;
        debugPrint('Procesando documento: ${doc.id} - Sede: $sede - Imagen: $imageUrl');

        if (sede != null && sede.isNotEmpty) {
          sedesSet.add(sede);
          // Usar la imagen de la primera cancha encontrada para cada sede
          if (imageUrl != null && imageUrl.isNotEmpty && !sedeImagesMap.containsKey(sede)) {
            // Validar que la URL no sea placeholder antes de asignarla
            if (!imageUrl.contains('placeholder')) {
              sedeImagesMap[sede] = imageUrl;
            }
          }
        }
      }

      _sedes = sedesSet.toList()..sort();
      _sedeImages = sedeImagesMap;
      debugPrint('Sedes cargadas: $_sedes');
      debugPrint('Imágenes de sedes: $_sedeImages');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al cargar sedes: $e';
      debugPrint('Error en fetchSedes: $e');
      notifyListeners();
    }
  }

  // Método actualizado para crear una nueva sede creando una cancha placeholder
  Future<void> crearSede(String nombreSede, {String? imageUrl}) async {
  if (nombreSede.isEmpty) {
    _errorMessage = 'El nombre de la sede no puede estar vacío';
    debugPrint('Error: Nombre de sede vacío');
    notifyListeners();
    return;
  }

  // Verificar si ya existe una sede con ese nombre
  if (_sedes.contains(nombreSede)) {
    _errorMessage = 'Ya existe una sede con ese nombre';
    debugPrint('Error: Sede ya existe');
    notifyListeners();
    return;
  }

  try {
    _errorMessage = '';
    debugPrint('Creando sede: $nombreSede');
    
    // Usar imagen por defecto si no se proporciona una
    final defaultImageUrl = imageUrl ?? 'https://images.unsplash.com/photo-1544966503-7cc5ac882d5f?ixlib=rb-4.0.3&auto=format&fit=crop&w=300&h=200';
    
    // Crear una cancha placeholder para la nueva sede
    final sedeRef = FirebaseFirestore.instance.collection('canchas').doc();
    await sedeRef.set({
      'sede': nombreSede,
      'nombre': 'Cancha Principal', // Nombre por defecto
      'descripcion': 'Cancha principal de $nombreSede',
      'disponible': false,
      'imagen': defaultImageUrl,
      'precio': 100000.0, // Precio por defecto como double
      'techada': false,
      'servicios': '',
      'ubicacion': nombreSede.toLowerCase(),
      'motivoNoDisponible': "en espera para abrir",
      'preciosPorHorario': {
        'lunes': _crearHorariosPorDefecto(),
        'martes': _crearHorariosPorDefecto(),
        'miércoles': _crearHorariosPorDefecto(),
        'jueves': _crearHorariosPorDefecto(),
        'viernes': _crearHorariosPorDefecto(),
        'sábado': _crearHorariosPorDefecto(),
        'domingo': _crearHorariosPorDefecto(),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Actualizar la lista local
    _sedes.add(nombreSede);
    _sedes.sort();
    
    // Solo agregar la imagen al mapa si no es placeholder
    if (defaultImageUrl.isNotEmpty && !defaultImageUrl.contains('placeholder')) {
      _sedeImages[nombreSede] = defaultImageUrl;
    }
    
    debugPrint('Sede creada exitosamente: $nombreSede con imagen: $defaultImageUrl');
    notifyListeners();
  } catch (e) {
    _errorMessage = 'Error al crear la sede: $e';
    debugPrint('Error en crearSede: $e');
    notifyListeners();
  }
}


  // Método helper para crear horarios por defecto
  Map<String, double> _crearHorariosPorDefecto() {
  Map<String, double> horarios = {};
  for (int i = 5; i <= 23; i++) {
    String hora = '${i.toString().padLeft(2, '0')}:00';
    horarios[hora] = 100000.0; // Precio por defecto como double
  }
  debugPrint('Horarios creados: $horarios');
  return horarios;
}

  Future<void> renombrarSede(String nombreActual, String nuevoNombre) async {
    if (nuevoNombre.isEmpty) {
      _errorMessage = 'El nuevo nombre de la sede no puede estar vacío';
      debugPrint('Error: Nuevo nombre vacío');
      notifyListeners();
      return;
    }

    if (nombreActual == nuevoNombre) {
      _errorMessage = 'El nuevo nombre es idéntico al actual';
      debugPrint('Error: Nombres idénticos');
      notifyListeners();
      return;
    }

    // Verificar si ya existe una sede con el nuevo nombre
    if (_sedes.contains(nuevoNombre)) {
      _errorMessage = 'Ya existe una sede con ese nombre';
      debugPrint('Error: Sede ya existe con nuevo nombre');
      notifyListeners();
      return;
    }

    try {
      _errorMessage = '';
      debugPrint('Renombrando sede de $nombreActual a $nuevoNombre');
      
      // Obtener todas las canchas de la sede actual
      final canchaDocs = await FirebaseFirestore.instance
          .collection('canchas')
          .where('sede', isEqualTo: nombreActual)
          .get();

      debugPrint('Canchas encontradas: ${canchaDocs.docs.length}');
      final batch = FirebaseFirestore.instance.batch();
      
      for (var doc in canchaDocs.docs) {
        batch.update(doc.reference, {'sede': nuevoNombre});
      }

      // Actualizar reservas asociadas
      final reservaDocs = await FirebaseFirestore.instance
          .collection('reservas')
          .where('sede', isEqualTo: nombreActual)
          .get();

      debugPrint('Reservas encontradas: ${reservaDocs.docs.length}');
      for (var doc in reservaDocs.docs) {
        batch.update(doc.reference, {'sede': nuevoNombre});
      }

      await batch.commit();
      debugPrint('Batch commit ejecutado correctamente');

      // Actualizar listas locales
      if (_sedes.contains(nombreActual)) {
        _sedes.remove(nombreActual);
        _sedes.add(nuevoNombre);
        _sedes.sort();
        
        // Transferir la imagen al nuevo nombre
        if (_sedeImages.containsKey(nombreActual)) {
          _sedeImages[nuevoNombre] = _sedeImages[nombreActual]!;
          _sedeImages.remove(nombreActual);
        }
        
        if (_selectedSede == nombreActual) {
          _selectedSede = nuevoNombre;
        }
        debugPrint('Sedes actualizadas localmente: $_sedes');
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Error al renombrar la sede: $e';
      debugPrint('Error en renombrarSede: $e');
      notifyListeners();
    }
  }

  // Método para actualizar la imagen de una sede
  Future<void> actualizarImagenSede(String nombreSede, String nuevaImagenUrl) async {
    try {
      debugPrint('Actualizando imagen de sede: $nombreSede con URL: $nuevaImagenUrl');
      
      // Actualizar todas las canchas de la sede con la nueva imagen
      final canchaDocs = await FirebaseFirestore.instance
          .collection('canchas')
          .where('sede', isEqualTo: nombreSede)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in canchaDocs.docs) {
        batch.update(doc.reference, {'imagen': nuevaImagenUrl});
      }
      await batch.commit();

      // Actualizar el mapa local solo si la imagen no es placeholder
      if (nuevaImagenUrl.isNotEmpty && !nuevaImagenUrl.contains('placeholder')) {
        _sedeImages[nombreSede] = nuevaImagenUrl;
        debugPrint('Imagen actualizada localmente para $nombreSede: $nuevaImagenUrl');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error actualizando imagen de sede: $e');
      _errorMessage = 'Error al actualizar la imagen: $e';
      notifyListeners();
    }
  }

  // Método para eliminar una sede
  // Método para eliminar una sede y todas sus canchas asociadas
  Future<void> eliminarSede(String nombreSede) async {
    if (nombreSede.isEmpty) {
      _errorMessage = 'El nombre de la sede no puede estar vacío';
      notifyListeners();
      return;
    }

    try {
      _errorMessage = '';
      debugPrint('🗑️ Iniciando eliminación de sede: $nombreSede');
      
      // Obtener todas las canchas de la sede
      final canchaDocs = await FirebaseFirestore.instance
          .collection('canchas')
          .where('sede', isEqualTo: nombreSede)
          .get();

      debugPrint('📊 Canchas encontradas para eliminar: ${canchaDocs.docs.length}');

      // Verificar si hay reservas activas (futuras)
      final now = DateTime.now();
      final hoy = DateTime(now.year, now.month, now.day);
      
      final reservasActivasQuery = await FirebaseFirestore.instance
          .collection('reservas')
          .where('sede', isEqualTo: nombreSede)
          .get();

      // Filtrar reservas que son del día actual o futuras
      final reservasActivas = reservasActivasQuery.docs.where((doc) {
        final data = doc.data();
        final fechaStr = data['fecha'] as String?;
        if (fechaStr == null) return false;
        
        try {
          final fechaReserva = DateTime.parse(fechaStr);
          final fechaReservaSinHora = DateTime(fechaReserva.year, fechaReserva.month, fechaReserva.day);
          return fechaReservaSinHora.isAtSameMomentAs(hoy) || fechaReservaSinHora.isAfter(hoy);
        } catch (e) {
          debugPrint('Error parseando fecha de reserva: $e');
          return false;
        }
      }).toList();

      if (reservasActivas.isNotEmpty) {
        _errorMessage = 'No se puede eliminar la sede porque tiene ${reservasActivas.length} reserva(s) activa(s) para hoy o fechas futuras';
        debugPrint('⚠️ Reservas activas encontradas: ${reservasActivas.length}');
        notifyListeners();
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      
      // Eliminar todas las canchas de la sede
      for (var doc in canchaDocs.docs) {
        debugPrint('🗑️ Eliminando cancha: ${doc.id}');
        batch.delete(doc.reference);
      }

      // Eliminar todas las reservas históricas de la sede
      final todasReservas = await FirebaseFirestore.instance
          .collection('reservas')
          .where('sede', isEqualTo: nombreSede)
          .get();
      
      debugPrint('📊 Reservas históricas encontradas: ${todasReservas.docs.length}');
      
      for (var doc in todasReservas.docs) {
        debugPrint('🗑️ Eliminando reserva: ${doc.id}');
        batch.delete(doc.reference);
      }

      // Ejecutar todas las eliminaciones
      await batch.commit();
      debugPrint('✅ Batch commit ejecutado - Todo eliminado');
      
      // Actualizar listas locales
      _sedes.remove(nombreSede);
      _sedeImages.remove(nombreSede);
      if (_selectedSede == nombreSede) {
        _selectedSede = '';
      }
      
      debugPrint('✅ Sede eliminada exitosamente: $nombreSede');
      debugPrint('📊 Canchas eliminadas: ${canchaDocs.docs.length}');
      debugPrint('📊 Reservas eliminadas: ${todasReservas.docs.length}');
      
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al eliminar la sede: $e';
      debugPrint('❌ Error en eliminarSede: $e');
      notifyListeners();
    }
  }
  }
