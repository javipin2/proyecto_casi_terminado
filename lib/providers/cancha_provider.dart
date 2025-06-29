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

  List<Cancha> get canchas => _canchas;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;

  Map<DateTime, List<TimeOfDay>> horasReservadasPorCancha(String canchaId) {
    return _horasReservadas[canchaId] ?? {};
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

  Future<Cancha> _procesarCancha(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    final imagenUrl = data['imagen'] as String? ?? 'assets/cancha_demo.png';
    final finalImagenUrl = imagenUrl.startsWith('assets/') ? imagenUrl : await _getDownloadUrl(imagenUrl);

    final preciosPorHorario = <String, Map<String, Map<String, dynamic>>>{};
    if (data['preciosPorHorario'] is Map) {
      final preciosRaw = data['preciosPorHorario'] as Map<String, dynamic>;
      preciosPorHorario.addAll(preciosRaw.map((day, horarios) => MapEntry(
        day,
        horarios is Map
            ? Map<String, Map<String, dynamic>>.from(horarios.map((hora, datos) => MapEntry(
                  hora,
                  datos is num
                      ? {'precio': datos.toDouble(), 'habilitada': true}
                      : datos is Map
                          ? {
                              'precio': (datos['precio'] as num?)?.toDouble() ?? 0.0,
                              'habilitada': datos['habilitada'] as bool? ?? true,
                            }
                          : {'precio': 0.0, 'habilitada': true},
                )))
            : <String, Map<String, dynamic>>{},
      )));
    }

    return Cancha(
      id: doc.id,
      nombre: data['nombre'] as String? ?? '',
      descripcion: data['descripcion'] as String? ?? '',
      imagen: finalImagenUrl,
      techada: data['techada'] as bool? ?? false,
      ubicacion: data['ubicacion'] as String? ?? '',
      precio: (data['precio'] as num?)?.toDouble() ?? 0.0,
      sedeId: data['sedeId'] as String? ?? '',
      preciosPorHorario: preciosPorHorario,
      disponible: data['disponible'] as bool? ?? true,
      motivoNoDisponible: data['motivoNoDisponible'] as String?,
    );
  }

  Future<void> _fetchCanchas({String? sede}) async {
    _isLoading = true;
    _errorMessage = '';
    _canchas.clear();

    try {
      developer.log('Consultando canchas${sede != null ? ' para sedeId: "$sede"' : ''}', name: 'CanchaProvider');
      final query = sede != null
          ? FirebaseFirestore.instance.collection('canchas').where('sedeId', isEqualTo: sede)
          : FirebaseFirestore.instance.collection('canchas');
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