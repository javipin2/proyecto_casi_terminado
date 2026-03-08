import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/horario.dart';

/// Provider centralizado para gestionar promociones
/// Evita streams duplicados y reduce costos de Firestore
class PromocionProvider with ChangeNotifier {
  // Streams activos por clave única (lugarId_canchaId_fecha)
  final Map<String, StreamSubscription<QuerySnapshot>> _firestoreStreams = {};
  final Map<String, StreamSubscription<QuerySnapshot>> _reservasStreams = {}; // ✅ NUEVO: Streams de reservas
  final Map<String, StreamController<Map<String, Map<String, dynamic>>>> _streamControllers = {};
  final Map<String, Map<String, Map<String, dynamic>>> _promocionesCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  /// Último valor emitido por clave (para reenviar a nuevos listeners al volver a la pantalla)
  final Map<String, Map<String, Map<String, dynamic>>> _lastEmittedByKey = {};
  
  // TTL del caché: 2 minutos
  static const Duration _cacheTTL = Duration(minutes: 2);
  
  /// Obtener promociones para una combinación específica
  /// Retorna un stream que se actualiza automáticamente
  Stream<Map<String, Map<String, dynamic>>> getPromociones({
    required String lugarId,
    required String canchaId,
    required String fecha, // formato: yyyy-MM-dd
    String? sedeId, // Opcional: para filtrar por sede
    String? sedeNombre, // Opcional: nombre de la sede
  }) {
    final cacheKey = '${lugarId}_${canchaId}_$fecha';

    // ✅ Reutilizar streams existentes. Al volver a la pantalla, el nuevo listener debe recibir
    // siempre un valor inicial (caché o último emitido) y luego las actualizaciones del controller.
    final existingController = _streamControllers[cacheKey];
    if (existingController != null && !existingController.isClosed) {
      // Reenviar último valor conocido para que el nuevo listener no quede sin datos
      final Map<String, Map<String, dynamic>> initialValue =
          _promocionesCache.containsKey(cacheKey) &&
                  _cacheTimestamps[cacheKey] != null &&
                  DateTime.now().difference(_cacheTimestamps[cacheKey]!) < _cacheTTL
              ? _promocionesCache[cacheKey]!
              : (_lastEmittedByKey[cacheKey] ?? {});
      return Stream.value(initialValue)
          .asyncExpand((_) => existingController.stream);
    }

    // Si hay restos de un stream anterior, limpiar
    _firestoreStreams[cacheKey]?.cancel();
    _reservasStreams[cacheKey]?.cancel();
    _firestoreStreams.remove(cacheKey);
    _reservasStreams.remove(cacheKey);
    _streamControllers.remove(cacheKey);
    _ultimoPromocionesSnapshot.remove(cacheKey);
    _ultimoReservasSnapshot.remove(cacheKey);
    _lastEmittedByKey.remove(cacheKey);

    // Crear nuevo stream (broadcast para soportar múltiples listeners si pasa)
    final controller = StreamController<Map<String, Map<String, dynamic>>>.broadcast();
    _streamControllers[cacheKey] = controller;
    
    // Consulta base optimizada
    Query query = FirebaseFirestore.instance
        .collection('promociones')
        .where('lugarId', isEqualTo: lugarId)
        .where('cancha_id', isEqualTo: canchaId)
        .where('fecha', isEqualTo: fecha)
        .where('activo', isEqualTo: true);
    
    // Si se proporciona sedeId, intentar filtrar en la consulta
    // (solo si está estandarizado como ID en Firestore)
    if (sedeId != null && sedeId.isNotEmpty) {
      // Intentar filtrar por sede si es posible
      // Nota: Si sede puede ser ID o nombre, este filtro puede no funcionar
      // En ese caso, se filtra después en el cliente
    }
    
    // ✅ NUEVO: Consultar reservas para filtrar promociones
    final reservasQuery = FirebaseFirestore.instance
        .collection('reservas')
        .where('fecha', isEqualTo: fecha)
        .where('cancha_id', isEqualTo: canchaId)
        .limit(24);
    
    // Si se proporciona sedeId, filtrar por sede
    Query reservasQueryFinal = reservasQuery;
    if (sedeId != null && sedeId.isNotEmpty) {
      reservasQueryFinal = reservasQuery.where('sede', isEqualTo: sedeId);
    }
    
    // ✅ NUEVO: Escuchar cambios en reservas también
    final reservasSubscription = reservasQueryFinal.snapshots().listen(
      (reservasSnapshot) {
        // Procesar promociones cuando cambien las reservas
        _procesarPromocionesConReservas(
          querySnapshot: null, // Se usará el último snapshot de promociones
          reservasSnapshot: reservasSnapshot,
          controller: controller,
          cacheKey: cacheKey,
          sedeId: sedeId,
          sedeNombre: sedeNombre,
        );
      },
      onError: (error) {
        debugPrint('⚠️ Error en stream de reservas para promociones: $error');
        // Continuar sin filtrar por reservas si hay error
      },
    );
    
    _reservasStreams[cacheKey] = reservasSubscription;
    
    final firestoreSubscription = query.snapshots().listen(
      (querySnapshot) {
        // Obtener el último snapshot de reservas si existe
        _procesarPromocionesConReservas(
          querySnapshot: querySnapshot,
          reservasSnapshot: null, // Se obtendrá del stream de reservas
          controller: controller,
          cacheKey: cacheKey,
          sedeId: sedeId,
          sedeNombre: sedeNombre,
        );
      },
      onError: (error) {
        debugPrint('❌ Error en stream de promociones: $error');
        if (!controller.isClosed) controller.addError(error);
      },
    );
    
    // Guardar la suscripción de Firestore
    _firestoreStreams[cacheKey] = firestoreSubscription;
    
    // Emitir valor inicial desde caché si existe y no está expirado
    if (_promocionesCache.containsKey(cacheKey)) {
      final cacheTime = _cacheTimestamps[cacheKey];
      if (cacheTime != null && 
          DateTime.now().difference(cacheTime) < _cacheTTL) {
        controller.add(_promocionesCache[cacheKey]!);
      }
    }
    
    return controller.stream;
  }
  
