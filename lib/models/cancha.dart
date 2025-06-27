import 'package:cloud_firestore/cloud_firestore.dart';

class Cancha {
  final String id;
  final String nombre;
  final String descripcion;
  final String imagen;
  final bool techada;
  final String ubicacion; // Mantenemos ubicacion en la cancha
  final double precio;
  final String sedeId; // Cambiado de 'sede' a 'sedeId' para consistencia
  final Map<String, Map<String, double>> preciosPorHorario;
  final bool disponible;
  final String? motivoNoDisponible;

  Cancha({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.imagen,
    required this.techada,
    required this.ubicacion, // Mantenemos ubicacion
    required this.precio,
    required this.sedeId, // Cambiado
    this.preciosPorHorario = const {},
    this.disponible = true,
    this.motivoNoDisponible,
  });

  // Crear Cancha desde un documento de Firestore
  factory Cancha.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Optimizar conversión de preciosPorHorario usando map en lugar de forEach
    final preciosPorHorario = <String, Map<String, double>>{};
    if (data.containsKey('preciosPorHorario')) {
      final preciosRaw =
          Map<String, dynamic>.from(data['preciosPorHorario'] as Map);
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
      imagen: data['imagen'] as String? ?? 'assets/cancha_demo.png',
      techada: data['techada'] as bool? ?? false,
      ubicacion: data['ubicacion'] as String? ?? '', // Agregamos ubicacion
      precio:
          (data['precio'] is num) ? (data['precio'] as num).toDouble() : 0.0,
      sedeId: data['sedeId'] as String? ?? '', // Consistente con Firebase
      preciosPorHorario: preciosPorHorario,
      disponible: data['disponible'] as bool? ?? true,
      motivoNoDisponible: data['motivoNoDisponible'] as String?,
    );
  }

  // Convertir a Map para guardar en Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'nombre': nombre,
      'descripcion': descripcion,
      'imagen': imagen,
      'techada': techada,
      'ubicacion': ubicacion, // Agregamos ubicacion
      'precio': precio,
      'sedeId': sedeId, // Cambiado de 'sede' a 'sedeId'
      'preciosPorHorario': preciosPorHorario,
      'disponible': disponible,
      'motivoNoDisponible': motivoNoDisponible,
    };
  }

  // Método para comparar con datos existentes y evitar escrituras redundantes
  bool hasChanges(Cancha other) {
    // Comparar campos escalares
    if (nombre != other.nombre ||
        descripcion != other.descripcion ||
        imagen != other.imagen ||
        techada != other.techada ||
        ubicacion != other.ubicacion || // Agregamos ubicacion
        precio != other.precio ||
        sedeId != other.sedeId || // Cambiado
        disponible != other.disponible ||
        motivoNoDisponible != other.motivoNoDisponible) {
      return true;
    }

    // Comparar preciosPorHorario
    if (preciosPorHorario.length != other.preciosPorHorario.length) {
      return true;
    }
    for (final day in preciosPorHorario.keys) {
      if (!other.preciosPorHorario.containsKey(day)) {
        return true;
      }
      final horarios = preciosPorHorario[day]!;
      final otherHorarios = other.preciosPorHorario[day]!;
      if (horarios.length != otherHorarios.length) {
        return true;
      }
      for (final hora in horarios.keys) {
        if (!otherHorarios.containsKey(hora) ||
            horarios[hora] != otherHorarios[hora]) {
          return true;
        }
      }
    }

    return false;
  }

  // Método auxiliar para obtener información de la sede (si necesitas datos adicionales de la sede)
  static Future<Map<String, dynamic>?> getSedeInfo(String sedeId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('sedes')
          .doc(sedeId)
          .get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      return null;
    }
  }
}