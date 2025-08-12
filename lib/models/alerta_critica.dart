// lib/models/alerta_critica.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum TipoAlerta {
  precio_anomalo,
  reserva_sospechosa,
  eliminacion_masiva,
  acceso_no_autorizado,
  cambio_critico,
  actividad_inusual
}

enum NivelRiesgo {
  bajo,     // Verde
  medio,    // Amarillo
  alto,     // Naranja
  critico   // Rojo
}

class AlertaCritica {
  final String id;
  final TipoAlerta tipo;
  final NivelRiesgo nivelRiesgo;
  final String titulo;
  final String descripcion;
  final String usuarioId;
  final String usuarioNombre;
  final String? entidadAfectada;
  final Map<String, dynamic> detalles;
  final DateTime timestamp;
  final bool leida;
  final String? accionRecomendada;

  AlertaCritica({
    required this.id,
    required this.tipo,
    required this.nivelRiesgo,
    required this.titulo,
    required this.descripcion,
    required this.usuarioId,
    required this.usuarioNombre,
    this.entidadAfectada,
    this.detalles = const {},
    required this.timestamp,
    this.leida = false,
    this.accionRecomendada,
  });

  factory AlertaCritica.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return AlertaCritica(
      id: doc.id,
      tipo: TipoAlerta.values.firstWhere(
        (e) => e.name == data['tipo'],
        orElse: () => TipoAlerta.actividad_inusual,
      ),
      nivelRiesgo: NivelRiesgo.values.firstWhere(
        (e) => e.name == data['nivelRiesgo'],
        orElse: () => NivelRiesgo.medio,
      ),
      titulo: data['titulo'] ?? '',
      descripcion: data['descripcion'] ?? '',
      usuarioId: data['usuarioId'] ?? '',
      usuarioNombre: data['usuarioNombre'] ?? 'Usuario desconocido',
      entidadAfectada: data['entidadAfectada'],
      detalles: Map<String, dynamic>.from(data['detalles'] ?? {}),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      leida: data['leida'] ?? false,
      accionRecomendada: data['accionRecomendada'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'tipo': tipo.name,
      'nivelRiesgo': nivelRiesgo.name,
      'titulo': titulo,
      'descripcion': descripcion,
      'usuarioId': usuarioId,
      'usuarioNombre': usuarioNombre,
      'entidadAfectada': entidadAfectada,
      'detalles': detalles,
      'timestamp': Timestamp.fromDate(timestamp),
      'leida': leida,
      'accionRecomendada': accionRecomendada,
    };
  }
}