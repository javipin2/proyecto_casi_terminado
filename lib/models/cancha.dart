import 'package:cloud_firestore/cloud_firestore.dart';

class Cancha {
  final String id;
  final String nombre;
  final String descripcion;
  final String imagen;
  final bool techada;
  final String ubicacion;
  final double precio;
  final String sede;
  final Map<String, Map<String, double>> preciosPorHorario;
  final bool disponible; // Nuevo campo para disponibilidad
  final String? motivoNoDisponible; // Nuevo campo para motivo

  Cancha({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.imagen,
    required this.techada,
    required this.ubicacion,
    required this.precio,
    required this.sede,
    this.preciosPorHorario = const {},
    this.disponible = true, // Por defecto, la cancha está disponible
    this.motivoNoDisponible, // Puede ser null si está disponible
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
      ubicacion: data['ubicacion'] as String? ?? '',
      precio:
          (data['precio'] is num) ? (data['precio'] as num).toDouble() : 0.0,
      sede: data['sede'] as String? ?? '',
      preciosPorHorario: preciosPorHorario,
      disponible: data['disponible'] as bool? ?? true, // Nuevo campo
      motivoNoDisponible: data['motivoNoDisponible'] as String?, // Nuevo campo
    );
  }

  // Convertir a Map para guardar en Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'nombre': nombre,
      'descripcion': descripcion,
      'imagen': imagen,
      'techada': techada,
      'ubicacion': ubicacion,
      'precio': precio,
      'sede': sede,
      'preciosPorHorario': preciosPorHorario,
      'disponible': disponible, // Nuevo campo
      'motivoNoDisponible': motivoNoDisponible, // Nuevo campo
    };
  }

  // Método para comparar con datos existentes y evitar escrituras redundantes
  bool hasChanges(Cancha other) {
    // Comparar campos escalares
    if (nombre != other.nombre ||
        descripcion != other.descripcion ||
        imagen != other.imagen ||
        techada != other.techada ||
        ubicacion != other.ubicacion ||
        precio != other.precio ||
        sede != other.sede ||
        disponible != other.disponible || // Nuevo campo
        motivoNoDisponible != other.motivoNoDisponible) {
      // Nuevo campo
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
}
