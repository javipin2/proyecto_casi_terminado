import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:reserva_canchas/models/horario.dart';
import 'dart:developer' as developer;
import '../models/cancha.dart';

class CanchaProvider with ChangeNotifier {
  List<Cancha> _canchas = [];
  final Map<String, Map<DateTime, List<TimeOfDay>>> _horasReservadas = {};
  bool _isLoading = false;
  String _errorMessage = '';
  String? _lugarId; // Nuevo: ID del lugar para filtrar canchas
  String? _lastLoadedLugarId;
  bool _isFetching = false;

  List<Cancha> get canchas => _canchas;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  String? get lugarId => _lugarId;

  Map<DateTime, List<TimeOfDay>> horasReservadasPorCancha(String canchaId) {
    return _horasReservadas[canchaId] ?? {};
  }

  // Nuevo: Establecer lugar para filtrar canchas
  void setLugar(String lugarId) {
    if (_lugarId == lugarId) return;
    _lugarId = lugarId;
    developer.log('Lugar establecido en CanchaProvider: $lugarId', name: 'CanchaProvider');
    // No dispara carga aquí para evitar duplicados; el llamador decide
    notifyListeners();
  }

  // Nuevo: Limpiar lugar
  void clearLugar() {
    _lugarId = null;
    _canchas = [];
    developer.log('Lugar limpiado en CanchaProvider', name: 'CanchaProvider');
    notifyListeners();
  }

  void limpiarCanchas() {
    if (_canchas.isEmpty) return;
    _canchas.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      developer.log('Notificando limpieza de canchas', name: 'CanchaProvider');
      notifyListeners();
    });
  }

  Future<String> _getDownloadUrl(String imagePath) async {
    try {
      if (imagePath.startsWith('http')) return imagePath;
      final ref = imagePath.startsWith('gs://') 
          ? FirebaseStorage.instance.refFromURL(imagePath)
          : FirebaseStorage.instance.ref().child(imagePath);
      return await ref.getDownloadURL();
    } catch (e) {
      developer.log('Error obteniendo URL para $imagePath: $e', name: 'CanchaProvider', error: e);
      return 'assets/cancha_demo.png';
    }
  }

  // Versión simplificada que usa directamente Cancha.fromFirestore:

