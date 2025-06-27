import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'dart:developer' as developer;
import '../models/cancha.dart';

class CanchaProvider with ChangeNotifier {
  List<Cancha> _canchas = [];
  final Map<String, Map<DateTime, List<TimeOfDay>>> _horasReservadas = {};
  bool _isLoading = false;
  String _errorMessage = '';

  List<Cancha> get canchas => _canchas;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;

  Map<DateTime, List<TimeOfDay>> horasReservadasPorCancha(String canchaId) {
    return _horasReservadas[canchaId] ?? {};
  }

  void limpiarCanchas() {
    developer.log('🧹 Limpiando canchas anteriores...', name: 'CanchaProvider');
    _canchas.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      developer.log('🔔 Notificando limpieza de canchas', name: 'CanchaProvider');
      notifyListeners();
    });
  }

  /// Obtiene la URL de descarga de Firebase Storage
  Future<String> _getDownloadUrl(String imagePath) async {
    try {
      // Si ya es una URL completa, la devolvemos tal como está
      if (imagePath.startsWith('http')) {
        return imagePath;
      }

      // Si es una referencia gs://, la convertimos
      if (imagePath.startsWith('gs://')) {
        final ref = FirebaseStorage.instance.refFromURL(imagePath);
        return await ref.getDownloadURL();
      }

      // Si es una ruta simple (como 'canchas/imagen.jpg'), creamos la referencia
      final ref = FirebaseStorage.instance.ref().child(imagePath);
      return await ref.getDownloadURL();
    } catch (e) {
      developer.log('❌ Error obteniendo URL de descarga para $imagePath: $e', 
          name: 'CanchaProvider', error: e);
      // Devolver una URL por defecto o la ruta original
      return 'assets/cancha_demo.png';
    }
  }

  /// Procesa una cancha para obtener su URL de imagen real
  Future<Cancha> _procesarCancha(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    // Obtener la URL real de la imagen
    String imagenUrl = data['imagen'] as String? ?? 'assets/cancha_demo.png';
    
    // Si la imagen no es un asset local, obtener URL de descarga
    if (!imagenUrl.startsWith('assets/')) {
      imagenUrl = await _getDownloadUrl(imagenUrl);
    }

    // Optimizar conversión de preciosPorHorario
    final preciosPorHorario = <String, Map<String, double>>{};
    if (data.containsKey('preciosPorHorario')) {
      final preciosRaw = Map<String, dynamic>.from(data['preciosPorHorario'] as Map);
      preciosPorHorario.addAll(preciosRaw.map((day, horarios) => MapEntry(
        day,
        (horarios is Map)
            ? Map<String, double>.from(
                horarios.map((hora, precio) => MapEntry(
                  hora,
                  (precio is num) ? precio.toDouble() : 0.0,
                )),
              )
            : <String, double>{},
      )));
    }

    return Cancha(
      id: doc.id,
      nombre: data['nombre'] as String? ?? '',
      descripcion: data['descripcion'] as String? ?? '',
      imagen: imagenUrl, // URL real de descarga
      techada: data['techada'] as bool? ?? false,
      ubicacion: data['ubicacion'] as String? ?? '',
      precio: (data['precio'] is num) ? (data['precio'] as num).toDouble() : 0.0,
      sedeId: data['sedeId'] as String? ?? '',
      preciosPorHorario: preciosPorHorario,
      disponible: data['disponible'] as bool? ?? true,
      motivoNoDisponible: data['motivoNoDisponible'] as String?,
    );
  }

  Future<void> fetchCanchas(String sede) async {
    _isLoading = true;
    _errorMessage = '';
    _canchas.clear();

    try {
      developer.log('🔍 Consultando canchas para sedeId: "$sede"', name: 'CanchaProvider');
      
      // Optimización: Usar get() con Source.server para datos frescos pero permitir cache en offline
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('canchas')
          .where('sedeId', isEqualTo: sede)
          .get();

      developer.log('📄 Documentos encontrados: ${querySnapshot.docs.length}', name: 'CanchaProvider');
      
      if (querySnapshot.docs.isEmpty) {
        _errorMessage = "No hay canchas registradas para la sedeId '$sede'.";
        developer.log('⚠️ No se encontraron canchas para "$sede"', name: 'CanchaProvider');
      } else {
        List<Cancha> canchasProcessed = [];
        for (DocumentSnapshot doc in querySnapshot.docs) {
          try {
            final cancha = await _procesarCancha(doc);
            canchasProcessed.add(cancha);
            developer.log('✅ Cancha procesada: ${cancha.nombre} - SedeId: ${cancha.sedeId}', 
                name: 'CanchaProvider');
          } catch (e) {
            developer.log('❌ Error procesando cancha ${doc.id}: $e', 
                name: 'CanchaProvider', error: e);
            canchasProcessed.add(Cancha.fromFirestore(doc));
          }
        }
        _canchas = canchasProcessed;
        developer.log('✅ Total canchas cargadas: ${_canchas.length}', name: 'CanchaProvider');
      }
    } catch (error) {
      _errorMessage = 'Error al cargar canchas: $error';
      developer.log('❌ Error en fetchCanchas: $error', name: 'CanchaProvider', error: error);
    } finally {
      _isLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        developer.log('🔔 Notificando cambios en fetchCanchas', name: 'CanchaProvider');
        notifyListeners();
      });
    }
  }

  Future<void> fetchAllCanchas() async {
    _isLoading = true;
    _errorMessage = '';

    try {
      // Optimización: Consulta directa sin filtros innecesarios
      QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance.collection('canchas').get();

      if (querySnapshot.docs.isEmpty) {
        _errorMessage = "No hay canchas registradas.";
      } else {
        // Procesar cada cancha para obtener URLs reales
        List<Cancha> canchasProcessed = [];
        for (DocumentSnapshot doc in querySnapshot.docs) {
          try {
            final cancha = await _procesarCancha(doc);
            canchasProcessed.add(cancha);
          } catch (e) {
            developer.log('❌ Error procesando cancha ${doc.id}: $e', 
                name: 'CanchaProvider', error: e);
            // Agregar cancha con imagen por defecto
            canchasProcessed.add(Cancha.fromFirestore(doc));
          }
        }
        
        _canchas = canchasProcessed;
        developer.log('✅ Todas las canchas cargadas: ${_canchas.length}', name: 'CanchaProvider');
      }
    } catch (error) {
      _errorMessage = 'Error al cargar todas las canchas: $error';
      developer.log('❌ Error en fetchAllCanchas: $error', name: 'CanchaProvider', error: error);
    } finally {
      _isLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        developer.log('🔔 Notificando cambios en fetchAllCanchas', name: 'CanchaProvider');
        notifyListeners();
      });
    }
  }

  Future<void> fetchHorasReservadas() async {
    _isLoading = true;
    _errorMessage = '';

    try {
      // Optimización: Solo obtener reservas activas/futuras para reducir datos transferidos
      final fechaHoy = DateTime.now();
      final fechaInicio = DateFormat('yyyy-MM-dd').format(fechaHoy);
      
      QuerySnapshot reservasSnapshot = await FirebaseFirestore.instance
          .collection('reservas')
          .where('fecha', isGreaterThanOrEqualTo: fechaInicio)
          .get();
      
      _horasReservadas.clear();

      for (var doc in reservasSnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        final canchaId = data['cancha_id'] ?? '';
        
        // Validar que el canchaId no esté vacío
        if (canchaId.isEmpty) continue;
        
        final fecha = DateFormat('yyyy-MM-dd').parse(data['fecha']);
        final horaStrFull = data['horario'] as String;
        final horaStr = horaStrFull.split(' ')[0];
        final is12HourFormat =
            horaStrFull.contains(RegExp(r'(AM|PM)', caseSensitive: false));
        int hour = int.parse(horaStr.split(':')[0]);
        final minute = int.parse(horaStr.split(':')[1]);

        if (is12HourFormat) {
          final period = horaStrFull.toUpperCase().contains('PM') ? 'PM' : 'AM';
          if (period == 'PM' && hour != 12) {
            hour += 12;
          } else if (period == 'AM' && hour == 12) {
            hour = 0;
          }
        }

        final hora = TimeOfDay(hour: hour, minute: minute);

        _horasReservadas.putIfAbsent(canchaId, () => {});
        _horasReservadas[canchaId]!.putIfAbsent(fecha, () => []);
        if (!_horasReservadas[canchaId]![fecha]!.contains(hora)) {
          _horasReservadas[canchaId]![fecha]!.add(hora);
        }
      }
    } catch (error) {
      _errorMessage = 'Error al cargar horas reservadas: $error';
      developer.log('❌ Error en fetchHorasReservadas: $error', name: 'CanchaProvider', error: error);
    } finally {
      _isLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        developer.log('🔔 Notificando cambios en fetchHorasReservadas', name: 'CanchaProvider');
        notifyListeners();
      });
    }
  }

  void reset() {
    _canchas.clear();
    _horasReservadas.clear();
    _isLoading = false;
    _errorMessage = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      developer.log('🔔 Notificando reset de CanchaProvider', name: 'CanchaProvider');
      notifyListeners();
    });
  }
}