  /// Obtener promociones desde caché (sin stream)
  /// Útil para consultas rápidas sin suscripción
  Map<String, Map<String, dynamic>>? getPromocionesFromCache({
    required String lugarId,
    required String canchaId,
    required String fecha,
  }) {
    final cacheKey = '${lugarId}_${canchaId}_$fecha';
    
    if (!_promocionesCache.containsKey(cacheKey)) {
      return null;
    }
    
    final cacheTime = _cacheTimestamps[cacheKey];
    if (cacheTime == null || 
        DateTime.now().difference(cacheTime) >= _cacheTTL) {
      // Caché expirado
      _promocionesCache.remove(cacheKey);
      _cacheTimestamps.remove(cacheKey);
      return null;
    }
    
    return _promocionesCache[cacheKey];
  }
  
  // ✅ NUEVO: Cache para los últimos snapshots
  final Map<String, QuerySnapshot> _ultimoPromocionesSnapshot = {};
  final Map<String, QuerySnapshot> _ultimoReservasSnapshot = {};
  
  // ✅ NUEVO: Procesar promociones filtrando por reservas
  void _procesarPromocionesConReservas({
    QuerySnapshot? querySnapshot,
    QuerySnapshot? reservasSnapshot,
    required StreamController<Map<String, Map<String, dynamic>>> controller,
    required String cacheKey,
    String? sedeId,
    String? sedeNombre,
  }) {
    // Guardar los últimos snapshots
    if (querySnapshot != null) {
      _ultimoPromocionesSnapshot[cacheKey] = querySnapshot;
    }
    if (reservasSnapshot != null) {
      _ultimoReservasSnapshot[cacheKey] = reservasSnapshot;
    }
    
    // Obtener los snapshots más recientes
    final promocionesSnap = _ultimoPromocionesSnapshot[cacheKey];
    final reservasSnap = _ultimoReservasSnapshot[cacheKey];
    
    if (promocionesSnap == null) {
      // Aún no hay promociones, esperar
      return;
    }
    
    // ✅ Construir mapa de reservas por horario normalizado
    final Map<String, bool> reservasConfirmadasPorHorario = {}; // horario -> confirmada
    final Map<String, bool> reservasPendientesPorHorario = {}; // horario -> pendiente
    
    if (reservasSnap != null) {
      for (var doc in reservasSnap.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          final estado = data['estado'] as String?;
          
          // ✅ EXCLUIR RESERVAS CON ESTADO "devolucion"
          if (estado == 'devolucion') {
            continue;
          }
          
          final horarioReserva = (data['horario'] as String? ?? '').trim();
          if (horarioReserva.isEmpty) continue;
          
          final horarioNormalizado = Horario.normalizarHora(horarioReserva);
          final confirmada = data['confirmada'] as bool? ?? false;
          
          if (confirmada) {
            reservasConfirmadasPorHorario[horarioNormalizado] = true;
          } else {
            reservasPendientesPorHorario[horarioNormalizado] = true;
          }
        } catch (e) {
          debugPrint('⚠️ Error procesando reserva para filtro de promociones: $e');
        }
      }
    }
    