Future<Cancha> _procesarCancha(DocumentSnapshot doc) async {
  // Usar directamente el método fromFirestore que ya tiene la lógica correcta
  final cancha = Cancha.fromFirestore(doc);
  
  // Solo procesar la imagen si es necesario
  if (cancha.imagen.startsWith('assets/')) {
    return cancha;
  }
  
  try {
    final finalImagenUrl = await _getDownloadUrl(cancha.imagen);
    
    // Crear una nueva instancia con la URL actualizada
    return Cancha(
      id: cancha.id,
      nombre: cancha.nombre,
      descripcion: cancha.descripcion,
      imagen: finalImagenUrl,
      techada: cancha.techada,
      ubicacion: cancha.ubicacion,
      precio: cancha.precio,
      sedeId: cancha.sedeId,
      lugarId: cancha.lugarId, // ✅ Agregar lugarId
      preciosPorHorario: cancha.preciosPorHorario, // ✅ Mantiene toda la lógica correcta
      disponible: cancha.disponible,
      motivoNoDisponible: cancha.motivoNoDisponible,
    );
  } catch (e) {
    developer.log('Error procesando imagen para ${cancha.nombre}: $e', name: 'CanchaProvider', error: e);
    return cancha; // Retornar la cancha original si hay error con la imagen
  }
}


  Future<void> _fetchCanchas({String? sede}) async {
    if (_isFetching) {
      developer.log('fetchCanchas evitado: ya hay una carga en curso', name: 'CanchaProvider');
      return;
    }
    _isLoading = true;
    _errorMessage = '';
    _canchas.clear();

    try {
      developer.log('Consultando canchas${sede != null ? ' para sedeId: "$sede"' : ''}${_lugarId != null ? ' para lugarId: "$_lugarId"' : ''}', name: 'CanchaProvider');
      
      Query query = FirebaseFirestore.instance
          .collection('canchas')
          .limit(100);
      
      // Si hay sede específica, filtrar por sede
      if (sede != null) {
        query = query.where('sedeId', isEqualTo: sede);
      }
      
      // Si hay lugar específico, filtrar por lugar
      if (_lugarId != null) {
        query = query.where('lugarId', isEqualTo: _lugarId);
      }
      
      if (sede == null && _lastLoadedLugarId == _lugarId && _canchas.isNotEmpty) {
        developer.log('Canchas ya cargadas para lugar $_lugarId, omitiendo recarga', name: 'CanchaProvider');
        _isLoading = false;
        notifyListeners();
        return;
      }

      _isFetching = true;
      final querySnapshot = await query.get();

      developer.log('Documentos encontrados: ${querySnapshot.docs.length}', name: 'CanchaProvider');

      if (querySnapshot.docs.isEmpty) {
        _errorMessage = sede != null
            ? "No hay canchas registradas para la sedeId '$sede'."
            : "No hay canchas registradas.";
        developer.log('No se encontraron canchas${sede != null ? ' para "$sede"' : ''}', name: 'CanchaProvider');
      } else {
        _canchas = await Future.wait(querySnapshot.docs.map((doc) async {
          try {
            final cancha = await _procesarCancha(doc);
            developer.log('Cancha procesada: ${cancha.nombre} - SedeId: ${cancha.sedeId}', name: 'CanchaProvider');
            return cancha;
          } catch (e) {
            developer.log('Error procesando cancha ${doc.id}: $e', name: 'CanchaProvider', error: e);
            return Cancha.fromFirestore(doc);
          }
        }));
        developer.log('Total canchas cargadas: ${_canchas.length}', name: 'CanchaProvider');
      }
    } catch (error) {
      _errorMessage = 'Error al cargar canchas: $error';
      developer.log('Error en fetchCanchas: $error', name: 'CanchaProvider', error: error);
    } finally {
      _isLoading = false;
      _isFetching = false;
      _lastLoadedLugarId = _lugarId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        developer.log('Notificando cambios en fetchCanchas', name: 'CanchaProvider');
        notifyListeners();
      });
    }
  }

  Future<void> fetchCanchas(String sede) async => _fetchCanchas(sede: sede);

  Future<void> fetchAllCanchas() async => _fetchCanchas();

  Future<void> fetchHorasReservadas() async {
  _isLoading = true;
  _errorMessage = '';
  _horasReservadas.clear();

  try {
    final fechaInicio = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final reservasSnapshot = await FirebaseFirestore.instance
        .collection('reservas')
        .where('fecha', isGreaterThanOrEqualTo: fechaInicio)
        .where('confirmada', isEqualTo: true) // ✅ Solo reservas confirmadas
        .get();

    for (var doc in reservasSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final canchaId = data['cancha_id'] as String? ?? '';
      if (canchaId.isEmpty) continue;

      final fecha = DateFormat('yyyy-MM-dd').parse(data['fecha'] as String);
      final horaStr = data['horario'] as String? ?? '0:00';
      final horario = Horario.fromHoraFormateada(horaStr);

      _horasReservadas.putIfAbsent(canchaId, () => {});
      _horasReservadas[canchaId]!.putIfAbsent(fecha, () => []);
      if (!_horasReservadas[canchaId]![fecha]!.contains(horario.hora)) {
        _horasReservadas[canchaId]![fecha]!.add(horario.hora);
      }
    }
  } catch (error) {
    _errorMessage = 'Error al cargar horas reservadas: $error';
    developer.log('Error en fetchHorasReservadas: $error', name: 'CanchaProvider', error: error);
  } finally {
    _isLoading = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      developer.log('Notificando cambios en fetchHorasReservadas', name: 'CanchaProvider');
      notifyListeners();
    });
  }
}


  void reset() {
    if (_canchas.isEmpty && _horasReservadas.isEmpty && !_isLoading && _errorMessage.isEmpty) return;
    _canchas.clear();
    _horasReservadas.clear();
    _isLoading = false;
    _errorMessage = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      developer.log('Notificando reset de CanchaProvider', name: 'CanchaProvider');
      notifyListeners();
    });
  }
}