    // ✅ Procesar promociones y filtrar según reservas
    final Map<String, Map<String, dynamic>> promocionesTemp = {};
    
    for (var doc in promocionesSnap.docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final horario = data['horario'] as String?;
        final promoSede = data['sede'] as String?;
        
        // Filtrar por sede si se proporcionó
        if (sedeId != null || sedeNombre != null) {
          bool sedeCoincide = false;
          if (promoSede != null) {
            if (sedeId != null && promoSede == sedeId) {
              sedeCoincide = true;
            } else if (sedeNombre != null && promoSede == sedeNombre) {
              sedeCoincide = true;
            }
          } else {
            // Si no tiene sede, asumir que coincide (por compatibilidad)
            sedeCoincide = true;
          }
          
          if (!sedeCoincide) {
            continue;
          }
        }
        
        if (horario == null || horario.isEmpty) {
          continue;
        }
        
        // ✅ Normalizar horario para comparación
        final horarioNormalizado = Horario.normalizarHora(horario);
        
        // Si hay reserva confirmada, solo ocultar (la desactivación se hace en reserva_screen)
        if (reservasConfirmadasPorHorario.containsKey(horarioNormalizado)) {
          continue;
        }
        
        // ✅ FILTRAR: Si hay reserva pendiente, ocultar temporalmente
        if (reservasPendientesPorHorario.containsKey(horarioNormalizado)) {
          continue; // Ocultar promoción con reserva pendiente
        }
        
        final precioPromocional = (data['precio_promocional'] as num?)?.toDouble();
        
        if (precioPromocional != null && precioPromocional > 0) {
          // Guardar solo con la clave normalizada
          promocionesTemp[horarioNormalizado] = {
            'id': doc.id,
            'precio_promocional': precioPromocional,
            'nota': data['nota'] as String?,
            'horario': horario,
            'sede': promoSede,
          };
        }
      } catch (e) {
        debugPrint('❌ Error procesando promoción ${doc.id}: $e');
      }
    }
    
    // Actualizar caché
    _promocionesCache[cacheKey] = promocionesTemp;
    _cacheTimestamps[cacheKey] = DateTime.now();
    _lastEmittedByKey[cacheKey] = promocionesTemp;

    // Emitir actualización (solo si el controller sigue abierto)
    if (!controller.isClosed) {
      controller.add(promocionesTemp);
    }
  }
  
  /// Cancelar stream específico
  void cancelStream(String lugarId, String canchaId, String fecha) {
    final cacheKey = '${lugarId}_${canchaId}_$fecha';
    _firestoreStreams[cacheKey]?.cancel();
    _reservasStreams[cacheKey]?.cancel(); // ✅ NUEVO
    _streamControllers[cacheKey]?.close();
    _firestoreStreams.remove(cacheKey);
    _reservasStreams.remove(cacheKey); // ✅ NUEVO
    _streamControllers.remove(cacheKey);
    _ultimoPromocionesSnapshot.remove(cacheKey); // ✅ NUEVO
    _ultimoReservasSnapshot.remove(cacheKey); // ✅ NUEVO
    _lastEmittedByKey.remove(cacheKey);
  }
  
  /// Limpiar caché expirado
  void _cleanExpiredCache() {
    final now = DateTime.now();
    final keysToRemove = <String>[];
    
    _cacheTimestamps.forEach((key, timestamp) {
      if (now.difference(timestamp) >= _cacheTTL) {
        keysToRemove.add(key);
      }
    });
    
    for (final key in keysToRemove) {
      _promocionesCache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }
  
  /// Limpiar todos los streams y caché
  @override
  void dispose() {
    for (final subscription in _firestoreStreams.values) {
      subscription.cancel();
    }
    for (final subscription in _reservasStreams.values) { // ✅ NUEVO
      subscription.cancel();
    }
    for (final controller in _streamControllers.values) {
      controller.close();
    }
    _firestoreStreams.clear();
    _reservasStreams.clear(); // ✅ NUEVO
    _streamControllers.clear();
    _promocionesCache.clear();
    _cacheTimestamps.clear();
    _ultimoPromocionesSnapshot.clear(); // ✅ NUEVO
    _ultimoReservasSnapshot.clear(); // ✅ NUEVO
    _lastEmittedByKey.clear();
    super.dispose();
  }
  
  @override
  void notifyListeners() {
    _cleanExpiredCache();
    super.notifyListeners();
  }
}

